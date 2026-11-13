-- Run from the AddOns folder: lua Tomte/tests/test_alts_learn.lua
local ns = {}
assert(loadfile("Tomte/Modules/Alts/LearnData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("recipes that were red and aren't now", function()
	local before = { a = true, b = true, c = false, d = true }
	local seen = { a = true, b = true, c = true, d = true }
	local now = { a = false, b = true, c = false }
	eq(table.concat(ns.Alts_NewlyLearnable(before, now, seen), " "), "a")
end)

test("a new recipe you can learn counts; one you can't doesn't", function()
	local now = { looted = false, toohigh = true }
	eq(table.concat(ns.Alts_NewlyLearnable({}, now, {}), " "), "looted")
end)

test("a recipe held but unread at the first read isn't new once it loads", function()
	eq(#ns.Alts_NewlyLearnable({}, { slow = false }, { slow = true }), 0)
end)

test("sorted, so the toast lists them the same way each time", function()
	local seen = { a = true, b = true }
	eq(table.concat(ns.Alts_NewlyLearnable({ b = true, a = true }, { b = false, a = false }, seen), " "), "a b")
end)

test("one recipe: its name and where it is", function()
	local title, text = ns.Alts_LearnToast({ { name = "Pattern: Embossed Leather Gloves", where = "bank" } })
	eq(title, "Pattern: Embossed Leather Gloves")
	eq(text, "You can learn it now. In your bank.")
end)

test("several: a count and a line each, the rest folded", function()
	local entries = {}
	for i = 1, 6 do
		entries[i] = { name = "Pattern " .. i, where = i == 1 and "warband" or "bags" }
	end
	local title, text = ns.Alts_LearnToast(entries)
	eq(title, "6 recipes you can learn now")
	eq(text, "Pattern 1 (Warband bank)\nPattern 2 (bags)\nPattern 3 (bags)\nPattern 4 (bags)\nand 2 more")
end)

H.done()
