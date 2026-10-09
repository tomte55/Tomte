local addonName, ns = ...

-- Waypoints, pure logic: no WoW API calls (unit-tested with plain Lua). Distance and arrival text, the
-- marker's state (far, close-up card, hidden), distance scaling, the edge arrow's position and angle, and the
-- Classic/Minimal style presets. Distances are in yards everywhere; only the text converts to meters.

local atan2 = math.atan2 or math.atan -- WoW (5.1) has atan2; plain Lua 5.4 takes atan(y, x)

ns.WAY_YARD_TO_METER = 0.9144
ns.WAY_SCALE_DISTANCE = 600 -- yards where the marker is drawn at its set size
ns.WAY_SCALE_MIN = 0.7
ns.WAY_SCALE_MAX = 1.3

-- Style presets: picking one sets these keys; each can still be changed on its own afterwards.
ns.WAY_STYLES = {
	classic = { beam = true, footer = "all", card = true, arrow = true, scale = 1 },
	minimal = { beam = false, footer = "distance", card = true, arrow = true, scale = 0.85 },
}
ns.WAY_STYLE_ORDER = { "classic", "minimal" }
ns.WAY_STYLE_NAMES = { classic = "Classic", minimal = "Minimal" }

ns.WAY_FOOTERS = { "all", "distance", "time", "name", "none" }
ns.WAY_FOOTER_NAMES = {
	all = "Distance, arrival and name",
	distance = "Distance",
	time = "Arrival time",
	name = "Name",
	none = "Nothing",
}

-- Guard directions: what a guard's directions do (Guard.lua).
ns.WAY_GUARD_MODES = { "never", "ask", "always" }
ns.WAY_GUARD_NAMES = { never = "Never", ask = "Ask", always = "Always" }

function ns.Way_ApplyStyle(db, style)
	local preset = ns.WAY_STYLES[style]
	if not preset then
		return false
	end
	db.style = style
	for key, value in pairs(preset) do
		db[key] = value
	end
	return true
end

-- 1234567 -> "1,234,567"
local function Thousands(n)
	local s = tostring(n)
	local headLength = (#s - 1) % 3 + 1
	return s:sub(1, headLength) .. s:sub(headLength + 1):gsub("%d%d%d", ",%0")
end

-- "1,240 yd", "850 m", "1.4 km". nil for a missing distance.
function ns.Way_FormatDistance(yards, metric)
	if not yards then
		return nil
	end
	if metric then
		local m = math.floor(yards * ns.WAY_YARD_TO_METER + 0.5)
		if m >= 1000 then
			return ("%.1f km"):format(m / 1000)
		end
		return m .. " m"
	end
	return Thousands(math.floor(yards + 0.5)) .. " yd"
end

-- Slider labels: a yard setting shown in the user's unit, rounded to 5.
function ns.Way_FormatSetting(yards, metric)
	if metric then
		return (math.floor(yards * ns.WAY_YARD_TO_METER / 5 + 0.5) * 5) .. " m"
	end
	return yards .. " yd"
end

-- "42s", "3:05", "1:02:10". nil when unknown.
function ns.Way_FormatArrival(seconds)
	if not seconds or seconds < 0 then
		return nil
	end
	seconds = math.floor(seconds + 0.5)
	if seconds < 60 then
		return seconds .. "s"
	end
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

-- Arrival estimate from how fast the distance shrinks: an exponential moving average of the closing speed.
-- Moving away or standing still clears the estimate (no time shown) but keeps the average for later.
local SPEED_ALPHA = 0.25
local MIN_DT = 0.2 -- seconds between samples
local MIN_SPEED = 0.5 -- yards per second
local MAX_SECONDS = 3 * 3600

function ns.Way_NewArrival()
	return {}
end

function ns.Way_UpdateArrival(state, distance, now)
	if not distance then
		state.seconds = nil
		return nil
	end
	if not state.distance then
		state.distance, state.time = distance, now
		return state.seconds
	end
	local dt = now - state.time
	if dt < MIN_DT then
		return state.seconds
	end
	local speed = (state.distance - distance) / dt
	state.distance, state.time = distance, now
	if speed <= MIN_SPEED then
		state.seconds = nil
		return nil
	end
	state.speed = state.speed and (state.speed + SPEED_ALPHA * (speed - state.speed)) or speed
	local seconds = distance / state.speed
	state.seconds = seconds <= MAX_SECONDS and seconds or nil
	return state.seconds
end

-- The footer line under the marker for a footer mode. Missing parts are left out.
function ns.Way_FooterText(mode, distanceText, arrivalText, name)
	if mode == "none" then
		return nil
	elseif mode == "distance" then
		return distanceText
	elseif mode == "time" then
		return arrivalText
	elseif mode == "name" then
		return name
	end
	local parts = {}
	if distanceText then
		parts[#parts + 1] = distanceText
	end
	if arrivalText then
		parts[#parts + 1] = arrivalText
	end
	local line = #parts > 0 and table.concat(parts, "  ·  ") or nil
	if name and name ~= "" then
		return line and (name .. "\n" .. line) or name
	end
	return line
end

-- What the marker shows. info: { distance, valid, inQuestArea, offscreen, hasDetails }; opts: { card,
-- cardDistance, hideDistance }. Returns "none" (nothing tracked or no position), "hidden" (arrived or inside the
-- quest area), "offscreen" (edge arrow), "card" (close-up card) or "far" (diamond and footer). Targets without
-- details (objectives, description, route step) never get a card: it would only repeat the name.
function ns.Way_State(info, opts)
	if not info.valid or not info.distance then
		return "none"
	end
	if info.distance <= opts.hideDistance or info.inQuestArea then
		return "hidden"
	end
	if info.offscreen then
		return "offscreen"
	end
	if opts.card and info.hasDetails and info.distance <= opts.cardDistance then
		return "card"
	end
	return "far"
end

-- Marker size multiplier for a distance: larger up close, smaller far away, within WAY_SCALE_MIN..MAX.
function ns.Way_DistanceScale(distance)
	if not distance or distance <= 0 then
		return ns.WAY_SCALE_MAX
	end
	local scale = (ns.WAY_SCALE_DISTANCE / distance) ^ 0.35
	return math.min(math.max(scale, ns.WAY_SCALE_MIN), ns.WAY_SCALE_MAX)
end

-- Edge arrow: (dx, dy) is the target's offset from the screen center. Returns where the ray toward it crosses an
-- ellipse with radii rx, ry (Blizzard's ClampElliptical), and the rotation for an arrow texture that points up at
-- rotation 0.
function ns.Way_EdgePoint(dx, dy, rx, ry)
	if dx == 0 and dy == 0 then
		return 0, ry, 0
	end
	local ratio = rx * ry / math.sqrt(rx * rx * dy * dy + ry * ry * dx * dx)
	return dx * ratio, dy * ratio, atan2(dy, dx) - math.pi / 2
end

-- Shortest-way step from one angle toward another, by `rate` (0-1) of the difference.
function ns.Way_TurnToward(current, target, rate)
	local diff = (target - current + math.pi) % (2 * math.pi) - math.pi
	if math.abs(diff) < 0.01 then
		return target
	end
	return current + diff * rate
end
