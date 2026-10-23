local addonName, ns = ...

-- Tooltip extras: small lines on tooltips (which key opens a chest, reputation tokens, reagents of combine items,
-- where a token is spent with Ctrl-click for a waypoint) and item counts under choice windows. Registers the module.
-- Pure text in Data.lua, game reads in Read.lua, tooltip lines in Tooltip.lua, choice windows in Choice.lua, data per
-- expansion in Data/<Expansion>/Tips.lua.

local module, db

local function RefreshChoice()
	if module.active then
		ns.TipsChoice_Refresh()
	end
end

-- /tomte tips why <item link or ID>: what each line kind knows about an item.
local function Why(arg)
	local itemID = tonumber(arg) or tonumber((arg or ""):match("item:(%d+)"))
	if not itemID then
		ns.Print("usage: /tomte tips why <item link or ID>")
		return
	end
	local _, spellID = C_Item.GetItemSpell(itemID)
	ns.Print(("%s (%d), use spell %s:"):format(C_Item.GetItemNameByID(itemID) or "item", itemID, tostring(spellID)))
	local factions = ns.Tips_ItemFactions(itemID)
	print("  reputation: " .. (factions and table.concat(factions, ", ") or "none"))
	local recipe = ns.Tips_ItemRecipe(itemID)
	print("  reagents: " .. (recipe and ("recipe " .. tostring(recipe.recipeID) .. ", " .. #recipe.reagents
		.. " reagents") or "none"))
	local places = ns.Tips_VendorPlaces(ns.Tips_Data("vendors")[itemID])
	print("  vendors: " .. #places)
end

module = ns.RegisterModule({
	key = "tips",
	name = "Tooltip extras",
	category = "interface",
	icon = 134332, -- inv_misc_note_06
	summary = "Extra lines on tooltips: keys, reputation tokens, reagents and where to spend tokens.",
	description = "Adds small lines to tooltips: which key opens a delve chest and how many you have, which faction a reputation token raises and whether you're already maxed, what a combine item needs and how many you own, and where a token is spent (Ctrl-click it in your bags for a waypoint). Choice windows show how many you own of what they take and give.",
	enabledByDefault = true,
	replaces = {
		{ addon = "Plumber",
			why = "chest keys, reputation tokens, reagents and vendor places on tooltips, and choice window counts" },
	},
	defaults = {
		keys = true,
		rep = true,
		reagents = true,
		vendors = true,
		choice = true,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			ns.TipsTooltip_Start(db)
			ns.TipsChoice_Start(db)
		else
			ns.TipsTooltip_Stop()
			ns.TipsChoice_Stop()
		end
	end,
	commands = {
		{ "why", "what Tooltip extras knows about an item (link or ID)", function(arg)
			Why(arg)
		end },
	},
	options = {
		{ type = "header", label = "Tooltip lines" },
		{ type = "checkbox", key = "keys", label = "Keys for chests",
			tooltip = "On a delve's Bountiful Coffer: the key it needs and how many you have." },
		{ type = "checkbox", key = "rep", label = "Reputation tokens",
			tooltip = "On an item or currency that gives reputation: the faction, your standing, and a warning when you're already maxed." },
		{ type = "checkbox", key = "reagents", label = "Reagents of combine items",
			tooltip = "On an item you combine or craft into something else: what it takes, how many you own, and how many you can make." },
		{ type = "checkbox", key = "vendors", label = "Where to spend tokens",
			tooltip = "On a token traded at a particular vendor: who and where. Ctrl-click it in your bags to set a waypoint there." },

		{ type = "header", label = "Choice windows" },
		{ type = "checkbox", key = "choice", label = "Show what you own", onChange = RefreshChoice,
			tooltip = "Under a choice window: how many you own of the token it takes and of each reward on offer." },
	},
})
