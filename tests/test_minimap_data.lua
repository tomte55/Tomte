-- Run from the AddOns folder: lua Tomte/tests/test_minimap_data.lua
local ns = {}
assert(loadfile("Tomte/Core/MinimapData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

test("map spot: a world point back to the map, axes turned as the world's", function()
	-- World x falls as map y grows, world y falls as map x grows (the client's axes); 2000 by 1000 yards.
	local corner = { 5000, 3000, 0, -2000, -1000, 0 }
	local x, y = ns.Mini_MapSpot(5000 - 0.4 * 1000, 3000 - 0.25 * 2000, corner)
	near(x, 0.25, "map x"); near(y, 0.4, "map y")
	x, y = ns.Mini_MapSpot(5000, 3000, corner)
	near(x, 0, "top left"); near(y, 0)
	eq(ns.Mini_MapSpot(1, 1, { 0, 0, 0, 0, 0, 0 }), nil, "no area")
end)

test("offset: east and north in yards", function()
	local e, n = ns.Mini_Offset(0.6, 0.4, 0.5, 0.5, 1000, 2000)
	near(e, 100, "east"); near(n, 200, "north (map y grows south)")
end)

test("rotating minimap: what you face is up", function()
	-- A spot due west, the player facing west (pi/2 counterclockwise from north): straight up.
	local e, n = ns.Mini_Offset(0.4, 0.5, 0.5, 0.5, 1000, 1000, math.pi / 2)
	near(e, 0, "x"); near(n, 100, "up")
	-- A spot due north, the player facing east (3/2 pi): to the left.
	e, n = ns.Mini_Offset(0.5, 0.4, 0.5, 0.5, 1000, 1000, math.pi * 1.5)
	near(e, -100, "left"); near(n, 0, "y")
	-- Facing north: nothing turns.
	e, n = ns.Mini_Offset(0.6, 0.5, 0.5, 0.5, 1000, 1000, 0)
	near(e, 100); near(n, 0)
end)

test("inside a round or square minimap", function()
	eq(ns.Mini_Inside(70, 70, 100, true), true)
	eq(ns.Mini_Inside(80, 80, 100, true), false, "the corner is outside a circle")
	eq(ns.Mini_Inside(80, 80, 100, false), true, "and inside a square")
	eq(ns.Mini_Inside(101, 0, 100, false), false)
end)

test("clamp to the edge", function()
	local x, y = ns.Mini_Clamp(300, 400, 100, true)
	near(x, 60); near(y, 80)
	x, y = ns.Mini_Clamp(300, 150, 100, false)
	near(x, 100); near(y, 50)
	x, y = ns.Mini_Clamp(0, 0, 100, true)
	eq(x, 0); eq(y, 0)
end)

test("clip a leg to a circle", function()
	local x1, y1, x2, y2 = ns.Mini_Clip(-200, 0, 200, 0, 100, true)
	near(x1, -100); near(y1, 0); near(x2, 100); near(y2, 0)
	x1, y1, x2, y2 = ns.Mini_Clip(0, 0, 50, 0, 100, true)
	near(x1, 0); near(x2, 50, "inside stays whole")
	eq(ns.Mini_Clip(-200, 150, 200, 150, 100, true), nil, "passes above")
	eq(ns.Mini_Clip(150, 0, 300, 0, 100, true), nil, "all outside on one side")
	x1, y1, x2, y2 = ns.Mini_Clip(0, 0, 0, 300, 100, true)
	near(y2, 100, "leaves through the edge")
	eq(ns.Mini_Clip(10, 10, 10, 10, 100, true), 10, "a dot inside")
end)

test("clip a leg to a square", function()
	local x1, y1, x2, y2 = ns.Mini_Clip(-200, 50, 200, 50, 100, false)
	near(x1, -100); near(y1, 50); near(x2, 100); near(y2, 50)
	eq(ns.Mini_Clip(-200, 150, 200, 150, 100, false), nil)
	x1, y1, x2, y2 = ns.Mini_Clip(0, 0, 200, 200, 100, false)
	near(x2, 100); near(y2, 100, "to the corner")
	-- A diagonal leg that cuts a circle's corner area but misses it is still in the square.
	eq(ns.Mini_Clip(70, 120, 120, 70, 100, true), nil, "misses the circle")
	eq(ns.Mini_Clip(70, 120, 120, 70, 100, false) ~= nil, true, "crosses the square's corner")
end)

test("world offset through the map's axes", function()
	-- WoW's world x runs north and y west: east is -y, north is +x.
	local axes = { ex = 0, ey = -1, nx = 1, ny = 0 }
	local e, n = ns.Mini_WorldOffset(30, -40, axes)
	near(e, 40, "east"); near(n, 30, "north")
end)

test("strips follow the circle at their middles", function()
	local strips = ns.Mini_Strips(100, 10)
	eq(#strips, 10)
	near(strips[1].top, 100, "first starts at the top")
	near(strips[10].top - strips[10].height, -100, "last ends at the bottom")
	near(strips[1].halfWidth, math.sqrt(100 * 100 - 90 * 90), "top strip: chord at y 90")
	near(strips[5].halfWidth, math.sqrt(100 * 100 - 10 * 10), "middle strip: chord at y 10")
	near(strips[6].halfWidth, strips[5].halfWidth, "symmetric")
	for _, s in ipairs(strips) do
		local mid = s.top - s.height / 2
		near(s.halfWidth * s.halfWidth + mid * mid, 100 * 100, "the middle's ends are on the circle")
	end
end)

H.done()
