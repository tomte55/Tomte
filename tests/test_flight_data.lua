-- Run from the AddOns folder: lua Tomte/tests/test_flight_data.lua
local ns = {}
assert(loadfile("Tomte/Modules/Flight/Data.lua"))("Tomte", ns)

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

local function near(actual, expected, label)
	if type(actual) ~= "number" or math.abs(actual - expected) > 1e-9 then
		error((label or "value") .. ": expected ~" .. tostring(expected) .. ", got " .. tostring(actual), 2)
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
	eq(tr.nextPoint, 2, "gave up on it after moving away")
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

test("PassTracker skips a missed waypoint and still times the next one", function()
	local tr = ns.NewPassTracker({
		{ index = 2, x = 0.45, y = 0.53 }, -- never within PASS_RADIUS
		{ index = 3, x = 0.55, y = 0.5 },
	})
	flyAlongX(tr, 0.5)
	eq(tr.passes[2], nil, "missed")
	eq(tr.passes[3], 15, "next")
end)

test("IsArrival with known position uses distance", function()
	eq(ns.IsArrival(0.005, 60, nil), true, "close")
	eq(ns.IsArrival(0.2, 60, 60), false, "far away")
end)

test("IsArrival rejects too-short flights", function()
	eq(ns.IsArrival(0, 3, nil), false)
end)

test("IsArrival without position compares against the expected time", function()
	eq(ns.IsArrival(nil, 30, 100), false, "early dismount")
	eq(ns.IsArrival(nil, 95, 100), true, "about on time")
	eq(ns.IsArrival(nil, 60, nil), true, "unknown route, nothing to protect")
end)

test("UpdateLanding ignores a short off-taxi blip", function()
	local w = {}
	eq(ns.UpdateLanding(w, true, 10, false), nil, "on taxi")
	eq(ns.UpdateLanding(w, false, 10.2, false), nil, "just went off")
	eq(ns.UpdateLanding(w, true, 10.4, false), nil, "back on")
	eq(ns.UpdateLanding(w, false, 11.0, false), nil, "off again, timer restarted")
	eq(ns.UpdateLanding(w, false, 11.6, false), nil, "only 0.6s off")
end)

test("UpdateLanding confirms after a steady second and reports when it started", function()
	local w = {}
	eq(ns.UpdateLanding(w, false, 20.0, false), nil)
	eq(ns.UpdateLanding(w, false, 20.6, false), nil)
	eq(ns.UpdateLanding(w, false, 21.0, false), 20.0)
end)

test("UpdateLanding never lands while suppressed (loading screen)", function()
	local w = {}
	eq(ns.UpdateLanding(w, false, 30, true), nil)
	eq(ns.UpdateLanding(w, false, 35, true), nil)
	eq(ns.UpdateLanding(w, false, 35.2, false), nil, "timer starts after suppression ends")
	eq(ns.UpdateLanding(w, false, 36.2, false), 35.2)
end)

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

test("CinematicWanted waits for takeoff and leaves before landing", function()
	eq(ns.CinematicWanted(nil, 1), false, "before delay")
	eq(ns.CinematicWanted(nil, 2), true, "unknown time, after delay")
	eq(ns.CinematicWanted(60, 30), true, "mid flight")
	eq(ns.CinematicWanted(60, 57), false, "inside end lead")
	eq(ns.CinematicWanted(60, 70), false, "overrun")
	eq(ns.CinematicWanted(15, 5), false, "short known flight")
	eq(ns.CinematicWanted(15, 5, 10), true, "allowed with a lower minimum")
	eq(ns.CinematicWanted(40, 5, 60), false, "blocked by a higher minimum")
end)

test("RecordStats counts, sums and keeps the longest", function()
	local db = ns.InitDB(nil)
	eq(db.stats.flights, 0, "fresh")
	eq(db.cinematic, true, "cinematic default")
	ns.RecordStats(db, 100, "A → B")
	ns.RecordStats(db, 60, "B → C")
	eq(db.stats.flights, 2, "count")
	eq(db.stats.seconds, 160, "sum")
	eq(db.stats.longest, 100, "longest")
	eq(db.stats.longestRoute, "A → B", "longest route")
end)

local function paceRoute()
	return {
		mapID = 5,
		path = { 1, 2, 3 },
		origin = { x = 0, y = 0 },
		points = { { index = 2, x = 0.3, y = 0.4 } }, -- 0.5 from origin
		dest = { x = 0.3, y = 0.9 }, -- 0.5 from the stop
	}
end

test("RecordPace accumulates seconds and distance per map", function()
	local db = ns.InitDB(nil)
	ns.RecordPace(db, paceRoute(), 100)
	ns.RecordPace(db, paceRoute(), 120)
	eq(db.paces[5].seconds, 220, "seconds")
	near(db.paces[5].distance, 2, "distance")
end)

test("RecordPace skips routes without positions", function()
	local db = ns.InitDB(nil)
	local route = paceRoute()
	route.origin = nil
	ns.RecordPace(db, route, 100)
	eq(db.paces[5], nil)
end)

test("LookupTime fills an unknown leg from the map pace, without calibration", function()
	local db = ns.InitDB(nil)
	db.calibration.offset = 7
	db.paces[5] = { seconds = 100, distance = 1 }
	db.hops["1>2"] = 40
	local t, est, raw, rough = ns.LookupTime(db, { 1, 2, 3 }, paceRoute())
	near(t, 90, "40 + 0.5 * 100")
	eq(est, true, "estimate")
	near(raw, 90, "raw")
	eq(rough, true, "rough")
end)

test("LookupTime estimates a never-flown route from pace alone", function()
	local db = ns.InitDB(nil)
	db.paces[5] = { seconds = 100, distance = 1 }
	near(ns.LookupTime(db, { 1, 2, 3 }, paceRoute()), 100)
end)

test("LookupTime without pace or route stays unknown", function()
	local db = ns.InitDB(nil)
	db.hops["1>2"] = 40
	eq(ns.LookupTime(db, { 1, 2, 3 }, paceRoute()), nil, "no pace for map")
	db.paces[5] = { seconds = 100, distance = 1 }
	eq(ns.LookupTime(db, { 1, 2, 3 }), nil, "no route given")
end)

test("LookupTime from hops only is not rough and keeps calibration", function()
	local db = ns.InitDB(nil)
	db.calibration.offset = 7
	db.paces[5] = { seconds = 100, distance = 1 }
	db.hops["1>2"] = 40
	db.hops["2>3"] = 50
	local t, est, raw, rough = ns.LookupTime(db, { 1, 2, 3 }, paceRoute())
	eq(t, 97); eq(raw, 90, "raw"); eq(rough, false, "rough")
end)

test("TimerText for countdown, estimate, overrun and recording", function()
	local text, fill, remaining = ns.TimerText(100, false, 40)
	eq(text, "01:00"); eq(fill, 0.6, "fill"); eq(remaining, 60, "remaining")
	eq(ns.TimerText(100, true, 40), "~01:00", "estimate")
	text, fill = ns.TimerText(100, true, 105)
	eq(text, "+00:05", "overrun"); eq(fill, 0, "empty")
	text, fill, remaining = ns.TimerText(nil, false, 75)
	eq(text, "01:15", "recording counts up"); eq(fill, nil, "no fill"); eq(remaining, nil, "no remaining")
end)

test("RecordStats tracks per-map time, departures and route counts", function()
	local db = ns.InitDB(nil)
	ns.RecordStats(db, 100, "A to B", "A", 7)
	ns.RecordStats(db, 50, "A to C", "A", 7)
	ns.RecordStats(db, 30, "A to B", "A", 9)
	eq(db.stats.byMap[7], 150, "map 7")
	eq(db.stats.byMap[9], 30, "map 9")
	eq(db.stats.departures["A"], 3, "departures")
	eq(db.stats.routeCounts["A to B"], 2, "route count")
end)

test("TopEntry returns the largest value", function()
	local k, v = ns.TopEntry({ a = 1, b = 5, c = 3 })
	eq(k, "b"); eq(v, 5)
	eq(ns.TopEntry({}), nil, "empty")
end)

test("OrbitFactor eases the orbit out before landing", function()
	eq(ns.OrbitFactor(nil, 500), 1, "recording keeps orbiting")
	eq(ns.OrbitFactor(60, 30), 1, "mid flight")
	eq(ns.OrbitFactor(60, 54), 1, "6s left")
	near(ns.OrbitFactor(60, 55.5), 0.5, "halfway through the ease")
	eq(ns.OrbitFactor(60, 57), 0, "at end lead")
	eq(ns.OrbitFactor(60, 80), 0, "overrun")
end)

test("RecordPace fades out flights older than the window", function()
	local db = ns.InitDB(nil)
	for _ = 1, 10 do
		ns.RecordPace(db, paceRoute(), 100) -- 100s per unit of distance
	end
	eq(db.paces[5].flights, 10, "full window")
	near(db.paces[5].seconds / db.paces[5].distance, 100, "slow pace")
	for _ = 1, 10 do
		ns.RecordPace(db, paceRoute(), 80) -- 25% faster taxi
	end
	local pace = db.paces[5].seconds / db.paces[5].distance
	near(pace, 100 * 0.9 ^ 10 + 80 * (1 - 0.9 ^ 10), "pace after faster flights")
	eq(db.paces[5].flights, 10, "window stays full")
end)

test("RecordPace shrinks pace data saved without a flight count to one window", function()
	local db = ns.InitDB(nil)
	db.paces[5] = { seconds = 10000, distance = 100 } -- lifetime totals (pace 100) from before the window
	ns.RecordPace(db, paceRoute(), 80)
	-- The old pace counts as 9 flights' worth of this flight's distance (1), then the new flight is added.
	near(db.paces[5].seconds, 980, "seconds")
	near(db.paces[5].distance, 10, "distance")
	eq(db.paces[5].flights, 10, "flights")
end)

if failures > 0 then
	print(failures .. " test(s) failed")
	os.exit(1)
end
print("all passed")
