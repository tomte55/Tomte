-- Run from the AddOns folder: lua Tomte/tests/test_flight_share.lua
local ns = {}
assert(loadfile("Tomte/Modules/Flight/ShareData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function DB(hops, routes)
	return { hops = hops or {}, routes = routes or {} }
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

test("export is sorted and the same every time", function()
	local db = DB({ ["20>10"] = 31, ["10>20"] = 30 }, { ["1>2>3"] = 90 })
	eq(ns.FlightShare_Export(db), "h10>20=30;h20>10=31;r1>2>3=90;")
	eq(ns.FlightShare_Export(db), ns.FlightShare_Export(DB({ ["10>20"] = 30, ["20>10"] = 31 }, { ["1>2>3"] = 90 })))
end)

test("an empty db exports an empty payload that imports nothing", function()
	eq(ns.FlightShare_Export(DB()), "")
	eq(ns.FlightShare_Import(DB(), ""), 0)
end)

test("import round trip adds everything to an empty db", function()
	local from = DB({ ["1>2"] = 30, ["2>3"] = 45 }, { ["1>2>3"] = 80 })
	local to = DB()
	eq(ns.FlightShare_Import(to, ns.FlightShare_Export(from)), 3)
	eq(to.hops["1>2"], 30)
	eq(to.hops["2>3"], 45)
	eq(to.routes["1>2>3"], 80)
end)

test("import fills gaps only: your own times are kept", function()
	local to = DB({ ["1>2"] = 33 })
	eq(ns.FlightShare_Import(to, "h1>2=30;h2>3=45;"), 1)
	eq(to.hops["1>2"], 33, "own kept")
	eq(to.hops["2>3"], 45)
end)

test("any bad entry rejects the whole payload and adds nothing", function()
	local bad = {
		"h1>2=30;h2>3=0;", -- seconds below 1
		"h1>2=3601;", -- seconds above an hour
		"h1>2>3=30;", -- hop with three nodes
		"r1=30;", -- route with one node
		"r" .. ("1>"):rep(30) .. "1=30;", -- route with 31 nodes
		"h0>2=30;", -- node 0
		"h1>2=30", -- no closing ;
		"x1>2=30;", -- unknown kind
		"h1>>2=30;", -- empty node
		"h1>2=30;;", -- empty entry
		"h1>2=3.5;", -- not whole seconds
	}
	for _, payload in ipairs(bad) do
		local db = DB()
		local added, reason = ns.FlightShare_Import(db, payload)
		eq(added, nil, payload)
		eq(type(reason), "string", payload .. " reason")
		eq(Count(db.hops) + Count(db.routes), 0, payload .. " nothing added")
	end
end)

test("more than 20000 entries is rejected", function()
	local parts = {}
	for i = 1, 20001 do
		parts[i] = "h" .. i .. ">" .. (i + 1) .. "=30;"
	end
	eq((ns.FlightShare_Import(DB(), table.concat(parts))), nil)
end)

test("node IDs are written the canonical way", function()
	local to = DB()
	ns.FlightShare_Import(to, "h007>2=30;")
	eq(to.hops["7>2"], 30)
end)

test("own entries that wouldn't pass import are left out of export and revision", function()
	local clean = DB({ ["1>2"] = 30 })
	local messy = DB({ ["1>2"] = 30, ["oops"] = 10, ["3>4"] = 0, ["5>6"] = 99999 }, { ["7"] = 5 })
	eq(ns.FlightShare_Export(messy), "h1>2=30;")
	eq(ns.FlightShare_Revision(messy), ns.FlightShare_Revision(clean))
end)

test("revision depends on keys, not seconds", function()
	local a = DB({ ["1>2"] = 30 }, { ["1>2>3"] = 80 })
	local b = DB({ ["1>2"] = 35 }, { ["1>2>3"] = 81 })
	local c = DB({ ["1>2"] = 30, ["2>3"] = 40 }, { ["1>2>3"] = 80 })
	local d = DB({}, { ["1>2"] = 30, ["1>2>3"] = 80 }) -- same text, route instead of hop
	eq(ns.FlightShare_Revision(a), ns.FlightShare_Revision(b))
	assert(ns.FlightShare_Revision(a) ~= ns.FlightShare_Revision(c), "new key changes it")
	assert(ns.FlightShare_Revision(a) ~= ns.FlightShare_Revision(d), "hop and route differ")
	assert(ns.FlightShare_Revision(DB()) >= 0, "empty is a number")
end)

-- One sync from one side: send `from`'s export to `to` (what a request answers).
local function Sync(from, to)
	return ns.FlightShare_Import(to, ns.FlightShare_Export(from))
end

test("two installs converge after one exchange each way", function()
	local a = DB({ ["1>2"] = 30, ["2>3"] = 40 }, { ["1>2>3"] = 72 })
	local b = DB({ ["1>2"] = 32, ["4>5"] = 50 })
	assert(ns.FlightShare_Revision(a) ~= ns.FlightShare_Revision(b))
	eq(Sync(a, b), 2, "b gets 2>3 and the route")
	eq(Sync(b, a), 1, "a gets 4>5")
	eq(ns.FlightShare_Revision(a), ns.FlightShare_Revision(b), "same keys now: no more requests")
	eq(a.hops["1>2"], 30, "a keeps its own")
	eq(b.hops["1>2"], 32, "b keeps its own")
	eq(Sync(a, b), 0, "nothing new")
end)

test("relay: A's times reach C through B", function()
	local a, b, c = DB({ ["1>2"] = 30 }), DB(), DB()
	Sync(a, b)
	Sync(b, c)
	eq(c.hops["1>2"], 30)
end)

H.done()
