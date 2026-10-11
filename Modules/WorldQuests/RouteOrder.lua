local addonName, ns = ...

-- World quest routes: the order to visit stops in (pure, no WoW API; tests/test_gold.lua). Route.lua reads the spots
-- and runs the route.

local sqrt = math.sqrt

local function Dist(a, b)
	if not b then
		return 0
	end
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- Shortens an open path in place by reversing stretches (2-opt). path[1] stays first.
local function Untangle(path)
	local n = #path
	for _ = 1, 50 do
		local better = false
		for i = 1, n - 2 do
			for j = i + 2, n do
				local a, b, c, d = path[i], path[i + 1], path[j], path[j + 1]
				if Dist(a, c) + Dist(b, d) < Dist(a, b) + Dist(c, d) - 1e-9 then
					local lo, hi = i + 1, j
					while lo < hi do
						path[lo], path[hi] = path[hi], path[lo]
						lo, hi = lo + 1, hi - 1
					end
					better = true
				end
			end
		end
		if not better then
			return
		end
	end
end

-- Nearest stop next from `from`, then untangled. Returns the stops in order (without `from` when it isn't a stop).
local function PathFrom(from, stops)
	local left = {}
	for i, s in ipairs(stops) do
		left[i] = s
	end
	local path = { from }
	while #left > 0 do
		local last, best, bestDist = path[#path], 1, math.huge
		for i, s in ipairs(left) do
			local d = Dist(last, s)
			if d < bestDist then
				best, bestDist = i, d
			end
		end
		path[#path + 1] = table.remove(left, best)
	end
	Untangle(path)
	table.remove(path, 1)
	return path
end

-- stops: { { id, cont, x, y, weight } } (world coordinates; cont = the continent they're measured on; weight = gold or
-- 1). start: { cont, x, y } where you stand, or nil. Returns the stop IDs in route order: your continent first (from
-- where you stand), then the other continents, heaviest first, each from its heaviest stop.
function ns.WQ_RouteOrder(stops, start)
	local byCont, conts = {}, {}
	for _, s in ipairs(stops) do
		local list = byCont[s.cont]
		if not list then
			list = { total = 0 }
			byCont[s.cont] = list
			conts[#conts + 1] = s.cont
		end
		list[#list + 1] = s
		list.total = list.total + (s.weight or 0)
	end
	table.sort(conts, function(a, b)
		local here = start and start.cont
		if (a == here) ~= (b == here) then
			return a == here
		end
		if byCont[a].total ~= byCont[b].total then
			return byCont[a].total > byCont[b].total
		end
		return a < b
	end)
	local ids = {}
	for _, cont in ipairs(conts) do
		local list = byCont[cont]
		local path
		if start and start.cont == cont then
			path = PathFrom({ x = start.x, y = start.y }, list)
		else
			table.sort(list, function(a, b)
				if (a.weight or 0) ~= (b.weight or 0) then
					return (a.weight or 0) > (b.weight or 0)
				end
				return a.id < b.id
			end)
			local first = table.remove(list, 1)
			path = PathFrom(first, list)
			table.insert(path, 1, first)
		end
		for _, s in ipairs(path) do
			ids[#ids + 1] = s.id
		end
	end
	return ids
end
