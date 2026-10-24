local addonName, ns = ...

-- Tooltip extras: reads the game into plain tables for Data.lua and the tooltip lines (Tooltip.lua, Choice.lua):
-- the merged per-expansion data, a faction's standing, a combine item's reagents, counts, names and icons.

local IsSecret = ns.IsSecret

local merged = {} -- [kind] = lookup over every expansion, built on first use (all data files load before this)
local reagentCache = {} -- [itemID] = { recipeID, outputItemID, reagents = { { itemID | currencyID, need } } } | false
local npcNames = {} -- [npcID] = localized name

-- Data ----------------------------------------------------------------------------------------------------------

function ns.Tips_Data(kind)
	if not merged[kind] then
		local sources = {}
		for _, expansion in ipairs(ns.Content_Expansions()) do
			sources[#sources + 1] = ns.Content_Get(expansion, "tips") or {}
		end
		merged[kind] = ns.Tips_Merge(sources, kind)
	end
	return merged[kind]
end

-- Counts, names, icons ------------------------------------------------------------------------------------------

-- Everything you own of an item: bags, bank, reagent bank, warband bank.
function ns.Tips_ItemCount(itemID)
	local count = C_Item.GetItemCount(itemID, true, false, true, true)
	if IsSecret(count) then
		return 0
	end
	return count or 0
end

-- name, count, icon of a currency (nil when the game doesn't know it).
function ns.Tips_Currency(currencyID)
	local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	if not info or IsSecret(info.quantity) then
		return nil
	end
	return info.name, info.quantity or 0, info.iconFileID
end

-- name, count, icon of an entry { kind = "item" | "currency", id }. name is nil while an item isn't loaded yet.
function ns.Tips_Entry(kind, id)
	if kind == "currency" then
		return ns.Tips_Currency(id)
	end
	return C_Item.GetItemNameByID(id), ns.Tips_ItemCount(id), C_Item.GetItemIconByID(id)
end

-- An inline icon in front of tooltip text.
function ns.Tips_Icon(icon)
	return icon and ("|T" .. icon .. ":0|t ") or ""
end

-- The localized name of an NPC, read once from its unit tooltip; fallback (the data's English name) until then.
function ns.Tips_NpcName(npcID, fallback)
	if npcNames[npcID] then
		return npcNames[npcID]
	end
	-- pcall: a hyperlink lookup can fail on an NPC this client doesn't have.
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID))
	local line = ok and data and data.lines and data.lines[1]
	local name = line and line.leftText
	if name and not IsSecret(name) and name ~= "" then
		npcNames[npcID] = name
		return name
	end
	return fallback
end

-- Reputation ------------------------------------------------------------------------------------------------------

local function Paragon(factionID)
	if not C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
		return nil
	end
	local value, threshold, _, pending = C_Reputation.GetFactionParagonInfo(factionID)
	if not value or IsSecret(value) then
		return nil
	end
	return { value = value, threshold = threshold, pending = pending == true }
end

-- A plain record of one faction's standing for ns.Tips_RepStatus, or nil when the game doesn't know it.
function ns.Tips_FactionRecord(factionID)
	local rec = { paragon = Paragon(factionID) }
	if C_Reputation.IsMajorFaction(factionID) then
		local data = C_MajorFactions.GetMajorFactionData(factionID)
		if not data then
			return nil
		end
		rec.kind, rec.name, rec.level = "renown", data.name, data.renownLevel
		rec.maxed = C_MajorFactions.HasMaximumRenown(factionID)
		rec.earned, rec.threshold = data.renownReputationEarned, data.renownLevelThreshold
		return rec
	end
	local friend = C_GossipInfo.GetFriendshipReputation(factionID)
	if friend and (friend.friendshipFactionID or 0) > 0 then
		local ranks = C_GossipInfo.GetFriendshipReputationRanks(friend.friendshipFactionID)
		rec.kind, rec.name, rec.standing = "friend", friend.name, friend.reaction
		rec.level, rec.maxLevel = ranks and ranks.currentLevel, ranks and ranks.maxLevel
		rec.maxed = friend.nextThreshold == nil
		rec.earned = (friend.standing or 0) - (friend.reactionThreshold or 0)
		rec.threshold = friend.nextThreshold and (friend.nextThreshold - (friend.reactionThreshold or 0)) or 0
		return rec
	end
	local data = C_Reputation.GetFactionDataByID(factionID)
	if not (data and data.name and data.name ~= "") then
		return nil
	end
	rec.kind, rec.name = "plain", data.name
	rec.standing = _G["FACTION_STANDING_LABEL" .. (data.reaction or 0)]
	rec.earned = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
	rec.threshold = (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)
	rec.maxed = rec.threshold <= 0
	return rec
end

-- The factions an item's use raises (a list), or nil.
function ns.Tips_ItemFactions(itemID)
	local _, spellID = C_Item.GetItemSpell(itemID)
	local value = spellID and not IsSecret(spellID) and ns.Tips_Data("repSpells")[spellID]
	return value and ns.Tips_FactionList(value) or nil
end

-- Reagents ----------------------------------------------------------------------------------------------------------

local SKIP_CLASSES = {
	[Enum.ItemClass.Recipe] = true, -- Alts' tooltip covers recipes
	[Enum.ItemClass.ItemEnhancement] = true, -- enchant scrolls carry their enchanting recipe's spell
}

local function ReadSchematic(itemID)
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	if SKIP_CLASSES[classID] or ns.Tips_Data("reagentSkip")[itemID] then
		return false
	end
	local _, spellID = C_Item.GetItemSpell(itemID)
	if not spellID or IsSecret(spellID) then
		return false
	end
	-- pcall: GetRecipeSchematic is meant for profession recipes and may error on other spells.
	local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
	if not (ok and schematic and schematic.reagentSlotSchematics) then
		return false
	end
	local fixes = ns.Tips_Data("reagentQuantity")[schematic.recipeID] or {}
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local first = slot.required and slot.reagents and slot.reagents[1]
		if first and (first.itemID or first.currencyID) then
			reagents[#reagents + 1] = {
				itemID = first.itemID,
				currencyID = first.currencyID,
				need = (first.itemID and fixes[first.itemID]) or slot.quantityRequired or 1,
			}
		end
	end
	if not ns.Tips_IsCombine(itemID, reagents) then
		return false
	end
	return { recipeID = schematic.recipeID, outputItemID = schematic.outputItemID, reagents = reagents }
end

-- The recipe an item's use makes (a combine item), or nil. Cached per item: recipes don't change in a session.
function ns.Tips_ItemRecipe(itemID)
	if reagentCache[itemID] == nil then
		reagentCache[itemID] = ReadSchematic(itemID)
	end
	return reagentCache[itemID] or nil
end

-- That recipe's reagents with names and what you own: { { name, have, need, icon } }, and whether a name was missing
-- (the item isn't loaded yet: the caller asks the tooltip to refresh).
function ns.Tips_ReadReagents(recipe)
	local list, missing = {}, false
	for _, r in ipairs(recipe.reagents) do
		local name, have, icon
		if r.itemID then
			name, have, icon = ns.Tips_Entry("item", r.itemID)
		else
			name, have, icon = ns.Tips_Currency(r.currencyID)
		end
		missing = missing or not name
		list[#list + 1] = { name = name, have = have or 0, need = r.need, icon = icon }
	end
	return list, missing
end
