# Friend-facing Extras Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three things for friends who install Tomte: a first-run preset picker (`/tomte setup`), a copyable bug
report (`/tomte bug`) and settings profiles (export string, import with preview, confirm and undo).

**Architecture:** The rules sit in pure files under `Core/` (presets, profile schema and checking, error filtering
and report text), unit-tested with plain Lua. The game readers and windows sit under `Panel/` and call the pure
functions with plain tables. `C_EncodingUtil` is reached only through a `codec` object, so tests use a fake one.

**Tech stack:** WoW retail 12.1 Lua (5.1), Tomte's `ns.UI` toolkit and theme roles, `ns.RegisterModule` options,
`C_EncodingUtil` (CBOR, Deflate, Base64), BugGrabber's read API, `ScriptErrorsFrame.errorData`.

**Spec:** `docs/superpowers/specs/2026-10-10-tomte-friend-extras-design.md`.

**Execution:** after the user has reviewed the spec's open questions. Work stays uncommitted until the user has
checked it in game (CLAUDE.md); then one commit and a CHANGELOG line.

## Global constraints

- Lua 5.1 syntax (CI runs 5.1): no `goto`, no `//`, no `utf8`, no integer division.
- No numeric RGB in `SetTextColor`, `SetVertexColor`, `SetColorTexture` or `CreateColor`; colors come from theme roles
  (`UI.Color(role)`, `UI.Text(parent, size, role, fontRole)`, `UI.Panel(frame)`). No `|cff` literals, no font paths.
  `tests/test_theme.lua` scans for them.
- One event frame per file, dispatching with `self[event](self, ...)`.
- No new globals except the named frames `TomteDialog`, `TomteSetup`, `TomteImportPreview` (for `UISpecialFrames`).
- Pure files (`Core/Setup.lua`, `Core/Profile.lua`, `Core/BugReport.lua`, `Core/BugFiles.lua`) make no WoW API call
  at load or in their functions, except `issecretvalue`, looked up at call time and treated as absent when nil.
- Never `loadstring`, `RunScript` or a call on imported data. Imported values are only written at paths that exist
  in the current defaults.
- Nothing is sent anywhere: no addon messages, no mail, no chat output beyond `ns.Print` to the user.
- Existing users must not see the picker unless they type `/tomte setup`.
- Picker apply, import and undo refuse in combat (`InCombatLockdown()`), with a message.
- The bug report text carries no character name, realm, BattleTag or gold.
- Export, import and reset agree on what a setting is: `ns.IsCollection` and `module.keep` from `Core/Modules.lua`.

## Review focus

1. **An existing user updating from 1.4.x** (TomteDB with `schema = 1`, no `setup` key) must get `state = "done"` and
   the one-time note, never the picker; a fresh install must stay `pending` even though migrations run on it. →
   Task 1 tests "existing user is marked done" and "fresh install stays pending".
2. **A pasted string with line breaks, spaces or Discord code fences** (```` ``` ````) must import as if it were
   clean. → Task 2 test "decode strips fences and whitespace".
3. **A string from an older or newer Tomte where a setting changed type** (string → number) or no longer exists must
   skip those values and count them, never error or write the wrong type. → Task 2 test "check skips wrong types and
   unknown paths".
4. **BugGrabber entries whose message is a table, nil or secret** must become "(unreadable)" / "(hidden by the game:
   secret value)", never break the report. → Task 3 test "normalize survives odd messages".
5. **Error paths shortened by Lua to `...ules/Alts/Send.lua:12:`** must still count as Tomte's, while
   `AddOns/TomteFoo/` and other addons' `...` paths must not. → Task 3 tests on `Bug_IsTomte`.

---

### Task 1: Presets and first-run state (`Core/Setup.lua`)

**Files:**
- Create: `Core/Setup.lua`
- Test: `tests/test_setup.lua`

**Interfaces:**
- Consumes: `ns.RegisterModule`, `ns.RefreshModule`, `ns.ModuleEnabled` (Core/Modules.lua).
- Produces:
  - `ns.SETUP_BASE = { "minimap", "vendor", "dura", "hunter", "pet", "rogue" }`
  - `ns.SETUP_PRESETS = { { key, name, text, on = {keys} | nil, all = true | nil } ... }` in the order minimal,
    collector, crafter, everything.
  - `ns.Setup_Preset(key)` → preset or nil.
  - `ns.Setup_Plan(key, modules)` → `{ clear = true }` for everything, else `{ enabled = { [moduleKey] = bool } }`
    for every module that isn't `alwaysOn`; `nil, "unknown preset"` for a bad key.
  - `ns.Setup_OnNames(key, modules)` → module names the preset turns on, in registration order.
  - `ns.Setup_Matches(key, modules)` → true when every module's `ns.ModuleEnabled` equals the plan.
  - `ns.Setup_Apply(db, plan, modules)`: writes `db.enabled` (clears it in place for `clear`), then
    `ns.RefreshModule` for each module.
  - `ns.Setup_MarkFresh(db)`: `db.setup = { state = "pending" }`.
  - `ns.Setup_Migrate(db)`: settings migration 2 (see Task 4).

- [ ] **Step 1: Write the failing tests** (`tests/test_setup.lua`, same harness as `tests/test_home.lua`: `test`,
  `eq`, the failure count and `os.exit(1)` at the end)

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_setup.lua
local ns = { errorHandler = function(err) error(err) end }
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Setup.lua"))("Tomte", ns)
-- (test / eq helpers as in test_home.lua)

-- The real module keys, read from the source so a renamed module breaks this test.
local function RealKeys()
	local keys = {}
	for line in io.lines("Tomte/Tomte.toc") do
		local file = line:match("^([%w_/\\]+%.lua)%s*$")
		if file then
			local f = assert(io.open("Tomte/" .. file:gsub("\\", "/")))
			local text = f:read("*a")
			f:close()
			for key in text:gmatch("RegisterModule%(%{%s*key%s*=%s*\"([%w_]+)\"") do
				keys[key] = true
			end
		end
	end
	return keys
end

local calls
local function Register()
	ns.modules, ns.modulesByKey, ns.homeByKey = {}, {}, {}
	calls = {}
	ns.RegisterModule({ key = "window", name = "Tomte window", category = "General", alwaysOn = true })
	for key in pairs(RealKeys()) do
		if key ~= "window" then
			ns.RegisterModule({ key = key, name = "N-" .. key, category = "X", enabledByDefault = true,
				toggle = function(on) calls[#calls + 1] = key .. (on and "+" or "-") end })
		end
	end
	ns.db = { enabled = {} }
	for _, m in ipairs(ns.modules) do
		ns.RefreshModule(m)
	end
	calls = {}
end

test("every preset and base key is a registered module key", function()
	local real = RealKeys()
	eq(real.window, true, "source scan finds modules")
	for _, key in ipairs(ns.SETUP_BASE) do
		eq(real[key], true, "base " .. key)
	end
	for _, preset in ipairs(ns.SETUP_PRESETS) do
		for _, key in ipairs(preset.on or {}) do
			eq(real[key], true, preset.key .. " " .. key)
		end
	end
end)

test("crafter plan turns its modules and the base on, the rest off, never touches window", function()
	Register()
	local plan = ns.Setup_Plan("crafter", ns.modules)
	eq(plan.enabled.alts, true, "alts")
	eq(plan.enabled.value, true, "value")
	eq(plan.enabled.hunter, true, "class modules are base")
	eq(plan.enabled.afk, false, "afk")
	eq(plan.enabled.whispers, false, "whispers")
	eq(plan.enabled.window, nil, "window is always on")
end)

test("everything clears the choices", function()
	Register()
	ns.db.enabled.afk = false
	local plan = ns.Setup_Plan("everything", ns.modules)
	eq(plan.clear, true, "clear")
	ns.Setup_Apply(ns.db, plan, ns.modules)
	eq(next(ns.db.enabled), nil, "enabled emptied")
end)

test("apply writes choices, refreshes modules and keeps the enabled table", function()
	Register()
	local before = ns.db.enabled
	ns.Setup_Apply(ns.db, ns.Setup_Plan("minimal", ns.modules), ns.modules)
	eq(ns.db.enabled, before, "same table")
	eq(ns.db.enabled.recap, false, "recap off")
	eq(ns.modulesByKey.recap.active, false, "recap stopped")
	eq(ns.modulesByKey.gear.active, true, "gear running")
end)

test("matches is true right after applying and false after a change", function()
	Register()
	ns.Setup_Apply(ns.db, ns.Setup_Plan("collector", ns.modules), ns.modules)
	eq(ns.Setup_Matches("collector", ns.modules), true, "matches")
	eq(ns.Setup_Matches("crafter", ns.modules), false, "other preset")
	ns.SetModuleEnabled("ach", false)
	eq(ns.Setup_Matches("collector", ns.modules), false, "after a change")
end)

test("unknown preset is an error, not a crash", function()
	Register()
	local plan, err = ns.Setup_Plan("nope", ns.modules)
	eq(plan, nil, "plan")
	eq(err, "unknown preset", "err")
end)

test("OnNames lists module names in registration order", function()
	Register()
	local names = ns.Setup_OnNames("minimal", ns.modules)
	eq(#names, #ns.SETUP_BASE + 4, "count")
end)

test("existing user is marked done with a note", function()
	local db = { schema = 1, enabled = { afk = false } }
	ns.Setup_Migrate(db)
	eq(db.setup.state, "done", "state")
	eq(db.setup.note, true, "note")
end)

test("fresh install stays pending through the migration", function()
	local db = {}
	ns.Setup_MarkFresh(db)
	ns.Setup_Migrate(db)
	eq(db.setup.state, "pending", "state")
	eq(db.setup.note, nil, "no note")
end)
```

- [ ] **Step 2: Run to see it fail**

Run (from `AddOns`): `lua Tomte/tests/test_setup.lua`
Expected: error loading `Tomte/Core/Setup.lua` (file missing).

- [ ] **Step 3: Implement `Core/Setup.lua`**

```lua
local addonName, ns = ...

-- First-run presets: which modules a new user starts with. Pure (no WoW API), unit-tested. The window is
-- Panel/Setup.lua. Base modules are in every preset: cheap, quiet, and the class ones only run for their class.

ns.SETUP_BASE = { "minimap", "vendor", "dura", "hunter", "pet", "rogue" }

ns.SETUP_PRESETS = {
	{ key = "minimal", name = "Minimal", text = "Just the helpers, nothing pops up.",
		on = { "way", "mount", "tp", "gear" } },
	{ key = "collector", name = "Collector", text = "Mounts, pets, achievements and the places to get them.",
		on = { "way", "mount", "tp", "flight", "collect", "ach", "pets", "wq", "moments", "next", "recent" } },
	{ key = "crafter", name = "Crafter", text = "Professions, alts and gold.",
		on = { "way", "mount", "tp", "gear", "alts", "value", "weekly", "next", "recent" } },
	{ key = "everything", name = "Everything", text = "All of Tomte, as it comes.", all = true },
}

function ns.Setup_Preset(key)
	for _, preset in ipairs(ns.SETUP_PRESETS) do
		if preset.key == key then
			return preset
		end
	end
	return nil
end

function ns.Setup_Plan(key, modules)
	local preset = ns.Setup_Preset(key)
	if not preset then
		return nil, "unknown preset"
	end
	if preset.all then
		return { clear = true }
	end
	local on = {}
	for _, k in ipairs(ns.SETUP_BASE) do
		on[k] = true
	end
	for _, k in ipairs(preset.on) do
		on[k] = true
	end
	local enabled = {}
	for _, module in ipairs(modules) do
		if not module.alwaysOn then
			enabled[module.key] = on[module.key] == true
		end
	end
	return { enabled = enabled }
end

function ns.Setup_OnNames(key, modules)
	local plan = ns.Setup_Plan(key, modules)
	local names = {}
	if not plan then
		return names
	end
	for _, module in ipairs(modules) do
		if not module.alwaysOn then
			local on
			if plan.clear then
				on = module.enabledByDefault == true
			else
				on = plan.enabled[module.key]
			end
			if on then
				names[#names + 1] = module.name
			end
		end
	end
	return names
end

function ns.Setup_Matches(key, modules)
	local plan = ns.Setup_Plan(key, modules)
	if not plan then
		return false
	end
	for _, module in ipairs(modules) do
		if not module.alwaysOn then
			local want
			if plan.clear then
				want = module.enabledByDefault == true
			else
				want = plan.enabled[module.key]
			end
			if ns.ModuleEnabled(module) ~= want then
				return false
			end
		end
	end
	return true
end

function ns.Setup_Apply(db, plan, modules)
	if plan.clear then
		for k in pairs(db.enabled) do
			db.enabled[k] = nil
		end
	else
		for k, v in pairs(plan.enabled) do
			db.enabled[k] = v
		end
	end
	for _, module in ipairs(modules) do
		ns.RefreshModule(module)
	end
end

function ns.Setup_MarkFresh(db)
	db.setup = { state = "pending" }
end

-- Settings migration 2 (Core.lua): saved variables from before the picker existed are an existing user's.
function ns.Setup_Migrate(db)
	if type(db.setup) ~= "table" then
		db.setup = {}
	end
	if db.setup.state == nil then
		db.setup.state = "done"
		db.setup.note = true
	end
end
```

- [ ] **Step 4: Add `Core/Setup.lua` to `Tomte.toc` after `Core/Modules.lua`.**
- [ ] **Step 5: Run** `lua Tomte/tests/test_setup.lua` → all ok. Run `lua Tomte/tests/test_modules.lua` → all ok.

### Task 2: Settings profiles, pure part (`Core/Profile.lua`)

**Files:**
- Create: `Core/Profile.lua`
- Modify: `Core/Modules.lua` (make `IsCollection` public as `ns.IsCollection`; `ResetModuleSettings` uses it)
- Modify: `Modules/Alts/Alts.lua` (`noShare = { "filterChar", "filterFor" }`), `Modules/Gear/Gear.lua`
  (`noShare = { "sheetOpen" }`), `Modules/Moments/Moments.lua` (`noShare = { "previewKind" }`),
  `Modules/NextUp/NextUp.lua` (`shareMaps = { sources = "boolean", priority = "number" }`)
- Test: `tests/test_profile.lua`

**Interfaces:**
- Consumes: `ns.IsCollection(v)`, `ns.modules`, module fields `defaults`, `keep`, `noShare`, `shareMaps`,
  `options` (`{ type, key, label, min, max, choices }`), `alwaysOn`, `enabledByDefault`.
- Produces:
  - Constants: `ns.PROFILE_VERSION = 1`, `ns.PROFILE_MAX_TEXT = 20000`, `ns.PROFILE_MAX_DATA = 262144`,
    `ns.PROFILE_MAX_ENTRIES = 2000`, `ns.PROFILE_MAX_STRING = 200`.
  - `ns.Profile_Schema(module)` → `{ [path] = "boolean"|"number"|"string" }`; map entries as `"<name>.*"`.
  - `ns.Profile_Get(tbl, path)`, `ns.Profile_Set(tbl, path, value)` (creates missing tables).
  - `ns.Profile_Collect(db, modules, version)` → payload `{ v, from, enabled, settings }`.
  - `ns.Profile_Check(payload, modules, db)` → `result | nil, err`, where `result = { groups = { { key, name, rows
    = { { path, label, old, new } } } }, changes = n, skipped = n }`; the module on/off group has key `"_enabled"`
    and name `"Modules on/off"` and comes first.
  - `ns.Profile_Apply(db, result, chosen)` → number written; `chosen[groupKey] = true` for ticked groups.
  - `ns.Profile_Encode(payload, codec)` → `"Tomte1:" .. codec.encode(payload)` or `nil, err`.
  - `ns.Profile_Decode(text, codec)` → `payload | nil, err`. Errors (exact text, shown to the user):
    `"Paste a Tomte settings string first."`, `"Too long to be a Tomte settings string."`,
    `"That's not a Tomte settings string."`, `"Made by a newer Tomte. Update Tomte first."`,
    `"The string is damaged. Copy it again."`.
  - `ns.Profile_ValueText(v)` → `"on"`/`"off"` for booleans, numbers to at most 2 decimals, strings in quotes.
  - `codec = { encode = function(payload) -> string|nil, decode = function(string) -> table|nil }` (both may
    raise; `Profile_Encode`/`Decode` call them in `pcall`).

Schema rules (from the spec): walk `module.defaults`; skip keys in `module.keep` (top level), skip keys named
`collapsed` or `view` at any depth, skip any table that has a `point` key, skip `module.noShare` paths (exact path or
path prefix + `.`), skip collections (`ns.IsCollection`), recurse into other tables, record leaves by `type(v)`. Then
add `name .. ".*" = type` for each `shareMaps` entry. Map keys must match `^[%w_%-]+$` and be at most 64 characters.

- [ ] **Step 1: Write the failing tests** (`tests/test_profile.lua`, loads `Core/Modules.lua` and `Core/Profile.lua`)

```lua
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
	local db = { enabled = {} }
	for _, m in ipairs(ns.modules) do
		db[m.key] = ns.MergeDefaults(m.defaults or {}, {})
	end
	return db
end

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

test("a dotted default key raises in Profile_Schema", function()
	local ok = pcall(ns.Profile_Schema, { key = "x", defaults = { ["a.b"] = 1 } })
	eq(ok, false, "raises")
end)

test("collect writes every shareable value and the full module on/off state", function()
	local db = Modules()
	db.enabled.mount = false
	db.next.sources.nextrare = false
	local payload = ns.Profile_Collect(db, ns.modules, "1.5.0")
	eq(payload.v, 1, "v")
	eq(payload.from, "1.5.0", "from")
	eq(payload.enabled.mount, false, "mount off")
	eq(payload.enabled.alts, true, "alts default on")
	eq(payload.enabled.window, nil, "alwaysOn left out")
	eq(payload.settings.mount.preferGround, true, "unchanged values too")
	eq(payload.settings.next["sources.nextrare"], false, "map entry")
	eq(payload.settings.alts.sendRules, nil, "keep left out")
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
	eq(alts.rows[1].label, "Tracker size", "label from the option")
end)

test("check reads enabled defensively", function()
	local db = Modules()
	local result = ns.Profile_Check({ v = 1, settings = {},
		enabled = { mount = false, window = false, nope = true, alts = "x" } }, ns.modules, db)
	eq(result.groups[1].key, "_enabled", "first group")
	eq(#result.groups[1].rows, 1, "only mount")
	eq(result.skipped, 3, "window, nope, alts")
end)

test("check refuses non-tables and other versions", function()
	local db = Modules()
	eq(select(2, ns.Profile_Check("x", ns.modules, db)), "That's not a Tomte settings string.", "string")
	eq(select(2, ns.Profile_Check({ v = 2 }, ns.modules, db)), "Made by a newer Tomte. Update Tomte first.", "v2")
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
		encode = function(t) stored = t return "QUJD" end,
		decode = function(s) assert(s == "QUJD") return stored end,
	}
	local text = ns.Profile_Encode({ v = 1, settings = {} }, codec)
	eq(text, "Tomte1:QUJD", "text")
	eq(ns.Profile_Decode(text, codec).v, 1, "decoded")
end)

test("decode strips fences and whitespace", function()
	local codec = { encode = function() return "" end, decode = function(s) assert(s == "QUJD") return { v = 1 } end }
	eq(ns.Profile_Decode("```\nTomte1:QU\n JD\n```", codec).v, 1, "fenced")
	eq(ns.Profile_Decode("  Tomte1:QUJD  ", codec).v, 1, "spaces")
end)

test("decode errors", function()
	local boom = { decode = function() error("bad cbor") end }
	local none = { decode = function() return nil end }
	eq(select(2, ns.Profile_Decode("", boom)), "Paste a Tomte settings string first.", "empty")
	eq(select(2, ns.Profile_Decode("!WA:2!abc", boom)), "That's not a Tomte settings string.", "WeakAuras")
	eq(select(2, ns.Profile_Decode("Tomte2:abc", boom)), "Made by a newer Tomte. Update Tomte first.", "newer")
	eq(select(2, ns.Profile_Decode("Tomte1:abc", boom)), "The string is damaged. Copy it again.", "raises")
	eq(select(2, ns.Profile_Decode("Tomte1:abc", none)), "The string is damaged. Copy it again.", "nil")
	eq(select(2, ns.Profile_Decode("Tomte1:" .. ("A"):rep(ns.PROFILE_MAX_TEXT), boom)),
		"Too long to be a Tomte settings string.", "long")
end)

test("value text", function()
	eq(ns.Profile_ValueText(true), "on", "true")
	eq(ns.Profile_ValueText(0.957), "0.96", "number")
	eq(ns.Profile_ValueText(5), "5", "whole number")
	eq(ns.Profile_ValueText("void"), "\"void\"", "string")
end)
```

- [ ] **Step 2: Run** `lua Tomte/tests/test_profile.lua` → fails (file missing).
- [ ] **Step 3: Implement `Core/Profile.lua`.** Key parts:

```lua
local addonName, ns = ...

-- Settings profiles: what a setting is (the same line Reset draws), collecting them, and checking a string from
-- someone else before anything is written. Pure: the C_EncodingUtil codec is passed in (Panel/Share.lua).

ns.PROFILE_VERSION = 1
ns.PROFILE_MAX_TEXT = 20000
ns.PROFILE_MAX_DATA = 262144 -- decompressed bytes, checked by the codec
ns.PROFILE_MAX_ENTRIES = 2000
ns.PROFILE_MAX_STRING = 200
local UI_STATE = { collapsed = true, view = true }
local MAP_KEY = "^[%w_%-]+$"

local function Listed(list, path)
	for _, p in ipairs(list or {}) do
		if path == p or path:sub(1, #p + 1) == p .. "." then
			return true
		end
	end
	return false
end

local function Walk(module, src, prefix, schema, keep)
	for k, v in pairs(src) do
		assert(type(k) ~= "string" or not k:find(".", 1, true), "default keys can't contain a dot: " .. tostring(k))
		local path = prefix .. tostring(k)
		local skip = UI_STATE[k] or (prefix == "" and keep[k]) or Listed(module.noShare, path)
		if not skip then
			if type(v) == "table" then
				if v.point == nil and not ns.IsCollection(v) then
					Walk(module, v, path .. ".", schema, keep)
				end
			else
				schema[path] = type(v)
			end
		end
	end
end

function ns.Profile_Schema(module)
	local schema, keep = {}, {}
	for _, k in ipairs(module.keep or {}) do
		keep[k] = true
	end
	Walk(module, module.defaults or {}, "", schema, keep)
	for name, t in pairs(module.shareMaps or {}) do
		schema[name .. ".*"] = t
	end
	return schema
end
```

`Profile_Check` per value: find the schema type (exact path, else `"<parent>.*"` with the last segment matching
`MAP_KEY` and at most 64 characters); compare `type(value)`; numbers: `value ~= value` or `value == math.huge` or
`value == -math.huge` → skip; option lookup by `spec.key == path`: slider → clamp to `min`/`max`, dropdown → value
must be in `choices` (call it in `pcall` when it's a function; a failing call skips the value); strings longer than
`PROFILE_MAX_STRING` or containing `|` → skip. A row is added only when the checked value differs from
`ns.Profile_Get(db[module.key], path)`. Count every entry read (settings and enabled); stop at
`PROFILE_MAX_ENTRIES`. Unknown module keys count every entry inside them as skipped (up to the cap). Group order:
`_enabled` first, then modules in registration order; rows sorted by path.

`Profile_Decode`: `text = text:gsub("`", ""):gsub("%s+", "")`; empty → first error; `#text > PROFILE_MAX_TEXT` →
too long; `text:match("^Tomte(%d+):(.+)$")`, no match → not Tomte; `tonumber(n) > PROFILE_VERSION` → newer;
`pcall(codec.decode, body)`, not ok or not a table → damaged.

- [ ] **Step 4: In `Core/Modules.lua`,** rename the local `IsCollection` to `ns.IsCollection` (keep it recursive)
  and use it in `ResetModuleSettings`. Add the `noShare` / `shareMaps` fields to Alts, Gear, Moments and Next up.
  Add `Core/Profile.lua` to the TOC after `Core/Setup.lua`.
- [ ] **Step 5: Run** `lua Tomte/tests/test_profile.lua` and `lua Tomte/tests/test_modules.lua` → all ok.

The real modules' defaults are checked for dotted keys in game by `/tomte profile selftest` (Task 6), which builds
every schema.

### Task 3: Bug report, pure part (`Core/BugReport.lua`, `Core/BugFiles.lua`)

**Files:**
- Create: `Core/BugReport.lua`, `Core/BugFiles.lua`
- Test: `tests/test_bugreport.lua`

**Interfaces:**
- Produces:
  - `ns.BUG_FILES = { "Core/Theme.lua", ... }`: every `.lua` line of `Tomte.toc`, in TOC order, forward slashes.
  - `ns.BUG_MAX_SHOWN = 3`, `ns.BUG_MAX_SAVED = 5`, `ns.BUG_STACK_LINES = 12`, `ns.BUG_MAX_MESSAGE = 500`.
  - `ns.Bug_IsTomte(message, stack, files)` → `isTomte, stackOnly`.
  - `ns.Bug_Normalize(raw, current)` → `{ message, stack, locals, count, time, when, current }`. `raw` may be a
    BugGrabber object (`counter`, numeric `time`), a ScriptErrorsFrame entry (`count`, string `time`) or a saved
    entry (`count`, numeric `time`). Non-string message → `"(unreadable)"`; secret → `"(hidden by the game: secret
    value)"`; same for stack and locals (secret/odd → nil).
  - `ns.Bug_Collect(lists, files, max)` → Tomte errors from `lists` (each already normalized and newest first,
    concatenated in the given order), deduplicated by message (counts added, first one kept), at most `max`.
  - `ns.Bug_StackHead(stack, n)` → first `n` lines.
  - `ns.Bug_Remember(buffer, errors, version, now, max)`: `errors` is newest first, so walk it from the end (oldest
    first) and insert at the front, leaving the newest at index 1. An existing message gets `count` added,
    `time = now`, moves to the front; new ones are inserted at the front with `message` cut to
    `BUG_MAX_MESSAGE`, `stack` cut to `BUG_STACK_LINES`, no locals; trimmed to `max`.
  - `ns.Bug_ReportText(info)` → the text block in the spec. `info = { version, build, interface, locale, theme,
    level, class, spec, specID, content, preset, on = {keys}, off = {keys}, blocked = { { key, reason } }, uses =
    { { name, version | false } }, catcher, others = {names}, errors = {normalized}, total = n, full = bool,
    profile = string | nil }`.

`Bug_IsTomte` rules: replace `\` with `/` in both strings first. True when the message or stack contains
`AddOns/Tomte/` (plain find). Otherwise, for each `...<tail>.lua` in the message start or in any stack line
(pattern `%.%.%.([^%s%[%]\"':]+%.lua)`): true when `#tail >= 12` and `("Interface/AddOns/Tomte/" .. file)` ends with
`tail` for some file in `files`. Otherwise true when the message contains `AddOn 'Tomte'`. `stackOnly` is true when
the match was only in the stack.

- [ ] **Step 1: Generate `Core/BugFiles.lua`** from the TOC (run from `AddOns`):

```sh
lua -e 'local t={} for l in io.lines("Tomte/Tomte.toc") do local f=l:match("^([%w_/\\]+%.lua)%s*$") if f then t[#t+1]="\t\""..f:gsub("\\","/").."\"," end end print("local addonName, ns = ...\n\n-- Tomte'"'"'s own Lua files, from the TOC (tests/test_bugreport.lua checks they match). The bug report uses them to\n-- recognise an error path Lua shortened to \"...<end of path>\".\nns.BUG_FILES = {\n"..table.concat(t,"\n").."\n}")' > Tomte/Core/BugFiles.lua
```

Then add `Core/BugReport.lua`, `Core/BugFiles.lua` to the TOC after `Core/Profile.lua`, and run the command again so
both new files are in the list. Check the file opens with `local addonName, ns = ...` and tabs.

- [ ] **Step 2: Write the failing tests** (`tests/test_bugreport.lua`, loads `Core/BugFiles.lua` and
  `Core/BugReport.lua`)

```lua
local SECRET = "<<secret>>"
issecretvalue = function(v) return v == SECRET end

test("BugFiles matches the TOC", function()
	local toc = {}
	for line in io.lines("Tomte/Tomte.toc") do
		local f = line:match("^([%w_/\\]+%.lua)%s*$")
		if f then
			toc[#toc + 1] = f:gsub("\\", "/")
		end
	end
	eq(#ns.BUG_FILES, #toc, "count (re-run the command in the plan's Task 3 Step 1)")
	for i, f in ipairs(toc) do
		eq(ns.BUG_FILES[i], f, "file " .. i)
	end
end)

test("IsTomte: full paths, backslashes and blocked calls", function()
	local F = ns.BUG_FILES
	eq(ns.Bug_IsTomte("Interface/AddOns/Tomte/Core/Core.lua:12: boom", nil, F), true, "full")
	eq(ns.Bug_IsTomte("Interface\\AddOns\\Tomte\\Core\\Core.lua:12: boom", nil, F), true, "backslash")
	eq(ns.Bug_IsTomte("[ADDON_ACTION_BLOCKED] AddOn 'Tomte' tried to call the protected function 'X'.", nil, F),
		true, "blocked")
end)

test("IsTomte: shortened paths", function()
	local F = ns.BUG_FILES
	eq(ns.Bug_IsTomte("...ules/Achievements/Achievements.lua:12: boom", nil, F), true, "tail of a Tomte file")
	eq(ns.Bug_IsTomte("...ules/SomethingElse/Other.lua:12: boom", nil, F), false, "tail of another file")
	eq(ns.Bug_IsTomte("...ts.lua:1: x", nil, F), false, "tail too short to tell")
end)

test("IsTomte: other addons and look-alike names", function()
	local F = ns.BUG_FILES
	eq(ns.Bug_IsTomte("Interface/AddOns/TomteFoo/a.lua:1: x", nil, F), false, "TomteFoo")
	eq(ns.Bug_IsTomte("Interface/AddOns/DBM-Core/DBM-Core.lua:1: x", nil, F), false, "DBM")
	local ok, stackOnly = ns.Bug_IsTomte("Interface/AddOns/Baganator/x.lua:5: y",
		"[Interface/AddOns/Baganator/x.lua]:5: in function\n[Interface/AddOns/Tomte/Modules/Gear/Gear.lua]:40: in function", F)
	eq(ok, true, "Tomte in the stack")
	eq(stackOnly, true, "stack only")
end)

test("normalize survives odd messages", function()
	eq(ns.Bug_Normalize({ message = { "x" } }, true).message, "(unreadable)", "table")
	eq(ns.Bug_Normalize({}, true).message, "(unreadable)", "nil")
	eq(ns.Bug_Normalize({ message = SECRET, stack = SECRET }, true).message,
		"(hidden by the game: secret value)", "secret")
	eq(ns.Bug_Normalize({ message = SECRET, stack = SECRET }, true).stack, nil, "secret stack")
	local bg = ns.Bug_Normalize({ message = "m", counter = 3, time = 100 }, false)
	eq(bg.count, 3, "BugGrabber counter")
	eq(bg.time, 100, "numeric time")
	local blz = ns.Bug_Normalize({ message = "m", count = 2, time = "Sat Oct 10 21:14:00 2026" }, true)
	eq(blz.when, "Sat Oct 10 21:14:00 2026", "string time kept as text")
end)

test("collect filters, dedupes and caps", function()
	local function E(msg, count)
		return ns.Bug_Normalize({ message = msg, count = count or 1 }, true)
	end
	local list = ns.Bug_Collect({
		{ E("Interface/AddOns/Tomte/Core/Core.lua:1: a", 2), E("Interface/AddOns/DBM-Core/x.lua:1: b") },
		{ E("Interface/AddOns/Tomte/Core/Core.lua:1: a", 1), E("Interface/AddOns/Tomte/Core/Core.lua:2: c"),
			E("Interface/AddOns/Tomte/Core/Core.lua:3: d"), E("Interface/AddOns/Tomte/Core/Core.lua:4: e") },
	}, ns.BUG_FILES, 3)
	eq(#list, 3, "capped")
	eq(list[1].count, 3, "counts added")
	eq(list[2].message, "Interface/AddOns/Tomte/Core/Core.lua:2: c", "order kept")
end)

test("remember keeps a small newest-first ring", function()
	local buffer = {}
	local errs = {}
	for i = 1, 7 do
		errs[i] = ns.Bug_Normalize({ message = "m" .. i, stack = ("line\n"):rep(30), count = 1 }, true)
	end
	ns.Bug_Remember(buffer, errs, "1.5.0", 1000, 5)
	eq(#buffer, 5, "capped")
	ns.Bug_Remember(buffer, { ns.Bug_Normalize({ message = "m3", count = 2 }, true) }, "1.5.0", 2000, 5)
	eq(buffer[1].message, "m3", "moved to the front")
	eq(buffer[1].count, 3, "count added")
	eq(buffer[1].time, 2000, "time")
	local _, lines = buffer[2].stack:gsub("\n", "")
	eq(lines < ns.BUG_STACK_LINES, true, "stack cut")
	eq(buffer[2].locals, nil, "no locals")
end)

test("report text has the key lines and no locals unless full", function()
	local info = { version = "1.5.0", build = "12.1.0.69933", interface = 120100, locale = "enUS",
		theme = "cartographer", level = 80, class = "Hunter", spec = "Marksmanship", specID = 254,
		content = "The War Within", preset = "collector", on = { "pets", "minimap" }, off = { "afk" },
		blocked = { { "rogue", "not a Rogue" } }, uses = { { "Baganator", "1.2.3" }, { "Auctionator", false } },
		catcher = "BugSack (BugGrabber v12.1.0)", others = { "DBM-Core" }, total = 1,
		errors = { ns.Bug_Normalize({ message = "Interface/AddOns/Tomte/Core/Core.lua:1: a", locals = "x = 1",
			count = 2, time = "now" }, true) } }
	local text = ns.Bug_ReportText(info)
	local function has(s)
		eq(text:find(s, 1, true) ~= nil, true, s)
	end
	has("Tomte 1.5.0 | WoW 12.1.0.69933 (120100) | enUS | theme cartographer")
	has("Character: level 80 Hunter (Marksmanship, spec 254) | content The War Within")
	has("Modules on (2): pets, minimap")
	has("Blocked (1): rogue (not a Rogue)")
	has("Uses: Baganator 1.2.3, Auctionator not loaded")
	has("Errors from Tomte (newest first, 1 of 1):")
	has("1) x2")
	eq(text:find("x = 1", 1, true), nil, "no locals")
	info.full = true
	info.profile = "Tomte1:QUJD"
	text = ns.Bug_ReportText(info)
	has("x = 1")
	has("Tomte1:QUJD")
end)

test("report text without errors says where to get them", function()
	local text = ns.Bug_ReportText({ version = "1", on = {}, off = {}, blocked = {}, uses = {}, others = {},
		errors = {}, total = 0, catcher = nil })
	eq(text:find("No error list available. Install BugSack to catch errors.", 1, true) ~= nil, true, "hint")
end)
```

- [ ] **Step 3: Run** `lua Tomte/tests/test_bugreport.lua` → fails (functions missing).
- [ ] **Step 4: Implement `Core/BugReport.lua`** to the interfaces above. `Bug_Normalize` reads `issecretvalue` at
  call time: `local secret = issecretvalue and issecretvalue(v)`. `when` is `date`-free: a string `time` is kept as
  text; a numeric time is left for the caller to format (`Panel/Bug.lua` fills `when` with
  `date("%Y-%m-%d %H:%M", time)` before `Bug_ReportText`). Every `info` field may be nil (print `?`). Report: "Errors from Tomte"
  when `catcher` or errors exist; with no `catcher` and no errors, the "No error list available..." line. Locals and `profile` only when
  `info.full`.
- [ ] **Step 5: Run** the test → all ok.

### Task 4: Core wiring (`Core/Core.lua`)

**Files:** Modify `Core/Core.lua`.

**Interfaces:**
- Consumes: `ns.Setup_MarkFresh`, `ns.Setup_Migrate` (Task 1). Later tasks provide `ns.SetupUI_Show()`,
  `ns.BugUI_Show(mode)`, `ns.BugUI_Clear()`, `ns.BugUI_SelfTest()`, `ns.ShareUI_Export()`, `ns.ShareUI_Import()`,
  `ns.ShareUI_Undo()`, `ns.ShareUI_SelfTest()`.
- Produces: `CORE_DEFAULTS.setup = {}`, `CORE_DEFAULTS.bugs = {}`; `TomteDB.profileBackup` (no default, nil until
  an import).

- [ ] **Step 1:** In `f:ADDON_LOADED`, before `ns.RunMigrations`:

```lua
	local fresh = TomteDB == nil
	local db = TomteDB or {}
	if fresh then
		ns.Setup_MarkFresh(db) -- before the migrations: migration 2 marks only older saved variables as done
	end
```

- [ ] **Step 2:** Append migration 2 to `MIGRATIONS`:

```lua
	-- 2: the first-run picker (1.5): saved variables from before it are an existing user's; no picker for them,
	-- one chat line instead (Panel/Setup.lua).
	function(db)
		ns.Setup_Migrate(db)
	end,
```

- [ ] **Step 3:** Add `setup = {}` and `bugs = {}` to `CORE_DEFAULTS` with comments ("first-run picker state" /
  "Tomte's last Lua errors, only without BugGrabber (Panel/Bug.lua)"). Check `ns.ResetAllSettings` leaves them
  (it only rebuilds `enabled`, `panel`, `toast`).
- [ ] **Step 4:** Slash commands, in `SlashCmdList.TOMTE` before the module lookup:

```lua
	elseif word == "setup" then
		ns.SetupUI_Show()
	elseif word == "bug" then
		if rest == "clear" then
			ns.BugUI_Clear()
		elseif rest == "selftest" then
			ns.BugUI_SelfTest()
		else
			ns.BugUI_Show(rest == "full" and "full" or nil)
		end
	elseif word == "profile" then
		if rest == "export" then
			ns.ShareUI_Export()
		elseif rest == "import" then
			ns.ShareUI_Import()
		elseif rest == "undo" then
			ns.ShareUI_Undo()
		elseif rest == "selftest" then
			ns.ShareUI_SelfTest()
		else
			PrintCommand("/tomte profile export", "your settings as a string to give a friend")
			PrintCommand("/tomte profile import", "paste a friend's string, see what changes, then import")
			PrintCommand("/tomte profile undo", "go back to your settings from before the last import")
		end
```

  And in `PrintHelp`, after `/tomte data`: `/tomte setup` ("pick what Tomte turns on: Collector, Crafter,
  Minimal or Everything"), `/tomte bug` ("a bug report to copy: versions, modules and Tomte's last errors";
  `full` adds error details and your settings), `/tomte profile` ("share settings with a friend").
- [ ] **Step 5:** Run all tests: `for t in Tomte/tests/test_*.lua; do lua "$t"; done` → all ok.

### Task 5: Shared text dialog (`Panel/Dialog.lua`)

**Files:**
- Create: `Panel/Dialog.lua` (TOC after `Panel/Widgets.lua`)
- Modify: `Modules/Pets/Card.lua` (remove `BuildPopup`, `ns.PetsPopup_Show` and the `popup` local),
  `Modules/Pets/Page.lua` (2 calls), `Modules/Pets/Card.lua:135` (1 call)

**Interfaces:**
- Produces: `ns.Dialog_Show(spec)`, `ns.Dialog_Hide()`. `spec = { title, hint, text, readOnly, height, saveText =
  "Save", onSave(text) -> error text | nil }`. Same behavior as `PetsPopup_Show` today; the frame is named
  `TomteDialog` and is in `UISpecialFrames`. `saveText` sets the save button's text (import uses "Check").

- [ ] **Step 1:** Move `BuildPopup` and `PetsPopup_Show` from `Modules/Pets/Card.lua` into `Panel/Dialog.lua`
  unchanged except: frame name `TomteDialog`, file header comment ("one text dialog for copying and pasting:
  links, scripts, bug reports, settings strings"), `popup.save.label:SetText(spec.saveText or "Save")` and its width
  like `Setup.button` in `Panel/Options.lua`.
- [ ] **Step 2:** Replace the three `ns.PetsPopup_Show(` calls with `ns.Dialog_Show(`. `grep -rn PetsPopup` → no
  hits.
- [ ] **Step 3:** Run `lua Tomte/tests/test_theme.lua` and `lua Tomte/tests/test_pets.lua` → all ok.
- [ ] **Step 4 (in game, with Task 9):** Pet Battles page → a tamer's links and a team's script still open the
  dialog; Esc closes it.

### Task 6: Share UI (`Panel/Share.lua`)

**Files:** Create `Panel/Share.lua` (TOC after `Panel/Window.lua`).

**Interfaces:**
- Consumes: Task 2 (`Profile_*`), Task 5 (`Dialog_Show`), `ns.db`, `ns.modules`, `ns.VERSION`, `UI`.
- Produces: `ns.ShareUI_Export()`, `ns.ShareUI_Import()`, `ns.ShareUI_Undo()`, `ns.ShareUI_HasBackup()`,
  `ns.ShareUI_SelfTest()`, `ns.ShareUI_ExportText()` (for the bug report's `full` mode; nil on failure).

- [ ] **Step 1: The codec.**

```lua
-- C_EncodingUtil (11.1.5+, warcraft.wiki.gg; EncodingUtilDocumentation.lua): CBOR, then raw Deflate, then Base64.
-- Every call may return nothing on bad input; Profile_Decode calls decode in pcall.
local codec = {
	encode = function(payload)
		local cbor = C_EncodingUtil.SerializeCBOR(payload)
		local packed = cbor and C_EncodingUtil.CompressString(cbor, Enum.CompressionMethod.Deflate)
		return packed and C_EncodingUtil.EncodeBase64(packed, Enum.Base64Variant.Standard)
	end,
	decode = function(body)
		local packed = C_EncodingUtil.DecodeBase64(body, Enum.Base64Variant.Standard)
		local cbor = packed and C_EncodingUtil.DecompressString(packed, Enum.CompressionMethod.Deflate)
		if not cbor or #cbor > ns.PROFILE_MAX_DATA then
			return nil
		end
		return C_EncodingUtil.DeserializeCBOR(cbor)
	end,
}
```

- [ ] **Step 2: Export.** `ns.ShareUI_ExportText()` = `ns.Profile_Encode(ns.Profile_Collect(ns.db, ns.modules,
  ns.VERSION), codec)`. `ShareUI_Export` shows it read-only with title "Your Tomte settings" and hint "Ctrl+C, then
  paste it to a friend. It has your settings, not your data (no characters, history or lists)." On failure:
  `ns.Print("couldn't build the string: " .. err)`.
- [ ] **Step 3: Import.** `ShareUI_Import` opens the dialog editable, empty, title "Import Tomte settings", hint
  "Paste a string from /tomte profile export. Nothing changes until you confirm.", `saveText = "Check"`, `onSave` =
  decode → check → on error return the error text (the dialog shows it); with no changes return "Your settings
  already match."; otherwise open the preview and return nil.
- [ ] **Step 4: Preview window** (`TomteImportPreview`, `UI.Panel`, DIALOG strata, 520×460, Esc closes):
  - title "What changes", summary line "`changes` changes in `n` groups. `skipped` settings skipped (this Tomte
    doesn't have them, or their values didn't fit)." (`textMuted`);
  - a `UI.Scroll` with, per group, a header row (`UI.Checkbox`, ticked, + group name + row count, `heading`
    role) and rows `label: old → new` (`text` role, values from `ns.Profile_ValueText`, old in `textMuted`);
  - buttons **Import and reload** and **Cancel**. Import: refuse in combat (`ns.Print("Import after combat.")`);
    save `ns.db.profileBackup = { at = time(), text = ns.ShareUI_ExportText() }` first; then
    `ns.Profile_Apply(ns.db, result, chosen)`; then `C_UI.Reload()` (the click is the hardware event, as with
    Reset). No ticked group → the button is disabled.
- [ ] **Step 5: Undo.** `ShareUI_Undo`: no backup → `ns.Print("nothing to undo.")`. Otherwise decode the backup text,
  check, and open the same preview titled "Undo last import (from <date>)". After the reload the backup stays until
  the next import, so undoing twice is harmless.
- [ ] **Step 6: Self-test** (hidden): builds every module's schema (`pcall`, reports the module whose defaults have a
  dotted key), encodes the current settings, decodes and checks them against yourself; prints
  "profile selftest ok: <n> settings, <bytes> characters, 0 changes" or the failing step. Zero changes is the pass
  condition.

### Task 7: Bug report UI and error sources (`Panel/Bug.lua`)

**Files:** Create `Panel/Bug.lua` (TOC after `Panel/Share.lua`).

**Interfaces:**
- Consumes: Task 3 (`Bug_*`, `BUG_FILES`), Task 5, Task 6 (`ShareUI_ExportText`), `ns.ModuleEnabled`,
  `ns.ModuleBlockedReason`, `ns.ContentExpansion`, `ns.ExpansionName`, `ns.Theme.name`, `ns.db.setup.preset`.
- Produces: `ns.BugUI_Show(mode)`, `ns.BugUI_Clear()`, `ns.BugUI_SelfTest()`.

- [ ] **Step 1: Error sources**, each in `pcall`, each returning a newest-first list of `ns.Bug_Normalize`d entries:
  - `FromBugGrabber()`: `local bg = BugGrabber`; needs `type(bg) == "table"` and `bg.GetDB`; `bg:GetDB()` is oldest
    first, so walk it backwards; `current = (err.session == bg:GetSessionId())`; stop after 200 entries.
  - `FromBlizzard()`: `ScriptErrorsFrame` and `type(ScriptErrorsFrame.errorData) == "table"`; walk backwards;
    `current = true`.
  - `FromSaved()`: `ns.db.bugs` as stored (already newest first), `current = false`.
  - Order: BugGrabber alone when it's loaded; otherwise Blizzard then saved. `catcher` text: "BugSack (BugGrabber
    <version>)" / "BugGrabber <version>" / "Blizzard's error list (this session) + Tomte's saved list" / nil.
  - Fill `when` for numeric times with `date("%Y-%m-%d %H:%M", t)`, plus ", this session" when `current`.
- [ ] **Step 2: Info.** `GetBuildInfo()` (version, build, _, interface), `GetLocale()`, `UnitLevel("player")`,
  `UnitClass("player")` (localized name), `C_SpecializationInfo.GetSpecialization()` →
  `C_SpecializationInfo.GetSpecializationInfo(index)` (id, name; nil index → "no spec"),
  `ns.ExpansionName(ns.ContentExpansion())`, `ns.Theme.name`, `ns.db.setup.preset or "none"`. Modules: `on`/`off`
  from `ns.ModuleEnabled` (skip `alwaysOn`), `blocked` from `ns.ModuleBlockedReason`. Uses: the set of `addon`
  names from every module's `uses` and `conflicts`, plus `BugSack`, `!BugGrabber`, `TomTom`, `Baganator`,
  `Syndicator`, `Auctionator`, `TradeSkillMaster`, `MountJournalEnhanced`; sorted; each with
  `C_AddOns.GetAddOnMetadata(name, "Version")` when `C_AddOns.IsAddOnLoaded(name)`, else `false`. Others: for `i =
  1, C_AddOns.GetNumAddOns()`, `C_AddOns.GetAddOnInfo(i)` name, loaded, `security == "INSECURE"`, not Tomte and not
  in Uses; sorted. Each of these groups is filled in its own `pcall`; a failure becomes the line
  "(could not read: <err>)".
- [ ] **Step 3: Show.** `ns.Dialog_Show({ title = "Tomte bug report", readOnly = true, height = 420, text =
  ns.Bug_ReportText(info), hint = "Ctrl+C, then paste it to Tomte's author or in a GitHub issue
  (github.com/tomte55/Tomte/issues). Read it first: it's sent nowhere by itself." })`. `mode == "full"` sets
  `info.full` and `info.profile = ns.ShareUI_ExportText()`.
- [ ] **Step 4: Ring buffer.** Own event frame, `PLAYER_LOGOUT`: when BugGrabber isn't loaded, take
  `FromBlizzard()`, keep Tomte's (`ns.Bug_IsTomte`), and `ns.Bug_Remember(ns.db.bugs, list, ns.VERSION, time(),
  ns.BUG_MAX_SAVED)`. Wrap in `pcall` (logout must never error).
- [ ] **Step 5: Clear and self-test.** `BugUI_Clear` empties `ns.db.bugs` in place and prints "saved errors
  cleared." (BugSack's own list is BugSack's: say "BugSack keeps its own list: /bugsack reset" when it's loaded).
  `BugUI_SelfTest` calls `error("Tomte bug report self-test (not a real error)")` from this file, so the message
  carries `Panel/Bug.lua`'s path.

### Task 8: First-run picker (`Panel/Setup.lua`)

**Files:** Create `Panel/Setup.lua` (TOC after `Panel/Bug.lua`).

**Interfaces:**
- Consumes: Task 1, `ns.db.setup`, `ns.Panel_OpenModule`, `ns.AnyCinematicState`, `ns.Print`, `UI`.
- Produces: `ns.SetupUI_Show()`.

- [ ] **Step 1: Window** `TomteSetup`: `UI.Panel`, DIALOG strata, 620×440, centered, movable, `UISpecialFrames`.
  - Title "Welcome to Tomte" (`heading`, `title` font), line "Pick what you want. You can change every module later."
    (`textMuted`).
  - Four cards (2×2) as Buttons with `UI.Surface`: name (`heading`), text (`text`), "Turns on: " +
    `table.concat(ns.Setup_OnNames(key, ns.modules), ", ")` (`textMuted`, 11, wrapping), and "matches your setup
    now" (`success` role, only from `/tomte setup` when `ns.Setup_Matches`). Selected card: accent border
    (`UI.SetBorderColor(card, UI.Color("accent"))`). Default selection: `everything`.
  - Footnote (`textMuted`): "Hunter Pets, Pet Health and Rogue Poisons only wake up on that class."
  - Buttons: **Use this**, **Choose myself**, **Skip**.
- [ ] **Step 2: Actions.**
  - Use this: in combat → `ns.Print("Pick after combat.")`; else `ns.Setup_Apply(ns.db, ns.Setup_Plan(key,
    ns.modules), ns.modules)`, `ns.db.setup.state = "done"`, `ns.db.setup.preset = key`, hide,
    `ns.Print(("%s set up: %d modules on. /tomte setup to change it."):format(name, #names))`,
    `ns.Panel_Refresh()` when the window is shown.
  - Choose myself: `state = "done"`, hide, `ns.Panel_OpenModule(ns.modules[1].key)`.
  - Skip, Esc or the close button (`OnHide` while `state == "pending"`): `state = "done"` and
    `ns.Print("Tomte keeps everything on. Change it any time with /tomte setup.")`.
- [ ] **Step 3: When it shows.** Own event frame on `PLAYER_ENTERING_WORLD` (unregistered after the first):
  - `ns.db.setup.note` → print once: "Tomte " .. ns.VERSION .. ": new /tomte setup (presets), /tomte bug (bug
    report) and settings sharing in Tomte window settings." and set `note = nil`.
  - `state == "pending"` → `C_Timer.After(3, TryShow)`. `TryShow`: in combat → register `PLAYER_REGEN_ENABLED`
    and retry there; `ns.AnyCinematicState()` → `C_Timer.After(5, TryShow)`; else show.
- [ ] **Step 4:** `ns.SetupUI_Show()` from `/tomte setup`: refuse in combat with a message, otherwise show with the
  "matches" marks.

### Task 9: Settings buttons, TOC, docs, full test run

**Files:** Modify `Panel/Window.lua`, `Tomte.toc`, `README.md`, `CHANGELOG.md`, `.gitattributes` (no change: all
new files ship).

- [ ] **Step 1:** In `Panel/Window.lua` options, after "Around you shows" (appended after the AROUND loop so it ends
  the page, above the Reset rows):

```lua
local SHARE = {
	{ type = "header", label = "Setup and sharing" },
	{ type = "button", label = "Pick a preset (Collector, Crafter, Minimal, Everything)", text = "Run setup",
		onClick = function() ns.SetupUI_Show() end,
		tooltip = "Turns modules on or off to fit how you play. Settings inside modules stay." },
	{ type = "button", label = "Your settings as a string for a friend", text = "Export",
		onClick = function() ns.ShareUI_Export() end,
		tooltip = "Settings only: no characters, history, flight times or lists." },
	{ type = "button", label = "Use a friend's settings", text = "Import",
		onClick = function() ns.ShareUI_Import() end,
		tooltip = "Paste their string, see what changes, then confirm. Your UI reloads." },
	{ type = "button", label = "Back to your settings from before the last import", text = "Undo import",
		shown = function() return ns.ShareUI_HasBackup() end,
		onClick = function() ns.ShareUI_Undo() end },
	{ type = "button", label = "Something broke? A report to copy and send", text = "Bug report",
		onClick = function() ns.BugUI_Show() end,
		tooltip = "Versions, modules, other addons and Tomte's last errors. Sent nowhere by itself." },
}
for _, spec in ipairs(SHARE) do
	module.options[#module.options + 1] = spec
end
```

- [ ] **Step 2: TOC order** (check it): `Core/Modules.lua`, `Core/Setup.lua`, `Core/Profile.lua`,
  `Core/BugReport.lua`, `Core/BugFiles.lua`, `Core/EditMode.lua`, ...; `Panel/Widgets.lua`, `Panel/Dialog.lua`,
  `Panel/Options.lua`, ..., `Panel/Window.lua`, `Panel/Share.lua`, `Panel/Bug.lua`, `Panel/Setup.lua`,
  `Panel/MapTabs.lua`, .... Re-run Task 3 Step 1's command so `Core/BugFiles.lua` lists the new Panel files.
- [ ] **Step 3: README:** Install step 3 mentions the picker; a short "Reporting a bug" section (`/tomte bug`, and
  BugSack for full errors); "Sharing settings" (`/tomte profile export` / `import` / `undo`); the three commands in
  the Commands list; `/tomte version` line keeps pointing at `/tomte bug`.
- [ ] **Step 4: CHANGELOG** under Unreleased (after the in-game check): "New installs start with a short welcome:
  pick Collector, Crafter, Minimal or Everything (`/tomte setup` any time).", "`/tomte bug` makes a bug report to
  copy: versions, modules and Tomte's last errors.", "Share settings with friends: Export and Import in Tomte window
  settings, with a preview of what changes and an Undo."
- [ ] **Step 5:** From `AddOns`: `for t in Tomte/tests/test_*.lua; do lua "$t"; done` → every file "all passed",
  including `test_theme.lua`'s source scan over the new Panel files.

### Task 10: Review and in-game checklist

- [ ] One reviewer agent reads the whole diff against the spec and this plan (Global constraints and Review focus
  first). Fix its findings, re-run all tests.
- [ ] Give the user this in-game checklist:
  1. `/reload` on your own account → no picker; one chat line "Tomte 1.5..." once; a second `/reload` → no line.
  2. `/tomte setup` → the picker; "Everything" says "matches your setup now"; pick Crafter → Moments and Recap off
     in the Tomte window; `/tomte setup` → Everything again.
  3. Fresh install: log out, rename `WTF\Account\<account>\SavedVariables\Tomte.lua` to `Tomte.lua.bak`, log in →
     picker after ~3 s; Esc → chat line, everything on. Log out and put the file back.
  4. `/tomte bug selftest`, then `/tomte bug` → the self-test error is listed with "Panel/Bug.lua" in it; BugSack
     shows it too. `/tomte bug full` adds locals and a `Tomte1:` string.
  5. `/tomte profile export` → copy; change "Prefer ground mounts"; `/tomte profile import`, paste, Check → one
     row "Prefer ground mounts: off → on"; Import and reload → back on. Undo import → it shows the change back.
  6. Paste `hello` → "That's not a Tomte settings string."; cut the string in half → "The string is damaged...".
  7. `/tomte profile selftest` → "profile selftest ok ... 0 changes".
  8. BugSack: no new Tomte errors after all of this.
