local addonName, ns = ...

-- Cursor highlight: pure logic (no WoW API calls; unit-tested in tests/test_cursor.lua). Shake detection from a
-- history of cursor samples, the ring's size and opacity over time after a shake and its pulse, the trail's points
-- (spacing, aging, size and opacity per point, twinkle and spin), when the trail shows, the color modes with the
-- rainbow's hue, and the spell effects the trail can use.
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

-- The ring's pulse (a gentle breathing while it's shown).
local PULSE_PERIOD = 1.6 -- seconds per breath
local PULSE_SCALE = 0.08 -- grows and shrinks by this much of its size
local PULSE_DIM = 0.3 -- opacity dips by this much at the smallest point

-- Trail points. Sparkles flicker between TWINKLE_LOW and full size; stars turn as they age.
local TWINKLE_LOW = 0.45
local TWINKLE_SPEED = 22 -- radians per second: about three and a half flickers a second
local GOLDEN_ANGLE = 2.39 -- radians; spreads neighbouring points' twinkle and spin apart
local SPIN_SPEED = 3 -- radians per second

-- Spell effects fade out once the mouse has been still for IDLE_HOLD seconds, over IDLE_FADE.
local IDLE_HOLD = 0.25
local IDLE_FADE = 0.35

local RAINBOW_PERIOD = 3 -- seconds for the rainbow to go once round the color wheel

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
-- (newest last). Each dot gets a serial number `n` (counting up in points.serial) that keeps its twinkle and spin
-- its own. Returns points.
function ns.Cursor_TrailAdd(points, t, x, y, gap, max)
	local newest = points[#points]
	if newest then
		local dx, dy = x - newest.x, y - newest.y
		if dx * dx + dy * dy < gap * gap then
			return points
		end
	end
	points.serial = (points.serial or 0) + 1
	points[#points + 1] = { t = t, x = x, y = y, n = points.serial }
	while #points > max do
		table.remove(points, 1)
	end
	return points
end

-- Drops dots older than `life` seconds and returns how strong each remaining dot is (1 = just placed, toward 0 as
-- it ages), in the same order as points. `out` (optional) is reused for the result, so drawing every frame makes no
-- garbage.
function ns.Cursor_TrailFade(points, now, life, out)
	while points[1] and now - points[1].t >= life do
		table.remove(points, 1)
	end
	local fade = out or {}
	for i, p in ipairs(points) do
		fade[i] = 1 - Clamp01((now - p.t) / life)
	end
	for i = #points + 1, #fade do
		fade[i] = nil
	end
	return fade
end

-- A trail point's size and opacity from its strength f (1 = fresh, 0 = gone): `head` is a fresh point's size,
-- `taper` how much of it is lost by the tail (0 = all the same size, 1 = shrinks to nothing), `opacity` a fresh
-- point's opacity.
function ns.Cursor_TrailLook(f, head, taper, opacity)
	f = Clamp01(f)
	return head * (1 - taper * (1 - f)), f * opacity
end

-- Sparkles twinkle: a size and opacity factor (TWINKLE_LOW..1) that flickers with age, out of step per point.
function ns.Cursor_Twinkle(n, age)
	local s = math.sin(n * GOLDEN_ANGLE + age * TWINKLE_SPEED)
	return TWINKLE_LOW + (1 - TWINKLE_LOW) * (s * s)
end

-- Stars turn slowly as they age, each from its own starting angle. Radians.
function ns.Cursor_Spin(n, age)
	return (n * GOLDEN_ANGLE + age * SPIN_SPEED) % (2 * math.pi)
end

-- When the trail shows -----------------------------------------------------------------------------------------

-- How strongly the trail shows right now (0 = not at all: clear it). on: the Trail setting; mode: "ring" (only
-- while the ring shows, fading with it), "moving" (always) or "combat" (in combat); state: ringAlpha (the ring's
-- look alpha, 0..1), combat, hidden (mouse-look hides the cursor). Movement itself is the caller's: a still mouse
-- adds no points, so the trail fades on its own.
function ns.Cursor_TrailGate(on, mode, state)
	if not on or state.hidden then
		return 0
	end
	if mode == "moving" then
		return 1
	elseif mode == "combat" then
		return state.combat and 1 or 0
	end
	return Clamp01(state.ringAlpha or 0)
end

-- Spell effects fade out once the mouse has been still for IDLE_HOLD seconds, over IDLE_FADE; 0 = hide the model.
function ns.Cursor_IdleFade(idle)
	return 1 - Clamp01((idle - IDLE_HOLD) / IDLE_FADE)
end

-- Ring pulse ---------------------------------------------------------------------------------------------------

-- A gentle breathing while the ring is shown: scale and opacity factors over time.
function ns.Cursor_Pulse(now)
	local s = math.sin(now * 2 * math.pi / PULSE_PERIOD)
	return 1 + PULSE_SCALE * s, 1 - PULSE_DIM * (1 - s) / 2
end

-- Colors -------------------------------------------------------------------------------------------------------

-- The rainbow's hue (0..1) at time t: one full turn every RAINBOW_PERIOD seconds. The ring takes it at the current
-- time, each trail point at the time it was placed, so a moving trail shows the colors one after another.
function ns.Cursor_Hue(t)
	return (t / RAINBOW_PERIOD) % 1
end

-- A hue (0..1) at full saturation and brightness as r, g, b (0..1).
function ns.Cursor_HueRGB(h)
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	if i == 0 then
		return 1, f, 0
	elseif i == 1 then
		return 1 - f, 1, 0
	elseif i == 2 then
		return 0, 1, f
	elseif i == 3 then
		return 0, 1 - f, 1
	elseif i == 4 then
		return f, 0, 1
	end
	return 1, 0, 1 - f
end

-- The color for a color mode ("theme", "class", "custom", "rainbow"). palette: accent and class as { r, g, b }
-- (class may be missing), custom as { r =, g =, b = } (empty until the player picks one). t: the time for the
-- rainbow. Anything missing falls back to the accent.
function ns.Cursor_Color(mode, palette, t)
	if mode == "rainbow" then
		return ns.Cursor_HueRGB(ns.Cursor_Hue(t))
	end
	local c = palette.accent
	if mode == "class" and palette.class then
		c = palette.class
	elseif mode == "custom" and palette.custom and palette.custom.r then
		local p = palette.custom
		return p.r, p.g, p.b
	end
	return c[1], c[2], c[3]
end

-- Shapes -------------------------------------------------------------------------------------------------------

-- Ring shapes: art is a file in Media/Cursor/; halo: whether the soft glow sits behind it (the soft glow shape is
-- one already).
ns.CURSOR_RING_SHAPES = {
	{ key = "ring", text = "Ring", art = "Ring", halo = true },
	{ key = "thick", text = "Thick ring", art = "RingThick", halo = true },
	{ key = "glow", text = "Soft glow", art = "Glow", halo = false },
	{ key = "crosshair", text = "Crosshair", art = "Crosshair", halo = true },
}

-- Flat trail shapes: art in Media/Cursor/ (none for the ribbon, which is drawn with lines); spin turns the points as
-- they age, twinkle makes them flicker.
ns.CURSOR_TRAIL_SHAPES = {
	{ key = "dots", text = "Glow dots", art = "Dot" },
	{ key = "rings", text = "Rings", art = "RingSmall" },
	{ key = "stars", text = "Stars", art = "Star", spin = true },
	{ key = "sparkles", text = "Sparkles", art = "Sparkle", twinkle = true },
	{ key = "ribbon", text = "Ribbon" },
}

-- The entry with that key in list, or the first one (a saved key that's no longer offered).
function ns.Cursor_Find(list, key)
	for _, e in ipairs(list) do
		if e.key == key then
			return e
		end
	end
	return list[1]
end

-- Dropdown choices ({ value, text }) for a list of shapes or effects.
function ns.Cursor_Choices(list)
	local out = {}
	for i, e in ipairs(list) do
		out[i] = { value = e.key, text = e.text }
	end
	return out
end

-- Spell effects ------------------------------------------------------------------------------------------------

-- Blizzard spell models drawn at the cursor; their particles stay behind in the scene as it moves, which makes the
-- trail. File IDs, sizes and turns as measured by the CursorTrail addon by UppyDan (CurseForge project 272840),
-- whose SetTransform placement Trail.lua follows; the IDs were checked on wago.tools. scale: the
-- model's size at the default head size; turn: rotation in degrees around x, y, z (missiles point along the screen).
ns.CURSOR_EFFECTS = {
	{ key = "arcane", text = "Arcane orb", file = 963808, scale = 0.028, turn = { 0, 0, 0 } }, -- arcane_missile_orb
	{ key = "flare", text = "Flare", file = 166566, scale = 0.05, turn = { 0, 0, 0 } }, -- missile_flare
	{ key = "solar", text = "Solar wrath", file = 1513210, scale = 0.009, turn = { 0, 90, 0 } }, -- druid solarwrath
	{ key = "starsurge", text = "Starsurge", file = 1513212, scale = 0.01, turn = { 0, 90, 0 } }, -- druid starsurge
	{ key = "soul", text = "Soul fire", file = 1366901, scale = 0.011, turn = { 0, 90, 0 } }, -- dh soulturret
}
