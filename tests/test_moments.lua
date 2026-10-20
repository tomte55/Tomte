-- Run from the AddOns folder: lua Tomte/tests/test_moments.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Moments/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("DefaultStyles has every type", function()
	local styles = ns.Moments_DefaultStyles()
	for _, t in ipairs(ns.MOMENT_TYPES) do
		eq(styles[t.key], t.style, t.key)
	end
end)

test("LevelStyle: Cinematic at max level is a banner below max level", function()
	eq(ns.Moments_LevelStyle("cinematicMax", 30, 80), "banner", "levelling")
	eq(ns.Moments_LevelStyle("cinematicMax", 80, 80), "cinematic", "at or reaching max")
	eq(ns.Moments_LevelStyle("cinematicMax", nil, 80), "cinematic", "unknown level")
	eq(ns.Moments_LevelStyle("cinematic", 30, 80), "cinematic", "cinematic always plays")
	eq(ns.Moments_LevelStyle("off", 30, 80), "off", "off stays off")
	eq(ns.Moments_LevelStyle("banner", 80, 80), "banner", "banner stays")
end)

test("Every default style is a choice", function()
	local values = {}
	for _, s in ipairs(ns.MOMENT_STYLES) do
		values[s.value] = true
	end
	for _, t in ipairs(ns.MOMENT_TYPES) do
		eq(values[t.style], true, t.key)
	end
end)

test("MigrateAtMax: checkbox on turns Cinematic into Cinematic at max level, except mounts and tames", function()
	local db = { cinematicsAtMax = true, styles = { zone = "cinematic", mount = "cinematic", tame = "cinematic",
		pet = "banner", toy = "off" } }
	ns.Moments_MigrateAtMax(db)
	eq(db.styles.zone, "cinematicMax", "zone")
	eq(db.styles.mount, "cinematic", "mount")
	eq(db.styles.tame, "cinematic", "tame")
	eq(db.styles.pet, "banner", "pet")
	eq(db.styles.toy, "off", "toy")
	eq(db.cinematicsAtMax, nil, "checkbox removed")
end)

test("MigrateAtMax: checkbox off keeps Cinematic; nothing saved is fine", function()
	local db = { cinematicsAtMax = false, styles = { zone = "cinematic" } }
	ns.Moments_MigrateAtMax(db)
	eq(db.styles.zone, "cinematic", "zone")
	eq(db.cinematicsAtMax, nil, "checkbox removed")
	ns.Moments_MigrateAtMax(nil)
	ns.Moments_MigrateAtMax({})
end)

test("Decide waits, then falls back to a banner", function()
	eq(ns.Moments_Decide(true, 0, 10), "cinematic")
	eq(ns.Moments_Decide(false, 3, 10), "wait")
	eq(ns.Moments_Decide(false, 10, 10), "banner")
end)

test("DiscoveredArea tries every pattern", function()
	local patterns = {
		ns.FormatToPattern("Discovered: %s"),
		ns.FormatToPattern("Discovered %s: %d experience gained"),
	}
	eq(ns.Moments_DiscoveredArea("Discovered: Goldshire", patterns), "Goldshire")
	eq(ns.Moments_DiscoveredArea("Discovered Goldshire: 30 experience gained", patterns), "Goldshire")
	eq(ns.Moments_DiscoveredArea("You are too far away", patterns), nil)
	eq(ns.Moments_DiscoveredArea(nil, patterns), nil)
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

test("HouseLevelUp only when an already seen house goes up", function()
	eq(ns.Moments_HouseLevelUp(nil, 12), false, "first sight of a house")
	eq(ns.Moments_HouseLevelUp(4, 4), false, "same level again (dashboard refresh)")
	eq(ns.Moments_HouseLevelUp(4, 2), false, "lower level")
	eq(ns.Moments_HouseLevelUp(4, 5), true, "one level up")
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

test("ZonePvPRole: Blizzard's PvP types map to theme roles", function()
	eq(ns.Moments_ZonePvPRole("sanctuary"), "accent")
	eq(ns.Moments_ZonePvPRole("friendly"), "success")
	eq(ns.Moments_ZonePvPRole("contested"), "warning")
	eq(ns.Moments_ZonePvPRole("hostile"), "danger")
	eq(ns.Moments_ZonePvPRole("combat"), "danger")
	eq(ns.Moments_ZonePvPRole(nil), "textMuted", "no PvP type")
end)

test("ZoneStatus: strips brackets, nil when empty", function()
	eq(ns.Moments_ZoneStatus("(Sanctuary)"), "Sanctuary")
	eq(ns.Moments_ZoneStatus("(Horde Territory)"), "Horde Territory")
	eq(ns.Moments_ZoneStatus("\239\188\136安全区域\239\188\137"), "安全区域", "full-width")
	eq(ns.Moments_ZoneStatus("Combat Zone"), "Combat Zone", "no brackets")
	eq(ns.Moments_ZoneStatus(""), nil)
	eq(ns.Moments_ZoneStatus("  "), nil)
	eq(ns.Moments_ZoneStatus(nil), nil)
end)

-- The game's discovery formats per client language (wago.tools GlobalStrings, ERR_ZONE_EXPLORED_XP and
-- ERR_ZONE_EXPLORED, 2026-10-19): xp format, plain format, an xp message, a plain message, the area.
local LOCALES = {
	{ "deDE", "%1$s entdeckt: %2$d Erfahrung erhalten.", "Entdeckt: %s",
		"Goldhain entdeckt: 30 Erfahrung erhalten.", "Entdeckt: Goldhain", "Goldhain" },
	{ "frFR", "Découverte : %s, %d points d’expérience gagnés", "Découverte : %s",
		"Découverte : Comté-de-l'Or, 30 points d’expérience gagnés", "Découverte : Comté-de-l'Or", "Comté-de-l'Or" },
	{ "esES", "Has descubierto %s: %d p. de experiencia obtenidos.", "Has descubierto: %s",
		"Has descubierto Villadorada: 30 p. de experiencia obtenidos.", "Has descubierto: Villadorada", "Villadorada" },
	{ "ruRU", "Открыта новая территория: %s. Получено %d |4очко:очка:очков; опыта.", "Открыта новая территория: %s",
		"Открыта новая территория: Златоземье. Получено 30 очков опыта.", "Открыта новая территория: Златоземье",
		"Златоземье" },
	{ "koKR", "%s 발견: 경험치 %d 획득", "%s|1을;를; 발견했습니다!",
		"골드샤이어 발견: 경험치 30 획득", "골드샤이어를 발견했습니다!", "골드샤이어" },
	{ "zhCN", "发现%s：获得%d点经验值", "发现：%s", "发现闪金镇：获得30点经验值", "发现：闪金镇", "闪金镇" },
}

local TOAST_TYPES = { LevelUp = 1, PetBattleCapture = 7, Quest = 3 }

local function toastDB(levelup, pet)
	return { replaceLevelUp = true, replacePetCapture = true, styles = { levelup = levelup, pet = pet } }
end

test("ReplacesToast: level-up and capture toasts hide while their moment is on", function()
	local db = toastDB("banner", "cinematic")
	eq(ns.Moments_ReplacesToast(1, TOAST_TYPES, db), true)
	eq(ns.Moments_ReplacesToast(7, TOAST_TYPES, db), true)
	eq(ns.Moments_ReplacesToast(3, TOAST_TYPES, db), false)
end)

test("ReplacesToast: kept when the moment is off or the setting is off", function()
	eq(ns.Moments_ReplacesToast(7, TOAST_TYPES, toastDB("banner", "off")), false)
	eq(ns.Moments_ReplacesToast(1, TOAST_TYPES, toastDB("off", "banner")), false)
	local db = toastDB("banner", "banner")
	db.replacePetCapture = false
	eq(ns.Moments_ReplacesToast(7, TOAST_TYPES, db), false)
	eq(ns.Moments_ReplacesToast(1, TOAST_TYPES, db), true)
end)

test("ReplacesToast: a client without the capture toast type", function()
	eq(ns.Moments_ReplacesToast(7, { LevelUp = 1 }, toastDB("banner", "banner")), false)
end)

test("DiscoveredArea: the game's formats in six client languages", function()
	for _, l in ipairs(LOCALES) do
		local patterns = ns.Moments_DiscoveryPatterns(l[2], l[3])
		eq(ns.Moments_DiscoveredArea(l[4], patterns), l[6], l[1] .. " with xp")
		eq(ns.Moments_DiscoveredArea(l[5], patterns), l[6], l[1] .. " plain")
	end
end)

test("DiscoveredArea: odd formats and messages return, never error", function()
	local formats = { "", "%d", "%s%%", "|4a:b;%s", "%2$s %1$d", "|1x;y;", "%s|4", "100%% %s" }
	local messages = { "", "%", "50% done", "Discovered: (x)", "a:b" }
	for _, fmt in ipairs(formats) do
		local patterns = ns.Moments_DiscoveryPatterns(fmt, fmt)
		for _, message in ipairs(messages) do
			ns.Moments_DiscoveredArea(message, patterns) -- an error here fails the test
		end
	end
end)

H.done()
