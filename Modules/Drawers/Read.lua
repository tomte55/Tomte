local addonName, ns = ...

-- Drawers: reads the game for entries. Turns a link, the cursor or a typed name into an entry, an entry into what
-- its button shows (name, icon, whether you have it), and searches into the items in your bags they match. Pure
-- parsing and sorting in Data.lua; used by Bar.lua and Editor.lua.

local EMPTY_ICON = 133633 -- inv_misc_bag_08, also the module's icon
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"
-- Backpack, bags 1-4 and the reagent bag (Enum.BagIndex 0-5; Forever has no reagent bag: it reads as 0 slots).
local BAGS = { 0, 1, 2, 3, 4, 5 }
local CONSUMABLE = 0 -- Enum.ItemClass
local IsSecret = ns.IsSecret

ns.DRAWERS_EMPTY_ICON = EMPTY_ICON

-- An item you have as a toy is used from the toy box (works with none in the bags); any other item by item ID.
local function ItemEntry(itemID)
	if PlayerHasToy and PlayerHasToy(itemID) then -- no toy box on Forever
		return { kind = "toy", id = itemID }
	end
	return { kind = "item", id = itemID }
end

-- A spell that summons a mount is kept as that mount: mounts are cast by name (see Bar.lua).
local function SpellEntry(spellID)
	local mountID = C_MountJournal and C_MountJournal.GetMountFromSpell(spellID) -- Forever: mounts are items
	if mountID then
		return { kind = "mount", id = mountID }
	end
	return { kind = "spell", id = spellID }
end

function ns.Drawers_FromLink(text)
	local kind, id = ns.Drawers_ParseLink(text)
	if kind == "item" then
		return ItemEntry(id)
	elseif kind == "spell" or kind == "mountSpell" then
		return SpellEntry(id)
	end
	return nil
end

-- What's on the cursor (dragged from the bags, spellbook, mount journal or toy box), or nil.
function ns.Drawers_FromCursor()
	local kind, id = ns.Drawers_ParseCursor(GetCursorInfo())
	if kind == "item" then
		return ItemEntry(id)
	elseif kind == "spell" then
		return SpellEntry(id)
	elseif kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID(id) then
		return { kind = "mount", id = id }
	end
	return nil
end

-- A typed name or item ID: a mount of that name, then a spell, then an item the game knows by name (one that's
-- been in your bags or bank this session). Names compare in the client's language, ignoring case.
function ns.Drawers_FromName(text)
	text = strtrim(text or "")
	if text == "" then
		return nil
	end
	local fromLink = ns.Drawers_FromLink(text)
	if fromLink then
		return fromLink
	end
	local number = tonumber(text)
	if number then
		-- Only real items: an unknown ID would never load (and Item:ContinueOnItemLoad errors on it).
		return number > 0 and number == math.floor(number) and C_Item.DoesItemExistByID(number) and ItemEntry(number)
			or nil
	end
	local wanted = text:lower()
	for _, mountID in ipairs(C_MountJournal and C_MountJournal.GetMountIDs() or {}) do
		local name = C_MountJournal.GetMountInfoByID(mountID)
		if name and name:lower() == wanted then
			return { kind = "mount", id = mountID }
		end
	end
	local spell = C_Spell.GetSpellInfo(text)
	if spell and spell.spellID then
		return SpellEntry(spell.spellID)
	end
	local itemID = C_Item.GetItemInfoInstant(text)
	if itemID then
		return ItemEntry(itemID)
	end
	return nil
end

-- Searches ------------------------------------------------------------------------------------------------------

-- The tooltip's text in lower case, for a search with words (as the bag search reads it, Bags/Read.lua).
local function TooltipText(bag, slot)
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	local parts = {}
	for _, line in ipairs(data and data.lines or {}) do
		for _, text in ipairs({ line.leftText, line.rightText }) do
			if type(text) == "string" and not IsSecret(text) then
				parts[#parts + 1] = text:lower()
			end
		end
	end
	return table.concat(parts, "\n")
end

-- One record per item ID in the bags, with the fields Bags/Search.lua's rules read (those a bag slot alone knows,
-- such as a marker or "new", stay empty and never match). Items above your level are left out: a drawer is for
-- using things. pending: some item's data hasn't loaded yet (asked for; BAG_UPDATE_DELAYED or the load reads again).
local function ReadBags(withText)
	local byID, list, pending = {}, {}, false
	local level = UnitLevel("player")
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not IsSecret(id, info.stackCount) then
				local item = byID[id]
				if item then
					item.count = item.count + (info.stackCount or 1)
				else
					local name, _, quality, ilvl, minLevel, typeName, subTypeName, _, _, _, price, classID, subclassID, _,
						expansion = C_Item.GetItemInfo(id)
					if not name then
						pending = true
						C_Item.RequestLoadItemDataByID(id)
					elseif (minLevel or 0) <= level then
						classID = ns.BagsRead_ItemClass(id, classID, subclassID)
						local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
						item = {
							itemID = id, name = name, typeName = typeName, subTypeName = subTypeName,
							quality = info.quality or quality, ilvl = ilvl, minLevel = minLevel, price = price,
							classID = classID, subclassID = subclassID, expansion = expansion,
							count = info.stackCount or 1,
							hearth = ns.BAGS_HEARTHS[id] == true,
							toy = PlayerHasToy ~= nil and PlayerHasToy(id) or false,
							mount = C_MountJournal ~= nil and C_MountJournal.GetMountFromItem(id) ~= nil,
							quest = quest ~= nil and (quest.isQuestItem or quest.questID ~= nil) or false,
							consumable = classID == CONSUMABLE and ns.ConsumableKind(id) or nil,
						}
						item.buff = item.consumable == "food" and ns.IsBuffFood(id)
						if withText then
							item.text = TooltipText(bag, slot)
						end
						byID[id] = item
						list[#list + 1] = item
					end
				end
			end
		end
	end
	return list, pending
end

-- The items each search entry finds in your bags: found[entry] = { itemIDs }, best first. Bad searches find
-- nothing (the editor says why when they're added). Also whether some item's data was still loading.
function ns.Drawers_Found(entries)
	local matchers, withText = {}, false
	for _, entry in ipairs(entries) do
		if entry.kind == "search" then
			local match, _, usesText = ns.BagsSearch_Compile(entry.text)
			matchers[entry] = match
			withText = withText or usesText == true
		end
	end
	local found = {}
	if not next(matchers) then
		return found, false
	end
	local items, pending = ReadBags(withText)
	for entry, match in pairs(matchers) do
		local hits = {}
		for _, item in ipairs(items) do
			if match(item) then
				hits[#hits + 1] = item
			end
		end
		ns.Drawers_SortFound(hits)
		local ids = {}
		for i, item in ipairs(hits) do
			ids[i] = item.itemID
		end
		found[entry] = ids
	end
	return found, pending
end

-- /tomte drawers search <text>: lines for chat. Each consumable in the bags with the spell it casts, what Tomte
-- makes of it and whether the search matches it; items left out (above your level, data loading) say so.
function ns.Drawers_SearchWhy(text)
	text = strtrim(text or "")
	local out = {}
	local match, why = ns.BagsSearch_Compile(text)
	if text ~= "" and not match then
		out[1] = "That search doesn't read: " .. tostring(why)
		return out
	end
	local items, pending = ReadBags(false)
	for _, item in ipairs(items) do
		if item.classID == CONSUMABLE then
			local spellName, spellID = C_Item.GetItemSpell(item.itemID)
			out[#out + 1] = ("%s (%d): spell %s (%s), reads as %s%s, needs level %s%s"):format(item.name, item.itemID,
				tostring(spellName), tostring(spellID), tostring(item.consumable), item.buff and ", buff food" or "",
				tostring(item.minLevel), match and (match(item) and ", MATCHES" or ", no match") or "")
		end
	end
	for _, kind in ipairs({ "food", "drink", "bandage" }) do
		local names = {}
		for _, spellID in ipairs(ns.CONSUMABLE_SPELLS[kind]) do
			names[#names + 1] = tostring(C_Spell.GetSpellName(spellID))
		end
		out[#out + 1] = ("Spells read as %s: %s."):format(kind, table.concat(names, ", "))
	end
	out[#out + 1] = ("Your level: %d."):format(UnitLevel("player"))
	out[#out + 1] = "Items above your level aren't listed: drawers leave them out."
	if pending then
		out[#out + 1] = "Some items' data was still loading: try again in a moment."
	end
	return out
end

-- Whether any of these entries is a search (its drawer changes with your bags).
function ns.Drawers_HasSearch(entries)
	for _, entry in ipairs(entries) do
		if entry.kind == "search" then
			return true
		end
	end
	return false
end

-- Entries ------------------------------------------------------------------------------------------------------

-- name (may be nil while the item isn't cached), icon, have (you own it / know it / carry it), mount spell ID.
-- A search's name is its text.
function ns.Drawers_Info(entry)
	local kind, id = entry.kind, entry.id
	if kind == "search" then
		return entry.text, SEARCH_ICON, true
	elseif kind == "item" then
		local count = C_Item.GetItemCount(id, false, true)
		return C_Item.GetItemNameByID(id), C_Item.GetItemIconByID(id) or EMPTY_ICON,
			IsSecret(count) or (count or 0) > 0
	elseif kind == "toy" and C_ToyBox then
		local _, name, icon = C_ToyBox.GetToyInfo(id)
		return name or C_Item.GetItemNameByID(id), icon or C_Item.GetItemIconByID(id) or EMPTY_ICON, PlayerHasToy(id)
	elseif kind == "spell" then
		return C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id) or EMPTY_ICON,
			ns.SpellKnown(id)
	elseif kind == "mount" and C_MountJournal then
		local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
		return name, icon or EMPTY_ICON, isCollected and true or false, spellID
	end
	return nil, EMPTY_ICON, false
end

-- The game's own tooltip for an entry, beside owner.
function ns.Drawers_Tooltip(owner, entry)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if entry.kind == "search" then
		GameTooltip:SetText("Search: " .. entry.text, ns.UI.RGB("heading"))
		local found = ns.Drawers_Found({ entry })[entry] or {}
		ns.UI.TipLine(#found == 1 and "1 item in your bags matches." or (#found .. " items in your bags match."),
			"text")
		ns.UI.TipLine("They fill this place in the drawer, the best first, and change with your bags (after combat"
			.. " when you're fighting).", "textMuted", true)
		GameTooltip:Show()
		return
	elseif entry.kind == "item" then
		GameTooltip:SetItemByID(entry.id)
	elseif entry.kind == "toy" then
		GameTooltip:SetToyByItemID(entry.id)
	elseif entry.kind == "spell" then
		GameTooltip:SetSpellByID(entry.id)
	else
		local _, _, _, spellID = ns.Drawers_Info(entry)
		if spellID then
			GameTooltip:SetMountBySpellID(spellID)
		end
	end
	GameTooltip:Show()
end

-- Kind as the editor lists it.
ns.DRAWERS_KIND_TEXT = { item = "Item", toy = "Toy", spell = "Spell", mount = "Mount", search = "Search" }
