local addonName, ns = ...

-- Moments: pure logic (no WoW API calls; unit-tested with plain Lua). Moment types, style decisions and
-- message parsing.

-- In options order. style = the default.
ns.MOMENT_TYPES = {
	{ key = "levelup", name = "Level up", style = "cinematic" },
	{ key = "achievement", name = "Achievement", style = "banner" },
	{ key = "mount", name = "New mount", style = "cinematic" },
	{ key = "pet", name = "New battle pet", style = "banner" },
	{ key = "toy", name = "New toy", style = "banner" },
	{ key = "zone", name = "New zone", style = "cinematic" },
	{ key = "discovery", name = "Area discovered", style = "banner" },
	{ key = "renown", name = "Renown", style = "banner" },
	{ key = "chapter", name = "Campaign chapter", style = "cinematic" },
	{ key = "house", name = "House level", style = "banner" },
	{ key = "tame", name = "Tamed pet (hunter)", style = "cinematic" },
}

ns.MOMENT_STYLES = {
	{ value = "off", text = "Off" },
	{ value = "banner", text = "Banner" },
	{ value = "cinematic", text = "Cinematic" },
}

function ns.Moments_DefaultStyles()
	local styles = {}
	for _, t in ipairs(ns.MOMENT_TYPES) do
		styles[t.key] = t.style
	end
	return styles
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

-- "Discovered: %s" -> "^Discovered: (.+)$" (also %d -> (%d+)). Other magic characters are escaped.
function ns.Moments_FormatToPattern(fmt)
	local escaped = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	escaped = escaped:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. escaped .. "$"
end

-- The area name from a "Discovered" info message, or nil. patterns from FormatToPattern.
function ns.Moments_DiscoveredArea(message, patterns)
	if type(message) ~= "string" then
		return nil
	end
	for _, pattern in ipairs(patterns) do
		local area = message:match(pattern)
		if area then
			return area
		end
	end
	return nil
end

-- Blizzard toasts an achievement unless it's a repeat on the account; guild ones are left out here.
function ns.Moments_ShouldShowAchievement(alreadyEarned, isGuild)
	return not alreadyEarned and not isGuild
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

-- Reveal tiers for collected creatures (mount, battle pet, tame), lowest first. Each tier adds effects:
-- rays = rotating light rays, spin = the model spins in, sparkles = rising sparks, bigFlash = a stronger
-- screen flash, charge = seconds of build-up before the reveal, extraTime = seconds added to the moment.
-- color = item quality color, glow = a lighter shade for additive glows. sounds = SOUNDKIT keys.
ns.MOMENT_TIERS = { "common", "rare", "epic", "legendary" }

ns.MOMENT_TIER_FX = {
	common = {
		name = "New", color = { 1, 0.82, 0.45 }, glow = { 1, 0.85, 0.55 },
		flash = 0.25, charge = 0, extraTime = 0,
		sounds = { "UI_EPICLOOT_TOAST" },
	},
	rare = {
		name = "Rare", color = { 0, 0.44, 0.87 }, glow = { 0.3, 0.62, 1 },
		flash = 0.35, rays = true, spin = true, charge = 0, extraTime = 0,
		sounds = { "UI_STORE_UNWRAP" },
	},
	epic = {
		name = "Epic", color = { 0.64, 0.21, 0.93 }, glow = { 0.72, 0.42, 1 },
		flash = 0.55, rays = true, spin = true, sparkles = true, bigFlash = true, charge = 0, extraTime = 1,
		sounds = { "UI_STORE_UNWRAP", "CATALOG_SHOP_GOLD_SHIMMER_START" },
	},
	legendary = {
		name = "Legendary", color = { 1, 0.5, 0 }, glow = { 1, 0.62, 0.2 },
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
