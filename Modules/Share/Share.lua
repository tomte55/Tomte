local addonName, ns = ...

-- Friend sharing module: pools data with Battle.net friends who run Tomte, over hidden Battle.net game data
-- (C_BattleNet.SendGameData, received on BN_CHAT_MSG_ADDON). Friends are trusted: what they send fills gaps in your
-- data and is passed on to your other friends. Data sets plug in with ns.Share_Register (Flight Timer's flight
-- times are the first, Modules/Flight/ShareData.lua). Wire format in Protocol.lua, who's reachable in Roster.lua,
-- the Friends page in Page.lua. Spec: docs/superpowers/specs/2026-10-13-tomte-friend-sharing-design.md.

local PREFIX = "Tomte"
local OWNER = "share"
local GAP = 1 -- seconds between sent messages (traffic fairness, see Protocol.lua)
local THROTTLED = 2 -- seconds to wait after a throttle answer
local LOCKDOWN = 10 -- seconds to wait while addon messages are locked down (encounters, some instances)
local START_DELAY = 5 -- seconds after the module starts before the first hello: the friend list fills in after login
local ONLINE_DELAY = 2 -- seconds: a friend's game info fills in just after BN_FRIEND_ACCOUNT_ONLINE (Friends Online)
local CHANGED_DELAY = 10 -- seconds: several changes in a row send one hello
local REPLY_WINDOW = 60 -- seconds: a hello is answered with ours unless we sent them one this recently (no ping-pong)
local LOG_SIZE = 20 -- lines kept per friend for /tomte share why
local RELEASES = "https://github.com/tomte55/Tomte/releases/latest"
local ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
local EVENTS = { "BN_CHAT_MSG_ADDON", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED",
	"PLAYER_REGEN_ENABLED" }

local SAMPLE_FRIEND = "Kesha" -- the settings preview's made-up friend
local SAMPLE_ADDED = 12 -- and how many new entries she sent

local UI = ns.UI

local module, db
local sets, setOrder = {}, {} -- [key] = set, keys in registration order
local queue = {} -- { to = gameAccountID, text, done = sending key when it's a transfer's last message }
local sending = {} -- [gameAccountID .. ":" .. set] = true while a transfer is queued
local inbox = {} -- Protocol.lua's reassembly
local helloAt = {} -- [gameAccountID] = GetTime() of the last hello we sent them
local log = {} -- [BattleTag] = { lines }
local pumpTimer, startTimer, changedTimer
local events = CreateFrame("Frame")

local function ShortName(tag)
	return tag:match("^[^#]+") or tag
end

local function Log(tag, text)
	local lines = log[tag] or {}
	log[tag] = lines
	lines[#lines + 1] = date("%H:%M:%S ") .. text
	if #lines > LOG_SIZE then
		table.remove(lines, 1)
	end
end

local function RefreshPage()
	if ns.SharePage_Refresh then
		ns.SharePage_Refresh()
	end
end

-- Sending ----------------------------------------------------------------------------------------------------------

local function DropQueued(to)
	for i = #queue, 1, -1 do
		if queue[i].to == to then
			table.remove(queue, i)
		end
	end
	for id in pairs(sending) do
		if id:match("^(%d+):") == tostring(to) then
			sending[id] = nil
		end
	end
end

local Pump

local function SchedulePump(wait)
	if not pumpTimer and #queue > 0 and not InCombatLockdown() then
		pumpTimer = C_Timer.NewTimer(wait, Pump)
	end
end

-- Sends the next queued message. Nothing goes out in combat: PLAYER_REGEN_ENABLED starts the pump again.
function Pump()
	pumpTimer = nil
	if InCombatLockdown() then
		return
	end
	local item = table.remove(queue, 1)
	if not item then
		return
	end
	local R = Enum.SendAddonMessageResult
	local result = C_BattleNet.SendGameData(item.to, PREFIX, item.text)
	local wait = GAP
	if result == R.AddonMessageThrottle or result == R.ChannelThrottle then
		table.insert(queue, 1, item)
		wait = THROTTLED
	elseif result == R.AddOnMessageLockdown then
		table.insert(queue, 1, item)
		wait = LOCKDOWN
	elseif result == R.TargetOffline then
		DropQueued(item.to)
		local friend = item.tag
		if friend then
			Log(friend, "they went offline, dropped what was queued")
		end
	else
		if result ~= nil and result ~= R.Success and item.tag then
			Log(item.tag, "send failed (code " .. tostring(result) .. ")")
		end
		if item.done then
			sending[item.done] = nil
		end
	end
	SchedulePump(wait)
end

local function Queue(to, tag, text, done)
	queue[#queue + 1] = { to = to, tag = tag, text = text, done = done }
	SchedulePump(0)
end

local function Friend(tag)
	local row = db.friends[tag]
	if not row then
		row = { blocked = false, sets = {} }
		db.friends[tag] = row
	end
	row.sets = row.sets or {}
	return row
end

local function Blocked(tag)
	local row = db.friends[tag]
	return row and row.blocked
end

-- A set is shared (offered, sent and accepted) when it's switched on here and its own module allows it (Gathering
-- off: no node spots).
local function Shared(key)
	local set = sets[key]
	return set ~= nil and db.sets[key] == true and (not set.active or set.active() == true)
end

local function SharedSets()
	local list = {}
	for _, key in ipairs(setOrder) do
		if Shared(key) then
			list[#list + 1] = { key, sets[key].revision() }
		end
	end
	return list
end

local function SendHello(id, friend)
	helloAt[id] = GetTime()
	local version = ns.VERSION:gsub("[^%w%.%-]", "")
	Queue(id, friend.tag, ns.Share_BuildHello(version ~= "" and version or "0", SharedSets()))
	Log(friend.tag, "sent hello")
end

-- Hello to every reachable friend that isn't blocked; onlyNew: only those we haven't greeted this session.
local function HelloAll(onlyNew)
	local n = 0
	for _, id in ipairs(ns.Share_RosterIDs()) do
		local friend = ns.Share_RosterGet(id)
		if friend and not Blocked(friend.tag) and not (onlyNew and helloAt[id]) then
			SendHello(id, friend)
			n = n + 1
		end
	end
	return n
end

-- Receiving --------------------------------------------------------------------------------------------------------

function ns.Share_ShowDownload()
	ns.Dialog_Show({
		title = "Get the newest Tomte",
		hint = "Ctrl+C to copy the link and open it in your browser. Download the zip, put its Tomte folder over the one in Interface\\AddOns and restart the game.",
		text = RELEASES,
		readOnly = true,
	})
end

-- A friend runs a newer Tomte: told once per version (a toast and a chat line); the page shows it until you update.
local function NoticeVersion(friend, version)
	if not (ns.Share_NewerVersion(version, ns.VERSION) and ns.Share_NewerVersion(version, db.toldVersion)) then
		return
	end
	db.toldVersion = version
	local text = ("%s runs Tomte %s, you have %s."):format(ShortName(friend.tag), version, ns.VERSION)
	ns.Print(text .. " Get it: " .. RELEASES)
	ns.Toast_Show({ owner = OWNER, label = "Tomte update", accent = { UI.Color("accent") }, icon = ICON,
		title = "A newer Tomte is out", text = text .. " Click for the download link.", hold = 12,
		onClick = ns.Share_ShowDownload })
end

local function OnHello(id, friend, row, msg)
	row.version = msg.version
	Log(friend.tag, "hello, Tomte " .. msg.version)
	NoticeVersion(friend, msg.version)
	for key, rev in pairs(msg.sets) do
		local set = sets[key]
		local got = row.sets[key]
		if Shared(key) and rev ~= set.revision() then
			if got and got.rev == rev then
				-- Imported before: what still differs merged into our own spots, or is what we reset or forgot.
				Log(friend.tag, key .. ": already have everything from this revision")
			else
				Queue(id, friend.tag, ns.Share_BuildRequest(key))
				Log(friend.tag, "asked for " .. key .. " (they have something we don't)")
			end
		end
	end
	if GetTime() - (helloAt[id] or -REPLY_WINDOW) >= REPLY_WINDOW then
		SendHello(id, friend)
	end
end

local function OnRequest(id, friend, msg)
	local set = sets[msg.set]
	if not Shared(msg.set) then
		Log(friend.tag, "asked for " .. msg.set .. ", not shared")
		return
	end
	local busy = id .. ":" .. msg.set
	if sending[busy] then
		return
	end
	sending[busy] = true
	local list = ns.Share_BuildData(msg.set, set.revision(), set.export())
	for i, text in ipairs(list) do
		Queue(id, friend.tag, text, i == #list and busy or nil)
	end
	Log(friend.tag, ("sending %s (%d %s)"):format(msg.set, #list, #list == 1 and "message" or "messages"))
end

-- The toast for something new from a friend. sample: a settings preview (kept out of Recent).
local function ReceivedSpec(name, text, sample)
	return { owner = OWNER, label = "Friend sharing", accent = { UI.Color("accent") }, icon = ICON,
		title = name, text = text, hold = 8, test = sample or nil }
end

-- Settings preview (Panel/Preview.lua): a made-up friend's flight times, worded by the first shared set's own count.
local function ReceivedPreview(host)
	local set = sets[setOrder[1]]
	local text = set and set.count(SAMPLE_ADDED, "new") or (SAMPLE_ADDED .. " new")
	return ns.Toast_DrawSample(host, ReceivedSpec(SAMPLE_FRIEND, text, true), 1)
end

local function OnData(id, friend, row, msg)
	local set = sets[msg.set]
	if not Shared(msg.set) then
		return
	end
	local payload = ns.Share_Receive(inbox, id, msg, GetTime())
	if not payload then
		return
	end
	local added, reason = set.import(payload)
	if not added then
		Log(friend.tag, msg.set .. " rejected: " .. reason)
		return
	end
	local got = row.sets[msg.set] or {}
	row.sets[msg.set] = got
	got.at, got.added, got.rev = time(), (got.added or 0) + added, msg.rev
	Log(friend.tag, ("%s received, %d new"):format(msg.set, added))
	if added > 0 then
		if db.toast then
			ns.Toast_Show(ReceivedSpec(ShortName(friend.tag), set.count(added, "new")))
		end
		ns.Share_Changed(msg.set)
	end
end

function events:BN_CHAT_MSG_ADDON(prefix, text, _, senderID)
	if prefix ~= PREFIX then
		return
	end
	local friend = ns.Share_RosterGet(senderID)
	if not friend then
		ns.Share_RosterDirty() -- a friend who just logged in may not be in the last build yet
		friend = ns.Share_RosterGet(senderID)
		if not friend then
			return
		end
	end
	local msg, reason = ns.Share_Parse(text)
	if not msg then
		Log(friend.tag, "ignored a message: " .. reason)
		return
	end
	if Blocked(friend.tag) then
		Log(friend.tag, "ignored, blocked")
		return
	end
	local row = Friend(friend.tag)
	row.character, row.seen = friend.character, time()
	if msg.type == "H" then
		OnHello(senderID, friend, row, msg)
	elseif msg.type == "R" then
		OnRequest(senderID, friend, msg)
	else
		OnData(senderID, friend, row, msg)
	end
	ns.Share_Prune(inbox, GetTime())
	RefreshPage()
end

function events:BN_FRIEND_ACCOUNT_ONLINE()
	ns.Share_RosterDirty()
	C_Timer.After(ONLINE_DELAY, function()
		if module.active then
			ns.Share_RosterDirty()
			HelloAll(true)
		end
	end)
end

function events:BN_FRIEND_ACCOUNT_OFFLINE()
	ns.Share_RosterDirty()
end

function events:BN_FRIEND_INFO_CHANGED()
	ns.Share_RosterDirty()
end

function events:PLAYER_REGEN_ENABLED()
	SchedulePump(GAP)
end

events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

-- Start and stop ---------------------------------------------------------------------------------------------------

local function Start()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	ns.Share_RosterDirty()
	startTimer = C_Timer.NewTimer(START_DELAY, function()
		startTimer = nil
		HelloAll()
	end)
end

local function Stop()
	events:UnregisterAllEvents()
	for _, timer in pairs({ pumpTimer, startTimer, changedTimer }) do
		timer:Cancel()
	end
	pumpTimer, startTimer, changedTimer = nil, nil, nil
	wipe(queue)
	wipe(sending)
	wipe(inbox)
	wipe(helloAt)
end

-- For data sets and the page ---------------------------------------------------------------------------------------

-- set = { key, label, count(n, adjective) -> "34 new flight times", export() -> payload, revision() -> number,
-- import(payload) -> added | nil, reason }. Called from the owning module's init (all files are loaded by then).
function ns.Share_Register(set)
	if not sets[set.key] then
		setOrder[#setOrder + 1] = set.key
	end
	sets[set.key] = set
end

-- The owning module's data changed: tell everyone (debounced). Does nothing while Friend sharing is off.
function ns.Share_Changed(key)
	-- Not Shared(key): a set just switched off still sends a hello, so friends learn it's no longer offered.
	if not (module and module.active and sets[key]) then
		return
	end
	if changedTimer then
		changedTimer:Cancel()
	end
	changedTimer = C_Timer.NewTimer(CHANGED_DELAY, function()
		changedTimer = nil
		HelloAll()
	end)
end

-- Friends seen running Tomte, by name: { tag, name, character, version, seen, blocked, gave = { "34 flight times" } }.
function ns.Share_Friends()
	local list = {}
	for tag, row in pairs(db.friends) do
		local gave = {}
		for _, key in ipairs(setOrder) do
			local got = row.sets and row.sets[key]
			if got and (got.added or 0) > 0 then
				gave[#gave + 1] = sets[key].count(got.added)
			end
		end
		list[#list + 1] = { tag = tag, name = ShortName(tag), character = row.character, version = row.version,
			seen = row.seen, blocked = row.blocked, gave = gave }
	end
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return list
end

-- The newest Tomte a friend runs when it's newer than ours: version, the friend's short name. Nil otherwise.
function ns.Share_NewestFriendVersion()
	if not (module and module.active) then
		return nil
	end
	local best, who = ns.VERSION, nil
	for tag, row in pairs(db.friends) do
		if not row.blocked and ns.Share_NewerVersion(row.version, best) then
			best, who = row.version, ShortName(tag)
		end
	end
	if who then
		return best, who
	end
	return nil
end

function ns.Share_SetBlocked(tag, on)
	Friend(tag).blocked = on and true or false
	if on then
		for _, id in ipairs(ns.Share_RosterIDs()) do
			local friend = ns.Share_RosterGet(id)
			if friend and friend.tag == tag then
				DropQueued(id)
			end
		end
	end
end

function ns.Share_Forget(tag)
	db.friends[tag] = nil
	log[tag] = nil
	RefreshPage()
end

local function Sync()
	if not ns.Module_RequireOn(module) then
		return
	end
	local n = HelloAll()
	ns.Print(n == 1 and "said hello to 1 friend in WoW." or ("said hello to " .. n .. " friends in WoW."))
end

-- Commands ---------------------------------------------------------------------------------------------------------

local function List()
	local list = ns.Share_Friends()
	if #list == 0 then
		ns.Print("no friends seen running Tomte with Friend sharing on yet.")
		return
	end
	for _, f in ipairs(list) do
		local parts = { f.character or "?", "Tomte " .. (f.version or "?") }
		if f.seen then
			parts[#parts + 1] = "seen " .. ns.Ago(time() - f.seen) .. " ago"
		end
		if #f.gave > 0 then
			parts[#parts + 1] = "gave you " .. table.concat(f.gave, ", ")
		end
		if f.blocked then
			parts[#parts + 1] = "blocked"
		end
		ns.Print(f.tag .. ": " .. table.concat(parts, " - "))
	end
end

local function Why(_, rawArg)
	local name = (rawArg or ""):lower()
	if name == "" then
		ns.Print("usage: /tomte share why <name>")
		return
	end
	for tag, lines in pairs(log) do
		if tag:lower():sub(1, #name) == name then
			ns.Print(tag .. ", this session:")
			for _, line in ipairs(lines) do
				print("  " .. line)
			end
			return
		end
	end
	ns.Print("nothing exchanged with " .. rawArg .. " this session.")
end

module = ns.RegisterModule({
	key = "share",
	name = "Friend sharing",
	category = "social",
	icon = 442272, -- achievement_guildperk_everybodysfriend
	summary = "Swap flight times and gathering spots with friends who run Tomte.",
	description = "Shares data with your Battle.net friends who run Tomte, in the background: flight times you've recorded (and those friends sent you) fill in each other's flight timers and coverage maps, and gathering node spots fill in each other's world maps. Also tells you when a friend runs a newer Tomte.",
	enabledByDefault = false,
	toasts = true,
	defaults = {
		sets = { flight = true, nodes = true }, -- [data set key] = shared (sent and accepted)
		toast = false,
		toldVersion = "", -- the newest Tomte version a friend's hello told us about (each version is told once)
		-- [BattleTag] = { blocked, character, version, seen, sets = { [key] = { at, added, rev } } }; rev is the
		-- friend's revision we last imported (not asked for again).
		friends = {},
	},
	noShare = { "friends" }, -- BattleTags: not in settings strings (Core/Profile.lua)
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "list", "friends seen running Tomte and what they gave you", List },
		{ "sync", "say hello to every friend now (they send what's new)", Sync },
		{ "why", "<name>: what was exchanged with that friend this session", Why },
	},
	home = {
		{ kind = "page", key = "share", order = 90, name = "Friend sharing", icon = ICON, page = ns.SharePage,
			summary = function()
				local n = #ns.Share_Friends()
				return n == 1 and "1 friend shares with you" or (n .. " friends share with you")
			end },
	},
	options = {
		{ type = "header", label = "What to share" },
		{ type = "checkbox", key = "sets.flight", label = "Flight times",
			onChange = function()
				ns.Share_Changed("flight")
			end,
			tooltip = "Send the flight times you know to your Battle.net friends and add theirs to yours. Your own times always win: flying a route records over a friend's time." },
		{ type = "checkbox", key = "sets.nodes", label = "Gathering nodes",
			onChange = function()
				ns.Share_Changed("nodes")
			end,
			tooltip = "Send the mining and herbalism spots Gathering remembers to your friends and add theirs to your world map. A friend's spot right next to one of yours is the same node and isn't added twice." },
		{ type = "header", label = "Friends" },
		{ type = "checkbox", key = "toast", label = "Toast when friends send something new",
			preview = ns.Preview_When("toast", ReceivedPreview) },
		{ type = "button", label = "Sync with friends", text = "Sync", onClick = Sync,
			tooltip = "Say hello to every friend in WoW now. They send anything you don't have yet." },
	},
})
