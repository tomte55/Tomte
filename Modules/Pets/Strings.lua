local addonName, ns = ...

-- Pet Battles: team strings in the Rematch format, as Xu-Fu's Pet Guides exports them (its "Rematch string"
-- button), and as Rematch, PetMatch and Long Live Pets share teams. The format is an interop format; no code is
-- taken from those addons. Pure (tests/test_pets.lua).
--
--   Name:npcIDs:tag1:tag2:tag3[:P:minHP:allowMM:expectedDD:maxHP:minLevel:maxXP][:N:notes]
--
-- NPC ids are base 32 (0-9 then A-V), comma separated. A pet tag is three ability digits (0 any, 1 or 2), one breed
-- character (0 any, 3-C) and the species id in base 32, or ZL (leveling pet), ZR<type> (random pet of a family,
-- 0 any), ZI / ZU (leave the slot). Notes are everything after the first ":N:", with literal "\n" for new lines; a
-- Pet Battle Script block in the notes is split off as the team's script.

local SCRIPT_BEGIN, SCRIPT_END = "-----BEGIN PET BATTLE SCRIPT-----", "-----END PET BATTLE SCRIPT-----"

ns.PETS_BREEDS = { [3] = "B/B", [4] = "P/P", [5] = "S/S", [6] = "H/H", [7] = "H/P", [8] = "P/S", [9] = "H/S",
	[10] = "P/B", [11] = "S/B", [12] = "H/B" }

local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUV"

function ns.Pets_Base32(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local n = 0
	for i = 1, #s do
		local d = DIGITS:find(s:sub(i, i):upper(), 1, true)
		if not d then
			return nil
		end
		n = n * 32 + d - 1
	end
	return n
end

function ns.Pets_ParseTag(tag)
	if type(tag) ~= "string" then
		return nil
	end
	tag = tag:upper()
	if tag == "ZL" then
		return { kind = "leveling" }
	elseif tag == "ZI" or tag == "ZU" then
		return { kind = "ignore" }
	end
	local family = tag:match("^ZR(%w*)$")
	if family then
		local t = family == "" and 0 or ns.Pets_Base32(family)
		return t and t <= 10 and { kind = "random", type = t } or nil
	end
	local a1, a2, a3, breed, species = tag:match("^([012])([012])([012])(%w)(%w+)$")
	if not a1 then
		return nil
	end
	local b = ns.Pets_Base32(breed)
	species = ns.Pets_Base32(species)
	if not (b and species) or (b ~= 0 and not ns.PETS_BREEDS[b]) then
		return nil
	end
	return { kind = "species", species = species, abilities = { tonumber(a1), tonumber(a2), tonumber(a3) }, breed = b }
end

local function Split(s, sep)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep) do
		out[#out + 1] = part
	end
	return out
end

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Notes and script from the text after ":N:". The script runs to the last END marker, as Pet Battle Scripts reads it.
local function SplitNotes(raw)
	local text = raw:gsub("\\n", "\n")
	local first = text:find(SCRIPT_BEGIN, 1, true)
	local script
	if first then
		local last
		local from = first
		while true do
			local s = text:find(SCRIPT_END, from, true)
			if not s then
				break
			end
			last, from = s, s + 1
		end
		local body = text:sub(first + #SCRIPT_BEGIN, last and last - 1 or #text)
		script = Trim(ns.Pets_Unescape(body))
		text = text:sub(1, first - 1) .. (last and text:sub(last + #SCRIPT_END) or "")
		if script == "" then
			script = nil
		end
	end
	return Trim(text), script
end

-- "6Q6M,1" -> { 223446, 1 }; nil when a part isn't base 32.
local function ParseNPCs(text)
	local npcs = {}
	for _, id in ipairs(Split(text, ",")) do
		id = Trim(id)
		local npc = ns.Pets_Base32(id)
		if npc and npc > 0 then
			npcs[#npcs + 1] = npc
		elseif id ~= "" then
			return nil
		end
	end
	return npcs
end

-- One team string -> team, or nil and why.
function ns.Pets_ParseTeam(line)
	if type(line) ~= "string" then
		return nil, "not text"
	end
	line = Trim(line)
	local head, notes = line, nil
	local n = line:find(":N:", 1, true)
	if n then
		head, notes = line:sub(1, n - 1), line:sub(n + 3)
	elseif line:sub(-2) == ":N" then
		head, notes = line:sub(1, -3), ""
	end
	local fields = Split(head, ":")
	-- Names aren't escaped and can hold colons ("Fight Night: Heliosus"): the name is everything before the first
	-- spot where an NPC list and three pet tags follow.
	local k, npcs, tags
	for at = 2, #fields - 3 do
		npcs, tags = ParseNPCs(fields[at]), {}
		for slot = 1, 3 do
			tags[slot] = ns.Pets_ParseTag(Trim(fields[at + slot]))
		end
		if npcs and tags[1] and tags[2] and tags[3] then
			k = at
			break
		end
	end
	if not k then
		return nil, "not a team string"
	end
	local team = { name = Trim(table.concat(fields, ":", 1, k - 1)), npcs = npcs, pets = tags }
	if team.name == "" then
		return nil, "no name"
	end
	local rest = k + 4
	if fields[rest] == "P" then
		team.prefs = { minHP = tonumber(fields[rest + 1] or ""), maxHP = tonumber(fields[rest + 4] or ""),
			minLevel = tonumber(fields[rest + 5] or "") }
	elseif fields[rest] and Trim(fields[rest]) ~= "" then
		return nil, "unknown part " .. fields[rest]
	end
	team.notes, team.script = SplitNotes(notes or "")
	return team
end

-- A pasted block: one team per line. Group headers (__ Name ... __) and blank lines are skipped silently; any
-- other line that isn't a team counts as skipped. Returns teams, skipped.
function ns.Pets_ParseImport(text)
	local teams, skipped = {}, 0
	for line in (text or ""):gmatch("[^\r\n]+") do
		line = Trim(line)
		if line ~= "" and not line:match("^__.*__$") then
			local team = ns.Pets_ParseTeam(line)
			if team then
				teams[#teams + 1] = team
			else
				skipped = skipped + 1
			end
		end
	end
	return teams, skipped
end
