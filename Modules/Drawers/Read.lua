local addonName, ns = ...

-- Drawers: reads the game for entries. Turns a link, the cursor or a typed name into an entry, and an entry into
-- what its button shows (name, icon, whether you have it). Pure parsing in Data.lua; used by Bar.lua and Editor.lua.

local EMPTY_ICON = 133633 -- inv_misc_bag_08, also the module's icon
local IsSecret = ns.IsSecret

ns.DRAWERS_EMPTY_ICON = EMPTY_ICON

-- An item you have as a toy is used from the toy box (works with none in the bags); any other item by item ID.
local function ItemEntry(itemID)
	if PlayerHasToy(itemID) then
		return { kind = "toy", id = itemID }
	end
	return { kind = "item", id = itemID }
end

-- A spell that summons a mount is kept as that mount: mounts are cast by name (see Bar.lua).
local function SpellEntry(spellID)
	local mountID = C_MountJournal.GetMountFromSpell(spellID)
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
	elseif kind == "mount" and C_MountJournal.GetMountInfoByID(id) then
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
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
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

-- name (may be nil while the item isn't cached), icon, have (you own it / know it / carry it), mount spell ID.
function ns.Drawers_Info(entry)
	local kind, id = entry.kind, entry.id
	if kind == "item" then
		local count = C_Item.GetItemCount(id, false, true)
		return C_Item.GetItemNameByID(id), C_Item.GetItemIconByID(id) or EMPTY_ICON,
			IsSecret(count) or (count or 0) > 0
	elseif kind == "toy" then
		local _, name, icon = C_ToyBox.GetToyInfo(id)
		return name or C_Item.GetItemNameByID(id), icon or C_Item.GetItemIconByID(id) or EMPTY_ICON, PlayerHasToy(id)
	elseif kind == "spell" then
		return C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id) or EMPTY_ICON,
			C_SpellBook.IsSpellKnown(id) and true or false
	elseif kind == "mount" then
		local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
		return name, icon or EMPTY_ICON, isCollected and true or false, spellID
	end
	return nil, EMPTY_ICON, false
end

-- The game's own tooltip for an entry, beside owner.
function ns.Drawers_Tooltip(owner, entry)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if entry.kind == "item" then
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
ns.DRAWERS_KIND_TEXT = { item = "Item", toy = "Toy", spell = "Spell", mount = "Mount" }
