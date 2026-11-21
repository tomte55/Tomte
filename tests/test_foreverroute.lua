-- Run from the AddOns folder: lua Tomte/tests/test_foreverroute.lua
local ns = {}
assert(loadfile("Tomte/Modules/Travel/ForeverRouteData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- Two continents: 1 (Thunder Bluff and Orgrimmar) and 0 (Grom'gol and Booty Bay), yards.
local KAL, EK = 1, 0

local function Place(map, x, y, name, kind)
	return { map = map, x = x, y = y, name = name, kind = kind }
end

local function World(bootyBayTaxi)
	local places = {
		Place(KAL, 0, 0, "Thunder Bluff", "taxi"), -- 1
		Place(KAL, 3000, 0, "Orgrimmar", "taxi"), -- 2
		Place(KAL, 3100, 0, "Orgrimmar", "dock"), -- 3: the zeppelin tower
		Place(EK, 0, 0, "Grom'gol", "dock"), -- 4
		Place(EK, 50, 0, "Grom'gol", "taxi"), -- 5
	}
	if bootyBayTaxi then
		places[6] = Place(EK, 0, 1500, "Booty Bay", "taxi")
	end
	return { places = places, links = { { a = 3, b = 4, kind = "zeppelin" } } }
end

local YOU = { map = KAL, x = 10, y = 10 }
local HEMING = { map = EK, x = 100, y = 1500 }

local function Texts(graph, plan)
	local out = {}
	for i, step in ipairs(plan.steps) do
		out[i] = ns.WayForever_StepText(graph, step)
	end
	return table.concat(out, ", ")
end

test("another continent: fly, zeppelin, fly", function()
	local graph = World(true)
	local plan = ns.WayForever_Plan(graph, YOU, HEMING)
	eq(Texts(graph, plan), "Fly to Orgrimmar, Take the zeppelin to Grom'gol, Fly to Booty Bay")
	eq(plan.steps[1].from, 1, "the first pin: Thunder Bluff's flight master")
	eq(plan.walk, nil)
end)

test("a flight path you don't know: ride from the dock", function()
	local graph = World(false)
	local plan = ns.WayForever_Plan(graph, YOU, HEMING)
	eq(Texts(graph, plan), "Fly to Orgrimmar, Take the zeppelin to Grom'gol")
end)

test("no way across: no steps, no cost", function()
	local graph = { places = { Place(KAL, 0, 0, "Thunder Bluff", "taxi") }, links = {} }
	local plan = ns.WayForever_Plan(graph, YOU, HEMING)
	eq(#plan.steps, 0)
	eq(plan.cost, nil)
end)

test("close by: walk", function()
	local graph = World(true)
	local plan = ns.WayForever_Plan(graph, YOU, { map = KAL, x = 400, y = 0 })
	eq(#plan.steps, 0)
	eq(plan.cost, plan.walk)
end)

test("far on the same continent: fly when it's clearly quicker", function()
	local graph = World(true)
	local plan = ns.WayForever_Plan(graph, YOU, { map = KAL, x = 3050, y = 100 })
	eq(Texts(graph, plan), "Fly to Orgrimmar")
end)

test("a route barely quicker than walking isn't taken", function()
	local graph = World(true)
	-- Walking 1200 yards: 120 s. Flying from right here to Orgrimmar's flight master... not near: walk.
	local plan = ns.WayForever_Plan(graph, { map = KAL, x = 1900, y = 0 }, { map = KAL, x = 3000, y = 0 })
	eq(#plan.steps, 0)
end)

test("following: the step stays unless another way is clearly quicker", function()
	local places = {
		Place(KAL, 0, 0, "Near", "taxi"), -- 1
		Place(KAL, 0, 120, "Other", "taxi"), -- 2: a little nearer the goal's flight master
		Place(KAL, 6000, 0, "Far", "taxi"), -- 3
	}
	local graph = { places = places, links = {} }
	local start, goal = { map = KAL, x = 0, y = 60 }, { map = KAL, x = 6000, y = 50 }
	local free = ns.WayForever_Plan(graph, start, goal)
	local kept = ns.WayForever_Plan(graph, start, goal, free.steps[1].from == 1 and 2 or 1)
	eq(#kept.steps, 1)
	eq(kept.steps[1].from ~= free.steps[1].from, true, "the followed one stays")
	places[2].y = 1500 -- now the followed one is far off
	local far = ns.WayForever_Plan(graph, start, goal, 2)
	eq(far.steps[1].from, 1, "much quicker the other way: changed")
end)

test("following: walking takes over once it's no slower", function()
	local graph = World(true)
	local landed = { map = EK, x = 0, y = 1500 }
	local plan = ns.WayForever_Plan(graph, landed, HEMING, 6)
	eq(#plan.steps, 0)
end)

test("memo: the same plans while you move, worked out again for a new goal or graph", function()
	local graph, memo = World(true), {}
	local plain = ns.WayForever_Plan(graph, YOU, HEMING)
	local first = ns.WayForever_Plan(graph, YOU, HEMING, nil, memo)
	local cost = memo.cost
	eq(first.steps[1].from, plain.steps[1].from)
	eq(#first.steps, #plain.steps)
	local moved = ns.WayForever_Plan(graph, { map = YOU.map, x = YOU.x + 40, y = YOU.y }, HEMING, nil, memo)
	eq(memo.cost, cost, "kept while the goal stays")
	eq(moved.steps[1].from, plain.steps[1].from)
	ns.WayForever_Plan(graph, YOU, { map = HEMING.map, x = HEMING.x + 1, y = HEMING.y }, nil, memo)
	eq(memo.cost ~= cost, true, "a new goal")
	cost = memo.cost
	ns.WayForever_Plan(World(true), YOU, { map = HEMING.map, x = HEMING.x + 1, y = HEMING.y }, nil, memo)
	eq(memo.cost ~= cost, true, "a new graph")
end)

test("same plan: the same steps on the same graph", function()
	local graph = World(true)
	local a = ns.WayForever_Plan(graph, YOU, HEMING)
	local b = ns.WayForever_Plan(graph, { map = YOU.map, x = YOU.x + 5, y = YOU.y }, HEMING)
	eq(ns.WayForever_SamePlan(a, b), true)
	a.graph, b.graph = graph, {}
	eq(ns.WayForever_SamePlan(a, b), false, "planned on another graph")
	b.graph = graph
	b.steps[#b.steps] = nil
	eq(ns.WayForever_SamePlan(a, b), false, "a step less")
	eq(ns.WayForever_SamePlan(a, nil), false)
end)

test("lines for chat", function()
	local graph = World(true)
	local plan = ns.WayForever_Plan(graph, YOU, HEMING)
	local lines = ns.WayForever_Lines(graph, plan, "Old Man Heming")
	eq(lines[1], "Fly to Orgrimmar (from Thunder Bluff)")
	eq(lines[2], "Take the zeppelin to Grom'gol (from Orgrimmar)")
	eq(lines[4], "Walk to Old Man Heming")
end)

H.done()
