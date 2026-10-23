local addonName, ns = ...

-- Quests: reads the NPC you talk to, its quests and gossip options, the quest window's offer or turn-in, and the
-- "Race Times" aura into plain tables for the rules in Data.lua. Acted on in Automation.lua and Medals.lua.

-- The "Race Times" aura at a skyriding race start (spell_holy_borrowedtime; the icon Plumber matches it by).
local RACE_AURA_ICON = 237538
local MAX_AURAS = 40 -- buffs scanned for that aura

local IsSecret = ns.IsSecret

-- Quest frequency per quest ID, learned from gossip lists this session: the quest window itself only says daily
-- or weekly, not "resets by schedule".
local frequencies = {}

local function Plain(v)
	if IsSecret(v) then
		return nil
	end
	return v
end

-- The NPC (or object) the open window belongs to: { guid, npcID, name }, fields nil when unreadable.
function ns.QuestsRead_Npc()
	local guid = Plain(UnitGUID("npc"))
	local name = Plain(UnitName("npc"))
	return { guid = guid, npcID = ns.Quests_NpcID(guid), name = name }
end

-- The target's NPC ID and name for the right-click menu, nil for players and unreadable units.
function ns.QuestsRead_UnitNpc(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then
		return nil
	end
	local guid = Plain(UnitGUID(unit))
	local npcID = ns.Quests_NpcID(guid)
	if not npcID then
		return nil
	end
	return npcID, Plain(UnitName(unit))
end

-- True when another character of the account has done the quest and this one hasn't.
function ns.QuestsRead_DoneElsewhere(questID)
	if not questID or C_QuestLog.IsQuestFlaggedCompleted(questID) then
		return false
	end
	return C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) and true or false
end

local function Title(questID, fallback)
	return Plain(fallback) or C_QuestLog.GetTitleForQuestID(questID) or ("quest " .. questID)
end

-- Gossip lists (GOSSIP_SHOW): active = { { questID, title, complete, frequency, repeatable } },
-- available = { { questID, title, frequency, repeatable, trivial, doneElsewhere } }.
function ns.QuestsRead_GossipQuests()
	local active, available = {}, {}
	for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
		local questID = Plain(q.questID)
		if questID then
			active[#active + 1] = { questID = questID, title = Title(questID, q.title), complete = q.isComplete,
				frequency = q.frequency, repeatable = q.repeatable or q.isRepeatable }
		end
	end
	for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		local questID = Plain(q.questID)
		if questID then
			frequencies[questID] = q.frequency
			available[#available + 1] = { questID = questID, title = Title(questID, q.title), frequency = q.frequency,
				repeatable = q.repeatable or q.isRepeatable, trivial = q.isTrivial,
				doneElsewhere = ns.QuestsRead_DoneElsewhere(questID) }
		end
	end
	return active, available
end

-- The old-style quest greeting (QUEST_GREETING): the same lists, each entry with its index for SelectActiveQuest
-- and SelectAvailableQuest.
function ns.QuestsRead_GreetingQuests()
	local active, available = {}, {}
	for i = 1, GetNumActiveQuests() do
		local title, complete = GetActiveTitle(i)
		local questID = Plain(GetActiveQuestID(i))
		if questID then
			active[#active + 1] = { index = i, questID = questID, title = Title(questID, title), complete = complete,
				repeatable = C_QuestLog.IsRepeatableQuest(questID) }
		end
	end
	for i = 1, GetNumAvailableQuests() do
		local trivial, frequency, repeatable, _, questID = GetAvailableQuestInfo(i)
		questID = Plain(questID)
		if questID then
			frequencies[questID] = frequency
			available[#available + 1] = { index = i, questID = questID, title = Title(questID, GetAvailableTitle(i)),
				frequency = frequency, repeatable = repeatable, trivial = trivial,
				doneElsewhere = ns.QuestsRead_DoneElsewhere(questID) }
		end
	end
	return active, available
end

-- The gossip options as the game lists them (sorted by orderIndex); secret fields read as missing.
function ns.QuestsRead_GossipOptions()
	local list = {}
	for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
		list[#list + 1] = { gossipOptionID = Plain(o.gossipOptionID), name = Plain(o.name), flags = Plain(o.flags),
			status = Plain(o.status), orderIndex = Plain(o.orderIndex) or 0,
			selectOptionWhenOnlyOption = Plain(o.selectOptionWhenOnlyOption), icon = Plain(o.icon),
			overrideIconID = Plain(o.overrideIconID), spellID = Plain(o.spellID) }
	end
	table.sort(list, function(a, b)
		return a.orderIndex < b.orderIndex
	end)
	return list
end

-- Frequency of a quest from the quest log (turn-ins), else what a gossip list said, else nil.
local function LogFrequency(questID)
	local index = C_QuestLog.GetLogIndexForQuestID(questID)
	local info = index and C_QuestLog.GetInfo(index)
	return (info and info.frequency) or frequencies[questID]
end

-- The quest the window offers (QUEST_DETAIL): { questID, title, frequency, repeatable, trivial, doneElsewhere, pvp,
-- autoAccept, fromAreaTrigger, dataReady }. dataReady: false while the quest's level isn't loaded yet (the
-- trivial check needs it).
function ns.QuestsRead_Offer()
	local questID = Plain(GetQuestID())
	if not questID or questID == 0 then
		return nil
	end
	local frequency = frequencies[questID]
	if QuestIsDaily() then
		frequency = 1
	elseif QuestIsWeekly() then
		frequency = 2
	end
	local level = C_QuestLog.GetQuestDifficultyLevel(questID)
	return { questID = questID, title = Title(questID), frequency = frequency,
		repeatable = C_QuestLog.IsRepeatableQuest(questID), trivial = C_QuestLog.IsQuestTrivial(questID),
		doneElsewhere = ns.QuestsRead_DoneElsewhere(questID), pvp = QuestFlagsPVP() and true or false,
		autoAccept = QuestGetAutoAccept() and true or false,
		fromAreaTrigger = QuestIsFromAreaTrigger() and true or false,
		dataReady = level ~= nil and level ~= 0 }
end

-- The quest being handed in (QUEST_PROGRESS with completable, QUEST_COMPLETE without):
-- { questID, title, completable, money, currencies, frequency, repeatable }.
function ns.QuestsRead_TurnIn(atProgress)
	local questID = Plain(GetQuestID())
	if not questID or questID == 0 then
		return nil
	end
	local info = { questID = questID, title = Title(questID), money = GetQuestMoneyToGet() or 0,
		currencies = GetNumQuestCurrencies() or 0, frequency = LogFrequency(questID),
		repeatable = C_QuestLog.IsRepeatableQuest(questID) }
	if atProgress then
		info.completable = IsQuestCompletable() and true or false
	end
	return info
end

-- The text lines of the "Race Times" aura's tooltip, or nil when it isn't on (or auras are secret right now).
function ns.QuestsRead_RaceAura()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
		return nil
	end
	for i = 1, MAX_AURAS do
		local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		if not aura then
			return nil
		end
		if not IsSecret(aura.icon, aura.auraInstanceID) and aura.icon == RACE_AURA_ICON then
			local data = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", aura.auraInstanceID)
			local line = data and data.lines and data.lines[2]
			local text = line and Plain(line.leftText)
			if type(text) == "string" then
				local lines = {}
				for part in text:gmatch("[^\r\n]+") do
					lines[#lines + 1] = part
				end
				return lines
			end
		end
	end
	return nil
end
