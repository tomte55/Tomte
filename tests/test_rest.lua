-- Run from the AddOns folder: lua Tomte/tests/test_rest.lua
local ns = {}
assert(loadfile("Tomte/Modules/Rest/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local NAMES = { food = "Food", drink = "Drink", bandage = "First Aid" }

local function situation(extra)
	local s = { health = 1, healthAt = 0.7, manaAt = 0.7, food = 1, drink = 2, bandage = 3 }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

test("ItemKind goes by the item's spell", function()
	eq(ns.Rest_ItemKind("Food", NAMES), "food")
	eq(ns.Rest_ItemKind("Drink", NAMES), "drink")
	eq(ns.Rest_ItemKind("First Aid", NAMES), "bandage")
	eq(ns.Rest_ItemKind("Healing Potion", NAMES), nil)
	eq(ns.Rest_ItemKind(nil, NAMES), nil)
end)

test("Pick: plain before buff food, then the highest level, then the first", function()
	eq(ns.Rest_Pick({}), nil)
	eq(ns.Rest_Pick({ { itemID = 1, level = 5 }, { itemID = 2, level = 25 } }).itemID, 2)
	eq(ns.Rest_Pick({ { itemID = 1, level = 25 }, { itemID = 2, level = 25 } }).itemID, 1)
	eq(ns.Rest_Pick({ { itemID = 1, level = 45, buff = true }, { itemID = 2, level = 5, buff = false } }).itemID, 2)
	eq(ns.Rest_Pick({ { itemID = 1, level = 5, buff = false }, { itemID = 2, level = 45, buff = true } }).itemID, 1)
	eq(ns.Rest_Pick({ { itemID = 1, level = 45, buff = true } }).itemID, 1, "buff food when it's all there is")
	eq(ns.Rest_Pick({ { itemID = 1 }, { itemID = 2, level = 1 } }).itemID, 2, "level unknown")
end)

test("Plan: nothing to do when fine, or blocked", function()
	eq(ns.Rest_Plan(situation({ mana = 1 })).text, nil)
	eq(#ns.Rest_Plan(situation({ health = 0.1, blocked = true })).uses, 0)
	eq(ns.Rest_Plan(situation({ health = 0.1, blocked = true })).text, nil)
end)

test("Plan: food and drink by what's low", function()
	local both = ns.Rest_Plan(situation({ health = 0.5, mana = 0.5 }))
	eq(both.text, "Eat and drink")
	eq(both.uses[1], 1)
	eq(both.uses[2], 2)
	eq(both.icon, 1)
	eq(ns.Rest_Plan(situation({ health = 0.5, mana = 1 })).text, "Eat")
	eq(ns.Rest_Plan(situation({ health = 1, mana = 0.5 })).text, "Drink")
	eq(ns.Rest_Plan(situation({ health = 1, mana = 0.5 })).icon, 2)
	eq(ns.Rest_Plan(situation({ health = 0.7 })).text, nil, "exactly at the line is fine")
end)

test("Plan: a class without mana never drinks", function()
	local plan = ns.Rest_Plan(situation({ health = 0.5, mana = nil }))
	eq(plan.text, "Eat")
	eq(#plan.uses, 1)
end)

test("Plan: skips what's already going", function()
	eq(ns.Rest_Plan(situation({ health = 0.5, eating = true })).text, nil)
	local plan = ns.Rest_Plan(situation({ health = 0.5, mana = 0.5, eating = true }))
	eq(plan.text, "Drink")
	eq(#plan.uses, 1)
	eq(ns.Rest_Plan(situation({ health = 0.5, mana = 0.5, drinking = true })).text, "Eat")
end)

test("Plan: a bandage only with no food, not while Recently Bandaged", function()
	eq(ns.Rest_Plan(situation({ health = 0.5 })).uses[1], 1, "food first")
	local plan = ns.Rest_Plan(situation({ health = 0.5, food = false }))
	eq(plan.text, "Bandage")
	eq(plan.uses[1], 3)
	eq(ns.Rest_Plan(situation({ health = 0.5, food = false, bandaged = true })).text, nil, "waiting it out")
end)

test("Plan: says what's missing", function()
	local plan = ns.Rest_Plan(situation({ health = 0.5, food = false, bandage = false }))
	eq(plan.text, "No food")
	eq(plan.role, "warning")
	eq(plan.icon, nil)
	eq(ns.Rest_Plan(situation({ mana = 0.5, drink = false })).text, "No drink")
	eq(ns.Rest_Plan(situation({ health = 0.5, mana = 0.5, drink = false })).text, "Eat", "what it can do wins")
end)

test("Plan: health the game hides counts as low, as a press means you want to recover", function()
	local s = situation()
	s.health = nil
	eq(ns.Rest_Plan(s).text, "Eat")
	eq(ns.Rest_Plan(s).uses[1], 1)
	s.eating = true
	eq(ns.Rest_Plan(s).text, nil, "already eating: nothing to do")
	eq(#ns.Rest_Plan(s).uses, 0)
	s.eating = false
	s.food, s.bandage = nil, nil
	eq(ns.Rest_Plan(s).text, "No food")
end)

test("Plan: mana the game hides counts as low too", function()
	local s = situation({ manaUnknown = true })
	eq(ns.Rest_Plan(s).text, "Drink")
	s.drinking = true
	eq(ns.Rest_Plan(s).text, nil)
end)

test("CurvePoints: full below the setting, nothing from it up", function()
	local p = ns.Rest_CurvePoints(0.7)
	eq(p[1][2], 1)
	eq(p[2][1], 0.7)
	eq(p[2][2], 1)
	eq(p[3][2], 0)
	eq(p[4][1], 1)
	eq(p[4][2], 0)
	assert(p[3][1] > p[2][1], "points in order")
end)

test("Macro has a line per item", function()
	eq(ns.Rest_Macro({ 117, 159 }), "/use item:117\n/use item:159")
	eq(ns.Rest_Macro({}), "")
end)

test("JustLow only on the way down", function()
	eq(ns.Rest_JustLow(6, 5, 5), true)
	eq(ns.Rest_JustLow(5, 4, 5), false, "already low")
	eq(ns.Rest_JustLow(nil, 2, 5), false, "first read")
	eq(ns.Rest_JustLow(4, 6, 5), false, "went up")
	eq(ns.Rest_JustLow(6, 0, 0), false, "off")
end)

H.done()
