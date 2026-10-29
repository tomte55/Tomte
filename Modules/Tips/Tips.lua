local addonName, ns = ...

-- Tooltip extras: small lines on tooltips (which key opens a chest, reputation tokens, reagents of combine items,
-- where a token is spent with Ctrl-click for a waypoint, whether an item has any use left) and item counts under
-- choice windows. Registers the module. Pure text and rules in Data.lua, game reads in Read.lua, the achievement
-- check in Scan.lua, tooltip lines in Tooltip.lua, choice windows in Choice.lua, data per expansion in
-- Data/<Expansion>/Tips.lua.

local module, db

local function RefreshChoice()
	if module.active then
		ns.TipsChoice_Refresh()
	end
end

-- The achievement check runs only while its line is on.
local function ToggleUse(on)
	if not module.active then
		return
	end
	if on then
		ns.TipsScan_Start()
	else
		ns.TipsScan_Stop()
	end
end

-- A switch row's preview: an example tooltip with that line kind on a real item (Tooltip.lua).
local function PreviewLine(kind)
	return function(host)
		return ns.TipsTooltip_Preview(host, kind, module)
	end
end

-- /tomte tips why: why the last bag item you pointed at got its "what's left to do" line (or none).
local function WhyUse()
	local last = ns.TipsTooltip_LastUse()
	if not last then
		ns.Print("point at an item in your bags first, or use /tomte tips why <item link or ID>")
		return
	end
	ns.Print(("%s (%d): %s."):format(C_Item.GetItemNameByID(last.itemID) or "item", last.itemID,
		last.reason or "?"))
end

-- /tomte tips why <item link or ID>: what each line kind knows about an item.
local function Why(arg)
	if not arg or arg == "" then
		WhyUse()
		return
	end
	local itemID = tonumber(arg) or tonumber(arg:match("item:(%d+)"))
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
	local achievement = ns.Tips_AchievementFor(itemID)
	print("  achievement: " .. (achievement or (ns.Tips_AchievementsScanned() and "none" or "still checking")))
end

module = ns.RegisterModule({
	key = "tips",
	name = "Tooltip extras",
	category = "interface",
	icon = 134332, -- inv_misc_note_06
	summary = "Extra lines on tooltips: keys, reputation tokens, reagents, where to spend tokens and items with no use left.",
	description = "Adds small lines to tooltips: which key opens a delve chest and how many you have, which faction a reputation token raises and whether you're already maxed, what a combine item needs and how many you own, and where a token is spent (Ctrl-click it in your bags for a waypoint). Items in your bags say when they have no use left (a book you've read, a toy you already know) and when an unfinished achievement needs them. Choice windows show how many you own of what they take and give.",
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
		use = true,
		choice = true,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			ns.TipsTooltip_Start(db)
			ns.TipsChoice_Start(db)
			if db.use then
				ns.TipsScan_Start()
			end
		else
			ns.TipsTooltip_Stop()
			ns.TipsChoice_Stop()
			ns.TipsScan_Stop()
		end
	end,
	commands = {
		{ "why", "what Tooltip extras knows about an item (link or ID); alone: why the last bag item got its "
			.. "\"use left\" line", function(arg)
			Why(arg)
		end },
	},
	options = {
		{ type = "header", label = "Tooltip lines" },
		{ type = "checkbox", key = "keys", label = "Keys for chests",
			preview = ns.Preview_When("keys", PreviewLine("keys")),
			tooltip = "On a delve's Bountiful Coffer: the key it needs and how many you have." },
		{ type = "checkbox", key = "rep", label = "Reputation tokens",
			preview = ns.Preview_When("rep", PreviewLine("rep")),
			tooltip = "On an item or currency that gives reputation: the faction, your standing, and a warning when you're already maxed." },
		{ type = "checkbox", key = "reagents", label = "Reagents of combine items",
			preview = ns.Preview_When("reagents", PreviewLine("reagents")),
			tooltip = "On an item you combine or craft into something else: what it takes, how many you own, and how many you can make." },
		{ type = "checkbox", key = "vendors", label = "Where to spend tokens",
			preview = ns.Preview_When("vendors", PreviewLine("vendors")),
			tooltip = "On a token traded at a particular vendor: who and where. Ctrl-click it in your bags to set a waypoint there." },
		{ type = "checkbox", key = "use", label = "Items with no use left", onChange = ToggleUse,
			tooltip = "On items in your bags: says when one is safe to delete or sell (a book with nothing else to it, a toy, mount, pet or recipe you already know), and when an unfinished achievement still needs it. Items it can't be sure about get no line." },

		{ type = "header", label = "Choice windows" },
		{ type = "checkbox", key = "choice", label = "Show what you own", onChange = RefreshChoice,
			preview = ns.Preview_When("choice", function(host)
				return ns.TipsChoice_Preview(host, module)
			end),
			tooltip = "Under a choice window: how many you own of the token it takes and of each reward on offer." },
	},
})
