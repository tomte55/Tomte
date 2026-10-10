local addonName, ns = ...

-- World quests: reading the game. ns.WQ_ForMap turns the viewed map's world quests into the plain records Data.lua
-- works on. What a quest rewards never changes, so that part is cached per quest once it has loaded; what changes
-- (time left, collected or not, Gear Check's verdict, currency caps, max renown) is read fresh on every call.
-- Rewards load asynchronously, like Blizzard's map pins: HaveQuestRewardData, else RequestPreloadRewardData and wait
-- for QUEST_LOG_UPDATE.

local GetQuestTimeLeftSeconds = C_TaskQuest.GetQuestTimeLeftSeconds

local TYPES = {} -- Enum.QuestTagType value -> record type
for enumKey, typeKey in pairs({
	Profession = "profession", PvP = "pvp", PetBattle = "petbattle", Dungeon = "dungeon", Raid = "raid",
	WorldBoss = "worldboss",
}) do
	local value = Enum.QuestTagType and Enum.QuestTagType[enumKey]
	if value then
		TYPES[value] = typeKey
	end
end

local REQUEST_EVERY = 5 -- seconds between load requests for one quest
local MAX_REQUESTS = 6 -- then the quest shows "rewards unknown"
local RETRY_FAILED = 120 -- seconds before a quest that gave up is tried again
local EXPIRY_SLACK = 120 -- seconds of drift allowed before a cached quest counts as a new one

local static = {} -- [questID] = what never changes: title, tags, raw rewards (once loaded)

function ns.WQ_Forget(questID)
	static[questID] = nil
end

function ns.WQ_ClearCache()
	wipe(static)
end

-- Static parts -----------------------------------------------------------------------------------------------------

local function Title(questID)
	local title = C_TaskQuest.GetQuestInfoByQuestID(questID)
	if not title or title == "" then
		title = C_QuestLog.GetTitleForQuestID(questID)
	end
	return title ~= "" and title or nil
end

local function ReadTags(s, questID)
	local tag = C_QuestLog.GetQuestTagInfo(questID)
	if not tag then
		return
	end
	s.type = tag.worldQuestType and TYPES[tag.worldQuestType]
	s.elite = tag.isElite == true
	s.quality = tag.quality
	s.skillLine = tag.tradeskillLineID
	if s.type == "profession" and s.skillLine then
		local name = C_TradeSkillUI.GetTradeSkillDisplayName(s.skillLine)
		s.profession = name ~= "" and name or nil
	end
end

local function IsGear(itemID)
	local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
	return (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
		and equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- Raw items; false while one hasn't loaded (asks for it).
local function ReadItems(questID)
	local items = {}
	for i = 1, GetNumQuestLogRewards(questID) or 0 do
		local name, icon, count, quality, _, itemID, itemLevel = GetQuestLogRewardInfo(i, questID)
		if not itemID then
			return false
		end
		local link = GetQuestLogItemLink("reward", i, questID)
		if not link or not name then
			C_Item.RequestLoadItemDataByID(itemID)
			return false
		end
		local gear = IsGear(itemID)
		items[#items + 1] = {
			index = i, name = name, icon = icon, count = count, quality = quality, itemID = itemID, link = link,
			gear = gear, ilvl = gear and (C_Item.GetDetailedItemLevelInfo(link) or itemLevel) or nil,
		}
	end
	return items
end

local function FactionName(factionID)
	local major = C_MajorFactions.GetMajorFactionData(factionID)
	if major and major.name then
		return major.name
	end
	local data = C_Reputation.GetFactionDataByID(factionID)
	return data and data.name or nil
end

-- Currencies that grant reputation count as reputation (as in Blizzard's world quest filter).
local function ReadCurrencies(questID)
	local currencies, reps = {}, {}
	for _, c in ipairs(C_QuestLog.GetQuestRewardCurrencies(questID) or {}) do
		local factionID = C_CurrencyInfo.GetFactionGrantedByCurrency(c.currencyID)
		if factionID then
			reps[#reps + 1] = { factionID = factionID, name = FactionName(factionID) or c.name, amount = c.totalRewardAmount }
		else
			currencies[#currencies + 1] = { id = c.currencyID, name = c.name, icon = c.texture, amount = c.totalRewardAmount }
		end
	end
	for _, r in ipairs(C_QuestLog.GetQuestLogMajorFactionReputationRewards(questID) or {}) do
		reps[#reps + 1] = { factionID = r.factionID, name = FactionName(r.factionID) or "Reputation", amount = r.rewardAmount }
	end
	return currencies, reps
end

-- Each load request fires QUEST_LOG_UPDATE, which redraws the tab: ask at most every REQUEST_EVERY seconds per
-- quest, and give up (failed) after MAX_REQUESTS.
local function MayRequest(s)
	local now = GetTime()
	if s.lastRequest and now - s.lastRequest < REQUEST_EVERY then
		return false
	end
	s.lastRequest = now
	s.requests = (s.requests or 0) + 1
	if s.requests > MAX_REQUESTS then
		s.failed = true
		return false
	end
	return true
end

-- A quest ID that comes back later can carry other rewards: a fresh read when it now ends later than it did.
local function Expired(s, seconds)
	return s.expires ~= nil and seconds ~= nil and seconds > 0 and GetTime() + seconds > s.expires + EXPIRY_SLACK
end

local function Static(questID, seconds)
	local s = static[questID]
	if s and s.loaded and not Expired(s, seconds) then
		if s.titleFallback then
			local title = Title(questID)
			if title then
				s.title, s.titleFallback = title, nil
			end
		end
		return s
	end
	if s and s.loaded then
		s = nil
	end
	s = s or { id = questID }
	static[questID] = s
	if s.failed then
		if GetTime() - s.lastRequest < RETRY_FAILED then
			return s
		end
		s.failed, s.requests = nil, 0
	end
	if not HaveQuestData(questID) then
		if MayRequest(s) then
			C_QuestLog.RequestLoadQuestByID(questID)
		end
		return s
	end
	s.title = Title(questID)
	if s.tagged == nil then
		ReadTags(s, questID)
		s.tagged = true
	end
	if not HaveQuestRewardData(questID) then
		if MayRequest(s) then
			C_TaskQuest.RequestPreloadRewardData(questID)
		end
		return s
	end
	local items = ReadItems(questID)
	if not items then
		MayRequest(s) -- counts toward giving up; ReadItems already asked for the item
		return s
	end
	s.items = items
	s.money = GetQuestLogRewardMoney(questID) or 0
	s.xp = GetQuestLogRewardXP(questID) or 0
	s.currencies, s.reps = ReadCurrencies(questID)
	if not s.title then
		-- Rewards are in but the title isn't: ask again within the retry budget, then show it as "Quest <id>"
		-- rather than keep the tab loading forever.
		if MayRequest(s) then
			C_QuestLog.RequestLoadQuestByID(questID)
			return s
		end
		if not s.failed then
			return s
		end
		s.failed = nil
		s.title, s.titleFallback = "Quest " .. questID, true
	end
	s.loaded = true
	s.expires = seconds and seconds > 0 and GetTime() + seconds or nil
	return s
end

-- Live parts -------------------------------------------------------------------------------------------------------

-- "mount" | "pet" | "toy" when the item teaches one you don't have.
local function MissingCollectible(itemID)
	local mountID = C_MountJournal.GetMountFromItem(itemID)
	if mountID then
		local isCollected = select(11, C_MountJournal.GetMountInfoByID(mountID))
		return not isCollected and "mount" or nil
	end
	local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
	if speciesID then
		return (C_PetJournal.GetNumCollectedInfo(speciesID) or 0) == 0 and "pet" or nil
	end
	if C_ToyBox.GetToyInfo(itemID) then
		return not PlayerHasToy(itemID) and "toy" or nil
	end
	return nil
end

-- An appearance this character can collect and the account doesn't have.
local function MissingAppearance(link)
	local _, sourceID = C_TransmogCollection.GetItemInfo(link)
	if not sourceID then
		return false
	end
	local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
	if not info or info.appearanceIsCollected then
		return false
	end
	local _, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
	return canCollect == true
end

local function Capped(currencyID)
	local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	if not info then
		return false
	end
	local have = info.useTotalEarnedForMaxQty and info.totalEarned or info.quantity
	if (info.maxQuantity or 0) > 0 and (have or 0) >= info.maxQuantity then
		return true
	end
	return (info.maxWeeklyQuantity or 0) > 0 and (info.quantityEarnedThisWeek or 0) >= info.maxWeeklyQuantity
end

local function MaxRenown(factionID)
	return factionID ~= nil and C_MajorFactions.GetMajorFactionData(factionID) ~= nil
		and C_MajorFactions.HasMaximumRenown(factionID) == true
end

local function KnownSkill(skillLine)
	return skillLine ~= nil and C_SpellBook.GetSkillLineIndexByID(skillLine) ~= nil
end

-- A fresh record (Data.lua's shape) for a quest; the static part is shared, item tables are copied. gearCtx is
-- ns.Gear_Context(), built once per scan.
function ns.WQ_ReadQuest(questID, zoneID, zoneName, gearCtx)
	local seconds = GetQuestTimeLeftSeconds(questID)
	local s = Static(questID, seconds)
	local q = {
		id = questID, title = s.title or ("Quest " .. questID), zoneID = zoneID, zone = zoneName,
		seconds = seconds, type = s.type, elite = s.elite, quality = s.quality,
		profession = s.profession, knownSkill = s.type == "profession" and KnownSkill(s.skillLine) or nil,
		loaded = s.loaded == true, failed = s.failed, money = s.money or 0, xp = s.xp or 0, items = {},
		currencies = {}, reps = {},
	}
	if not q.loaded then
		return q
	end
	for _, raw in ipairs(s.items) do
		local item = {}
		for k, v in pairs(raw) do
			item[k] = v
		end
		item.collectible = MissingCollectible(raw.itemID)
		if raw.gear then
			item.appearance = MissingAppearance(raw.link)
			if gearCtx then
				item.verdict, item.headline, item.headlineColor = ns.Gear_Verdict(raw.link, gearCtx)
			end
		end
		q.items[#q.items + 1] = item
	end
	for _, c in ipairs(s.currencies) do
		q.currencies[#q.currencies + 1] = { id = c.id, name = c.name, icon = c.icon, amount = c.amount, capped = Capped(c.id) }
	end
	for _, r in ipairs(s.reps) do
		q.reps[#q.reps + 1] = { factionID = r.factionID, name = r.name, amount = r.amount, max = MaxRenown(r.factionID) }
	end
	return q
end

-- Maps -------------------------------------------------------------------------------------------------------------

local function Wanted(info)
	return C_QuestLog.IsWorldQuest(info.questID) and not C_QuestLog.IsQuestFlaggedCompleted(info.questID)
end

-- The zone a quest belongs to, nil when the game doesn't say.
local function QuestZone(questID)
	local zoneID = C_TaskQuest.GetQuestZoneID(questID)
	return zoneID and (ns.MapTabs_ResolveMap(zoneID)) or nil
end

-- mapID is zoneID or one of its child maps (a city inside a zone).
local function IsWithin(mapID, zoneID)
	local depth = 0
	while mapID and mapID > 0 and depth < 10 do
		if mapID == zoneID then
			return true
		end
		local info = C_Map.GetMapInfo(mapID)
		mapID, depth = info and info.parentMapID, depth + 1
	end
	return false
end

-- Adds the zone's own world quests (GetQuestsOnMap also returns neighbours near the edge), named by their own zone.
local function AddZone(quests, seen, zoneID, zoneName, gearCtx)
	for _, info in ipairs(C_TaskQuest.GetQuestsOnMap(zoneID) or {}) do
		local id = info.questID
		if id and not seen[id] and Wanted(info) then
			local home = QuestZone(id)
			if home == nil or IsWithin(home, zoneID) then
				seen[id] = true
				local homeInfo = home and home ~= zoneID and C_Map.GetMapInfo(home)
				quests[#quests + 1] = ns.WQ_ReadQuest(id, home or zoneID, homeInfo and homeInfo.name or zoneName, gearCtx)
			end
		end
	end
end

-- quests, mapName, kind ("zone" | "continent"), mapID, pending (quests still loading); nil for world/cosmic maps.
function ns.WQ_ForMap(viewedMapID)
	local mapID, info, kind = ns.MapTabs_ResolveMap(viewedMapID)
	if not mapID then
		return nil
	end
	local quests, seen = {}, {}
	local gearCtx = ns.Gear_Context()
	if kind == "continent" then
		for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, true) or {}) do
			AddZone(quests, seen, child.mapID, child.name, gearCtx)
		end
	else
		AddZone(quests, seen, mapID, info.name, gearCtx)
	end
	local pending = 0
	for _, q in ipairs(quests) do
		if not q.loaded and not q.failed then
			pending = pending + 1
		end
	end
	return quests, info.name, kind, mapID, pending
end

-- XP-only rewards are worthless only at the account's level cap (not the content expansion's: a Midnight owner's 80
-- still levels), so this stays on GetMaxLevelForPlayerExpansion.
function ns.WQ_MaxLevel()
	return UnitLevel("player") >= GetMaxLevelForPlayerExpansion()
end
