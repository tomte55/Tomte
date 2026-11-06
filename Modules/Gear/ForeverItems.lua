local addonName, ns = ...

-- Gear Check on World of Warcraft: Forever: reads items into the descriptors ForeverRules.lua judges and keeps the worn
-- snapshot. Registered in Forever.lua. Items the client hasn't cached return nil and are asked for; the module's
-- GET_ITEM_INFO_RECEIVED handler judges again once they arrive.

local BAGS = { 0, 1, 2, 3, 4 } -- backpack and the four bags
local WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 } -- no shirt or tabard
local MAX_CACHE = 1000
-- Red lines ("Requires Level 20", a weapon type not trained yet) change with the character: an item with one is kept
-- only this many seconds.
local RED_TTL = 5

local Secret = ns.IsSecret

local cache, cacheSize = {}, 0
local worn -- slot -> descriptor; nil when it has to be read again

-- Events shared by this module's files: RewardCard.lua takes this bus at file load.
ns.Gear_Events = ns.NewEvents()

-- Forever's ranged slot, nil on a client without one. pcall: the API errors on a slot name the client doesn't know.
local function RangedSlot()
	local ok, slot = pcall(GetInventorySlotInfo, "RangedSlot")
	return ok and slot or nil
end
ns.GearForever_RangedSlot = RangedSlot

-- [weapon subclass] = { name, rank, max } for the weapon skills this character has. Weapons with no entry aren't trained,
-- which the item's own red tooltip line says.
function ns.GearForever_WeaponSkills()
	local skills = {}
	for subclass, skillID in pairs(ns.GEARFOREVER_WEAPON_SKILLS) do
		local info = C_SkillInfo.GetSkillLineInfoByID(skillID)
		if info and info.maxRank and info.maxRank > 0 then
			skills[subclass] = { name = info.name, rank = info.rank or 0, max = info.maxRank }
		end
	end
	return skills
end

-- Blizzard's red (RED_FONT_COLOR 1, 0.125, 0.125): something about the item the player can't use.
local function IsRed(color)
	return color and color.r and not Secret(color.r) and color.r > 0.9 and color.g < 0.3 and color.b < 0.3
end

-- Patterns are built on first use: every Blizzard string is there by then.
local dpsPattern, durabilityPattern
local function ReadTooltip(desc, link)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
		return
	end
	dpsPattern = dpsPattern or (DPS_TEMPLATE and ns.Gear_FormatPattern(DPS_TEMPLATE))
	durabilityPattern = durabilityPattern or (DURABILITY_TEMPLATE and ns.Gear_FormatPattern(DURABILITY_TEMPLATE, true))
	local data = C_TooltipInfo.GetHyperlink(link)
	for i, line in ipairs(data and data.lines or {}) do
		local text, right = line.leftText, line.rightText
		if text and not Secret(text) and text ~= "" then
			desc.unique = desc.unique or ns.Gear_ParseUnique(text)
			desc.dps = desc.dps or ns.GearForever_ParseDps(text, dpsPattern)
			-- Line 1 is the name; a broken item (red durability) is still usable gear.
			if i > 1 and IsRed(line.leftColor) and not (durabilityPattern and text:find(durabilityPattern)) then
				desc.redText = desc.redText or text
			end
		end
		if right and not Secret(right) and right ~= "" and IsRed(line.rightColor) then
			desc.redText = desc.redText or right
		end
	end
end

-- nil while the item isn't loaded (and asks for it).
function ns.GearForever_Describe(link)
	if not link or Secret(link) then
		return nil
	end
	local held = cache[link]
	if held then
		if not (held.redText and GetTime() - held.readAt > RED_TTL) then
			return held
		end
		cache[link] = nil
		cacheSize = cacheSize - 1
	end
	local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
	if not itemID then
		return nil
	end
	local name, _, _, _, minLevel = C_Item.GetItemInfo(link)
	local raw = name and C_Item.GetItemStats(link)
	if not raw then
		if C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return nil
	end
	local stats = ns.Gear_NormalizeStats(raw)
	stats.SPI = raw.ITEM_MOD_SPIRIT_SHORT
	local desc = {
		link = link,
		itemID = itemID,
		equipLoc = equipLoc,
		classID = classID,
		subclassID = subclassID,
		minLevel = minLevel,
		ilvl = C_Item.GetDetailedItemLevelInfo(link),
		stats = stats,
		readAt = GetTime(),
	}
	ReadTooltip(desc, link)
	if cacheSize >= MAX_CACHE then
		wipe(cache)
		cacheSize = 0
	end
	cache[link] = desc
	cacheSize = cacheSize + 1
	return desc
end

-- slot -> descriptor of everything worn; nil until every worn item is loaded.
function ns.GearForever_Worn()
	if worn then
		return worn
	end
	local snapshot = {}
	local function Read(slot)
		local link = GetInventoryItemLink("player", slot)
		if not link then
			return not GetInventoryItemID("player", slot) -- worn, but its link hasn't arrived yet
		end
		snapshot[slot] = ns.GearForever_Describe(link)
		return snapshot[slot] ~= nil
	end
	for _, slot in ipairs(WORN_SLOTS) do
		if not Read(slot) then
			return nil
		end
	end
	local ranged = RangedSlot()
	if ranged and not Read(ranged) then
		return nil
	end
	-- Nothing worn at all is usually a read at login before the inventory arrived: use it, but don't keep it.
	if next(snapshot) then
		worn = snapshot
	end
	return snapshot
end

function ns.GearForever_ForgetWorn()
	worn = nil
end

-- A level up changes the red lines: read everything again.
function ns.GearForever_ForgetAll()
	wipe(cache)
	cacheSize = 0
	worn = nil
end

-- Links of everything equippable in the bags, with where each one is: { { link, bag, slot } }.
function ns.GearForever_BagGear()
	local list = {}
	local ranged = RangedSlot()
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local link = C_Container.GetContainerItemLink(bag, slot)
			local equipLoc = link and not Secret(link) and select(4, C_Item.GetItemInfoInstant(link))
			if equipLoc and ns.GearForever_Slots(equipLoc, ranged) then
				list[#list + 1] = { link = link, bag = bag, slot = slot }
			end
		end
	end
	return list
end
