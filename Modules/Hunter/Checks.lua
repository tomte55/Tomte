local addonName, ns = ...

-- Hunter Pets readiness check: after entering a dungeon, raid or delve, on a ready check, or on demand.
-- Looks at the pet (out, alive, spec for this content, Passive, Growl autocast) and shows what's off as a
-- banner plus a chat line. Also a toast when Growl is left off with your pet out, alone in the open world. The rules
-- live in Data.lua. Out of combat only.

local ENTER_DELAY = 4 -- seconds after zoning in: the pet is summoned again by then
local GROWL = 2649 -- the pet's Growl
local GROWL_DELAY = 3 -- seconds after zoning, a group change or a pet call before Growl's autocast is read
local WARNING = "warning" -- theme role for the banner accent (the chat lines use it too)
local ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local function PetSpecName()
	if ns.FOREVER then -- pets have no specs there
		return nil
	end
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
	-- Forever has ranks: only rank 1 is GROWL's ID, so its pet bar is matched by the spell's name.
	local growlName = ns.FOREVER and C_Spell.GetSpellName(GROWL)
	for i = 1, NUM_PET_ACTION_SLOTS or 10 do
		local name, _, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(i)
		if isToken and name == "PET_MODE_PASSIVE" and isActive then
			passive = true
		end
		if (spellID == GROWL or (growlName and name == growlName)) and autoCastAllowed then
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
		content = ns.Check_ContentKind(instanceType, difficultyID),
		wantsAnySpec = ns.FOREVER and ns.PetBar_HasPet(),
	}
	local players, tank = Group()
	s.inGroup, s.groupHasTank = players > 0, tank
	if s.hasPet then
		s.petDead = UnitIsDead("pet")
		s.petSpec = PetSpecName()
		s.passive, s.growl = PetBar()
		if ns.FOREVER then
			local happiness = C_PetInfo.GetPetHappiness()
			s.happiness = not ns.IsSecret(happiness) and happiness or nil
		end
	end
	return s
end

-- verbose: also say so when everything is fine (the slash command and the options button).
local function FindProblems()
	return ns.Hunter_Problems(Situation(), ns.hunterDB.check), ICON
end

function ns.Checks_Run(verbose)
	ns.Check_Report({
		active = ns.hunterModule.active,
		verbose = verbose,
		name = "pet check",
		find = FindProblems,
		banner = ns.hunterDB.check.banner,
		bannerOnVerbose = true,
		owner = "hunter",
		label = "Pet check",
		accent = WARNING,
	})
end

function ns.Checks_OnEnterWorld()
	if not ns.hunterDB.check.onEnter then
		return
	end
	ns.Check_OnEnterWorld(ENTER_DELAY, function()
		ns.Checks_Run(false)
	end)
end

-- Growl left off ------------------------------------------------------------------------------------------------------

local growlTold = false -- told since Growl was last seen on
local growlPending = false

-- A toast when Growl is off with your pet out, alone in the open world: once, until it's been on again.
local function CheckGrowl()
	growlPending = false
	if not (ns.hunterModule.active and ns.hunterDB.check.growlSolo) or InCombatLockdown() then
		return
	end
	local s = Situation()
	if s.growl then
		growlTold = false
	end
	if growlTold or not ns.Hunter_GrowlForgotten(s) then
		return
	end
	growlTold = true
	ns.Toast_Show({
		owner = "hunter",
		label = "Pet",
		title = "Growl is off",
		text = "Your pet won't pull enemies off you. Right-click Growl on the pet bar to turn it back on.",
		icon = C_Spell.GetSpellTexture(GROWL) or ICON,
	})
end

-- After zoning, a group change or a pet call: the pet bar has caught up by then.
function ns.Checks_GrowlSoon()
	if growlPending then
		return
	end
	growlPending = true
	C_Timer.After(GROWL_DELAY, CheckGrowl)
end

function ns.Checks_OnReadyCheck()
	if ns.hunterDB.check.onReadyCheck then
		ns.Checks_Run(false)
	end
end
