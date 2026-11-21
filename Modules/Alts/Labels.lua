local addonName, ns = ...

-- Alts: the shared labels the Alts files draw items and recipes with: Alts_QualityMarkup, Alts_RankMarkup,
-- Alts_ItemLabel, Alts_RecipeLabel and Alts_MissingText (and Alts_RankOf, the rank of a ranked reagent).

local UI = ns.UI

local function ItemName(itemID)
	return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

local function RecipeName(recipeID)
	local r = ns.altsDB.recipes[recipeID]
	return r and r.name or "?"
end

-- Text in an item's rarity colour (as it is until the item's data has loaded).
local function InQuality(text, itemID)
	local quality = itemID and C_Item.GetItemQualityByID(itemID)
	if not quality then
		return text
	end
	local r, g, b = C_Item.GetItemQualityColor(quality)
	return UI.Wrap(text, { r, g, b })
end

local function Icon(icon, size)
	return icon and size and ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(icon, size, size) or ""
end

-- Quality icons --------------------------------------------------------------------------------------------------

-- An atlas as text, the older tier atlas when it's missing, else "Q2".
local TIER_ATLAS = "Professions-ChatIcon-Quality-Tier%d"
local function QualityIcon(atlas, n)
	for _, a in ipairs({ atlas or false, n and TIER_ATLAS:format(n) or false }) do
		if a and C_Texture.GetAtlasInfo(a) then
			return CreateAtlasMarkup(a, 16, 16)
		end
	end
	return n and UI.Wrap("Q" .. n, "textMuted") or ""
end

-- The icon of a recipe's output at quality n (1, 2, ...: GetRecipeItemQualityInfo takes the tier, as Blizzard's
-- schematic form passes operationInfo.craftingQuality), "" for nil.
function ns.Alts_QualityMarkup(recipeID, n)
	if not n then
		return ""
	end
	local ok, info = pcall(C_TradeSkillUI.GetRecipeItemQualityInfo, recipeID, n)
	return QualityIcon(ok and type(info) == "table" and info.iconChat or nil, n)
end

-- [itemID] = rank, for every reagent that comes in ranks (its position in a recipe's slot). Rebuilt when recipes change.
local rankOf
function ns.AltsList_RecipesChanged()
	rankOf = nil
end

function ns.Alts_RankOf(itemID)
	if not rankOf then
		rankOf = {}
		for _, r in pairs(ns.altsDB.recipes) do
			for _, slot in ipairs(r.reagents or {}) do
				if #slot.items > 1 then
					for i, id in ipairs(slot.items) do
						rankOf[id] = i
					end
				end
			end
		end
	end
	return rankOf[itemID]
end

-- A ranked reagent's rank icon (the game's, from GetItemReagentQualityInfo), "" for items without ranks.
function ns.Alts_RankMarkup(itemID)
	local rank = itemID and ns.Alts_RankOf(itemID)
	if not rank then
		return ""
	end
	local ok, info = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, itemID)
	return QualityIcon(ok and type(info) == "table" and info.iconChat or nil, rank)
end

-- An item as the crafting list shows it: its icon (when size is given), its name in its rarity colour and, for a
-- ranked reagent, its rank (unless noRank: a material of any rank is shown by its first one).
function ns.Alts_ItemLabel(itemID, size, noRank)
	local label = Icon(C_Item.GetItemIconByID(itemID), size) .. InQuality(ItemName(itemID), itemID)
	local rank = not noRank and ns.Alts_RankMarkup(itemID) or ""
	return rank ~= "" and (label .. " " .. rank) or label
end

-- What a plan is short of: "Missing 5 Echoing Flux" for one material, "Missing 3 materials" for more
-- (plan.missing counts units, not materials).
function ns.Alts_MissingText(plan)
	local short, count = nil, 0
	for _, m in ipairs(plan.materials) do
		if m.missing > 0 then
			short, count = m, count + 1
		end
	end
	if count == 1 then
		return ("Missing %d %s"):format(short.missing, ItemName(short.items[1]))
	end
	return ("Missing %d materials"):format(count)
end

-- A recipe: its icon (when size is given), its name in the rarity colour of what it makes and the quality icon
-- when one is picked.
function ns.Alts_RecipeLabel(recipeID, size, quality)
	local r = ns.altsDB.recipes[recipeID]
	local label = Icon(r and r.icon, size) .. InQuality(RecipeName(recipeID), r and r.item)
	quality = r and ns.Alts_Qualities(r) > 1 and ns.Alts_ClampQuality(r, quality)
	return quality and (label .. " " .. ns.Alts_QualityMarkup(recipeID, quality)) or label
end

-- For List.lua (the tracker's rows and its messages).
ns.Alts_RecipeName = RecipeName
