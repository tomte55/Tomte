-- Run from the AddOns folder: lua Tomte/tests/test_profile.lua
local ns = {
	errorHandler = function(err)
		error(err)
	end,
}
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Profile.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Modules()
	ns.modules, ns.modulesByKey, ns.homeByKey = {}, {}, {}
	ns.RegisterModule({ key = "window", name = "Tomte window", category = "General", alwaysOn = true,
		defaults = { theme = "blizzard", opacity = 0.96, around = { wqaround = true } },
		options = { { type = "dropdown", key = "theme", label = "Theme", choices = function()
			return { { value = "blizzard", text = "Blizzard" }, { value = "void", text = "Void" } }
		end } } })
	ns.RegisterModule({ key = "mount", name = "Smart Mount", category = "Travel", enabledByDefault = true,
		defaults = { zones = {}, useZones = true, preferGround = true },
		options = { { type = "checkbox", key = "preferGround", label = "Prefer ground mounts" } } })
	ns.RegisterModule({ key = "alts", name = "Alts", category = "General", enabledByDefault = true,
		defaults = { chars = {}, view = "craft", sendRules = "", filterFor = "all", crafts = 1, sendSubject = "Tomte",
			tracker = { shown = true, scale = 1, collapsed = false } },
		keep = { "sendRules" }, noShare = { "filterFor" },
		options = { { type = "slider", key = "tracker.scale", label = "Tracker size", min = 0.5, max = 2 } } })
	ns.RegisterModule({ key = "pet", name = "Pet Health", category = "Combat", enabledByDefault = true,
		defaults = { frame = { point = "CENTER", x = 0, y = -170, locked = true }, threshold = 40 } })
	ns.RegisterModule({ key = "next", name = "Next up", category = "General", enabledByDefault = true,
		defaults = { rows = 5, sources = {}, priority = {} }, shareMaps = { sources = "boolean", priority = "number" } })
	ns.RegisterModule({ key = "gather", name = "Gathering", category = "General", enabledByDefault = true,
		defaults = { auto = true, runs = {}, spells = {}, pageScope = "all", pageView = "runs" },
		noShare = { "pageScope", "pageView" } })
	local db = { enabled = {} }
	for _, m in ipairs(ns.modules) do
		db[m.key] = ns.MergeDefaults(m.defaults or {}, {})
	end
	return db
end

test("IsCollection is public and recursive", function()
	eq(ns.IsCollection({}), true, "empty")
	eq(ns.IsCollection({ a = {}, b = { c = {} } }), true, "nested empty")
	eq(ns.IsCollection({ a = 1 }), false, "value")
	eq(ns.IsCollection(1), false, "not a table")
end)

test("schema skips collections, keep, view, collapsed, positions and noShare", function()
	Modules()
	local s = ns.Profile_Schema(ns.modulesByKey.alts)
	eq(s.crafts, "number", "crafts")
	eq(s.sendSubject, "string", "sendSubject")
	eq(s["tracker.shown"], "boolean", "tracker.shown")
	eq(s["tracker.scale"], "number", "tracker.scale")
	eq(s.chars, nil, "collection")
	eq(s.view, nil, "view")
	eq(s.sendRules, nil, "keep")
	eq(s.filterFor, nil, "noShare")
	eq(s["tracker.collapsed"], nil, "collapsed")
	local p = ns.Profile_Schema(ns.modulesByKey.pet)
	eq(p.threshold, "number", "threshold")
	eq(p["frame.x"], nil, "position")
	eq(p["frame.locked"], nil, "whole position table")
	local n = ns.Profile_Schema(ns.modulesByKey.next)
	eq(n["sources.*"], "boolean", "map")
	eq(n["priority.*"], "number", "map")
	eq(ns.Profile_Schema(ns.modulesByKey.window)["around.wqaround"], "boolean", "filled map is a setting")
end)

test("gathering's page filters and history aren't settings", function()
	Modules()
	local s = ns.Profile_Schema(ns.modulesByKey.gather)
	eq(s.auto, "boolean", "auto")
	eq(s.pageScope, nil, "page filter")
	eq(s.pageView, nil, "page view")
	eq(s.runs, nil, "runs")
	eq(s.spells, nil, "spells")
end)

-- The real modules list their page filters as noShare (the fakes above can't tell).
test("Gathering and Session recap keep their page filters out of settings strings", function()
	local function Source(path)
		local f = assert(io.open(path, "rb"))
		local text = f:read("*a")
		f:close()
		return text
	end
	local gather = Source("Tomte/Modules/Gather/Gather.lua")
	eq(gather:find('noShare = { "pageScope", "pageRange", "pageKind", "pageView" }', 1, true) ~= nil, true,
		"Gather noShare")
	local recap = Source("Tomte/Modules/Recap/Recap.lua")
	eq(recap:find('noShare = { "pageScope", "pageRange" }', 1, true) ~= nil, true, "Recap noShare")
end)

test("a dotted default key raises in Profile_Schema", function()
	local ok = pcall(ns.Profile_Schema, { key = "x", defaults = { ["a.b"] = 1 } })
	eq(ok, false, "raises")
end)

test("get and set walk dotted paths", function()
	local t = { a = { b = 1 } }
	eq(ns.Profile_Get(t, "a.b"), 1, "get")
	eq(ns.Profile_Get(t, "a.c.d"), nil, "missing")
	eq(ns.Profile_Get(t, "a.b.c"), nil, "through a value")
	ns.Profile_Set(t, "x.y", true)
	eq(t.x.y, true, "set creates tables")
end)

test("collect writes every shareable value and the full module on/off state", function()
	local db = Modules()
	db.enabled.mount = false
	db.next.sources.nextrare = false
	db.next.sources["bad key"] = true
	db.next.priority.nextrare = "x"
	local payload = ns.Profile_Collect(db, ns.modules, "1.5.0")
	eq(payload.v, 1, "v")
	eq(payload.from, "1.5.0", "from")
	eq(payload.enabled.mount, false, "mount off")
	eq(payload.enabled.alts, true, "alts default on")
	eq(payload.enabled.window, nil, "alwaysOn left out")
	eq(payload.settings.mount.preferGround, true, "unchanged values too")
	eq(payload.settings.next["sources.nextrare"], false, "map entry")
	eq(payload.settings.next["sources.bad key"], nil, "bad map key left out")
	eq(payload.settings.next["priority.nextrare"], nil, "wrong map value type left out")
	eq(payload.settings.alts.sendRules, nil, "keep left out")
	eq(payload.settings.window.theme, "blizzard", "theme travels")
end)

test("collect then check against yourself has no changes", function()
	local db = Modules()
	db.enabled.mount = false
	db.alts.tracker.scale = 1.5
	db.next.priority.nextrare = 3
	local result = ns.Profile_Check(ns.Profile_Collect(db, ns.modules, "1.5.0"), ns.modules, db)
	eq(result.changes, 0, "changes")
	eq(result.skipped, 0, "skipped")
end)

test("check skips wrong types and unknown paths", function()
	local db = Modules()
	local result = ns.Profile_Check({ v = 1, enabled = {}, settings = {
		mount = { preferGround = false, useZones = "yes", bogus = 1 },
		unknownmod = { a = 1 },
		alts = { crafts = 0 / 0, ["tracker.scale"] = 9, sendSubject = "|cffff0000x" },
		window = { theme = "neon" },
		next = { ["sources.nextrare"] = false, ["sources.bad key"] = true, ["priority.x"] = 1 / 0 },
	} }, ns.modules, db)
	eq(result.changes, 3, "preferGround, tracker.scale (clamped), sources.nextrare")
	eq(result.skipped, 8, "useZones, bogus, unknownmod.a, NaN, pipe, theme, bad key, inf")
	local alts
	for _, g in ipairs(result.groups) do
		if g.key == "alts" then
			alts = g
		end
	end
	eq(alts.rows[1].new, 2, "clamped to the slider max")
	eq(alts.rows[1].old, 1, "old value")
	eq(alts.rows[1].label, "Tracker size", "label from the option")
end)

test("check skips odd keys, long strings and non-table modules", function()
	local db = Modules()
	local result = ns.Profile_Check({ v = 1, settings = {
		next = { ["sources.*"] = true, [1] = true },
		alts = { sendSubject = ("x"):rep(ns.PROFILE_MAX_STRING + 1), filterFor = "x", sendRules = "Bob" },
		mount = "nope",
		pet = { ["frame.x"] = 5 },
	} }, ns.modules, db)
	eq(result.changes, 0, "changes")
	eq(result.skipped, 7, "literal *, number key, long string, noShare, keep, non-table, position")
end)

test("check takes a valid dropdown value and orders groups", function()
	local db = Modules()
	local result = ns.Profile_Check({ v = 1, enabled = { gather = false }, settings = {
		window = { theme = "void" }, mount = { preferGround = false } } }, ns.modules, db)
	eq(result.groups[1].key, "_enabled", "on/off first")
	eq(result.groups[1].name, "Modules on/off", "name")
	eq(result.groups[2].key, "window", "then registration order")
	eq(result.groups[3].key, "mount", "mount")
	eq(result.groups[2].rows[1].new, "void", "theme")
	eq(result.changes, 3, "changes")
end)

test("check reads enabled defensively", function()
	local db = Modules()
	local result = ns.Profile_Check({ v = 1, settings = {},
		enabled = { mount = false, window = false, nope = true, alts = "x" } }, ns.modules, db)
	eq(result.groups[1].key, "_enabled", "first group")
	eq(#result.groups[1].rows, 1, "only mount")
	eq(result.groups[1].rows[1].label, "Smart Mount", "label")
	eq(result.skipped, 3, "window, nope, alts")
end)

test("check refuses non-tables and other versions", function()
	local db = Modules()
	eq(select(2, ns.Profile_Check("x", ns.modules, db)), "That's not a Tomte settings string.", "string")
	eq(select(2, ns.Profile_Check({ v = 2 }, ns.modules, db)), "Made by a newer Tomte. Update Tomte first.", "v2")
	eq(select(2, ns.Profile_Check({}, ns.modules, db)), "That's not a Tomte settings string.", "no v")
	local ok = ns.Profile_Check({ v = 1, settings = "x", enabled = 5 }, ns.modules, db)
	eq(ok.changes, 0, "odd parts are ignored")
end)

test("check stops reading after the entry cap", function()
	local db = Modules()
	local many = {}
	for i = 1, ns.PROFILE_MAX_ENTRIES + 50 do
		many["k" .. i] = 1
	end
	local result = ns.Profile_Check({ v = 1, settings = { mount = many } }, ns.modules, db)
	eq(result.skipped <= ns.PROFILE_MAX_ENTRIES, true, "capped")
end)

test("apply writes only the chosen groups", function()
	local db = Modules()
	local result = ns.Profile_Check({ v = 1, enabled = { mount = false }, settings = {
		mount = { preferGround = false }, alts = { ["tracker.scale"] = 1.5 } } }, ns.modules, db)
	local n = ns.Profile_Apply(db, result, { mount = true, _enabled = true })
	eq(n, 2, "written")
	eq(db.mount.preferGround, false, "mount")
	eq(db.enabled.mount, false, "enabled")
	eq(db.alts.tracker.scale, 1, "alts not chosen")
end)

test("encode and decode round trip with a codec", function()
	local stored
	local codec = {
		encode = function(t)
			stored = t
			return "QUJD"
		end,
		decode = function(s)
			assert(s == "QUJD")
			return stored
		end,
	}
	local text = ns.Profile_Encode({ v = 1, settings = {} }, codec)
	eq(text, "Tomte1:QUJD", "text")
	eq(ns.Profile_Decode(text, codec).v, 1, "decoded")
end)

test("encode reports a failing codec", function()
	eq(ns.Profile_Encode({}, { encode = function() error("x") end }), nil, "raises")
	eq(ns.Profile_Encode({}, { encode = function() return nil end }), nil, "nil")
end)

test("decode strips fences and whitespace", function()
	local codec = { encode = function() return "" end, decode = function(s)
		assert(s == "QUJD")
		return { v = 1 }
	end }
	eq(ns.Profile_Decode("```\nTomte1:QU\n JD\n```", codec).v, 1, "fenced")
	eq(ns.Profile_Decode("  Tomte1:QUJD  ", codec).v, 1, "spaces")
	eq(ns.Profile_Decode("\r\n`Tomte1:QUJD`\r\n", codec).v, 1, "inline code")
end)

test("decode errors", function()
	local boom = { decode = function() error("bad cbor") end }
	local none = { decode = function() return nil end }
	local text = { decode = function() return "x" end }
	eq(select(2, ns.Profile_Decode("", boom)), "Paste a Tomte settings string first.", "empty")
	eq(select(2, ns.Profile_Decode(nil, boom)), "Paste a Tomte settings string first.", "nil")
	eq(select(2, ns.Profile_Decode("!WA:2!abc", boom)), "That's not a Tomte settings string.", "WeakAuras")
	eq(select(2, ns.Profile_Decode("Tomte1:", boom)), "That's not a Tomte settings string.", "no body")
	eq(select(2, ns.Profile_Decode("Tomte2:abc", boom)), "Made by a newer Tomte. Update Tomte first.", "newer")
	eq(select(2, ns.Profile_Decode("Tomte1:abc", boom)), "The string is damaged. Copy it again.", "raises")
	eq(select(2, ns.Profile_Decode("Tomte1:abc", none)), "The string is damaged. Copy it again.", "nil")
	eq(select(2, ns.Profile_Decode("Tomte1:abc", text)), "The string is damaged. Copy it again.", "not a table")
	eq(select(2, ns.Profile_Decode("Tomte1:" .. ("A"):rep(ns.PROFILE_MAX_TEXT), boom)),
		"Too long to be a Tomte settings string.", "long")
end)

test("value text", function()
	eq(ns.Profile_ValueText(true), "on", "true")
	eq(ns.Profile_ValueText(false), "off", "false")
	eq(ns.Profile_ValueText(0.957), "0.96", "number")
	eq(ns.Profile_ValueText(0.5), "0.5", "trailing zero")
	eq(ns.Profile_ValueText(5), "5", "whole number")
	eq(ns.Profile_ValueText("void"), "\"void\"", "string")
	eq(ns.Profile_ValueText(nil), "(not set)", "nil")
end)

H.done()
