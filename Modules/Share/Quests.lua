local addonName, ns = ...

-- Friend sharing, quest progress (World of Warcraft: Forever only; tools/forever_list.lua): swaps quest progress with
-- party members who run Tomte over hidden addon messages, whichever quest tracker they use. Your log goes out as a full
-- state when someone joins (or asks with a hello) and as changes after that; theirs is kept per member for the Quest
-- list to show (ns.ShareQuests_Member, drawn by Modules/QuestList/Party.lua). Party messages, not Battle.net ones like
-- the rest of Friend sharing: anyone in your party counts. Runs while Friend sharing is on with its "Quest progress"
-- setting (ns.ShareQuests_Apply from Share.lua). Message format in QuestsData.lua.
-- See docs/superpowers/specs/2026-11-14-tomte-quest-list-party-design.md.

local PREFIX = "TomteQuests" -- addon message prefix (16 characters at most)
local SEND_GAP = 0.2 -- seconds between messages
local THROTTLED = 2 -- seconds to wait after the game throttled a message
local LOCKDOWN = 10 -- seconds to wait while addon messages are locked down
local LOG_DELAY = 1 -- seconds: the quest log changes in bursts, one send per burst
local FULL_GAP = 10 -- seconds: our full state goes out at most this often (hellos from several new members share one)
local HELLO_GAP = 10 -- seconds between our own hellos

local IsSecret = ns.IsSecret

local active = false
local roster = {} -- party members in party order: { guid, name }
-- [guid] = { quests = { [questID] = { complete, objectives = { [k] = { have, need, finished } } } },
-- turnedIn = { [questID] = true } }: only members whose Tomte has sent us something
local members = {}
local listeners = {} -- functions called when what we know about the party's quests changed
local sent = {} -- [questID] = the entry last sent to the party
local turnedIn = {} -- [questID] = true: handed in since the last send
local queue = {} -- messages waiting to go
local pumping = false
local fullAt, helloAt = -math.huge, -math.huge
local logTimer, fullTimer

-- The addon channel for your group, nil outside one.
local function Channel()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
		and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	end
	return IsInGroup() and "PARTY" or nil
end

local function Changed()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- Party members (your subgroup in a raid) we can tell apart: a secret GUID or name leaves that member out.
local function ReadRoster()
	local list = {}
	for i = 1, GetNumSubgroupMembers() do
		local unit = "party" .. i
		local guid, name = UnitGUID(unit), UnitName(unit)
		if guid and name and not IsSecret(guid, name) then
			list[#list + 1] = { guid = guid, name = name }
		end
	end
	return list
end

-- Your quests as entries, { [questID] = entry }.
local function MyEntries()
	local out = {}
	for _, q in ipairs(ns.LevelingRead_Quests()) do
		out[q.questID] = ns.ShareQuests_Entry({ questID = q.questID, complete = q.complete,
			objectives = ns.QuestListRead_Objectives(q.questID) })
	end
	return out
end

-- Sending ------------------------------------------------------------------------------------------------------------

local function Pump()
	local text = table.remove(queue, 1)
	local channel = Channel()
	if not text or not channel or not active then
		wipe(queue)
		pumping = false
		return
	end
	local result = C_ChatInfo.SendAddonMessage(PREFIX, text, channel)
	local wait = SEND_GAP
	local R = Enum.SendAddonMessageResult
	if R and (result == R.AddonMessageThrottle or result == R.ChannelThrottle) then
		table.insert(queue, 1, text)
		wait = THROTTLED
	elseif R and result == R.AddOnMessageLockdown then
		table.insert(queue, 1, text)
		wait = LOCKDOWN
	end
	C_Timer.After(wait, Pump)
end

local function Send(messages)
	for _, m in ipairs(messages) do
		queue[#queue + 1] = m
	end
	if not pumping and #queue > 0 then
		pumping = true
		Pump()
	end
end

-- Every quest in your log, as a full state.
local function SendFull()
	fullTimer = nil
	if not (active and Channel()) then
		return
	end
	local mine = MyEntries()
	local ids, entries = {}, {}
	for id in pairs(mine) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for i, id in ipairs(ids) do
		entries[i] = mine[id]
	end
	sent = mine
	wipe(turnedIn)
	fullAt = GetTime()
	Send(ns.ShareQuests_Pack("S", entries))
end

-- A full state soon: right away unless one just went out, then once that gap is over.
local function FullSoon()
	if fullTimer then
		return
	end
	fullTimer = C_Timer.NewTimer(math.max(SEND_GAP, fullAt + FULL_GAP - GetTime()), SendFull)
end

-- Someone new in the party: ask everyone for theirs, and send ours.
local function Greet()
	if not Channel() then
		return
	end
	if GetTime() - helloAt >= HELLO_GAP then
		helloAt = GetTime()
		Send({ ns.ShareQuests_Hello() })
	end
	FullSoon()
end

-- After the log changed: the quests that changed, those gone, those turned in.
local function LogSettled()
	logTimer = nil
	if not (active and Channel()) then
		wipe(turnedIn)
		return
	end
	local now = MyEntries()
	local changed, gone, turned = ns.ShareQuests_Diff(sent, now, turnedIn)
	sent = now
	wipe(turnedIn)
	if #changed > 0 then
		Send(ns.ShareQuests_Pack("Q", changed))
	end
	if #gone > 0 then
		Send(ns.ShareQuests_PackIDs("G", gone))
	end
	if #turned > 0 then
		Send(ns.ShareQuests_PackIDs("T", turned))
	end
end

local function LogChanged()
	if not logTimer then
		logTimer = C_Timer.NewTimer(LOG_DELAY, LogSettled)
	end
end

-- Receiving ----------------------------------------------------------------------------------------------------------

-- A party member's GUID by the sender of an addon message ("Name-Realm"). Names in a party are told apart without the
-- realm.
local function FromSender(sender)
	local short = Ambiguate(sender, "short")
	for _, r in ipairs(roster) do
		if r.name == short then
			return r.guid
		end
	end
	return nil
end

local function Received(text, sender)
	local guid = FromSender(sender)
	local msg = guid and ns.ShareQuests_Decode(text)
	if not msg then
		return
	end
	if msg.kind == "hello" then
		FullSoon()
		return
	end
	local m = members[guid]
	if not m then
		m = { quests = {}, turnedIn = {} }
		members[guid] = m
	end
	if msg.kind == "full" then
		wipe(m.quests)
		wipe(m.turnedIn)
	end
	if msg.kind == "full" or msg.kind == "update" then
		for _, q in ipairs(msg.quests) do
			m.quests[q.questID] = { complete = q.complete, objectives = q.objectives }
			m.turnedIn[q.questID] = nil
		end
	else
		for _, id in ipairs(msg.ids) do
			m.quests[id] = nil
			m.turnedIn[id] = msg.kind == "turnedIn" or nil
		end
	end
	Changed()
end

-- Events -------------------------------------------------------------------------------------------------------------

local function UpdateRoster()
	local old = {}
	for _, r in ipairs(roster) do
		old[r.guid] = true
	end
	roster = ReadRoster()
	local now, fresh = {}, false
	for _, r in ipairs(roster) do
		now[r.guid] = true
		fresh = fresh or not old[r.guid]
	end
	local left = false
	for guid in pairs(members) do
		if not now[guid] then
			members[guid] = nil
			left = true
		end
	end
	if #roster == 0 then
		wipe(sent) -- the next party gets a full state anyway
	end
	if fresh then
		Greet()
	end
	if left then
		Changed()
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

function events:GROUP_ROSTER_UPDATE()
	UpdateRoster()
end

function events:CHAT_MSG_ADDON(prefix, text, _, sender)
	if prefix == PREFIX and not IsSecret(text, sender) then
		Received(text, sender)
	end
end

function events:QUEST_LOG_UPDATE()
	LogChanged()
end

function events:QUEST_TURNED_IN(questID)
	turnedIn[questID] = true
	LogChanged()
end

local EVENTS = { "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN" }

local function Start()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	UpdateRoster()
end

local function Stop()
	events:UnregisterAllEvents()
	for _, t in pairs({ logTimer, fullTimer }) do
		t:Cancel()
	end
	logTimer, fullTimer = nil, nil
	wipe(roster)
	wipe(members)
	wipe(sent)
	wipe(turnedIn)
	wipe(queue)
	pumping = false
	Changed()
end

-- For the Quest list -------------------------------------------------------------------------------------------------

-- What a party member's Tomte told us: { quests = { [questID] = { complete, objectives } }, turnedIn = { [questID] =
-- true } }, or nil when nothing came from them (no Tomte, sharing off, or not heard from yet).
function ns.ShareQuests_Member(guid)
	return active and members[guid] or nil
end

-- fn() is called whenever what we know about the party's quests changes.
function ns.ShareQuests_OnChange(fn)
	listeners[#listeners + 1] = fn
end

-- Prints who in your party shares quest progress with you (/tomte share quests).
function ns.ShareQuests_Why()
	if not active then
		ns.Print("quest progress isn't shared: Friend sharing or its Quest progress setting is off.")
		return
	end
	if #roster == 0 then
		ns.Print("quest progress: you're not in a party.")
		return
	end
	ns.Print(("quest progress: %d with you, on %s."):format(#roster, Channel() or "no channel"))
	for _, r in ipairs(roster) do
		local m = members[r.guid]
		local n = 0
		for _ in pairs(m and m.quests or {}) do
			n = n + 1
		end
		print(("  %s: %s"):format(r.name, m and ("shares " .. n .. (n == 1 and " quest" or " quests"))
			or "nothing heard (no Tomte, sharing off, or an older Tomte)"))
	end
end

-- Whether quest progress is being shared right now.
function ns.ShareQuests_Active()
	return active
end

-- Starts or stops sharing: on while Friend sharing is on with its Quest progress setting.
function ns.ShareQuests_Apply(on)
	if on and not active then
		active = true
		Start()
	elseif not on and active then
		active = false
		Stop()
	end
end
