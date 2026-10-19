-- Run from the AddOns folder: lua Tomte/tests/test_wq_route.lua
local ns = {}
assert(loadfile("Tomte/Modules/WorldQuests/RouteOrder.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Up(...)
	local up = {}
	for _, id in ipairs({ ... }) do
		up[id] = true
	end
	return up
end

test("the first check tracks the first stop", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1, 2 } }, Up(1, 2, 3), 0)
	eq(table.concat(ids, ","), "3,1,2")
	eq(action, "track")
end)

test("the tracked stop expired: it drops out and the next is tracked", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1, 2 }, current = 3 }, Up(1, 2), 3)
	eq(table.concat(ids, ","), "1,2")
	eq(action, "track")
end)

test("a later stop expired: dropped, nothing else happens", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1, 2 }, current = 3 }, Up(3, 2), 3)
	eq(table.concat(ids, ","), "3,2")
	eq(action, nil)
end)

test("nothing left is done", function()
	local ids, action = ns.WQRoute_Step({ ids = {}, current = 3 }, Up(1, 2), 0)
	eq(#ids, 0)
	eq(action, "done")
end)

test("the provider lists nothing at all: can't tell (an instance, a cleared cache), the route keeps its stops", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(), 3)
	eq(table.concat(ids, ","), "3,1")
	eq(action, nil)
end)

test("handed in (already off the list) while the map still lists it: next is tracked", function()
	local _, action = ns.WQRoute_Step({ ids = { 1, 2 }, current = 3 }, Up(1, 2, 3), 0)
	eq(action, "track")
end)

test("the player tracks another quest: pause", function()
	local _, action = ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), 99)
	eq(action, "pause")
end)

test("the player tracks a map pin or nothing: pause", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), -1)), "pause")
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), 0)), "pause")
end)

test("can't tell (combat wait, corpse): never pauses", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), nil)), nil)
end)

test("can't tell, but the current stop expired: still moves on", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1), nil)), "track")
end)

test("paused: a hand-in elsewhere only shortens the list", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 2 }, current = 3, paused = true }, Up(2, 3), 99)
	eq(table.concat(ids, ","), "3,2")
	eq(action, nil)
end)

test("paused: the current stop expired, still nothing tracked", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 2 }, current = 3, paused = true }, Up(2), 99)
	eq(table.concat(ids, ","), "2")
	eq(action, nil)
end)

test("paused: the player tracks the current stop again: resume", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 2 }, current = 3, paused = true }, Up(2, 3), 3)), "resume")
end)

test("paused with nothing left is done", function()
	eq(select(2, ns.WQRoute_Step({ ids = {}, current = 3, paused = true }, Up(2), 99)), "done")
end)

H.done()
