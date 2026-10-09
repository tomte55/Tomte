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

test("MergeDefaults replaces a saved table where the default is a plain value now", function()
	local dst = ns.MergeDefaults({ a = "x", b = 2, t = { c = true } }, { a = { old = 1 }, b = 5, t = "old" })
	eq(dst.a, "x", "a")
	eq(dst.b, 5, "b kept")
	eq(type(dst.t), "table", "t")
	eq(dst.t.c, true, "t.c")
end)

test("RunMigrations runs each pending migration once, in order", function()
	local order = {}
	local migrations = {
		function(db) order[#order + 1] = 1; db.a = nil end,
		function(db) order[#order + 1] = 2; db.b = (db.b or 0) + 1 end,
	}
	local db = { a = true }
	ns.RunMigrations(db, migrations)
	eq(table.concat(order, ","), "1,2", "order")
	eq(db.schema, 2, "schema")
	eq(db.a, nil, "a removed")
	ns.RunMigrations(db, migrations)
	eq(#order, 2, "not run again")
	eq(db.b, 1, "b once")
	migrations[3] = function(db) order[#order + 1] = 3 end
	ns.RunMigrations(db, migrations)
	eq(table.concat(order, ","), "1,2,3", "only the new one")
	eq(db.schema, 3, "schema 3")
end)

test("RunMigrations stops at an error and retries it later", function()
	reset()
	local fail = true
	local runs = 0
	local migrations = {
		function() end,
		function() runs = runs + 1; if fail then error("boom") end end,
		function(db) db.third = true end,
	}
	local db = {}
	ns.RunMigrations(db, migrations)
	eq(db.schema, 1, "schema after error")
	eq(db.third, nil, "later one not run")
	eq(#errors, 1, "error reported")
	fail = false
	ns.RunMigrations(db, migrations)
	eq(runs, 2, "retried")
	eq(db.schema, 3, "schema")
	eq(db.third, true, "third")
end)

test("ResetModuleSettings resets settings and keeps collections, keep keys and unknown keys", function()
	reset()
	local m = newModule("flight", { defaults = {
		alert = true, frame = { x = 0, locked = true }, routes = {}, store = { convos = {} },
		stats = { flights = 0 }, styles = { zone = "cinematic" },
	}, keep = { "stats" } })
	ns.InitModules({ flight = {
		alert = false, frame = { x = 50, locked = false }, routes = { r = 1 }, store = { convos = { c = 1 } },
		stats = { flights = 9 }, styles = { zone = "off", extra = "x" }, faction = 7,
	} })
	local db = m.db
	ns.ResetModuleSettings(m)
	eq(m.db, db, "same table")
	eq(db.alert, true, "alert")
	eq(db.frame.x, 0, "frame.x")
	eq(db.frame.locked, true, "frame.locked")
	eq(db.styles.zone, "cinematic", "styles.zone")
	eq(db.styles.extra, nil, "styles.extra")
	eq(db.routes.r, 1, "collection kept")
	eq(db.store.convos.c, 1, "nested collection kept")
	eq(db.stats.flights, 9, "keep key")
	eq(db.faction, 7, "key outside defaults kept")
end)

test("ResetModuleSettings uses module.keep", function()
	reset()
	local m = newModule("a", { defaults = { seen = 0, on = true }, keep = { "seen" } })
	ns.InitModules({ a = { seen = 42, on = false } })
	ns.ResetModuleSettings(m)
	eq(m.db.seen, 42, "seen")
	eq(m.db.on, true, "on")
end)

test("ResetAllSettings resets modules, enabled state and the window, keeps the engine's backup", function()
	reset()
	local m = newModule("a", { defaults = { on = true } })
	local db = { a = { on = false }, enabled = { a = true }, panel = { layout = { x = 1 }, collapsed = { G = true } },
		toast = { point = {} }, cinematic = { musicVolumeBackup = "0.5" }, schema = 1 }
	ns.InitModules(db)
	ns.ResetAllSettings(db, { enabled = {}, panel = { collapsed = {} }, cinematic = {}, toast = {} })
	eq(m.db.on, true, "module setting")
	eq(next(db.enabled), nil, "enabled")
	eq(db.panel.layout, nil, "layout")
	eq(next(db.panel.collapsed), nil, "collapsed")
	eq(db.toast.point, nil, "toast")
	eq(db.cinematic.musicVolumeBackup, "0.5", "backup")
	eq(db.schema, 1, "schema")
end)

test("ChoiceOrDefault falls back when the value isn't a choice", function()
	local choices = { { value = "a", text = "A" }, { value = "b", text = "B" } }
	eq(ns.ChoiceOrDefault("b", choices, "a"), "b", "valid")
	eq(ns.ChoiceOrDefault("gone", choices, "a"), "a", "invalid")
	eq(ns.ChoiceOrDefault(nil, choices, "a"), "a", "nil")
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
