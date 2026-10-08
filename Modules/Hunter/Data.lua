local addonName, ns = ...

-- Hunter Pets: pure logic (no WoW API calls; unit-tested with plain Lua). Stable snapshots, the tame log,
-- and the readiness rules.

local SPEC_BM, SPEC_MM, SPEC_SV = 253, 254, 255
local DELVE_DIFFICULTY = 208

-- Creature families that aren't hunter pets (warlock demons, DK ghouls, mage elementals).
local NOT_HUNTER_FAMILIES = {
	Imp = true, ["Fel Imp"] = true, Voidwalker = true, Voidlord = true, Succubus = true, Incubus = true,
	Shivarra = true, Felhunter = true, Observer = true, Felguard = true, Wrathguard = true, Infernal = true,
	Abyssal = true, Doomguard = true, Terrorguard = true, Ghoul = true, Abomination = true,
	["Water Elemental"] = true,
}

-- "Creature-0-3767-0-11-12345-0000ABCDEF" -> 12345 (creatures and vehicles only)
function ns.Hunter_NpcID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	return tonumber(id)
end

function ns.Hunter_IsPetFamily(name)
	return type(name) == "string" and name ~= "" and not NOT_HUNTER_FAMILIES[name]
end

-- The fields of a C_StableInfo PetInfo we keep in the saved cache.
function ns.Hunter_SlimPet(info)
	return {
		name = info.name,
		family = info.familyName,
		spec = info.specialization,
		specAbility = info.specAbilities and info.specAbilities[1] or nil,
		icon = info.icon,
		displayID = info.displayID,
		uiModelSceneID = info.uiModelSceneID, -- camera and framing Blizzard uses for this pet
		creatureID = info.creatureID,
		exotic = info.isExotic or nil,
		level = info.level,
		petNumber = info.petNumber,
		slot = info.slotID,
	}
end

local function EachPet(snapshot, fn)
	if not snapshot then
		return
	end
	for _, pet in pairs(snapshot.active or {}) do
		fn(pet)
	end
	for _, pet in ipairs(snapshot.stabled or {}) do
		fn(pet)
	end
end
ns.Hunter_EachPet = EachPet

function ns.Hunter_PetCount(snapshot)
	local n = 0
	EachPet(snapshot, function()
		n = n + 1
	end)
	return n
end

-- Every pet number the character has had: the old snapshot's record plus its pets.
local function KnownNumbers(old)
	local known = {}
	for n in pairs(old.known or {}) do
		known[n] = true
	end
	EachPet(old, function(pet)
		if pet.petNumber then
			known[pet.petNumber] = true
		end
	end)
	return known
end

-- Pets in `new` whose pet number the character never had before. Nothing without an old snapshot.
function ns.Hunter_NewPets(old, new)
	local found = {}
	if not old or not new then
		return found
	end
	local known = KnownNumbers(old)
	EachPet(new, function(pet)
		if pet.petNumber and not known[pet.petNumber] then
			found[#found + 1] = pet
		end
	end)
	return found
end

-- A new read may lack the stabled list (if the API only answers it at a stable master): keep the cached
-- one. New pets are only looked for in lists that were read both times; a burst of them is the cache
-- catching up, not tames. Every pet number ever seen is kept (new.known), so a pet missing from one
-- partial read isn't "new" when it shows up again. settling = right after a loading screen, when reads
-- can be incomplete: record, never report. Returns the tamed pets; `new` is updated in place.
local MAX_TAMES = 2
function ns.Hunter_MergeSnapshot(old, new, settling)
	local stabledRead = #new.stabled > 0
	if not stabledRead and old and old.stabled and #old.stabled > 0 then
		new.stabled = old.stabled
	end
	new.stabledRead = stabledRead or nil
	local found = {}
	if old and not settling then
		local compare = { active = new.active, stabled = {} }
		if stabledRead and old.stabledRead then
			compare.stabled = new.stabled
		end
		found = ns.Hunter_NewPets(old, compare)
		if #found > MAX_TAMES then
			found = {}
		end
	end
	local known = old and KnownNumbers(old) or {}
	EachPet(new, function(pet)
		if pet.petNumber then
			known[pet.petNumber] = true
		end
	end)
	new.known = known
	return found
end

-- For the tame-log tooltip line: how many pets of this family, and whether this exact creature is owned.
function ns.Hunter_Ownership(snapshot, family, npcID)
	local count, same = 0, nil
	EachPet(snapshot, function(pet)
		if pet.family == family then
			count = count + 1
		end
		if npcID and pet.creatureID == npcID then
			same = same or pet
		end
	end)
	return count, same
end

-- Remember a creature seen in the world (account-wide). Returns true when it wasn't known yet.
function ns.Hunter_RecordSeen(seen, family, npcID, creatureName, zone, now)
	local entry = seen[family]
	if not entry then
		entry = { creatures = {} }
		seen[family] = entry
	end
	local key = npcID or creatureName
	if entry.creatures[key] then
		return false
	end
	entry.creatures[key] = { name = creatureName, zone = zone, at = now }
	return true
end

local function ByName(a, b)
	return a.name < b.name
end

-- Stable page data: owned families (with their pets) and families only seen in the world.
function ns.Hunter_StableSummary(snapshot, seen)
	local families = {}
	local owned = {}
	EachPet(snapshot, function(pet)
		local family = pet.family or "?"
		local entry = families[family]
		if not entry then
			entry = { name = family, pets = {}, exotic = pet.exotic }
			families[family] = entry
			owned[#owned + 1] = entry
		end
		entry.pets[#entry.pets + 1] = pet
	end)
	for _, entry in ipairs(owned) do
		table.sort(entry.pets, ByName)
	end
	table.sort(owned, ByName)
	local seenOnly = {}
	for family, entry in pairs(seen or {}) do
		if not families[family] then
			local creatures = {}
			-- Copies (the saved entries stay as they are); the key is the npcID, or the name for old entries.
			for key, c in pairs(entry.creatures) do
				creatures[#creatures + 1] = {
					name = c.name, zone = c.zone, at = c.at, family = family,
					npcID = type(key) == "number" and key or nil,
				}
			end
			table.sort(creatures, ByName)
			seenOnly[#seenOnly + 1] = { name = family, creatures = creatures }
		end
	end
	table.sort(seenOnly, ByName)
	return { owned = owned, seenOnly = seenOnly, pets = ns.Hunter_PetCount(snapshot) }
end

-- instanceType/difficultyID from GetInstanceInfo() -> "dungeon" | "raid" | "delve" | nil
function ns.Hunter_ContentKind(instanceType, difficultyID)
	if instanceType == "party" then
		return "dungeon"
	elseif instanceType == "raid" then
		return "raid"
	elseif instanceType == "scenario" and difficultyID == DELVE_DIFFICULTY then
		return "delve"
	end
	return nil
end

ns.HUNTER_CONTENT_LABEL = { dungeon = "dungeon", raid = "raid", delve = "delve" }
-- Pet specialization IDs to the names the settings store, so the check works on any client language.
ns.HUNTER_PET_SPEC = { [74] = "Ferocity", [79] = "Cunning", [81] = "Tenacity" }

-- The readiness warnings for a situation. s = {
--   specID, hasPet, petDead, petSpec ("Ferocity"...), content ("dungeon"...), passive, growl (nil = no Growl
--   on the bar, else autocast on/off), inGroup (other players), groupHasTank (companions count) }
-- rules = the module's check settings.
function ns.Hunter_Problems(s, rules)
	local problems = {}
	local wantsPet = s.specID == SPEC_BM or s.specID == SPEC_SV or (s.specID == SPEC_MM and rules.marksman)
	if not s.hasPet then
		if wantsPet and rules.noPet then
			problems[#problems + 1] = s.petDead and "Your pet is dead" or "No pet out"
		end
		return problems
	end
	if s.petDead then
		if wantsPet and rules.noPet then
			problems[#problems + 1] = "Your pet is dead"
		end
		return problems
	end
	local want = s.content and rules.specs[s.content]
	if want and want ~= "any" and s.petSpec and s.petSpec:lower() ~= want:lower() then
		problems[#problems + 1] = ("%s pet in a %s (you wanted %s)"):format(s.petSpec, ns.HUNTER_CONTENT_LABEL[s.content], want)
	end
	if rules.passive and s.passive then
		problems[#problems + 1] = "Pet is on Passive"
	end
	if rules.growl and s.growl ~= nil then
		if s.growl and s.inGroup and s.groupHasTank and s.content ~= "delve" then
			problems[#problems + 1] = "Growl is on, and the group has a tank"
		elseif not s.growl and not s.inGroup and s.content == "delve" then
			problems[#problems + 1] = "Growl is off (solo delve)"
		end
	end
	return problems
end
