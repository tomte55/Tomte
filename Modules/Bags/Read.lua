local addonName, ns = ...

-- Bags: reads the backpack, the four bags and the reagent bag into plain item records for Data.lua's categories,
-- Search.lua's rules and the window (the record's fields are listed at the top of Search.lua and Data.lua). Gear
-- Check's arrows come through ns.Gear_BagArrow, looked up at call time (it may be off). Records are cached per slot
-- until the slot's link or count changes or the cache is dropped (ns.BagsRead_Invalidate).

-- The bags read, in the game's order: backpack, bags 1-4, reagent bag (Enum.BagIndex 0-5).
local BAGS = { 0, 1, 2, 3, 4, 5 }
local REAGENT_BAG = 5
local WEAPON, ARMOR, RECIPE, BATTLEPET, PROFESSION = 2, 4, 9, 17, 19 -- Enum.ItemClass
-- Classes whose tooltip can say in red that you can't use the item (armor type, class, skill, level).
local CAN_BE_UNUSABLE = { [WEAPON] = true, [ARMOR] = true, [RECIPE] = true, [PROFESSION] = true }
-- A tooltip line in the game's red (RED_FONT_COLOR, 1 / 0.125 / 0.125) says the item can't be used.
local RED_MIN, OTHER_MAX = 0.99, 0.2
-- Hearthstones that are bag items, not toys: Hearthstone, Garrison Hearthstone, Dalaran Hearthstone.
local HEARTHS = { [6948] = true, [110560] = true, [140192] = true }

local IsSecret = ns.IsSecret
local BindState = ns.Bags_BindState
local Counts, MarkGained = ns.Bags_Counts, ns.Bags_MarkGained

local cache = {} -- [bag * 1000 + slot] = item record
-- Bumped when whether you can use things may have changed (combat ended, spec, skill, recipes): a cached record whose
-- usableAt is older checks its red tint again on its next read, and nothing else about it.
local usableGen = 0
-- Slots the game flagged new since the bags last closed: [bag * 1000 + slot] = link. Blizzard's item button clears
-- the game's flag whenever the mouse is on it (ContainerFrameItemButtonMixin:OnUpdate, run by the tooltip), and New
-- then redraws another item under the mouse, so with the flag alone New emptied itself while you looked at it.
local seenNew = {}
local countsAtClose -- Bags_Counts of the bags when they last closed, or at the session's first read

local function Key(bag, slot)
	return bag * 1000 + slot
end

-- The equipment sets each bag slot's item is in: [bag * 1000 + slot] = { set names }.
local function SetSlots()
	local slots = {}
	if not (C_EquipmentSet and EquipmentManager_GetLocationData) then
		return slots
	end
	for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
		local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
		for _, location in pairs(C_EquipmentSet.GetItemLocations(setID) or {}) do
			local data = EquipmentManager_GetLocationData(location)
			if name and data.isBags and not data.isBank and data.bag and data.slot then
				local key = Key(data.bag, data.slot)
				slots[key] = slots[key] or {}
				table.insert(slots[key], name)
			end
		end
	end
	return slots
end

-- Housing decor (C_Item.IsDecorItem, as Blizzard's item buttons ask; missing on clients without housing).
local function IsDecor(itemID)
	return C_Item.IsDecorItem ~= nil and C_Item.IsDecorItem(itemID) == true
end

-- Red tooltip lines that don't mean "you can't use this": the game adds them in combat ("can't change equipment in
-- combat"), in places you can't use it now, or for what can't be scrapped or disenchanted (the game's own words, so
-- every client language). The same lines Baganator skips.
local function NotUnusable(text)
	return text == CANNOT_UNEQUIP_COMBAT or text == SPELL_FAILED_NOT_HERE or text == ITEM_SCRAPABLE_NOT
		or text == ITEM_DISENCHANT_NOT_DISENCHANTABLE or text == ERR_NOT_IN_COMBAT
end

-- The item's tooltip lines in red: wrong armor type, class, skill or level. { line } (empty when it's usable).
local function RedLines(bag, slot)
	local red = {}
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		local color = line.leftColor
		if color and not IsSecret(color.r) and color.r >= RED_MIN and color.g <= OTHER_MAX and color.b <= OTHER_MAX
			and not (IsSecret(line.leftText) or NotUnusable(line.leftText)) then
			red[#red + 1] = line
		end
	end
	return red
end

local function Unusable(bag, slot)
	return #RedLines(bag, slot) > 0
end

-- /tomte bags red: each bag item tinted red and the tooltip lines that did it (type and text).
function ns.BagsRead_PrintRed()
	local found = false
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local _, _, _, _, _, _, _, _, _, _, _, classID = info and info.hyperlink and C_Item.GetItemInfo(info.hyperlink)
			if classID and CAN_BE_UNUSABLE[classID] then
				for _, line in ipairs(RedLines(bag, slot)) do
					found = true
					print(("  %s: line type %s, \"%s\""):format(info.hyperlink, tostring(line.type),
						tostring(line.leftText)))
				end
			end
		end
	end
	if not found then
		print("  No item in your bags is red.")
	end
end

-- A caged battle pet: its link isn't an item link, so the item info calls know nothing about it.
local function PetRecord(bag, slot, info)
	return {
		bag = bag, slot = slot, link = info.hyperlink, itemID = info.itemID, icon = info.iconFileID, readable = true,
		name = info.itemName, count = info.stackCount or 1, quality = info.quality, classID = BATTLEPET, pet = true,
		petLevel = ns.Bags_PetLevel(info.hyperlink),
	}
end

-- A record for a filled slot, or nil and true when the item's data hasn't loaded yet.
local function Record(bag, slot, info)
	local link, itemID = info.hyperlink, info.itemID
	if IsSecret(link, itemID, info.stackCount) then
		return { bag = bag, slot = slot, icon = info.iconFileID, count = 1, readable = false }
	end
	if link and link:find("|Hbattlepet:") then
		return PetRecord(bag, slot, info)
	end
	local name, _, quality, _, _, typeName, subTypeName, _, equipLoc, _, price, classID, subclassID, bindType,
		expansion = C_Item.GetItemInfo(link)
	if not name then
		return { bag = bag, slot = slot, link = link, itemID = itemID, icon = info.iconFileID,
			count = info.stackCount or 1, quality = info.quality, readable = false }, true
	end
	local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
	local item = {
		bag = bag, slot = slot, link = link, itemID = itemID, icon = info.iconFileID, readable = true,
		name = name, typeName = typeName, subTypeName = subTypeName, equipLoc = equipLoc,
		count = info.stackCount or 1, quality = info.quality or quality, price = price, noValue = info.hasNoValue,
		classID = classID, subclassID = subclassID, expansion = expansion,
		bind = BindState(bindType, info.isBound),
		junk = ns.Bags_IsJunk(info.quality or quality, info.hasNoValue, BindState(bindType, info.isBound)),
		hearth = HEARTHS[itemID] == true,
		toy = C_ToyBox.GetToyInfo(itemID) ~= nil,
		mount = C_MountJournal.GetMountFromItem(itemID) ~= nil,
		pet = C_PetJournal.GetPetInfoByItemID(itemID) ~= nil,
		decor = IsDecor(itemID),
	}
	local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
	item.quest = quest and (quest.isQuestItem or quest.questID ~= nil) or false
	item.questID, item.questActive = quest and quest.questID, quest and quest.isActive
	if CAN_BE_UNUSABLE[classID] then
		item.unusable = Unusable(bag, slot)
		item.usableAt = usableGen
	end
	if classID == WEAPON or classID == ARMOR then
		item.ilvl = C_Item.GetCurrentItemLevel(location)
		item.look = ns.NewAppearance(link)
		if ns.Gear_BagArrow then
			item.upgrade = ns.Gear_BagArrow(link, location, info.isBound)
		end
	end
	return item
end

-- Every slot of the bags (or of containers: a list of bag IDs, such as the bank's tabs): item records and one empty
-- record per free slot; pending is true when some item's data hasn't loaded yet (those aren't cached, and
-- GET_ITEM_INFO_RECEIVED reads again).
function ns.BagsRead_Bags(containers)
	local items, pending = {}, false
	local sets = SetSlots()
	for _, bag in ipairs(containers or BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local key = Key(bag, slot)
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if not info then
				cache[key] = nil
				items[#items + 1] = { empty = true, kind = bag == REAGENT_BAG and "reagent" or "normal",
					bag = bag, slot = slot }
			else
				local item = cache[key]
				if not (item and item.link == info.hyperlink and item.count == (info.stackCount or 1)) then
					local waiting
					item, waiting = Record(bag, slot, info)
					pending = pending or waiting == true
					cache[key] = item.readable and item or nil
				elseif item.usableAt and item.usableAt ~= usableGen then
					item.unusable = Unusable(bag, slot)
					item.usableAt = usableGen
				end
				-- Checked on every read, not cached: they change without the link changing.
				item.locked = info.isLocked
				item.isReadable = info.isReadable -- a book or letter (the inspect cursor), not "data loaded"
				if C_NewItems.IsNewItem(bag, slot) then
					seenNew[key] = info.hyperlink
				end
				item.new = info.hyperlink ~= nil and seenNew[key] == info.hyperlink
				item.set = sets[key]
				items[#items + 1] = item
			end
		end
	end
	if not containers then
		-- The first read of the session counts what you have, so loot is caught before the bags first close: the
		-- game's flag alone can be gone before this read (the slot was under the mouse, as when opening a container).
		countsAtClose = countsAtClose or Counts(items)
		MarkGained(items, countsAtClose)
	end
	return items, pending
end

-- Item records for another character's items (Item counts' record: { { id, link, count } }), for looking only: no
-- bag or slot of yours (bag is LIST_BAG, slot the index), no upgrade arrows (they'd judge them for the character
-- you're on). Items whose data hasn't loaded show their icon and are read again on the next draw.
local LIST_BAG = -100
function ns.BagsRead_FromList(list)
	local items = {}
	for i, entry in ipairs(list) do
		local link = entry.link
		local item = { bag = LIST_BAG, slot = i, link = link, itemID = entry.id, count = entry.count or 1,
			icon = entry.id and C_Item.GetItemIconByID(entry.id), readable = false }
		local name, quality, typeName, subTypeName, equipLoc, price, classID, subclassID, bindType, expansion, _
		if link then -- not "link and GetItemInfo(link)": that keeps only the first value
			name, _, quality, _, _, typeName, subTypeName, _, equipLoc, _, price, classID, subclassID, bindType,
				expansion = C_Item.GetItemInfo(link)
		end
		if link and link:find("|Hbattlepet:") then
			item.classID, item.pet, item.petLevel, item.readable = BATTLEPET, true, ns.Bags_PetLevel(link), true
			item.name = link:match("%[(.-)%]")
		elseif name then
			item.readable = true
			item.name, item.typeName, item.subTypeName, item.equipLoc = name, typeName, subTypeName, equipLoc
			item.quality, item.price, item.classID, item.subclassID = quality, price, classID, subclassID
			item.expansion = expansion
			item.bind = BindState(bindType, nil)
			item.junk = ns.Bags_IsJunk(quality, price == 0, item.bind)
			if classID == WEAPON or classID == ARMOR then
				item.ilvl = C_Item.GetDetailedItemLevelInfo(link)
				item.look = ns.NewAppearance(link)
			end
		end
		items[#items + 1] = item
	end
	return items
end

-- The tooltip's lines, in lower case, for searches with words (Search.lua reads item.text). Read once per record:
-- records are cached until their item changes. Secret lines are skipped.
local function TooltipText(item)
	local data
	if item.bag == LIST_BAG then
		data = item.link and C_TooltipInfo.GetHyperlink(item.link)
	else
		data = C_TooltipInfo.GetBagItem(item.bag, item.slot)
	end
	local parts = {}
	for _, line in ipairs(data and data.lines or {}) do
		for _, text in ipairs({ line.leftText, line.rightText }) do
			if text and text ~= "" and not IsSecret(text) then
				parts[#parts + 1] = text:lower()
			end
		end
	end
	return table.concat(parts, "\n")
end

function ns.BagsRead_LoadText(items)
	for _, item in ipairs(items) do
		if not item.empty and item.readable and not item.text then
			item.text = TooltipText(item)
		end
	end
end

-- Clears the "new" flag of every item in the bags: Blizzard does it when its bag frames hide (UpdateNewItemList in
-- ContainerFrame_OnHide), which never runs while they sit under Takeover.lua's hidden parent. Also forgets what
-- Tomte saw as new, and counts what the bags hold now, so what comes in on top of a stack is new next time.
function ns.BagsRead_ClearNew()
	wipe(seenNew)
	local held = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if C_NewItems.IsNewItem(bag, slot) then
				C_NewItems.RemoveNewItem(bag, slot)
			end
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				held[#held + 1] = { itemID = info.itemID, count = info.stackCount or 1 }
			end
		end
	end
	countsAtClose = Counts(held)
end

-- Whether you can use gear and recipes may have changed: each cached one checks its red tint again when next read
-- (cheap: only those items, only once, only when a window draws).
function ns.BagsRead_UsableChanged()
	usableGen = usableGen + 1
end

-- Drops cached records: one bag's, or every bag's (nil). Gear Check's verdicts and transmog changes need all.
function ns.BagsRead_Invalidate(bag)
	if bag == nil then
		wipe(cache)
		return
	end
	for key in pairs(cache) do
		if math.floor(key / 1000) == bag then
			cache[key] = nil
		end
	end
end
