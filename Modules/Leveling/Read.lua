local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): reads the game into plain tables for Data.lua and the page. Every API here is
-- from Blizzard's own Forever UI; values that can be secret in combat are checked before use. Registered in Leveling.lua.

local BAR_SLOTS = 120 -- the action bars' slots; Blizzard's stance and possess bars above it hold no reagent spells
local WEAPON_SLOTS = { 16, 17, 18 } -- main hand, off hand, ranged
local SKILL_GAP = 5 -- weapon skills this far under their cap are listed; Gear Check warns from further behind
local LAST_CARRIED_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear
local MAP_CONTINENT = 2 -- Enum.UIMapType.Continent: quest spots are read up to here (cosmic and world maps above it)
local AREA_W, AREA_H = 1002, 668 -- the quest area frame's size (any size; the measured one, the map canvas's shape)
local AREA_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside" -- needed before it answers (see QuestsInArea)
local AREA_FILL_ALPHA = 128 -- of 255, as the map's own quest areas (QuestBlobPinMixin:OnLoad)

local IsSecret = ns.IsSecret
local Readable = ns.Readable

-- Your spellbook's skill line names (General, then your class's lines), for telling your class trainer apart.
local function SpellBookLines()
	local names = {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
		return names
	end
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and info.name then
			names[#names + 1] = info.name
		end
	end
	return names
end

-- The class trainer's rows, or nil at another kind of trainer (trade, pet, riding, weapons) or when it's listing
-- nothing. Second return: whether its "not available yet" rows are showing (its own filter), so later levels are in
-- the list.
function ns.LevelingRead_Trainer()
	if C_Trainer.GetTrainerType() ~= Enum.TrainerType.General then
		return nil
	end
	local total = GetNumTrainerServices()
	if not total or total == 0 then
		return nil
	end
	local lines = {}
	for i = 1, total do
		local line = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(i)
		if line then
			lines[#lines + 1] = line
		end
	end
	if not ns.Leveling_IsClassTrainer(lines, SpellBookLines()) then
		return nil
	end
	local rows = {}
	for i = 1, total do
		local name, serviceType, _, level, rank = GetTrainerServiceInfo(i)
		local row = ns.Leveling_SlimService(name, serviceType, rank, level, (GetTrainerServiceCost(i)))
		if row then
			rows[#rows + 1] = row
		end
	end
	return rows, GetTrainerServiceTypeFilter("unavailable") == true
end

-- The spells on the action bars: { { spellID, name, subtext, highest, consumable, count } }.
function ns.LevelingRead_Bars()
	local list = {}
	for slot = 1, BAR_SLOTS do
		if C_ActionBar.HasAction(slot) then
			local kind, id = GetActionInfo(slot)
			if kind == "spell" and id and not IsSecret(id) then
				local count = C_ActionBar.GetActionUseCount(slot)
				list[#list + 1] = {
					spellID = id,
					name = C_Spell.GetSpellName(id),
					subtext = C_Spell.GetSpellSubtext(id),
					highest = C_ActionBar.IsHighestSpellRank(id),
					consumable = C_ActionBar.IsConsumableAction(slot),
					count = not IsSecret(count) and count or nil,
				}
			end
		end
	end
	return list
end

function ns.LevelingRead_UnspentTalents()
	return C_SpecializationInfo.HasPlayerEarnedATalentPoint() and C_ClassTalents.HasUnspentTalentPoints() or false
end

-- Whether this character uses ammo right now, how much it has, its ranged weapon's subclass.
function ns.LevelingRead_Ammo()
	if not (UnitUsesAmmo("player") and C_PaperDollInfo.AmmoNeeded()) then
		return false, 0, nil
	end
	-- pcall: the API errors on a slot name the client doesn't know.
	local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
	local count = ok and slot and GetInventoryItemCount("player", slot) or 0
	if not ns.Leveling_CaresAboutAmmo(select(2, UnitClass("player")), count > 0) then
		return false, 0, nil
	end
	local rangedOK, ranged = pcall(GetInventorySlotInfo, "RangedSlot")
	local weapon = rangedOK and ranged and GetInventoryItemID("player", ranged)
	local subclass = weapon and select(7, C_Item.GetItemInfoInstant(weapon))
	return true, count, subclass
end

-- For Leveling_AmmoState: whether the slot's ammo goes with this weapon (nil for an empty slot), and the best ammo in
-- your bags that does and isn't in the slot ({ name, count, countText }, or nil).
function ns.LevelingRead_AmmoFit(weapon)
	local equipped = ns.LevelingRead_AmmoSlot()
	local fits = equipped and ns.LevelingRead_ItemFits(equipped, weapon) or nil
	for _, t in ipairs(ns.Leveling_AmmoTypes(ns.LevelingRead_AmmoCarried(), weapon, UnitLevel("player"))) do
		if t.fits and t.itemID ~= equipped and t.count > 0 then
			return fits, { name = t.name, count = t.count, countText = ns.Thousands(t.count) }
		end
	end
	return fits, nil
end

-- The ammo in its slot: name (nil until the item has loaded) and icon, or nothing when the slot is empty.
function ns.LevelingRead_AmmoItem()
	local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
	local itemID = ok and slot and GetInventoryItemID("player", slot)
	if not itemID then
		return nil, nil
	end
	return (C_Item.GetItemInfo(itemID)), GetInventoryItemTexture("player", slot)
end

-- Armor kits ------------------------------------------------------------------------------------------------------------

local function KitList()
	return ns.Content_Get(ns.CONTENT_FOREVER, "armorKits") or {}
end

function ns.LevelingRead_IsKit(itemID)
	for _, id in ipairs(KitList()) do
		if id == itemID then
			return true
		end
	end
	return false
end

-- The kits in your bags, best first, for Leveling_KitPlan.
local function CarriedKits()
	local kits = {}
	for _, itemID in ipairs(KitList()) do
		local count = C_Item.GetItemCount(itemID)
		if count > 0 then
			local name, _, _, _, minLevel = C_Item.GetItemInfo(itemID)
			kits[#kits + 1] = { itemID = itemID, name = name, count = count, minLevel = minLevel }
		end
	end
	return kits
end

-- What you wear where a kit fits: { { slot, label, name, link } }.
function ns.LevelingRead_KitGear()
	local gear = {}
	for _, place in ipairs(ns.LEVELING_KIT_SLOTS) do
		local link = GetInventoryItemLink("player", place.slot)
		if link then
			gear[#gear + 1] = { slot = place.slot, label = place.label, link = link,
				name = C_Item.GetItemNameByID(GetInventoryItemID("player", place.slot)) }
		end
	end
	return gear
end

function ns.LevelingRead_KitPlan()
	return ns.Leveling_KitPlan(CarriedKits(), ns.LevelingRead_KitGear(), UnitLevel("player"))
end

-- The item in the ammo slot, nil when it's empty.
function ns.LevelingRead_AmmoSlot()
	local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
	return ok and slot and GetInventoryItemID("player", slot) or nil
end

function ns.LevelingRead_ItemFits(itemID, weaponSubclass)
	local _, _, _, _, _, _, subclassID = C_Item.GetItemInfoInstant(itemID)
	return ns.Leveling_AmmoFitsWeapon(subclassID, weaponSubclass)
end

-- All the ammo in your bags, one entry per slot, for Leveling_AmmoTypes.
function ns.LevelingRead_AmmoCarried()
	local items = {}
	for bag = 0, LAST_CARRIED_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
				if ns.Leveling_IsAmmo(classID) then
					local name, _, _, itemLevel, minLevel = C_Item.GetItemInfo(info.itemID)
					items[#items + 1] = { itemID = info.itemID, name = name, count = info.stackCount, subclassID = subclassID,
						minLevel = minLevel, itemLevel = itemLevel }
				end
			end
		end
	end
	return items
end

-- What the open merchant sells, for Leveling_PickAmmo. Items with another price than gold aren't offered. maxStack is how
-- many fit in a bag slot, maxBuy how many one purchase can buy.
function ns.LevelingRead_Merchant()
	local items = {}
	for i = 1, GetMerchantNumItems() do
		local info = C_MerchantFrame.GetItemInfo(i)
		local link = GetMerchantItemLink(i)
		if info and link and info.isPurchasable and not info.hasExtendedCost then
			local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
			local _, _, _, _, minLevel, _, _, maxStack = C_Item.GetItemInfo(link)
			local stack = info.stackCount or 1
			items[#items + 1] = {
				index = i, itemID = itemID, name = info.name, icon = info.texture, classID = classID, subclassID = subclassID,
				price = info.price, stack = stack, available = info.numAvailable, usable = info.isUsable,
				minLevel = minLevel, maxStack = maxStack or stack, maxBuy = GetMerchantItemMaxStack(i),
			}
		end
	end
	return items
end

-- The carried bags that take this ammo, for Leveling_AmmoRoom: { { family, free, topUp } }.
function ns.LevelingRead_AmmoBags(item)
	local bags = {}
	local itemFamily = C_Item.GetItemFamily(item.itemID)
	for bag = 0, LAST_CARRIED_BAG do
		local free, family = C_Container.GetContainerNumFreeSlots(bag)
		if ns.Bags_BagTakes(family, itemFamily) then
			local topUp = 0
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID == item.itemID then
					topUp = topUp + math.max(item.maxStack - info.stackCount, 0)
				end
			end
			bags[#bags + 1] = { family = family, free = free or 0, topUp = topUp }
		end
	end
	return bags
end

-- The quest log: { { questID, title, level, difficulty, elite, complete, timeLeft, xp, zone, tagID, watched, active } }.
-- xp is 0 until the game has the quest's rewards; zone is the heading it's under (a zone, or a dungeon's name for its
-- quests); tagID is its Enum.QuestTag (dungeon, raid, group) or nil; watched: it's on the objective tracker; active: it's
-- Tomte's active quest (ns.ActiveQuest_ID: the one follow-the-nearest follows, else the game's super-tracked quest).
function ns.LevelingRead_Quests()
	local list = {}
	local active = ns.ActiveQuest_ID()
	local heading
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader then
			heading = info.title
		elseif info and not info.isHidden and info.questID then
			local id = info.questID
			local total, elapsed = C_QuestLog.GetTimeAllowed(id)
			local xp = GetQuestLogRewardXP(id)
			local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(id)
			-- The quest's usable item, as the game's tracker shows it (Blizzard_ObjectiveTrackerShared.lua).
			local itemLink, itemIcon, itemCharges, itemWhenDone
			if GetQuestLogSpecialItemInfo then
				itemLink, itemIcon, itemCharges, itemWhenDone = GetQuestLogSpecialItemInfo(i)
			end
			list[#list + 1] = {
				logIndex = i,
				itemLink = itemLink,
				itemIcon = itemIcon,
				itemCharges = itemCharges,
				itemWhenDone = itemWhenDone and true or false, -- the item still shows once the quest is done
				tagID = tag and tag.tagID,
				xp = xp and not IsSecret(xp) and xp or 0,
				questID = id,
				title = info.title,
				level = info.difficultyLevel or info.level,
				difficulty = C_PlayerInfo.GetContentDifficultyQuestForPlayer(id),
				elite = C_QuestLog.IsEliteQuest(id),
				complete = C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id),
				timeLeft = total and elapsed and total > elapsed and total - elapsed or nil,
				zone = heading,
				watched = C_QuestLog.GetQuestWatchType(id) ~= nil,
				active = id == active,
			}
		end
	end
	return list
end

-- The quest log with each quest's dungeon (Leveling_QuestDungeon). Second return: Forever's dungeon list.
function ns.LevelingRead_QuestsTagged()
	local quests = ns.LevelingRead_Quests()
	local dungeons = ns.Content_Get(ns.CONTENT_FOREVER, "dungeons") or {}
	for _, q in ipairs(quests) do
		q.dungeon = ns.Leveling_QuestDungeon(q, dungeons)
	end
	return quests, dungeons
end

-- Quest places -----------------------------------------------------------------------------------------------------

local zoneNames = {} -- [uiMapID] = name

local function ZoneName(mapID)
	if zoneNames[mapID] == nil then
		local info = C_Map.GetMapInfo(mapID)
		zoneNames[mapID] = info and info.name or false
	end
	return zoneNames[mapID] or nil
end

-- A spot on a map as world yards: { x, y, continent }, or nil where the map has no world position.
local function WorldPoint(mapID, x, y)
	local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not (continent and pos) then
		return nil
	end
	local wx, wy = pos:GetXY()
	return { x = wx, y = wy, continent = continent }
end

-- Where you stand, as world yards ({ x, y, continent }), and your map. Nil in instances, where the game gives no
-- position (warcraft.wiki.gg API_C_Map.GetPlayerMapPosition).
function ns.LevelingRead_You()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or not Readable(mapID) then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil, mapID
	end
	local x, y = pos:GetXY()
	if not (Readable(x) and Readable(y)) or (x == 0 and y == 0) then
		return nil, mapID
	end
	return WorldPoint(mapID, x, y), mapID
end

-- Where a quest is handed in, as world yards ({ x, y, continent }), from the generated data (Data/Forever/QuestEnds.lua),
-- or false when it isn't known or its zone has no map here. Kept: the data doesn't change.
local handPoints = {}

function ns.LevelingRead_HandPoint(questID)
	local known = handPoints[questID]
	if known ~= nil then
		return known
	end
	local ends = ns.Content_Get(ns.CONTENT_FOREVER, "questEnds")
	local area, x, y = (ends and ends[questID] or ""):match("^(%d+):([%d%.]+):([%d%.]+)$")
	local mapID = area and ns.MapForArea(tonumber(area))
	local point = mapID and WorldPoint(mapID, tonumber(x) / 100, tonumber(y) / 100) or false
	handPoints[questID] = point
	return point
end

-- The quests whose map area you stand in: [questID] = true (empty without a position). One hidden QuestPOIFrame of
-- ours (never the map's own) draws each quest's area in turn and asks whether your spot is inside, the way the map's
-- quest areas answer the mouse (QuestBlobPinMixin:UpdateTooltip). Measured on Forever 1.60.1 (2026-11-14): it answers
-- right after DrawBlob, but only once the frame has a fill texture and a size; without them every answer was nil.
local areaFrame

function ns.LevelingRead_QuestsInArea()
	local inside = {}
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or not Readable(mapID) or not C_QuestLog.GetQuestsOnMap then
		return inside
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if pos then
		x, y = pos:GetXY()
	end
	if not (Readable(x) and Readable(y)) or (x == 0 and y == 0) then
		return inside
	end
	if not areaFrame then
		areaFrame = CreateFrame("QuestPOIFrame", nil, UIParent)
		areaFrame:SetSize(AREA_W, AREA_H)
		areaFrame:SetPoint("CENTER")
		areaFrame:SetFillTexture(AREA_FILL)
		areaFrame:SetFillAlpha(AREA_FILL_ALPHA)
		areaFrame:EnableMouse(false)
		areaFrame:SetAlpha(0) -- never seen: it only answers where the areas are
	end
	areaFrame:SetMapID(mapID)
	for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
		local id = info.questID
		if id and Readable(id) then
			areaFrame:DrawNone()
			areaFrame:DrawBlob(id, true)
			local hit = areaFrame:UpdateMouseOverTooltip(x, y)
			if hit and Readable(hit) then
				inside[id] = true
			end
		end
	end
	areaFrame:DrawNone()
	return inside
end

-- Each quest's spot, as the map shows it (its objective, or where it's turned in): [questID] = { x, y (world yards),
-- continent, zone }. Read from your map and the maps above it up to the continent; your zone's map also lists the
-- quests of the zones around it, each with its own map (measured on Forever, 2026-11-08). A quest's x, y are on the map
-- that was asked, as Blizzard's quest pins place them.
-- The world points already worked out: [mapID][questID] = point, with the map spot it came from (mx, my). The quest log
-- changes many times a fight (every kill credit) and three readers (Quest list, its minimap, Next quests) read again
-- each time, while a quest's spot rarely moves: an unmoved spot reuses its point instead of making two vectors and a
-- table (the minimap's 7 MB of garbage and slow frames in a questing report, 2026-11-21). Points are shared: read-only.
local pointCache = {}

local function CachedPoint(mapID, questID, x, y)
	local byQuest = pointCache[mapID]
	if not byQuest then
		byQuest = {}
		pointCache[mapID] = byQuest
	end
	local p = byQuest[questID]
	if p and p.mx == x and p.my == y then
		return p
	end
	p = WorldPoint(mapID, x, y)
	if p then
		p.mx, p.my = x, y
	end
	byQuest[questID] = p
	return p
end

function ns.LevelingRead_QuestPoints(mapID)
	local points, seen = {}, {}
	while mapID and not seen[mapID] do
		seen[mapID] = true
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
			if info.questID and not points[info.questID] and info.x and info.y then
				local p = CachedPoint(mapID, info.questID, info.x, info.y)
				if p then
					p.zone = ZoneName(info.mapID or mapID)
					points[info.questID] = p
				end
			end
		end
		local map = C_Map.GetMapInfo(mapID)
		if not map or map.mapType <= MAP_CONTINENT then
			break
		end
		mapID = map.parentMapID
	end
	return points
end

-- Your professions: { { name, skill, max } }.
function ns.LevelingRead_Professions()
	local list = {}
	for _, index in pairs({ GetProfessions() }) do
		local name, _, skill, max = GetProfessionInfo(index)
		if name and skill and max then
			list[#list + 1] = { name = name, skill = skill, max = max }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- How many mounts this character has (only "none or some" matters: the mount fund stops at the first). Once one is
-- found it stays found for the session.
local hasMount = false
function ns.LevelingRead_Mounts()
	if hasMount then
		return 1
	end
	for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
		local isCollected = select(11, C_MountJournal.GetMountInfoByID(id))
		if isCollected then
			hasMount = true
			return 1
		end
	end
	return 0
end

-- This character's gold per hour over its kept sessions (Session recap's history), or nil without any.
local function GoldPerHour()
	local recap = ns.recapDB
	if not (recap and recap.history and ns.Recap_HistoryFilter) then
		return nil
	end
	local t = ns.Recap_HistoryTotals(ns.Recap_HistoryFilter(recap.history, "char", UnitGUID("player")))
	return t.count > 0 and t.perHour or nil
end

-- The mount fund (Leveling_MountFund) and its words: fund, "47g of 100g", "10h 36m" (nil without a pace).
local function MountFund(db, level)
	local fund = ns.Leveling_MountFund(GetMoney(), db.mountGoal, level, ns.LevelingRead_Mounts(), GoldPerHour())
	if not fund then
		return nil
	end
	local text = ("%s of %s"):format(ns.CoinPart(math.floor(fund.have / 10000), "g"),
		ns.CoinPart(math.floor(fund.goal / 10000), "g"))
	local hours = fund.hours and ns.Recap_Duration and ns.Recap_Duration(math.floor(fund.hours * 3600)) or nil
	return fund, text, hours
end

-- The weapon skills this character has: { { name, rank, max, worn } }.
function ns.LevelingRead_Skills()
	local worn = {}
	for _, slot in ipairs(WEAPON_SLOTS) do
		local id = GetInventoryItemID("player", slot)
		local subclass = id and select(7, C_Item.GetItemInfoInstant(id))
		if subclass then
			worn[subclass] = true
		end
	end
	local list = {}
	for subclass, skill in pairs(ns.GearForever_WeaponSkills()) do
		list[#list + 1] = { name = skill.name, rank = skill.rank, max = skill.max, worn = worn[subclass] == true }
	end
	return list
end

-- Everything the page and the Home section draw, read fresh each time: { level, atCap, xp (Leveling_XPView), todo, fine,
-- nextLevel, upcoming (trainer rows), skills, questCount, groups (Leveling_SortQuests) }.
function ns.LevelingRead_State()
	local db = ns.Leveling_DB()
	local level = UnitLevel("player")
	local char = db.chars[UnitGUID("player")]
	local services = char and char.services
	local ready, nextLevel, upcoming = ns.Leveling_TrainerSplit(services, level)
	local bars = ns.LevelingRead_Bars()
	local quests, dungeons = ns.LevelingRead_QuestsTagged()
	local groups = ns.Leveling_SortQuests(quests)
	local needs, count, weapon = ns.LevelingRead_Ammo()
	local ammoFits, ammoSpare
	if needs then
		ammoFits, ammoSpare = ns.LevelingRead_AmmoFit(weapon)
	end
	local mount, mountText, mountHours = MountFund(db, level)
	local todo, fine = ns.Leveling_Checklist({
		professions = ns.Leveling_ProfessionRanks(ns.LevelingRead_Professions(), level),
		dungeons = ns.Leveling_DungeonsNear(dungeons, level, quests),
		mount = mount, mountText = mountText, mountHours = mountHours,
		visited = services ~= nil,
		ready = ready,
		talents = ns.LevelingRead_UnspentTalents(),
		oldRanks = ns.Leveling_OldRanks(bars),
		reagents = ns.Leveling_LowReagents(bars, db.reagentLow),
		ammoState = ns.Leveling_AmmoState(needs, count, db.ammoLow, ammoFits, ammoSpare),
		ammoText = ns.Thousands(count),
		ammoSpare = ammoSpare,
		turnIns = groups.done,
		kit = db.armorKit and ns.LevelingRead_KitPlan() or nil,
	})
	local turnIn = 0
	for _, q in ipairs(groups.done) do
		turnIn = turnIn + q.xp
	end
	local atCap = level >= GameRulesUtil.GetEffectiveMaxLevelForPlayer()
	return {
		level = level,
		atCap = atCap,
		xp = not atCap and ns.Leveling_XPView(UnitXP("player"), UnitXPMax("player"), GetXPExhaustion(), turnIn) or nil,
		todo = todo,
		fine = fine,
		nextLevel = nextLevel,
		upcoming = upcoming,
		skills = ns.Leveling_SkillsBehind(ns.LevelingRead_Skills(), SKILL_GAP),
		questCount = #quests,
		groups = groups,
	}
end
