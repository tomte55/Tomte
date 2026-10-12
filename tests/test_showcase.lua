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

local LABELS = { ARMOR = "Armor", AGI = "Agility", STR = "Strength", STA = "Stamina", CRIT = "Critical Strike",
	HASTE = "Haste", MASTERY = "Mastery", VERS = "Versatility" }

test("Card stats: armor, the spec's primary, stamina, then secondaries", function()
	local rows = ns.CharShow_CardStats({ ARMOR = 60, PRIMARY = { AGI = 39, INT = 39 }, STA = 1458, MASTERY = 29,
		CRIT = 37 }, "AGI", LABELS)
	eq(#rows, 5, "rows")
	eq(rows[1].text, "60 Armor")
	eq(rows[2].text, "+39 Agility")
	eq(rows[3].text, "+1,458 Stamina")
	eq(rows[3].secondary, false)
	eq(rows[4].key, "CRIT", "secondaries in order")
	eq(rows[4].secondary, true)
	eq(rows[5].text, "+29 Mastery")
	eq(#ns.CharShow_CardStats({ PRIMARY = { STR = 10 } }, "AGI", LABELS), 0, "other primary left out")
	eq(#ns.CharShow_CardStats(nil, nil, LABELS), 0, "no stats")
end)

test("Meta line skips empty parts", function()
	eq(ns.CharShow_MetaLine("Head", "Mail", "Soulbound"), "Head · Mail · Soulbound")
	eq(ns.CharShow_MetaLine("Neck", nil, "", "Warbound"), "Neck · Warbound")
	eq(ns.CharShow_Percent(1.716), "1.72%")
	eq(ns.CharShow_Percent(nil), nil)
end)

test("Menu statuses", function()
	local text, role = ns.CharShow_EquipStatus(0, "Head")
	eq(text, "No other item for Head")
	eq(role, "danger")
	eq((ns.CharShow_EquipStatus(1, "Head")), "1 item in your bags")
	eq((ns.CharShow_EquipStatus(3, "Head")), "3 items in your bags")
	text, role = ns.CharShow_EnchantStatus(true, "+86 Haste", 0)
	eq(text, "+86 Haste")
	eq(role, "success")
	eq((ns.CharShow_EnchantStatus(true, nil, 2)), "No enchant")
	eq((ns.CharShow_EnchantStatus(false, nil, 2)), "2 in your bags")
	eq((ns.CharShow_EnchantStatus(false, nil, 0)), "Doesn't take one")
	eq((ns.CharShow_GemStatus(0, 0)), "No socket")
	text, role = ns.CharShow_GemStatus(2, 1)
	eq(text, "1 empty socket")
	eq(role, "warning")
	eq((ns.CharShow_GemStatus(2, 2)), "2 empty sockets")
	eq((ns.CharShow_GemStatus(1, 0)), "All sockets filled")
end)

test("Enchant items fit their slots", function()
	eq(ns.CharShow_EnchantFits(5, "INVTYPE_CHEST", 8, 4), "permanent", "chest scroll")
	eq(ns.CharShow_EnchantFits(5, "INVTYPE_ROBE", 8, 4), "permanent", "robe")
	eq(ns.CharShow_EnchantFits(9, "INVTYPE_WRIST", 8, 4), nil, "chest scroll on wrists")
	eq(ns.CharShow_EnchantFits(11, "INVTYPE_FINGER", 8, 10), "permanent", "ring 1")
	eq(ns.CharShow_EnchantFits(12, "INVTYPE_FINGER", 8, 10), "permanent", "ring 2")
	eq(ns.CharShow_EnchantFits(16, "INVTYPE_2HWEAPON", 8, 12), "permanent", "two-hander")
	eq(ns.CharShow_EnchantFits(16, "INVTYPE_RANGEDRIGHT", 8, 12), "permanent", "gun")
	eq(ns.CharShow_EnchantFits(16, "INVTYPE_2HWEAPON", 8, 11), "permanent", "weapon scroll on a two-hander")
	eq(ns.CharShow_EnchantFits(16, "INVTYPE_RANGED", 8, 11), "permanent", "weapon scroll on a bow")
	eq(ns.CharShow_EnchantFits(17, "INVTYPE_SHIELD", 8, 11), nil, "weapon scroll on a shield")
	eq(ns.CharShow_EnchantFits(16, nil, 8, 11), nil, "empty weapon slot")
	eq(ns.CharShow_EnchantFits(17, "INVTYPE_WEAPON", 8, 11), "permanent", "off-hand weapon")
	eq(ns.CharShow_EnchantFits(17, "INVTYPE_SHIELD", 8, 13), "permanent", "shield")
	eq(ns.CharShow_EnchantFits(16, "INVTYPE_WEAPON", 0, 6), "temporary", "oil")
	eq(ns.CharShow_EnchantFits(17, "INVTYPE_SHIELD", 0, 6), nil, "oil on a shield")
	eq(ns.CharShow_EnchantFits(1, "INVTYPE_HEAD", 0, 6), nil, "oil on a helm")
	eq(ns.CharShow_EnchantFits(1, "INVTYPE_HEAD", 0, 1), nil, "potion")
	eq(ns.CharShow_EnchantMacro(2, 14, 16), "/use 2 14\n/use 16")
end)

test("Gems and the socket to fill", function()
	assert(ns.CharShow_IsGem(3, 7), "haste gem")
	assert(not ns.CharShow_IsGem(3, 11), "relic")
	assert(not ns.CharShow_IsGem(4, 7), "armor")
	eq(ns.CharShow_PickSocket(2, { 123 }), 2, "first empty")
	eq(ns.CharShow_PickSocket(2, { 1, 2 }), 1, "all full: the first")
	eq(ns.CharShow_PickSocket(0, {}), nil, "no socket")
end)

H.done()
