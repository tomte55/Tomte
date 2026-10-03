-- Run from the AddOns folder: lua Tomte/tests/test_upkeep.lua
local ns = {}
assert(loadfile("Tomte/Modules/Upkeep/Data.lua"))("Tomte", ns)

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

local Plan = ns.Upkeep_RepairPlan

test("repair: nothing to repair", function()
	eq(Plan(0, 1000, true, true, -1), nil)
	eq(Plan(nil, 1000, true, true, -1), nil)
end)

test("repair: guild when allowed and the limit covers it", function()
	eq(Plan(500, 0, true, true, 500), "guild")
	eq(Plan(500, 0, true, true, -1), "guild", "unlimited")
end)

test("repair: own gold when the guild limit is too low", function()
	eq(Plan(500, 1000, true, true, 499), "own")
end)

test("repair: own gold when guild is off or not allowed", function()
	eq(Plan(500, 1000, false, true, -1), "own", "setting off")
	eq(Plan(500, 1000, true, false, -1), "own", "no guild rights")
	eq(Plan(500, 1000, true, true, nil), "own", "no limit known")
end)

test("repair: poor", function()
	eq(Plan(500, 499, true, true, 100), "poor")
	eq(Plan(500, 499, false, false, nil), "poor")
end)

test("junk: greys only, counts stacks, skips excluded and valueless", function()
	local value, n = ns.Upkeep_JunkValue({
		{ quality = 0, count = 3, price = 10 },
		{ quality = 0, count = 1, price = 25 },
		{ quality = 1, count = 1, price = 1000 },
		{ quality = 0, count = 1, price = 50, excluded = true },
		{ quality = 0, count = 1, price = 50, noValue = true },
		{ quality = 0, count = 1, price = 0 },
	})
	eq(value, 55, "value")
	eq(n, 2, "stacks")
end)

test("durability summary: lowest, slot and broken count", function()
	local lowest, slot, broken = ns.Durability_Summary({
		{ slot = 1, cur = 80, max = 100 },
		{ slot = 7, cur = 0, max = 120 },
		{ slot = 5, cur = 30, max = 100 },
		{ slot = 2, cur = 0, max = 0 },
	})
	eq(lowest, 0, "lowest")
	eq(slot, 7, "slot")
	eq(broken, 1, "broken")
	eq(ns.Durability_Summary({}), nil, "empty")
end)

test("durability alert: once per crossing, again after a repair", function()
	local state = {}
	eq(ns.Durability_Alert(state, 0.5, 0, 0.3), nil, "fine")
	eq(ns.Durability_Alert(state, 0.29, 0, 0.3), "low", "crossed")
	eq(ns.Durability_Alert(state, 0.2, 0, 0.3), nil, "already warned")
	eq(ns.Durability_Alert(state, 1, 0, 0.3), nil, "repaired")
	eq(ns.Durability_Alert(state, 0.25, 0, 0.3), "low", "crossed again")
end)

test("durability alert: broken items warn even after a low warning", function()
	local state = {}
	eq(ns.Durability_Alert(state, 0.1, 0, 0.3), "low")
	eq(ns.Durability_Alert(state, 0, 1, 0.3), "broken", "first break")
	eq(ns.Durability_Alert(state, 0, 1, 0.3), nil, "same break")
	eq(ns.Durability_Alert(state, 0, 2, 0.3), "broken", "second break")
end)

test("durability alert: no durability items resets", function()
	local state = { warned = true, broken = 2 }
	eq(ns.Durability_Alert(state, nil, 0, 0.3), nil)
	eq(state.warned, false)
	eq(ns.Durability_Alert(state, 0.1, 0, 0.3), "low")
end)

test("durability percent floors", function()
	eq(ns.Durability_Percent(0.299), "29%")
	eq(ns.Durability_Percent(1), "100%")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
