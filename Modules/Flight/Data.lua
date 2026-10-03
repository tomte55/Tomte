local addonName, ns = ...

-- Pure logic only: no WoW API calls in this file (unit-tested with plain Lua).

ns.PASS_RADIUS = 0.015 -- normalized map distance that counts as "at" a waypoint
ns.PASS_MARGIN = 0.002 -- how far past the closest point before committing the pass
ns.SKIP_MARGIN = 0.03 -- how far past a never-reached waypoint before giving up on it
ns.LAND_RADIUS = 0.02 -- normalized map distance from destination that counts as arrived
ns.MIN_FLIGHT = 5 -- shorter flights are discarded
ns.CALIBRATION_WINDOW = 10
ns.CALIBRATION_MAX_ERROR = 0.5 -- ignore samples off by more than this fraction of the estimate
ns.ALERT_LEAD = 5 -- seconds before the expected end to alert
ns.CINEMATIC_DELAY = 2 -- seconds after takeoff before going cinematic
ns.CINEMATIC_END_LEAD = 3 -- seconds before the expected landing to bring the UI back
ns.CINEMATIC_MIN = 20 -- default: known flights shorter than this stay normal
ns.ARRIVAL_SHOT = 6 -- seconds before landing the orbit starts easing out
ns.ARRIVAL_RATIO = 0.8 -- without a position, a flight this close to the expected time counts as arrived
ns.PACE_WINDOW = 10 -- flights per map that make up the learned pace; older ones fade out (faster taxis show up)


ns.defaults = {
	routes = {},
	hops = {},
	frame = { point = "TOP", relPoint = "TOP", x = 0, y = -150, locked = true },
	calibration = { offset = 0, samples = 0 },
	alert = true,
	cinematic = true,
	orbit = true,
	showcase = true,
	music = false,
	musicTrack = 1,
	cinematicMin = 20,
	resumeDelay = 20, -- seconds of idle before a paused cinematic comes back
	paces = {}, -- [uiMapID] = { seconds, distance }: learned flight speed per taxi map
	stats = {
		flights = 0,
		seconds = 0,
		copper = 0,
		longest = 0,
		longestRoute = "",
		byMap = {}, -- [uiMapID] = seconds
		departures = {}, -- [flight master name] = count
		routeCounts = {}, -- [route name] = count
	},
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

local function NodePositions(route)
	if not (route and route.origin and route.dest) then
		return nil
	end
	local pts = { route.origin }
	for _, p in ipairs(route.points) do
		pts[#pts + 1] = p
	end
	pts[#pts + 1] = route.dest
	return pts
end

local function Distance(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Returns seconds, isEstimate, raw, rough. nil when unknown.
-- raw: estimate before calibration. rough: some leg was guessed from distance x the map's learned pace
-- (pace comes from whole flights, so it already includes takeoff/landing and gets no calibration).
-- route (optional) supplies mapID and node positions for the pace fallback.
function ns.LookupTime(db, path, route)
	local n = #path
	if n < 2 then
		return nil
	end
	local exact = db.routes[ns.RouteKey(path)]
	if exact then
		return exact, false, exact, false
	end
	local total, rough = 0, false
	local pace, pts
	for i = 1, n - 1 do
		local t = db.hops[ns.HopKey(path[i], path[i + 1])] or db.hops[ns.HopKey(path[i + 1], path[i])]
		if not t then
			if pace == nil then
				local learned = route and db.paces[route.mapID]
				pts = NodePositions(route)
				pace = (learned and pts and learned.distance > 0) and (learned.seconds / learned.distance) or false
			end
			if not pace then
				return nil
			end
			t = Distance(pts[i], pts[i + 1]) * pace
			rough = true
		end
		total = total + t
	end
	if rough then
		return math.max(total, 1), true, total, true
	end
	return math.max(total + db.calibration.offset, 1), true, total, false
end

function ns.RecordPace(db, route, duration)
	local pts = NodePositions(route)
	if not pts or not route.mapID then
		return
	end
	local distance = 0
	for i = 1, #pts - 1 do
		distance = distance + Distance(pts[i], pts[i + 1])
	end
	if distance <= 0 then
		return
	end
	local pace = db.paces[route.mapID] or { seconds = 0, distance = 0, flights = 0 }
	db.paces[route.mapID] = pace
	local flights = pace.flights
	if not flights then
		-- Saved before the window existed (lifetime totals): keep the old pace, but only as much of it as
		-- PACE_WINDOW - 1 flights of this length, so the new flight starts pulling it right away.
		local scale = (ns.PACE_WINDOW - 1) * distance / pace.distance
		pace.seconds, pace.distance = pace.seconds * scale, pace.distance * scale
		flights = ns.PACE_WINDOW - 1
	elseif flights >= ns.PACE_WINDOW then
		local keep = (ns.PACE_WINDOW - 1) / ns.PACE_WINDOW
		pace.seconds, pace.distance = pace.seconds * keep, pace.distance * keep
		flights = ns.PACE_WINDOW - 1
	end
	pace.seconds = pace.seconds + duration
	pace.distance = pace.distance + distance
	pace.flights = flights + 1
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
	elseif tracker.best > ns.PASS_RADIUS and d > tracker.best + ns.SKIP_MARGIN then
		-- Never got close enough and now clearly moving away: give up on it so later waypoints still get timed.
		tracker.nextPoint = tracker.nextPoint + 1
		tracker.best, tracker.bestTime = nil, nil
	end
end

-- distance: normalized distance to the destination at landing, or nil if the position is unknown.
-- expected: previously known time for the route, or nil.
function ns.IsArrival(distance, duration, expected)
	if duration < ns.MIN_FLIGHT then
		return false
	end
	if distance then
		return distance <= ns.LAND_RADIUS
	end
	if expected then
		return duration >= expected * ns.ARRIVAL_RATIO
	end
	return true
end

ns.LANDING_CONFIRM = 1 -- seconds off the taxi before a landing counts (loading screens blip UnitOnTaxi)

-- Returns the time the player first went off the taxi once that has held for LANDING_CONFIRM, else nil.
-- suppressed: true during/just after a loading screen, when UnitOnTaxi can't be trusted.
function ns.UpdateLanding(watch, onTaxi, now, suppressed)
	if onTaxi or suppressed then
		watch.offSince = nil
		return nil
	end
	watch.offSince = watch.offSince or now
	if now - watch.offSince >= ns.LANDING_CONFIRM then
		return watch.offSince
	end
end

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
	if n < 3 then
		return {}
	end
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
		local pts = NodePositions(route)
		if not pts then
			return nil
		end
		legs = {}
		for i = 1, n - 1 do
			legs[i] = Distance(pts[i], pts[i + 1])
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

function ns.CinematicWanted(expected, elapsed, minLength)
	if expected and expected < (minLength or ns.CINEMATIC_MIN) then
		return false
	end
	if elapsed < ns.CINEMATIC_DELAY then
		return false
	end
	if expected and expected - elapsed <= ns.CINEMATIC_END_LEAD then
		return false
	end
	return true
end

function ns.RecordStats(db, duration, routeName, originName, mapID)
	local stats = db.stats
	stats.flights = stats.flights + 1
	stats.seconds = stats.seconds + duration
	if duration > stats.longest then
		stats.longest = duration
		stats.longestRoute = routeName
	end
	if mapID then
		stats.byMap[mapID] = (stats.byMap[mapID] or 0) + duration
	end
	if originName then
		stats.departures[originName] = (stats.departures[originName] or 0) + 1
	end
	stats.routeCounts[routeName] = (stats.routeCounts[routeName] or 0) + 1
end

function ns.TopEntry(tbl)
	local bestKey, bestValue
	for k, v in pairs(tbl) do
		if not bestValue or v > bestValue then
			bestKey, bestValue = k, v
		end
	end
	return bestKey, bestValue
end

-- Camera orbit speed multiplier: eases from 1 to 0 over the arrival shot, ending when the UI comes back.
function ns.OrbitFactor(expected, elapsed)
	if not expected then
		return 1
	end
	local remaining = expected - elapsed
	if remaining >= ns.ARRIVAL_SHOT then
		return 1
	end
	if remaining <= ns.CINEMATIC_END_LEAD then
		return 0
	end
	return (remaining - ns.CINEMATIC_END_LEAD) / (ns.ARRIVAL_SHOT - ns.CINEMATIC_END_LEAD)
end

-- Display text for the timer. Returns text, fill (0..1 remaining, nil when recording), remaining seconds (nil when recording).
function ns.TimerText(expected, isEstimate, elapsed)
	if not expected then
		return ns.FormatTime(elapsed), nil, nil
	end
	local remaining = expected - elapsed
	if remaining >= 0 then
		return (isEstimate and "~" or "") .. ns.FormatTime(remaining), remaining / expected, remaining
	end
	return "+" .. ns.FormatTime(-remaining), 0, remaining
end
