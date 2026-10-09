local addonName, ns = ...

-- Gear Check's built-in sets, one per expansion in Data/<Expansion>/Gear.lua (ns.Content_Register(expansion, "gear",
-- set)), refreshed by hand each season. A character uses the set of its content expansion (ns.ContentExpansion of
-- its level), so a War Within character gets War Within weights and gems whatever the account owns. Imported
-- weights (/tomte gear import) always win over these.
--
-- A set: {
--   seasonName = "Midnight S2", -- shown in /tomte gear weights and hints
--   season = 37,                -- C_SeasonInfo.GetCurrentDisplaySeasonID() it's from (nil: unknown)
--   final = true,               -- the expansion's last season: never "stale" (Gear_WeightsHint)
--   specs = { [specID] = { label = "sims, Midnight S2", weights = { STR = 1, CRIT = 0.8, ... } } },
--   gems = { itemID, ... },     -- secondary-stat gems, best one picked for the weights (stats read in game)
--   diamonds = { itemID, ... }, diamondName = "...", -- the unique main-stat gem: only pointed out when none is worn
-- }
-- Label starting with "guide priority" (Gear_IsGuideLabel): guide ladder, not a sim. Spec IDs from
-- warcraft.wiki.gg SpecializationID; /tomte gear specs checks them against the game.

-- No set for an expansion: no built-in weights (the neutral fallback and the import hint), no gem advice.
ns.GEAR_NO_SCALES = { specs = {}, gems = {}, diamonds = {}, diamondIDs = {}, final = true, missing = true }

-- The set for an expansion (never nil), with expansion and name filled in.
function ns.Gear_ScalesFor(expansion)
	local set = ns.Content_Get(expansion, "gear")
	if not set then
		return ns.GEAR_NO_SCALES
	end
	if not set.expansion then
		set.expansion = expansion
		set.specs, set.gems, set.diamonds = set.specs or {}, set.gems or {}, set.diamonds or {}
		set.diamondIDs = {}
		for _, id in ipairs(set.diamonds or {}) do
			set.diamondIDs[id] = true
		end
	end
	return set
end

-- The set for a character's level (nil: the player's). A levelling character older than every set (below The War
-- Within's band) gets the oldest set: weights still beat item level alone.
function ns.Gear_ScalesForLevel(level)
	local expansion = ns.ContentExpansion(level)
	if expansion and not ns.EXPANSION_NAMES[expansion] then -- older than Tomte's data
		for _, e in ipairs(ns.Content_Expansions()) do
			if e > expansion and ns.Content_Get(e, "gear") then
				expansion = e
				break
			end
		end
	end
	return ns.Gear_ScalesFor(expansion)
end

-- "War Within S3 (The War Within)" for chat, or "none for Midnight".
function ns.Gear_ScalesName(set, expansion)
	if set.missing then
		return "none for " .. ns.ExpansionName(expansion)
	end
	return ("%s (%s)"):format(set.seasonName or "?", ns.ExpansionName(set.expansion))
end

-- /tomte data: the set this character uses, whether its spec has weights, whether the gems resolve.
if ns.Content_AddCheck then
	ns.Content_AddCheck("gear", function(expansion)
		local set = ns.Gear_ScalesFor(expansion)
		if set.missing then
			return { "!no built-in set for " .. ns.ExpansionName(expansion) .. " (neutral weights, import to fix)" }
		end
		local lines = { ("set %s, season %s%s"):format(ns.Gear_ScalesName(set, expansion), tostring(set.season),
			set.final and ", final" or "") }
		local index = C_SpecializationInfo.GetSpecialization()
		local specID, specName
		if index then
			specID, specName = C_SpecializationInfo.GetSpecializationInfo(index)
		end
		if specID and specID ~= 0 then
			local scale = set.specs[specID]
			lines[#lines + 1] = scale and ("%s: %s"):format(specName, scale.label)
				or ("!no built-in weights for %s (%d)"):format(tostring(specName), specID)
		end
		local missing, waiting = {}, 0
		for _, list in ipairs({ set.gems or {}, set.diamonds or {} }) do
			for _, id in ipairs(list) do
				if not C_Item.GetItemInfoInstant(id) then
					missing[#missing + 1] = tostring(id)
				elseif not C_Item.GetItemInfo(id) then
					waiting = waiting + 1
					C_Item.RequestLoadItemDataByID(id)
				end
			end
		end
		local total = #(set.gems or {}) + #(set.diamonds or {})
		lines[#lines + 1] = ("gems: %d of %d named%s"):format(total - #missing - waiting, total,
			waiting > 0 and (", %d not cached yet (run again)"):format(waiting) or "")
		if #missing > 0 then
			lines[#lines + 1] = "!unknown gem IDs: " .. table.concat(missing, ", ")
		end
		local first = set.gems and set.gems[1]
		local name = first and C_Item.GetItemInfo(first)
		if name then
			lines[#lines + 1] = ("e.g. %d = %s; %s"):format(first, name, tostring(set.diamondName))
		end
		return lines
	end)
end
