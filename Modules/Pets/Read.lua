local addonName, ns = ...

-- Pet Battles: reads the battle. The round counters and played pets as Pet Battle Scripts counts them (in db.cache,
-- so they survive a /reload), the live api the script interpreter calls (Script.lua lists its methods) and ReadSide,
-- the plain tables the matchup rules (Data.lua) and the battle helper (Battle.lua) use.

local ALLY, ENEMY = 1, 2

local db

function ns.PetsRead_Init(moduleDB)
	db = moduleDB
end

-- Round counters and played pets (as Pet Battle Scripts counts them) -------------------------------------------

local function Cache()
	return db.cache
end

local function ResetCache()
	db.cache = { round = 0, rounds = { [ALLY] = 0, [ENEMY] = 0 }, played = {} }
end

-- The live api for the interpreter (Script.lua lists the methods) ------------------------------------------------

local api = {}

function api:NumPets(o)
	return C_PetBattles.GetNumPets(o) or 0
end
function api:Active(o)
	return C_PetBattles.GetActivePet(o)
end
function api:Health(o, i)
	return C_PetBattles.GetHealth(o, i) or 0
end
function api:MaxHealth(o, i)
	return C_PetBattles.GetMaxHealth(o, i) or 1
end
function api:Speed(o, i)
	return C_PetBattles.GetSpeed(o, i) or 0
end
function api:Power(o, i)
	return C_PetBattles.GetPower(o, i) or 0
end
function api:Level(o, i)
	return C_PetBattles.GetLevel(o, i) or 0
end
function api:Type(o, i)
	return C_PetBattles.GetPetType(o, i)
end
function api:Quality(o, i)
	return C_PetBattles.GetBreedQuality(o, i)
end
function api:Species(o, i)
	return C_PetBattles.GetPetSpeciesID(o, i)
end
function api:Name(o, i)
	return (C_PetBattles.GetName(o, i))
end
function api:Ability(o, i, s)
	local id, name, _, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfo(o, i, s)
	return id, name, petType, noHints
end
function api:AbilityState(o, i, s)
	return C_PetBattles.GetAbilityState(o, i, s)
end
local function AuraList(o, i)
	local list = {}
	for k = 1, C_PetBattles.GetNumAuras(o, i) or 0 do
		local id, _, turns = C_PetBattles.GetAuraInfo(o, i, k)
		if id then
			local _, name = C_PetBattles.GetAbilityInfoByID(id)
			list[#list + 1] = { id = id, name = name, turns = turns or 0 }
		end
	end
	return list
end
function api:Auras(o, i)
	return AuraList(o, i)
end
function api:PadAuras(o)
	return AuraList(o, PET_BATTLE_PAD_INDEX)
end
function api:Weather()
	local id, _, turns = C_PetBattles.GetAuraInfo(Enum.BattlePetOwner.Weather, PET_BATTLE_PAD_INDEX, 1)
	if id then
		local _, name = C_PetBattles.GetAbilityInfoByID(id)
		return id, name, turns or 0
	end
end
function api:Modifier(atk, def)
	return C_PetBattles.GetAttackModifier(atk, def) or 1
end
function api:CanSwapOut()
	return C_PetBattles.CanActivePetSwapOut()
end
function api:PetSelect()
	return C_PetBattles.ShouldShowPetSelect()
end
function api:CanSwapIn(i)
	return C_PetBattles.CanPetSwapIn(i)
end
function api:CanSkip()
	return C_PetBattles.IsSkipAvailable()
end
function api:Trap()
	return C_PetBattles.IsTrapAvailable()
end
function api:Round(o)
	local c = Cache()
	if o then
		return c.rounds[o] or 0
	end
	return c.round or 0
end
function api:Played(o, i)
	return Cache().played[o .. ":" .. i] == true
end
function api:Collected(o, i)
	local species = C_PetBattles.GetPetSpeciesID(o, i)
	if not species then
		return 0, 0, false
	end
	local owned, max = C_PetJournal.GetNumCollectedInfo(species)
	local obtainable = select(11, C_PetJournal.GetPetInfoBySpeciesID(species))
	return owned or 0, max or 0, obtainable and true or false
end
local typeNames, qualityNames
function api:TypeOf(name)
	if not typeNames then
		typeNames = {}
		for t = 1, C_PetJournal.GetNumPetTypes() do
			local n = _G["BATTLE_PET_NAME_" .. t]
			if n then
				typeNames[n:lower()] = t
			end
		end
	end
	return typeNames[name]
end
function api:QualityOf(name)
	if not qualityNames then
		qualityNames = {}
		for q = 1, 6 do
			local n = _G["BATTLE_PET_BREED_QUALITY" .. q]
			if n then
				qualityNames[n:lower()] = q
			end
		end
	end
	return qualityNames[name]
end

-- Reading the battle for the advice -------------------------------------------------------------------------

-- side = { active, pets = { { name, icon, type, health, maxHealth, quality, species, dead, abilities } } }
local function ReadSide(o)
	local side = { active = C_PetBattles.GetActivePet(o), pets = {} }
	for i = 1, C_PetBattles.GetNumPets(o) or 0 do
		local health, maxHealth = C_PetBattles.GetHealth(o, i) or 0, C_PetBattles.GetMaxHealth(o, i) or 1
		local p = { name = (C_PetBattles.GetName(o, i)), icon = C_PetBattles.GetIcon(o, i),
			type = C_PetBattles.GetPetType(o, i), health = health, maxHealth = maxHealth, dead = health <= 0,
			quality = C_PetBattles.GetBreedQuality(o, i), species = C_PetBattles.GetPetSpeciesID(o, i), abilities = {} }
		for s = 1, 3 do
			local id, _, _, _, _, _, petType, noHints = C_PetBattles.GetAbilityInfo(o, i, s)
			if id then
				local usable
				if o == ALLY and i == side.active then
					usable = C_PetBattles.GetAbilityState(o, i, s) and true or false
				end
				p.abilities[#p.abilities + 1] = { id = id, type = petType, noHints = noHints, usable = usable }
			end
		end
		side.pets[i] = p
	end
	return side
end

ns.PetsRead_Cache = Cache
ns.PetsRead_ResetCache = ResetCache
ns.PetsRead_Api = api
ns.PetsRead_Side = ReadSide
