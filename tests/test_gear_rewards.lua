-- Run from the AddOns folder: lua Tomte/tests/test_gear_rewards.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Gear/Rules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Gear/Rewards.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq
local Pick = ns.GearRewards_Pick

local function upgrade(pct)
	return { kind = "upgrade", pct = pct, warnings = 0, reasons = {} }
end
local function levelUp(diff, warnings)
	return { kind = "levelUp", ilvlDiff = diff, pct = 1, warnings = warnings or 0, reasons = {} }
end
local SIDE = { kind = "sidegrade", pct = 0.5, warnings = 0, reasons = {} }
local DOWN = { kind = "downgrade", pct = -8, warnings = 0, reasons = {} }
local NOPE = { kind = "notForYou", why = "cloth", reasons = {} }
local EMPTY = { kind = "empty", warnings = 0, reasons = {} }
local BUT = { kind = "upgradeBut", pct = 6, warnings = 1, reasons = { "Breaks your 4-set (4 > 3)" } }

test("the biggest clean upgrade wins", function()
	local best, sure = Pick({ { verdict = upgrade(2) }, { verdict = upgrade(5) }, { verdict = SIDE } })
	eq(best, 2, "best")
	eq(sure, true, "sure")
end)

test("a recipe of one of your professions, unless you know it", function()
	local profs = { { name = "Leatherworking", skill = 75 }, { name = "Skinning", skill = 90 } }
	local r = ns.GearRewards_RecipeFor({ name = "Leatherworking", level = 90 }, false, profs)
	eq(r.profession, "Leatherworking")
	eq(r.now, false, "75 of 90: later")
	eq(ns.GearRewards_RecipeText(r), "For your Leatherworking: learn it at 90")
	eq(ns.GearRewards_RecipeFor({ name = "Leatherworking", level = 60 }, false, profs).now, true)
	eq(ns.GearRewards_RecipeText({ profession = "Leatherworking", level = 60, now = true }),
		"For your Leatherworking: learn it now")
	eq(ns.GearRewards_RecipeFor({ name = "Leatherworking", level = 60 }, true, profs), nil, "known")
	eq(ns.GearRewards_RecipeFor({ name = "Tailoring", level = 60 }, false, profs), nil, "not yours")
	eq(ns.GearRewards_RecipeFor(nil, false, profs), nil, "no requirement line")
	eq(ns.GearRewards_RecipeFor({ name = "Khaz Algar Leatherworking", level = 25 }, false,
		{ { name = "Leatherworking", skill = 30 } }).now, true, "retail's expansion names")
end)

test("the recipe pick prefers one you can learn now", function()
	local later, now = { profession = "X", level = 90, now = false }, { profession = "X", level = 50, now = true }
	eq(ns.GearRewards_PickRecipe({ { recipe = later }, { verdict = SIDE }, { recipe = now } }), 3)
	eq(ns.GearRewards_PickRecipe({ { verdict = SIDE }, { recipe = later } }), 2)
	eq(ns.GearRewards_PickRecipe({ { verdict = SIDE } }), nil)
end)

test("no upgrade among the choices: no best", function()
	local best, sure = Pick({ { verdict = SIDE }, { verdict = DOWN }, { verdict = NOPE } })
	eq(best, nil, "best")
	eq(sure, false, "sure")
end)

test("choices without a verdict are skipped", function()
	eq(Pick({ { verdict = nil }, { verdict = upgrade(3) } }), 2)
	eq(Pick({ {}, {} }), nil)
end)

test("a clean upgrade beats a bigger one that needs checking", function()
	local best, sure = Pick({ { verdict = BUT }, { verdict = upgrade(2) } })
	eq(best, 2, "best")
	eq(sure, true, "sure")
end)

test("only a maybe-upgrade: picked, not sure", function()
	local best, sure = Pick({ { verdict = SIDE }, { verdict = BUT } })
	eq(best, 2, "best")
	eq(sure, false, "sure")
end)

test("an empty slot beats a stat upgrade", function()
	eq(Pick({ { verdict = upgrade(20) }, { verdict = EMPTY } }), 2)
end)

test("while leveling the bigger item level jump wins", function()
	eq(Pick({ { verdict = levelUp(3) }, { verdict = levelUp(8) }, { verdict = levelUp(5) } }), 2)
end)

test("a level-up with a warning only needs checking", function()
	local best, sure = Pick({ { verdict = levelUp(8, 1) }, { verdict = DOWN } })
	eq(best, 1, "best")
	eq(sure, false, "sure")
end)

test("ties go to the first choice", function()
	eq(Pick({ { verdict = upgrade(4) }, { verdict = upgrade(4) } }), 1)
end)

test("most gold: the highest sell price", function()
	local _, _, gold = Pick({ { sell = 1200 }, { sell = 125404 }, { sell = 9000 } })
	eq(gold, 2)
end)

test("most gold: nothing sells, no pick", function()
	local _, _, gold = Pick({ { sell = 0 }, {} })
	eq(gold, nil)
end)

test("most gold ties go to the first choice", function()
	local _, _, gold = Pick({ { sell = 500 }, { sell = 500 } })
	eq(gold, 1)
end)

H.done()
