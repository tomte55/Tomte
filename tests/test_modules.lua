-- Run from the AddOns folder: lua Tomte/tests/test_modules.lua
local errors = {}
local ns = {
	errorHandler = function(err)
		errors[#errors + 1] = tostring(err)
	end,
}
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Migration.lua"))("Tomte", ns)

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

-- Fresh registry for each test. Returns a module whose toggle calls are recorded in module.calls.
local function reset()
	ns.modules, ns.modulesByKey = {}, {}
	errors = {}
end
local function newModule(key, extra)
	local m = { key = key, name = key, category = "Misc", calls = {} }
	m.toggle = function(active)
		m.calls[#m.calls + 1] = active
	end
	for k, v in pairs(extra or {}) do
		m[k] = v
	end
	return ns.RegisterModule(m)
end

test("MergeDefaults adds missing nested keys and keeps existing values", function()
	local defaults = { a = 1, t = { x = 1, y = 2 } }
	local dst = ns.MergeDefaults(defaults, { a = 5, t = { x = 9 } })
	eq(dst.a, 5, "a")
	eq(dst.t.x, 9, "t.x")
	eq(dst.t.y, 2, "t.y")
end)

test("MergeDefaults does not share default tables", function()
	local defaults = { t = {} }
	local a = ns.MergeDefaults(defaults, {})
	local b = ns.MergeDefaults(defaults, {})
	a.t.z = 1
	eq(b.t.z, nil, "b.t.z")
	eq(defaults.t.z, nil, "defaults.t.z")
end)

test("RegisterModule rejects a duplicate key", function()
	reset()
	newModule("a")
	eq(pcall(newModule, "a"), false, "duplicate accepted")
end)

test("enabledByDefault module activates on InitModules, toggle called once", function()
	reset()
	local m = newModule("a", { enabledByDefault = true })
	ns.InitModules({})
	eq(m.active, true, "active")
	eq(#m.calls, 1, "calls")
	eq(m.calls[1], true, "call 1")
end)

test("module without enabledByDefault stays off and toggle is not called", function()
	reset()
	local m = newModule("a")
	ns.InitModules({})
	eq(m.active, false, "active")
	eq(#m.calls, 0, "calls")
end)

test("saved enabled=false overrides enabledByDefault", function()
	reset()
	local m = newModule("a", { enabledByDefault = true })
	ns.InitModules({ enabled = { a = false } })
	eq(m.active, false, "active")
end)

test("InitModules merges defaults into db[key], sets module.db and calls init before toggle", function()
	reset()
	local order = {}
	local m = newModule("a", { enabledByDefault = true, defaults = { n = 3, t = { k = 1 } } })
	m.init = function(db)
		order[#order + 1] = "init:" .. db.n
	end
	m.toggle = function()
		order[#order + 1] = "toggle"
	end
	local db = { a = { n = 7 } }
	ns.InitModules(db)
	eq(m.db, db.a, "module.db")
	eq(db.a.n, 7, "kept value")
	eq(db.a.t.k, 1, "merged nested")
	eq(order[1], "init:7", "init first")
	eq(order[2], "toggle", "toggle second")
end)

test("SetModuleEnabled toggles only on change and saves the choice", function()
	reset()
	local m = newModule("a", { enabledByDefault = true })
	local db = {}
	ns.InitModules(db)
	ns.SetModuleEnabled("a", false)
	ns.SetModuleEnabled("a", false)
	eq(#m.calls, 2, "calls")
	eq(m.calls[2], false, "call 2")
	eq(db.enabled.a, false, "saved")
	ns.SetModuleEnabled("a", true)
	eq(m.calls[3], true, "call 3")
	eq(db.enabled.a, true, "saved again")
end)

test("blocked module is not active until the reason is gone", function()
	reset()
	local reason = "busy"
	local m = newModule("a", {
		enabledByDefault = true,
		blocked = function()
			return reason
		end,
	})
	ns.InitModules({})
	eq(m.active, false, "active while blocked")
	eq(ns.ModuleBlockedReason(m), "busy", "reason")
	eq(ns.ModuleEnabled(m), true, "still enabled")
	reason = nil
	ns.RefreshModule(m)
	eq(m.active, true, "active after unblock")
	eq(#m.calls, 1, "calls")
end)

test("a toggle error is reported and does not stop other modules", function()
	reset()
	local bad = newModule("bad", { enabledByDefault = true })
	bad.toggle = function()
		error("boom")
	end
	local good = newModule("good", { enabledByDefault = true })
	ns.InitModules({})
	eq(#errors, 1, "errors")
	eq(errors[1]:find("boom", 1, true) ~= nil, true, "error text")
	eq(bad.active, true, "bad stays active so disabling still cleans up")
	eq(good.active, true, "good active")
end)

test("ModuleCategories lists categories in order of first use", function()
	reset()
	newModule("a", { category = "Travel" })
	newModule("b", { category = "Social" })
	newModule("c", { category = "Travel" })
	local cats = ns.ModuleCategories()
	eq(#cats, 2, "count")
	eq(cats[1], "Travel", "first")
	eq(cats[2], "Social", "second")
end)

test("ModuleMatches searches name and description, case-insensitive", function()
	reset()
	local m = newModule("a", { name = "Flight Timer", description = "Times Flight paths" })
	eq(ns.ModuleMatches(m, ""), true, "empty")
	eq(ns.ModuleMatches(m, "timer"), true, "name")
	eq(ns.ModuleMatches(m, "paths"), true, "description")
	eq(ns.ModuleMatches(m, "bags"), false, "no match")
end)

test("AnyCinematicState only asks active modules", function()
	reset()
	local state = {}
	local off = newModule("off", {
		cinematicState = function()
			return {}
		end,
	})
	local on = newModule("on", {
		enabledByDefault = true,
		cinematicState = function()
			return state
		end,
	})
	ns.InitModules({})
	eq(ns.AnyCinematicState(), state, "state")
	ns.SetModuleEnabled("on", false)
	eq(ns.AnyCinematicState(), nil, "none")
	eq(off.active, false, "off inactive")
end)

test("CopyFlightData deep-copies and drops FlightTimer's runtime state", function()
	local src = {
		routes = { ["1>2"] = 50 },
		stats = { flights = 3, byMap = { [2214] = 120 } },
		alert = false,
		current = { start = 1 },
		musicVolumeBackup = "0.4",
	}
	local copy = ns.CopyFlightData(src)
	eq(copy.routes["1>2"], 50, "routes")
	eq(copy.stats.byMap[2214], 120, "nested")
	eq(copy.alert, false, "false value kept")
	eq(copy.current, nil, "current dropped")
	eq(copy.musicVolumeBackup, nil, "backup dropped")
	copy.stats.flights = 99
	copy.routes["3>4"] = 1
	eq(src.stats.flights, 3, "source unchanged")
	eq(src.routes["3>4"], nil, "source tables not shared")
	eq(src.current.start, 1, "source keeps current")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
