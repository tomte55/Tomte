local addonName, ns = ...

-- Gathering routes: pure logic (no WoW API calls; unit-tested in tests/test_gather_route.lua). A loop through a map's
-- node spots (nearest neighbour, then 2-opt), far-off spots left out, and the follow rules: where to start, which way
-- round and which spot comes next. Spots are { x, y } in 0..1 map coordinates; w, h are the map's size in yards.
-- Cached and drawn by MapPins.lua, MinimapPins.lua and Follow.lua.

local K = 8 -- nearest neighbours per spot that 2-opt tries; more finds little and costs time
local MAX_SPOTS = 1000 -- no loop above this (built in one frame, about 0.15 s at 1000; no zone has that many spawn points)
local MAX_PASSES = 50 -- 2-opt passes; it settles in a handful
local EPS = 1e-6
local TIGHT_FACTOR = 3 -- a far-off spot's detour is this many median legs or more ...
local TIGHT_MIN = 300 -- ... and at least this many yards
local TIGHT_SHARE = 0.25 -- at most this share of the spots is left out

local atan2 = math.atan2 or math.atan -- Lua 5.1 (WoW, CI) has atan2; newer test runners take two arguments to atan

ns.GATHER_ROUTE_MAX = MAX_SPOTS

local function Dist(a, b, w, h)
	local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
	return math.sqrt(dx * dx + dy * dy)
end
ns.GatherRoute_Dist = Dist

-- [i] = up to K nearest other spots, nearest first.
local function Neighbours(spots, w, h)
	local n, lists = #spots, {}
	for i = 1, n do
		local near, dist = {}, {}
		for j = 1, n do
			if j ~= i then
				local d = Dist(spots[i], spots[j], w, h)
				if #near < K or d < dist[#near] then
					local k = math.min(#near, K - 1) + 1
					near[k], dist[k] = j, d
					while k > 1 and dist[k] < dist[k - 1] do
						near[k], near[k - 1] = near[k - 1], near[k]
						dist[k], dist[k - 1] = dist[k - 1], dist[k]
						k = k - 1
					end
				end
			end
		end
		lists[i] = near
	end
	return lists
end

local function NearestNeighbour(spots, near, w, h)
	local n = #spots
	local tour, seen = { 1 }, { [1] = true }
	local at = 1
	for step = 2, n do
		local best, bestD
		for _, j in ipairs(near[at]) do
			if not seen[j] then
				best = j
				break
			end
		end
		if not best then
			for j = 1, n do
				if not seen[j] then
					local d = Dist(spots[at], spots[j], w, h)
					if not bestD or d < bestD then
						best, bestD = j, d
					end
				end
			end
		end
		tour[step], seen[best] = best, true
		at = best
	end
	return tour
end

-- Reverses tour positions i..j (cyclic, inclusive), or the rest of the loop when that is shorter (same loop, mirrored).
local function Reverse(tour, pos, i, j)
	local n = #tour
	local len = (j - i) % n + 1
	if len * 2 > n then
		i, j = j % n + 1, (i - 2) % n + 1
		len = n - len
	end
	for _ = 1, math.floor(len / 2) do
		local a, b = tour[i], tour[j]
		tour[i], tour[j] = b, a
		pos[b], pos[a] = i, j
		i = i % n + 1
		j = (j - 2) % n + 1
	end
end

local function TwoOpt(spots, tour, near, w, h)
	local n = #tour
	if n < 4 then
		return
	end
	local pos = {}
	for i, s in ipairs(tour) do
		pos[s] = i
	end
	local function D(a, b)
		return Dist(spots[a], spots[b], w, h)
	end
	for _ = 1, MAX_PASSES do
		local improved = false
		for a = 1, n do
			for _, c in ipairs(near[a]) do
				local i, j = pos[a], pos[c]
				-- With a's next spot b and c's next spot d: legs a-b, c-d become a-c, b-d.
				local b, d = tour[i % n + 1], tour[j % n + 1]
				if c ~= b and d ~= a and D(a, c) + D(b, d) < D(a, b) + D(c, d) - EPS then
					Reverse(tour, pos, i % n + 1, j)
					improved = true
				else
					-- With their previous spots: legs ap-a, cp-c become a-c, ap-cp.
					i, j = pos[a], pos[c]
					local ap, cp = tour[(i - 2) % n + 1], tour[(j - 2) % n + 1]
					if c ~= ap and cp ~= a and D(a, c) + D(ap, cp) < D(ap, a) + D(cp, c) - EPS then
						Reverse(tour, pos, j, (i - 2) % n + 1)
						improved = true
					end
				end
			end
		end
		if not improved then
			return
		end
	end
end

local function Median(list)
	local sorted = {}
	for i, v in ipairs(list) do
		sorted[i] = v
	end
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return 0
	end
	return n % 2 == 1 and sorted[(n + 1) / 2] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

-- Drops far-off spots, worst detour first. Returns the shorter tour and how many were left out.
local function Tighten(spots, tour, w, h)
	local n = #tour
	if n < 5 then
		return tour, 0
	end
	local legs = {}
	for i = 1, n do
		legs[i] = Dist(spots[tour[i]], spots[tour[i % n + 1]], w, h)
	end
	local limit = math.max(TIGHT_FACTOR * Median(legs), TIGHT_MIN)
	local nextOf, prevOf, alive = {}, {}, {}
	for i = 1, n do
		nextOf[tour[i]], prevOf[tour[i]], alive[tour[i]] = tour[i % n + 1], tour[(i - 2) % n + 1], true
	end
	local function Detour(s)
		local p, q = prevOf[s], nextOf[s]
		return Dist(spots[p], spots[s], w, h) + Dist(spots[s], spots[q], w, h) - Dist(spots[p], spots[q], w, h)
	end
	local left, dropped = n, 0
	local maxDrop = math.floor(n * TIGHT_SHARE)
	while dropped < maxDrop and left > 4 do
		local worst, worstD
		for s in pairs(alive) do
			local d = Detour(s)
			if d > limit and (not worstD or d > worstD or (d == worstD and s < worst)) then
				worst, worstD = s, d
			end
		end
		if not worst then
			break
		end
		local p, q = prevOf[worst], nextOf[worst]
		nextOf[p], prevOf[q], alive[worst] = q, p, nil
		left, dropped = left - 1, dropped + 1
	end
	if dropped == 0 then
		return tour, 0
	end
	local start = tour[1]
	while not alive[start] do
		start = nextOf[start]
	end
	local out, s = {}, start
	repeat
		out[#out + 1] = s
		s = nextOf[s]
	until s == start
	return out, dropped
end

-- The loop: { order = { spot index... }, length = yards a lap, dropped = spots left out }, or nil, reason.
-- opts.tight leaves far-off spots out.
function ns.GatherRoute_Build(spots, w, h, opts)
	local n = #spots
	if n < 2 then
		return nil, "fewer than 2 spots"
	end
	if n > MAX_SPOTS then
		return nil, "too many spots"
	end
	if not (w and w > 0 and h and h > 0) then
		return nil, "map size unknown"
	end
	local near = Neighbours(spots, w, h)
	local tour = NearestNeighbour(spots, near, w, h)
	TwoOpt(spots, tour, near, w, h)
	local dropped = 0
	if opts and opts.tight then
		tour, dropped = Tighten(spots, tour, w, h)
	end
	-- Always start at the lowest spot index, so the same spots give the same loop.
	local first = 1
	for i = 2, #tour do
		if tour[i] < tour[first] then
			first = i
		end
	end
	local order = {}
	for i = 1, #tour do
		order[i] = tour[(first + i - 2) % #tour + 1]
	end
	local length = 0
	for i = 1, #order do
		length = length + Dist(spots[order[i]], spots[order[i % #order + 1]], w, h)
	end
	return { order = order, length = length, dropped = dropped }
end

-- Follow rules -------------------------------------------------------------------------------------------------------

-- Angle of a step on the map, as GetPlayerFacing gives it: radians counterclockwise from north (map y grows south).
local function Bearing(fromX, fromY, toX, toY, w, h)
	return atan2(-(toX - fromX) * w, -(toY - fromY) * h) % (2 * math.pi)
end

local function AngleBetween(a, b)
	local d = math.abs(a - b) % (2 * math.pi)
	return d > math.pi and 2 * math.pi - d or d
end

-- Where following starts: k (position in route.order) and dir (1 or -1). player = { x, y }, facing in radians or
-- nil; recent(spotIndex) is true for a spot gathered a moment ago (skipped unless every spot was).
function ns.GatherRoute_Start(route, spots, player, facing, w, h, recent)
	local order, best, bestD = route.order, nil, nil
	for pass = 1, 2 do
		for k, s in ipairs(order) do
			if pass == 2 or not (recent and recent(s)) then
				local d = Dist(player, spots[s], w, h)
				if not bestD or d < bestD then
					best, bestD = k, d
				end
			end
		end
		if best then
			break
		end
	end
	local dir = 1
	if facing and #order > 2 then
		local here = spots[order[best]]
		local ahead = spots[order[best % #order + 1]]
		local behind = spots[order[(best - 2) % #order + 1]]
		local fwd = AngleBetween(Bearing(here.x, here.y, ahead.x, ahead.y, w, h), facing)
		local back = AngleBetween(Bearing(here.x, here.y, behind.x, behind.y, w, h), facing)
		if back < fwd then
			dir = -1
		end
	end
	return best, dir
end

-- The next position after k going dir, skipping recent spots (unless all are). Returns k and how many steps it took.
function ns.GatherRoute_Next(route, k, dir, recent)
	local n = #route.order
	local step = 0
	local at = k
	repeat
		at = (at - 1 + dir) % n + 1
		step = step + 1
	until not (recent and recent(route.order[at])) or step >= n
	if step >= n and recent and recent(route.order[at]) then
		return (k - 1 + dir) % n + 1, 1
	end
	return at, step
end

-- "42 spots, 6,300 yards a lap" (yards rounded to tens), with "3 far-off left out" when some were.
function ns.GatherRoute_Text(route)
	local n = #route.order
	local text = ("%d spots, %s yards a lap"):format(n, ns.Thousands(math.floor(route.length / 10 + 0.5) * 10))
	if route.dropped > 0 then
		text = text .. (", %d far-off left out"):format(route.dropped)
	end
	return text
end
