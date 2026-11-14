local addonName, ns = ...

-- Quest list: party members' progress and the party actions on the quest menu. Counts come from the tooltip data of
-- your target, the unit under the mouse and the nameplates (works for anyone: it's what the game's own mob tooltip
-- shows), and from party members who run Tomte over hidden addon messages (sync), which replace the tooltip reads for
-- them. Rules and the message format in PartyData.lua; QuestList.lua starts and stops this and asks for each quest's
-- party lines (QuestListParty_Annotate). Makes the module's event bus, ns.QuestList_Events.
-- See docs/superpowers/specs/2026-11-14-tomte-quest-list-party-design.md.

local PREFIX = "TomteQuests" -- addon message prefix (16 characters at most)
local READ_EVERY = 3 -- seconds between nameplate reads while you're in a party: kill credit doesn't fire an event here
local SEND_GAP = 0.2 -- seconds between sync messages
local THROTTLED = 2 -- seconds to wait after the game throttled a message
local LOCKDOWN = 10 -- seconds to wait while addon messages are locked down
local LOG_DELAY = 1 -- seconds: the quest log changes in bursts, one sync per burst
local FULL_GAP = 10 -- seconds: our full state goes out at most this often (hellos from several new members share one)
local HELLO_GAP = 10 -- seconds between our own hellos
local NAMEPLATES = 40 -- nameplate unit tokens to look through
local OWNER = "questListParty"

local events = ns.NewEvents()
ns.QuestList_Events = events

local IsSecret = ns.IsSecret

local db
local active = false
local onChange -- QuestList.lua's redraw (debounced there)
local roster = {} -- party members in party order: { unit, guid, name, class }
-- [guid] = { quests = { [questID] = { complete, objectives = { [k] = { have, need, finished } } } }, synced (runs
-- Tomte: its quests are all of them), turnedIn = { [questID] = true } }
local members = {}
local myQuests = {} -- your quests with their objectives, for matching tooltip lines and for sync
local sent = {} -- [questID] = the entry last sent to the party
local turnedIn = {} -- [questID] = true: handed in since the last sync
local queue = {} -- sync messages waiting to go
local pumping = false
local fullAt, helloAt = -math.huge, -math.huge
local readTicker, logTimer, fullTimer

-- The party --------------------------------------------------------------------------------------------------------

-- Party members (your subgroup in a raid) we can tell apart: a secret GUID or name leaves that member out.
local function ReadRoster()
	local list = {}
	for i = 1, GetNumSubgroupMembers() do
		local unit = "party" .. i
		local guid, name = UnitGUID(unit), UnitName(unit)
		local _, class = UnitClass(unit)
		if guid and name and not IsSecret(guid, name, class) then
			list[#list + 1] = { unit = unit, guid = guid, name = name, class = class }
		end
	end
	return list
end

-- The addon channel for your group, nil outside one.
local function Channel()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
		and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	end
	return IsInGroup() and "PARTY" or nil
end

local function Changed()
	if onChange then
		onChange()
	end
end

-- Your quests --------------------------------------------------------------------------------------------------------

local function ReadMine()
	local list = {}
	for _, q in ipairs(ns.LevelingRead_Quests()) do
		list[#list + 1] = { questID = q.questID, title = q.title, complete = q.complete,
			objectives = ns.QuestListRead_Objectives(q.questID) }
	end
	myQuests = list
end

local function MyEntries()
	local out = {}
	for _, q in ipairs(myQuests) do
		out[q.questID] = ns.QuestListParty_Entry(q)
	end
	return out
end

-- Tooltip reads ------------------------------------------------------------------------------------------------------

-- A unit's quest lines as PartyData.lua reads them, nil when a value is secret or there's no tooltip.
local function ReadLines(unit)
	local data = C_TooltipInfo.GetUnit(unit)
	if not data or not data.lines or IsSecret(data.lines) then
		return nil
	end
	local LineType = Enum.TooltipDataLineType
	local lines = {}
	for _, line in ipairs(data.lines) do
		local kind = line.type
		if IsSecret(kind) then
			return nil
		end
		if kind == LineType.QuestTitle then
			local text, id = line.leftText, line.id
			if IsSecret(text, id) then
				return nil
			end
			lines[#lines + 1] = { kind = "title", text = text, id = type(id) == "number" and id or nil }
		elseif kind == LineType.QuestPlayer then
			local guid = line.guid
			if IsSecret(guid) then
				return nil
			end
			lines[#lines + 1] = { kind = "player", guid = guid }
		elseif kind == LineType.QuestObjective then
			local text, completed = line.leftText, line.completed
			if IsSecret(text, completed) then
				return nil
			end
			lines[#lines + 1] = { kind = "objective", text = text, completed = completed and true or false }
		end
	end
	return lines
end

-- Reads one unit's tooltip into the members it counts for. True when a count changed. Players are skipped (their
-- tooltips carry no quest lines worth the read).
local function ReadUnit(unit)
	if not UnitExists(unit) then
		return false
	end
	local isPlayer, me = UnitIsPlayer(unit), UnitGUID("player")
	if IsSecret(isPlayer, me) or isPlayer then
		return false
	end
	local lines = ReadLines(unit)
	if not lines or #lines == 0 then
		return false
	end
	local changed = false
	for guid, quests in pairs(ns.QuestListParty_ReadTooltip(lines, myQuests, me)) do
		local m = members[guid]
		if m and not m.synced then
			for questID, objectives in pairs(quests) do
				local q = m.quests[questID] or { objectives = {} }
				m.quests[questID] = q
				for k, o in pairs(objectives) do
					local old = q.objectives[k]
					if not old or old.have ~= o.have or old.finished ~= o.finished then
						q.objectives[k] = o
						changed = true
					end
				end
			end
		end
	end
	return changed
end

local function Reading()
	return active and db.party and #roster > 0
end

local function ReadOne(unit)
	if Reading() and ReadUnit(unit) then
		Changed()
	end
end

local function ReadAround()
	if not Reading() then
		return
	end
	local changed = ReadUnit("target")
	changed = ReadUnit("mouseover") or changed
	for i = 1, NAMEPLATES do
		changed = ReadUnit("nameplate" .. i) or changed
	end
	if changed then
		Changed()
	end
end

-- The read ticker runs only while there's a party to read for.
local function ApplyTicker()
	local want = Reading()
	if want and not readTicker then
		readTicker = C_Timer.NewTicker(READ_EVERY, ReadAround)
	elseif not want and readTicker then
		readTicker:Cancel()
		readTicker = nil
	end
end

-- Sync ---------------------------------------------------------------------------------------------------------------

local function Syncing()
	return active and db.partySync and Channel() ~= nil
end

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
	if not Syncing() then
		return
	end
	ReadMine()
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
	Send(ns.QuestListParty_Pack("S", entries))
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
	if not Syncing() then
		return
	end
	if GetTime() - helloAt >= HELLO_GAP then
		helloAt = GetTime()
		Send({ ns.QuestListParty_Hello() })
	end
	FullSoon()
end

-- After the log changed: the quests that changed, those gone, those turned in.
local function LogSettled()
	logTimer = nil
	if not active then
		return
	end
	ReadMine()
	if not Syncing() then
		wipe(turnedIn)
		return
	end
	local now = MyEntries()
	local changed, gone, turned = ns.QuestListParty_Diff(sent, now, turnedIn)
	sent = now
	wipe(turnedIn)
	if #changed > 0 then
		Send(ns.QuestListParty_Pack("Q", changed))
	end
	if #gone > 0 then
		Send(ns.QuestListParty_PackIDs("G", gone))
	end
	if #turned > 0 then
		Send(ns.QuestListParty_PackIDs("T", turned))
	end
end

local function LogChanged()
	if not logTimer then
		logTimer = C_Timer.NewTimer(LOG_DELAY, LogSettled)
	end
end

-- A party member by the sender of an addon message ("Name-Realm"). Names in a party are told apart without the realm.
local function FromSender(sender)
	local short = Ambiguate(sender, "short")
	for _, r in ipairs(roster) do
		if r.name == short then
			return members[r.guid]
		end
	end
	return nil
end

local function Received(text, sender)
	local m = FromSender(sender)
	local msg = m and ns.QuestListParty_Decode(text)
	if not msg then
		return
	end
	if msg.kind == "hello" then
		FullSoon()
		return
	end
	m.synced = true
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

-- Roster -------------------------------------------------------------------------------------------------------------

local function UpdateRoster()
	roster = ReadRoster()
	local now, fresh = {}, false
	for _, r in ipairs(roster) do
		now[r.guid] = true
		if not members[r.guid] then
			members[r.guid] = { quests = {}, turnedIn = {} }
			fresh = true
		end
	end
	for guid in pairs(members) do
		if not now[guid] then
			members[guid] = nil
		end
	end
	if #roster == 0 then
		wipe(sent) -- the next party gets a full state anyway
	end
	ApplyTicker()
	if fresh then
		Greet()
	end
end

-- Events -------------------------------------------------------------------------------------------------------------

local WATCHED = {
	GROUP_ROSTER_UPDATE = function()
		UpdateRoster()
		Changed()
	end,
	CHAT_MSG_ADDON = function(_, prefix, text, _, sender)
		if prefix == PREFIX and db.partySync and not IsSecret(text, sender) then
			Received(text, sender)
		end
	end,
	QUEST_LOG_UPDATE = LogChanged,
	QUEST_TURNED_IN = function(_, questID)
		turnedIn[questID] = true
		LogChanged()
	end,
	-- A party member's log changed (a quest taken, done or dropped): what they have is asked again on the redraw.
	UNIT_QUEST_LOG_CHANGED = function(_, unit)
		if unit ~= "player" and #roster > 0 then
			Changed()
		end
	end,
	NAME_PLATE_UNIT_ADDED = function(_, unit)
		ReadOne(unit)
	end,
	PLAYER_TARGET_CHANGED = function()
		ReadOne("target")
	end,
	UPDATE_MOUSEOVER_UNIT = function()
		ReadOne("mouseover")
	end,
}
for event, fn in pairs(WATCHED) do
	events:On(OWNER, event, fn)
end

-- Started and stopped with the Quest list. changed: called when what the list shows about the party changed.
function ns.QuestListParty_Start(moduleDB, changed)
	db, onChange = moduleDB, changed
	active = true
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	for event in pairs(WATCHED) do
		events:Watch(OWNER, event)
	end
	ReadMine()
	UpdateRoster()
end

function ns.QuestListParty_Stop()
	active = false
	events:UnwatchAll(OWNER)
	for _, t in pairs({ readTicker, logTimer, fullTimer }) do
		t:Cancel()
	end
	readTicker, logTimer, fullTimer = nil, nil, nil
	wipe(roster)
	wipe(members)
	wipe(myQuests)
	wipe(sent)
	wipe(turnedIn)
	wipe(queue)
end

-- A party setting changed.
function ns.QuestListParty_Settings()
	if not active then
		return
	end
	ApplyTicker()
	if db.partySync then
		Greet()
	else
		for _, m in pairs(members) do
			if m.synced then
				m.synced = false
				wipe(m.quests)
				wipe(m.turnedIn)
			end
		end
	end
	Changed()
end

-- The list's quests get q.party (PartyData.lua's QuestListParty_Lines), nil when there's nothing to show.
function ns.QuestListParty_Annotate(quests)
	local show = active and db.party and #roster > 0
	local onQuest = C_QuestLog.IsUnitOnQuest
	for _, q in ipairs(quests) do
		q.party = nil
		if show then
			local list = {}
			for i, r in ipairs(roster) do
				local m = members[r.guid]
				local on
				if m.synced then
					on = m.quests[q.questID] ~= nil
				elseif onQuest and UnitIsConnected(r.unit) then
					on = onQuest(r.unit, q.questID)
					if IsSecret(on) then
						on = nil
					end
				end
				list[i] = { name = r.name, class = r.class, onQuest = on, turnedIn = m.turnedIn[q.questID],
					quest = m.quests[q.questID] }
			end
			q.party = ns.QuestListParty_Lines(q, list, { missing = db.partyMissing })
		end
	end
end

-- Quest menu ---------------------------------------------------------------------------------------------------------

function ns.QuestListParty_CanShare(q)
	if not IsInGroup() or not C_QuestLog.IsPushableQuest then
		return false
	end
	local ok = C_QuestLog.IsPushableQuest(q.questID)
	return not IsSecret(ok) and ok and true or false
end

-- The game's own quest share (each party member gets the usual accept window). Passed the log index as the quest log's
-- own Share button does; selecting the quest from here first would taint the quest log's selection.
function ns.QuestListParty_Share(q)
	local index = C_QuestLog.GetLogIndexForQuestID(q.questID)
	if index then
		QuestLogPushQuest(index)
	end
end

function ns.QuestListParty_CanTell()
	return Channel() ~= nil
end

local function QuestLink(q)
	local link = GetQuestLink and GetQuestLink(q.questID)
	if not link or link == "" then
		link = "[" .. (q.title or "?") .. "]"
	end
	return link
end

-- Your progress on q in party chat: its link and each objective's count (q carries the list's objectives).
function ns.QuestListParty_Tell(q)
	local channel = Channel()
	if not channel then
		return
	end
	for _, text in ipairs(ns.QuestListParty_ChatLines(QuestLink(q), q.objectives or {}, q.complete)) do
		ns.Chat_Send(text, channel)
	end
end

-- The quest's link in the chat box, to write the rest yourself: added to an open box, or opening one with it.
function ns.QuestListParty_LinkToChat(q)
	local link = QuestLink(q)
	if not ns.Chat_InsertLink(link) then
		ns.Chat_Open(link)
	end
end

-- Your zone's General channel by its number (/1), nil where there's none (an instance).
local function General()
	local id = C_ChatInfo.GetGeneralChannelLocalID and C_ChatInfo.GetGeneralChannelLocalID()
	if IsSecret(id) or not id or id <= 0 then
		return nil
	end
	return id
end

function ns.QuestListParty_CanPost()
	return General() ~= nil
end

-- "LFG [quest]" or "LFM [quest], 2/5" for General, put in the chat box ready to send ("/1 ..."): you press Enter.
-- Sending to a channel from addon code was blocked even straight from the menu row's click (ADDON_ACTION_BLOCKED on
-- Forever 1.60.1, 2026-11-14; warcraft.wiki.gg lists SendChatMessage as AllowedWhenUntainted).
function ns.QuestListParty_Post(q, kind)
	local id = General()
	if not id then
		return
	end
	local most = IsInGroup() and not IsInRaid() and (MEMBERS_PER_RAID_GROUP or 5) or nil
	local text = ns.QuestListParty_GroupText(kind, QuestLink(q), q.elite, GetNumGroupMembers(), most)
	ns.Chat_Open(("/%d %s"):format(id, text))
end

-- /tomte questlist party
function ns.QuestListParty_Why()
	if not active then
		ns.Print("Quest list party: the Quest list is off.")
		return
	end
	if #roster == 0 then
		ns.Print("Quest list party: you're not in a party.")
		return
	end
	ns.Print(("Quest list party: %d with you, progress %s, sync %s."):format(#roster, db.party and "shown" or "hidden",
		db.partySync and "on" or "off"))
	for _, r in ipairs(roster) do
		local m = members[r.guid]
		local n = 0
		for _ in pairs(m.quests) do
			n = n + 1
		end
		print(("  %s: %s, counts for %d quest%s"):format(r.name,
			m.synced and "runs Tomte (synced)" or "read from tooltips", n, n == 1 and "" or "s"))
	end
end
