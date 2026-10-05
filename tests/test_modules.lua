-- Run from the AddOns folder: lua Tomte/tests/test_modules.lua
local errors = {}
local ns = {
	errorHandler = function(err)
		errors[#errors + 1] = tostring(err)
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

-- Fresh registry for each test. Returns a module whose toggle calls are recorded in module.calls.
local function reset()
	ns.modules, ns.modulesByKey, ns.homeByKey = {}, {}, {}
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

test("HomeEntries lists visible entries of a kind in registration order", function()
	reset()
	local hunter = false
	newModule("a", { enabledByDefault = true, home = {
		{ kind = "page", key = "pa" },
		{ kind = "map", key = "ma" },
	} })
	newModule("b", { enabledByDefault = true, home = {
		{ kind = "page", key = "pb", shown = function() return hunter end },
		{ kind = "page", key = "pb2" },
	} })
	newModule("c", { home = { { kind = "page", key = "pc" } } }) -- off by default
	ns.InitModules({})
	local pages = ns.HomeEntries("page")
	eq(#pages, 2, "pages")
	eq(pages[1].key, "pa", "first")
	eq(pages[2].key, "pb2", "hidden by shown()")
	eq(ns.HomeEntries("map")[1].module.key, "a", "entry knows its module")
	hunter = true
	eq(#ns.HomeEntries("page"), 3, "shown() true")
	ns.SetModuleEnabled("c", true)
	eq(ns.HomeEntries("page")[4].key, "pc", "turned on")
	eq(ns.homeByKey.pc.module.key, "c", "by key")
	eq(#ns.ModulePages(ns.modulesByKey.b), 2, "module pages ignore shown()")
end)

test("RegisterModule rejects a duplicate home entry key", function()
	reset()
	newModule("a", { home = { { kind = "page", key = "x" } } })
	local ok = pcall(newModule, "b", { home = { { kind = "page", key = "x" } } })
	eq(ok, false, "duplicate")
end)

test("ModuleDependencies says whether used addons are loaded and conflicting ones aren't", function()
	reset()
	local m = newModule("a", {
		uses = { { addon = "Syndicator", why = "item counts", without = "only this character" } },
		conflicts = { { addon = "WaypointUI", why = "stays off while it's enabled" } },
	})
	local loaded = { Syndicator = true }
	local lines = ns.ModuleDependencies(m, function(name) return loaded[name] == true end)
	eq(#lines, 2, "lines")
	eq(lines[1].ok, true, "uses ok")
	eq(lines[1].text, "Uses Syndicator: item counts", "uses text")
	eq(lines[2].ok, true, "no conflict")
	loaded = { WaypointUI = true }
	lines = ns.ModuleDependencies(m, function(name) return loaded[name] == true end)
	eq(lines[1].ok, false, "missing")
	eq(lines[1].text, "Uses Syndicator: not loaded, only this character", "without text")
	eq(lines[2].ok, false, "conflict loaded")
	eq(#ns.ModuleDependencies(newModule("b"), function() return true end), 0, "none")
end)

test("HomeEntries sorts by order, then registration", function()
	reset()
	newModule("a", { enabledByDefault = true, home = { { kind = "page", key = "late" }, { kind = "page", key = "first", order = 1 } } })
	newModule("b", { enabledByDefault = true, home = { { kind = "page", key = "second", order = 2 } } })
	ns.InitModules({})
	local pages = ns.HomeEntries("page")
	eq(pages[1].key, "first", "1")
	eq(pages[2].key, "second", "2")
	eq(pages[3].key, "late", "default last")
end)

test("an alwaysOn module stays enabled", function()
	reset()
	local m = newModule("w", { alwaysOn = true })
	ns.InitModules({ enabled = { w = false } })
	eq(ns.ModuleEnabled(m), true, "enabled")
	eq(m.active, true, "active")
end)

test("PanelResume reopens where you were for a while, then Home", function()
	local ok = function(key) return key == "alts" end
	local view, key = ns.PanelResume({ view = "page", page = "alts", at = 1000 }, 1100, 300, ok)
	eq(view, "page", "page")
	eq(key, "alts", "key")
	eq((ns.PanelResume({ view = "page", page = "alts", at = 1000 }, 1400, 300, ok)), "home", "too long ago")
	eq((ns.PanelResume({ view = "page", page = "gone", at = 1000 }, 1100, 300, ok)), "home", "page gone")
	eq((ns.PanelResume({ view = "settings", at = 1000 }, 1100, 300, ok)), "settings", "settings")
	eq((ns.PanelResume({ view = "page", page = "alts", at = 1000 }, 1100, 0, ok)), "home", "turned off")
	eq((ns.PanelResume(nil, 1100, 300, ok)), "home", "first time")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
