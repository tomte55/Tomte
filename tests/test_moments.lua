-- Run from the AddOns folder: lua Tomte/tests/test_moments.lua
local ns = {}
assert(loadfile("Tomte/Modules/Moments/Data.lua"))("Tomte", ns)

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

test("DefaultStyles has every type", function()
	local styles = ns.Moments_DefaultStyles()
	for _, t in ipairs(ns.MOMENT_TYPES) do
		eq(styles[t.key], t.style, t.key)
	end
end)

test("Decide waits, then falls back to a banner", function()
	eq(ns.Moments_Decide(true, 0, 10), "cinematic")
	eq(ns.Moments_Decide(false, 3, 10), "wait")
	eq(ns.Moments_Decide(false, 10, 10), "banner")
end)

test("FormatToPattern handles %s, %d and magic characters", function()
	eq(ns.Moments_FormatToPattern("Discovered: %s"), "^Discovered: (.+)$")
	local p = ns.Moments_FormatToPattern("Discovered %s: %d experience gained")
	eq(("Discovered Silvermoon: 450 experience gained"):match(p), "Silvermoon")
	local dotted = ns.Moments_FormatToPattern("Found (%s).")
	eq(("Found (X)."):match(dotted), "X")
	eq(("Found (X)!"):match(dotted), nil)
end)

test("DiscoveredArea tries every pattern", function()
	local patterns = {
		ns.Moments_FormatToPattern("Discovered: %s"),
		ns.Moments_FormatToPattern("Discovered %s: %d experience gained"),
	}
	eq(ns.Moments_DiscoveredArea("Discovered: Goldshire", patterns), "Goldshire")
	eq(ns.Moments_DiscoveredArea("Discovered Goldshire: 30 experience gained", patterns), "Goldshire")
	eq(ns.Moments_DiscoveredArea("You are too far away", patterns), nil)
	eq(ns.Moments_DiscoveredArea(nil, patterns), nil)
end)

test("ShouldShowAchievement skips repeats and guild", function()
	eq(ns.Moments_ShouldShowAchievement(nil, false), true)
	eq(ns.Moments_ShouldShowAchievement(true, false), false)
	eq(ns.Moments_ShouldShowAchievement(false, true), false)
end)

test("LevelLabel marks max level", function()
	eq(ns.Moments_LevelLabel(47, 90), "Level up")
	eq(ns.Moments_LevelLabel(90, 90), "Maximum level")
	eq(ns.Moments_LevelLabel(12, nil), "Level up")
end)

test("IsNewZone needs overlays and nothing explored before", function()
	eq(ns.Moments_IsNewZone(0, 1), true)
	eq(ns.Moments_IsNewZone(nil, 1), true)
	eq(ns.Moments_IsNewZone(nil, 3), false)
	eq(ns.Moments_IsNewZone(2, 3), false)
	eq(ns.Moments_IsNewZone(0, 0), false)
	eq(ns.Moments_IsNewZone(nil, 0), false)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
