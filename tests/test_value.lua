-- Run from the AddOns folder: lua Tomte/tests/test_value.lua
local ns = {}
assert(loadfile("Tomte/Modules/Value/Data.lua"))("Tomte", ns)

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

test("categories", function()
	eq(ns.Value_Category(7), "gathered")
	eq(ns.Value_Category(4), "gear")
	eq(ns.Value_Category(2), "gear")
	eq(ns.Value_Category(0), "other")
	eq(ns.Value_Category(nil), "other")
end)

test("source picks the setting, then falls back", function()
	local both, ator, none = { auctionator = true, tsm = true }, { auctionator = true }, {}
	eq(ns.Value_Source("auto", both), "tsm")
	eq(ns.Value_Source("auto", ator), "auctionator")
	eq(ns.Value_Source("auto", none), "vendor")
	eq(ns.Value_Source("auctionator", both), "auctionator")
	eq(ns.Value_Source("tsm", ator), "auctionator")
	eq(ns.Value_Source("vendor", both), "vendor")
end)

test("pick: auction, bound, gear options", function()
	local p, k = ns.Value_Pick({ category = "gathered", auction = 500, vendor = 10 }, "vendor")
	eq(p, 500)
	eq(k, "auction")
	p, k = ns.Value_Pick({ category = "gathered", auction = 500, vendor = 10, bound = true }, "vendor")
	eq(p, 10)
	eq(k, "vendor")
	eq((ns.Value_Pick({ category = "gear", auction = 900, vendor = 40 }, "vendor")), 40)
	eq((ns.Value_Pick({ category = "gear", auction = 900, vendor = 40 }, "auction")), 900)
	eq((ns.Value_Pick({ category = "gear", auction = 900, vendor = 40 }, "none")), nil)
	eq((ns.Value_Pick({ category = "other", vendor = 3 }, "vendor")), 3, "no auction price")
end)

test("loot adds up and totals by category", function()
	local loot = {}
	ns.Value_LootAdd(loot, 1, "l1", 5, 100, "gathered")
	ns.Value_LootAdd(loot, 1, "l1", 2, 120, "gathered")
	ns.Value_LootAdd(loot, 2, "l2", 1, 3000, "gear")
	eq(loot[1].n, 7)
	eq(loot[1].v, 740)
	local total, by = ns.Value_LootTotals(loot)
	eq(total, 3740)
	eq(by.gathered, 740)
	eq(by.gear, 3000)
	total = ns.Value_LootTotals(loot, nil, { gear = true })
	eq(total, 740)
	total = ns.Value_LootTotals(loot, function(id)
		return id == 1 and 200 or nil
	end)
	eq(total, 7 * 200 + 3000, "today's price, else the looted value")
end)

test("loot: gear copies at different item levels keep their own link and value", function()
	local loot = {}
	ns.Value_LootAdd(loot, 9, "item:9::::::::::::1:600", 1, 500, "gear")
	ns.Value_LootAdd(loot, 9, "item:9::::::::::::1:700", 1, 2000, "gear")
	ns.Value_LootAdd(loot, 9, "item:9::::::::::::1:600", 1, 500, "gear")
	eq(loot["item:9::::::::::::1:600"].n, 2)
	eq(loot["item:9::::::::::::1:700"].v, 2000)
	eq(loot[9], nil)
	local seen = {}
	local total = ns.Value_LootTotals(loot, function(_, e)
		seen[#seen + 1] = e.link
		return e.link:find("700") and 3000 or 400
	end)
	eq(total, 2 * 400 + 3000, "each copy priced by its own link")
	eq(#seen, 2)
end)

test("sum and craft cost", function()
	eq(ns.Value_Sum({ { price = 10, count = 3 }, { count = 5 }, { price = 7 } }), 37)
	local mats = { { need = 10, have = 4, unit = 100 }, { need = 2, have = 2, unit = 50 } }
	local cost, complete = ns.Value_CraftCost(mats, "market")
	eq(cost, 1100)
	eq(complete, true)
	cost = ns.Value_CraftCost(mats, "free")
	eq(cost, 600)
	cost, complete = ns.Value_CraftCost({ { need = 1, have = 0 } }, "market")
	eq(cost, 0)
	eq(complete, false)
end)

test("stale", function()
	eq(ns.Value_Stale(nil, 7), false)
	eq(ns.Value_Stale(3, 7), false)
	eq(ns.Value_Stale(9, 7), true)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
