-- Run from the AddOns folder: lua Tomte/tests/test_petcare.lua
local ns = {}
assert(loadfile("Tomte/Modules/PetCare/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("wants food below happy", function()
	eq(ns.PetCare_WantsFood(1), true)
	eq(ns.PetCare_WantsFood(2), true)
	eq(ns.PetCare_WantsFood(3), false)
	eq(ns.PetCare_WantsFood(nil), false)
end)

test("PickFood: the lowest in range, so good food stays", function()
	local foods = { { itemID = 1, ilvl = 45 }, { itemID = 2, ilvl = 25 }, { itemID = 3, ilvl = 5 } }
	eq(ns.PetCare_PickFood(foods, 40).itemID, 2, "pet 40: 5 is out of range")
	eq(ns.PetCare_PickFood(foods, 10).itemID, 3, "pet 10: everything is in range")
	eq(ns.PetCare_PickFood(foods, 35).itemID, 3, "exactly 30 under counts")
end)

test("PickFood falls back to the highest when nothing's in range", function()
	local foods = { { itemID = 1, ilvl = 5 }, { itemID = 2, ilvl = 12 } }
	eq(ns.PetCare_PickFood(foods, 60).itemID, 2)
end)

test("PickFood keeps the first of equals, copes with no food and no level", function()
	local foods = { { itemID = 1, ilvl = 5 }, { itemID = 2, ilvl = 5 } }
	eq(ns.PetCare_PickFood(foods, 10).itemID, 1)
	eq(ns.PetCare_PickFood({}, 10), nil)
	eq(ns.PetCare_PickFood({ { itemID = 3 } }, nil).itemID, 3)
end)

test("Macro casts the spell, then uses the food", function()
	eq(ns.PetCare_Macro("Feed Pet", { bag = 2, slot = 7 }), "/cast Feed Pet\n/use 2 7")
end)

test("words", function()
	eq(ns.PetCare_Mood(1), "Unhappy")
	eq(ns.PetCare_Mood(3), "Happy")
	eq(ns.PetCare_Mood(nil), nil)
	eq(ns.PetCare_TrainingLeft(10, 4), 6)
	eq(ns.PetCare_TrainingLeft(4, 10), 0)
	eq(ns.PetCare_TrainingLeft(nil, nil), 0)
	eq(ns.PetCare_DietText({ "Meat", "Fish" }), "Meat, Fish")
	eq(ns.PetCare_DietText({}), nil)
end)

H.done()
