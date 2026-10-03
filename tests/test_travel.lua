-- Run from the AddOns folder: lua Tomte/tests/test_travel.lua
local ns = {}
assert(loadfile("Tomte/Modules/Travel/Data.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end
local function near(actual, expected, label)
	if math.abs(actual - expected) > 0.001 then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

-- Distance and time text -----------------------------------------------------------------------------------

test("FormatDistance in yards groups thousands", function()
	eq(ns.Way_FormatDistance(12.4, false), "12 yd")
	eq(ns.Way_FormatDistance(1240, false), "1,240 yd")
	eq(ns.Way_FormatDistance(1234567, false), "1,234,567 yd")
	eq(ns.Way_FormatDistance(nil, false), nil)
end)

test("FormatDistance in meters switches to km at 1000 m", function()
	eq(ns.Way_FormatDistance(100, true), "91 m")
	eq(ns.Way_FormatDistance(1093, true), "999 m")
	eq(ns.Way_FormatDistance(1532, true), "1.4 km")
end)

test("FormatSetting shows yards as is and meters rounded to 5", function()
	eq(ns.Way_FormatSetting(325, false), "325 yd")
	eq(ns.Way_FormatSetting(325, true), "295 m")
	eq(ns.Way_FormatSetting(25, true), "25 m")
end)

test("FormatArrival", function()
	eq(ns.Way_FormatArrival(nil), nil)
	eq(ns.Way_FormatArrival(-1), nil)
	eq(ns.Way_FormatArrival(41.6), "42s")
	eq(ns.Way_FormatArrival(185), "3:05")
	eq(ns.Way_FormatArrival(3730), "1:02:10")
end)

-- Arrival estimate -----------------------------------------------------------------------------------------

test("UpdateArrival needs two samples and estimates from the closing speed", function()
	local s = ns.Way_NewArrival()
	eq(ns.Way_UpdateArrival(s, 1000, 0), nil)
	near(ns.Way_UpdateArrival(s, 990, 1), 990 / 10)
end)

test("UpdateArrival ignores samples closer than the minimum interval", function()
	local s = ns.Way_NewArrival()
	ns.Way_UpdateArrival(s, 1000, 0)
	ns.Way_UpdateArrival(s, 990, 1)
	near(ns.Way_UpdateArrival(s, 900, 1.05), 99)
end)

test("UpdateArrival smooths speed changes", function()
	local s = ns.Way_NewArrival()
	ns.Way_UpdateArrival(s, 1000, 0)
	ns.Way_UpdateArrival(s, 990, 1) -- 10 yd/s
	local seconds = ns.Way_UpdateArrival(s, 960, 2) -- 30 yd/s instant
	near(s.speed, 15)
	near(seconds, 960 / 15)
end)

test("UpdateArrival clears the time when moving away and resumes later", function()
	local s = ns.Way_NewArrival()
	ns.Way_UpdateArrival(s, 1000, 0)
	ns.Way_UpdateArrival(s, 990, 1)
	eq(ns.Way_UpdateArrival(s, 995, 2), nil)
	near(ns.Way_UpdateArrival(s, 985, 3), 985 / 10)
end)

test("UpdateArrival drops estimates over the cap", function()
	local s = ns.Way_NewArrival()
	ns.Way_UpdateArrival(s, 100000, 0)
	eq(ns.Way_UpdateArrival(s, 99999, 1), nil)
end)

-- Footer ---------------------------------------------------------------------------------------------------

test("FooterText per mode", function()
	eq(ns.Way_FooterText("none", "10 m", "5s", "Bob"), nil)
	eq(ns.Way_FooterText("distance", "10 m", "5s", "Bob"), "10 m")
	eq(ns.Way_FooterText("time", "10 m", "5s", "Bob"), "5s")
	eq(ns.Way_FooterText("time", "10 m", nil, "Bob"), nil)
	eq(ns.Way_FooterText("name", "10 m", "5s", "Bob"), "Bob")
	eq(ns.Way_FooterText("all", "10 m", "5s", "Bob"), "Bob\n10 m  ·  5s")
	eq(ns.Way_FooterText("all", "10 m", nil, nil), "10 m")
	eq(ns.Way_FooterText("all", nil, nil, "Bob"), "Bob")
end)

-- State ----------------------------------------------------------------------------------------------------

local OPTS = { card = true, cardDistance = 325, hideDistance = 25 }

test("State: nothing without a valid distance", function()
	eq(ns.Way_State({ valid = false, distance = 100 }, OPTS), "none")
	eq(ns.Way_State({ valid = true }, OPTS), "none")
end)

test("State: hidden on arrival or inside the quest area", function()
	eq(ns.Way_State({ valid = true, distance = 20 }, OPTS), "hidden")
	eq(ns.Way_State({ valid = true, distance = 500, inQuestArea = true }, OPTS), "hidden")
	eq(ns.Way_State({ valid = true, distance = 20, offscreen = true }, OPTS), "hidden")
end)

test("State: offscreen wins over card and far", function()
	eq(ns.Way_State({ valid = true, distance = 100, offscreen = true }, OPTS), "offscreen")
	eq(ns.Way_State({ valid = true, distance = 900, offscreen = true }, OPTS), "offscreen")
end)

test("State: card inside the card distance, unless cards are off", function()
	eq(ns.Way_State({ valid = true, distance = 300, hasDetails = true }, OPTS), "card")
	eq(ns.Way_State({ valid = true, distance = 400, hasDetails = true }, OPTS), "far")
	eq(ns.Way_State({ valid = true, distance = 300, hasDetails = true },
		{ card = false, cardDistance = 325, hideDistance = 25 }), "far")
end)

test("State: no card for a target without details", function()
	eq(ns.Way_State({ valid = true, distance = 100, hasDetails = false }, OPTS), "far")
	eq(ns.Way_State({ valid = true, distance = 100 }, OPTS), "far")
end)

-- Scale and arrow ------------------------------------------------------------------------------------------

test("DistanceScale is 1 at the base distance and clamped", function()
	near(ns.Way_DistanceScale(ns.WAY_SCALE_DISTANCE), 1)
	eq(ns.Way_DistanceScale(1), ns.WAY_SCALE_MAX)
	eq(ns.Way_DistanceScale(0), ns.WAY_SCALE_MAX)
	eq(ns.Way_DistanceScale(1000000), ns.WAY_SCALE_MIN)
	assert(ns.Way_DistanceScale(200) > ns.Way_DistanceScale(600))
end)

test("EdgePoint lands on the ellipse and points the arrow outward", function()
	local x, y, rot = ns.Way_EdgePoint(500, 0, 300, 200)
	near(x, 300)
	near(y, 0)
	near(rot, -math.pi / 2, "right is a quarter turn clockwise")
	x, y, rot = ns.Way_EdgePoint(0, 50, 300, 200)
	near(x, 0)
	near(y, 200)
	near(rot, 0, "up")
	x, y, rot = ns.Way_EdgePoint(0, -50, 300, 200)
	near(y, -200)
	near(math.abs(rot), math.pi, "down")
	x, y = ns.Way_EdgePoint(0, 0, 300, 200)
	near(x, 0)
	near(y, 200)
end)

test("EdgePoint stays on the line to the target", function()
	local x, y, rot = ns.Way_EdgePoint(100, 100, 300, 200)
	near(x, y, "45 degrees stays at 45 degrees")
	near((x / 300) ^ 2 + (y / 200) ^ 2, 1, "on the ellipse")
	near(rot, math.pi / 4 - math.pi / 2)
end)

test("TurnToward takes the short way round", function()
	near(ns.Way_TurnToward(0, 1, 0.5), 0.5)
	local a = ns.Way_TurnToward(3, -3, 0.5) -- across pi: should go up, not down
	assert(a > 3, "went the long way: " .. a)
	eq(ns.Way_TurnToward(1, 1.005, 0.5), 1.005)
end)

-- Styles ---------------------------------------------------------------------------------------------------

test("ApplyStyle sets the preset keys and the style", function()
	local db = { beam = true, footer = "all", card = false, arrow = false, scale = 1, metric = true }
	eq(ns.Way_ApplyStyle(db, "minimal"), true)
	eq(db.style, "minimal")
	eq(db.beam, false)
	eq(db.footer, "distance")
	eq(db.card, true)
	eq(db.scale, 0.85)
	eq(db.metric, true, "untouched")
	eq(ns.Way_ApplyStyle(db, "nope"), false)
	eq(db.style, "minimal")
end)

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
