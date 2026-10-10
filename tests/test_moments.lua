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

test("LevelStyle: cinematics become banners below max level, except mounts and tames", function()
	eq(ns.Moments_LevelStyle("cinematic", "zone", 30, 80, true), "banner", "levelling")
	eq(ns.Moments_LevelStyle("cinematic", "levelup", 80, 80, true), "cinematic", "reaching max")
	eq(ns.Moments_LevelStyle("cinematic", "zone", 80, 80, true), "cinematic", "at max")
	eq(ns.Moments_LevelStyle("cinematic", "mount", 30, 80, true), "cinematic", "mount")
	eq(ns.Moments_LevelStyle("cinematic", "tame", 30, 80, true), "cinematic", "tame")
	eq(ns.Moments_LevelStyle("cinematic", "zone", 30, 80, false), "cinematic", "setting off")
	eq(ns.Moments_LevelStyle("off", "zone", 30, 80, true), "off", "off stays off")
	eq(ns.Moments_LevelStyle("banner", "zone", 30, 80, true), "banner", "banner stays")
	eq(ns.Moments_LevelStyle("cinematic", "zone", nil, 80, true), "cinematic", "unknown level")
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

test("FormatToPattern: positional specifiers (German) give captures in argument order", function()
	local pattern, spec = ns.Moments_FormatToPattern("%1$s entdeckt: %2$d Erfahrung erhalten.")
	eq(pattern, "^(.+) entdeckt: (%d+) Erfahrung erhalten%.$")
	local captures = ns.Moments_Match("Goldhain entdeckt: 30 Erfahrung erhalten.", pattern, spec)
	eq(captures[1], "Goldhain")
	eq(captures[2], "30")
	local swapped, swappedSpec = ns.Moments_FormatToPattern("%2$d XP: %1$s")
	captures = ns.Moments_Match("45 XP: Elwynn", swapped, swappedSpec)
	eq(captures[1], "Elwynn", "reordered area")
	eq(captures[2], "45", "reordered xp")
	eq(select(2, ns.Moments_FormatToPattern("Discovered: %s")), nil, "plain format needs no spec")
	eq(ns.Moments_FormatToPattern("100%% done: %s"), "^100%% done: (.+)$", "literal percent")
end)

test("FormatToPattern: grammar tokens match either word and are cut from the capture", function()
	local pattern, spec = ns.Moments_FormatToPattern("%s|1을;를; 발견했습니다.")
	eq(ns.Moments_Match("엘윈 숲을 발견했습니다.", pattern, spec)[1], "엘윈 숲")
	eq(ns.Moments_Match("골드샤이어를 발견했습니다.", pattern, spec)[1], "골드샤이어")
	local plural, pspec = ns.Moments_FormatToPattern("%d |4point:points; for %s")
	local captures = ns.Moments_Match("3 points for Goldshire", plural, pspec)
	eq(captures[1], "3")
	eq(captures[2], "Goldshire")
	eq(ns.Moments_FormatToPattern("Got |3-6(%s)"), "^Got (.+)$", "declension")
end)

test("DiscoveryPatterns: the XP variant first, so French discoveries keep a clean area name", function()
	local patterns = ns.Moments_DiscoveryPatterns("Découverte : %s (%d points d'expérience gagnés)", "Découverte : %s")
	eq(ns.Moments_DiscoveredArea("Découverte : Comté-de-l'Or (30 points d'expérience gagnés)", patterns), "Comté-de-l'Or")
	eq(ns.Moments_DiscoveredArea("Découverte : Comté-de-l'Or", patterns), "Comté-de-l'Or")
	local german = ns.Moments_DiscoveryPatterns("%1$s entdeckt: %2$d Erfahrung erhalten.", "Entdeckt: %s")
	eq(ns.Moments_DiscoveredArea("Goldhain entdeckt: 30 Erfahrung erhalten.", german), "Goldhain")
	eq(ns.Moments_DiscoveredArea("Entdeckt: Goldhain", german), "Goldhain")
	eq(ns.Moments_DiscoveredArea("Discovered: Goldshire", ns.Moments_DiscoveryPatterns(nil, "Discovered: %s")), "Goldshire", "missing XP format")
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

test("MountTier uses the share of players who own it", function()
	eq(ns.Moments_MountTier(nil), "rare")
	eq(ns.Moments_MountTier(0.07), "legendary")
	eq(ns.Moments_MountTier(1.99), "legendary")
	eq(ns.Moments_MountTier(2), "epic")
	eq(ns.Moments_MountTier(9.9), "epic")
	eq(ns.Moments_MountTier(10), "rare")
	eq(ns.Moments_MountTier(19.9), "rare")
	eq(ns.Moments_MountTier(20), "common")
	eq(ns.Moments_MountTier(85), "common")
end)

test("PetTier follows battle pet quality", function()
	eq(ns.Moments_PetTier(nil), "common")
	eq(ns.Moments_PetTier(1), "common")
	eq(ns.Moments_PetTier(3), "common")
	eq(ns.Moments_PetTier(4), "rare")
	eq(ns.Moments_PetTier(5), "epic")
	eq(ns.Moments_PetTier(6), "legendary")
end)

test("TameTier: exotic and rare spawns", function()
	eq(ns.Moments_TameTier(false, false), "common")
	eq(ns.Moments_TameTier(true, false), "rare")
	eq(ns.Moments_TameTier(false, true), "rare")
	eq(ns.Moments_TameTier(true, true), "epic")
end)

test("IsRareClassification", function()
	eq(ns.Moments_IsRareClassification("rare"), true)
	eq(ns.Moments_IsRareClassification("rareelite"), true)
	eq(ns.Moments_IsRareClassification("elite"), false)
	eq(ns.Moments_IsRareClassification(nil), false)
end)

test("TierLabel names the tier, plain for common", function()
	eq(ns.Moments_TierLabel("common", "mount"), "New mount")
	eq(ns.Moments_TierLabel("rare", "battle pet"), "Rare battle pet")
	eq(ns.Moments_TierLabel("legendary", "mount"), "Legendary mount")
	eq(ns.Moments_TierLabel(nil, "companion"), "New companion")
end)

test("OwnedLine formats the share", function()
	eq(ns.Moments_OwnedLine(nil), nil)
	eq(ns.Moments_OwnedLine(0.0739), "Owned by 0.07% of players")
	eq(ns.Moments_OwnedLine(0.004), "Owned by less than 0.01% of players")
	eq(ns.Moments_OwnedLine(4.6972), "Owned by 4.7% of players")
	eq(ns.Moments_OwnedLine(63.2), "Owned by 63% of players")
end)

test("Every tier has effects, colors and a sound list", function()
	for _, tier in ipairs(ns.MOMENT_TIERS) do
		local fx = ns.MOMENT_TIER_FX[tier]
		assert(fx, tier)
		assert(fx.color and #fx.color == 3, tier .. " color")
		assert(type(fx.sounds) == "table" and #fx.sounds > 0, tier .. " sounds")
	end
	assert(ns.MOMENT_TIER_FX.legendary.extraTime > 0)
	eq(ns.Moments_IsTier("epic"), true)
	eq(ns.Moments_IsTier("mount"), false)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
