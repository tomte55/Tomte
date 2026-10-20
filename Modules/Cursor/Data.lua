local addonName, ns = ...

-- Cursor highlight: pure logic (no WoW API calls; unit-tested in tests/test_cursor.lua). Shake detection from a
-- history of cursor samples, the ring's size and opacity over time after a shake, and the trail's fading dots.
-- Positions are in UIParent units (screen pixels divided by UIParent's effective scale), times in seconds.

-- Shake detection. A shake is quick back-and-forth movement: within the window, the cursor turns around at least
-- MIN_REVERSALS times along one axis, each leg between turns at least MIN_LEG long, and travels MIN_DISTANCE in all.
-- Measured against a 768-unit-tall UI (the height at UI scale 1 on any screen): a fast flick of the wrist covers
-- 60 to 200 units per leg, ordinary aiming at a button rarely turns around three times in half a second.
local WINDOW = 0.5
local MIN_REVERSALS = 3
local MIN_LEG = 25
local MIN_DISTANCE = 250
local JITTER = 2 -- steps shorter than this along an axis neither start a leg nor turn it around

-- The ring after a shake: grows to POP times its size, stays big while the shaking goes on, shrinks back once it
-- stops, then fades out after HOLD seconds of calm. Shake detection itself lags up to WINDOW behind the hand, so
-- the ring is gone about a second after the mouse stops.
local POP = 2.4
local GROW = 0.15
local SHRINK = 0.35
local FADE_IN = 0.08
local HOLD = 0.6
local FADE_OUT = 0.4

ns.CURSOR_SHAKE_WINDOW = WINDOW

local function Clamp01(v)
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- Looked up at call time: Core.lua loads before this file in game, the unit test provides it.
local function Ease(p)
	return ns.Smoothstep(Clamp01(p))
end

-- Samples ------------------------------------------------------------------------------------------------------

-- Appends { t, x, y } to samples (oldest first) and drops samples older than the window. Returns samples.
function ns.Cursor_AddSample(samples, t, x, y, window)
	samples[#samples + 1] = { t = t, x = x, y = y }
	local cutoff = t - (window or WINDOW)
	local drop = 0
	while samples[drop + 1] and samples[drop + 1].t < cutoff do
		drop = drop + 1
	end
	if drop > 0 then
		local n = #samples
		for i = 1, n do
			samples[i] = samples[i + drop]
		end
	end
	return samples
end

-- Turns around along one axis ("x" or "y"): how many times the movement changed direction after a leg of at
-- least MIN_LEG, counting only when the new leg also reaches MIN_LEG.
local function Reversals(samples, axis)
	local count, sign, leg, pending = 0, 0, 0, false
	for i = 2, #samples do
		local d = samples[i][axis] - samples[i - 1][axis]
		if d > JITTER or d < -JITTER then
			local s = d > 0 and 1 or -1
			if s == sign then
				leg = leg + math.abs(d)
			else
				-- A turn: it counts once the previous leg was long enough and the new one gets long enough too.
				pending = sign ~= 0 and leg >= MIN_LEG
				sign, leg = s, math.abs(d)
			end
			if pending and leg >= MIN_LEG then
				count = count + 1
				pending = false
			end
		end
	end
	return count
end

local function PathLength(samples)
	local total = 0
	for i = 2, #samples do
		local dx, dy = samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y
		total = total + math.sqrt(dx * dx + dy * dy)
	end
	return total
end

-- Whether the samples (all inside the window, oldest first) are a shake.
function ns.Cursor_IsShake(samples)
	if #samples < 4 or PathLength(samples) < MIN_DISTANCE then
		return false
	end
	return Reversals(samples, "x") >= MIN_REVERSALS or Reversals(samples, "y") >= MIN_REVERSALS
end

-- Ring ---------------------------------------------------------------------------------------------------------

-- The ring after a shake that began at `began` and was last seen at `last`. Returns scale (1 = the size setting)
-- and alpha (0..1, times the opacity setting); alpha 0 means the shake look is over.
function ns.Cursor_ShakeLook(began, last, now)
	local calm = now - last
	if ns.Cursor_ShakeOver(last, now) then
		return 1, 0
	end
	local grown = Ease((now - began) / GROW)
	local shrunk = Ease(calm / SHRINK)
	local scale = 1 + (POP - 1) * grown * (1 - shrunk)
	local alpha = Clamp01((now - began) / FADE_IN) * (1 - Ease((calm - HOLD) / FADE_OUT))
	return scale, alpha
end

-- Whether the shake look last seen at `last` has fully faded out. Ask this rather than testing ShakeLook's alpha
-- for 0: the alpha is 0 on the very first frame of a shake too, before the fade-in.
function ns.Cursor_ShakeOver(last, now)
	return now - last >= HOLD + FADE_OUT
end

-- What the ring looks like now. state: steady (always, in combat or the test: shown at full opacity), shake
-- ({ began, last } or nil), hidden (mouse-look hides it). Returns scale and alpha; alpha 0 = hide the ring.
function ns.Cursor_Look(state, now)
	if state.hidden then
		return 1, 0
	end
	local scale, alpha = 1, 0
	if state.shake then
		scale, alpha = ns.Cursor_ShakeLook(state.shake.began, state.shake.last, now)
	end
	if state.steady then
		alpha = 1
	end
	return scale, alpha
end

-- Trail --------------------------------------------------------------------------------------------------------

-- Adds a dot where the cursor is when it moved at least `gap` from the newest dot; keeps at most `max` dots
-- (newest last). Returns points.
function ns.Cursor_TrailAdd(points, t, x, y, gap, max)
	local newest = points[#points]
	if newest then
		local dx, dy = x - newest.x, y - newest.y
		if dx * dx + dy * dy < gap * gap then
			return points
		end
	end
	points[#points + 1] = { t = t, x = x, y = y }
	while #points > max do
		table.remove(points, 1)
	end
	return points
end

-- Drops dots older than `life` seconds and returns how strong each remaining dot is (1 = just placed, toward 0 as
-- it ages), in the same order as points.
function ns.Cursor_TrailFade(points, now, life)
	while points[1] and now - points[1].t >= life do
		table.remove(points, 1)
	end
	local fade = {}
	for i, p in ipairs(points) do
		fade[i] = 1 - Clamp01((now - p.t) / life)
	end
	return fade
end
