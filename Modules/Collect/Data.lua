local addonName, ns = ...

-- Collect here, pure logic (unit-tested with plain Lua): reading the journals' source text, matching its zone names
-- against a map's names, whole-word achievement matching, the tab's sections and the toast text. The game has no
-- zone data for collectibles, only these labelled source lines ("Drop: Doomwalker|nZone: Tanaris"), in English here.

local ZONE_LABELS = { zone = true, location = true, ["pet battle"] = true }

-- The first of these labels becomes a row's source line.
local LINE_LABELS = {
	"drop", "vendor", "quest", "achievement", "treasure", "world event", "holiday", "pet battle", "profession",
	"discovery", "trading post", "in-game shop", "promotion", "trading card game",
}

-- A qualifier on a zone value that's worth showing next to the source line.
local DIFFICULTIES = {
	normal = true, heroic = true, mythic = true, ["raid finder"] = true, lfr = true, timewalking = true,
	["10 player"] = true, ["25 player"] = true,
}

-- Source names that aren't map names.
local ALIASES = {
	["capital cities"] = { "stormwind city", "orgrimmar", "ironforge", "darnassus", "undercity", "thunder bluff",
		"the exodar", "silvermoon city" },
	["stormwind"] = { "stormwind city" },
	["exodar"] = { "the exodar" },
	["silvermoon"] = { "silvermoon city" },
}

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function StripColors(s)
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function ns.Collect_Clean(text)
	if not text then
		return ""
	end
	return Trim(StripColors(text):gsub("|T.-|t", ""))
end

local function DropQualifier(s)
	return Trim((s:gsub("%s*%b()%s*$", "")))
end

local function Qualifier(s)
	return s:match("%(([^()]*)%)%s*$")
end

local function AddUnique(list, seen, value)
	if value ~= "" and not seen[value] then
		seen[value] = true
		list[#list + 1] = value
	end
end

-- "A, B (Heroic), C" -> whole value, each piece, and neighbouring pieces joined again (names can contain a comma:
-- "Amirdrassil, the Dream's Hope"). Lower case, trailing "(...)" dropped.
function ns.Collect_Candidates(value)
	local out, seen = {}, {}
	local function add(s)
		AddUnique(out, seen, DropQualifier(s):lower())
	end
	add(value)
	local pieces = {}
	for piece in (value .. ","):gmatch("([^,]*),") do
		pieces[#pieces + 1] = DropQualifier(piece)
	end
	for i, piece in ipairs(pieces) do
		add(piece)
		if pieces[i + 1] then
			add(piece .. ", " .. pieces[i + 1])
		end
	end
	return out
end

-- raw journal source text -> { lines = { { label, display, value, raw } }, zones, drop, line }.
-- label: lower case without the colon; value: cleaned; raw: colors stripped, textures kept (the gold icon).
function ns.Collect_ParseSource(raw)
	local result = { lines = {}, zones = {} }
	if not raw or raw == "" then
		return result
	end
	local seen = {}
	local qualifier
	raw = raw:gsub("\r?\n", "|n") -- a few sources break lines for real
	for segment in (raw .. "|n"):gmatch("(.-)|n") do
		local plain = StripColors(segment)
		local label, rest = plain:match("^%s*([^:]+):%s*(.-)%s*$")
		if label then
			local key = Trim(label):lower()
			local entry = { label = key, display = Trim(label), value = ns.Collect_Clean(rest), raw = rest }
			result.lines[#result.lines + 1] = entry
			if ZONE_LABELS[key] then
				for _, c in ipairs(ns.Collect_Candidates(entry.value)) do
					AddUnique(result.zones, seen, c)
					for _, alias in ipairs(ALIASES[c] or {}) do
						AddUnique(result.zones, seen, alias)
					end
				end
				local q = Qualifier(entry.value)
				if key ~= "pet battle" and q and DIFFICULTIES[q:lower()] then
					qualifier = qualifier or q
				end
			end
		end
	end
	local byLabel = {}
	for _, entry in ipairs(result.lines) do
		byLabel[entry.label] = byLabel[entry.label] or entry
	end
	local drop = byLabel.drop and DropQualifier(byLabel.drop.value)
	if drop and drop ~= "" and drop:lower() ~= "world drop" then
		result.drop = drop
	end
	local first
	for _, label in ipairs(LINE_LABELS) do
		if byLabel[label] then
			first = byLabel[label]
			break
		end
	end
	if not first then
		for _, entry in ipairs(result.lines) do
			if not ZONE_LABELS[entry.label] and entry.label ~= "cost" then
				first = entry
				break
			end
		end
	end
	if first then
		local line = first.label == "pet battle" and "Wild pet battle" or (first.display .. ": " .. first.value)
		if qualifier then
			line = line .. " (" .. qualifier .. ")"
		end
		if byLabel.cost then
			line = line .. " · " .. Trim(byLabel.cost.raw)
		end
		result.line = line
	end
	return result
end

-- zones: candidates from ParseSource; nameSet: [lower-case map name] = display name. The first match's name or nil.
function ns.Collect_MatchZones(zones, nameSet)
	for _, c in ipairs(zones) do
		local name = nameSet[c]
		if name then
			return name
		end
	end
	return nil
end

local function IsWordChar(c)
	return c ~= "" and c:find("^%w") ~= nil
end

-- lower: lower-case text; names: lower-case names. A name (4+ characters) appears in it as whole words.
function ns.Collect_LowerMentions(lower, names)
	if not lower then
		return false
	end
	for _, n in ipairs(names) do
		if #n >= 4 then
			local start = 1
			while true do
				local s, e = lower:find(n, start, true)
				if not s then
					break
				end
				if not IsWordChar(lower:sub(s - 1, s - 1)) and not IsWordChar(lower:sub(e + 1, e + 1)) then
					return true
				end
				start = s + 1
			end
		end
	end
	return false
end

-- A name (4+ characters) appears as whole words in the text, ignoring case.
function ns.Collect_TextMentions(text, names)
	if not text then
		return false
	end
	local lowerNames = {}
	for i, name in ipairs(names) do
		lowerNames[i] = name:lower()
	end
	return ns.Collect_LowerMentions(text:lower(), lowerNames)
end

ns.COLLECT_SECTIONS = {
	{ key = "mounts", kind = "mount", title = "Mounts" },
	{ key = "pets", kind = "pet", title = "Pets" },
	{ key = "achievements", kind = "ach", title = "Achievements" },
}

local function ByUpNowThenName(a, b)
	local au, bu = a.upNow ~= nil, b.upNow ~= nil
	if au ~= bu then
		return au
	end
	return a.name < b.name
end

local function ByPercentThenName(a, b)
	local ap, bp = a.percent or 0, b.percent or 0
	if ap ~= bp then
		return ap > bp
	end
	return a.name < b.name
end

-- entries: { kind = "mount" | "pet" | "ach", name, upNow, percent }. opts = { show = { [key] = bool },
-- collapsed = { [key] = bool } }. Returns the non-empty shown sections: { { key, kind, title, entries, collapsed } }.
function ns.Collect_Sections(entries, opts)
	local out = {}
	for _, s in ipairs(ns.COLLECT_SECTIONS) do
		if opts.show[s.key] ~= false then
			local list = {}
			for _, e in ipairs(entries) do
				if e.kind == s.kind then
					list[#list + 1] = e
				end
			end
			if #list > 0 then
				table.sort(list, s.kind == "ach" and ByPercentThenName or ByUpNowThenName)
				out[#out + 1] = { key = s.key, kind = s.kind, title = s.title, entries = list,
					collapsed = opts.collapsed[s.key] == true }
			end
		end
	end
	return out
end

function ns.Collect_Counts(entries)
	local counts = { mounts = 0, pets = 0, achievements = 0 }
	for _, e in ipairs(entries) do
		for _, s in ipairs(ns.COLLECT_SECTIONS) do
			if e.kind == s.kind then
				counts[s.key] = counts[s.key] + 1
			end
		end
	end
	return counts
end

local NOUNS = { mounts = { "mount", "mounts" }, pets = { "pet", "pets" }, achievements = { "achievement", "achievements" } }

-- "2 mounts, 1 pet, 18 achievements left", or nil when nothing is left.
function ns.Collect_ZoneToastText(counts)
	local parts = {}
	for _, s in ipairs(ns.COLLECT_SECTIONS) do
		local n = counts[s.key] or 0
		if n > 0 then
			parts[#parts + 1] = ("%d %s"):format(n, NOUNS[s.key][n == 1 and 1 or 2])
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ", ") .. " left"
end
