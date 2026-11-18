-- Run from the AddOns folder: lua Tomte/tests/test_questroute.lua
local ns = {}
assert(loadfile("Tomte/Modules/Leveling/RouteData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local MERGE = 40
local YOU = { x = 0, y = 0 }

local function P(x, y)
	return { x = x, y = y }
end

local function Kinds(stops)
	local out = {}
	for i, s in ipairs(stops) do
		out[i] = s.kind .. ":" .. table.concat(s.quests, "+")
	end
	return table.concat(out, " ")
end

-- Every quest's do stop comes before its hand stop.
local function InOrder(stops)
	local done = {}
	for _, s in ipairs(stops) do
		for _, id in ipairs(s.quests) do
			if s.kind == "do" then
				done[id] = true
			elseif s.needs and s.needs[id] and not done[id] then
				return false
			end
		end
	end
	return true
end

test("a hand-in waits for its quest's objective, however close it is", function()
	local quests = { { questID = 1, point = P(1000, 0), hand = P(10, 0) } }
	eq(Kinds(ns.Route_Plan(YOU, quests, nil, MERGE)), "do:1 hand:1")
end)

test("the Brill case: the west quest first when it hands in at Brill too", function()
	local brill = P(900, 300)
	local quests = { { questID = 9, point = P(-200, 200), hand = brill } }
	for id = 1, 5 do
		quests[#quests + 1] = { questID = id, complete = true, point = P(900 + id, 300) }
	end
	local stops = ns.Route_Plan(YOU, quests, nil, MERGE)
	eq(Kinds(stops), "do:9 hand:1+2+3+4+5+9", "one stop at Brill for all six")
end)

test("a finished quest isn't held back by an unfinished one handed in at the same place", function()
	local brill = P(100, 0)
	local quests = { { questID = 1, complete = true, point = brill }, { questID = 2, point = P(1000, 0), hand = brill } }
	eq(Kinds(ns.Route_Plan(YOU, quests, nil, MERGE)), "hand:1 do:2 hand:2")
end)

test("a town's quest givers are one stop, each within reach of the one before", function()
	local quests = {
		{ questID = 1, complete = true, point = P(500, 0) },
		{ questID = 2, complete = true, point = P(530, 0) },
		{ questID = 3, complete = true, point = P(560, 0) }, -- 60 from the first, 30 from the one before
		{ questID = 4, complete = true, point = P(700, 0) }, -- 140 from the one before: another place
	}
	eq(Kinds(ns.Route_Plan(YOU, quests, nil, MERGE)), "hand:1+2+3 hand:4")
end)

test("finished quests at one place are one stop; a quest without hand-in data is a do stop only", function()
	local quests = {
		{ questID = 1, complete = true, point = P(500, 0) },
		{ questID = 2, complete = true, point = P(510, 10) },
		{ questID = 3, point = P(100, 0) },
	}
	eq(Kinds(ns.Route_Plan(YOU, quests, nil, MERGE)), "do:3 hand:1+2")
end)

test("a finished quest hands in at the game's spot, its data spot only when the game has none", function()
	local stops = ns.Route_Plan(YOU, { { questID = 1, complete = true, point = P(50, 0), hand = P(900, 0) } }, nil, MERGE)
	eq(stops[1].x, 50)
	stops = ns.Route_Plan(YOU, { { questID = 1, complete = true, hand = P(900, 0) } }, nil, MERGE)
	eq(stops[1].x, 900)
end)

test("an unfinished quest without a spot to do it adds nothing", function()
	eq(#ns.Route_Plan(YOU, { { questID = 1, hand = P(10, 0) } }, nil, MERGE), 0)
	eq(#ns.Route_Plan(YOU, {}, nil, MERGE), 0)
end)

test("untangling never puts a hand-in before its objective", function()
	math.randomseed(7)
	for _ = 1, 200 do
		local quests = {}
		for id = 1, 8 do
			local q = { questID = id, complete = math.random() < 0.3 }
			q.point = P(math.random(-1000, 1000), math.random(-1000, 1000))
			if math.random() < 0.8 then
				q.hand = P(math.random(-1000, 1000), math.random(-1000, 1000))
			end
			quests[id] = q
		end
		local stops = ns.Route_Plan(YOU, quests, nil, MERGE)
		assert(InOrder(stops), "a hand-in came before its objective")
	end
end)

test("the followed stop stays first unless another plan is clearly shorter", function()
	local quests = { { questID = 1, point = P(500, 0) }, { questID = 2, point = P(450, 0) } }
	eq(ns.Route_Plan(YOU, quests, nil, MERGE)[1].quests[1], 2, "free: the nearer one")
	eq(ns.Route_Plan(YOU, quests, 1, MERGE)[1].quests[1], 1, "followed: kept, the other way is barely shorter")
	quests = { { questID = 1, point = P(1000, 0) }, { questID = 2, point = P(100, 0) } }
	eq(ns.Route_Plan(YOU, quests, 1, MERGE)[1].quests[1], 2, "much shorter the other way: changed")
	eq(ns.Route_Plan(YOU, quests, 77, MERGE)[1].quests[1], 2, "followed quest not in the plan: the free plan")
end)

test("finished quests handed in close by come first, even when going on first is shorter", function()
	-- Followed: a quest 1,100 yards west; three hand-ins 300 yards east, on the way back, and the rest further east.
	-- By distance alone the west quest first is shorter (the hand-ins are passed on the way back).
	local quests = { { questID = 1, point = P(-1100, 0) } }
	for id = 2, 4 do
		quests[#quests + 1] = { questID = id, complete = true, point = P(300 + id, 0) }
	end
	for id = 5, 7 do
		quests[#quests + 1] = { questID = id, point = P(1500 + id * 300, 0) }
	end
	for _, followed in ipairs({ 1, false }) do
		local stops = ns.Route_Plan(YOU, quests, followed or nil, MERGE)
		eq(Kinds({ stops[1] }), "hand:2+3+4", "hand in next door first")
	end
	quests = { { questID = 1, point = P(100, 0) }, { questID = 2, complete = true, point = P(-900, 0) } }
	eq(ns.Route_Plan(YOU, quests, nil, MERGE)[1].kind, "do", "a hand-in far off waits its turn")
end)

test("a followed quest's hand-in can't be forced before its objective", function()
	local quests = { { questID = 1, point = P(1000, 0), hand = P(10, 0) }, { questID = 2, point = P(5, 5) } }
	local stops = ns.Route_Plan(YOU, quests, 1, MERGE)
	eq(stops[1].kind, "do")
	eq(InOrder(stops), true)
end)

test("a quest saved for later comes after everything else, its hand-in too", function()
	local quests = {
		{ questID = 1, point = P(50, 0), hand = P(60, 0), later = true }, -- right here, but saved
		{ questID = 2, point = P(500, 0) },
		{ questID = 3, complete = true, point = P(800, 0) },
	}
	eq(Kinds(ns.Route_Plan(YOU, quests, nil, MERGE)), "do:2 hand:3 do:1 hand:1")
	eq(Kinds(ns.Route_Plan(YOU, { quests[1] }, nil, MERGE)), "do:1 hand:1", "nothing else: it's the route")
	eq(ns.Route_Plan(YOU, quests, 1, MERGE)[1].quests[1], 2, "following it doesn't pull it forward")
end)

test("quests close by are done first, nearest first, even where saving them for the way back is shorter", function()
	-- Tirisfal: three quests around you, one far east, everything handed in at a town to the west. Saving the close ones
	-- for the walk back west is the shortest tour; the route does them first instead.
	local town = P(-1500, 0)
	local quests = {
		{ questID = 1, point = P(20, 0), hand = town },
		{ questID = 2, point = P(600, 0), hand = town },
		{ questID = 3, point = P(-150, 60), hand = town },
		{ questID = 4, point = P(-100, -90), hand = town },
	}
	local stops = ns.Route_Plan(YOU, quests, 1, MERGE, 300)
	eq(Kinds({ stops[1], stops[2], stops[3], stops[4] }), "do:1 do:4 do:3 do:2")
	eq(InOrder(stops), true)
	eq(stops[#stops].kind, "hand", "then all four hand in at the town")
end)

test("a quest whose area you're in is close by however far its spot is", function()
	local quests = { { questID = 1, point = P(700, 0), inside = true }, { questID = 2, point = P(400, 0) } }
	eq(ns.Route_Plan(YOU, quests, nil, MERGE, 300)[1].quests[1], 1)
	eq(ns.Route_Plan(YOU, quests, nil, MERGE, nil)[1].quests[1], 2, "without the close-by step: nearest first")
end)

test("close by doesn't pull a saved-for-later quest forward, or go before hand-ins next door", function()
	local quests = {
		{ questID = 1, point = P(30, 0), later = true },
		{ questID = 2, point = P(800, 0) },
		{ questID = 3, complete = true, point = P(200, 0) },
		{ questID = 4, point = P(100, 0) },
	}
	eq(Kinds(ns.Route_Plan(YOU, quests, nil, MERGE, 300)), "hand:3 do:4 do:2 do:1")
end)

test("SavedForLater: a quest near one too high for you yet waits for it", function()
	local doable = { { questID = 1, point = P(0, 0) }, { questID = 2, point = P(2000, 0) } }
	local tooHigh = { P(200, 0) }
	local later = ns.Route_SavedForLater(doable, tooHigh, 300)
	eq(later[1], true, "Shadowvale: the Elixir waits for The Tarnished")
	eq(later[2], nil, "far away: not held back")
	eq(next(ns.Route_SavedForLater(doable, {}, 300)), nil, "nothing too high: nothing waits")
end)

test("Length walks the stops from you", function()
	eq(ns.Route_Length(YOU, { { x = 3, y = 4 }, { x = 3, y = 10 } }), 11)
	eq(ns.Route_Length(YOU, {}), 0)
end)

H.done()
