local addonName, ns = ...

-- Hunter Pets: reads the stable (C_StableInfo) and keeps the last good read per character in the saved
-- cache, so the tooltips and the stable page work wherever the API answers (or doesn't). A pet number
-- that wasn't in the previous read is a fresh tame (there's no tame event) and becomes a Moment.

-- Call Pet 1-5, then the BM bonus slot. Forever's stable has one pet you call and two stabled (PetConsts_Camelot).
local ACTIVE_SLOTS = ns.FOREVER and 1 or 6
local FOREVER_LAST_SLOT = 3 -- Constants.PetConsts.NUM_PET_SLOTS_HUNTER there: 1 is the current pet, 2-3 the stable
local READ_DELAY = 0.5 -- coalesces bursts of stable events
local SETTLE = 10 -- seconds after a loading screen when reads may be incomplete (no tame moments)
local TAME_BEAST = 1515
local TAME_WINDOW = 90 -- seconds a Tame Beast cast counts for the next new pet

local pending
local settleUntil = 0
local lastTame -- { rare = target was a rare spawn, at = GetTime() } from the last Tame Beast cast

local Secret = ns.IsSecret

-- Tame Beast started: remember whether the beast is a rare spawn (the stable only says exotic).
function ns.Stable_OnSpellcast(spellID)
	if Secret(spellID) or spellID ~= TAME_BEAST then
		return
	end
	local classification = UnitClassification("target")
	if Secret(classification) then
		return
	end
	lastTame = { rare = ns.Moments_IsRareClassification(classification), at = GetTime() }
end

local function CharKey()
	return UnitGUID("player")
end

function ns.Stable_Snapshot()
	local chars = ns.hunterDB.chars
	return chars[CharKey()]
end

-- Forever's pets have loyalty and happiness instead of a spec (its field is there but doesn't apply).
local function Slim(info)
	local pet = ns.Hunter_SlimPet(info)
	if ns.FOREVER then
		pet.spec, pet.specAbility = nil, nil
		pet.loyalty, pet.happiness = info.loyaltyName, info.happinessLevel
	end
	return pet
end

-- Forever: Blizzard's stable reads each slot by index and never asks for GetStabledPetList, so neither do we.
local function StabledInfos()
	if not ns.FOREVER then
		return C_StableInfo.GetStabledPetList() or {}
	end
	local infos = {}
	for slot = ACTIVE_SLOTS + 1, FOREVER_LAST_SLOT do
		infos[#infos + 1] = C_StableInfo.GetStablePetInfo(slot)
	end
	return infos
end

local function Read()
	local active, count = {}, 0
	for slot = 1, ACTIVE_SLOTS do
		local info = C_StableInfo.GetStablePetInfo(slot)
		if info and info.name then
			active[slot] = Slim(info)
			active[slot].slot = slot
			count = count + 1
		end
	end
	local stabled = {}
	for _, info in ipairs(StabledInfos()) do
		if info.name then
			local pet = Slim(info)
			if ns.FOREVER then
				pet.slot = nil -- the page would call slot 2 "Call Pet 2"
			end
			stabled[#stabled + 1] = pet
			count = count + 1
		end
	end
	if count == 0 then
		return nil -- not readable here (or no pets at all): keep the cache
	end
	return { active = active, stabled = stabled, at = time() }
end

local function Update()
	pending = false
	if not ns.hunterModule.active then
		return
	end
	local snapshot = Read()
	if not snapshot then
		return
	end
	local old = ns.Stable_Snapshot()
	local tames = ns.Hunter_MergeSnapshot(old, snapshot, GetTime() < settleUntil)
	ns.hunterDB.chars[CharKey()] = snapshot
	local rareSpawn = lastTame and lastTame.rare and GetTime() - lastTame.at < TAME_WINDOW
	if #tames > 0 then
		lastTame = nil
	end
	for _, pet in ipairs(tames) do
		local family = pet.family and (pet.exotic and ("Exotic " .. pet.family) or pet.family) or nil
		ns.Session_Note("tame", { title = pet.name, icon = pet.icon, detail = family })
		if ns.Moments_Trigger then
			ns.Moments_Trigger("tame", {
				title = pet.name,
				subtitle = family,
				icon = pet.icon,
				displayID = pet.displayID,
				exotic = pet.exotic,
				rareSpawn = rareSpawn,
			})
		end
	end
	if ns.StablePage_Refresh then
		ns.StablePage_Refresh()
	end
end

function ns.Stable_OnEnterWorld()
	settleUntil = GetTime() + SETTLE
	ns.Stable_Refresh()
end

function ns.Stable_Refresh()
	if pending then
		return
	end
	pending = true
	C_Timer.After(READ_DELAY, Update)
end

-- The cached pet behind Call Pet <index> (1-5), or nil.
function ns.Stable_CallPet(index)
	local snapshot = ns.Stable_Snapshot()
	return snapshot and snapshot.active and snapshot.active[index]
end

-- Which Call Pet slot is summoned right now (Blizzard's StableUI asks the same way).
function ns.Stable_SummonedSlot()
	if ns.FOREVER then -- one Call Pet, and Blizzard's camelot stable never asks IsCurrentSpell
		return UnitExists("pet") and 1 or nil
	end
	for i, spellID in ipairs(ns.CALL_PET_SPELLS) do
		if C_Spell.IsCurrentSpell(spellID) then
			return i
		end
	end
	return nil
end
