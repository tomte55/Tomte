# Polish A: core services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One combat-refusal line, one "module is off" gate for commands, bindings and buttons, map tabs that open
the map's side panel themselves, Esc that closes one Tomte frame at a time, and the Core/Panel robustness fixes from
the audit.

**Architecture:** Shared helpers go in Core (`Core/Core.lua` for printing/gating, pure rules in `Core/Modules.lua`,
new pure `Core/CheckData.lua`) and Panel (`Panel/MapTabs.lua`, `Panel/Controls.lua`, pure `Panel/Layout.lua`). Module
files only change call sites. Plans B to F build on the names in "Interfaces for other plans".

**Tech Stack:** Lua 5.1 (WoW 12.1.5 retail), plain-Lua unit tests in tests/.
**Spec:** `docs/superpowers/specs/2026-10-19-tomte-polish-core-design.md`

## Global Constraints

- Files are CRLF with tabs; edit Lua with the Edit/Write tools only (sed/awk/heredocs drop CR and collapse `\\`).
- First line `local addonName, ns = ...`, then a header comment; new pure files say "pure logic (no WoW API calls;
  unit-tested in tests/test_<name>.lua)".
- Colors and fonts by theme role only (`UI.Wrap`, `UI.Color`); no `|cff` literals, numeric colors or font paths.
- No deprecated globals; nothing may error with `/console loadDeprecationFallbacks 0`.
- No bare `pcall` around our own code; `pcall` only around a game call that can legitimately fail, failure handled.
  Errors from our code go to `ns.errorHandler` (via `xpcall`).
- Migrations are append-only (`ns.MIGRATIONS`), cope with missing tables, and get a case in `tests/test_migrations.lua`.
- Cross-file names `ns.<Prefix>_<Name>`; only globals: `TomteDB`, `Tomte_*` binding/compartment functions, frame
  names that `UISpecialFrames`/bindings need (`TomteEscape`), `BINDING_NAME_*`.
- A hook (`hooksecurefunc`/`HookScript`) can't be undone: it must do nothing while its module is off.
- `SetScript("OnShow"/"OnHide")` drops hooks: `UI.CloseOnEscape` is called after a frame's own SetScript calls.
- Don't touch other addons' folders; Plumber was only read.
- Player wording for every printed line and settings label: short, sentence case, no internals.
- Commit only after the user confirmed the task in game; message `<Area>: what changed`; CHANGELOG **Unreleased**
  line in player wording per confirmed behavior change (pure moves/refactors get none).

## Review Focus

1. **Esc with a dialog over the window, in and out of combat**: one press closes only the dialog, the next the
   window; the yes/no question still takes Esc/Enter itself out of combat. No test can cover the UISpecialFrames
   path: in-game check in Task 6, including a press during combat.
2. **Alt+Z / AFK screen / flight cinematic with the Tomte window open**: the window must come back when the UI does,
   and Esc afterwards must still close it (the dummy is shown again by the frames' OnShow). In-game check in Task 6.
3. **Event bus error isolation must not change call order or arguments** (WoW's `xpcall` passes `bus, ...` on; Lua
   5.1 in CI needs the harness shim, or every bus test silently runs handlers without arguments). Test "handlers get
   their arguments through xpcall" in Task 1.
4. **The central command gate**: a blocked module (Hunter Pets on a non-hunter) must print its reason, not "turn it
   on"; `whileOff` commands and modules' `fallbackCommand`s must still run. Tests in Task 4 plus an in-game check on
   a non-hunter.
5. **Opening a map tab from code**: `OpenQuestLog` on a maximized map, with the quest-log game rule active, and
   afterwards in combat (taint): in-game check in Task 5 (open with `/tomte wq open` on a maximized map, then enter
   combat and press M; BugSack must show no ADDON_ACTION_BLOCKED).
6. **Migration 10** with an existing `window.around` table (other unticked blocks must survive): test in Task 7.

## Interfaces for other plans

Plans B to F use these names; they exist after this plan.

| Name | File | What |
| --- | --- | --- |
| `ns.Print_Combat(action)` | Core/Core.lua | Prints "Tomte: can't `<action>` in combat." `action` lower case, no period. Nothing queues. |
| `ns.Module_RequireOn(moduleOrKey) -> bool` | Core/Core.lua | true when the module is active; otherwise prints `ns.Module_OffText` and returns false. Accepts the module table or its key. |
| `ns.Module_OffText(module, blockedReason) -> text` | Core/Modules.lua (pure) | "Gathering is off. Turn it on in /tomte." or "Hunter Pets: Only for hunters." |
| `ns.Module_CommandAllowed(module, cmd) -> bool` | Core/Modules.lua (pure) | active, or `cmd.whileOff == true`. |
| command flag `whileOff = true` | module `commands` / `fallbackCommand` | The command runs while the module is off (Core's gate skips it). |
| `ns.Binding_Add(name, moduleKey, fn)` | Core/Core.lua | Registers `ns.bindings[name]`; fn runs only while the module is on, else the off line. |
| `ns.MapTabs_Open(key, mapID) -> bool` | Panel/MapTabs.lua | Opens the world map with its quest log side panel and selects the tab (combat line in combat; false when the tab isn't shown). Callers check `ns.Module_RequireOn` first. |
| `UI.CloseOnEscape(frame)` | Panel/Controls.lua | Esc closes frame, last shown first. Never add a name to `UISpecialFrames` directly; call after your own SetScript("OnShow"/"OnHide"); `UI.Dialog` does it unless `opts.escape == false`. |
| `ns.Check_ContentKind(instanceType, difficultyID)` | Core/CheckData.lua (pure) | "dungeon" / "raid" / "delve" / nil. Replaces `ns.Hunter_ContentKind` (removed). |
| `ns.Home_AroundChoices() -> { { key, name }, ... }` | Core/Modules.lua (pure) | Every around entry, Home's order. New around entries get a switch in "Around you shows" automatically; don't add per-module "show in Around you" settings. |
| `ns.PanelLayout_Visibility(options) -> "1010"` | Panel/Layout.lua (pure) | Options pages re-check `shown()` after every change; plans can rely on `shown()` updating live. |
| `ns.PanelLayout_Matches` | Panel/Layout.lua (pure) | Search now covers option `label`, `text`, `tooltip` strings. |
| Migration 10 | Core/Migrations.lua | Taken by this plan. Other plans append 11 and later. |
| `ns.NewEvents()` | Core/Events.lua | Handlers are isolated: an error in one reaches BugSack and the others still run. |
| `tests/harness.lua` | tests | Under Lua 5.1, `xpcall(f, handler, ...)` passes the extra arguments (as WoW does). |

---

### Task 1: Event bus isolates handler errors (`Core/Events.lua`)

**Files:** Modify `tests/harness.lua` (whole file, add a block after line 6), `Core/Events.lua:15-26`,
`tests/test_eventbus.lua:1-13` and add tests before `H.done()`.

**Interfaces:** Consumes `ns.errorHandler` (Core/Core.lua:11, looked up per call). Produces: bus handlers called
through `xpcall`; harness `xpcall` with arguments under Lua 5.1.

- [ ] In `tests/harness.lua`, after the comment block and `local H = { failures = 0 }`, add:

```lua
-- WoW's xpcall passes extra arguments on to the function (xpcall(fn, handler, ...)); Lua 5.1's (CI) drops them.
-- The addon's code relies on WoW's behaviour, so the tests get it too.
if _VERSION == "Lua 5.1" then
	local xpcall51 = xpcall
	xpcall = function(fn, handler, ...)
		local n, args = select("#", ...), { ... }
		return xpcall51(function()
			return fn(unpack(args, 1, n))
		end, handler)
	end
end
```

- [ ] In `tests/test_eventbus.lua` replace `local ns = {}` (line 12) with:

```lua
local reported = {}
local ns = {
	errorHandler = function(err)
		reported[#reported + 1] = tostring(err)
	end,
}
```

  and add before `H.done()`:

```lua
test("a handler that errors doesn't stop the next one", function()
	local bus, calls = ns.NewEvents(), {}
	for i = #reported, 1, -1 do
		reported[i] = nil
	end
	bus:On("a", "E", function()
		error("boom")
	end)
	bus:On("b", "E", function(self, x)
		calls[#calls + 1] = "b" .. x
	end)
	bus:Watch("a", "E")
	bus:Watch("b", "E")
	Fire(bus, "E", 1)
	eq(table.concat(calls, " "), "b1", "b still ran")
	eq(#reported, 1, "the error went to ns.errorHandler")
	assert(reported[1]:find("boom"), reported[1])
end)
test("handlers get their arguments through xpcall", function()
	local bus, got = ns.NewEvents(), {}
	bus:On("a", "E", function(self, x, y, z)
		got.self, got.x, got.y, got.z = self, x, y, z
	end)
	bus:Watch("a", "E")
	Fire(bus, "E", "one", nil, 3)
	eq(got.self, bus, "the bus first")
	eq(got.x, "one")
	eq(got.y, nil, "a nil in the middle survives")
	eq(got.z, 3)
end)
```

- [ ] Run `lua Tomte/tests/test_eventbus.lua` from the AddOns folder: "a handler that errors" FAILS (the error escapes
  `Fire`).
- [ ] In `Core/Events.lua` replace lines 20-25:

```lua
		for i = 1, #list do
			local h = list[i]
			if watching[h.owner] then
				h.fn(bus, ...)
			end
		end
```

  with:

```lua
		for i = 1, #list do
			local h = list[i]
			if watching[h.owner] then
				-- One handler's error goes to BugSack and the others still run. ns.errorHandler is looked up per
				-- call: Core.lua sets it after this file loads.
				xpcall(h.fn, ns.errorHandler, bus, ...)
			end
		end
```

  and add to the header comment (after line 6): `-- A handler that errors is reported (ns.errorHandler) and the
  next ones still run.`
- [ ] Run `lua Tomte/tests/test_eventbus.lua`: all pass. Run every test (Task 13 command): all pass (the shim must
  not break other tests).
- [ ] In game: `/reload`, play a minute (bags, map, a vendor). BugSack shows no new Tomte errors; Home and the Weekly
  board still update. Commit after the user confirms: `Core: one module's event error no longer stops the others`.

### Task 2: Journal scan stops on a callback error (`Core/Journal.lua`)

**Files:** Modify `Core/Journal.lua:13-93`; create `tests/test_journal.lua`.

**Interfaces:** Consumes `ns.errorHandler`. Produces: unchanged `ns.Journal_Scan/Stop/Progress/StillMissing`;
callbacks erroring stop the scan.

- [ ] Create `tests/test_journal.lua`:

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_journal.lua
-- Core/Journal.lua with stubbed frames and journals: a callback that errors is reported once and stops the scan.
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local frames = {}
_G.CreateFrame = function()
	local f = { scripts = {}, shown = true }
	function f:SetScript(name, fn)
		self.scripts[name] = fn
	end
	function f:Show()
		self.shown = true
	end
	function f:Hide()
		self.shown = false
	end
	frames[#frames + 1] = f
	return f
end
local clock = 0
_G.debugprofilestop = function()
	clock = clock + 0.01 -- 400 reads per 4 ms frame budget
	return clock
end
_G.C_MountJournal = {
	GetMountIDs = function()
		return { 1, 2, 3 }
	end,
	GetMountInfoByID = function(id)
		return "Mount " .. id, 100 + id, 0, nil, nil, nil, nil, nil, nil, false, false
	end,
	GetMountInfoExtraByID = function()
		return nil, nil, "A vendor"
	end,
}
_G.C_PetJournal = {
	GetPetInfoBySpeciesID = function(id)
		if id == 5 then
			return "Pet 5", 1, nil, nil, "A drop", nil, nil, nil, nil, nil, true, 99
		end
	end,
	GetNumCollectedInfo = function()
		return 0
	end,
}
local reported = {}
local ns = {
	errorHandler = function(err)
		reported[#reported + 1] = tostring(err)
	end,
}
assert(loadfile("Tomte/Core/Journal.lua"))("Tomte", ns)

local function Clear()
	for i = #reported, 1, -1 do
		reported[i] = nil
	end
end

-- Runs the owner's frame like game frames until it hides (at most 50).
local function Run(f)
	for _ = 1, 50 do
		if not f.shown then
			return
		end
		f.scripts.OnUpdate(f, 0.016)
	end
end

test("a clean scan reads every missing mount and pet and finishes", function()
	Clear()
	local mounts, pets, done = 0, 0, false
	ns.Journal_Scan("ok", {
		mount = function()
			mounts = mounts + 1
		end,
		pet = function(id)
			pets = pets + 1
			eq(id, 5)
		end,
		done = function()
			done = true
		end,
	})
	Run(frames[#frames])
	eq(mounts, 3)
	eq(pets, 1)
	eq(done, true)
	eq(#reported, 0)
end)

test("a mount callback that errors is reported once and stops the scan", function()
	Clear()
	local calls = 0
	ns.Journal_Scan("bad", {
		mount = function()
			calls = calls + 1
			error("boom")
		end,
	})
	local f = frames[#frames]
	f.scripts.OnUpdate(f, 0.016)
	eq(calls, 1, "not retried")
	eq(#reported, 1)
	eq(f.shown, false, "the frame stops")
	eq(ns.Journal_Progress("bad"), nil, "no scan left")
end)

test("a pet callback or mountsDone that errors stops the scan too", function()
	Clear()
	ns.Journal_Scan("pets", {
		pet = function()
			error("pet boom")
		end,
	})
	Run(frames[#frames])
	eq(#reported, 1)
	eq(ns.Journal_Progress("pets"), nil)
	Clear()
	ns.Journal_Scan("phase", {
		mountsDone = function()
			error("done boom")
		end,
	})
	Run(frames[#frames])
	eq(#reported, 1)
	eq(ns.Journal_Progress("phase"), nil)
end)

H.done()
```

- [ ] Run `lua Tomte/tests/test_journal.lua`: the error tests FAIL (the error escapes OnUpdate; the index never
  advances).
- [ ] In `Core/Journal.lua` replace lines 13-70 (ReadMount, ReadPet, OnUpdate) with:

```lua
-- Calls a callback, its error to BugSack. false when it errored: the scan then stops, since a callback that fails on
-- one entry would fail on the next thousands too, every frame.
local function Call(fn, ...)
	if not fn then
		return true
	end
	return (xpcall(fn, ns.errorHandler, ...))
end

local function ReadMount(scan, mountID)
	local name, spellID, icon, _, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	if not name or isCollected or shouldHideOnChar then
		return true
	end
	local _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)
	return Call(scan.cb.mount, mountID, { name = name, spellID = spellID, icon = icon, source = source })
end

local function ReadPet(scan, speciesID)
	-- pcall: an unused species ID may error instead of returning nothing.
	local ok, name, icon, _, _, source, _, _, _, _, _, obtainable, displayID =
		pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
	if not ok or not name or not obtainable then
		return true
	end
	local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
	if owned and owned > 0 then
		return true
	end
	return Call(scan.cb.pet, speciesID, { name = name, icon = icon, source = source, displayID = displayID })
end

local function Stop(frame)
	frame.scan = nil
	frame:Hide()
end

local function OnUpdate(self)
	local scan = self.scan
	if not scan then
		self:Hide()
		return
	end
	local deadline = debugprofilestop() + BUDGET_MS
	while debugprofilestop() < deadline do
		if self.scan ~= scan then
			return -- a callback stopped or replaced this scan
		end
		local ok
		if scan.phase == "mounts" then
			local mountID = scan.ids[scan.i]
			if mountID then
				scan.i = scan.i + 1 -- before the callback: an entry whose callback errors isn't read again
				ok = ReadMount(scan, mountID)
			else
				scan.phase, scan.i = "pets", 1
				ok = Call(scan.cb.mountsDone)
			end
		elseif scan.i <= MAX_SPECIES then
			local speciesID = scan.i
			scan.i = scan.i + 1
			ok = ReadPet(scan, speciesID)
		else
			Stop(self)
			Call(scan.cb.done)
			return
		end
		if not ok then
			if self.scan == scan then
				Stop(self)
			end
			return
		end
	end
end
```

  and replace `ns.Journal_Stop`'s body (lines 88-92) with:

```lua
	local frame = scans[owner]
	if frame then
		Stop(frame)
	end
```

  Add to the header comment: `-- A callback that errors is reported once (ns.errorHandler) and stops its scan.`
- [ ] Run `lua Tomte/tests/test_journal.lua`: passes.
- [ ] In game: `/reload`, open Tomte > Collect here's map tab and the Holidays page (both scan the journals). The lists
  fill as before, no errors in BugSack. Commit after confirmation: `Core: a failing journal scan reports once and stops`.

### Task 3: One combat line (`ns.Print_Combat`)

**Files:** Modify `Core/Core.lua` (after `ns.Print`, line 40) and the call sites below.

**Interfaces:** Produces `ns.Print_Combat(action)`.

- [ ] In `Core/Core.lua` after `function ns.Print(msg) ... end` add:

```lua

-- The one line for something Tomte won't do in combat: "Tomte: can't open the map in combat." action: what the
-- player asked for, lower case, no period. Nothing is queued for after combat.
function ns.Print_Combat(action)
	ns.Print(("can't %s in combat."):format(action))
end
```

- [ ] `Core/Check.lua:18-23` (finding 8). Before:

```lua
	if InCombatLockdown() or UnitIsDeadOrGhost("player") then
		if spec.verbose then
			ns.Print(spec.name .. ": not in combat or while dead.")
		end
		return
	end
```

  After:

```lua
	if InCombatLockdown() then
		if spec.verbose then
			ns.Print_Combat("run the " .. spec.name)
		end
		return
	end
	if UnitIsDeadOrGhost("player") then
		if spec.verbose then
			ns.Print(("can't run the %s while you're dead."):format(spec.name))
		end
		return
	end
```

- [ ] Replace each refusal line (the `if InCombatLockdown() then ... return end` around it stays as is):

| Site | Before | After |
| --- | --- | --- |
| `Modules/Achievements/Achievements.lua:203` | `ns.Print("the Achievements window opens after combat.")` | `ns.Print_Combat("open the Achievements window")` |
| `Modules/Alts/Send.lua:185` | `ns.Print("not in combat.")` | `ns.Print_Combat("move items for your alts")` |
| `Modules/Flight/Flight.lua:461` | `ns.Print("not in combat.")` | `ns.Print_Combat("open the map")` |
| `Modules/Gear/Reveal.lua:116` | `ns.Print("Gear Check: you can't change gear in combat.")` | `ns.Print_Combat("change gear")` |
| `Modules/Gear/Sheet.lua:331` | `ns.Print("not in combat.")` | `ns.Print_Combat("open the character pane")` |
| `Modules/GoldQuests/Window.lua:54` | `ns.Print("not in combat.")` | `ns.Print_Combat("open the map")` |
| `Modules/Holidays/Calendar.lua:242` | `ns.Print("after combat: open the Dungeon Finder.")` | `ns.Print_Combat("open the Dungeon Finder")` |
| `Modules/Mount/Mount.lua:445` | `ns.Print("macros can't be made in combat.")` | `ns.Print_Combat("make the mount macro")` |
| `Modules/Mount/Mount.lua:572` | `ns.Print("not in combat.")` | `ns.Print_Combat("summon a mount")` |
| `Panel/Entries.lua:23` | `ns.Print("the journal opens after combat.")` | `ns.Print_Combat("open the journal")` |
| `Panel/HomeHero.lua:72` | `ns.Print("not in combat.")` | `ns.Print_Combat("open the character pane")` |
| `Panel/HomeHero.lua:154` | `ns.Print("not in combat.")` | `ns.Print_Combat("open the map")` |
| `Panel/Setup.lua:34` | `ns.Print("Pick after combat.")` | `ns.Print_Combat("apply a preset")` |
| `Panel/Setup.lua:180` | `ns.Print("Run setup after combat.")` | `ns.Print_Combat("run setup")` |
| `Panel/Share.lua:70` | `ns.Print("Import after combat.")` | `ns.Print_Combat("import settings")` |
| `Panel/Share.lua:216` | `ns.Print("Import after combat.")` | `ns.Print_Combat("import settings")` |
| `Panel/Share.lua:238` | `ns.Print("Undo after combat.")` | `ns.Print_Combat("undo an import")` |
| `Panel/Window.lua:43` | `ns.Print("Reload after combat to switch themes.")` | `ns.Print_Combat("reload to switch themes")` |

  The three map tab sites (`Modules/Collect/Tab.lua:352`, `Modules/Teleports/MapTab.lua:515`,
  `Modules/WorldQuests/Tab.lua:652`) go away in Task 5.
- [ ] Fix the comment above `ns.Entry_Open` (`Panel/Entries.lua:19-20`): "Both wait for the end of combat: opening
  ..." becomes "Neither opens in combat: opening ...".
- [ ] Grep check: `grep -rn "after combat\|not in combat" --include=*.lua Core Panel Modules` lists only the kept
  sites from the spec's "Checked, not changed" (SafeTrack queues, Pets' reason, Teleports' note/tooltip, Moments,
  Fishing, settings tooltips).
- [ ] Run all tests: pass. `luac -l Core/Core.lua | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` lists only WoW/Lua globals.
- [ ] In game: `/reload`, start a fight with a training dummy, then: click Home's location (world map), `/tomte setup`,
  `/tomte profile import`, `/tomte hunter check` on a hunter (or `/tomte rogue check`). Each prints one line
  "Tomte: can't ... in combat." and nothing opens. Commit after confirmation: `Core: one wording for what Tomte won't
  do in combat`.

### Task 4: Off modules say so (central command gate, bindings, RequireOn)

**Files:** Modify `Core/Modules.lua` (add after `ns.ModuleWanted`, line 250), `Core/Core.lua:181-198` and after
`ns.Print_Combat`, `tests/test_modules.lua` (before `H.done()`), the binding files, the RequireActive files and the
inline-check files listed below, `Modules/Fishing/Fishing.lua:135`.

**Interfaces:** Produces `ns.Module_OffText`, `ns.Module_CommandAllowed`, `ns.Module_RequireOn`, `ns.Binding_Add`,
`whileOff`. Consumes `ns.ModuleBlockedReason`, `ns.modulesByKey`.

- [ ] Add to `tests/test_modules.lua` before `H.done()`:

```lua
test("OffText says the module is off, or why it can't run", function()
	eq(ns.Module_OffText({ key = "gather", name = "Gathering" }), "Gathering is off. Turn it on in /tomte.")
	eq(ns.Module_OffText({ key = "hunter", name = "Hunter Pets" }, "Only for hunters."),
		"Hunter Pets: Only for hunters.")
	eq(ns.Module_OffText({ key = "x" }), "x is off. Turn it on in /tomte.", "no name: the key")
end)
test("CommandAllowed: an active module, or a command marked whileOff", function()
	local on, off = { active = true }, { active = false }
	eq(ns.Module_CommandAllowed(on, { "list" }), true)
	eq(ns.Module_CommandAllowed(off, { "list" }), false)
	eq(ns.Module_CommandAllowed(off, { "status", whileOff = true }), true)
	eq(ns.Module_CommandAllowed(off, nil), false)
end)
```

- [ ] Run `lua Tomte/tests/test_modules.lua`: FAILS (functions missing).
- [ ] In `Core/Modules.lua` after `ns.ModuleWanted` add:

```lua

-- The line for a command, key binding or button of a module that isn't running: "Gathering is off. Turn it on in
-- /tomte.", or its blocked reason ("Hunter Pets: Only for hunters.") when it can't run here at all.
function ns.Module_OffText(module, blockedReason)
	local name = module.name or module.key
	if blockedReason then
		return name .. ": " .. blockedReason
	end
	return name .. " is off. Turn it on in /tomte."
end

-- A /tomte command runs while its module is active; cmd.whileOff = true lets it run while off (a status line that
-- reports the off state itself).
function ns.Module_CommandAllowed(module, cmd)
	return module.active == true or (cmd ~= nil and cmd.whileOff == true)
end
```

- [ ] Run `lua Tomte/tests/test_modules.lua`: passes.
- [ ] In `Core/Core.lua` after `ns.Print_Combat` add:

```lua

-- True when the module (table or key) is running; otherwise says it's off (or why it can't run) and returns false.
-- For buttons, key bindings and anything else a player can reach while the module is off.
function ns.Module_RequireOn(module)
	if type(module) == "string" then
		module = ns.modulesByKey[module]
	end
	if not module then
		return false
	end
	if module.active then
		return true
	end
	ns.Print(ns.Module_OffText(module, ns.ModuleBlockedReason(module)))
	return false
end
```

- [ ] Replace `RunModuleCommand` (`Core/Core.lua:177-198`, comment included) with:

```lua
-- "preview mount" runs the "preview" command with "mount". Text that matches no command goes to the module's
-- fallbackCommand (if it has one and its pattern matches), with the whole text. While the module is off a command
-- only says so, unless it's marked whileOff.
-- Handlers get the text lowercased, then as typed (item links and names keep their case):
--   cmd[3](arg, rawArg)  fallback[3](text, rawText)
local function RunModuleCommand(module, text, rawText)
	rawText = rawText or text
	local name, arg = text:match("^(%S*)%s*(.-)$")
	local rawArg = rawText:match("^%S*%s*(.-)$")
	local found
	for _, cmd in ipairs(module.commands) do
		if cmd[1] == name then
			found = cmd
			break
		end
	end
	local fallback = module.fallbackCommand
	if not found and fallback and text:match(fallback.pattern) then
		found, arg, rawArg = fallback, text, rawText
	end
	if not found then
		ns.Print(module.name .. " commands:")
		PrintModuleCommands(module)
		return
	end
	if not ns.Module_CommandAllowed(module, found) then
		ns.Print(ns.Module_OffText(module, ns.ModuleBlockedReason(module)))
		return
	end
	found[3](arg, rawArg)
end
```

- [ ] Replace the bindings block (`Core/Core.lua:200-212`) with:

```lua
-- Keybinds (Bindings.xml, Key Bindings > Tomte): the binding scripts need a global. Modules add theirs with
-- ns.Binding_Add; TOGGLE is the window's.
ns.bindings = {
	TOGGLE = function()
		ns.Panel_Toggle()
	end,
}
function Tomte_Binding(name)
	local handler = ns.bindings[name]
	if handler then
		handler()
	end
end
BINDING_NAME_TOMTE_TOGGLE = "Toggle Tomte"

-- A key binding of moduleKey's: fn runs while that module is on; while it's off the key says so.
function ns.Binding_Add(name, moduleKey, fn)
	ns.bindings[name] = function()
		if ns.Module_RequireOn(moduleKey) then
			fn()
		end
	end
end
```

- [ ] Bindings, each replaced (the `BINDING_NAME_*` lines stay):

  `Modules/Gather/Gather.lua:405-414` before:

```lua
ns.bindings.GATHER_FOLLOW = function()
	if module.active then
		ns.GatherFollow_Toggle()
	end
end
ns.bindings.GATHER_SKIP = function()
	if module.active then
		ns.GatherFollow_Skip()
	end
end
```

  after:

```lua
ns.Binding_Add("GATHER_FOLLOW", "gather", function()
	ns.GatherFollow_Toggle()
end)
ns.Binding_Add("GATHER_SKIP", "gather", function()
	ns.GatherFollow_Skip()
end)
```

  `Modules/Chat/Copy.lua:196-200`: `ns.bindings.CHAT_COPY = function() if module and module.active then CopyCurrent()
  end end` becomes

```lua
ns.Binding_Add("CHAT_COPY", "chatcopy", function()
	CopyCurrent()
end)
```

  `Modules/GoldQuests/Gold.lua:304-308` becomes

```lua
ns.Binding_Add("GOLD", "wgq", function()
	ns.GoldWindow_Toggle()
end)
```

  `Modules/Showcase/Showcase.lua:169-173` becomes

```lua
ns.Binding_Add("SHOWCASE", "showcase", function()
	ns.CharShow_Toggle()
end)
```

  `Modules/Social/Whispers.lua:463-472` becomes

```lua
ns.Binding_Add("WHISPER_REPLY", "whispers", function()
	ReplyNewest()
end)
ns.Binding_Add("WHISPER_INBOX", "whispers", function()
	ns.Inbox_Toggle()
end)
```

  Update the comment above each block to `-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.`
- [ ] Fold the module-local `RequireActive` into the shared one. In each file: delete the whole `local function
  RequireActive() ... end` block, then replace every remaining `RequireActive()` with `ns.Module_RequireOn(module)`
  (Edit with `replace_all`, after the definition is gone). Files and lines:
  - `Modules/Achievements/Achievements.lua:323-329` (uses 332, 339, 463, 469, 475)
  - `Modules/Collect/Collect.lua:241-247` (uses 250, 268)
  - `Modules/Flight/Flight.lua:409-415` (uses 566, 572)
  - `Modules/GoldQuests/Gold.lua:230-236` (uses 239, 245, 251, 269, 291)
  - `Modules/Holidays/Holidays.lua:421-427` (uses 430, 510)
  - `Modules/Travel/Waypoint.lua:221-227` (uses 230, 254, 403; 230/254 also serve `/way`, which doesn't go through
    the command gate)
  - `Modules/WorldQuests/WorldQuests.lua:140-146` (uses 149, 172)
- [ ] Inline checks: replace the block

```lua
	if not module.active then
		ns.Print("<Name> is off.")
		return
	end
```

  with

```lua
	if not ns.Module_RequireOn(module) then
		return
	end
```

  (same indentation as found) at: `Modules/AFK/AFK.lua:256-259`, `Modules/Chat/Copy.lua:81-84` (its text ends
  "Turn it on in /tomte (Chat)."), `Modules/Chat/Filter.lua:215-218`, `:231-234`, `:240-243`,
  `Modules/Gear/Gear.lua:152-155` (inside `Command`), `Modules/Combat/PetHealth.lua:351-354` (inside `Command`),
  `Modules/Hunter/Hunter.lua:51-54`, `Modules/Moments/Moments.lua:599-602`, `Modules/Share/Share.lua:430-433`,
  `Modules/Showcase/Showcase.lua:98-101`, `Modules/Social/Alerts.lua:145-148`, `Modules/Social/Friends.lua:312-315`,
  `Modules/Social/Mentions.lua:120-123`, `Modules/Social/Whispers.lua:422-425`.
  Two differ:
  - `Modules/Gear/Reveal.lua:323-326`: `if not ns.gearModule.active then ns.Print("Gear Check is off.") return end`
    becomes `if not ns.Module_RequireOn(ns.gearModule) then return end` (on four lines as above).
  - `Modules/Mount/Mount.lua:448-451`: `if not module.active then ns.Print("turn Smart Mount on first.") return end`
    becomes the standard block.
  - `Modules/Recap/Recap.lua:159-165`, `IsOff`, becomes:

```lua
-- Commands and buttons while the module is off: says so and returns true.
local function IsOff()
	return not ns.Module_RequireOn(module)
end
```

- [ ] `Modules/Fishing/Fishing.lua:135`: `{ "status", "key, soft interact, helpers and pending restores", Status },`
  becomes `{ "status", "key, soft interact, helpers and pending restores", Status, whileOff = true },`.
- [ ] Grep check: `grep -rn "is off\.\")" --include=*.lua Modules` lists nothing; `grep -rn "RequireActive"
  --include=*.lua .` lists nothing; `grep -rn "ns.bindings\." --include=*.lua Modules` lists nothing.
- [ ] Run all tests: pass. luac global check on `Core/Core.lua`, `Core/Modules.lua` and each edited module file.
- [ ] In game: `/reload`. Turn Gathering off in /tomte, press the Gathering follow key (if bound) and type
  `/tomte gather nodes`: both print "Tomte: Gathering is off. Turn it on in /tomte." Type `/tomte fishing status` with
  Fishing off: the status lines still print. On a non-hunter: `/tomte hunter check` prints "Tomte: Hunter Pets: Only
  for hunters." Turn Gathering on again: the key and command work. `/tomte chatcopy` with Chat Copy on still copies
  (fallback command). Commit after confirmation: `Core: commands and keys of a module that's off say so`.

### Task 5: Map tabs open the map's side panel (`ns.MapTabs_Open`)

**Files:** Modify `Panel/MapTabs.lua` (header lines 11-13, add after `ns.MapTabs_IsActive` line 82),
`Modules/WorldQuests/Tab.lua:649-663`, `Modules/Teleports/MapTab.lua:512-526`, `Modules/Collect/Tab.lua:349-363`.

**Interfaces:** Consumes `ns.Print_Combat`, `ns.Module_RequireOn`, Blizzard `OpenQuestLog(mapID)` (FrameXML global,
Blizzard_WorldMap.lua on the live 12.1.5 branch: `WorldMapFrame:HandleUserActionOpenQuestLog(mapID)` ->
`SetDisplayState(DISPLAY_STATE_OPEN_MINIMIZED_WITH_LOG)`, returns early when the `WorldMapDisabled` game rule is on).
Produces `ns.MapTabs_Open(key, mapID) -> bool`.

- [ ] In `Panel/MapTabs.lua` add after `ns.MapTabs_IsActive`:

```lua

-- Opens the world map with its quest log side panel and shows tab key (/tomte ... open, Home, zone toasts). The panel
-- opens the way the L key does (OpenQuestLog: a maximized map becomes the windowed one); the questLogOpen CVar, the
-- player's own choice, is left alone. Not in combat: showing Blizzard's map from addon code there can be blocked.
-- Returns true when the tab shows; false when it isn't there (its module is off) or the panel can't open.
function ns.MapTabs_Open(key, mapID)
	local t = byKey[key]
	if not (t and t.shown) then
		return false
	end
	if InCombatLockdown() then
		ns.Print_Combat("open the map")
		return false
	end
	if not (WorldMapFrame:IsShown() and QuestMapFrame:IsShown()) then
		OpenQuestLog(mapID)
	elseif mapID then
		WorldMapFrame:SetMapID(mapID)
	end
	if not QuestMapFrame:IsShown() then
		ns.Print("the map's side panel can't open here.") -- a game rule (some scenarios) hides it
		return false
	end
	ns.MapTabs_Select(key)
	return true
end
```

  and in the header list (line 12) add `ns.MapTabs_Open(key, mapID)`.
- [ ] `Modules/WorldQuests/Tab.lua:649-663` before:

```lua
-- /tomte wq open and the zone toast: the map on this tab.
function ns.WQTab_Open()
	if InCombatLockdown() then
		ns.Print("not in combat.")
		return
	end
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	if QuestMapFrame:IsShown() then
		ns.MapTabs_Select(KEY)
	else
		ns.Print("open the map's quest log panel, then click the map tab.")
	end
end
```

  after:

```lua
-- /tomte wq open, Home and the zone toast: the map on this tab.
function ns.WQTab_Open()
	if ns.Module_RequireOn("wq") then
		ns.MapTabs_Open(KEY)
	end
end
```

- [ ] `Modules/Teleports/MapTab.lua:512-526` (same shape, "portal tab"): after:

```lua
-- /tomte tp open and Home: the map with this tab showing.
function ns.TpTab_Open()
	if ns.Module_RequireOn("tp") then
		ns.MapTabs_Open(KEY)
	end
end
```

- [ ] `Modules/Collect/Tab.lua:349-363` (same shape, "horse tab"): after:

```lua
-- /tomte collect open, Home and the zone toast: the map on this tab.
function ns.CollectTab_Open()
	if ns.Module_RequireOn("collect") then
		ns.MapTabs_Open(KEY)
	end
end
```

- [ ] Run all tests; luac global check on the four files (`OpenQuestLog`, `WorldMapFrame`, `QuestMapFrame` are WoW
  globals).
- [ ] In game: `/reload`. (1) Map closed: `/tomte wq open` opens the windowed map with the side panel on the World
  quests tab. (2) Map open, quest log hidden (side panel toggle at the map's bottom right): `/tomte tp open` opens the
  panel on Teleports. (3) Maximize the map, `/tomte collect open`: it becomes the windowed map with the panel on
  Collect here. (4) Close the map, enter combat, press M (and L): the map opens; BugSack shows no
  ADDON_ACTION_BLOCKED. (5) In combat `/tomte wq open` prints "Tomte: can't open the map in combat." (6) With World
  quests off, `/tomte wq open` prints the off line. Commit after confirmation: `Map tabs: open the map's side panel
  themselves`.

### Task 6: Esc closes one Tomte frame at a time (`UI.CloseOnEscape`)

**Files:** Modify `Panel/Controls.lua` (append a section at the end, header comment line 3), `Panel/Widgets.lua:85-111`
(`UI.Dialog`), `Panel/Confirm.lua:30-31`, `Panel/Setup.lua:143`, `Panel/Panel.lua:17, 277-283, 294, 415-423`,
`Modules/Social/Inbox.lua:511-526`, `Modules/Weekly/Popup.lua:102-117`.

**Interfaces:** Produces `UI.CloseOnEscape(frame)`, global frame name `TomteEscape`. Removes `TomtePanelEscape`,
`TomteInboxEscape`, `TomteWeeklyEscape` and the `UISpecialFrames` entries of `TomteDialog`, `TomteSetup`,
`TomteImportPreview`, `TomtePetsGuides`.

- [ ] Append to `Panel/Controls.lua`:

```lua

-- Escape --------------------------------------------------------------------------------------------------------------

-- Esc closes the Tomte frame on top (the last one shown), one per press, so a dialog over the Tomte window closes on
-- its own. One dummy in UISpecialFrames stands for all of them: Blizzard's CloseSpecialWindows hides it, its OnHide
-- closes the top frame, and while more are open it shows again a frame later. Works in combat, where a frame can't
-- take keyboard input. (RegisterGameMenuEscHandler would be the direct way, but registering a handler from addon code
-- taints the Esc chain.)
local escapeOpen = {} -- shown frames in the order they were shown: the last one is on top
local escapeDummy

-- Drops frame (nil: none) and every frame that isn't shown any more from the list.
local function EscapeForget(frame)
	for i = #escapeOpen, 1, -1 do
		if escapeOpen[i] == frame or not escapeOpen[i]:IsShown() then
			table.remove(escapeOpen, i)
		end
	end
end

local function EscapeDummy()
	if escapeDummy then
		return escapeDummy
	end
	escapeDummy = CreateFrame("Frame", "TomteEscape", UIParent)
	escapeDummy:Hide()
	tinsert(UISpecialFrames, "TomteEscape")
	escapeDummy:SetScript("OnHide", function(self)
		-- Still shown: UIParent hid (Alt+Z, a cinematic), not Esc; the frames come back with it.
		if self:IsShown() then
			return
		end
		EscapeForget(nil)
		local top = escapeOpen[#escapeOpen]
		if top then
			top:Hide() -- its OnHide takes it off the list
		end
		C_Timer.After(0, function()
			if #escapeOpen > 0 and not self:IsShown() then
				self:Show()
			end
		end)
	end)
	return escapeDummy
end

-- Esc closes frame, the last one shown first. Call it after the frame's own SetScript("OnShow"/"OnHide"): SetScript
-- drops hooks.
function UI.CloseOnEscape(frame)
	local dummy = EscapeDummy()
	frame:HookScript("OnShow", function(self)
		EscapeForget(self)
		escapeOpen[#escapeOpen + 1] = self
		dummy:Show()
	end)
	frame:HookScript("OnHide", function(self)
		EscapeForget(self)
		if #escapeOpen == 0 then
			dummy:Hide()
		end
	end)
end
```

  and change the header (line 3) to "More ns.UI controls: an on/off switch, segmented buttons, a resize grip and Esc
  handling for Tomte's windows."
- [ ] `Panel/Widgets.lua` `UI.Dialog`: replace

```lua
	if opts.escape ~= false then
		tinsert(UISpecialFrames, name)
	end
```

  with

```lua
	if opts.escape ~= false then
		UI.CloseOnEscape(frame) -- Controls.lua: only this dialog closes, not the Tomte window under it
	end
```

  and in the comment above `UI.Dialog` change "opts.escape (default true) lets Escape close it." to "opts.escape
  (default true) lets Escape close it (UI.CloseOnEscape; callers HookScript OnShow/OnHide, SetScript would drop it)."
- [ ] `Panel/Confirm.lua:30-31`: before

```lua
	-- Escape is handled below rather than through UISpecialFrames, which would close the Tomte window too.
	dialog = UI.Dialog("TomteConfirm", WIDTH, nil, { y = 160, escape = false })
```

  after

```lua
	-- Out of combat Esc and Enter are handled below; in combat (no keyboard) Esc closes it through UI.CloseOnEscape,
	-- before the Tomte window under it.
	dialog = UI.Dialog("TomteConfirm", WIDTH, nil, { y = 160 })
```

- [ ] `Panel/Setup.lua:143`: `frame:SetScript("OnHide", function(self)` becomes `frame:HookScript("OnHide",
  function(self)` (keeps UI.Dialog's Esc hook; the body already ignores a hide by UIParent).
- [ ] `Panel/Panel.lua`: line 17 `local panel, escape` becomes `local panel`; in OnShow (277-280) remove
  `escape:Show()`; in OnHide (281-283) remove `escape:Hide()`; after the OnHide block's `end)` (line 294, before the
  function's `end`) add

```lua
	UI.CloseOnEscape(panel) -- after the SetScripts above: they would drop its hooks
```

  and in `ns.Panel_Init` remove lines 415-423 (the comment, the `TomtePanelEscape` frame, the `UISpecialFrames` insert
  and its OnHide), leaving `CreateSettingsStub()` as the body.
- [ ] `Modules/Social/Inbox.lua:511-526`: replace the comment, the `TomteInboxEscape` frame and the two HookScripts with

```lua
	UI.CloseOnEscape(frame) -- after the SetScripts above: they would drop its hooks
```

- [ ] `Modules/Weekly/Popup.lua:102-117`: the same replacement for `TomteWeeklyEscape`.
- [ ] Grep check: `grep -rn "UISpecialFrames" --include=*.lua Panel Modules Core` lists only Controls.lua's insert and
  the read-only loops in `Cinematic/Engine.lua` and `Modules/Moments/Moments.lua`.
- [ ] Run all tests; luac global check on `Panel/Controls.lua` (`UISpecialFrames`, `tinsert`, `C_Timer`, `UIParent`,
  `CreateFrame` only).
- [ ] In game: `/reload`. (1) Open Tomte, then Tomte window settings > Export: Esc closes only the export dialog;
  Esc again closes Tomte. (2) Open Tomte, then the whisper inbox (`/tomte whispers inbox`): Esc closes the inbox,
  then Tomte. (3) Reset a module's settings link (the yes/no question) over Tomte: Esc answers No and Tomte stays.
  (4) In combat with a training dummy: open Tomte and the export dialog, Esc closes the dialog first. (5) With Tomte
  open press Alt+Z twice: Tomte is back; Esc closes it. (6) With Tomte open go AFK (`/afk`, AFK screen on) and come
  back: Tomte is back. (7) With nothing of Tomte's open, Esc opens the game menu as usual. (8) First-run style check:
  `/tomte setup`, Esc closes the picker. Commit after confirmation: `Panel: Esc closes one Tomte window at a time,
  and Alt+Z keeps the window`.

### Task 7: "Around you shows" from every module's around blocks; Delves' switch folds in

**Files:** Modify `Core/Modules.lua:163-182` (`ns.HomeEntries`) and add `ns.Home_AroundChoices`,
`tests/test_home.lua`, `Core/Migrations.lua` (append migration 10), `tests/test_migrations.lua`, `Panel/Window.lua`
(whole file restructure), `Modules/Delves/Delves.lua:149-172, 313, 322-323`.

**Interfaces:** Produces `ns.Home_AroundChoices()`, migration 10. Consumes module `home` entries.

- [ ] Add to `tests/test_home.lua` before `H.done()`:

```lua
test("AroundChoices lists every around block, on or off, in Home's order", function()
	reset()
	ns.RegisterModule({ key = "a", name = "a", category = "x", home = {
		{ kind = "around", key = "flightaround", name = "Flight masters", order = 4 },
		{ kind = "page", key = "pagea", name = "Page" },
		{ kind = "around", key = "collectaround", name = "Collect here", order = 1 },
	} })
	ns.RegisterModule({ key = "b", name = "b", category = "x", home = {
		{ kind = "around", key = "delvesaround", name = "Delves", order = 6 },
		{ kind = "around", key = "extra", name = "No order" },
	} })
	local choices = ns.Home_AroundChoices()
	local keys = {}
	for i, c in ipairs(choices) do
		keys[i] = c.key
	end
	eq(table.concat(keys, ","), "collectaround,flightaround,delvesaround,extra")
	eq(choices[1].name, "Collect here")
end)
```

- [ ] Add to `tests/test_migrations.lua` before the "migrations don't run twice" test:

```lua
test("Delves: an unticked Delves in Around you moves to the window's Around you shows", function()
	local db = { schema = 9, delves = { around = false, entrance = true }, window = { around = { wqaround = false } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.delves.around, nil)
	eq(db.delves.entrance, true, "other Delves settings kept")
	eq(db.window.around.delvesaround, false)
	eq(db.window.around.wqaround, false, "other blocks kept")
	local on = { schema = 9, delves = { around = true } }
	ns.RunMigrations(on, ns.MIGRATIONS)
	eq(on.delves.around, nil)
	eq(on.window, nil, "ticked: nothing to move")
	local noWindow = { schema = 9, delves = { around = false } }
	ns.RunMigrations(noWindow, ns.MIGRATIONS)
	eq(noWindow.window.around.delvesaround, false, "window tables made")
	local bare = { schema = 9 }
	ns.RunMigrations(bare, ns.MIGRATIONS)
	eq(bare.delves, nil, "no delves table is fine")
end)
```

- [ ] Run `lua Tomte/tests/test_home.lua` and `lua Tomte/tests/test_migrations.lua`: both FAIL.
- [ ] `Core/Modules.lua`: replace `ns.HomeEntries` (lines 163-182) and add the choices function:

```lua
-- Sorts entries by entry.order (lowest first, default 100), then by index[entry] (registration order).
local function SortEntries(list, index)
	table.sort(list, function(a, b)
		local x, y = a.order or 100, b.order or 100
		if x ~= y then
			return x < y
		end
		return index[a] < index[b]
	end)
end

-- Sorted by entry.order (lowest first, default 100), then registration order.
function ns.HomeEntries(kind)
	local list, index = {}, {}
	for _, module in ipairs(ns.modules) do
		for _, entry in ipairs(module.home or {}) do
			if entry.kind == kind and ns.HomeEntryVisible(entry) and not (kind == "around" and AroundHidden(entry)) then
				list[#list + 1] = entry
				index[entry] = #list
			end
		end
	end
	SortEntries(list, index)
	return list
end

-- Every "around" block of every module, on or off, in Home's order: { key, name } for the Tomte window's
-- "Around you shows" switches (Panel/Window.lua).
function ns.Home_AroundChoices()
	local list, index = {}, {}
	for _, module in ipairs(ns.modules) do
		for _, entry in ipairs(module.home or {}) do
			if entry.kind == "around" then
				list[#list + 1] = entry
				index[entry] = #list
			end
		end
	end
	SortEntries(list, index)
	local choices = {}
	for i, entry in ipairs(list) do
		choices[i] = { key = entry.key, name = entry.name }
	end
	return choices
end
```

- [ ] `Core/Migrations.lua`: append inside `ns.MIGRATIONS`, after migration 9:

```lua
	-- 10: Delves' own "Delves in Around you" switch became the Tomte window's "Around you shows" one (delvesaround).
	function(db)
		local delves = type(db.delves) == "table" and db.delves
		if not delves then
			return
		end
		if delves.around == false then
			if type(db.window) ~= "table" then
				db.window = {}
			end
			if type(db.window.around) ~= "table" then
				db.window.around = {}
			end
			db.window.around.delvesaround = false
		end
		delves.around = nil
	end,
```

- [ ] Run both tests: pass.
- [ ] `Panel/Window.lua`: replace lines 9-16 (the AROUND list) with nothing; change `local module = ns.RegisterModule({`
  to a forward-declared `local module` + `module = ns.RegisterModule({`; move the `SHARE` table and its comment above
  the registration; delete the two loops at the end (`for _, block in ipairs(AROUND)` and `for _, spec in
  ipairs(SHARE)`); add before the registration:

```lua
local module

-- "Around you shows": one switch per "around" block of every module (on or off), added on ADDON_LOADED (init), when
-- every module has registered; Setup and sharing after them. A block never touched starts ticked.
local function AddRows(db)
	if module.rowsAdded then
		return
	end
	module.rowsAdded = true
	for _, choice in ipairs(ns.Home_AroundChoices()) do
		module.defaults.around[choice.key] = true -- what Reset puts back
		if db.around[choice.key] == nil then
			db.around[choice.key] = true
		end
		module.options[#module.options + 1] = { type = "checkbox", key = "around." .. choice.key, label = choice.name,
			onChange = Redraw, tooltip = "This block in Home's \"Around you\" column (it still needs its module on)." }
	end
	for _, spec in ipairs(SHARE) do
		module.options[#module.options + 1] = spec
	end
end
```

  and in the registration table add `init = AddRows,` after `alwaysOn = true,`; change the `around` default comment to
  `around = {}, -- [home entry key] = false hides that "Around you" block (one true per block, set in AddRows)`.
- [ ] `Modules/Delves/Delves.lua`: in `AROUND.items` (lines 158-171) remove

```lua
		if not db.around then
			return rows
		end
```

  in `defaults` (line 313) remove `around = true, `; in `options` remove the row
  `{ type = "checkbox", key = "around", label = "Delves in Around you", onChange = ns.Delves_Changed, tooltip = "The
  delves in your zone on Home, bountiful first. Click one to track it." },` (lines 322-323).
- [ ] Run all tests (test_profile included: an export/import must not need `delves.around`). luac global check on
  `Panel/Window.lua`, `Core/Modules.lua`.
- [ ] In game: `/reload`. Tomte window settings > "Around you shows" lists Collect here, World quests, Teleports,
  Flight masters, Mount favorites, Delves, all ticked (or Delves unticked if "Delves in Around you" was off before).
  Untick Delves: Home's Around you drops the Delves block. Delves' settings no longer have that switch. Search the
  settings for "around": the Tomte window shows. Commit after confirmation: `Home: Around you shows every block,
  Delves included`.

### Task 8: Settings search finds words in a module's settings

**Files:** Modify `Panel/Layout.lua:92-103`, `tests/test_panel_layout.lua` (before `H.done()`).

**Interfaces:** Produces the extended `ns.PanelLayout_Matches(module, groupName, text)` (same signature).

- [ ] Add the test:

```lua
test("search also finds a module by its options' labels, button texts and tooltips", function()
	local m = { name = "Gathering", options = {
		{ type = "header", label = "Route" },
		{ type = "checkbox", key = "recordNodes", label = "Remember node spots", tooltip = "Saves where herbs grew." },
		{ type = "button", label = function()
			return "dynamic"
		end, text = "Clear spots" },
	} }
	eq(ns.PanelLayout_Matches(m, "Professions", "node spots"), true, "label")
	eq(ns.PanelLayout_Matches(m, "Professions", "herbs"), true, "tooltip")
	eq(ns.PanelLayout_Matches(m, "Professions", "clear spots"), true, "button text")
	eq(ns.PanelLayout_Matches(m, "Professions", "route"), true, "header")
	eq(ns.PanelLayout_Matches(m, "Professions", "dynamic"), false, "label functions aren't called")
	eq(ns.PanelLayout_Matches({ name = "X", options = "not a table" }, nil, "y"), false)
end)
```

- [ ] Run `lua Tomte/tests/test_panel_layout.lua`: FAILS.
- [ ] Replace `ns.PanelLayout_Matches` with:

```lua
-- text must already be lower case; "" matches everything. Looks at the name, summary, description and group name,
-- and at the text labels, button texts and tooltips of the module's options (label functions aren't called: they
-- can read the game).
function ns.PanelLayout_Matches(module, groupName, text)
	if text == "" then
		return true
	end
	local function Has(s)
		return type(s) == "string" and s:lower():find(text, 1, true) ~= nil
	end
	if Has(module.name) or Has(module.summary) or Has(module.description) or Has(groupName) then
		return true
	end
	for _, spec in ipairs(type(module.options) == "table" and module.options or {}) do
		if Has(spec.label) or Has(spec.text) or Has(spec.tooltip) then
			return true
		end
	end
	return false
end
```

  and update the file header's "what search matches" phrase to "what search matches (names, descriptions, option
  labels and tooltips)".
- [ ] Run the test: passes.
- [ ] In game: `/reload`, Tomte settings search "guild funds": Vendor shows. "node spots": Gathering. "theme": Tomte
  window. Commit after confirmation: `Settings: search also finds words in each module's settings`.

### Task 9: shown() rows update right away

**Files:** Modify `Panel/Layout.lua` (append), `tests/test_panel_layout.lua`, `Panel/Options.lua:24-29, 69-85,
248-262, 544-550`.

**Interfaces:** Produces `ns.PanelLayout_Visibility(options) -> string`.

- [ ] Add the test:

```lua
test("Visibility marks each shown() row, in order", function()
	local open = true
	local options = {
		{ type = "checkbox", key = "a", label = "A" },
		{ type = "button", label = "B", shown = function()
			return open
		end },
		{ type = "slider", key = "c", label = "C", shown = function()
			return nil
		end },
	}
	eq(ns.PanelLayout_Visibility(options), "10")
	open = false
	eq(ns.PanelLayout_Visibility(options), "00")
	eq(ns.PanelLayout_Visibility(nil), "")
	eq(ns.PanelLayout_Visibility({ { label = "plain" } }), "", "rows without shown() don't count")
end)
```

- [ ] Run: FAILS. Append to `Panel/Layout.lua`:

```lua

-- Which option rows with a shown() show now, as "1"/"0" in schema order (rows without shown() don't count). The
-- options page rebuilds when this changes.
function ns.PanelLayout_Visibility(options)
	local marks = {}
	for _, spec in ipairs(options or {}) do
		if spec.shown then
			marks[#marks + 1] = spec.shown() and "1" or "0"
		end
	end
	return table.concat(marks)
end
```

- [ ] Run: passes.
- [ ] `Panel/Options.lua`: after `local builtFor -- module whose options are built` (line 29) add
  `local builtVisibility -- ns.PanelLayout_Visibility of builtFor's options when they were built`. Replace
  `SetOption` (lines 69-85) with:

```lua
-- Rebuilds module's options when rows hang on what just changed: a parent option (rows dim or light up) or a shown()
-- that answers differently now. After the switch has finished sliding: a rebuild would cut its animation short.
local function RebuildIfChanged(module, key)
	if builtFor ~= module or not scrollFrame then
		return
	end
	if not (key and IsParent(module, key)) and ns.PanelLayout_Visibility(module.options) == builtVisibility then
		return
	end
	local scroll = scrollFrame
	C_Timer.After(UI.SWITCH_SECONDS, function()
		if builtFor == module and scroll:IsVisible() then
			ns.PanelOptions_Build(scroll, module)
		end
	end)
end

local function SetOption(module, spec, value)
	local tbl, field = Resolve(module.db, spec.key)
	tbl[field] = value
	if spec.onChange then
		spec.onChange(value)
	end
	RebuildIfChanged(module, spec.key)
end
```

  In `Factory.button` replace the OnClick body:

```lua
	row.button:SetScript("OnClick", function()
		local spec, module = row.spec, row.module
		local function Run()
			spec.onClick()
			RebuildIfChanged(module)
		end
		if spec.confirm then
			ns.Confirm_Show(spec.confirm, Run)
		else
			Run()
		end
	end)
```

  In `Build`, after `builtFor = module` add `builtVisibility = ns.PanelLayout_Visibility(module.options)`. Update
  the file header: "shown() (hides the row; re-checked after every change on the page)".
- [ ] Run all tests; luac global check on `Panel/Options.lua`.
- [ ] In game: `/reload`. Tomte window settings: pick another theme in the dropdown: "The new theme shows after a
  reload / Reload now" appears at once (pick the current theme again: it goes). After `/tomte profile import` +
  import, "Undo import" shows on the page without leaving it (the UI reloads on import, so check it's there after the
  reload, and that Undo removes it). Commit after confirmation: `Settings: rows that depend on a choice show or hide
  right away`.

### Task 10: Content kind moves to Core (`Core/CheckData.lua`)

**Files:** Create `Core/CheckData.lua`, `tests/test_check.lua`; modify `Tomte.toc` (before `Core/Check.lua`, line
34), `Core/Check.lua:51`, `Modules/Hunter/Data.lua:7, 256-266`, `Modules/Hunter/Checks.lua:67`,
`Modules/Upkeep/Durability.lua:105`, `tests/test_hunter.lua:178-184`; regenerate `Core/BugFiles.lua`.

**Interfaces:** Produces `ns.Check_ContentKind`. Removes `ns.Hunter_ContentKind`.

- [ ] Create `tests/test_check.lua` (the cases move from test_hunter):

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_check.lua
local ns = {}
assert(loadfile("Tomte/Core/CheckData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("ContentKind maps instance types", function()
	eq(ns.Check_ContentKind("party", 8), "dungeon")
	eq(ns.Check_ContentKind("raid", 16), "raid")
	eq(ns.Check_ContentKind("scenario", 208), "delve")
	eq(ns.Check_ContentKind("scenario", 12), nil, "other scenarios")
	eq(ns.Check_ContentKind("none", 0), nil, "open world")
	eq(ns.Check_ContentKind("pvp", 0), nil, "battlegrounds")
	eq(ns.Check_ContentKind(nil, nil), nil)
end)

H.done()
```

- [ ] Run `lua Tomte/tests/test_check.lua`: FAILS (file missing).
- [ ] Create `Core/CheckData.lua` (CRLF, Write tool):

```lua
local addonName, ns = ...

-- Readiness checks: pure logic (no WoW API calls; unit-tested in tests/test_check.lua). The guards, chat lines and
-- banner are in Check.lua; Hunter Pets, Rogue Poisons and Durability check again on entering content.

local DELVE_DIFFICULTY = 208 -- GetInstanceInfo()'s difficultyID inside a delve, any tier

-- instanceType, difficultyID from GetInstanceInfo() -> "dungeon" | "raid" | "delve" | nil (open world,
-- battlegrounds, other scenarios)
function ns.Check_ContentKind(instanceType, difficultyID)
	if instanceType == "party" then
		return "dungeon"
	elseif instanceType == "raid" then
		return "raid"
	elseif instanceType == "scenario" and difficultyID == DELVE_DIFFICULTY then
		return "delve"
	end
	return nil
end
```

- [ ] `Tomte.toc`: add `Core/CheckData.lua` on the line before `Core/Check.lua`. Run `lua Tomte/tools/bugfiles.lua`.
- [ ] Replace `ns.Hunter_ContentKind(` with `ns.Check_ContentKind(` in `Core/Check.lua:51`,
  `Modules/Hunter/Checks.lua:67`, `Modules/Upkeep/Durability.lua:105`.
- [ ] `Modules/Hunter/Data.lua`: delete `local DELVE_DIFFICULTY = 208` (line 7) and the function with its comment
  (lines 256-266). `tests/test_hunter.lua`: delete the "ContentKind maps instance types" test (lines 178-184).
- [ ] Run all tests (test_check, test_hunter, test_bugreport): pass. luac global check on `Core/CheckData.lua`: no
  globals at all.
- [ ] In game: `/reload`, enter a dungeon (or a delve) on a hunter with the pet check on: the check runs after
  zoning as before; Durability's instance warning still comes when gear is low. Pure move: commit after
  confirmation, no CHANGELOG line: `Move the content kind rule from Hunter Pets into Core (pure move)`.

### Task 11: Model preview keeps pcall only around the game calls

**Files:** Modify `Panel/ModelPreview.lua:187-223` (SetCreature, SetAppearance), `:249-273` (ModelPreview_Show).

**Interfaces:** Unchanged `ns.ModelPreview_Show(p, model) -> bool`.

- [ ] `SetCreature`: `return` in the early-out becomes `return true`; replace

```lua
	actor:SetModelByCreatureDisplayID(model.displayID) -- set while shown: one set while hidden can stay blank
```

  with

```lua
	-- Set while shown: one set while hidden can stay blank. pcall: a display ID this client doesn't know can error.
	if not pcall(actor.SetModelByCreatureDisplayID, actor, model.displayID) then
		return false
	end
```

  and add `return true` after `p.fitting = GetTime()`.
- [ ] `SetAppearance`: early-out `return` becomes `return true`; replace

```lua
	if actor then
		actor:TryOn(link)
		p.actor, p.baseYaw, p.turn = actor, actor:GetYaw(), 0
	end
```

  with

```lua
	if not actor then
		return false
	end
	-- pcall: TryOn can error on a link the client can't dress (an odd item, a link from another client version).
	if not pcall(actor.TryOn, actor, link) then
		return false
	end
	p.actor, p.baseYaw, p.turn = actor, actor:GetYaw(), 0
	return true
```

- [ ] `ns.ModelPreview_Show`: replace

```lua
	local ok = pcall(function()
		if model.link then
			SetAppearance(p, model.link, model.key or model.link)
		else
			SetCreature(p, model, model.key or model.displayID)
		end
	end)
	if not ok then
		ClearModel(p)
	end
```

  with

```lua
	local ok
	if model.link then
		ok = SetAppearance(p, model.link, model.key or model.link)
	else
		ok = SetCreature(p, model, model.key or model.displayID)
	end
	if not ok then
		ClearModel(p)
	end
```

- [ ] Run all tests; luac global check on `Panel/ModelPreview.lua`.
- [ ] In game: `/reload`, hover rows with a preview in Collect here (a mount), World quests (an appearance reward) and
  Almost Done (a reward): the 3D card shows as before; BugSack shows nothing new. Commit after confirmation:
  `Model preview: only game calls that can fail are guarded`.

### Task 12: Collapse button polls less; scroll thumb drag ends on hide

**Files:** Modify `Panel/Widgets.lua` constants at the top, `:550-552` (comment), `:592-598` (CollapseButton
OnUpdate), `:740-755` (ScrollThumb).

**Interfaces:** Unchanged `UI.CollapseButton`, `UI.ScrollThumb`.

- [ ] Add with the file's other constants: `local COLLAPSE_POLL = 0.1 -- seconds between hover checks for the collapse
  button`.
- [ ] Replace

```lua
	frame:HookScript("OnUpdate", function()
		local over = frame:IsMouseOver()
		if over ~= b:IsShown() then
			b:SetShown(over)
			b:Update()
		end
	end)
```

  with

```lua
	local sinceCheck = 0
	frame:HookScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < COLLAPSE_POLL then
			return
		end
		sinceCheck = 0
		local over = frame:IsMouseOver()
		if over ~= b:IsShown() then
			b:SetShown(over)
			b:Update()
		end
	end)
```

  and extend the comment above `UI.CollapseButton`: "... so the button polls IsMouseOver, a few times a second."
- [ ] In `UI.ScrollThumb`, after the OnMouseUp script add:

```lua
	thumb:SetScript("OnHide", function(self)
		-- Hidden mid-drag (the page changed, the window closed): OnMouseUp never comes.
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		Look(false)
	end)
```

- [ ] Run all tests; luac global check on `Panel/Widgets.lua`.
- [ ] In game: `/reload`. Hover the Almost Done tracker and the Alts crafting tracker: the minus shows within a blink
  and hides when the mouse leaves. In the Tomte window start dragging a scroll thumb and press the Tomte key (window
  closes mid-drag); reopen: the list doesn't jump while the mouse moves and the thumb is thin again. Commit after
  confirmation: `Panel: lighter tracker hover check, scroll drag ends when the list hides`.

### Task 13: Finish

**Files:** `CHANGELOG.md` (**Unreleased**), `README.md` ("Using Tomte" around line 184; Home paragraph line 205-212).

- [ ] All tests from the AddOns folder: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t";
  done` prints nothing.
- [ ] `lua Tomte/tools/bugfiles.lua` (TOC changed in Task 10), then test_bugreport passes.
- [ ] luac check for every Lua file this plan touched: `luac -l <file> | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` lists
  only WoW API and Lua globals (`OpenQuestLog`, `UISpecialFrames`, `tinsert`, `xpcall`, ...), never a local's name.
- [ ] `CHANGELOG.md` under **Unreleased**, one line per confirmed task (skip Task 10):
  - "Everything Tomte won't do in combat now says so the same way ("can't open the map in combat"), and nothing claims it will happen after combat when it won't."
  - "A command, key binding or button of a module that's off now says so ("Gathering is off. Turn it on in /tomte.") instead of doing nothing."
  - "World quests, Teleports and Collect here open the world map's side panel on their tab themselves (commands, Home, zone toasts)."
  - "Esc closes one Tomte window at a time: a dialog over the Tomte window closes on its own. Hiding the UI (Alt+Z, the AFK screen) no longer closes the Tomte window."
  - "Around you shows now lists every block, Delves included; Delves' own switch moved there."
  - "Settings search also finds words inside each module's settings."
  - "Settings that depend on another choice show or hide right away."
  - "An error in one part of Tomte no longer stops other parts reacting to the same game event, and a failing collection scan reports once instead of every frame."
  - "Model previews and the tracker minus button: small fixes (fewer checks while hovering, no stuck scroll drag)."
- [ ] `README.md`: in "Using Tomte", after "switch off what you don't want." add: "A command, key binding or button of
  a module that's off tells you so. In combat Tomte says what it can't do (\"can't open the map in combat\") rather
  than waiting." In the Home paragraph, "\"Around you\" (Collect here, World quests, Teleports, flight masters ...,
  and your mount zone favorites with a click to summon)" gets "Delves in your zone, " before "and your mount zone
  favorites". No module rows or commands change.
- [ ] In-game checklist for the user (one `/reload`, then): the in-game steps of Tasks 1-12 in order; report anything
  odd with the BugSack text. Commit each task separately once confirmed, messages as given in each task; CHANGELOG
  and README in the commit of the task they describe (or one `Docs: polish A notes` commit at the end).
