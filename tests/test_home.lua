-- Run from the AddOns folder: lua Tomte/tests/test_home.lua
local ns = {
	errorHandler = function(err)
		error(err)
	end,
}
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)

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

local function reset()
	ns.modules, ns.modulesByKey, ns.homeByKey = {}, {}, {}
end

test("PillText is empty at 0 and for no count, the number up to 99, then 99+", function()
	eq(ns.Home_PillText(0), "", "0")
	eq(ns.Home_PillText(nil), "", "nil")
	eq(ns.Home_PillText(-2), "", "negative")
	eq(ns.Home_PillText("3"), "", "not a number")
	eq(ns.Home_PillText(1), "1", "1")
	eq(ns.Home_PillText(99), "99", "99")
	eq(ns.Home_PillText(100), "99+", "100")
	eq(ns.Home_PillText(2.7), "2", "rounded down")
end)

-- Two modules with around entries; the Tomte window's db.window.around is what "Around you shows" writes.
local function Setup(window)
	reset()
	ns.RegisterModule({ key = "a", name = "a", category = "x", enabledByDefault = true, home = {
		{ kind = "around", key = "collectaround", order = 1 },
		{ kind = "around", key = "flightaround", order = 4 },
		{ kind = "page", key = "pagea" },
	} })
	ns.RegisterModule({ key = "b", name = "b", category = "x", enabledByDefault = true, home = {
		{ kind = "around", key = "mountaround", order = 5 },
	} })
	local db = { window = window }
	ns.InitModules(db)
	return db
end

local function Keys(list)
	local keys = {}
	for i, e in ipairs(list) do
		keys[i] = e.key
	end
	return table.concat(keys, ",")
end

test("HomeEntries(around) leaves out blocks unticked in Around you shows", function()
	local db = Setup({ around = { collectaround = true, flightaround = false, mountaround = true } })
	eq(Keys(ns.HomeEntries("around")), "collectaround,mountaround", "flight off")
	db.window.around.flightaround = true
	eq(Keys(ns.HomeEntries("around")), "collectaround,flightaround,mountaround", "flight back on")
	db.window.around.collectaround = false
	db.window.around.mountaround = false
	eq(Keys(ns.HomeEntries("around")), "flightaround", "two off")
end)

test("HomeEntries(around) shows a block missing from the settings (new block, defaults not merged yet)", function()
	Setup({ around = { collectaround = true } })
	eq(Keys(ns.HomeEntries("around")), "collectaround,flightaround,mountaround", "unknown keys shown")
	Setup(nil)
	eq(#ns.HomeEntries("around"), 3, "no window settings")
end)

test("the around filter only touches around entries, and a module that's off still hides its block", function()
	local db = Setup({ around = { pagea = false } })
	eq(Keys(ns.HomeEntries("page")), "pagea", "page untouched")
	ns.SetModuleEnabled("b", false)
	eq(Keys(ns.HomeEntries("around")), "collectaround,flightaround", "module off")
	eq(db.enabled.b, false, "saved")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
