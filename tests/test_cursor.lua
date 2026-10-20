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

H.done()
