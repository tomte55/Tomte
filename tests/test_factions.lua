-- Run from the AddOns folder: lua Tomte/tests/test_factions.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/WarWithin/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Weekly/FactionData.lua"))("Tomte", ns)

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

local function Rec(over)
	local r = { id = 2590, name = "Council of Dornogal", renown = true, level = 7, max = 25, earned = 1737,
		threshold = 2500, kit = "Dornogal" }
	for k, v in pairs(over or {}) do
		r[k] = v
	end
	return r
end

test("ring: renown in progress", function()
	local ring = ns.Weekly_FactionRing(Rec())
	eq(ring.frac, 1737 / 2500)
	eq(ring.badge, "7")
	eq(ring.color, "blue")
	eq(ring.glow, false)
end)

test("ring: maxed without paragon is full and gold", function()
	local ring = ns.Weekly_FactionRing(Rec({ level = 25, earned = 0 }))
	eq(ring.frac, 1)
	eq(ring.color, "gold")
end)

test("ring: paragon progress and a waiting reward", function()
	local ring = ns.Weekly_FactionRing(Rec({ level = 25, paragon = { value = 2500, threshold = 10000 } }))
	eq(ring.frac, 0.25)
	eq(ring.color, "gold")
	eq(ring.glow, false)
	local waiting = ns.Weekly_FactionRing(Rec({ level = 25, paragon = { value = 12500, threshold = 10000, pending = true } }))
	eq(waiting.frac, 1, "a waiting reward shows full")
	eq(waiting.glow, true)
end)

test("ring: plain reputation uses its standing", function()
	local ring = ns.Weekly_FactionRing({ id = 2669, name = "Darkfuse", renown = false, level = 3, earned = 500,
		threshold = 1000 })
	eq(ring.badge, "3")
	eq(ring.frac, 0.5)
	eq(ring.color, "white")
end)

test("ring: a maxed friendship is full and gold", function()
	local ring = ns.Weekly_FactionRing({ id = 2601, renown = false, level = 9, maxed = true, threshold = 0 })
	eq(ring.frac, 1)
	eq(ring.color, "gold")
end)

test("ring: zero threshold doesn't divide by zero", function()
	eq(ns.Weekly_FactionRing(Rec({ threshold = 0 })).frac, 0)
end)

test("detail texts", function()
	local d = ns.Weekly_FactionDetail(Rec())
	eq(d.title, "Council of Dornogal")
	eq(d.line1, "Renown 7/25")
	eq(d.line2, "763 until next level")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25 })).line2, "Max renown")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25, paragon = { value = 4200, threshold = 10000 } })).line2,
		"Paragon 4,200 / 10,000")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25, paragon = { value = 10000, threshold = 10000 } })).line2,
		"Paragon 10,000 / 10,000", "a full round reads full")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25, paragon = { value = 10000, threshold = 10000, pending = true } })).line2,
		"Paragon reward waiting")
	local plain = ns.Weekly_FactionDetail({ name = "Darkfuse", renown = false, standing = "Rank 3", earned = 500,
		threshold = 1000 })
	eq(plain.line1, "Rank 3")
	eq(plain.line2, "500 / 1,000")
	eq(ns.Weekly_FactionDetail({ name = "Weaver", renown = false, standing = "Rank 9", maxed = true }).line2, "Max rank")
end)

test("atlas: kit pattern, missing atlas falls back", function()
	local exists = function(name)
		return name == "majorfactions_icons_Dornogal512"
	end
	eq(ns.Weekly_FactionAtlas("Dornogal", exists), "majorfactions_icons_Dornogal512")
	eq(ns.Weekly_FactionAtlas("Nope", exists), nil)
	eq(ns.Weekly_FactionAtlas(nil, exists), nil)
end)

test("reward track: earned levels and rewards per level", function()
	local levels = { { level = 7 }, { level = 8 }, { level = 9 } }
	local track = ns.Weekly_RewardTrack(Rec(), levels, function(level)
		if level == 8 then
			return { { name = "Gem", icon = 1, uiOrder = 2 }, { name = "Pouch", icon = 2, uiOrder = 1 } }
		end
		return { { name = "Level " .. level, icon = 3 } }
	end)
	eq(#track, 3)
	eq(track[1].earned, true, "level 7 is earned at renown 7")
	eq(track[2].earned, false)
	eq(track[2].rewards[1].name, "Pouch", "uiOrder first")
	eq(#ns.Weekly_RewardTrack(Rec(), nil, function() end), 0)
end)

test("layout: parents by name, subs attached, subs not listed on their own", function()
	local recs = {
		Rec({ id = 2653, name = "Cartels of Undermine" }),
		Rec({ id = 2590, name = "Council of Dornogal" }),
		{ id = 2669, name = "Darkfuse", parent = 2653 },
		{ id = 2673, name = "Bilgewater", parent = 2653 },
	}
	local layout = ns.Weekly_FactionLayout(recs)
	eq(#layout, 2)
	eq(layout[1].rec.name, "Cartels of Undermine")
	eq(#layout[1].subs, 2)
	eq(layout[1].subs[1].name, "Darkfuse", "table order kept")
	eq(#layout[2].subs, 0)
	eq(#ns.Weekly_FactionLayout({}), 0)
end)

test("sub-faction table for The War Within", function()
	eq(#ns.Content_Get(10, "subfactions")[2653], 5)
	eq(#ns.Content_Get(10, "subfactions")[2600], 3)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
