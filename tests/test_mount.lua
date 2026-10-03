-- Run from the AddOns folder: lua Tomte/tests/test_mount.lua
local ns = {}
assert(loadfile("Tomte/Modules/Mount/Data.lua"))("Tomte", ns)

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

local function first()
	return 1
end

local GROUND = { id = 1 }
local FLYER = { id = 2, flying = true }
local STEADY = { id = 3, flying = true, steady = true }
local TURTLE = { id = 4, aquatic = true, swimOnly = true }
local OTTER = { id = 5, aquatic = true }

test("type info: known and unknown", function()
	eq(ns.Mount_TypeInfo(248).flying, true, "flying")
	eq(ns.Mount_TypeInfo(231).swimOnly, true, "turtle")
	eq(ns.Mount_TypeInfo(99999).flying, nil, "unknown is ground")
	eq(ns.Mount_KnownType(99999), false)
end)

test("context", function()
	eq(ns.Mount_Context({ submerged = true, flyable = true }), "water")
	eq(ns.Mount_Context({ flyable = true }), "flying")
	eq(ns.Mount_Context({ flyable = true, indoors = true }), "ground")
	eq(ns.Mount_Context({}), "ground")
end)

test("zone list: nearest map with a list wins", function()
	local zones = { [10] = { 7 }, [2] = { 8, 9 } }
	local list, mapID = ns.Mount_ZoneList({ 100, 10, 2 }, zones)
	eq(mapID, 10)
	eq(list[1], 7)
	list, mapID = ns.Mount_ZoneList({ 101, 2 }, zones)
	eq(mapID, 2)
	eq(ns.Mount_ZoneList({ 5 }, zones), nil)
	eq(ns.Mount_ZoneList({ 5 }, { [5] = {} }), nil, "empty list skipped")
end)

test("toggle zone favorites", function()
	local zones = {}
	eq(ns.Mount_ToggleZone(zones, 10, 7), true)
	eq(ns.Mount_InZone(zones, 10, 7), true)
	eq(ns.Mount_ToggleZone(zones, 10, 8), true)
	eq(ns.Mount_ToggleZone(zones, 10, 7), false)
	eq(#zones[10], 1)
	eq(ns.Mount_ToggleZone(zones, 10, 8), false)
	eq(zones[10], nil, "empty list removed")
end)

test("pick: flying context prefers flyers", function()
	eq(ns.Mount_Pick({ GROUND, FLYER }, "flying", {}, first), FLYER)
	eq(ns.Mount_Pick({ GROUND }, "flying", {}, first), GROUND, "no flyer: ground")
end)

test("pick: skyriding skips steady-only flyers when it can", function()
	eq(ns.Mount_Pick({ STEADY, FLYER }, "flying", { skyriding = true }, first), FLYER)
	eq(ns.Mount_Pick({ STEADY }, "flying", { skyriding = true }, first), STEADY, "only steady")
	eq(ns.Mount_Pick({ STEADY, FLYER }, "flying", {}, first), STEADY, "steady style")
end)

test("pick: ground prefers land mounts, never swim-only ones", function()
	eq(ns.Mount_Pick({ FLYER, GROUND }, "ground", { preferGround = true }, first), GROUND)
	eq(ns.Mount_Pick({ FLYER, GROUND }, "ground", {}, first), FLYER, "no preference")
	eq(ns.Mount_Pick({ TURTLE, FLYER }, "ground", { preferGround = true }, first), FLYER)
	eq(ns.Mount_Pick({ OTTER, TURTLE }, "ground", {}, first), OTTER)
	eq(ns.Mount_Pick({ TURTLE }, "ground", {}, first), TURTLE, "last resort")
end)

test("pick: water prefers swimmers, then flyers", function()
	eq(ns.Mount_Pick({ GROUND, FLYER, TURTLE }, "water", {}, first), TURTLE)
	eq(ns.Mount_Pick({ GROUND, FLYER }, "water", {}, first), FLYER)
	eq(ns.Mount_Pick({ GROUND }, "water", {}, first), GROUND)
end)

test("pick: avoids the last mount when there's a choice", function()
	local a, b = { id = 1 }, { id = 2 }
	eq(ns.Mount_Pick({ a, b }, "ground", { avoid = 1 }, first), b)
	eq(ns.Mount_Pick({ a }, "ground", { avoid = 1 }, first), a, "only one")
end)

test("pick: nothing usable", function()
	eq(ns.Mount_Pick({}, "ground", {}, first), nil)
end)

test("pick: uses rand over the pool", function()
	local a, b, c = { id = 1 }, { id = 2 }, { id = 3 }
	local seen
	local got = ns.Mount_Pick({ a, b, c }, "ground", {}, function(n)
		seen = n
		return n
	end)
	eq(seen, 3)
	eq(got, c)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
