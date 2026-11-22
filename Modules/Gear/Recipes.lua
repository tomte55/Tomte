local addonName, ns = ...

-- Gear Check in the profession window: beside each gear recipe in the recipe list, what its item would be for you
-- ("+12%" in the success color, "+5%?" in the warning color for one to check), retail and Forever, through
-- Panel/RecipeRows.lua. The verdict is the item tooltip's (ns.Gear_Verdict: Gear.lua on retail, Forever.lua on
-- Forever) for the recipe's plain output item, so on retail a craft whose item level follows the reagents is judged at
-- base quality. Mark text in Rules.lua (Gear_RecipeMark). Started and stopped by Gear.lua or Forever.lua, which call
-- GearRecipes_Refresh whenever their verdicts change (gear, level, spec, items loaded).

local ORDER = 1 -- at the right end of the row (RecipeRows_Add)
-- Output items that are never gear Gear Check judges.
local NOT_GEAR = { [""] = true, INVTYPE_BAG = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_QUIVER = true,
	INVTYPE_AMMO = true }

local db
local active = false
local links = {} -- [recipeID] = output item link, once the game has one (a recipe's output never changes)
local loading = {} -- [itemID] = true while an output item's data is asked for

-- Asks for an item's data once; the rows are drawn again when it has arrived.
local function Load(itemID)
	if loading[itemID] then
		return
	end
	loading[itemID] = true
	Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
		loading[itemID] = nil
		ns.RecipeRows_Refresh()
	end)
end

-- The recipe's item, when it's gear. Nil for enchants, reagents, bags and while the link isn't there yet.
local function GearLink(recipeID)
	local link = links[recipeID]
	if not link then
		local info = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
		link = info and info.hyperlink
		if not link then
			if info and info.itemID then
				Load(info.itemID)
			end
			return nil
		end
		links[recipeID] = link
	end
	local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
	if not equipLoc or NOT_GEAR[equipLoc] then
		return nil
	end
	return link
end

ns.RecipeRows_Add("gear", ORDER, function(recipe)
	if not (active and db.recipeMarks) then
		return nil
	end
	local link = GearLink(recipe.recipeID)
	return ns.Gear_RecipeMark(link and ns.Gear_Verdict(link))
end)

-- Gear.lua and Forever.lua call this when their verdicts change, and the setting's onChange.
function ns.GearRecipes_Refresh()
	ns.RecipeRows_Refresh()
end

function ns.GearRecipes_Start(moduleDB)
	db = moduleDB
	active = true
	ns.RecipeRows_Refresh()
end

function ns.GearRecipes_Stop()
	active = false
	ns.RecipeRows_Refresh()
end
