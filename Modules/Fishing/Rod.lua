local addonName, ns = ...

-- Fishing on World of Warcraft: Forever: a rod has to be in your hands there. Reads the rod and lures for the key's next
-- press (Key.lua, rules in Data.lua), remembers the weapons a rod replaced and puts them back: when you mount, change zone
-- or get pulled, or on a right-click of the fishing button. Forever only: not in the retail TOC.

local MAIN, OFF = 16, 17 -- inventory slots
local MAIN_WEAPON_SLOT = 0 -- Enum.WeaponSlot: what C_Item.GetWeaponEnchantInfo takes
local BAGS = { 0, 1, 2, 3, 4 }
-- Seconds between tries, and how many: a weapon can't be equipped while the game still holds the swap before it.
local RETRY, TRIES = 0.5, 8
local OWNER = "rod"

local db
local events = ns.Fishing_Events
local rods -- rods in the bags { { itemID, ilvl } }, nil until read again after a bag change
local tries = 0
local retrying = false

local IsSecret = ns.IsSecret

local function Saved()
	return db.swap[UnitGUID("player")]
end

local function RodIn(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then
		return false
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return ns.Fishing_IsRod(classID, subclassID)
end

local function ReadRods()
	if rods then
		return rods
	end
	rods = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
				if ns.Fishing_IsRod(classID, subclassID) then
					rods[#rods + 1] = { itemID = info.itemID, ilvl = C_Item.GetDetailedItemLevelInfo(info.hyperlink) }
				end
			end
		end
	end
	return rods
end

-- Anything secret counts as a lure on the rod: no press wasted on a false alarm.
local function LureUp()
	for _, e in ipairs(C_Item.GetWeaponEnchantInfo(MAIN_WEAPON_SLOT)) do
		if IsSecret(e.hasEnchant) or e.hasEnchant then
			return true
		end
	end
	return false
end

-- Adds to the key's situation (see ns.Fishing_NextAction): needsRod and rod, lure and lureUp.
function ns.FishingRod_Situation(s)
	local holding = RodIn(MAIN)
	if not holding then
		if db.rod.equip then
			s.needsRod = true
			s.rod = ns.Fishing_PickRod(ReadRods())
		end
		return
	end
	if db.rod.lure then
		s.lure = ns.Fishing_PickLure(ns.Content_Get(ns.CONTENT_FOREVER, "lures") or {}, function(itemID)
			return C_Item.GetItemCount(itemID) > 0 and C_Item.IsUsableItem(itemID) ~= false
		end)
		s.lureUp = LureUp()
	end
end

-- Just before a press equips the rod: the weapons it's about to replace. Empty hands leave nothing to put back.
function ns.FishingRod_Remember()
	if RodIn(MAIN) then
		return
	end
	local main, off = GetInventoryItemLink("player", MAIN), GetInventoryItemLink("player", OFF)
	db.swap[UnitGUID("player")] = (main or off) and { main = main, off = off } or nil
end

function ns.FishingRod_HasSaved()
	return Saved() ~= nil
end

local function Try()
	retrying = false
	local swap = Saved()
	if not swap then
		return
	end
	-- One weapon per try: the second has to wait for the first swap to finish.
	if swap.main and GetInventoryItemLink("player", MAIN) ~= swap.main then
		C_Item.EquipItemByName(swap.main, MAIN)
	elseif swap.off and GetInventoryItemLink("player", OFF) ~= swap.off then
		C_Item.EquipItemByName(swap.off, OFF)
	else
		db.swap[UnitGUID("player")] = nil
		ns.FishingKey_Refresh()
		return
	end
	tries = tries + 1
	if tries < TRIES then
		retrying = true
		C_Timer.After(RETRY, Try)
	end
end

-- Puts the remembered weapons back. Returns false when there's nothing to put back. A rod no longer in hand means the
-- player changed weapons themselves, and those win.
function ns.FishingRod_PutBack()
	if not Saved() then
		return false
	end
	if retrying then -- under way: with the main weapon back and the off hand to go, no rod in hand is expected
		return true
	end
	if not RodIn(MAIN) then
		db.swap[UnitGUID("player")] = nil
		return false
	end
	tries = 0
	Try()
	return true
end

local function AutoPutBack()
	if db.rod.back then
		ns.FishingRod_PutBack()
	end
end

events:On(OWNER, "BAG_UPDATE_DELAYED", function()
	rods = nil
end)

events:On(OWNER, "PLAYER_MOUNT_DISPLAY_CHANGED", function()
	if IsMounted() then
		AutoPutBack()
	end
end)

events:On(OWNER, "ZONE_CHANGED_NEW_AREA", AutoPutBack)
events:On(OWNER, "PLAYER_REGEN_DISABLED", AutoPutBack) -- the last moment before the lockdown
events:On(OWNER, "PLAYER_REGEN_ENABLED", AutoPutBack) -- if the game refused during the fight

function ns.FishingRod_Init(moduleDB)
	db = moduleDB
end

function ns.FishingRod_Toggle(active)
	if active then
		for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_MOUNT_DISPLAY_CHANGED", "ZONE_CHANGED_NEW_AREA",
			"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
			events:Watch(OWNER, event)
		end
	else
		events:UnwatchAll(OWNER)
		ns.FishingRod_PutBack()
	end
end
