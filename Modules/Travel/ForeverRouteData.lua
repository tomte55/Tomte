local addonName, ns = ...

-- Waypoints on World of Warcraft: Forever: routes by flight path, zeppelin and boat: pure logic (no WoW API calls;
-- unit-tested in tests/test_foreverroute.lua). The game is read and the pin moved in ForeverRouter.lua; the zeppelins
-- and boats are in Data/Forever/Transports.lua.
--
-- A place is { map (the continent's instance ID), x, y (world yards), name, kind ("taxi" or "dock") }. A graph is
-- { places = { place, ... }, links = { { a = index, b = index, kind = "zeppelin" or "boat" }, ... } }. Any two flight
-- masters on one continent are taken as linked by air, and any two places on one continent by land.

local WALK_SPEED = 10 -- yards per second: riding most of the way (a mount is 11, running 7)
local FLY_SPEED = 30 -- yards per second on a flight path
local FLY_DETOUR = 1.25 -- flights follow the roads between flight masters, not a straight line
local FLY_WAIT = 20 -- seconds: talking to the flight master, taking off and landing
local SHIP_COST = { zeppelin = 210, boat = 270 } -- seconds: half the wait for the next one, and the crossing
-- A route is taken only when it takes at most this share of walking's time and saves at least this many seconds.
local WORTH_SHARE, WORTH_SECONDS = 0.8, 60
-- The step being followed stays while its way is at most this much slower than the best one (share, or seconds):
-- a slightly better way found on a boat or at a dock mustn't make the pin jump about.
local KEEP_SHARE, KEEP_SECONDS = 1.15, 30
local STEP_WORDS = { fly = "Fly to %s", zeppelin = "Take the zeppelin to %s", boat = "Take the boat to %s" }

local sqrt = math.sqrt
local huge = math.huge

local function Distance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- Seconds on foot (or mount) between two points, nil across continents.
local function Walk(a, b)
	if a.map ~= b.map then
		return nil
	end
	return Distance(a, b) / WALK_SPEED
end

local function Fly(a, b)
	return FLY_WAIT + Distance(a, b) * FLY_DETOUR / FLY_SPEED
end

-- Each place's ways out other than walking: { to, kind, cost }.
local function Ways(graph)
	local ways = {}
	local places = graph.places
	for i = 1, #places do
		ways[i] = {}
	end
	for i = 1, #places do
		local a = places[i]
		if a.kind == "taxi" then
			for j = i + 1, #places do
				local b = places[j]
				if b.kind == "taxi" and b.map == a.map then
					local cost = Fly(a, b)
					ways[i][#ways[i] + 1] = { to = j, kind = "fly", cost = cost }
					ways[j][#ways[j] + 1] = { to = i, kind = "fly", cost = cost }
				end
			end
		end
	end
	for _, link in ipairs(graph.links or {}) do
		local cost = SHIP_COST[link.kind] or SHIP_COST.boat
		ways[link.a][#ways[link.a] + 1] = { to = link.b, kind = link.kind, cost = cost }
		ways[link.b][#ways[link.b] + 1] = { to = link.a, kind = link.kind, cost = cost }
	end
	return ways
end

-- Seconds from every place to the goal, and each place's next hop toward it ({ to = index or "goal", kind }). Every way
-- goes both directions, so this is one Dijkstra from the goal.
local function FromGoal(graph, goal)
	local places = graph.places
	local n = #places
	local ways = Ways(graph)
	local cost, nextHop, done = {}, {}, {}
	for i = 1, n do
		local walk = Walk(places[i], goal)
		cost[i] = walk or huge
		nextHop[i] = walk and { to = "goal", kind = "walk" } or nil
	end
	for _ = 1, n do
		local u, best = nil, huge
		for i = 1, n do
			if not done[i] and cost[i] < best then
				u, best = i, cost[i]
			end
		end
		if not u then
			break
		end
		done[u] = true
		for v = 1, n do
			if not done[v] then
				local walk = Walk(places[v], places[u])
				if walk and best + walk < cost[v] then
					cost[v], nextHop[v] = best + walk, { to = u, kind = "walk" }
				end
			end
		end
		for _, way in ipairs(ways[u]) do
			local v = way.to
			if not done[v] and best + way.cost < cost[v] then
				cost[v], nextHop[v] = best + way.cost, { to = u, kind = way.kind }
			end
		end
	end
	return cost, nextHop
end

-- The hops from place i to the goal that aren't on foot: { from, to, kind }.
local function Steps(nextHop, i)
	local steps, seen = {}, {}
	while i ~= "goal" and i and not seen[i] do
		seen[i] = true
		local hop = nextHop[i]
		if not hop then
			return nil
		end
		if hop.kind ~= "walk" then
			steps[#steps + 1] = { from = i, to = hop.to, kind = hop.kind }
		end
		i = hop.to
	end
	return steps
end

-- The seconds from each place to the goal don't depend on where you stand, so a route planned again every second only
-- needs them once per goal: memo keeps them while the graph (the same table, not changed) and the goal stay.
local function Memoized(memo, graph, goal)
	if not memo then
		return FromGoal(graph, goal)
	end
	if memo.graph ~= graph or memo.map ~= goal.map or memo.x ~= goal.x or memo.y ~= goal.y then
		memo.graph, memo.map, memo.x, memo.y = graph, goal.map, goal.x, goal.y
		memo.cost, memo.nextHop = FromGoal(graph, goal)
	end
	return memo.cost, memo.nextHop
end

-- The way from start to goal (both { map, x, y }). keep: the place the followed step boards at, or nil when no route
-- is being followed. memo: a table kept by the caller between plans to the same goal (see Memoized), or nil. Returns
-- { steps = { { from, to, kind }, ... }, cost (seconds), walk (seconds on foot straight there, nil across
-- continents) }; steps is empty when walking is the way (and cost nil when there's no way at all).
function ns.WayForever_Plan(graph, start, goal, keep, memo)
	local places = graph.places
	local cost, nextHop = Memoized(memo, graph, goal)
	local walk = Walk(start, goal)
	local first, firstCost = nil, huge
	local keepCost
	for i = 1, #places do
		local toPlace = Walk(start, places[i])
		if toPlace and cost[i] < huge then
			local total = toPlace + cost[i]
			if total < firstCost then
				first, firstCost = i, total
			end
			if keep and i == keep then
				keepCost = total
			end
		end
	end
	if keepCost and keepCost <= math.max(firstCost * KEEP_SHARE, firstCost + KEEP_SECONDS) then
		first, firstCost = keep, keepCost
	end
	if walk then
		-- Following a route, walking takes over once it's no slower; else a route must be clearly worth it.
		local better = keep and walk <= firstCost
			or not keep and not (firstCost <= walk * WORTH_SHARE and walk - firstCost >= WORTH_SECONDS)
		if not first or better then
			return { steps = {}, cost = walk, walk = walk }
		end
	end
	if not first then
		return { steps = {}, walk = walk }
	end
	local steps = Steps(nextHop, first)
	if not steps then
		return { steps = {}, walk = walk }
	end
	return { steps = steps, cost = firstCost, walk = walk }
end

-- What to do at a step's place: "Fly to Orgrimmar", "Take the zeppelin to Grom'gol".
-- Whether two plans take the same steps (and were planned on the same graph, plan.graph when the caller sets it): one
-- planned again to the same steps is kept, so its line on the map isn't drawn again every second.
function ns.WayForever_SamePlan(a, b)
	if not (a and b) or a.graph ~= b.graph or #a.steps ~= #b.steps then
		return false
	end
	for i, s in ipairs(a.steps) do
		local t = b.steps[i]
		if s.from ~= t.from or s.to ~= t.to or s.kind ~= t.kind then
			return false
		end
	end
	return true
end

function ns.WayForever_StepText(graph, step)
	local to = graph.places[step.to]
	return (STEP_WORDS[step.kind] or STEP_WORDS.boat):format(to and to.name or "?")
end

-- The whole route as lines for chat: each step from where it starts, then the walk to the pin (destName).
function ns.WayForever_Lines(graph, plan, destName)
	local lines = {}
	for _, step in ipairs(plan.steps) do
		local from = graph.places[step.from]
		lines[#lines + 1] = ("%s (from %s)"):format(ns.WayForever_StepText(graph, step), from and from.name or "?")
	end
	lines[#lines + 1] = "Walk to " .. (destName or "your pin")
	return lines
end
