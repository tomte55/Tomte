-- Run from the AddOns folder: lua Tomte/tests/test_xpdata.lua
local ns = {}
assert(loadfile("Tomte/Modules/Leveling/XPData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("what's left past the next level goes into the one after", function()
	-- Level 9, 2,010 XP to go, 4,290 in finished quests: 2,280 past level 10, of the 7,600 level 10 needs.
	local level, percent = ns.Leveling_XPBeyond(9, 4290 - 2010)
	eq(level, 10)
	eq(percent, 30)
end)

test("enough for several levels", function()
	-- 7,600 for level 10 and 4,400 more: level 11, half of its 8,800.
	local level, percent = ns.Leveling_XPBeyond(9, 7600 + 4400)
	eq(level, 11)
	eq(percent, 50)
end)

test("exactly the next level, and the level cap", function()
	eq(select(2, ns.Leveling_XPBeyond(9, 0)), 0)
	local level, percent = ns.Leveling_XPBeyond(59, 999999)
	eq(level, 60)
	eq(percent, nil, "nothing past the cap")
end)

test("a level the table doesn't know says nothing", function()
	eq(ns.Leveling_XPBeyond(70, 100), nil)
end)

H.done()
