# FlightTimer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Account-wide WoW flight path timer: per-hop learning, flight map tooltip with expected time, and an in-flight bar that records (unknown route) or counts down (known/estimated route).

**Architecture:** Pure logic (keys, lookup, recording, time formatting, waypoint pass detection) lives in `Data.lua` with no WoW API calls so it can be unit-tested with plain Lua 5.4. `Core.lua` owns the single event frame, SavedVariables init, slash command, and the flight state machine (pending → flying → landed). `Bar.lua` is the in-flight status bar. `Tooltip.lua` hooks both flight map UIs.

**Tech Stack:** WoW retail 12.1.0 Lua (5.1 dialect), no libraries. Local Lua 5.4.6 (`lua`, `luac` on PATH) for unit tests and syntax checks only.

**Spec:** `docs/superpowers/specs/2026-10-02-flighttimer-design.md`

**Deviation from spec (file roles):** pure logic moved from `Core.lua` into a new `Data.lua` for testability; slash command lives in `Core.lua` instead of `Tooltip.lua`. Overtime renders as `+00:05` (same formatter as everything else) rather than `+0:05`.

## Global Constraints

- TOC `## Interface: 120100`.
- `local addonName, ns = ...` in every file. No globals except `FlightTimerDB` and `SLASH_FLIGHTTIMER1` / `SlashCmdList.FLIGHTTIMER`.
- One event frame, dispatching `self[event](self, ...)`.
- Do not modify any third-party addon folder.
- Code must be Lua 5.1-compatible (no `//`, no `goto`, no integer-only semantics, no `<const>`).
- `Data.lua` must not reference any WoW global at file load time or inside its functions.
- Time format: `mm:ss` with leading zero, `h:mm:ss` when ≥ 1 hour. Estimate prefix `~`. Unknown → no tooltip line.
- Route key = full node path joined with `>` (e.g. `"12>34>56"`); hop key = `"a>b"`.

## Review Focus

1. **`/reload` mid-flight** → bar comes back with correct elapsed/remaining and the flight is still saved on landing. (Task 3, in-game step.)
2. **Early landing / dismounting away from the destination** → nothing saved, bar hides. (Task 3, in-game step.)
3. **Intermediate waypoint never comes within pass radius** (pin offset from spline, or position nil) → hop timings skipped, route total still saved, no error. (Task 1 unit tests.)
4. **Route the addon can't resolve** (map layer transition, missing slot) → no Lua error, no bar, no tooltip line. (Task 3/4, `BuildRoute` returns nil; in-game step.)
5. **Flight overruns its estimate** → bar empty, text `+00:05` counting up. (Task 2, preview overrun step.)

---

### Task 1: Pure logic (`Data.lua`) + unit tests

**Files:**
- Create: `FlightTimer/Data.lua`
- Test: `FlightTimer/tests/test_data.lua` (not listed in TOC, WoW never loads it)

**Interfaces:**
- Produces:
  - `ns.defaults` (table)
  - `ns.InitDB(db) -> db` — merges defaults into `db` (or a new table), returns it
  - `ns.HopKey(a, b) -> string`, `ns.RouteKey(path) -> string`
  - `ns.LookupTime(db, path) -> seconds|nil, isEstimate|nil`
  - `ns.RecordFlight(db, path, total, passes)` — `passes[i]` = elapsed seconds when passing `path[i]` (intermediate indices only)
  - `ns.FormatTime(seconds) -> string`
  - `ns.NewPassTracker(points) -> tracker` — `points` = array of `{ index = pathIndex, x = n, y = n }`
  - `ns.UpdatePassTracker(tracker, x, y, t)` — fills `tracker.passes[index] = t`

- [ ] **Step 1: Write the failing tests**

`FlightTimer/tests/test_data.lua`:

```lua
-- Run from the AddOns folder: lua FlightTimer/tests/test_data.lua
local ns = {}
assert(loadfile("FlightTimer/Data.lua"))("FlightTimer", ns)

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

test("FormatTime", function()
	eq(ns.FormatTime(0), "00:00")
	eq(ns.FormatTime(83), "01:23")
	eq(ns.FormatTime(83.4), "01:23")
	eq(ns.FormatTime(83.6), "01:24")
	eq(ns.FormatTime(59.5), "01:00")
	eq(ns.FormatTime(3725), "1:02:05")
end)

test("keys", function()
	eq(ns.HopKey(1, 2), "1>2")
	eq(ns.RouteKey({ 1, 2, 3 }), "1>2>3")
end)

test("InitDB fresh", function()
	local db = ns.InitDB(nil)
	eq(type(db.routes), "table", "routes")
	eq(type(db.hops), "table", "hops")
	eq(db.frame.locked, true, "locked")
	eq(db.frame.point, "TOP", "point")
end)

test("InitDB keeps existing values and adds missing keys", function()
	local db = ns.InitDB({ routes = { ["1>2"] = 50 }, frame = { locked = false } })
	eq(db.routes["1>2"], 50, "route kept")
	eq(type(db.hops), "table", "hops added")
	eq(db.frame.locked, false, "locked kept")
	eq(db.frame.point, "TOP", "point added")
end)

test("InitDB does not share default tables between calls", function()
	local a = ns.InitDB(nil)
	a.routes["1>2"] = 10
	local b = ns.InitDB(nil)
	eq(b.routes["1>2"], nil)
end)

test("LookupTime unknown / degenerate", function()
	local db = ns.InitDB(nil)
	eq(ns.LookupTime(db, { 1, 2 }), nil, "unknown")
	eq(ns.LookupTime(db, { 1 }), nil, "single node")
	eq(ns.LookupTime(db, {}), nil, "empty")
end)

test("LookupTime exact route is not an estimate", function()
	local db = ns.InitDB(nil)
	db.routes["1>2>3"] = 100
	local t, est = ns.LookupTime(db, { 1, 2, 3 })
	eq(t, 100); eq(est, false, "isEstimate")
end)

test("LookupTime sums hops and falls back to reverse", function()
	local db = ns.InitDB(nil)
	db.hops["1>2"] = 40
	db.hops["3>2"] = 55 -- only reverse of 2>3 known
	local t, est = ns.LookupTime(db, { 1, 2, 3 })
	eq(t, 95); eq(est, true, "isEstimate")
end)

test("LookupTime missing hop is unknown", function()
	local db = ns.InitDB(nil)
	db.hops["1>2"] = 40
	eq(ns.LookupTime(db, { 1, 2, 3 }), nil)
end)

test("RecordFlight direct route", function()
	local db = ns.InitDB(nil)
	ns.RecordFlight(db, { 1, 2 }, 60.4, {})
	eq(db.routes["1>2"], 60, "route")
	eq(db.hops["1>2"], 60, "hop")
	local t, est = ns.LookupTime(db, { 1, 2 })
	eq(t, 60); eq(est, false, "exact")
	t, est = ns.LookupTime(db, { 2, 1 })
	eq(t, 60); eq(est, true, "reverse is estimate")
end)

test("RecordFlight multi-hop with pass times teaches each hop", function()
	local db = ns.InitDB(nil)
	ns.RecordFlight(db, { 1, 2, 3 }, 100.2, { [2] = 40.3 })
	eq(db.routes["1>2>3"], 100, "route")
	eq(db.hops["1>2"], 40, "hop 1")
	eq(db.hops["2>3"], 60, "hop 2")
	local t, est = ns.LookupTime(db, { 1, 2 })
	eq(t, 40); eq(est, true, "A>B estimate")
	t, est = ns.LookupTime(db, { 3, 2, 1 })
	eq(t, 100); eq(est, true, "reverse route estimate")
end)

test("RecordFlight without pass times saves only the route", function()
	local db = ns.InitDB(nil)
	ns.RecordFlight(db, { 1, 2, 3 }, 100, {})
	eq(db.routes["1>2>3"], 100, "route")
	eq(db.hops["1>2"], nil, "hop 1")
	eq(db.hops["2>3"], nil, "hop 2")
end)

test("RecordFlight ignores impossible pass times", function()
	local db = ns.InitDB(nil)
	ns.RecordFlight(db, { 1, 2, 3 }, 100, { [2] = 120 })
	eq(db.hops["1>2"], 120, "hop 1 still positive")
	eq(db.hops["2>3"], nil, "negative hop skipped")
end)

test("RecordFlight overwrites old measurement", function()
	local db = ns.InitDB(nil)
	ns.RecordFlight(db, { 1, 2 }, 60, {})
	ns.RecordFlight(db, { 1, 2 }, 70, {})
	eq(db.routes["1>2"], 70)
end)

local function flyAlongX(tracker, y)
	-- x from 0.40 to 0.60 in steps of 0.01; t = step number
	for i = 0, 20 do
		ns.UpdatePassTracker(tracker, 0.40 + i * 0.01, y, i)
	end
end

test("PassTracker records closest approach", function()
	local tr = ns.NewPassTracker({ { index = 2, x = 0.5, y = 0.5 } })
	flyAlongX(tr, 0.5)
	eq(tr.passes[2], 10)
end)

test("PassTracker ignores a waypoint that is never close", function()
	local tr = ns.NewPassTracker({ { index = 2, x = 0.5, y = 0.5 } })
	flyAlongX(tr, 0.6)
	eq(tr.passes[2], nil)
	eq(tr.nextPoint, 1, "still waiting on first point")
end)

test("PassTracker handles waypoints in order", function()
	local tr = ns.NewPassTracker({
		{ index = 2, x = 0.45, y = 0.5 },
		{ index = 3, x = 0.55, y = 0.5 },
	})
	flyAlongX(tr, 0.5)
	eq(tr.passes[2], 5, "first")
	eq(tr.passes[3], 15, "second")
end)

test("PassTracker with no points is a no-op", function()
	local tr = ns.NewPassTracker({})
	flyAlongX(tr, 0.5)
	eq(next(tr.passes), nil)
end)

if failures > 0 then
	print(failures .. " test(s) failed")
	os.exit(1)
end
print("all passed")
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `D:/World of Warcraft/_retail_/Interface/AddOns`): `lua FlightTimer/tests/test_data.lua`
Expected: error `cannot open FlightTimer/Data.lua` (assertion on loadfile).

- [ ] **Step 3: Implement `FlightTimer/Data.lua`**

```lua
local addonName, ns = ...

-- Pure logic only: no WoW API calls in this file (unit-tested with plain Lua).

ns.PASS_RADIUS = 0.015 -- normalized map distance that counts as "at" a waypoint
ns.PASS_MARGIN = 0.002 -- how far past the closest point before committing the pass

ns.defaults = {
	routes = {},
	hops = {},
	frame = { point = "TOP", relPoint = "TOP", x = 0, y = -150, locked = true },
}

local function MergeDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			MergeDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns.InitDB(db)
	return MergeDefaults(ns.defaults, db or {})
end

function ns.HopKey(a, b)
	return a .. ">" .. b
end

function ns.RouteKey(path)
	return table.concat(path, ">")
end

local function Round(x)
	return math.floor(x + 0.5)
end

-- Returns seconds, isEstimate. nil when unknown.
function ns.LookupTime(db, path)
	local n = #path
	if n < 2 then
		return nil
	end
	local exact = db.routes[ns.RouteKey(path)]
	if exact then
		return exact, false
	end
	local total = 0
	for i = 1, n - 1 do
		local t = db.hops[ns.HopKey(path[i], path[i + 1])] or db.hops[ns.HopKey(path[i + 1], path[i])]
		if not t then
			return nil
		end
		total = total + t
	end
	return total, true
end

-- passes[i] = elapsed seconds when passing path[i], for intermediate nodes (1 < i < #path).
function ns.RecordFlight(db, path, total, passes)
	local n = #path
	db.routes[ns.RouteKey(path)] = Round(total)
	local function At(i)
		if i == 1 then
			return 0
		elseif i == n then
			return total
		end
		return passes[i]
	end
	for i = 1, n - 1 do
		local a, b = At(i), At(i + 1)
		if a and b and b > a then
			db.hops[ns.HopKey(path[i], path[i + 1])] = Round(b - a)
		end
	end
end

function ns.FormatTime(seconds)
	seconds = Round(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

-- Detects when the player passes each waypoint (in order) by closest approach.
function ns.NewPassTracker(points)
	return { points = points, nextPoint = 1, passes = {} }
end

function ns.UpdatePassTracker(tracker, x, y, t)
	local p = tracker.points[tracker.nextPoint]
	if not p then
		return
	end
	local dx, dy = x - p.x, y - p.y
	local d = math.sqrt(dx * dx + dy * dy)
	if not tracker.best or d < tracker.best then
		tracker.best, tracker.bestTime = d, t
	elseif tracker.best <= ns.PASS_RADIUS and d > tracker.best + ns.PASS_MARGIN then
		tracker.passes[p.index] = tracker.bestTime
		tracker.nextPoint = tracker.nextPoint + 1
		tracker.best, tracker.bestTime = nil, nil
	end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua FlightTimer/tests/test_data.lua`
Expected: every line `ok   ...`, final line `all passed`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add FlightTimer/Data.lua FlightTimer/tests/test_data.lua
git commit -m "FlightTimer: pure route/hop logic with unit tests"
```

---

### Task 2: TOC, Core skeleton, in-flight bar, `/ft`

**Files:**
- Create: `FlightTimer/FlightTimer.toc`
- Create: `FlightTimer/Core.lua`
- Create: `FlightTimer/Bar.lua`

**Interfaces:**
- Consumes: `ns.InitDB`, `ns.FormatTime` (Task 1)
- Produces:
  - `ns.db` (= `FlightTimerDB`)
  - `ns.eventFrame` (the one event frame; Task 3 adds handlers to it)
  - `ns.Bar_Init()`
  - `ns.Bar_Start(destName, expected|nil, isEstimate, startTime)` — `startTime` is a `GetTime()` value
  - `ns.Bar_Stop()`
  - `ns.Bar_SetLocked(locked)`

- [ ] **Step 1: Create `FlightTimer/FlightTimer.toc`**

```
## Interface: 120100
## Title: FlightTimer
## Notes: Times flight paths account-wide and shows a countdown while flying.
## Author: tomte55
## Version: 1.0.0
## IconTexture: Interface\Icons\INV_Misc_PocketWatch_01
## SavedVariables: FlightTimerDB

Data.lua
Core.lua
Bar.lua
Tooltip.lua
```

(`Tooltip.lua` doesn't exist until Task 4; WoW just skips a missing file with no error, so this is safe.)

- [ ] **Step 2: Create `FlightTimer/Core.lua`**

```lua
local addonName, ns = ...

local PREFIX = "|cff66ccffFlightTimer|r: "

local f = CreateFrame("Frame")
ns.eventFrame = f
f:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
f:RegisterEvent("ADDON_LOADED")

function f:ADDON_LOADED(name)
	if name == addonName then
		FlightTimerDB = ns.InitDB(FlightTimerDB)
		ns.db = FlightTimerDB
		ns.Bar_Init()
	end
end

SLASH_FLIGHTTIMER1 = "/ft"
SlashCmdList.FLIGHTTIMER = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "lock" then
		ns.Bar_SetLocked(true)
		print(PREFIX .. "bar locked.")
	elseif cmd == "unlock" then
		ns.Bar_SetLocked(false)
		print(PREFIX .. "drag the bar, then /ft lock.")
	elseif cmd == "reset" then
		wipe(ns.db.routes)
		wipe(ns.db.hops)
		print(PREFIX .. "all recorded flight times cleared.")
	else
		print(PREFIX .. "commands:")
		print("  /ft lock | unlock - move the flight bar")
		print("  /ft reset - forget all recorded flight times")
	end
end
```

- [ ] **Step 3: Create `FlightTimer/Bar.lua`**

```lua
local addonName, ns = ...

local WIDTH, HEIGHT = 240, 20
local COLOR_COUNTDOWN = { 0.2, 0.75, 0.25 }
local COLOR_RECORDING = { 0.75, 0.2, 0.1 }
local SWEEP_PERIOD = 2 -- seconds for the recording spark to cross the bar
local PREVIEW_SECONDS = 90

local bar
local active -- { destName, expected, isEstimate, start, preview }

local function SavePosition()
	local point, _, relPoint, x, y = bar:GetPoint()
	local pos = ns.db.frame
	pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
end

local function SetMode(recording)
	local c = recording and COLOR_RECORDING or COLOR_COUNTDOWN
	bar:SetStatusBarColor(c[1], c[2], c[3])
	bar.dot:SetShown(recording)
	bar.rec:SetShown(recording)
	bar.spark:SetShown(recording)
	bar.name:ClearAllPoints()
	if recording then
		bar.pulse:Play()
		bar.name:SetPoint("LEFT", bar.rec, "RIGHT", 6, 0)
	else
		bar.pulse:Stop()
		bar.name:SetPoint("LEFT", bar, "LEFT", 6, 0)
	end
	bar.name:SetPoint("RIGHT", bar.time, "LEFT", -6, 0)
end

local function OnUpdate(self)
	if not active then
		return
	end
	local elapsed = GetTime() - active.start
	if active.expected then
		local remaining = active.expected - elapsed
		if remaining >= 0 then
			self:SetValue(remaining / active.expected)
			self.time:SetText((active.isEstimate and "~" or "") .. ns.FormatTime(remaining))
		else
			self:SetValue(0)
			self.time:SetText("+" .. ns.FormatTime(-remaining))
		end
	else
		self:SetValue(1)
		local frac = (elapsed % SWEEP_PERIOD) / SWEEP_PERIOD
		self.spark:SetPoint("CENTER", self, "LEFT", frac * self:GetWidth(), 0)
		self.time:SetText(ns.FormatTime(elapsed))
	end
end

local function ShowPreview()
	ns.Bar_Start("Drag me, then /ft lock", PREVIEW_SECONDS, false, GetTime())
	active.preview = true
end

function ns.Bar_Init()
	bar = CreateFrame("StatusBar", nil, UIParent)
	bar:SetSize(WIDTH, HEIGHT)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 1)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	bar:SetScript("OnUpdate", OnUpdate)

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bg:SetColorTexture(0, 0, 0, 0.6)

	bar.spark = bar:CreateTexture(nil, "OVERLAY", nil, -1)
	bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	bar.spark:SetBlendMode("ADD")
	bar.spark:SetSize(24, HEIGHT * 2)

	bar.dot = bar:CreateTexture(nil, "OVERLAY")
	bar.dot:SetSize(10, 10)
	bar.dot:SetPoint("LEFT", bar, "LEFT", 5, 0)
	bar.dot:SetColorTexture(1, 0.15, 0.15)
	local mask = bar:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(bar.dot)
	bar.dot:AddMaskTexture(mask)

	bar.pulse = bar.dot:CreateAnimationGroup()
	bar.pulse:SetLooping("BOUNCE")
	local fade = bar.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.15)
	fade:SetDuration(0.6)

	bar.rec = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.rec:SetPoint("LEFT", bar.dot, "RIGHT", 3, 0)
	bar.rec:SetText("REC")
	bar.rec:SetTextColor(1, 0.35, 0.35)

	bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bar.time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

	bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.name:SetJustifyH("LEFT")
	bar.name:SetWordWrap(false)

	local pos = ns.db.frame
	bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	bar:EnableMouse(not pos.locked)
	bar:Hide()
	if not pos.locked then
		ShowPreview()
	end
end

function ns.Bar_Start(destName, expected, isEstimate, startTime)
	if expected and expected <= 0 then
		expected = nil
	end
	active = { destName = destName, expected = expected, isEstimate = isEstimate, start = startTime }
	bar.name:SetText(destName)
	SetMode(expected == nil)
	OnUpdate(bar)
	bar:Show()
end

function ns.Bar_Stop()
	active = nil
	bar.pulse:Stop()
	if ns.db.frame.locked then
		bar:Hide()
	else
		ShowPreview()
	end
end

function ns.Bar_SetLocked(locked)
	ns.db.frame.locked = locked
	bar:EnableMouse(not locked)
	if locked then
		if active and active.preview then
			ns.Bar_Stop()
		end
	elseif not active then
		ShowPreview()
	end
end
```

- [ ] **Step 4: Syntax check + unit tests still pass**

Run: `luac -p FlightTimer/Data.lua FlightTimer/Core.lua FlightTimer/Bar.lua && lua FlightTimer/tests/test_data.lua`
Expected: no output from `luac`, then `all passed`.

- [ ] **Step 5: In-game test (user)**

1. `/reload`. No BugSack errors. The bar should not be visible.
2. `/ft` → help lines print.
3. `/ft unlock` → green bar "Drag me, then /ft lock" counting down from `01:30`. Drag it somewhere.
4. Leave it ~90s → bar empties, text becomes `+00:01`, `+00:02`… (Review Focus 5).
5. `/ft lock` → bar hides. `/reload`, `/ft unlock` → bar appears at the dragged position. `/ft lock`.

- [ ] **Step 6: Commit (after user confirms)**

```bash
git add FlightTimer/FlightTimer.toc FlightTimer/Core.lua FlightTimer/Bar.lua
git commit -m "FlightTimer: TOC, movable flight bar, /ft command"
```

---

### Task 3: Flight tracking

**Files:**
- Modify: `FlightTimer/Core.lua` (add route building, takeoff hook, state machine, reload resume)

**Interfaces:**
- Consumes: `ns.LookupTime`, `ns.RecordFlight`, `ns.NewPassTracker`, `ns.UpdatePassTracker` (Task 1); `ns.Bar_Start`, `ns.Bar_Stop`, `ns.eventFrame` (Task 2)
- Produces:
  - `ns.BuildRoute(destSlot) -> route|nil` where `route = { mapID, path = {nodeID...}, destName, points = { {index, x, y} ... } (intermediate nodes), dest = { x, y } }`. Only valid while a taxi map is open.
  - `FlightTimerDB.current` — the active flight (persisted for `/reload`), cleared on landing.

- [ ] **Step 1: Add constants and route building to `Core.lua`** (insert after the `PREFIX` line)

```lua
local TICK = 0.2 -- seconds between taxi/position checks
local START_TIMEOUT = 10 -- seconds to wait for the taxi to start after TakeTaxiNode
local LAND_RADIUS = 0.02 -- normalized map distance from destination that counts as arrived
local MIN_FLIGHT = 5 -- shorter flights are discarded
local MAX_RESUME_AGE = 3600 -- don't resume a saved flight older than this

local pending -- route picked on the taxi map, waiting for UnitOnTaxi
local flight -- active flight (same table as ns.db.current)
local tracker

-- Resolves the hop path to a destination slot. Only valid while the taxi map is open.
function ns.BuildRoute(destSlot)
	local mapID = GetTaxiMapID()
	if not mapID then
		return nil
	end
	local bySlot = {}
	for _, info in ipairs(C_TaxiMap.GetAllTaxiNodes(mapID)) do
		bySlot[info.slotIndex] = info
	end
	local numHops = GetNumRoutes(destSlot)
	if not numHops or numHops < 1 then
		return nil
	end
	local nodes = { bySlot[TaxiGetNodeSlot(destSlot, 1, true)] }
	if not nodes[1] then
		return nil
	end
	for hop = 1, numHops do
		local info = bySlot[TaxiGetNodeSlot(destSlot, hop, false)]
		if not info then
			return nil
		end
		nodes[hop + 1] = info
	end

	local route = { mapID = mapID, path = {}, points = {}, destName = nodes[#nodes].name }
	for i, info in ipairs(nodes) do
		route.path[i] = info.nodeID
		local x, y = info.position:GetXY()
		if i == #nodes then
			route.dest = { x = x, y = y }
		elseif i > 1 then
			route.points[#route.points + 1] = { index = i, x = x, y = y }
		end
	end
	return route
end
```

- [ ] **Step 2: Add the flight state machine to `Core.lua`** (after `BuildRoute`)

```lua
local function PlayerPos(mapID)
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		return pos:GetXY()
	end
end

local function StartFlight(route, startTime)
	flight = route
	flight.start = startTime
	flight.passes = flight.passes or {}
	local remaining = {}
	for _, p in ipairs(flight.points) do
		if not flight.passes[p.index] then
			remaining[#remaining + 1] = p
		end
	end
	tracker = ns.NewPassTracker(remaining)
	tracker.passes = flight.passes
	ns.db.current = flight
	local expected, isEstimate = ns.LookupTime(ns.db, flight.path)
	ns.Bar_Start(flight.destName, expected, isEstimate, flight.start)
end

local function EndFlight()
	local duration = GetTime() - flight.start
	local arrived = true
	local x, y = PlayerPos(flight.mapID)
	if x then
		local dx, dy = x - flight.dest.x, y - flight.dest.y
		arrived = math.sqrt(dx * dx + dy * dy) <= LAND_RADIUS
	end
	if arrived and duration >= MIN_FLIGHT then
		ns.RecordFlight(ns.db, flight.path, duration, flight.passes)
	end
	flight, tracker = nil, nil
	ns.db.current = nil
	ns.Bar_Stop()
end

local sinceTick = 0
f:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick < TICK then
		return
	end
	sinceTick = 0
	if pending then
		if UnitOnTaxi("player") then
			local route = pending
			pending = nil
			StartFlight(route, GetTime())
		elseif GetTime() - pending.requested > START_TIMEOUT then
			pending = nil
		end
	elseif flight then
		if not UnitOnTaxi("player") then
			EndFlight()
		else
			local x, y = PlayerPos(flight.mapID)
			if x then
				ns.UpdatePassTracker(tracker, x, y, GetTime() - flight.start)
			end
		end
	end
end)

hooksecurefunc("TakeTaxiNode", function(slot)
	local route = ns.BuildRoute(slot)
	if route then
		route.requested = GetTime()
		pending = route
	end
end)

-- After /reload mid-flight: GetTime() keeps counting across reloads, so the saved start is still valid.
function f:PLAYER_ENTERING_WORLD()
	local cur = ns.db.current
	if flight or not cur then
		return
	end
	local age = GetTime() - (cur.start or -math.huge)
	if UnitOnTaxi("player") and age >= 0 and age < MAX_RESUME_AGE then
		StartFlight(cur, cur.start)
	else
		ns.db.current = nil
	end
end
```

- [ ] **Step 3: Register `PLAYER_ENTERING_WORLD`** — in `f:ADDON_LOADED`, inside the `if name == addonName then` block, after `ns.Bar_Init()`:

```lua
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
```

- [ ] **Step 4: Syntax check + unit tests**

Run: `luac -p FlightTimer/*.lua && lua FlightTimer/tests/test_data.lua`
Expected: no `luac` output, `all passed`.

- [ ] **Step 5: In-game test (user)**

1. `/reload`. Take a flight you've never timed (direct, no stops) → red bar, pulsing dot, `REC`, spark sweeping, time counting up, destination name shown.
2. After landing, bar hides. `/dump FlightTimerDB.routes` → one entry with ~the flight's seconds.
3. Fly the same route back → green countdown with `~` (reverse estimate). Fly the original route again → green countdown without `~`, ends near `00:00`.
4. Take a multi-stop flight A→B→C → after landing, `/dump FlightTimerDB.hops` shows both hops A>B and B>C (if one is missing, note which — Review Focus 3, the pass radius may need tuning).
5. Start a flight and `/reload` mid-air → bar returns with the right time; after landing the route is saved (Review Focus 1).
6. Start a recording flight and use the "land early" button on the flight bar (or vehicle exit) → bar hides, nothing new in `/dump FlightTimerDB.routes` (Review Focus 2).
7. No BugSack errors throughout, including flights with a map transition (Review Focus 4: no bar is fine there).

- [ ] **Step 6: Commit (after user confirms)**

```bash
git add FlightTimer/Core.lua
git commit -m "FlightTimer: record flights per route and per hop"
```

---

### Task 4: Flight map tooltips

**Files:**
- Create: `FlightTimer/Tooltip.lua`
- Modify: `FlightTimer/Core.lua` (`f:ADDON_LOADED` calls the hooks)

**Interfaces:**
- Consumes: `ns.BuildRoute` (Task 3), `ns.LookupTime`, `ns.FormatTime` (Task 1)
- Produces: `ns.HookFlightMap()`, `ns.HookTaxiFrame()`

Background (verified in Blizzard source, `Gethe/wow-ui-source` live):
- Modern map: `FlightMap_FlightPointPinMixin:OnMouseEnter()` builds the tooltip. `Blizzard_MapCanvas.lua` does `pin:SetScript("OnEnter", pin.OnMouseEnter)` **once at pin creation**, so the mixin must be hooked before pins exist (on `ADDON_LOADED` of the load-on-demand `Blizzard_FlightMap`); already-existing pins need `HookScript`.
- Legacy taxi frame: global `TaxiNodeOnButtonEnter(button)`, slot = `button:GetID()`, `TaxiNodeGetType(slot) == "REACHABLE"`.

- [ ] **Step 1: Create `FlightTimer/Tooltip.lua`**

```lua
local addonName, ns = ...

local function AddTimeLine(slot)
	local route = ns.BuildRoute(slot)
	if not route then
		return
	end
	local t, isEstimate = ns.LookupTime(ns.db, route.path)
	if not t then
		return
	end
	GameTooltip:AddLine((isEstimate and "~" or "") .. ns.FormatTime(t), 1, 1, 1)
	GameTooltip:Show()
end

local function OnPinEnter(pin)
	local data = pin.taxiNodeData
	if data and data.state == Enum.FlightPathState.Reachable then
		AddTimeLine(data.slotIndex)
	end
end

local flightMapHooked
function ns.HookFlightMap()
	if flightMapHooked then
		return
	end
	flightMapHooked = true
	-- Pins created from now on copy the hooked method into their OnEnter script.
	hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", OnPinEnter)
	-- Pins that already exist captured the original method; hook their script directly.
	if FlightMapFrame then
		for pin in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
			pin:HookScript("OnEnter", OnPinEnter)
		end
	end
end

function ns.HookTaxiFrame()
	if not TaxiNodeOnButtonEnter then
		return
	end
	hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
		local slot = button:GetID()
		if TaxiNodeGetType(slot) == "REACHABLE" then
			AddTimeLine(slot)
		end
	end)
end
```

- [ ] **Step 2: Wire hooks in `Core.lua` `f:ADDON_LOADED`** — replace the whole function with:

```lua
function f:ADDON_LOADED(name)
	if name == addonName then
		FlightTimerDB = ns.InitDB(FlightTimerDB)
		ns.db = FlightTimerDB
		ns.Bar_Init()
		ns.HookTaxiFrame()
		if C_AddOns.IsAddOnLoaded("Blizzard_FlightMap") then
			ns.HookFlightMap()
		end
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
	elseif name == "Blizzard_FlightMap" then
		ns.HookFlightMap()
	end
end
```

- [ ] **Step 3: Syntax check + unit tests**

Run: `luac -p FlightTimer/*.lua && lua FlightTimer/tests/test_data.lua`
Expected: no `luac` output, `all passed`.

- [ ] **Step 4: In-game test (user)**

1. `/reload`, open a flight master.
2. Hover a destination you've flown from here → white line `mm:ss` under the cost.
3. Hover a destination only known via hops/reverse → `~mm:ss`.
4. Hover a never-flown destination → tooltip unchanged.
5. Hover your current node / an unreachable node → unchanged, no errors.
6. If you know a flight master that opens the old-style square taxi window, check the same there.

- [ ] **Step 5: Commit (after user confirms)**

```bash
git add FlightTimer/Tooltip.lua FlightTimer/Core.lua
git commit -m "FlightTimer: show recorded flight time on flight map tooltips"
```
