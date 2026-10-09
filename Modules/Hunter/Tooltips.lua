local addonName, ns = ...

-- Hunter Pets tooltips:
-- * Call Pet 1-5: which pet it calls (name, family, spec and its spec ability), and whether it's out now.
-- * Creatures with a hunter-pet family: the tame log line (family, how many you own, whether you have this
--   very creature). Each one seen goes into the account-wide tame log.
-- The post-calls can't be removed, so they check whether the module is on. Anything secret is skipped.

local GREY = "|cff9d9d9d"
local GOLD = "|cffffd173"
local GREEN = "|cff7fe07f"

local function Secret(...)
	if not issecretvalue then
		return false
	end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end

local callPetIndex = {}
for i, spellID in ipairs(ns.CALL_PET_SPELLS) do
	callPetIndex[spellID] = i
end

local function OnSpell(tooltip, data)
	if not (ns.hunterModule.active and ns.hunterDB.callPetTooltip) or not data or Secret(data.id) then
		return
	end
	local index = callPetIndex[data.id]
	if not index then
		return
	end
	local pet = ns.Stable_CallPet(index)
	local name = pet and pet.name
	if not name and GetCallPetSpellInfo then
		local _, petName = GetCallPetSpellInfo(data.id)
		if not Secret(petName) and petName ~= "" then
			name = petName
		end
	end
	if not name then
		return
	end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine(GOLD .. name .. "|r", pet and pet.family and (GREY .. pet.family .. "|r") or "")
	if pet and pet.spec then
		local ability = pet.specAbility and C_Spell.GetSpellName(pet.specAbility)
		tooltip:AddLine(GREY .. pet.spec .. (ability and ("  -  " .. ability) or "") .. "|r")
	end
	if ns.Stable_SummonedSlot() == index then
		tooltip:AddLine(GREEN .. "Summoned|r")
	end
	tooltip:Show()
end

local function OnUnit(tooltip, data)
	if tooltip ~= GameTooltip or not (ns.hunterModule.active and ns.hunterDB.tameTooltip) then
		return
	end
	local _, unit = tooltip:GetUnit()
	if not unit or Secret(unit) then
		return
	end
	local controlled = UnitPlayerControlled(unit)
	if Secret(controlled) or controlled then
		return
	end
	local family, familyID = UnitCreatureFamily(unit)
	if Secret(family, familyID) or not ns.Hunter_IsPetFamily(family, familyID) then
		return
	end
	local guid, name = UnitGUID(unit), UnitName(unit)
	if Secret(guid, name) then
		return
	end
	local npcID = ns.Hunter_NpcID(guid)
	if name then
		ns.Hunter_RecordSeen(ns.hunterDB.seen, family, npcID, name, GetZoneText(), time())
	end
	local count, same = ns.Hunter_Ownership(ns.Stable_Snapshot(), family, npcID)
	local right
	if same then
		right = GOLD .. "you have this one (" .. same.name .. ")|r"
	elseif count > 0 then
		right = GREY .. count .. " in your stable|r"
	else
		right = GREEN .. "new family|r"
	end
	tooltip:AddDoubleLine(GOLD .. family .. "|r", right)
	tooltip:Show()
end

function ns.HunterTooltips_Hook()
	if ns.hunterTooltipsHooked then
		return
	end
	ns.hunterTooltipsHooked = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnSpell)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
end
