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
