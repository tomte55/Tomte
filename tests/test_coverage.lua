-- Run from the AddOns folder: lua Tomte/tests/test_coverage.lua
local ns = {}
assert(loadfile("Tomte/Modules/Flight/Coverage.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function Node(id, name, undiscovered)
	return { nodeID = id, name = name, undiscovered = undiscovered }
end

test("Timed collects nodes from hops and routes, legs once per pair", function()
	local db = {
		hops = { ["1>2"] = 30, ["2>1"] = 31, ["2>3"] = 40 },
		routes = { ["1>2"] = 30, ["4>2>5"] = 90 },
	}
	local timed, legs = ns.Coverage_Timed(db)
	for _, id in ipairs({ 1, 2, 3, 4, 5 }) do
		eq(timed[id], true, "node " .. id)
	end
	eq(timed[6], nil, "node 6")
	eq(#legs, 2, "legs")
end)

test("NodeState is timed, known or undiscovered", function()
	local timed = { [1] = true }
	eq(ns.Coverage_NodeState(Node(1, "A"), timed), "timed")
	eq(ns.Coverage_NodeState(Node(1, "A", true), timed), "timed") -- flew there on another character
	eq(ns.Coverage_NodeState(Node(2, "B"), timed), "known")
	eq(ns.Coverage_NodeState(Node(3, "C", true), timed), "undiscovered")
end)

test("Count gives timed and total for a node list", function()
	local timed, total = ns.Coverage_Count({ Node(1, "A"), Node(2, "B"), Node(3, "C") }, { [1] = true, [3] = true })
	eq(timed, 2)
	eq(total, 3)
end)

test("Summarize sums zones into continents and the total, sorted, empty ones left out", function()
	local atlas = {
		continents = {
			{ mapID = 100, name = "Khaz Algar", zones = {
				{ mapID = 102, name = "The Ringing Deeps", nodes = { Node(3, "Gundargaz"), Node(4, "Opportunity Point", true) } },
				{ mapID = 101, name = "Isle of Dorn", nodes = { Node(2, "Dornogal"), Node(1, "Rambleshire") } },
				{ mapID = 103, name = "Empty", nodes = {} },
			} },
			{ mapID = 200, name = "Nowhere", zones = { { mapID = 201, name = "Void", nodes = {} } } },
		},
	}
	local db = { hops = { ["1>2"] = 30, ["2>3"] = 50 }, routes = {} }
	local s = ns.Coverage_Summarize(atlas, db)
	eq(s.timed, 3, "total timed")
	eq(s.total, 4, "total nodes")
	eq(s.legs, 2, "total legs")
	eq(#s.continents, 1, "empty continent left out")
	local c = s.continents[1]
	eq(c.timed, 3)
	eq(c.total, 4)
	eq(c.legs, 2)
	eq(#c.zones, 2, "empty zone left out")
	local dorn, deeps = c.zones[1], c.zones[2]
	eq(dorn.name, "Isle of Dorn", "zones by name")
	eq(dorn.timed, 2)
	eq(dorn.legs, 2, "1>2 inside, 2>3 crosses out")
	eq(deeps.legs, 1)
	eq(dorn.nodes[1].name, "Dornogal", "nodes by name")
	eq(dorn.nodes[1].state, "timed")
	eq(deeps.nodes[2].state, "undiscovered")
end)

test("Summarize counts a leg once per continent even when both ends are inside", function()
	local atlas = {
		continents = {
			{ mapID = 100, name = "C", zones = {
				{ mapID = 101, name = "A", nodes = { Node(1, "a") } },
				{ mapID = 102, name = "B", nodes = { Node(2, "b") } },
			} },
		},
	}
	local s = ns.Coverage_Summarize(atlas, { hops = { ["1>2"] = 10 }, routes = {} })
	eq(s.continents[1].legs, 1)
	eq(s.continents[1].zones[1].legs, 1)
	eq(s.continents[1].zones[2].legs, 1)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
