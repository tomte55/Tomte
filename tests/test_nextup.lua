-- Run from the AddOns folder: lua Tomte/tests/test_nextup.lua
local ns = {}
assert(loadfile("Tomte/Modules/NextUp/Data.lua"))("Tomte", ns)

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

local function Lists()
	return {
		{ source = "a", score = 50, items = { { key = "a1" }, { key = "a2", bonus = 9 } } },
		{ source = "b", score = 90, items = { { key = "b1", state = 3 } } },
		{ source = "c", score = 50, items = { { key = "c1" } } },
	}
end

test("sorts by priority, then bonus, then order", function()
	local r = ns.NextUp_Rank(Lists(), { limit = 10 })
	eq(r[1].key, "b1")
	eq(r[2].key, "a2")
	eq(r[3].key, "a1")
	eq(r[4].key, "c1")
	eq(r[1].source, "b")
end)

test("user priority overrides the entry score", function()
	local r = ns.NextUp_Rank(Lists(), { limit = 10, priority = { c = 95 } })
	eq(r[1].key, "c1")
end)

test("disabled sources are skipped", function()
	local r = ns.NextUp_Rank(Lists(), { limit = 10, enabled = { b = false } })
	eq(#r, 3)
	eq(r[1].key, "a2")
end)

test("limit caps the list", function()
	eq(#ns.NextUp_Rank(Lists(), { limit = 2 }), 2)
end)

test("dismissed until login hides the key whatever its state", function()
	local r = ns.NextUp_Rank(Lists(), { limit = 10, mode = "login", dismissed = { b1 = 2, a1 = true } })
	eq(#r, 2)
	eq(r[1].key, "a2")
end)

test("dismissed until it changes comes back with a new state", function()
	local r = ns.NextUp_Rank(Lists(), { limit = 10, mode = "change", dismissed = { b1 = 2, a1 = true } })
	eq(r[1].key, "b1", "state 3 ~= dismissed 2")
	eq(#r, 3, "a1 has no state, so true matches")
	r = ns.NextUp_Rank(Lists(), { limit = 10, mode = "change", dismissed = { b1 = 3 } })
	eq(r[1].key, "a2")
end)

test("dismiss value is the state or true", function()
	eq(ns.NextUp_DismissValue({ state = 4 }), 4)
	eq(ns.NextUp_DismissValue({}), true)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
