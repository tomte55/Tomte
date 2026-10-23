-- Run from the AddOns folder: lua Tomte/tests/test_gear_helpers.lua
local ns = {}
assert(loadfile("Tomte/Modules/Gear/HelperData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local GEM, RELIC = 3, 11 -- Enum.ItemClass.Gem, Enum.ItemGemSubclass.Artifactrelic

test("ordinary sockets take gems, special ones don't", function()
	eq(ns.GearHelpers_TakesGems({ "Prismatic" }), true, "prismatic")
	eq(ns.GearHelpers_TakesGems({ "Meta", "Red" }), true, "old colored")
	eq(ns.GearHelpers_TakesGems({ "Domination" }), false, "domination")
	eq(ns.GearHelpers_TakesGems({}), false, "none")
	eq(ns.GearHelpers_TakesGems(nil), false, "nil")
end)

test("gems are gem-class items that aren't relics", function()
	eq(ns.GearHelpers_IsGem(3, 7, GEM, RELIC), true, "haste gem")
	eq(ns.GearHelpers_IsGem(3, 11, GEM, RELIC), false, "relic")
	eq(ns.GearHelpers_IsGem(4, 7, GEM, RELIC), false, "armor")
	eq(ns.GearHelpers_IsGem(nil, nil, GEM, RELIC), false, "unknown")
end)

test("the first empty ordinary socket", function()
	local sockets = { { type = "Prismatic", filled = true }, { type = "Meta" }, { type = "Prismatic" } }
	eq(ns.GearHelpers_EmptySocket(sockets), 3, "skips filled and meta")
	eq(ns.GearHelpers_EmptySocket({ { type = "Prismatic", filled = true } }), nil, "all filled")
end)

test("gems ranked by weights, best marked, diamonds last", function()
	local weights = { HASTE = 1, MASTERY = 0.5 }
	local function score(stats)
		local sum = 0
		for key, amount in pairs(stats) do
			sum = sum + amount * (weights[key] or 0)
		end
		return sum
	end
	local gems = ns.GearHelpers_RankGems({
		{ itemID = 1, name = "Mastery gem", stats = { MASTERY = 10 } },
		{ itemID = 2, name = "Diamond", stats = { PRIMARY = { AGI = 5 } }, diamond = true },
		{ itemID = 3, name = "Haste gem", stats = { HASTE = 10 } },
		{ itemID = 4, name = "Crit gem", stats = { CRIT = 10 } },
	}, score)
	eq(gems[1].itemID, 3, "haste first")
	eq(gems[1].best, true, "haste best")
	eq(gems[2].itemID, 1, "mastery second")
	eq(gems[2].best, nil, "only one best")
	eq(gems[3].itemID, 4, "crit (worth 0) after")
	eq(gems[4].itemID, 2, "diamond last")
	eq(gems[4].best, nil, "diamond never best")
end)

test("no weights: no best, sorted by name", function()
	local gems = ns.GearHelpers_RankGems({ { itemID = 2, name = "B" }, { itemID = 1, name = "A" } }, nil)
	eq(gems[1].name, "A", "by name")
	eq(gems[1].best, nil, "no best")
end)

test("stronger border from rare up", function()
	eq(ns.GearHelpers_Glows(2), false, "uncommon")
	eq(ns.GearHelpers_Glows(3), true, "rare")
	eq(ns.GearHelpers_Glows(5), true, "legendary")
	eq(ns.GearHelpers_Glows(nil), false, "empty slot")
end)

test("sort direction setting", function()
	eq(ns.GearHelpers_SortRightToLeft("rtl"), true, "rtl")
	eq(ns.GearHelpers_SortRightToLeft("ltr"), false, "ltr")
	eq(ns.GearHelpers_SortRightToLeft("keep"), nil, "keep")
end)

test("character pane at the upgrade NPC", function()
	eq(ns.GearHelpers_ShouldOpenPane(true, false, false), true, "open")
	eq(ns.GearHelpers_ShouldOpenPane(true, true, false), false, "not in combat")
	eq(ns.GearHelpers_ShouldOpenPane(true, false, true), false, "already open")
	eq(ns.GearHelpers_ShouldOpenPane(false, false, false), false, "setting off")
	eq(ns.GearHelpers_ShouldClosePane(true, false, true), true, "close ours")
	eq(ns.GearHelpers_ShouldClosePane(false, false, true), false, "player's own")
	eq(ns.GearHelpers_ShouldClosePane(true, true, true), false, "not in combat")
end)

H.done()
