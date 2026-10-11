-- Run from the AddOns folder: lua Tomte/tests/test_minimap.lua
local ns = {}
assert(loadfile("Tomte/Modules/Minimap/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, near = H.test, H.near

test("Offset: round right", function()
	local x, y = ns.Minimap_Offset(0, 75, 75, nil)
	near(x, 75)
	near(y, 0)
end)

test("Offset: round 225", function()
	local x, y = ns.Minimap_Offset(225, 75, 75, "ROUND")
	near(x, -75 * math.sqrt(0.5))
	near(y, -75 * math.sqrt(0.5))
end)

test("Offset: square corner", function()
	-- On the diagonal, pulled 10 px in from the corner (as LibDBIcon does).
	local x, y = ns.Minimap_Offset(45, 75, 75, "SQUARE")
	local d = math.sqrt(0.5) * (math.sqrt(2 * 75 ^ 2) - 10)
	near(x, d)
	near(y, d)
end)

test("Offset: square edge middle", function()
	local x, y = ns.Minimap_Offset(90, 75, 75, "SQUARE")
	near(x, 0)
	near(y, 75)
end)

test("Offset: unknown shape counts as round", function()
	local x = ns.Minimap_Offset(0, 75, 75, "BLOB")
	near(x, 75)
end)

test("Angle wraps to 0-360", function()
	near(ns.Minimap_Angle(1, 0), 0)
	near(ns.Minimap_Angle(0, 1), 90)
	near(ns.Minimap_Angle(-1, -1), 225)
end)

H.done()
