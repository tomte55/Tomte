-- Run from the AddOns folder: lua Tomte/tests/test_gold.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/WorldQuests/RouteOrder.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/GoldQuests/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local GOLD = 10000

local nextID = 0
local function Q(zone, gold, fields)
	nextID = nextID + 1
	local q = { id = nextID, title = "Quest " .. nextID, zone = zone, money = gold * GOLD, loaded = true, seconds = 3600 }
	for k, v in pairs(fields or {}) do
		q[k] = v
	end
	return q
end

-- Gold quests -------------------------------------------------------------------------------------------------------

test("group: gold quests by zone, richest zone and quest first, totals", function()
	local quests = {
		Q("Hallowfall", 100), Q("Isle of Dorn", 300), Q("Hallowfall", 250), Q("Hallowfall", 0),
		Q("Isle of Dorn", 50, { loaded = false }), Q("Azj-Kahet", 900),
	}
	local g = ns.Gold_Group(quests)
	eq(g.count, 4, "count")
	eq(g.total, 1550 * GOLD, "total")
	eq(#g.zones, 3, "zones")
	eq(g.zones[1].name, "Azj-Kahet")
	eq(g.zones[2].name, "Hallowfall")
	eq(g.zones[2].total, 350 * GOLD, "zone total")
	eq(g.zones[2].quests[1].money, 250 * GOLD, "richest first")
	eq(g.zones[3].name, "Isle of Dorn")
	eq(#g.zones[3].quests, 1, "unloaded left out")
end)

test("group: same gold sorts by time left, then title", function()
	local a = Q("Z", 100, { seconds = 7200, title = "B" })
	local b = Q("Z", 100, { seconds = 600, title = "C" })
	local c = Q("Z", 100, { seconds = 7200, title = "A" })
	local g = ns.Gold_Group({ a, b, c })
	eq(g.zones[1].quests[1], b)
	eq(g.zones[1].quests[2], c)
	eq(g.zones[1].quests[3], a)
end)

test("summary and login line", function()
	eq(ns.Gold_Summary(ns.Gold_Group({})), "no gold quests")
	eq(ns.Gold_Summary(ns.Gold_Group({ Q("Z", 250) })), "1 quest · 250g")
	eq(ns.Gold_Summary(ns.Gold_Group({ Q("Z", 2000), Q("Y", 1250) })), "2 quests · 3,250g")
	eq(ns.Gold_LoginLine(ns.Gold_Group({})), "Gold world quests: none up right now.")
	eq(ns.Gold_LoginLine(ns.Gold_Group({ Q("Z", 2000), Q("Y", 1250) })),
		"Gold world quests: 2 up, 3,250g. /tomte wgq opens the list.")
end)

-- Route -------------------------------------------------------------------------------------------------------------

local function S(id, cont, x, y, weight)
	return { id = id, cont = cont, x = x, y = y, weight = weight or 0 }
end

test("route: nearest first from where you stand", function()
	local stops = { S(1, 1, 10, 0), S(2, 1, 1, 0), S(3, 1, 5, 0) }
	eq(table.concat(ns.WQ_RouteOrder(stops, { cont = 1, x = 0, y = 0 }), ","), "2,3,1")
end)

local function Length(order, byID, start)
	local total, last = 0, start
	for _, id in ipairs(order) do
		local s = byID[id]
		total = total + math.sqrt((s.x - last.x) ^ 2 + (s.y - last.y) ^ 2)
		last = s
	end
	return total
end

-- Nearest stop next, nothing else: what the route must never be worse than.
local function Greedy(stops, start)
	local left, order, last = {}, {}, start
	for i, s in ipairs(stops) do
		left[i] = s
	end
	while #left > 0 do
		local best, bestDist = 1, math.huge
		for i, s in ipairs(left) do
			local d = math.sqrt((s.x - last.x) ^ 2 + (s.y - last.y) ^ 2)
			if d < bestDist then
				best, bestDist = i, d
			end
		end
		last = table.remove(left, best)
		order[#order + 1] = last.id
	end
	return order
end

test("route: every stop once, never longer than nearest-first", function()
	local seed = 7
	local function Rand()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % 1000
	end
	for _ = 1, 30 do
		local stops, byID = {}, {}
		for id = 1, 14 do
			local s = S(id, 1, Rand(), Rand())
			stops[id], byID[id] = s, s
		end
		local start = { cont = 1, x = Rand(), y = Rand() }
		local ids = ns.WQ_RouteOrder(stops, start)
		eq(#ids, 14, "stops")
		local once = {}
		for _, id in ipairs(ids) do
			assert(not once[id], "stop twice")
			once[id] = true
		end
		assert(Length(ids, byID, start) <= Length(Greedy(stops, start), byID, start) + 1e-6, "longer than greedy")
	end
end)

test("route: a zigzag nearest-first makes gets untangled", function()
	-- Nearest-first from (0,0): 1, 2, then across to 3 and back to 4 (a crossing); untangled it's shorter.
	local stops = { S(1, 1, 1, 0), S(2, 1, 2, 3), S(3, 1, 4, 0), S(4, 1, 2, -3) }
	local byID = {}
	for _, s in ipairs(stops) do
		byID[s.id] = s
	end
	local start = { cont = 1, x = 0, y = 0 }
	local ids = ns.WQ_RouteOrder(stops, start)
	assert(Length(ids, byID, start) < Length(Greedy(stops, start), byID, start) - 1e-6,
		"not shorter: " .. table.concat(ids, ","))
end)

test("route: your continent first, others richest first from their richest stop", function()
	local stops = { S(1, 2, 0, 0, 100), S(2, 2, 50, 0, 900), S(3, 1, 3, 0, 10), S(4, 3, 0, 0, 5000), S(5, 2, 40, 0, 1) }
	local ids = ns.WQ_RouteOrder(stops, { cont = 1, x = 0, y = 0 })
	eq(table.concat(ids, ","), "3,4,2,5,1")
end)

test("route: without a start the richest continent and stop lead", function()
	local stops = { S(1, 1, 0, 0, 100), S(2, 1, 9, 0, 300), S(3, 1, 10, 0, 50) }
	eq(table.concat(ns.WQ_RouteOrder(stops, nil), ","), "2,3,1")
end)

test("route: empty", function()
	eq(#ns.WQ_RouteOrder({}, { cont = 1, x = 0, y = 0 }), 0)
end)

-- Special assignments -----------------------------------------------------------------------------------------------

test("assignment with an unlock quest", function()
	local st = ns.Gold_AssignmentState
	eq(st({ hasUnlock = true, questDone = true }), "done")
	eq(st({ hasUnlock = true, questLive = true }), "up")
	eq(st({ hasUnlock = true, unlockDone = true }), "up", "unlocked, not on the map yet")
	eq(st({ hasUnlock = true, unlockLive = true }), "locked")
	eq(st({ hasUnlock = true }), nil, "not out this week")
end)

test("assignment without an unlock quest: done only from this week's turn-ins", function()
	local st = ns.Gold_AssignmentState
	eq(st({ questDone = true }), nil, "an old flag")
	eq(st({ questDone = true, turnedIn = true }), "done")
	eq(st({ questLive = true }), "up")
end)

test("best per zone: live beats an old flag, then done > up > locked", function()
	local rows = {
		{ zone = "A", state = "done", live = false, n = 1 },
		{ zone = "A", state = "locked", live = true, n = 2 },
		{ zone = "B", state = "locked", live = true, n = 3 },
		{ zone = "B", state = "up", live = true, n = 4 },
		{ zone = "C", state = nil, n = 5 },
		{ zone = "D", state = "up", live = true, n = 6 },
		{ zone = "D", state = "up", live = true, n = 7 },
	}
	local best = ns.Gold_BestPerZone(rows)
	eq(#best, 3)
	eq(best[1].n, 2)
	eq(best[2].n, 4)
	eq(best[3].n, 6, "first wins a tie")
end)

-- Caches and characters ---------------------------------------------------------------------------------------------

test("cache done from a flag or this week's turn-ins, any quest of a pool", function()
	local cache = { quests = { 10, 11, 12 } }
	eq(ns.Gold_CacheDone(cache, function()
		return false
	end, {}), false)
	eq(ns.Gold_CacheDone(cache, function(id)
		return id == 12
	end, {}), true)
	eq(ns.Gold_CacheDone(cache, nil, { [11] = true }), true)
end)

test("week rolls over at the reset", function()
	local c = ns.Gold_NewChar()
	eq(ns.Gold_RollWeek(c, 1000, 500), false, "first week")
	eq(c.nextReset, 1500)
	eq(ns.Gold_AddEarned(c, 7, 250 * GOLD), true)
	eq(ns.Gold_AddEarned(c, 7, 250 * GOLD), false, "same quest twice")
	eq(ns.Gold_AddEarned(c, 8, 0), false, "no gold")
	c.turnedIn[7], c.caches.unity = true, true
	eq(c.weekCopper, 250 * GOLD)
	eq(ns.Gold_RollWeek(c, 1400, 100), false, "still this week")
	eq(c.weekCopper, 250 * GOLD)
	eq(ns.Gold_RollWeek(c, 1600, 604700), true, "after the reset")
	eq(c.weekCopper, 0)
	eq(c.totalCopper, 250 * GOLD, "lifetime kept")
	eq(c.turnedIn[7], nil)
	eq(c.caches.unity, nil)
	eq(c.nextReset, 1600 + 604700)
	eq(ns.Gold_AddEarned(c, 7, 100 * GOLD), true, "the same quest counts again next week")
	eq(c.totalCopper, 350 * GOLD)
end)

test("another character's week reads as empty after its reset", function()
	local c = ns.Gold_NewChar()
	ns.Gold_RollWeek(c, 1000, 500)
	ns.Gold_AddEarned(c, 1, 100 * GOLD)
	c.caches.x = true
	local week, caches = ns.Gold_CharWeek(c, 1200)
	eq(week, 100 * GOLD)
	eq(caches.x, true)
	week, caches = ns.Gold_CharWeek(c, 1500)
	eq(week, 0)
	eq(caches.x, nil)
end)

test("characters: current first, then gold this week, then name", function()
	local function C(name, week)
		local c = ns.Gold_NewChar()
		c.name, c.weekCopper, c.nextReset = name, week, 9999
		return c
	end
	local list = ns.Gold_SortChars({ a = C("Zed", 10), b = C("Amy", 500), c = C("Bob", 500), d = C("Me", 0) }, "d", 100)
	eq(list[1].guid, "d")
	eq(list[2].char.name, "Amy")
	eq(list[3].char.name, "Bob")
	eq(list[4].char.name, "Zed")
end)

H.done()
