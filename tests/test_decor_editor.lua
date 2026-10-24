-- Run from the AddOns folder: lua Tomte/tests/test_decor_editor.lua
local ns = {}
assert(loadfile("Tomte/Modules/Decor/EditorData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

-- Dye slots as the game lists them: not always in display order.
local SLOTS = {
	{ ID = 12, orderIndex = 2, dyeColorID = 7 },
	{ ID = 11, orderIndex = 1, dyeColorID = 3 },
	{ ID = 13, orderIndex = 3 },
}

test("dye colors come in display order, 0 for an undyed slot", function()
	local colors = ns.DecorEditor_DyeColors(SLOTS)
	eq(#colors, 3)
	eq(colors[1], 3)
	eq(colors[2], 7)
	eq(colors[3], 0)
	eq(SLOTS[1].ID, 12, "the game's table isn't sorted in place")
end)

test("a decor without dye slots has no colors", function()
	eq(ns.DecorEditor_DyeColors({}), nil)
	eq(ns.DecorEditor_DyeColors(nil), nil)
end)

test("the plan changes only the slots that differ and clears extra ones", function()
	local target = {
		{ ID = 21, orderIndex = 1, dyeColorID = 3 },
		{ ID = 22, orderIndex = 2, dyeColorID = 9 },
		{ ID = 23, orderIndex = 3, dyeColorID = 5 },
		{ ID = 24, orderIndex = 4, dyeColorID = 1 },
	}
	local plan = ns.DecorEditor_DyePlan({ 3, 7, 0 }, target)
	eq(#plan, 3)
	eq(plan[1].slotID, 22)
	eq(plan[1].colorID, 7)
	eq(plan[2].slotID, 23)
	eq(plan[2].colorID, nil, "a 0 in the copy clears the slot")
	eq(plan[3].slotID, 24)
	eq(plan[3].colorID, nil, "a slot the copy doesn't have is cleared")
end)

test("matching dyes give an empty plan", function()
	local colors = ns.DecorEditor_DyeColors(SLOTS)
	eq(#ns.DecorEditor_DyePlan(colors, SLOTS), 0)
	assert(ns.DecorEditor_DyesMatch(colors, SLOTS))
	assert(not ns.DecorEditor_DyesMatch({ 3, 8, 0 }, SLOTS))
	assert(not ns.DecorEditor_DyesMatch(nil, SLOTS))
	eq(#ns.DecorEditor_DyePlan(nil, SLOTS), 0)
end)

test("place another picks the stored stack with the same dyes", function()
	local plain = { recordID = 5, variantIdentifier = 0 }
	local red = { recordID = 5, variantIdentifier = 1 }
	local variants = {
		{ entryVariantID = plain, numStored = 2, dyeSlots = { { ID = 1, orderIndex = 1 } } },
		{ entryVariantID = red, numStored = 1, dyeSlots = { { ID = 1, orderIndex = 1, dyeColorID = 4 } } },
	}
	eq(ns.DecorEditor_PickVariant(variants, { { ID = 1, orderIndex = 1, dyeColorID = 4 } }), red)
	eq(ns.DecorEditor_PickVariant(variants, { { ID = 1, orderIndex = 1 } }), plain)
	eq(ns.DecorEditor_PickVariant(variants, { { ID = 1, orderIndex = 1, dyeColorID = 9 } }), plain,
		"no stack with those dyes: any stored stack")
end)

test("place another skips empty stacks and falls back to an unredeemed copy", function()
	local only = { recordID = 6 }
	local variants = { { entryVariantID = only, numStored = 0, dyeSlots = {} } }
	eq(ns.DecorEditor_PickVariant(variants, {}), nil)
	eq(ns.DecorEditor_PickVariant(variants, {}, true), only)
	eq(ns.DecorEditor_PickVariant({}, {}, true), nil)
	eq(ns.DecorEditor_PickVariant(nil, nil), nil)
	local undyed = { recordID = 7 }
	eq(ns.DecorEditor_PickVariant({ { entryVariantID = undyed, numStored = 1, dyeSlots = {} } }, {}), undyed)
end)

test("the decor budget", function()
	assert(ns.DecorEditor_BudgetAllows(10, 100, true, 2))
	assert(ns.DecorEditor_BudgetAllows(98, 100, true, 2))
	assert(not ns.DecorEditor_BudgetAllows(99, 100, true, 2))
	assert(ns.DecorEditor_BudgetAllows(nil, nil, false, 5), "no budget here")
end)

test("hover lines", function()
	local info = { totalNumStored = 2, remainingRedeemable = 1, totalNumPlaced = 4, placementCost = 3 }
	local lines = ns.DecorEditor_HoverLines(info, true)
	eq(lines[1][1], "In storage: 3")
	eq(lines[2][1], "Placed in your houses: 4")
	eq(lines[3][1], "Decor budget cost: 3")
	eq(lines[4][1], "Alt: place another")
	local none = ns.DecorEditor_HoverLines({ totalNumStored = 0, placementCost = 1 }, true)
	eq(none[1][2], "textMuted")
	eq(#none, 2, "no Alt line with nothing to place")
	eq(#ns.DecorEditor_HoverLines(nil, true), 0)
	eq(#ns.DecorEditor_HoverLines(info, false), 3)
end)

test("clock text", function()
	eq(ns.DecorEditor_ClockText(14, 5, true), "14:05")
	eq(ns.DecorEditor_ClockText(9, 30, true), "09:30")
	eq(ns.DecorEditor_ClockText(14, 5, false), "2:05 PM")
	eq(ns.DecorEditor_ClockText(0, 0, false), "12:00 AM")
	eq(ns.DecorEditor_ClockText(12, 15, false, "am", "pm"), "12:15 pm")
end)

local HOUSES = {
	{ houseName = "Mira's Cottage", neighborhoodName = "Razorwind Shores", neighborhoodGUID = "n1", houseGUID = "h1",
		plotID = 4 },
	{ houseName = "Aldric's Hall", neighborhoodName = "Founder's Point", neighborhoodGUID = "n2", houseGUID = "h2",
		plotID = 9 },
	{ houseName = "No plot yet", neighborhoodGUID = "n3" },
}

test("house rows: your faction's first, unusable houses left out", function()
	local rows = ns.DecorEditor_HouseRows(HOUSES, { h1 = true })
	eq(#rows, 2)
	eq(rows[1].name, "Mira's Cottage")
	eq(rows[2].name, "Aldric's Hall")
	local byPlace = ns.DecorEditor_HouseRows(HOUSES, {})
	eq(byPlace[1].where, "Founder's Point")
	eq(#ns.DecorEditor_HouseRows(nil), 0)
end)

test("the Teleport home key", function()
	local rows = ns.DecorEditor_HouseRows(HOUSES, { h2 = true })
	eq(ns.DecorEditor_HomeAction(rows, true), "return")
	local action, house = ns.DecorEditor_HomeAction(rows, false)
	eq(action, "teleport")
	eq(house.houseGUID, "h2")
	eq(ns.DecorEditor_HomeAction({}, false), "none")
end)

test("the alert's decor by name", function()
	local entries = { { id = 10, name = "Oak Chair" }, { id = 11, name = "Lamp" } }
	eq(ns.DecorEditor_FindByName("Lamp", {}, entries), 11)
	eq(ns.DecorEditor_FindByName("Lamp", { Lamp = 99 }, entries), 99, "the decor that just arrived wins")
	eq(ns.DecorEditor_FindByName("Bed", {}, entries), nil)
	eq(ns.DecorEditor_FindByName(nil, {}, entries), nil)
	eq(ns.DecorEditor_FindByName("", nil, nil), nil)
end)

test("size next to a person", function()
	eq(ns.DecorEditor_PeopleText(3, 2), "about 1.5 people tall")
	eq(ns.DecorEditor_PeopleText(2, 2), "about 1 person tall")
	eq(ns.DecorEditor_PeopleText(nil, 2), nil)
end)

-- An atlas region in the middle of its file: 400 x 200 pixels at coords 0.2-0.6 by 0.1-0.3.
local WIDE = { width = 400, height = 200, leftTexCoord = 0.2, rightTexCoord = 0.6, topTexCoord = 0.1,
	bottomTexCoord = 0.3 }

test("art taller than the card keeps the full width and a band at the focus", function()
	-- The card is 4:1, the art 2:1: half the height stays.
	local l, r, t, b = ns.DecorEditor_ArtCrop(WIDE, 4, 0)
	near(l, 0.2)
	near(r, 0.6)
	near(t, 0.1)
	near(b, 0.2)
	l, r, t, b = ns.DecorEditor_ArtCrop(WIDE, 4, 1)
	near(t, 0.2)
	near(b, 0.3)
	l, r, t, b = ns.DecorEditor_ArtCrop(WIDE, 4, 0.5)
	near(t, 0.15)
	near(b, 0.25)
end)

test("art wider than the card keeps the full height and the middle", function()
	-- The card is 1:1, the art 2:1: the middle half of the width stays.
	local l, r, t, b = ns.DecorEditor_ArtCrop(WIDE, 1, 0)
	near(l, 0.3)
	near(r, 0.5)
	near(t, 0.1)
	near(b, 0.3)
end)

test("art crop without a usable region or size is nil", function()
	eq(ns.DecorEditor_ArtCrop(nil, 2), nil)
	eq(ns.DecorEditor_ArtCrop({ width = 0, height = 10 }, 2), nil)
	eq(ns.DecorEditor_ArtCrop(WIDE, 0), nil)
end)

test("neighborhood art covers only the painted part, both spellings of Durotar", function()
	local art = ns.DecorEditor_NeighborhoodArt("durotar")
	eq(art.file, 7490877)
	near(art.topTexCoord, 0.165)
	near(art.height, 1684 * 0.67)
	eq(ns.DecorEditor_NeighborhoodArt("duratar").file, 7490877)
	eq(ns.DecorEditor_NeighborhoodArt("elwynn").file, 7377860)
	eq(ns.DecorEditor_NeighborhoodArt("quelthalas"), nil)
	eq(ns.DecorEditor_NeighborhoodArt(nil), nil)
	-- A wide card crops a band inside the painted part.
	local _, _, t, b = ns.DecorEditor_ArtCrop(art, 3.4, art.focusY)
	assert(t >= 0.165 and b <= 0.835, "the band stays off the grey bars")
end)

test("a house card names its neighborhood only when the house name doesn't", function()
	eq(ns.DecorEditor_ShowNeighborhood("1 Hot Gravel Settlement", "Hot Gravel Settlement"), false)
	eq(ns.DecorEditor_ShowNeighborhood("1 hot gravel settlement", "Hot Gravel Settlement"), false)
	eq(ns.DecorEditor_ShowNeighborhood("Aldric's Cottage", "Hot Gravel Settlement"), true)
	eq(ns.DecorEditor_ShowNeighborhood(nil, "Hot Gravel Settlement"), true)
	eq(ns.DecorEditor_ShowNeighborhood("Aldric's Cottage", nil), false)
	eq(ns.DecorEditor_ShowNeighborhood("Aldric's Cottage", ""), false)
end)

test("the View Houses window shows every card up to the max, and room for one with none", function()
	eq(ns.DecorEditor_CardsShown(0, 3), 1)
	eq(ns.DecorEditor_CardsShown(nil, 3), 1)
	eq(ns.DecorEditor_CardsShown(2, 3), 2)
	eq(ns.DecorEditor_CardsShown(7, 3), 3)
end)

H.done()
