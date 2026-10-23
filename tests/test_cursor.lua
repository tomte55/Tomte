-- Run from the AddOns folder: lua Tomte/tests/test_cursor.lua
local ns = {}
-- Core.lua's easing (Core.lua needs the game, so the test supplies the same function).
ns.Smoothstep = function(p)
	return p * p * (3 - 2 * p)
end
assert(loadfile("Tomte/Modules/Cursor/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

-- Feeds points (x, y pairs) sampled every `step` seconds from t0 and returns the samples still in the window.
local function feed(points, step, t0)
	local samples, t = {}, t0 or 0
	for i = 1, #points, 2 do
		ns.Cursor_AddSample(samples, t, points[i], points[i + 1])
		t = t + step
	end
	return samples, t - step
end

-- A horizontal zigzag: `legs` legs of `width` units around x = 500, `perLeg` samples each.
local function zigzag(legs, width, perLeg)
	local pts, x, dir = {}, 500, 1
	for _ = 1, legs do
		for _ = 1, perLeg do
			x = x + dir * width / perLeg
			pts[#pts + 1] = x
			pts[#pts + 1] = 300
		end
		dir = -dir
	end
	return pts
end

test("AddSample keeps only samples inside the window", function()
	local s = {}
	ns.Cursor_AddSample(s, 0, 1, 1)
	ns.Cursor_AddSample(s, 0.3, 2, 2)
	ns.Cursor_AddSample(s, 0.7, 3, 3)
	eq(#s, 2, "count")
	eq(s[1].x, 2, "oldest kept")
	eq(s[2].x, 3, "newest")
	ns.Cursor_AddSample(s, 5, 4, 4)
	eq(#s, 1, "all old ones dropped")
	eq(s[2], nil, "no leftovers past the end")
end)

test("a fast zigzag is a shake", function()
	local s = feed(zigzag(5, 120, 3), 1 / 30)
	eq(ns.Cursor_IsShake(s), true)
end)

test("a vertical zigzag is a shake too", function()
	local pts = zigzag(5, 120, 3)
	for i = 1, #pts, 2 do
		pts[i], pts[i + 1] = 300, pts[i]
	end
	eq(ns.Cursor_IsShake(feed(pts, 1 / 30)), true)
end)

test("a straight fast move is not a shake", function()
	local pts = {}
	for i = 1, 15 do
		pts[#pts + 1] = 100 + i * 40
		pts[#pts + 1] = 300
	end
	eq(ns.Cursor_IsShake(feed(pts, 1 / 30)), false)
end)

test("two turns are not enough", function()
	eq(ns.Cursor_IsShake(feed(zigzag(3, 150, 3), 1 / 30)), false)
end)

test("small wiggles (aiming at a button) are not a shake", function()
	eq(ns.Cursor_IsShake(feed(zigzag(8, 15, 2), 1 / 30)), false)
end)

test("jitter blips inside a leg don't count as turns", function()
	local pts = {}
	local x = 100
	for _ = 1, 4 do
		for _ = 1, 3 do
			x = x + 40
			pts[#pts + 1], pts[#pts + 2] = x, 300
		end
		x = x - 5 -- a short twitch back
		pts[#pts + 1], pts[#pts + 2] = x, 300
	end
	eq(ns.Cursor_IsShake(feed(pts, 1 / 30)), false)
end)

test("a slow zigzag falls out of the window", function()
	-- Same shape as the fast shake, but sampled 4 times slower: only part of it is inside the half second.
	eq(ns.Cursor_IsShake(feed(zigzag(5, 120, 3), 4 / 30)), false)
end)

test("ShakeLook pops, holds, shrinks and fades", function()
	local scale, alpha = ns.Cursor_ShakeLook(0, 0, 0)
	near(scale, 1, "starts at normal size")
	near(alpha, 0, "starts invisible")
	scale, alpha = ns.Cursor_ShakeLook(0, 1, 1)
	near(scale, 2.4, "big while shaking")
	near(alpha, 1, "fully visible while shaking")
	scale, alpha = ns.Cursor_ShakeLook(0, 1, 1.5)
	near(scale, 1, "back to normal size after the shrink")
	near(alpha, 1, "still visible during the hold")
	scale, alpha = ns.Cursor_ShakeLook(0, 1, 1.8)
	assert(alpha > 0 and alpha < 1, "fading: " .. alpha)
	scale, alpha = ns.Cursor_ShakeLook(0, 1, 2)
	near(alpha, 0, "gone a second after the last shake")
end)

test("ShakeOver: a shake that just began is not over, one long calm is", function()
	-- Regression: the driver used to end a shake when ShakeLook's alpha was 0, which it is on the first frame.
	local _, alpha = ns.Cursor_ShakeLook(3, 3, 3)
	eq(alpha, 0, "first frame is still invisible")
	eq(ns.Cursor_ShakeOver(3, 3), false, "just began")
	eq(ns.Cursor_ShakeOver(1, 1.9), false, "still fading")
	eq(ns.Cursor_ShakeOver(1, 2), true, "faded out")
end)

test("ShakeLook shrinks smoothly", function()
	local a = ns.Cursor_ShakeLook(0, 1, 1.1)
	local b = ns.Cursor_ShakeLook(0, 1, 1.2)
	assert(a > b and b > 1, ("shrinking: %.2f then %.2f"):format(a, b))
end)

test("Look: steady modes show at full opacity, mouse-look hides", function()
	local _, alpha = ns.Cursor_Look({ steady = true }, 5)
	eq(alpha, 1, "steady")
	_, alpha = ns.Cursor_Look({}, 5)
	eq(alpha, 0, "nothing on")
	local scale
	scale, alpha = ns.Cursor_Look({ steady = true, shake = { began = 0, last = 1 } }, 1)
	near(scale, 2.4, "a shake still pops a steady ring")
	eq(alpha, 1, "steady wins over the fade-in")
	_, alpha = ns.Cursor_Look({ steady = true, hidden = true }, 1)
	eq(alpha, 0, "hidden")
end)

test("TrailAdd spaces dots and caps their number", function()
	local p = {}
	ns.Cursor_TrailAdd(p, 0, 0, 0, 10, 3)
	ns.Cursor_TrailAdd(p, 0.1, 5, 0, 10, 3)
	eq(#p, 1, "too close to the last dot")
	for i = 1, 5 do
		ns.Cursor_TrailAdd(p, i, i * 20, 0, 10, 3)
	end
	eq(#p, 3, "capped")
	eq(p[3].x, 100, "newest last")
	eq(p[1].x, 60, "oldest dropped first")
end)

test("TrailFade ages and drops dots", function()
	local p = { { t = 0, x = 0, y = 0 }, { t = 0.2, x = 1, y = 0 }, { t = 0.4, x = 2, y = 0 } }
	local fade = ns.Cursor_TrailFade(p, 0.45, 0.3)
	eq(#p, 2, "the oldest expired")
	eq(#fade, 2, "one strength per dot")
	near(fade[1], 1 - 0.25 / 0.3, "older dot")
	near(fade[2], 1 - 0.05 / 0.3, "newer dot")
end)

test("TrailAdd numbers points so each keeps its own twinkle", function()
	local p = {}
	ns.Cursor_TrailAdd(p, 0, 0, 0, 10, 2)
	ns.Cursor_TrailAdd(p, 1, 20, 0, 10, 2)
	ns.Cursor_TrailAdd(p, 2, 40, 0, 10, 2)
	eq(p[1].n, 2, "serial survives dropping the oldest")
	eq(p[2].n, 3, "newest")
end)

test("TrailFade reuses its result table and trims it", function()
	local out = { 9, 9, 9, 9 }
	local p = { { t = 0, x = 0, y = 0 }, { t = 0.2, x = 1, y = 0 } }
	local fade = ns.Cursor_TrailFade(p, 0.35, 0.3, out)
	eq(fade, out, "same table")
	eq(#out, 1, "trimmed to the points left")
end)

test("TrailLook tapers size and fades opacity", function()
	local size, alpha = ns.Cursor_TrailLook(1, 14, 0.6, 0.5)
	near(size, 14, "fresh point at head size")
	near(alpha, 0.5, "fresh point at full opacity")
	size, alpha = ns.Cursor_TrailLook(0, 14, 0.6, 0.5)
	near(size, 14 * 0.4, "tail shrunk to 40%")
	near(alpha, 0, "tail gone")
	size = ns.Cursor_TrailLook(0.5, 20, 0, 1)
	near(size, 20, "no taper keeps the size")
	size = ns.Cursor_TrailLook(2, 10, 1, 1)
	near(size, 10, "strength clamped")
end)

test("Twinkle and Spin stay in range and differ per point", function()
	for n = 1, 20 do
		for age = 0, 1, 0.05 do
			local k = ns.Cursor_Twinkle(n, age)
			assert(k >= 0.45 - 1e-9 and k <= 1 + 1e-9, "twinkle " .. k)
			local r = ns.Cursor_Spin(n, age)
			assert(r >= 0 and r < 2 * math.pi, "spin " .. r)
		end
	end
	assert(ns.Cursor_Twinkle(1, 0) ~= ns.Cursor_Twinkle(2, 0), "neighbours out of step")
end)

test("TrailGate: off, mouse-look, and the three modes", function()
	eq(ns.Cursor_TrailGate(false, "moving", {}), 0, "trail off")
	eq(ns.Cursor_TrailGate(true, "moving", { hidden = true }), 0, "mouse-look hides")
	eq(ns.Cursor_TrailGate(true, "moving", {}), 1, "moving: always")
	eq(ns.Cursor_TrailGate(true, "combat", { combat = false }), 0, "combat: out of combat")
	eq(ns.Cursor_TrailGate(true, "combat", { combat = true }), 1, "combat: in combat")
	near(ns.Cursor_TrailGate(true, "ring", { ringAlpha = 0.4 }), 0.4, "ring: fades with the ring")
	eq(ns.Cursor_TrailGate(true, "ring", { ringAlpha = 0 }), 0, "ring: hidden with the ring")
	near(ns.Cursor_TrailGate(true, nil, { ringAlpha = 1 }), 1, "missing mode acts as ring")
end)

test("IdleFade holds, then fades the spell effect out", function()
	eq(ns.Cursor_IdleFade(0), 1, "moving")
	eq(ns.Cursor_IdleFade(0.2), 1, "short pause")
	local mid = ns.Cursor_IdleFade(0.4)
	assert(mid > 0 and mid < 1, "fading: " .. mid)
	eq(ns.Cursor_IdleFade(1), 0, "gone")
end)

test("Pulse breathes around normal size", function()
	local lo, hi = math.huge, -math.huge
	for t = 0, 1.6, 0.01 do
		local s, a = ns.Cursor_Pulse(t)
		lo, hi = math.min(lo, s), math.max(hi, s)
		assert(a >= 0.7 - 1e-9 and a <= 1 + 1e-9, "alpha " .. a)
	end
	near(lo, 0.92, "smallest")
	near(hi, 1.08, "biggest")
end)

test("HueRGB and Hue", function()
	local r, g, b = ns.Cursor_HueRGB(0)
	near(r, 1, "red")
	near(g + b, 0, "only red")
	r, g, b = ns.Cursor_HueRGB(1 / 3)
	near(g, 1, "green")
	near(r + b, 0, "only green")
	r, g, b = ns.Cursor_HueRGB(2 / 3)
	near(b, 1, "blue")
	r, g, b = ns.Cursor_HueRGB(1.5)
	near(r, 0, "1.5 wraps round to cyan")
	near(g + b, 2, "cyan")
	near(ns.Cursor_Hue(1.5), 0.5, "half a turn")
	near(ns.Cursor_Hue(3), 0, "full turn")
end)

test("Color picks by mode and falls back to the accent", function()
	local palette = { accent = { 0.1, 0.2, 0.3 }, class = { 0.4, 0.5, 0.6 }, custom = {} }
	eq(table.concat({ ns.Cursor_Color("theme", palette, 0) }, ","), "0.1,0.2,0.3", "theme")
	eq(table.concat({ ns.Cursor_Color("class", palette, 0) }, ","), "0.4,0.5,0.6", "class")
	eq(table.concat({ ns.Cursor_Color("custom", palette, 0) }, ","), "0.1,0.2,0.3", "custom not picked yet")
	palette.custom = { r = 0.7, g = 0.8, b = 0.9 }
	eq(table.concat({ ns.Cursor_Color("custom", palette, 0) }, ","), "0.7,0.8,0.9", "custom")
	palette.class = nil
	eq(table.concat({ ns.Cursor_Color("class", palette, 0) }, ","), "0.1,0.2,0.3", "no class color")
	local r, g, b = ns.Cursor_Color("rainbow", palette, 0)
	near(r, 1, "rainbow starts red")
	near(g + b, 0, "only red")
end)

test("Find falls back to the first entry; Choices lists every entry", function()
	eq(ns.Cursor_Find(ns.CURSOR_RING_SHAPES, "crosshair").art, "Crosshair", "found")
	eq(ns.Cursor_Find(ns.CURSOR_RING_SHAPES, "gone").key, "ring", "fallback")
	local choices = ns.Cursor_Choices(ns.CURSOR_TRAIL_SHAPES)
	eq(#choices, #ns.CURSOR_TRAIL_SHAPES, "one choice each")
	eq(choices[5].value, "ribbon", "value is the key")
	for _, e in ipairs(ns.CURSOR_EFFECTS) do
		assert(type(e.file) == "number" and e.scale > 0 and #e.turn == 3, "effect " .. e.key)
	end
end)

H.done()
