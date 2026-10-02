# FlightTimer Round 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Estimate calibration, arrival alert, stop markers, arrival clock, and a nicer-looking bar.

**Architecture:** New pure functions in `Data.lua` (`CalibrateEstimate`, `StopFractions`, `ShouldAlert`, and `LookupTime` gets an offset plus a third return value), each unit-tested. `Core.lua` wires them into the flight lifecycle and adds `/ft alert`. `Bar.lua` is rewritten for the visual changes (border, icon, ticks, ETA, fades).

**Tech Stack:** WoW 12.1.0 Lua 5.1; local Lua 5.4.6 for tests.

**Spec:** `docs/superpowers/specs/2026-10-02-flighttimer-round1-design.md` (builds on `2026-10-02-flighttimer-design.md`)

## Global Constraints

- Same as the base plan: `local addonName, ns = ...`, one event frame, no new globals, Lua 5.1-compatible, `Data.lua` free of WoW API calls.
- Alert: `PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3, "Master")` + `FlashClientIcon()`, 5s before the expected end, once per flight.
- Calibration: window 10, ignore samples off by more than 50% of the raw estimate.
- Arrival clock text: `lands HH:MM` (24-hour).

## Review Focus

1. **Flight from a saved `db.current` written by the previous version** (no `origin`, no `rawEstimate`) → no error, no ticks unless the hops are known. (Task 1 test "StopFractions without origin".)
2. **Negative calibration making an estimate ≤ 0** → clamped to 1s. (Task 1 test.)
3. **Bar shown again while it is still fading out** (landing straight into a new flight, or `/ft unlock` right after landing) → bar visible at full alpha. (Task 2 in-game.)
4. **Early landing on a known route before the 5s mark** → the alert still fires once on landing, never twice. (Task 2 code: `alerted` flag.)
5. **`/reload` after the alert fired** → no second alert (the flag lives in `db.current`). (Task 2 in-game.)

---

### Task 1: Pure logic

**Files:** Modify `FlightTimer/Data.lua`, `FlightTimer/tests/test_data.lua`

**Produces:**
- `ns.LookupTime(db, path) -> t, isEstimate, raw` (estimates: `t = max(raw + offset, 1)`; exact: `raw = t`)
- `ns.CalibrateEstimate(db, rawEstimate, actual)`
- `ns.StopFractions(db, route) -> {fraction...} | nil`, where route has `path`, `points`, `dest`, optional `origin`
- `ns.ShouldAlert(expected, elapsed) -> bool`, `ns.ALERT_LEAD = 5`
- defaults: `calibration = { offset = 0, samples = 0 }`, `alert = true`

- [ ] Step 1: add the tests below (before the `if failures > 0` footer), plus a `near(a, b, label)` helper next to `eq`. Run them and watch them fail.

```lua
test("InitDB adds calibration and alert defaults, keeps alert=false", function()
	local db = ns.InitDB(nil)
	eq(db.calibration.offset, 0, "offset")
	eq(db.calibration.samples, 0, "samples")
	eq(db.alert, true, "alert")
	eq(ns.InitDB({ alert = false }).alert, false, "kept")
end)

test("LookupTime adds the calibration offset to estimates only", function()
	local db = ns.InitDB(nil)
	db.calibration.offset = 7
	db.hops["1>2"] = 40
	db.hops["3>2"] = 55
	local t, est, raw = ns.LookupTime(db, { 1, 2, 3 })
	eq(t, 102); eq(est, true, "est"); eq(raw, 95, "raw")
	db.routes["1>2>3"] = 100
	t, est, raw = ns.LookupTime(db, { 1, 2, 3 })
	eq(t, 100); eq(est, false, "exact"); eq(raw, 100, "raw exact")
end)

test("LookupTime never returns an estimate below 1s", function()
	local db = ns.InitDB(nil)
	db.calibration.offset = -10
	db.hops["1>2"] = 3
	eq(ns.LookupTime(db, { 1, 2 }), 1)
end)

test("CalibrateEstimate averages the first samples", function()
	local db = ns.InitDB(nil)
	ns.CalibrateEstimate(db, 100, 107)
	eq(db.calibration.offset, 7, "first"); eq(db.calibration.samples, 1, "n")
	ns.CalibrateEstimate(db, 100, 103)
	eq(db.calibration.offset, 5, "second"); eq(db.calibration.samples, 2, "n")
end)

test("CalibrateEstimate becomes a moving average after the window", function()
	local db = ns.InitDB(nil)
	db.calibration.samples = 10
	ns.CalibrateEstimate(db, 100, 110)
	eq(db.calibration.offset, 1); eq(db.calibration.samples, 10, "capped")
end)

test("CalibrateEstimate ignores outliers", function()
	local db = ns.InitDB(nil)
	ns.CalibrateEstimate(db, 100, 200)
	eq(db.calibration.offset, 0); eq(db.calibration.samples, 0, "n")
end)

test("StopFractions direct route has no stops", function()
	local db = ns.InitDB(nil)
	eq(#ns.StopFractions(db, { path = { 1, 2 }, points = {}, dest = { x = 1, y = 1 } }), 0)
end)

test("StopFractions uses hop times when all are known", function()
	local db = ns.InitDB(nil)
	db.hops["1>2"] = 30
	db.hops["3>2"] = 90
	local fr = ns.StopFractions(db, { path = { 1, 2, 3 }, points = { { index = 2, x = 0, y = 0 } }, dest = { x = 0, y = 0 } })
	near(fr[1], 0.25)
end)

test("StopFractions falls back to distance between flight masters", function()
	local db = ns.InitDB(nil)
	local route = {
		path = { 1, 2, 3 },
		origin = { x = 0, y = 0 },
		points = { { index = 2, x = 0.3, y = 0.4 } }, -- 0.5 from origin
		dest = { x = 0.3, y = 0.9 }, -- 0.5 from the stop
	}
	near(ns.StopFractions(db, route)[1], 0.5)
end)

test("StopFractions without origin and unknown hops is nil", function()
	local db = ns.InitDB(nil)
	eq(ns.StopFractions(db, { path = { 1, 2, 3 }, points = { { index = 2, x = 0, y = 0 } }, dest = { x = 1, y = 1 } }), nil)
end)

test("ShouldAlert fires 5s before the expected end", function()
	eq(ns.ShouldAlert(60, 54.9), false, "too early")
	eq(ns.ShouldAlert(60, 55), true, "at 5s")
	eq(ns.ShouldAlert(nil, 100), false, "recording")
end)
```

`near` helper:

```lua
local function near(actual, expected, label)
	if type(actual) ~= "number" or math.abs(actual - expected) > 1e-9 then
		error((label or "value") .. ": expected ~" .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end
```

- [ ] Step 2: implement in `Data.lua`:

```lua
ns.CALIBRATION_WINDOW = 10
ns.CALIBRATION_MAX_ERROR = 0.5 -- ignore samples off by more than this fraction of the estimate
ns.ALERT_LEAD = 5 -- seconds before the expected end to alert
```

Defaults gain `calibration = { offset = 0, samples = 0 }` and `alert = true`.

`LookupTime` (replace the existing function):

```lua
-- Returns seconds, isEstimate, raw (raw = estimate before calibration). nil when unknown.
function ns.LookupTime(db, path)
	local n = #path
	if n < 2 then
		return nil
	end
	local exact = db.routes[ns.RouteKey(path)]
	if exact then
		return exact, false, exact
	end
	local total = 0
	for i = 1, n - 1 do
		local t = db.hops[ns.HopKey(path[i], path[i + 1])] or db.hops[ns.HopKey(path[i + 1], path[i])]
		if not t then
			return nil
		end
		total = total + t
	end
	return math.max(total + db.calibration.offset, 1), true, total
end
```

New functions:

```lua
-- Estimates miss the takeoff and landing that pass-through hop timings don't include; learn that gap.
function ns.CalibrateEstimate(db, rawEstimate, actual)
	local err = actual - rawEstimate
	if math.abs(err) > rawEstimate * ns.CALIBRATION_MAX_ERROR then
		return
	end
	local c = db.calibration
	c.samples = math.min(c.samples + 1, ns.CALIBRATION_WINDOW)
	c.offset = c.offset + (err - c.offset) / c.samples
end

-- Fraction of the flight elapsed at each intermediate stop, in path order. nil when it can't be worked out.
function ns.StopFractions(db, route)
	local path = route.path
	local n = #path
	local legs = {}
	for i = 1, n - 1 do
		local t = db.hops[ns.HopKey(path[i], path[i + 1])] or db.hops[ns.HopKey(path[i + 1], path[i])]
		if not t then
			legs = nil
			break
		end
		legs[i] = t
	end
	if not legs then
		if not route.origin then
			return nil
		end
		local pts = { route.origin }
		for _, p in ipairs(route.points) do
			pts[#pts + 1] = p
		end
		pts[#pts + 1] = route.dest
		legs = {}
		for i = 1, n - 1 do
			local dx, dy = pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y
			legs[i] = math.sqrt(dx * dx + dy * dy)
		end
	end
	local total = 0
	for i = 1, n - 1 do
		total = total + legs[i]
	end
	local fractions = {}
	if total <= 0 then
		return fractions
	end
	local acc = 0
	for i = 1, n - 2 do
		acc = acc + legs[i]
		fractions[i] = acc / total
	end
	return fractions
end

function ns.ShouldAlert(expected, elapsed)
	return expected ~= nil and expected - elapsed <= ns.ALERT_LEAD
end
```

- [ ] Step 3: `lua FlightTimer/tests/test_data.lua` → `all passed`. Commit `FlightTimer: estimate calibration, stop fractions, alert trigger`.

### Task 2: Core wiring + bar rewrite

**Files:** Modify `FlightTimer/Core.lua`; rewrite `FlightTimer/Bar.lua`.

**Consumes:** Task 1. **Changes:** `ns.Bar_Start(destName, expected, isEstimate, startTime, stops)` gains `stops` (array of fractions or nil).

Core:
- `BuildRoute`: store `route.origin = { x, y }` for node 1.
- `StartFlight`: `local expected, isEstimate, raw = ns.LookupTime(...)`; `flight.expected = expected`; `flight.rawEstimate = isEstimate and raw or nil`; `stops = expected and ns.StopFractions(ns.db, flight)`; pass to `Bar_Start`.
- `Alert()`: sets `flight.alerted = true`; if `ns.db.alert`, play the sound and flash.
- OnUpdate while on taxi: `if not flight.alerted and ns.ShouldAlert(flight.expected, now - flight.start) then Alert() end`.
- `EndFlight`: on arrival, `CalibrateEstimate` when `flight.rawEstimate`; then `RecordFlight`. Afterwards `if not flight.alerted then Alert() end` (recording flights and early landings).
- `/ft alert` toggles `ns.db.alert`; add it to help.

Bar: border via `BackdropTemplate`, fill `Interface\RaidFrame\Raid-Bar-Hp-Fill`, icon `Interface\TaxiFrame\UI-Taxi-Icon-Green` left of the bar, tick textures (2px, bright while ahead and alpha 0.25 once passed), ETA font string under the bar right (`lands HH:MM`, only updated when it changes), fade-in 0.3s / fade-out 0.4s (fade-out `OnFinished` hides and resets alpha; `Bar_Start` cancels a running fade-out). The preview shows ticks at 0.35 and 0.7.

- [ ] `luac -p FlightTimer/*.lua`, tests pass, global-write scan shows only `FlightTimerDB`/`SLASH_FLIGHTTIMER1`. Commit `FlightTimer: arrival alert, stop markers, arrival clock, bar polish`.
- [ ] In-game test (user), see the spec's Testing section.
