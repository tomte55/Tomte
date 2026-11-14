local addonName, ns = ...

-- Quest route: pure logic (no WoW API calls; unit-tested in tests/test_questroute.lua). Plans the order to visit your quests
-- in: each quest's objective ("do") and where it's handed in ("hand"), the hand-in after the objective, hand-ins at one
-- place as one stop, walking the least. The follow takes the first stop (Route.lua reads the game; QuestList.lua and
-- NextQuests.lua follow it). See docs/superpowers/specs/2026-11-14-tomte-quest-route-design.md.

local KEEP_UNLESS = 0.8 -- the followed stop stays first unless a plan without it first is under 80% as long
-- Finished quests handed in this close come first (Route_Plan): about a town, the distance you'd turn back for.
-- Measured case (Tirisfal, 2026-11-14): three hand-ins 300 yards off while the arrow led 1,100 yards the other way.
local NEAR_HAND_YARDS = 400
local UNTANGLE_PASSES = 50

local sqrt = math.sqrt

local function Dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- Stops from quests: a do stop per unfinished quest with a spot and a hand stop per quest. Each quest hands in on its
-- own stop, so a finished one is never held back by an unfinished one handed in at the same place; stops at one place
-- are 0 yards apart, so the route takes them together anyway, and Merge joins them afterwards. A hand stop's
-- needs = { [questID] = true } when its quest's do stop comes first; ready = it can be handed in right away.
local function Build(quests)
	local stops = {}
	for _, q in ipairs(quests) do
		if q.complete then
			local at = q.point or q.hand
			if at then
				stops[#stops + 1] = { kind = "hand", x = at.x, y = at.y, quests = { q.questID }, needs = {}, ready = true }
			end
		elseif q.point then
			stops[#stops + 1] = { kind = "do", x = q.point.x, y = q.point.y, quests = { q.questID } }
			if q.hand then
				stops[#stops + 1] = { kind = "hand", x = q.hand.x, y = q.hand.y, quests = { q.questID },
					needs = { [q.questID] = true } }
			end
		end
	end
	return stops
end

-- Joins hand stops next to each other in the route, each within mergeYards of the one before: one stop per place
-- ("Brill: hand in 6", its quest givers spread over the town). Inside it, the ones you can hand in right away first,
-- then by quest ID.
local function Merge(path, mergeYards)
	local out = {}
	for _, s in ipairs(path) do
		local last = out[#out]
		if s.kind == "hand" and last and last.kind == "hand" and Dist(last.tail, s) <= mergeYards then
			last.tail = s
			for _, id in ipairs(s.quests) do
				last.quests[#last.quests + 1] = id
				last.readyOf[id] = s.ready or false
			end
			for id in pairs(s.needs) do
				last.needs[id] = true
			end
		else
			local copy = { kind = s.kind, x = s.x, y = s.y, quests = { s.quests[1] } }
			if s.kind == "hand" then
				copy.tail = s -- the last spot joined, for the next one's distance
				copy.needs, copy.readyOf = {}, { [s.quests[1]] = s.ready or false }
				for id in pairs(s.needs) do
					copy.needs[id] = true
				end
			end
			out[#out + 1] = copy
		end
	end
	for _, s in ipairs(out) do
		if s.readyOf then
			local readyOf = s.readyOf
			table.sort(s.quests, function(a, b)
				if readyOf[a] ~= readyOf[b] then
					return readyOf[a]
				end
				return a < b
			end)
			s.readyOf, s.tail = nil, nil
		end
	end
	return out
end

-- The do stop of an unfinished quest, by quest ID.
local function DoStops(stops)
	local byQuest = {}
	for _, s in ipairs(stops) do
		if s.kind == "do" then
			byQuest[s.quests[1]] = s
		end
	end
	return byQuest
end

-- Whether every hand stop in path comes after the do stops it waits for (path[1] is where you stand).
local function Valid(path, doOf)
	local seen = {}
	for i = 2, #path do
		local s = path[i]
		for id in pairs(s.needs or {}) do
			if doOf[id] and not seen[doOf[id]] then
				return false
			end
		end
		seen[s] = true
	end
	return true
end

local function PathLength(path)
	local total = 0
	for i = 2, #path do
		total = total + Dist(path[i - 1], path[i])
	end
	return total
end

-- Shortens path in place by reversing stretches (2-opt), from index `from` on, keeping it Valid.
local function Untangle(path, from, doOf)
	local n = #path
	for _ = 1, UNTANGLE_PASSES do
		local better = false
		for i = from - 1, n - 2 do
			for j = i + 2, n do
				local a, b, c, d = path[i], path[i + 1], path[j], path[j + 1]
				local before = Dist(a, b) + (d and Dist(c, d) or 0)
				local after = Dist(a, c) + (d and Dist(b, d) or 0)
				if after < before - 1e-9 then
					local lo, hi = i + 1, j
					while lo < hi do
						path[lo], path[hi] = path[hi], path[lo]
						lo, hi = lo + 1, hi - 1
					end
					if Valid(path, doOf) then
						better = true
					else
						lo, hi = i + 1, j
						while lo < hi do
							path[lo], path[hi] = path[hi], path[lo]
							lo, hi = lo + 1, hi - 1
						end
					end
				end
			end
		end
		if not better then
			return
		end
	end
end

-- A stop can be next once the do stops it waits for are behind you.
local function Ready(s, visited, doOf)
	for id in pairs(s.needs or {}) do
		if doOf[id] and not visited[doOf[id]] then
			return false
		end
	end
	return true
end

-- Nearest ready stop next from you (first: a stop to start with), then untangled. Returns the stops in order.
local function Order(you, stops, doOf, first)
	local path, visited = { you }, {}
	if first then
		path[2], visited[first] = first, true
	end
	while #path - 1 < #stops do
		local last, best, bestDist = path[#path], nil, math.huge
		for _, s in ipairs(stops) do
			if not visited[s] and Ready(s, visited, doOf) then
				local d = Dist(last, s)
				if d < bestDist then
					best, bestDist = s, d
				end
			end
		end
		if not best then
			break -- can't happen: a do stop waits for nothing, so something is always ready
		end
		visited[best] = true
		path[#path + 1] = best
	end
	Untangle(path, first and 3 or 2, doOf)
	return path
end

local function Strip(path)
	local out = {}
	for i = 2, #path do
		out[i - 1] = path[i]
	end
	return out
end

-- you: { x, y } (world yards). quests: { { questID, complete, point = { x, y } (where to do it; for a finished quest
-- the game's turn-in spot), hand = { x, y } (where it's handed in, from data), later (saved for later: planned after
-- the rest) } }, all on your continent. followedID:
-- the quest followed now, or nil. Returns stops in route order: { { kind = "do" | "hand", x, y, quests = { IDs },
-- needs } }. The followed quest's stop stays first unless a plan starting elsewhere is clearly shorter (KEEP_UNLESS).
-- One set of quests planned from `from`, unmerged.
local function PlanSet(from, quests, followedID)
	local stops = Build(quests)
	if #stops == 0 then
		return {}
	end
	local doOf = DoStops(stops)
	local free = Order(from, stops, doOf, nil)
	local keep = followedID and doOf[followedID]
	if not keep and followedID then
		for _, s in ipairs(stops) do
			if s.kind == "hand" and s.ready and s.quests[1] == followedID then
				keep = s
			end
		end
	end
	if keep then
		local kept = Order(from, stops, doOf, keep)
		if PathLength(free) >= KEEP_UNLESS * PathLength(kept) then
			return Strip(kept)
		end
	end
	return Strip(free)
end

-- Finished quests handed in within NEAR_HAND_YARDS of you come first, even where going on first is shorter (their
-- hand-in passed on the way back): their XP counts now (a level opens quests saved for later), and they aren't left
-- for later. Then the rest, then quests saved for later (q.later: Route_SavedForLater), each from where the last ends.
function ns.Route_Plan(you, quests, followedID, mergeYards)
	local near, now, later = {}, {}, {}
	for _, q in ipairs(quests) do
		local at = q.complete and (q.point or q.hand)
		local list = (at and Dist(you, at) <= NEAR_HAND_YARDS) and near or (q.later and later or now)
		list[#list + 1] = q
	end
	local path = PlanSet(you, near, nil)
	for _, set in ipairs({ now, later }) do
		for _, s in ipairs(PlanSet(path[#path] or you, set, followedID)) do
			path[#path + 1] = s
		end
	end
	return Merge(path, mergeYards)
end

-- The quests to save for later: [questID] = true for each one you can do whose spot is within yards of a quest still
-- too high for you (tooHigh: their spots). Doing it now means walking back once that one turns yellow; at the end of
-- the route you've likely gained the levels, and the place is one trip for all of them. doable: { { questID, point } }.
function ns.Route_SavedForLater(doable, tooHigh, yards)
	local later = {}
	for _, q in ipairs(doable) do
		for _, p in ipairs(tooHigh) do
			if q.point and Dist(q.point, p) <= yards then
				later[q.questID] = true
				break
			end
		end
	end
	return later
end

-- How far the route walks from you, in yards.
function ns.Route_Length(you, stops)
	local total, last = 0, you
	for _, s in ipairs(stops) do
		total = total + Dist(last, s)
		last = s
	end
	return total
end
