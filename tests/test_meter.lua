-- Run from the AddOns folder: lua Tomte/tests/test_meter.lua
local ns = {}
assert(loadfile("Tomte/Modules/Meter/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function list(t)
	return table.concat(t, " ")
end

test("the top lines, and your place below them when you're further down", function()
	eq(list(ns.Meter_Rows(5, 2, 3)), "1 2 3", "you're in the top three")
	eq(list(ns.Meter_Rows(5, 5, 3)), "1 2 3 5", "fifth: shown under them")
	eq(list(ns.Meter_Rows(2, 1, 3)), "1 2", "fewer sources than lines")
	eq(list(ns.Meter_Rows(4, nil, 3)), "1 2 3", "not in the ranking")
	eq(list(ns.Meter_Rows(0, nil, 3)), "", "nothing yet")
	eq(list(ns.Meter_Rows(3, 7, 3)), "1 2 3", "a place past the list is ignored")
end)

test("shows in a group in combat and for a while after; solo only when asked", function()
	local s = { grouped = true, solo = false, inCombat = true, linger = 10 }
	eq(ns.Meter_Shows(s), true)
	s.inCombat, s.endedAgo = false, 4
	eq(ns.Meter_Shows(s), true, "lingers")
	s.endedAgo = 10
	eq(ns.Meter_Shows(s), false, "gone after the linger")
	s.endedAgo = nil
	eq(ns.Meter_Shows(s), false, "no fight yet")
	eq(ns.Meter_Shows({ grouped = false, solo = false, inCombat = true, linger = 10 }), false, "solo")
	eq(ns.Meter_Shows({ grouped = false, solo = true, inCombat = true, linger = 10 }), true, "solo when asked")
end)

test("only in dungeons and raids when asked", function()
	local s = { grouped = true, inCombat = true, linger = 10, instancesOnly = true, inInstance = false }
	eq(ns.Meter_Shows(s), false, "out in the world")
	s.inInstance = true
	eq(ns.Meter_Shows(s), true, "in a dungeon")
	s.instancesOnly, s.inInstance = false, false
	eq(ns.Meter_Shows(s), true, "anywhere by default")
end)

test("which numbers a line shows", function()
	local function numbers(setting)
		local main, extra = ns.Meter_Numbers(setting)
		return main .. " " .. tostring(extra)
	end
	eq(numbers("rate"), "perSecond nil")
	eq(numbers("total"), "total nil")
	eq(numbers("both"), "perSecond total")
	eq(numbers(nil), "perSecond nil", "an unknown value falls back to per second")
end)

test("a saved spot fits the direction the meter grows", function()
	eq(ns.Meter_PointFits(nil, "up"), true, "the default spot")
	eq(ns.Meter_PointFits({ "TOPLEFT", "BOTTOMLEFT", 10, 500 }, "down"), true)
	eq(ns.Meter_PointFits({ "TOPLEFT", "BOTTOMLEFT", 10, 500 }, "up"), false)
	eq(ns.Meter_PointFits({ "BOTTOMLEFT", "BOTTOMLEFT", 10, 300 }, "up"), true)
	eq(ns.Meter_PointFits({ "BOTTOMRIGHT", "BOTTOMRIGHT", -330, 220 }, "down"), false)
end)

H.done()
