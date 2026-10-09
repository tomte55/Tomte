local addonName, ns = ...

-- Which expansion's content a character is in, and the hand-kept data per expansion (Data/<Expansion>/*.lua).
-- A character follows its level band (the rule Blizzard's Group Finder and Encounter Journal use:
-- GetExpansionForLevel), capped at what the account owns (GetExpansionLevel). Enum.ExpansionLevel: 10 The War
-- Within, 11 Midnight. Modules read data with Content_Get and add in-game checks for /tomte data with
-- Content_AddCheck. See docs/superpowers/specs/2026-10-09-tomte-content-expansion-design.md.

ns.EXPANSION_NAMES = { [10] = "The War Within", [11] = "Midnight" }

local data = {} -- [expansion][key] = table
local checks = {} -- { { name, fn(expansion) -> lines } }

-- Pure: forLevel = GetExpansionForLevel(level) (may be nil), owned = GetExpansionLevel().
function ns.Content_Resolve(forLevel, owned)
	if not owned then
		return forLevel
	end
	if not forLevel or forLevel > owned then
		return owned
	end
	return forLevel
end

-- The content expansion for a level (default: the player's).
function ns.ContentExpansion(level)
	level = level or UnitLevel("player")
	if issecretvalue and issecretvalue(level) then
		level = nil
	end
	local forLevel = level and GetExpansionForLevel and GetExpansionForLevel(level)
	return ns.Content_Resolve(forLevel, GetExpansionLevel and GetExpansionLevel())
end

-- That expansion's max level (80 for The War Within, 90 for Midnight); nil when the game doesn't say.
function ns.ContentMaxLevel(expansion)
	return expansion and GetMaxLevelForExpansionLevel and GetMaxLevelForExpansionLevel(expansion)
end

-- True when the character is at its content expansion's max level (weekly snapshots, max-level views).
function ns.ContentAtMax(level)
	level = level or UnitLevel("player")
	if issecretvalue and issecretvalue(level) then
		return false
	end
	local maxLevel = ns.ContentMaxLevel(ns.ContentExpansion(level))
	return not maxLevel or level >= maxLevel
end

function ns.ExpansionName(expansion)
	return ns.EXPANSION_NAMES[expansion] or ("expansion " .. tostring(expansion))
end

function ns.Content_Register(expansion, key, value)
	data[expansion] = data[expansion] or {}
	data[expansion][key] = value
end

function ns.Content_Get(expansion, key)
	return expansion and data[expansion] and data[expansion][key]
end

-- The expansions that registered anything, oldest first.
function ns.Content_Expansions()
	local list = {}
	for expansion in pairs(data) do
		list[#list + 1] = expansion
	end
	table.sort(list)
	return list
end

-- fn(expansion) returns a list of lines (strings) describing what it found; prefix problems with "!".
function ns.Content_AddCheck(name, fn)
	checks[#checks + 1] = { name = name, fn = fn }
end

-- /tomte data: what Tomte knows for this character's expansion, for a friend to paste.
function ns.Content_Report()
	local level = UnitLevel("player")
	local owned = GetExpansionLevel and GetExpansionLevel()
	local expansion = ns.ContentExpansion()
	local season = C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID and C_SeasonInfo.GetCurrentDisplaySeasonID()
	ns.Print(("data: version %s, level %s, owns %s, content %s (max level %s), season %s."):format(ns.VERSION,
		tostring(level), ns.ExpansionName(owned), ns.ExpansionName(expansion), tostring(ns.ContentMaxLevel(expansion)),
		tostring(season)))
	local keys = {}
	for key in pairs(data[expansion] or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	print(("  tables: %s"):format(#keys > 0 and table.concat(keys, ", ") or "none"))
	for _, check in ipairs(checks) do
		local ok, lines = pcall(check.fn, expansion)
		if not ok then
			lines = { "!error: " .. tostring(lines) }
		end
		for _, line in ipairs(lines or {}) do
			local bad = line:sub(1, 1) == "!"
			print(("  %s%s: %s|r"):format(bad and "|cffff6060" or "|cffcccccc", check.name, bad and line:sub(2) or line))
		end
	end
end
