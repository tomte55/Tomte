local addonName, ns = ...

-- Pet Battles: saved teams (imported strategies), which team is used for which tamer, enemy teams Tomte has seen,
-- and lookups into the tamer table (Tamers.lua). The battle helper, the tamer card and the page all go through here.

local db
local encounterIndex
local scripts = {} -- [team id] = { code, script, err }

local XUFU = "https://www.wow-petguide.com/Encounter/%d"
local WOWHEAD = "https://www.wowhead.com/npc=%d"

function ns.PetsStore_Init(moduleDB)
	db = moduleDB
end

function ns.Pets_XufuURL(id)
	return XUFU:format(id)
end

function ns.Pets_WowheadURL(npc)
	return WOWHEAD:format(npc)
end

-- Tamer table ----------------------------------------------------------------------------------------------------

local sectionsByID

local function Sections()
	if not sectionsByID then
		sectionsByID = {}
		for i, s in ipairs(ns.PETS_SECTIONS or {}) do
			sectionsByID[s.id] = s
			s.order = i
		end
	end
	return sectionsByID
end

function ns.PetsStore_Section(id)
	return Sections()[id]
end

-- Xu-Fu encounters for an NPC: { { id, name, section } }, newest expansion's section first.
function ns.PetsStore_Encounters(npc)
	encounterIndex = encounterIndex or ns.Pets_IndexEncounters(ns.PETS_ENCOUNTERS or {})
	local out = {}
	for _, id in ipairs(npc and encounterIndex[npc] or {}) do
		local e = ns.PETS_ENCOUNTERS[id]
		out[#out + 1] = { id = id, name = e.name, section = e.section }
	end
	local sections = Sections()
	table.sort(out, function(a, b)
		local sa, sb = sections[a.section], sections[b.section]
		local oa, ob = sa and sa.order or 999, sb and sb.order or 999
		if oa ~= ob then
			return oa < ob
		end
		return a.id < b.id
	end)
	return out
end

-- Learned enemies --------------------------------------------------------------------------------------------

-- name: the NPC's name as the game showed it (gossip or target), kept for lists.
function ns.PetsStore_Learn(npc, species, name)
	local entry = db.learned[npc] or {}
	if species and #species > 0 then
		entry.species = species
		entry.types = entry.types or {}
	end
	entry.name = name or entry.name
	entry.seen = time()
	db.learned[npc] = entry
end

function ns.PetsStore_SetTypes(npc, types)
	if db.learned[npc] then
		db.learned[npc].types = types
	end
end

function ns.PetsStore_Learned(npc)
	return npc and db.learned[npc]
end

-- The NPC whose learned team has these species (for battles started without talking to the tamer).
function ns.PetsStore_MatchSignature(species)
	local sig = ns.Pets_Signature(species)
	if sig == "" then
		return nil
	end
	for npc, entry in pairs(db.learned) do
		if entry.species and ns.Pets_Signature(entry.species) == sig then
			return npc
		end
	end
	return nil
end

-- A name to show for an NPC: what the game called it, else the tamer table's encounter name.
function ns.PetsStore_NPCName(npc)
	local learned = npc and db.learned[npc]
	if learned and learned.name then
		return learned.name
	end
	local e = ns.PetsStore_Encounters(npc)[1]
	return e and e.name or (npc and ("NPC " .. npc)) or "?"
end

-- Is this an NPC Tomte has something for (table, team or a learned fight)?
function ns.PetsStore_Known(npc)
	if not npc then
		return false
	end
	if #ns.PetsStore_Encounters(npc) > 0 or (db.learned[npc] and db.learned[npc].species) then
		return true
	end
	return #ns.PetsStore_TeamsFor(npc) > 0
end

-- Teams --------------------------------------------------------------------------------------------------------

local function NewID()
	local id
	repeat
		db.nextID = (db.nextID or 0) + 1
		id = "t" .. db.nextID
	until not db.teams[id]
	return id
end

-- Saves a parsed team (Strings.lua). Returns its id.
function ns.PetsStore_Add(team)
	local id = NewID()
	team.id = nil
	team.imported = time()
	db.teams[id] = team
	return id
end

function ns.PetsStore_Get(id)
	local team = id and db.teams[id]
	if team then
		team.id = id
	end
	return team
end

function ns.PetsStore_Delete(id)
	db.teams[id] = nil
	scripts[id] = nil
	for npc, active in pairs(db.active) do
		if active == id then
			db.active[npc] = nil
		end
	end
end

function ns.PetsStore_Rename(id, name)
	if db.teams[id] and name and name ~= "" then
		db.teams[id].name = name
	end
end

function ns.PetsStore_SetScript(id, code)
	local team = db.teams[id]
	if team then
		team.script = (code and code:match("%S")) and code or nil
		scripts[id] = nil
	end
end

-- Every team, sorted by name: list of teams (each with .id).
function ns.PetsStore_Teams()
	local out = {}
	for id, team in pairs(db.teams) do
		team.id = id
		out[#out + 1] = team
	end
	table.sort(out, function(a, b)
		if a.name:lower() ~= b.name:lower() then
			return a.name:lower() < b.name:lower()
		end
		return a.id < b.id
	end)
	return out
end

-- Teams saved for this NPC, oldest import first.
function ns.PetsStore_TeamsFor(npc)
	local out = {}
	for id, team in pairs(db.teams) do
		for _, n in ipairs(team.npcs or {}) do
			if n == npc then
				team.id = id
				out[#out + 1] = team
				break
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.imported or 0) < (b.imported or 0) or ((a.imported or 0) == (b.imported or 0) and a.id < b.id)
	end)
	return out
end

-- The team used against this NPC: the one picked for it, else the first imported.
function ns.PetsStore_TeamFor(npc)
	if not npc then
		return nil
	end
	local chosen = db.active[npc] and ns.PetsStore_Get(db.active[npc])
	if chosen then
		return chosen
	end
	return ns.PetsStore_TeamsFor(npc)[1]
end

function ns.PetsStore_SetActive(npc, id)
	db.active[npc] = id
end

-- The team's script, built (cached until the script text changes). Returns script or nil, err.
function ns.PetsStore_Script(team)
	if not (team and team.script) then
		return nil
	end
	local cached = scripts[team.id]
	if not cached or cached.code ~= team.script then
		local script, err = ns.PetScript_Build(team.script)
		cached = { code = team.script, script = script, err = err }
		scripts[team.id] = cached
	end
	return cached.script, cached.err
end
