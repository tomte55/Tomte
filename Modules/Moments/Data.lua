local addonName, ns = ...

-- Moments: pure logic (no WoW API calls; unit-tested with plain Lua). Moment types, style decisions and
-- message parsing.

-- In options order. style = the default.
ns.MOMENT_TYPES = {
	{ key = "levelup", name = "Level up", style = "cinematicMax" },
	{ key = "achievement", name = "Achievement", style = "banner" },
	{ key = "mount", name = "New mount", style = "cinematic" },
	{ key = "pet", name = "New battle pet", style = "banner" },
	{ key = "toy", name = "New toy", style = "banner" },
	{ key = "zone", name = "New zone", style = "cinematic" },
	{ key = "discovery", name = "Area discovered", style = "banner" },
	{ key = "renown", name = "Renown", style = "banner" },
	{ key = "companion", name = "Companion level (delves)", style = "banner" },
	{ key = "chapter", name = "Campaign chapter", style = "cinematic" },
	{ key = "house", name = "House level", style = "banner" },
	{ key = "tame", name = "Tamed pet (hunter)", style = "cinematic" },
	{ key = "upgrade", name = "Gear upgrade (Gear Check)", style = "cinematic" },
}

ns.MOMENT_STYLES = {
	{ value = "off", text = "Off" },
	{ value = "banner", text = "Banner" },
	{ value = "cinematic", text = "Cinematic" },
	{ value = "cinematicMax", text = "Cinematic at max level" },
}

function ns.Moments_DefaultStyles()
	local styles = {}
	for _, t in ipairs(ns.MOMENT_TYPES) do
		styles[t.key] = t.style
	end
	return styles
end

-- "Cinematic at max level" (cinematicMax): a banner below the expansion's max level, so levelling (a level every
-- few minutes) isn't a string of 7-second cutscenes, and a cinematic from there on. The level-up that reaches max
-- level passes its new level, so it still gets its cinematic. level or maxLevel nil (unknown) = cinematic.
-- Returns "off", "banner" or "cinematic".
function ns.Moments_LevelStyle(style, level, maxLevel)
	if style ~= "cinematicMax" then
		return style
	end
	if type(level) == "number" and type(maxLevel) == "number" and level < maxLevel then
		return "banner"
	end
	return "cinematic"
end

-- Settings from before 1.6 had one "Cinematics only at max level" checkbox (default on) that turned every
-- Cinematic except mounts and tames into a banner while levelling. Keeps that behavior with the per-moment
-- style: Cinematic becomes Cinematic at max level when the checkbox was on. db = the Moments settings or nil.
function ns.Moments_MigrateAtMax(db)
	if type(db) ~= "table" then
		return
	end
	if db.cinematicsAtMax ~= false and type(db.styles) == "table" then
		for key, style in pairs(db.styles) do
			if style == "cinematic" and key ~= "mount" and key ~= "tame" then
				db.styles[key] = "cinematicMax"
			end
		end
	end
	db.cinematicsAtMax = nil
end

-- A cinematic moment waits for a safe moment, then shows; after maxWait seconds it becomes a banner.
-- Returns "cinematic", "banner" or "wait".
function ns.Moments_Decide(canPlay, waited, maxWait)
	if canPlay then
		return "cinematic"
	end
	if waited >= maxWait then
		return "banner"
	end
	return "wait"
end

-- Matchers for the discovery messages, the XP variant first: a shorter format ("Découverte : %s") would
-- also match it and swallow the experience into the area name.
function ns.Moments_DiscoveryPatterns(withXP, plain)
	local list = {}
	for _, fmt in ipairs({ withXP or false, plain or false }) do
		if type(fmt) == "string" then
			local pattern, spec = ns.FormatToPattern(fmt)
			list[#list + 1] = { pattern = pattern, spec = spec }
		end
	end
	return list
end

-- The area name (the format's first argument) from a "Discovered" info message, or nil. patterns =
-- FormatToPattern strings or { pattern, spec } tables (Moments_DiscoveryPatterns).
function ns.Moments_DiscoveredArea(message, patterns)
	if type(message) ~= "string" then
		return nil
	end
	for _, p in ipairs(patterns) do
		local captures
		if type(p) == "table" then
			captures = ns.FormatMatch(message, p.pattern, p.spec)
		else
			captures = ns.FormatMatch(message, p)
		end
		if captures and captures[1] then
			return captures[1]
		end
	end
	return nil
end

-- Blizzard toasts an achievement unless it's a repeat on the account; guild ones are left out here.
function ns.Moments_ShouldShowAchievement(alreadyEarned, isGuild)
	return not alreadyEarned and not isGuild
end

-- Blizzard's event toasts that say what one of our moments says: the moment type and the setting that hides it.
local REPLACED_TOASTS = {
	LevelUp = { kind = "levelup", setting = "replaceLevelUp" },
	PetBattleCapture = { kind = "pet", setting = "replacePetCapture" },
}

-- Hide this Blizzard toast? eventType = the toast's Enum.EventToastEventType value, toastTypes = that enum,
-- db = Moments' saved settings.
function ns.Moments_ReplacesToast(eventType, toastTypes, db)
	for name, rule in pairs(REPLACED_TOASTS) do
		if toastTypes[name] ~= nil and eventType == toastTypes[name] then
			return db[rule.setting] == true and (db.styles[rule.kind] or "off") ~= "off"
		end
	end
	return false
end

function ns.Moments_LevelLabel(level, maxLevel)
	if maxLevel and level >= maxLevel then
		return "Maximum level"
	end
	return "Level up"
end

-- After a discovery: was it the first in a whole new zone? before = explored map overlays when we
-- entered the zone (nil when the discovery came first), after = overlays now. A zone without map fog has
-- no overlays at all and never counts.
function ns.Moments_IsNewZone(before, after)
	if after == 0 then
		return false
	end
	if before == nil then
		return after <= 1
	end
	return before == 0
end

-- An owned house's level just went up: saved = the highest level seen before for that house (nil the first
-- time we see it, so a house never celebrates the level it already had when we first read it).
function ns.Moments_HouseLevelUp(saved, level)
	return saved ~= nil and level > saved
end

-- Zone text: the theme color role for C_PvP.GetZonePVPInfo's pvpType (Blizzard tints its zone text the same way).
local ZONE_PVP_ROLES = {
	sanctuary = "accent", friendly = "success", contested = "warning",
	hostile = "danger", arena = "danger", combat = "danger",
}

function ns.Moments_ZonePvPRole(pvpType)
	return ZONE_PVP_ROLES[pvpType] or "textMuted"
end

-- "(Sanctuary)" -> "Sanctuary": Blizzard's PvP line without its brackets (ASCII or full-width), nil when empty.
function ns.Moments_ZoneStatus(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	text = text:gsub("^%((.*)%)$", "%1"):gsub("^\239\188\136(.*)\239\188\137$", "%1")
	if text == "" then
		return nil
	end
	return text
end

-- Reveal tiers for collected creatures (mount, battle pet, tame), lowest first. Each tier adds effects:
-- rays = rotating light rays, spin = the model spins in, sparkles = rising sparks, bigFlash = a stronger
-- screen flash, charge = seconds of build-up before the reveal, extraTime = seconds added to the moment.
-- color = item quality color, glow = a lighter shade for additive glows. sounds = SOUNDKIT keys.
-- role = draw color and glow in this theme role instead (Scene.lua); the tables are then only a fallback.
ns.MOMENT_TIERS = { "common", "rare", "epic", "legendary" }

ns.MOMENT_TIER_FX = {
	common = {
		name = "New", color = { 1, 1, 1 }, glow = { 1, 1, 1 }, role = "accent",
		flash = 0.25, charge = 0, extraTime = 0,
		sounds = { "UI_EPICLOOT_TOAST" },
	},
	rare = {
		name = "Rare", color = { 0, 0.44, 0.87 }, glow = { 0.3, 0.62, 1 }, -- theme: item quality color
		flash = 0.35, rays = true, spin = true, charge = 0, extraTime = 0,
		sounds = { "UI_STORE_UNWRAP" },
	},
	epic = {
		name = "Epic", color = { 0.64, 0.21, 0.93 }, glow = { 0.72, 0.42, 1 }, -- theme: item quality color
		flash = 0.55, rays = true, spin = true, sparkles = true, bigFlash = true, charge = 0, extraTime = 1,
		sounds = { "UI_STORE_UNWRAP", "CATALOG_SHOP_GOLD_SHIMMER_START" },
	},
	legendary = {
		name = "Legendary", color = { 1, 0.5, 0 }, glow = { 1, 0.62, 0.2 }, -- theme: item quality color
		flash = 0.75, rays = true, doubleRays = true, spin = true, sparkles = true, bigFlash = true,
		charge = 1, extraTime = 3,
		sounds = { "UI_LEGENDARY_LOOT_TOAST", "CATALOG_SHOP_GOLD_SHIMMER_START" },
	},
}

function ns.Moments_IsTier(tier)
	return ns.MOMENT_TIER_FX[tier] ~= nil
end

-- percent = share of players owning the mount (MountsRarity), nil when unknown. Same cut-offs as Mount
-- Journal Enhanced's name colors. Unknown counts as rare: a new mount is always worth a little more.
function ns.Moments_MountTier(percent)
	if not percent then
		return "rare"
	end
	if percent < 2 then
		return "legendary"
	elseif percent < 10 then
		return "epic"
	elseif percent < 20 then
		return "rare"
	end
	return "common"
end

-- Battle pet quality: 1 poor ... 4 rare, 5 epic, 6 legendary.
function ns.Moments_PetTier(quality)
	if not quality or quality <= 3 then
		return "common"
	elseif quality == 4 then
		return "rare"
	elseif quality == 5 then
		return "epic"
	end
	return "legendary"
end

function ns.Moments_TameTier(exotic, rareSpawn)
	if exotic and rareSpawn then
		return "epic"
	elseif exotic or rareSpawn then
		return "rare"
	end
	return "common"
end

function ns.Moments_IsRareClassification(classification)
	return classification == "rare" or classification == "rareelite"
end

-- ("rare", "mount") -> "Rare mount"; common -> "New mount".
function ns.Moments_TierLabel(tier, noun)
	local fx = ns.MOMENT_TIER_FX[tier] or ns.MOMENT_TIER_FX.common
	return fx.name .. " " .. noun
end

function ns.Moments_OwnedLine(percent)
	if not percent then
		return nil
	end
	local text
	if percent < 0.01 then
		text = "less than 0.01"
	elseif percent < 1 then
		text = ("%.2f"):format(percent)
	elseif percent < 10 then
		text = ("%.1f"):format(percent)
	else
		text = ("%d"):format(math.floor(percent + 0.5))
	end
	return "Owned by " .. text .. "% of players"
end
