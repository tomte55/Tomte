local addonName, ns = ...

-- Graphics presets: pure logic (no WoW API calls; unit-tested in tests/test_graphics.lua). Which situation applies,
-- which preset wins, what to write and what to restore. The game reads and writes are in Graphics.lua.

-- Situations in priority order: the first one that applies and has a preset wins. Instances exclude each other;
-- outside them AFK beats a city, a city beats the open world.
ns.GRAPHICS_SITUATIONS = {
	{ key = "pvp", label = "Battlegrounds and arenas" },
	{ key = "raid", label = "Raids" },
	{ key = "dungeon", label = "Dungeons and delves" },
	{ key = "afk", label = "While AFK" },
	{ key = "city", label = "Cities and inns" },
	{ key = "world", label = "Open world" },
}

-- What each preset group sets. quality: Blizzard's overall Graphics Quality slider and the settings it moves
-- (the list in Blizzard_Settings_Shared/Mainline/GraphicsOverrides.lua); fps: the foreground frame rate cap.
ns.GRAPHICS_GROUPS = { "quality", "fps" }

-- The Graphics Quality slider's sub-settings, in Blizzard's order. min: the lowest value Blizzard's slider sets
-- (particle density never goes below 1 outside raids); spellDensity: only where the client supports it.
ns.GRAPHICS_QUALITY_SUBS = {
	{ cvar = "graphicsShadowQuality" },
	{ cvar = "graphicsLiquidDetail" },
	{ cvar = "graphicsParticleDensity", min = 1 },
	{ cvar = "graphicsSSAO" },
	{ cvar = "graphicsDepthEffects" },
	{ cvar = "graphicsComputeEffects" },
	{ cvar = "graphicsOutlineMode" },
	{ cvar = "graphicsTextureResolution" },
	{ cvar = "graphicsSpellDensity", spellDensity = true },
	{ cvar = "graphicsProjectedTextures" },
	{ cvar = "graphicsViewDistance" },
	{ cvar = "graphicsEnvironmentDetail" },
	{ cvar = "graphicsGroundClutter" },
}
ns.GRAPHICS_QUALITY_CVAR = "graphicsQuality"
ns.GRAPHICS_FPS_CVARS = { "useMaxFPS", "maxFPS" }

local QUALITY_LEVELS = 10 -- the slider shows 1-10; the CVar holds 0-9

-- "graphicsShadowQuality" -> "raidGraphicsShadowQuality": the Raid and Battleground copy of a setting.
function ns.Graphics_RaidCVar(cvar)
	return "raid" .. cvar:sub(1, 1):upper() .. cvar:sub(2)
end

-- Every CVar Tomte may touch, in write order: the overall quality before the settings it moves (Blizzard's slider
-- writes the CVar, then its change callback sets the rest), the raid copies, then the frame rate cap.
function ns.Graphics_AllCVars()
	local list = { ns.GRAPHICS_QUALITY_CVAR }
	for _, sub in ipairs(ns.GRAPHICS_QUALITY_SUBS) do
		list[#list + 1] = sub.cvar
	end
	list[#list + 1] = ns.Graphics_RaidCVar(ns.GRAPHICS_QUALITY_CVAR)
	for _, sub in ipairs(ns.GRAPHICS_QUALITY_SUBS) do
		list[#list + 1] = ns.Graphics_RaidCVar(sub.cvar)
	end
	for _, cvar in ipairs(ns.GRAPHICS_FPS_CVARS) do
		list[#list + 1] = cvar
	end
	return list
end

-- [cvar] = group name, for every CVar in Graphics_AllCVars.
function ns.Graphics_GroupOf()
	local groups = {}
	for _, cvar in ipairs(ns.Graphics_AllCVars()) do
		groups[cvar] = "quality"
	end
	for _, cvar in ipairs(ns.GRAPHICS_FPS_CVARS) do
		groups[cvar] = "fps"
	end
	return groups
end

-- The slider's level (1-10) as the graphicsQuality value (0-9), nil for anything else.
function ns.Graphics_QualityValue(level)
	if type(level) ~= "number" or level < 1 or level > QUALITY_LEVELS then
		return nil
	end
	return math.floor(level) - 1
end

-- ctx = { instanceType, difficultyID (GetInstanceInfo), resting (bool), afk (bool) } -> situation keys that apply,
-- in priority order.
function ns.Graphics_Situations(ctx)
	local instanceType = ctx.instanceType
	if instanceType == "pvp" or instanceType == "arena" then
		return { "pvp" }
	end
	local kind = ns.Check_ContentKind(instanceType, ctx.difficultyID)
	if kind == "raid" then
		return { "raid" }
	elseif kind == "dungeon" or kind == "delve" or instanceType == "scenario" then
		return { "dungeon" } -- every other scenario too (visions, story scenarios): small group content
	end
	local list = {}
	if ctx.afk then
		list[#list + 1] = "afk"
	end
	if ctx.resting then
		list[#list + 1] = "city"
	end
	list[#list + 1] = "world"
	return list
end

-- The first applying situation whose preset for `group` isn't "leave alone" (0): situation key, value. Each group
-- falls through on its own, so AFK can cap the frame rate while the city's quality level stays.
function ns.Graphics_Winner(situations, presets, group)
	local values = presets[group] or {}
	for _, key in ipairs(situations) do
		local value = values[key]
		if type(value) == "number" and value > 0 then
			return key, value
		end
	end
	return nil, nil
end

-- What to apply per group: { quality = { situation, value } | nil, fps = ... }. paused[group] = the situation the
-- player changed that group's settings in by hand: Tomte keeps out of that group until another situation wins
-- (a different preset or none). Clears paused entries that no longer hold.
function ns.Graphics_Decide(situations, presets, paused)
	local out = {}
	for _, group in ipairs(ns.GRAPHICS_GROUPS) do
		local key, value = ns.Graphics_Winner(situations, presets, group)
		if paused[group] ~= nil and paused[group] ~= (key or false) then
			paused[group] = nil
		end
		if key and paused[group] == nil then
			out[group] = { situation = key, value = value }
		end
	end
	return out
end

-- CVar values compare as numbers when both read as numbers ("1" and "1.0" are the same), else as strings.
function ns.Graphics_Same(a, b)
	local x, y = tonumber(a), tonumber(b)
	if x and y then
		return x == y
	end
	return tostring(a) == tostring(b)
end

-- Writes that bring the CVars to `wanted` ([cvar] = value; a CVar not in it goes back to the player's own value).
-- saved: [cvar] = the player's own value, kept the first time Tomte changes a CVar and dropped once restored
-- (changed in place). current: [cvar] = the value now (nil: the CVar doesn't exist on this client, never touched).
-- order: every CVar in write order. Returns { { cvar, value } } in that order.
function ns.Graphics_Plan(saved, wanted, current, order)
	local writes = {}
	for _, cvar in ipairs(order) do
		local now, want = current[cvar], wanted[cvar]
		if now ~= nil then
			if want ~= nil then
				if saved[cvar] == nil then
					saved[cvar] = now
				end
				if not ns.Graphics_Same(now, want) then
					writes[#writes + 1] = { cvar = cvar, value = want }
				end
			elseif saved[cvar] ~= nil then
				if not ns.Graphics_Same(now, saved[cvar]) then
					writes[#writes + 1] = { cvar = cvar, value = saved[cvar] }
				end
				saved[cvar] = nil
			end
		end
	end
	return writes
end

-- Groups whose CVars someone else changed: a CVar Tomte set (applied[cvar], what it read back after writing) that
-- now reads differently. groupOf: Graphics_GroupOf(). Returns { [group] = true }.
function ns.Graphics_ChangedGroups(applied, current, groupOf)
	local changed = {}
	for cvar, value in pairs(applied) do
		local now = current[cvar]
		if now ~= nil and not ns.Graphics_Same(now, value) and groupOf[cvar] then
			changed[groupOf[cvar]] = true
		end
	end
	return changed
end

-- The player's own choice wins: forget the kept originals and what Tomte set for every CVar of `group`, so the
-- values the player picked are now theirs (nothing is written).
function ns.Graphics_Adopt(saved, applied, group, groupOf)
	for _, t in ipairs({ saved, applied }) do
		for cvar in pairs(t) do
			if groupOf[cvar] == group then
				t[cvar] = nil
			end
		end
	end
end

-- Label for a quality preset (slider value): "Leave alone" or "Level 4".
function ns.Graphics_QualityText(value)
	if not value or value <= 0 then
		return "Leave alone"
	end
	return "Level " .. value
end

-- Label for a frame rate cap preset (slider value): "Leave alone" or "60 fps".
function ns.Graphics_FPSText(value)
	if not value or value <= 0 then
		return "Leave alone"
	end
	return value .. " fps"
end

-- A settings slider's value text (a narrow column, so no unit): "off" for leave alone, else the number.
function ns.Graphics_SliderText(value)
	if not value or value <= 0 then
		return "off"
	end
	return tostring(value)
end
