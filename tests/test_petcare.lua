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

test("FoodValue goes by how far the food is under the pet", function()
	eq(ns.PetCare_FoodValue(30, 30), "full")
	eq(ns.PetCare_FoodValue(40, 30), "full", "above the pet")
	eq(ns.PetCare_FoodValue(15, 30), "full", "exactly 15 under")
	eq(ns.PetCare_FoodValue(14, 30), "half")
	eq(ns.PetCare_FoodValue(5, 30), "half", "exactly 25 under")
	eq(ns.PetCare_FoodValue(4, 30), "little")
	eq(ns.PetCare_FoodValue(nil, nil), "full", "nothing known")
end)

test("PickFood: the lowest that does a full feeding, so better food stays", function()
	local foods = { { itemID = 1, ilvl = 45 }, { itemID = 2, ilvl = 25 }, { itemID = 3, ilvl = 5 } }
	eq(ns.PetCare_PickFood(foods, 40).itemID, 2, "pet 40: 5 is too low to do much")
	eq(ns.PetCare_PickFood(foods, 10).itemID, 3, "pet 10: everything does a full feeding")
	eq(ns.PetCare_PickFood(foods, 20).itemID, 3, "exactly 15 under counts")
	eq(ns.PetCare_PickFood(foods, 21).itemID, 2, "16 under is too weak when there's better")
end)

test("PickFood falls back to the highest when nothing does a full feeding", function()
	local foods = { { itemID = 1, ilvl = 5 }, { itemID = 2, ilvl = 12 } }
	eq(ns.PetCare_PickFood(foods, 60).itemID, 2)
end)

test("SlimTraining keeps what can still be learned", function()
	local row = ns.PetCare_SlimTraining("Bite", "available", "(Rank 2)", 8, 7)
	eq(row.name, "Bite (Rank 2)")
	eq(row.level, 8)
	eq(row.cost, 7)
	eq(ns.PetCare_SlimTraining("Growl", "unavailable", "", 30, 9).name, "Growl", "no rank")
	eq(ns.PetCare_SlimTraining("Growl", "used", "", 1, 1), nil, "already learned")
	eq(ns.PetCare_SlimTraining("Growl", "available", "Rank 1", 1, 0), nil, "0 points: the pet already knows it")
	eq(ns.PetCare_SlimTraining("Growl", "available", "Rank 1", 1, nil), nil, "cost unknown")
	eq(ns.PetCare_SlimTraining("Group", "header"), nil)
	eq(ns.PetCare_SlimTraining(nil, "available"), nil)
end)

test("TrainingLearnable needs the points and the level", function()
	local rows = { { name = "A", cost = 5, level = 1 }, { name = "B", cost = 20, level = 1 }, { name = "C", cost = 1, level = 30 } }
	local list = ns.PetCare_TrainingLearnable(rows, 10, 10)
	eq(#list, 1)
	eq(list[1].name, "A")
	eq(#ns.PetCare_TrainingLearnable(rows, 25, 30), 3)
	eq(#ns.PetCare_TrainingLearnable(rows, 0, 30), 0)
end)

test("TrainingState speaks only when there's something to do", function()
	local rows = { { name = "A", cost = 10, level = 1 } }
	eq(ns.PetCare_TrainingState(nil, 0, 10), nil, "no points")
	eq(ns.PetCare_TrainingState(nil, 5, 10), "unread", "window never opened")
	eq(ns.PetCare_TrainingState({ rows = rows, seenLeft = 5, seenLevel = 10 }, 5, 10), nil, "seen, can't afford it")
	eq(ns.PetCare_TrainingState({ rows = rows, seenLeft = 5, seenLevel = 10 }, 9, 11), nil, "more, still not enough")
	eq(ns.PetCare_TrainingState({ rows = rows, seenLeft = 5, seenLevel = 10 }, 10, 11), "ready", "now it can")
	eq(ns.PetCare_TrainingState({ rows = rows, seenLeft = 10, seenLevel = 11 }, 10, 11), nil, "looked and left it")
	eq(ns.PetCare_TrainingState({ rows = {}, seenLeft = 5, seenLevel = 10 }, 50, 60), nil, "nothing left to learn")
end)

test("TrainingText names what it can learn", function()
	local rows = { { name = "A", cost = 5, level = 1 }, { name = "B", cost = 6, level = 1 }, { name = "C", cost = 90, level = 1 } }
	eq(ns.PetCare_TrainingText("ready", 10, rows, 5), "It can learn: A, B.")
	eq(ns.PetCare_TrainingText("unread", 12), "It has 12 training points to spend.")
end)

test("Label says what to do", function()
	eq(ns.PetCare_Label({ value = "full" }), "Click to feed")
	eq(ns.PetCare_Label({ value = "full", fedBefore = true }), "Still hungry: feed")
	eq(ns.PetCare_Label({ value = "half" }), "Feed: weak food")
	eq(ns.PetCare_Label({ value = "little", fedBefore = true }), "Feed: weak food")
	eq(ns.PetCare_Label({ value = "full", eatingLeft = 13.2 }), "Eating: 14s", "rounds up, wins over the rest")
	eq(select(2, ns.PetCare_Label({ value = "little" })), "warning")
end)

test("FoodTip warns about weak food only", function()
	eq(select(2, ns.PetCare_FoodTip("full")), "textMuted")
	eq(select(2, ns.PetCare_FoodTip("half")), "warning")
	eq(select(2, ns.PetCare_FoodTip("little")), "warning")
end)

test("PickFood keeps the first of equals, copes with no food and no level", function()
	local foods = { { itemID = 1, ilvl = 5 }, { itemID = 2, ilvl = 5 } }
	eq(ns.PetCare_PickFood(foods, 10).itemID, 1)
	eq(ns.PetCare_PickFood({}, 10), nil)
	eq(ns.PetCare_PickFood({ { itemID = 3 } }, nil).itemID, 3)
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
