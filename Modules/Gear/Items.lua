local addonName, ns = ...

-- Gear Check item reading: turns an item link into the descriptor Data.lua judges, and keeps the equipped
-- snapshot. Everything here is plain item data (not secret in 12.x), but tooltip text is still checked with
-- issecretvalue before use. Items the client hasn't cached return nil and are requested; ns.GearItems_OnReady
-- (set by Gear.lua) runs once the data has arrived.

local LINE = Enum.TooltipDataLineType
local EFFECT_TYPES = {
	[LINE.ItemSpellTriggerOnUse] = true, [LINE.ItemSpellTriggerOnEquip] = true, [LINE.ItemSpellTriggerOnProc] = true,
}
local GEM_TEXT = LINE.GemSocketEnchantment
local SKIP_RED = { [LINE.ItemName] = true, [LINE.FlavorText] = true, [LINE.ItemSpellTriggerLearn] = true }
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local MAX_CACHE = 1000
local UNREAD_GRACE = 10 -- seconds an item without stats is read again before it's taken as it is
local EFFECT_CHARS = 60

local BAGS = { 0, 1, 2, 3, 4 } -- backpack and the four bags (gear never goes in the reagent bag)

local cache, cacheSize = {}, 0
local equipped -- slot -> descriptor; nil when it has to be rebuilt
local bagGear -- descriptors of the gear in the bags; nil when it has to be rebuilt
local waiting = false -- something we asked for hasn't loaded yet
local unreadSince = {} -- [link] = when it was first read without stats

local function Secret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- Blizzard's red (RED_FONT_COLOR 1, 0.125, 0.125): something about the item the player can't use.
local function IsRed(color)
	return color and color.r and not Secret(color.r) and color.r > 0.9 and color.g < 0.3 and color.b < 0.3
end

local function Short(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if #text > EFFECT_CHARS then
		text = text:sub(1, EFFECT_CHARS - 3) .. "..."
	end
	return text
end

local function ReadTooltip(desc, link)
	local data = C_TooltipInfo.GetHyperlink(link)
	if not data or not data.lines then
		return false
	end
	for _, line in ipairs(data.lines) do
		local text, right = line.leftText, line.rightText
		if text and not Secret(text) and text ~= "" then
			local unique = ns.Gear_ParseUnique(text)
			if unique then
				desc.unique = unique
			elseif EFFECT_TYPES[line.type] then
				desc.effect = desc.effect or Short(text)
			elseif line.type == GEM_TEXT then
				desc.gemStats = ns.Gear_ParseStatText(text, desc.gemStats)
				desc.gemText = desc.gemText or Short(text)
			elseif not SKIP_RED[line.type] and IsRed(line.leftColor) and not text:find("^Durability") then
				desc.redText = desc.redText or Short(text)
			end
		end
		if right and not Secret(right) and right ~= "" and IsRed(line.rightColor) then
			desc.redText = desc.redText or Short(right)
		end
	end
	return true
end

-- nil while the item isn't loaded (and asks for it).
function ns.GearItems_Describe(link)
	if not link or Secret(link) then
		return nil
	end
	if cache[link] then
		return cache[link]
	end
	local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
	if not itemID then
		return nil
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		waiting = true
		return nil
	end
	local raw = C_Item.GetItemStats(ns.Gear_StripLink(link))
	if not raw then
		waiting = true
		return nil
	end
	local enchanted, gems = ns.Gear_LinkInfo(link)
	local desc = {
		link = link,
		itemID = itemID,
		equipLoc = equipLoc,
		classID = classID,
		subclassID = subclassID,
		ilvl = C_Item.GetDetailedItemLevelInfo(link),
		stats = ns.Gear_NormalizeStats(raw),
		enchanted = enchanted,
		gems = gems,
		gemIDs = ns.Gear_LinkGemIDs(link),
		sockets = C_Item.GetItemNumSockets(link) or 0,
		setID = select(16, C_Item.GetItemInfo(link)),
		minLevel = select(5, C_Item.GetItemInfo(link)), -- for other characters (their red level line isn't ours)
	}
	local up = C_Item.GetItemUpgradeInfo(link)
	if up and up.currentLevel and up.maxLevel then
		desc.upgrade = { cur = up.currentLevel, max = up.maxLevel, maxIlvl = up.maxItemLevel, track = up.trackString }
	end
	local specs = C_Item.GetItemSpecInfo and C_Item.GetItemSpecInfo(link)
	if type(specs) == "table" and #specs > 0 then
		desc.specs = {}
		for _, specID in ipairs(specs) do
			desc.specs[specID] = true
		end
	end
	if not ReadTooltip(desc, link) then
		waiting = true
		return nil
	end
	-- No stats at all (not even armor) is usually a read before the item's bonus data arrived: use it, but read it
	-- again next time instead of keeping it.
	-- Some gear really has no stats (cosmetic armor): after UNREAD_GRACE it's kept as it is, or every bag refresh
	-- and every burst of item data would read it again.
	if not next(desc.stats) then
		local now = GetTime()
		unreadSince[link] = unreadSince[link] or now
		if now - unreadSince[link] < UNREAD_GRACE then
			desc.unread = true
			waiting = true
			return desc
		end
	end
	if cacheSize >= MAX_CACHE then
		wipe(cache)
		wipe(unreadSince)
		cacheSize = 0
	end
	cache[link] = desc
	cacheSize = cacheSize + 1
	return desc
end

-- Normalized stats of a gem, nil until it has loaded (and asks for it). GetItemStats first; gems it returns
-- nothing for are read from their tooltip text ("+13 Haste", "+12 Haste and +5 Mastery").
local gemStats = {}
function ns.GearItems_GemStats(itemID)
	if gemStats[itemID] then
		return gemStats[itemID]
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		waiting = true
		return nil
	end
	local stats = ns.Gear_NormalizeStats(C_Item.GetItemStats("item:" .. itemID))
	if not next(stats) then
		local data = C_TooltipInfo.GetItemByID(itemID)
		for _, line in ipairs(data and data.lines or {}) do
			local text = line.leftText
			if text and not Secret(text) and text:find("^%+") then
				ns.Gear_ParseStatText(text, stats)
			end
		end
	end
	if not next(stats) then
		return nil
	end
	gemStats[itemID] = stats
	return stats
end

-- The loaded gems out of a list of item IDs: { { itemID, name, stats } }.
function ns.GearItems_Gems(ids)
	local list = {}
	for _, id in ipairs(ids or {}) do
		local stats = ns.GearItems_GemStats(id)
		local name = stats and C_Item.GetItemNameByID(id)
		if name then
			list[#list + 1] = { itemID = id, name = name, stats = stats }
		end
	end
	return list
end

-- Bind state ("warbound", "warboundUntilEquip", "boe", "soulbound", nil while unknown; Advice.lua's
-- Gear_BindState). location: an ItemLocation you hold (bag, bank, worn), the exact answer from C_Item.IsBound and
-- C_Item.IsBoundToAccountUntilEquip. Else lines: tooltip data lines, whose bind line is the displayed item's own
-- ("Soulbound" on a worn Bind on Equip item). Else the item's bind type (GetItemInfo's 14th return), with bound
-- from the caller when it knows (Baganator's isBound for another character's bags). Lines matched like Syndicator
-- and Baganator do, against Blizzard's global strings (some don't exist on every client).
local bindTexts
local function BindTexts()
	if bindTexts then
		return bindTexts
	end
	bindTexts = {}
	local states = {
		soulbound = { "ITEM_SOULBOUND", "ITEM_BIND_ON_PICKUP", "ITEM_BIND_QUEST" },
		boe = { "ITEM_BIND_ON_EQUIP", "ITEM_BIND_ON_USE" },
		warbound = { "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_ACCOUNT", "ITEM_BIND_TO_BNETACCOUNT" },
		warboundUntilEquip = { "ITEM_ACCOUNTBOUND_UNTIL_EQUIP", "ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP" },
	}
	for state, names in pairs(states) do
		for _, name in ipairs(names) do
			local text = _G[name]
			if type(text) == "string" and text ~= "" then
				bindTexts[text] = state
			end
		end
	end
	return bindTexts
end

function ns.GearItems_BindState(link, location, lines, bound)
	local bindType = select(14, C_Item.GetItemInfo(link))
	if location and location.IsValid and location:IsValid() then
		local ok, exists = pcall(C_Item.DoesItemExist, location)
		if ok and exists then
			return ns.Gear_BindState(bindType, C_Item.IsBound(location), C_Item.IsBoundToAccountUntilEquip(location))
		end
	end
	if lines then
		local texts = {}
		for _, line in ipairs(lines) do
			local text = line.leftText
			if text and not Secret(text) then
				texts[#texts + 1] = text
			end
		end
		local state = ns.Gear_BindStateFromLines(texts, BindTexts())
		if state then
			return state
		end
	end
	return ns.Gear_BindState(bindType, bound, nil)
end

-- slot -> descriptor of everything worn; nil until every worn item is loaded.
function ns.GearItems_Equipped()
	if equipped then
		return equipped
	end
	local snapshot, complete, any = {}, true, false
	for _, slot in ipairs(EQUIP_SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if not link and GetInventoryItemID("player", slot) then
			return nil -- worn, but its link hasn't arrived yet
		elseif link then
			local desc = ns.GearItems_Describe(link)
			if not desc then
				return nil
			end
			snapshot[slot] = desc
			any = true
			complete = complete and not desc.unread
		end
	end
	-- Nothing worn at all is usually a read at login before the inventory arrived: use it, but don't keep it.
	if complete and any then
		equipped = snapshot
	end
	return snapshot
end

function ns.GearItems_InvalidateEquipped()
	equipped = nil
end

-- Descriptors of the equippable items in the bags. Items still loading are left out until they arrive.
function ns.GearItems_BagGear()
	if bagGear then
		return bagGear
	end
	local list, complete = {}, true
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local link = C_Container.GetContainerItemLink(bag, slot)
			local equipLoc = link and select(4, C_Item.GetItemInfoInstant(link))
			if equipLoc and ns.Gear_Slots(equipLoc) then
				local desc = ns.GearItems_Describe(link)
				if desc then
					list[#list + 1] = desc
					complete = complete and not desc.unread
				else
					complete = false
				end
			end
		end
	end
	if complete then
		bagGear = list
	end
	return list
end

function ns.GearItems_InvalidateBags()
	bagGear = nil
end

-- After a level up, red "Requires level" lines change.
function ns.GearItems_ClearCache()
	wipe(cache)
	cacheSize = 0
	equipped = nil
	bagGear = nil
end

-- GET_ITEM_INFO_RECEIVED: tell Gear.lua once (it refreshes bag arrows), shortly after the burst ends.
function ns.GearItems_InfoReceived()
	if not waiting then
		return
	end
	waiting = false
	C_Timer.After(0.3, function()
		if ns.GearItems_OnReady then
			ns.GearItems_OnReady()
		end
	end)
end
