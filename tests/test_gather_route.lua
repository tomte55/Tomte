-- Run from the AddOns folder: lua Tomte/tests/test_gather_route.lua
local ns = {}
ns.Thousands = function(n)
	local digits = tostring(math.floor(n))
	local head = (#digits - 1) % 3 + 1
	return digits:sub(1, head) .. digits:sub(head + 1):gsub("%d%d%d", ",%0")
end
assert(loadfile("Tomte/Modules/Gather/Route.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

local W, HT = 1000, 1000 -- yards: a square map, so 0.1 of it is 100 yards

local function Spots(list)
	local spots = {}
	for i, p in ipairs(list) do
		spots[i] = { x = p[1], y = p[2] }
	end
	return spots
end

local function Visits(route, n)
	local seen, count = {}, 0
	for _, s in ipairs(route.order) do
		if not seen[s] then
			seen[s] = true
			count = count + 1
		end
	end
	eq(count, #route.order, "no spot twice")
	if n then
		eq(#route.order, n, "spots in the loop")
	end
end

-- Spots on a circle, given in shuffled order: the best loop is the circle itself.
local function Circle(n, radius, seed)
	local pts = {}
	for i = 1, n do
		local a = 2 * math.pi * i / n
		pts[i] = { 0.5 + radius * math.cos(a), 0.5 + radius * math.sin(a) }
	end
	local r = seed
	for i = n, 2, -1 do
		r = (r * 1103515245 + 12345) % 2147483648
		local j = r % i + 1
		pts[i], pts[j] = pts[j], pts[i]
	end
	return Spots(pts)
end

test("too few spots or no map size give no loop", function()
	local route, why = ns.GatherRoute_Build(Spots({ { 0.1, 0.1 } }), W, HT)
	eq(route, nil); eq(why, "fewer than 2 spots")
	route, why = ns.GatherRoute_Build(Spots({ { 0.1, 0.1 }, { 0.2, 0.2 } }), 0, 0)
	eq(route, nil); eq(why, "map size unknown")
end)

test("two spots: there and back", function()
	local route = ns.GatherRoute_Build(Spots({ { 0.1, 0.1 }, { 0.4, 0.5 } }), W, HT)
	Visits(route, 2)
	near(route.length, 1000, "500 yards each way")
end)

test("a shuffled circle comes out as the circle", function()
	local n, radius = 40, 0.3
	local route = ns.GatherRoute_Build(Circle(n, radius, 7), W, HT)
	Visits(route, n)
	local perfect = n * 2 * radius * W * math.sin(math.pi / n)
	near(route.length / perfect, 1, "lap as long as the polygon")
end)

test("the same spots always give the same loop", function()
	local a = ns.GatherRoute_Build(Circle(30, 0.25, 3), W, HT)
	local b = ns.GatherRoute_Build(Circle(30, 0.25, 3), W, HT)
	eq(table.concat(a.order, ","), table.concat(b.order, ","))
	eq(a.order[1], 1, "starts at the first spot")
end)

test("2-opt removes crossings on a grid", function()
	local pts = {}
	for i = 0, 5 do
		for j = 0, 5 do
			pts[#pts + 1] = { 0.2 + i * 0.1, 0.2 + j * 0.1 }
		end
	end
	local route = ns.GatherRoute_Build(Spots(pts), W, HT)
	Visits(route, 36)
	-- The best tour of a 6x6 grid with 100-yard steps is 3600 yards; nearest neighbour alone is far worse.
	eq(route.length <= 3600 * 1.1, true, "within 10% of the best: " .. route.length)
end)

test("map size in yards: wide maps stretch x", function()
	local route = ns.GatherRoute_Build(Spots({ { 0.1, 0.5 }, { 0.2, 0.5 } }), 3000, 1000)
	near(route.length, 600, "0.1 of 3000 yards, both ways")
end)

test("tight leaves out a lone far-off spot, and not otherwise", function()
	local spots = Circle(20, 0.1, 5)
	spots[#spots + 1] = { x = 0.95, y = 0.95 }
	local full = ns.GatherRoute_Build(spots, W, HT)
	eq(full.dropped, 0)
	Visits(full, 21)
	local tight = ns.GatherRoute_Build(spots, W, HT, { tight = true })
	eq(tight.dropped, 1)
	Visits(tight, 20)
	for _, s in ipairs(tight.order) do
		eq(s ~= 21, true, "the far spot is gone")
	end
	eq(tight.length < full.length, true)
	local plain = ns.GatherRoute_Build(Circle(20, 0.3, 5), W, HT, { tight = true })
	eq(plain.dropped, 0, "an even loop keeps everything")
end)

test("tight never drops more than a quarter", function()
	local pts = {}
	for i = 1, 8 do
		pts[i] = { i * 0.11, (i % 2) * 0.8 + 0.1 }
	end
	local route = ns.GatherRoute_Build(Spots(pts), W, HT, { tight = true })
	eq(route.dropped <= 2, true)
end)

test("follow starts at the nearest spot, facing picks the way round", function()
	-- A square loop: 1 (0.2,0.2) top-left, 2 (0.8,0.2) top-right, 3 (0.8,0.8), 4 (0.2,0.8).
	local spots = Spots({ { 0.2, 0.2 }, { 0.8, 0.2 }, { 0.8, 0.8 }, { 0.2, 0.8 } })
	local route = ns.GatherRoute_Build(spots, W, HT)
	Visits(route, 4)
	local player = { x = 0.25, y = 0.22 }
	-- Facing east (3/2 pi, counterclockwise from north): next is spot 2.
	local k, dir = ns.GatherRoute_Start(route, spots, player, math.pi * 1.5, W, HT)
	eq(route.order[k], 1)
	local nk = ns.GatherRoute_Next(route, k, dir)
	eq(route.order[nk], 2, "east goes to the top-right")
	-- Facing south (pi): next is spot 4.
	k, dir = ns.GatherRoute_Start(route, spots, player, math.pi, W, HT)
	nk = ns.GatherRoute_Next(route, k, dir)
	eq(route.order[nk], 4, "south goes to the bottom-left")
end)

test("follow skips spots gathered a moment ago", function()
	local spots = Spots({ { 0.2, 0.2 }, { 0.8, 0.2 }, { 0.8, 0.8 }, { 0.2, 0.8 } })
	local route = ns.GatherRoute_Build(spots, W, HT)
	local recent = { [1] = true }
	local function Recent(s)
		return recent[s]
	end
	local k = ns.GatherRoute_Start(route, spots, { x = 0.21, y = 0.21 }, nil, W, HT, Recent)
	eq(route.order[k] ~= 1, true, "not the spot just mined")
	recent = { [1] = true, [2] = true }
	local at = 1
	for i, s in ipairs(route.order) do
		if s == 4 then
			at = i
		end
	end
	local nk, steps = ns.GatherRoute_Next(route, at, 1, Recent)
	eq(recent[route.order[nk]], nil, "lands on a fresh spot")
	eq(steps >= 1, true)
	recent = { true, true, true, true }
	nk, steps = ns.GatherRoute_Next(route, 2, 1, Recent)
	eq(nk, 3, "all recent: just the next one")
	eq(steps, 1)
end)

test("next wraps around both ways", function()
	local route = { order = { 5, 6, 7 } }
	eq(ns.GatherRoute_Next(route, 3, 1), 1)
	eq(ns.GatherRoute_Next(route, 1, -1), 3)
end)

test("route text", function()
	eq(ns.GatherRoute_Text({ order = { 1, 2, 3 }, length = 6304, dropped = 0 }), "3 spots, 6,300 yards a lap")
	eq(ns.GatherRoute_Text({ order = { 1, 2 }, length = 95, dropped = 2 }), "2 spots, 100 yards a lap, 2 far-off left out")
end)

test("a big map builds in reasonable time", function()
	local pts, r = {}, 11
	for i = 1, 800 do
		r = (r * 1103515245 + 12345) % 2147483648
		local x = (r % 10000) / 10000
		r = (r * 1103515245 + 12345) % 2147483648
		pts[i] = { x, (r % 10000) / 10000 }
	end
	local t = os.clock()
	local route = ns.GatherRoute_Build(Spots(pts), 6000, 6000, { tight = true })
	Visits(route)
	eq(os.clock() - t < 2, true, "took " .. (os.clock() - t) .. " s")
end)

H.done()
