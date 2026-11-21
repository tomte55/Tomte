-- Run from the AddOns folder: lua Tomte/tests/test_chat_recipes.lua
local ns = {}
assert(loadfile("Tomte/Modules/Social/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Chat/RecipeData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ENCHANTING, TAILORING = 333, 197
-- A low enchanter: knows the rod and a bracer enchant, not the boots ones.
local RECIPES = {
	{ id = 7421, name = "Runed Copper Rod", item = 6218, base = ENCHANTING, known = true },
	{ id = 7428, name = "Enchant Bracer - Minor Deflect", item = 0, base = ENCHANTING, known = true },
	{ id = 7418, name = "Enchant Bracer - Minor Health", item = 0, base = ENCHANTING, known = false },
	{ id = 13890, name = "Enchant Boots - Minor Speed", item = 0, base = ENCHANTING, known = false },
	{ id = 7457, name = "Enchant Bracer - Minor Stamina", item = 0, base = ENCHANTING, known = true },
	{ id = 13836, name = "Enchant Boots - Minor Stamina", item = 0, base = ENCHANTING, known = false },
	{ id = 14807, name = "Lesser Magic Wand", item = 11287, base = ENCHANTING, known = false },
	{ id = 13628, name = "Disenchant", item = 0, base = ENCHANTING, known = false },
	-- A profession you don't have (or the game didn't answer for): nothing known.
	{ id = 3915, name = "Brown Linen Shirt", item = 4344, base = TAILORING, known = false },
}
local WORDS = { prof = { "enchanting", "ench", "enchanter", "chanter" }, own = { "thorium" } }
local IGNORE = { "wts" }

local index = ns.Chat_RecipeIndex(RECIPES)

local function decide(text)
	return (ns.Chat_DecideRequest(text, WORDS, IGNORE, index))
end

test("RecipeIndex: only professions with a known recipe are read", function()
	eq(index.readable[ENCHANTING], true)
	eq(index.readable[TAILORING], nil)
	eq(index.byPhrase["brown linen shirt"], nil)
end)

test("RecipeIndex: one-word names don't count, enchant suffixes do", function()
	eq(index.byPhrase["disenchant"], nil)
	eq(#index.byPhrase["minor speed"], 1)
	eq(#index.byPhrase["minor stamina"], 2)
end)

test("The reported case: a boots enchant you don't know is hidden", function()
	eq(decide("If enchanter Enchant Boots - Minor Speed"), false)
	local _, why = ns.Chat_DecideRequest("If enchanter Enchant Boots - Minor Speed", WORDS, IGNORE, index)
	eq(why, "names a recipe you don't know (enchant boots - minor speed)")
end)

test("Asked for by its short name", function()
	eq(decide("LF ench minor speed on boots"), false)
	eq(decide("LF ench minor deflect"), true)
end)

test("A name shared by a known and an unknown recipe shows", function()
	eq(decide("need enchanter for minor stamina"), true)
end)

test("A plain profession request still shows", function()
	eq(decide("LF enchanter, tips"), true)
end)

test("A recipe you know shows without the profession's name", function()
	eq(decide("anyone make a Runed Copper Rod?"), true)
	local _, _, phrase = ns.Chat_DecideRequest("anyone make a Runed Copper Rod?", WORDS, IGNORE, index)
	eq(phrase, "runed copper rod")
end)

test("Links: enchant by spell, crafted item by item ID", function()
	local boots = "LF |cffffd000|Henchant:13890|h[Enchant Boots - Minor Speed]|h|r"
	eq(decide(boots), false)
	eq(decide("LF |cffffd000|Henchant:7428|h[Enchant Bracer - Minor Deflect]|h|r"), true)
	eq(decide("can someone make |cff1eff00|Hitem:11287::::::::20:::::|h[Lesser Magic Wand]|h|r ench"), false)
	local _, why, phrase = ns.Chat_DecideRequest("|cffffffff|Hitem:6218::::::::20:::::|h[Runed Copper Rod]|h|r",
		WORDS, IGNORE, index)
	eq(why, "names a recipe you know (link)")
	eq(phrase, nil)
end)

test("Your own keywords and ignore words win", function()
	eq(decide("enchanter for Enchant Boots - Minor Speed, paying thorium"), true)
	eq(decide("WTS Enchant Bracer - Minor Deflect"), false)
end)

test("Recipes of a profession you don't read decide nothing", function()
	eq(ns.Chat_RecipeVerdict("LF Brown Linen Shirt", index), nil)
	eq(decide("LF Brown Linen Shirt"), false) -- no keyword either
end)

test("Without an index it is the keyword filter", function()
	eq((ns.Chat_DecideRequest("If enchanter Enchant Boots - Minor Speed", WORDS, IGNORE, nil)), true)
	eq((ns.Chat_DecideRequest("Runed Copper Rod", WORDS, IGNORE, nil)), false)
	eq(ns.Chat_RecipeVerdict("x", ns.Chat_RecipeIndex({})), nil)
end)

test("Whole words only", function()
	eq(ns.Chat_RecipeVerdict("minor speeds", index), nil)
end)

H.done()
