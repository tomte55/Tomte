local addonName, ns = ...

-- Weekly board: reads the game into the current character's snapshot (TomteDB.weekly.chars[guid]) and learns weekly
-- quests from the quest log. Only max-level characters get a snapshot. Nothing is read in combat; refreshes are
-- debounced to one per second. Each part is read on its own, so one failing API leaves the others working.
-- Weekly.lua starts and stops it; ns.Weekly_Changed runs after every refresh.

local DEBOUNCE = 1
local RESET_SLACK = 30 -- seconds after the weekly reset before reading again

local db, guid
local pending, resetTimer
local turnedIn = {} -- [questID] = true, this session (the completed flag can lag behind the turn-in)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Completed(id)
	return turnedIn[id] or C_QuestLog.IsQuestFlaggedCompleted(id)
end

local function IsTracked()
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
	return not maxLevel or UnitLevel("player") >= maxLevel
end

local function ReadVault(snap)
	local vault = {}
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		local kind = Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType[track.enum] or track.type
		local activities = C_WeeklyRewards.GetActivities(kind) or {}
		table.sort(activities, function(a, b)
			return a.index < b.index
		end)
		local slots = {}
		for i, a in ipairs(activities) do
			local slot = { progress = a.progress, threshold = a.threshold }
			if a.threshold > 0 and a.progress >= a.threshold then
				local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(a.id)
				slot.ilvl = link and C_Item.GetDetailedItemLevelInfo(link) or nil
			end
			slots[i] = slot
		end
		vault[track.key] = slots
	end
	snap.vault = vault
	-- Blizzard's vault window says "return to the vault to claim" on exactly this.
	snap.vaultReady = C_WeeklyRewards.HasAvailableRewards() == true
end

local function ReadCurrencies(snap)
	local currencies = {}
	for _, id in ipairs(ns.WEEKLY_CRESTS) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info and info.name and info.name ~= "" and (info.discovered or (info.quantity or 0) > 0 or (info.totalEarned or 0) > 0) then
			currencies[id] = {
				name = info.name, qty = info.quantity, earnedWeek = info.quantityEarnedThisWeek,
				weeklyCap = info.maxWeeklyQuantity, total = info.totalEarned, seasonCap = info.maxQuantity,
				useTotal = info.useTotalEarnedForMaxQty,
			}
		end
	end
	snap.currencies = currencies
end

local function ReadRenown(snap)
	local renown = {}
	local hidden = C_MajorFactions.IsMajorFactionHiddenFromExpansionPage
	for _, id in ipairs(C_MajorFactions.GetMajorFactionIDs(GetExpansionLevel()) or {}) do
		local data = C_MajorFactions.GetMajorFactionData(id)
		if data and data.isUnlocked and not (hidden and hidden(id)) then
			renown[id] = {
				name = data.name, level = data.renownLevel, max = (data.maxLevel or 0) > 0 and data.maxLevel or nil,
				earned = data.renownReputationEarned, threshold = data.renownLevelThreshold,
			}
		end
	end
	snap.renown = renown
end

local function ReadLockouts(snap, now)
	local list = {}
	for i = 1, GetNumSavedInstances() do
		local name, _, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
		if isRaid and (locked or extended) and (reset or 0) > 0 then
			list[#list + 1] = { name = name, difficulty = difficultyName, killed = encounterProgress, total = numEncounters,
				expires = now + reset }
		end
	end
	for i = 1, GetNumSavedWorldBosses() do
		local name, _, reset = GetSavedWorldBossInfo(i)
		if name and (reset or 0) > 0 then
			list[#list + 1] = { name = name, worldBoss = true, expires = now + reset }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	snap.lockouts = list
end

-- Weekly quests in the log are learned (account-wide); every learned quest is checked for this character.
local function ReadQuests(snap, now)
	local quests = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.frequency == Enum.QuestFrequency.Weekly
			and not ns.Weekly_IsProfQuest(info.questID) then
			local q = db.quests[info.questID] or { firstSeen = now }
			q.title = info.title
			db.quests[info.questID] = q
			quests[info.questID] = "log"
		end
	end
	for id in pairs(db.quests) do
		if Completed(id) then
			quests[id] = "done"
		end
	end
	snap.quests = quests
end

local function ReadProfs(snap, now)
	local old = snap.profs or {}
	local profs = {}
	local expansion = ns.Weekly_Expansion(GetExpansionLevel())
	local first, second = GetProfessions()
	for _, index in pairs({ first, second }) do
		local name, icon, _, _, _, _, base = GetProfessionInfo(index)
		local def = base and ns.Weekly_ProfDef(expansion, base)
		if def then
			local prof = { name = name, icon = icon, base = base, expansion = expansion, gathering = def.gathering,
				knowledge = {} }
			for _, id in ipairs(ns.Weekly_ProfQuestIDs(def)) do
				if Completed(id) then
					prof.knowledge[id] = true
				end
			end
			local before = old[def.child] and old[def.child].conc
			local currency = not def.gathering and C_TradeSkillUI.GetConcentrationCurrencyID(def.child)
			local info = currency and currency > 0 and C_CurrencyInfo.GetCurrencyInfo(currency)
			if info and (info.maxQuantity or 0) > 0 then
				prof.conc = ns.Weekly_MergeConc(before, {
					qty = info.quantity, max = info.maxQuantity, cycleMS = info.rechargingCycleDurationMS,
					perCycle = info.rechargingAmountPerCycle, at = now,
				})
			else
				prof.conc = before -- keep the last good reading (it may not be readable before the profession opens)
			end
			profs[def.child] = prof
		end
	end
	snap.profs = profs
end

local function Read(reader, snap, now)
	xpcall(reader, function(err)
		return ns.errorHandler(err)
	end, snap, now)
end

local function ScheduleResetRefresh(snap, now)
	if resetTimer then
		resetTimer:Cancel()
		resetTimer = nil
	end
	local wait = snap.nextReset and snap.nextReset - now + RESET_SLACK
	if wait and wait > 0 and wait < 7 * 86400 then
		resetTimer = C_Timer.NewTimer(wait, ns.WeeklyCollect_Request)
	end
end

local function Refresh()
	pending = false
	if not db then
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if not IsTracked() then
		ns.Weekly_Changed() -- no snapshot here, but other characters' Concentration still toasts
		return
	end
	guid = UnitGUID("player")
	local now = GetServerTime()
	local snap = db.chars[guid] or {}
	db.chars[guid] = snap
	snap.guid = guid
	snap.name = UnitName("player")
	snap.realm = GetNormalizedRealmName()
	snap.class = select(2, UnitClass("player"))
	snap.level = UnitLevel("player")
	snap.at, snap.seen = now, now
	local untilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if snap.nextReset and now >= snap.nextReset then
		wipe(turnedIn) -- turned in last week
	end
	if untilReset and untilReset > 0 then
		snap.nextReset = now + untilReset
	end
	Read(ReadVault, snap, now)
	Read(ReadCurrencies, snap, now)
	Read(ReadRenown, snap, now)
	Read(ReadLockouts, snap, now)
	Read(ReadQuests, snap, now)
	Read(ReadProfs, snap, now)
	ScheduleResetRefresh(snap, now)
	ns.Weekly_Changed()
end

function ns.WeeklyCollect_Request()
	if not db or pending then
		return
	end
	pending = true
	C_Timer.After(DEBOUNCE, Refresh)
end

local REFRESH_EVENTS = {
	"WEEKLY_REWARDS_UPDATE", "CURRENCY_DISPLAY_UPDATE", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED",
	"UPDATE_INSTANCE_INFO", "QUEST_ACCEPTED", "QUEST_REMOVED", "TRADE_SKILL_SHOW", "SKILL_LINES_CHANGED", "LOOT_CLOSED",
	"PLAYER_LEVEL_UP",
}
for _, event in ipairs(REFRESH_EVENTS) do
	events[event] = ns.WeeklyCollect_Request
end

function events:PLAYER_ENTERING_WORLD()
	RequestRaidInfo() -- answers with UPDATE_INSTANCE_INFO
	ns.WeeklyCollect_Request()
end

function events:QUEST_TURNED_IN(questID)
	turnedIn[questID] = true
	ns.WeeklyCollect_Request()
end

function events:PLAYER_REGEN_ENABLED()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns.WeeklyCollect_Request()
end

-- Last seen, for the grid's order. The data itself is from the last refresh (API data at logout isn't guaranteed).
function events:PLAYER_LOGOUT()
	local snap = db and guid and db.chars[guid]
	if snap then
		snap.seen = GetServerTime()
	end
end

function ns.WeeklyCollect_Start(moduleDB)
	db = moduleDB
	for _, event in ipairs(REFRESH_EVENTS) do
		events:RegisterEvent(event)
	end
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("QUEST_TURNED_IN")
	events:RegisterEvent("PLAYER_LOGOUT")
	if ns.inWorld then
		events:PLAYER_ENTERING_WORLD()
	end
end

function ns.WeeklyCollect_Stop()
	events:UnregisterAllEvents()
	if resetTimer then
		resetTimer:Cancel()
		resetTimer = nil
	end
	db = nil
end
