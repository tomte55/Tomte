-- Run from the AddOns folder: lua Tomte/tests/test_showcase.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Showcase/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

test("columns hold every gear slot once, shirt and tabard left out", function()
	local seen = {}
	for _, list in ipairs({ ns.CHARSHOW_LEFT, ns.CHARSHOW_RIGHT }) do
		eq(#list, 9, "rows")
		for _, slot in ipairs(list) do
			if slot then
				assert(not seen[slot], "slot twice: " .. slot)
				seen[slot] = true
			end
		end
	end
	for slot = 1, 17 do
		eq(seen[slot] or false, slot ~= 4, "slot " .. slot)
	end
	eq(ns.CHARSHOW_LEFT[9], 16, "main hand on the bottom row")
	eq(ns.CHARSHOW_RIGHT[9], 17, "off hand on the bottom row")
end)

test("Zoom grows with height and is clamped", function()
	local small, tall = ns.CharShow_Zoom(1), ns.CharShow_Zoom(2.8)
	assert(tall > small, "taller is farther")
	near(ns.CharShow_Zoom(2), 0.4 + 2.2)
	near(ns.CharShow_Zoom(nil), ns.CharShow_Zoom(2), "default height")
	near(ns.CharShow_Zoom(0.1), 1.5, "min")
	near(ns.CharShow_Zoom(100), 20, "max")
	near(ns.CharShow_Zoom(2, false, 1.5), (0.4 + 2.2) * 1.5, "distance setting")
	assert(ns.CharShow_Zoom(2, true) > ns.CharShow_Zoom(2) + 2, "mounted is farther")
end)

test("Shoulder follows the zoom, 0 when centered", function()
	near(ns.CharShow_Shoulder(4, true), 1.32)
	near(ns.CharShow_Shoulder(8, true), 2.64)
	eq(ns.CharShow_Shoulder(4, false), 0)
end)

test("SwingRate ramps up, then eases down into the slow turn", function()
	near(ns.CharShow_SwingRate(0, 1.6, 220, 2, 0.4), 2, "starts at the slow turn, no jolt")
	assert(ns.CharShow_SwingRate(0.4, 1.6, 220, 2, 0.4) > 150, "fast after the ramp")
	near(ns.CharShow_SwingRate(1.6, 1.6, 220, 2, 0.4), 2)
	near(ns.CharShow_SwingRate(9, 1.6, 220, 2, 0.4), 2, "clamped after the end")
	near(ns.CharShow_SwingRate(0, 1, 100, 0), 100, "no ramp")
	-- About 135 degrees in all: from behind round to a 3/4 front view.
	local turned, dt = 0, 0.01
	for t = 0, 1.6 - dt / 2, dt do
		turned = turned + ns.CharShow_SwingRate(t + dt / 2, 1.6, 220, 2, 0.4) * dt
	end
	assert(turned > 130 and turned < 140, "turned " .. turned)
end)

test("YawRate scales the CVar", function()
	near(ns.CharShow_YawRate("180", 0.5), 90)
	near(ns.CharShow_YawRate(nil, 1), 180, "default 180")
end)

test("Track for the pips", function()
	local track, cur, max = ns.CharShow_Track({ track = "Hero", cur = 4, max = 6 })
	eq(track, "Hero")
	eq(cur, 4)
	eq(max, 6)
	track, cur = ns.CharShow_Track({ track = "Myth", cur = 9, max = 6 })
	eq(cur, 6, "clamped")
	eq(ns.CharShow_Track({ track = "", cur = 1, max = 6 }), nil)
	eq(ns.CharShow_Track(nil), nil)
end)

test("Split: shares by rating", function()
	local parts = ns.CharShow_Split({
		{ key = "crit", rating = 302 }, { key = "haste", rating = 222 }, { key = "mastery", rating = 361 },
		{ key = "versatility", rating = 64 },
	})
	near(parts[1].share, 302 / 949)
	near(parts[4].share, 64 / 949)
	local sum = 0
	for _, p in ipairs(parts) do
		sum = sum + p.share
	end
	near(sum, 1)
	eq(ns.CharShow_Split({ { key = "crit", rating = 0 } }), nil, "nothing to split")
	eq(ns.CharShow_Split({}), nil)
end)

test("DialFill", function()
	local fill, lit = ns.CharShow_DialFill(146, 146, 48)
	near(fill, 1)
	eq(lit, 48)
	fill, lit = ns.CharShow_DialFill(73, 146, 48)
	near(fill, 0.5)
	eq(lit, 24)
	fill, lit = ns.CharShow_DialFill(150, 146, 48)
	near(fill, 1, "never above full")
	fill, lit = ns.CharShow_DialFill(10, 0, 48)
	eq(lit, 0, "no best item level")
end)

test("EnchantText strips the prefix and colors", function()
	eq(ns.CharShow_EnchantText("Enchanted: +86 Haste", "Enchanted: %s"), "+86 Haste")
	eq(ns.CharShow_EnchantText("|cff00ff00Enchanted: Crystalline Radiance|r", "Enchanted: %s"), "Crystalline Radiance")
	eq(ns.CharShow_EnchantText("Verzaubert: +86 Tempo", "Verzaubert: %s"), "+86 Tempo")
	eq(ns.CharShow_EnchantText("Something else", "Enchanted: %s"), "Something else", "no prefix: as it is")
	eq(ns.CharShow_EnchantText("x (y)", "x (%s)"), "y", "magic characters in the format")
	eq(ns.CharShow_EnchantText("", "Enchanted: %s"), nil)
	eq(ns.CharShow_EnchantText(nil, "Enchanted: %s"), nil)
end)

test("Hints: enchant, missing only at max level, sockets", function()
	local h = ns.CharShow_Hints({ enchanted = true, sockets = 2, gems = 1 }, true, true, "+86 Haste")
	eq(h.enchant, "+86 Haste")
	eq(h.missing, false)
	eq(h.gems, 1)
	eq(h.empty, 1)
	h = ns.CharShow_Hints({ enchanted = false }, true, true)
	eq(h.missing, true)
	eq(h.empty, 0)
	h = ns.CharShow_Hints({ enchanted = false }, true, false)
	eq(h.missing, false, "leveling")
	h = ns.CharShow_Hints({ enchanted = false }, false, true)
	eq(h.missing, false, "slot without enchants")
end)

local function Entries()
	return {
		{ key = "primary", value = 541 }, { key = "stamina", value = 6294 }, { key = "health", value = 138468 },
		{ key = "armor", value = 0 }, { key = "crit", value = 39.84, rating = 302, percent = true },
		{ key = "haste", value = 0, percent = true }, { key = "leech", value = 0, percent = true },
		{ key = "dodge", value = 13.06, percent = true }, { key = "parry", value = 0, percent = true },
		{ key = "block", value = 20, percent = true }, { key = "speed", value = nil },
	}
end

local function Keys(list)
	local keys = {}
	for _, e in ipairs(list) do
		keys[#keys + 1] = e.key
	end
	return table.concat(keys, " ")
end

test("FilterStats: like Blizzard's sheet", function()
	eq(Keys(ns.CharShow_FilterStats(Entries(), false, false)), "primary stamina health armor crit")
	eq(Keys(ns.CharShow_FilterStats(Entries(), true, false)), "primary stamina health armor crit dodge")
	eq(Keys(ns.CharShow_FilterStats(Entries(), true, true)), "primary stamina health armor crit dodge block")
end)

test("StatText", function()
	local v, r = ns.CharShow_StatText({ value = 39.844, rating = 302, percent = true })
	eq(v, "39.84%")
	eq(r, "302")
	v, r = ns.CharShow_StatText({ value = 138468 })
	eq(v, "138,468")
	eq(r, nil)
	v, r = ns.CharShow_StatText({ value = 4.48, rating = 0, percent = true })
	eq(r, nil, "no rating at 0")
end)

test("Subtitle and Title", function()
	eq(ns.CharShow_Subtitle(80, "Beast Mastery", "Hunter"), "80 Beast Mastery Hunter")
	eq(ns.CharShow_Subtitle(12, nil, "Hunter"), "12 Hunter")
	eq(ns.CharShow_Title("the Fabulous "), "the Fabulous")
	eq(ns.CharShow_Title("%s the Patient"), "the Patient")
	eq(ns.CharShow_Title(" "), nil)
	eq(ns.CharShow_Title(nil), nil)
end)

H.done()
