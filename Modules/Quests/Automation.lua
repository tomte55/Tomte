local addonName, ns = ...

-- Quests: accepting and handing in quests, taking the reward and picking gossip options, one step per window the
-- game opens (GOSSIP_SHOW, QUEST_GREETING, QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE). A conversation is one
-- NPC from the first window to the last; the skip key, the quests tried and the options picked are remembered for
-- that conversation only, and what was decided is kept for /tomte quests why. Rules in Data.lua, reads in
-- Read.lua; started and stopped by Quests.lua, which owns db.
-- DialogueUI handles the same events with its own window: every step here selects by quest or option ID (never
-- by position), and each quest and option at most once per conversation, so a step DialogueUI already took
-- can't land on something else. When DialogueUI's own quest or gossip automation is on, that part is left to it.

-- Seconds after QUEST_FINISHED before the conversation counts as over: accepting or handing in a quest closes the
-- quest window, and the NPC's gossip often opens again right after.
local END_DELAY = 1
-- "Pick the reward for me": Gear Check needs the reward items' data, which can arrive after QUEST_COMPLETE.
local REWARD_RETRY = 0.3 -- seconds between tries
local REWARD_TRIES = 6
local MAX_LOG = 30 -- lines kept for why
local SKIP_KEY_NAMES = { shift = "Shift", ctrl = "Ctrl", alt = "Alt" }

local IsSecret = ns.IsSecret

local events = ns.NewEvents() -- shared with Medals.lua, Cinematics.lua, TalkingHead.lua and Items.lua
ns.Quests_Events = events
local OWNER = "auto"

local db
local active = false
local conv -- { guid, npcID, name, skipped, tried = { [questID] = true }, picked = { [optionID] = true }, log }
local lastLog = {} -- the last conversation's log, for why
local endTimer, rewardTimer
local rewardOpen -- questID while its reward window is open
local pendingOffer -- questID whose data was requested before deciding on it

local function Rules()
	return { skipRepeatable = db.skipRepeatable, skipTrivial = db.skipTrivial,
		skipDoneElsewhere = db.skipDoneElsewhere, skipCosts = db.skipCosts }
end

local function CancelEnd()
	if endTimer then
		endTimer:Cancel()
		endTimer = nil
	end
end

local function End()
	CancelEnd()
	conv = nil
end

local function Note(text, did)
	if not conv then
		return
	end
	local log = conv.log
	if #log < MAX_LOG then
		log[#log + 1] = text
	end
	if did and db.announce then
		ns.Print(text)
	end
end

-- The conversation for the NPC whose window just opened: the current one when it's the same NPC (or the NPC can't
-- be told apart right now), else a new one.
local function Conversation()
	CancelEnd()
	local npc = ns.QuestsRead_Npc()
	if conv and (npc.guid == nil or conv.guid == nil or conv.guid == npc.guid) then
		return conv
	end
	conv = { guid = npc.guid, npcID = npc.npcID, name = npc.name, tried = {}, picked = {}, log = {} }
	lastLog = conv.log
	lastLog.name = npc.name
	return conv
end

-- Whether this window may be automated (writes the reason when not).
local function Allowed(c)
	if not db.auto then
		return false
	end
	if c.skipped then
		return false
	end
	if ns.Quests_SkipKeyDown(db.skipKey, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()) then
		c.skipped = true
		Note(("%s was held: left to you until you close the window."):format(SKIP_KEY_NAMES[db.skipKey] or "Shift"))
		return false
	end
	if c.npcID and db.ignored[c.npcID] then
		c.skipped = true
		Note("This NPC is on your ignore list.")
		return false
	end
	return true
end

-- DialogueUI's own automation (both off by default): "AutoSelectGossip" picks gossip options, "AutoCompleteQuest"
-- takes quest steps. Whichever is on, that part is left to DialogueUI.
local function DialogueUISetting(key)
	local saved = _G.DialogueUI_DB
	return C_AddOns.IsAddOnLoaded("DialogueUI") and type(saved) == "table" and saved[key] == true
end

-- Whether this conversation's quest steps (opening, accepting, handing in) are ours to take.
local function QuestSteps(c)
	if not DialogueUISetting("AutoCompleteQuest") then
		return true
	end
	if not c.dialogueNoted then
		c.dialogueNoted = true
		Note("DialogueUI's Auto Complete Quest is on: it takes the quest steps instead.")
	end
	return false
end

-- Gossip -------------------------------------------------------------------------------------------------------

local function EventIDs()
	local set = {}
	for _, entry in ipairs(ns.Content_Get(ns.ContentExpansion(), "questGossip") or {}) do
		set[entry.gossipOptionID] = entry.name
	end
	return set
end


local function OpenQuest(kind, q, byIndex)
	conv.tried[q.questID] = true
	local id = byIndex and q.index or q.questID
	if kind == "active" then
		Note(("Opened \"%s\" to hand it in."):format(q.title))
		if byIndex then
			SelectActiveQuest(id)
		else
			C_GossipInfo.SelectActiveQuest(id)
		end
	else
		Note(("Opened \"%s\" to accept it."):format(q.title))
		if byIndex then
			SelectAvailableQuest(id)
		else
			C_GossipInfo.SelectAvailableQuest(id)
		end
	end
end

local function NotePassed(passed)
	for _, text in ipairs(passed) do
		Note("Passed over " .. text .. ".")
	end
end

local function OnGossipShow()
	local c = Conversation()
	if not Allowed(c) then
		return
	end
	local activeQuests, available = ns.QuestsRead_GossipQuests()
	if QuestSteps(c) then
		local kind, q, passed = ns.Quests_PickQuest(activeQuests, available, c.tried, Rules())
		NotePassed(passed)
		if kind then
			OpenQuest(kind, q, false)
			return
		end
	end
	if not (db.gossipStep or db.gossipOnly or db.gossipEvents) then
		return
	end
	if DialogueUISetting("AutoSelectGossip") then
		Note("DialogueUI's Auto Select Gossip is on: it picks gossip options instead.")
		return
	end
	local options = ns.QuestsRead_GossipOptions()
	local rules = { questStep = db.gossipStep, only = db.gossipOnly, events = db.gossipEvents,
		hasQuests = #activeQuests + #available > 0, forceGossip = C_GossipInfo.ForceGossip() and true or false,
		inInstance = IsInInstance() and true or false, onlyPicked = c.onlyPicked }
	local i, why, rule = ns.Quests_GossipPick(options, EventIDs(), c.picked, rules)
	if not i then
		if why then
			Note(why:gsub("^%l", string.upper) .. ".")
		end
		return
	end
	local option = options[i]
	c.picked[ns.Quests_GossipKey(option)] = true
	if rule == "only" then
		c.onlyPicked = true
	end
	Note(("Picked \"%s\" (%s)."):format(option.name or option.gossipOptionID, why), true)
	C_GossipInfo.SelectOption(option.gossipOptionID)
end

local function OnGreeting()
	local c = Conversation()
	if not Allowed(c) then
		return
	end
	if not QuestSteps(c) then
		return
	end
	local activeQuests, available = ns.QuestsRead_GreetingQuests()
	local kind, q, passed = ns.Quests_PickQuest(activeQuests, available, c.tried, Rules())
	NotePassed(passed)
	if kind then
		OpenQuest(kind, q, true)
	end
end

-- Quest window -------------------------------------------------------------------------------------------------

local function OnDetail(questStartItemID)
	local c = Conversation()
	if not Allowed(c) then
		return
	end
	if not QuestSteps(c) then
		return
	end
	if QuestIsFromAdventureMap() then
		return -- an offer from the adventure map; Blizzard's quest frame leaves those alone too
	end
	local offer = ns.QuestsRead_Offer()
	if not offer then
		return
	end
	offer.fromItem = type(questStartItemID) == "number" and questStartItemID ~= 0 and not IsSecret(questStartItemID)
	if offer.autoAccept and offer.fromAreaTrigger then
		return -- the game accepted it already and shows it in the quest tracker
	end
	local rules = Rules()
	if db.skipTrivial and not offer.dataReady and pendingOffer ~= offer.questID then
		-- Everything but the trivial check first: an item's offer or a PvP quest is decided now, before the
		-- game closes the window (item offers) or the wait would lose what this event said.
		rules.skipTrivial = false
		local ok, why = ns.Quests_ShouldAccept(offer, rules)
		if not ok then
			Note(("Left \"%s\" to you: %s."):format(offer.title, why))
			return
		end
		pendingOffer = offer.questID -- decided when QUEST_DATA_LOAD_RESULT says its data is in
		C_QuestLog.RequestLoadQuestByID(offer.questID)
		return
	end
	pendingOffer = nil
	local ok, why = ns.Quests_ShouldAccept(offer, rules)
	if not ok then
		Note(("Left \"%s\" to you: %s."):format(offer.title, why))
		return
	end
	c.tried[offer.questID] = true
	Note(("Accepted \"%s\"."):format(offer.title), true)
	if offer.autoAccept then
		AcknowledgeAutoAcceptQuest()
	else
		AcceptQuest()
	end
end

local function OnDataLoaded(questID, success)
	if not pendingOffer or questID ~= pendingOffer then
		return
	end
	if not success or GetQuestID() ~= questID then
		pendingOffer = nil
		return
	end
	OnDetail(nil)
end

local function OnProgress()
	local c = Conversation()
	if not (Allowed(c) and QuestSteps(c)) then
		return
	end
	local info = ns.QuestsRead_TurnIn(true)
	if not info then
		return
	end
	local ok, why = ns.Quests_ShouldTurnIn(info, Rules())
	if not ok then
		Note(("Left \"%s\" to you: %s."):format(info.title, why))
		return
	end
	Note(("Handed in \"%s\"."):format(info.title))
	CompleteQuest()
end

local function CancelReward()
	if rewardTimer then
		rewardTimer:Cancel()
		rewardTimer = nil
	end
end

local function TakeReward(questID, title, attempt)
	rewardTimer = nil
	if rewardOpen ~= questID or GetQuestID() ~= questID then
		return
	end
	local n = GetNumQuestChoices() or 0
	local best = db.pickReward and n > 1 and ns.GearRewards_BestChoice and ns.GearRewards_BestChoice() or nil
	local choice = ns.Quests_RewardChoice(n, best, db.pickReward)
	if choice then
		if n > 1 then
			Note(("Finished \"%s\" and took reward %d (Gear Check's pick)."):format(title, choice), true)
		else
			Note(("Finished \"%s\"."):format(title), true)
		end
		GetQuestReward(choice)
		return
	end
	if db.pickReward and attempt < REWARD_TRIES then
		rewardTimer = C_Timer.NewTimer(REWARD_RETRY, function()
			TakeReward(questID, title, attempt + 1)
		end)
		return
	end
	Note(("\"%s\" has %d rewards to choose from: %s."):format(title, n,
		db.pickReward and "Gear Check isn't sure which is best, so it's yours to pick" or "yours to pick"))
end

local function OnComplete()
	local c = Conversation()
	if not (Allowed(c) and QuestSteps(c)) then
		return
	end
	local info = ns.QuestsRead_TurnIn(false)
	if not info then
		return
	end
	local ok, why = ns.Quests_ShouldTurnIn(info, Rules())
	if not ok then
		Note(("Left \"%s\" to you: %s."):format(info.title, why))
		return
	end
	CancelReward()
	rewardOpen = info.questID
	TakeReward(info.questID, info.title, 1)
end

local function OnFinished()
	rewardOpen = nil
	CancelReward()
	CancelEnd()
	if conv then
		endTimer = C_Timer.NewTimer(END_DELAY, End)
	end
end

local function OnGossipClosed(interactionIsContinuing)
	if not interactionIsContinuing then
		End()
	end
end

events:On(OWNER, "GOSSIP_SHOW", OnGossipShow)
events:On(OWNER, "GOSSIP_CLOSED", function(_, interactionIsContinuing)
	OnGossipClosed(interactionIsContinuing)
end)
events:On(OWNER, "QUEST_GREETING", OnGreeting)
events:On(OWNER, "QUEST_DETAIL", function(_, questStartItemID)
	OnDetail(questStartItemID)
end)
events:On(OWNER, "QUEST_DATA_LOAD_RESULT", function(_, questID, success)
	OnDataLoaded(questID, success)
end)
events:On(OWNER, "QUEST_PROGRESS", OnProgress)
events:On(OWNER, "QUEST_COMPLETE", OnComplete)
events:On(OWNER, "QUEST_FINISHED", OnFinished)

local EVENTS = {
	"GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_DATA_LOAD_RESULT", "QUEST_PROGRESS",
	"QUEST_COMPLETE", "QUEST_FINISHED",
}

-- Ignore list ---------------------------------------------------------------------------------------------------

function ns.QuestsAuto_IsIgnored(npcID)
	return active and npcID ~= nil and db.ignored[npcID] ~= nil
end

-- Adds or removes an NPC (by ID) from the ignore list; true when it's on the list now.
function ns.QuestsAuto_ToggleIgnore(npcID, name)
	if db.ignored[npcID] then
		db.ignored[npcID] = nil
		ns.Print(("%s is automated again."):format(name or ("NPC " .. npcID)))
		return false
	end
	db.ignored[npcID] = name or true
	ns.Print(("%s is on your ignore list: quests and gossip there are left to you."):format(name or ("NPC " .. npcID)))
	return true
end

-- Commands ------------------------------------------------------------------------------------------------------

function ns.QuestsAuto_PrintWhy()
	if #lastLog == 0 then
		ns.Print("nothing to explain yet: talk to an NPC with quests or gossip first.")
		return
	end
	ns.Print(("last NPC: %s"):format(lastLog.name or "unknown"))
	for _, line in ipairs(lastLog) do
		print("  " .. line)
	end
end

function ns.QuestsAuto_PrintIgnored()
	local list = {}
	for npcID, name in pairs(db.ignored) do
		list[#list + 1] = { id = npcID, name = type(name) == "string" and name or ("NPC " .. npcID) }
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	if #list == 0 then
		ns.Print("no NPCs on the ignore list. Right-click a targeted NPC's portrait to add one.")
		return
	end
	ns.Print(("%d NPCs on the ignore list (/tomte quests ignore <ID> takes one off):"):format(#list))
	for _, entry in ipairs(list) do
		print(("  %s (%d)"):format(entry.name, entry.id))
	end
end

-- Start and stop ------------------------------------------------------------------------------------------------

function ns.QuestsAuto_Start(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs(EVENTS) do
		events:Watch(OWNER, event)
	end
end

function ns.QuestsAuto_Stop()
	active = false
	events:UnwatchAll(OWNER)
	CancelReward()
	End()
	rewardOpen, pendingOffer = nil, nil
end
