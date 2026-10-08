local addonName, ns = ...

-- Hunter Pets readiness check: after entering a dungeon, raid or delve, on a ready check, or on demand.
-- Looks at the pet (out, alive, spec for this content, Passive, Growl autocast) and shows what's off as a
-- banner plus a chat line. The rules live in Data.lua. Out of combat only.

local ENTER_DELAY = 4 -- seconds after zoning in: the pet is summoned again by then
local GROWL = 2649
local ORANGE = { 1, 0.6, 0.25 }
-- The globals only exist with the deprecation fallbacks loaded.
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local function PetSpecName()
	local index = GetSpecialization(false, true)
	if not index then
		return nil
	end
	local id, name = GetSpecializationInfo(index, false, true)
	return ns.HUNTER_PET_SPEC[id] or name
end

-- Passive mode and Growl autocast, from the pet action bar.
local function PetBar()
	local passive, growl = false, nil
	for i = 1, NUM_PET_ACTION_SLOTS or 10 do
		local name, _, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(i)
		if isToken and name == "PET_MODE_PASSIVE" and isActive then
			passive = true
		end
		if spellID == GROWL and autoCastAllowed then
			growl = autoCastEnabled and true or false
		end
	end
	return passive, growl
end

-- Other players in the group (delve and follower-dungeon companions don't count), and whether anyone else
-- (companions included) is the tank.
local function Group()
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	local players, tank = 0, false
	for i = 1, count do
		local unit = prefix .. i
		if not UnitIsUnit(unit, "player") then
			if UnitIsPlayer(unit) then
				players = players + 1
			end
			if UnitGroupRolesAssigned(unit) == "TANK" then
				tank = true
			end
		end
	end
	return players, tank
end

local function Situation()
	local specIndex = GetSpecialization()
	local specID = specIndex and GetSpecializationInfo(specIndex)
	local _, instanceType, difficultyID = GetInstanceInfo()
	local s = {
		specID = specID,
		hasPet = UnitExists("pet"),
		content = ns.Hunter_ContentKind(instanceType, difficultyID),
	}
	local players, tank = Group()
	s.inGroup, s.groupHasTank = players > 0, tank
	if s.hasPet then
		s.petDead = UnitIsDead("pet")
		s.petSpec = PetSpecName()
		s.passive, s.growl = PetBar()
	end
	return s
end

-- verbose: also say so when everything is fine (the slash command and the options button).
function ns.Checks_Run(verbose)
	if not ns.hunterModule.active then
		return
	end
	if InCombatLockdown() or UnitIsDeadOrGhost("player") then
		if verbose then
			ns.Print("pet check: not in combat or while dead.")
		end
		return
	end
	local problems = ns.Hunter_Problems(Situation(), ns.hunterDB.check)
	if #problems == 0 then
		if verbose then
			ns.Print("pet check: all good.")
		end
		return
	end
	for _, problem in ipairs(problems) do
		ns.Print("|cffff9940" .. problem .. "|r")
	end
	if ns.hunterDB.check.banner then
		ns.Banner_Show({
			owner = "hunter",
			label = "Pet check",
			accent = ORANGE,
			title = problems[1],
			subtitle = #problems > 1 and table.concat(problems, "   -   ", 2) or nil,
			icon = "Interface\\Icons\\Ability_Hunter_BeastCall",
			hold = 5,
		})
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

function ns.Checks_OnEnterWorld()
	if not ns.hunterDB.check.onEnter then
		return
	end
	local _, instanceType, difficultyID = GetInstanceInfo()
	if ns.Hunter_ContentKind(instanceType, difficultyID) then
		C_Timer.After(ENTER_DELAY, function()
			ns.Checks_Run(false)
		end)
	end
end

function ns.Checks_OnReadyCheck()
	if ns.hunterDB.check.onReadyCheck then
		ns.Checks_Run(false)
	end
end
