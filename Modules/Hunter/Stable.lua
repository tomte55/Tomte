local addonName, ns = ...

-- Hunter Pets: reads the stable (C_StableInfo) and keeps the last good read per character in the saved
-- cache, so the tooltips and the stable page work wherever the API answers (or doesn't). A pet number
-- that wasn't in the previous read is a fresh tame (there's no tame event) and becomes a Moment.

local ACTIVE_SLOTS = 6 -- Call Pet 1-5, then the BM bonus slot
local READ_DELAY = 0.5 -- coalesces bursts of stable events
local SETTLE = 10 -- seconds after a loading screen when reads may be incomplete (no tame moments)

local pending
local settleUntil = 0

local function CharKey()
	return UnitGUID("player")
end

function ns.Stable_Snapshot()
	local chars = ns.hunterDB.chars
	return chars[CharKey()]
end

local function Read()
	local active, count = {}, 0
	for slot = 1, ACTIVE_SLOTS do
		local info = C_StableInfo.GetStablePetInfo(slot)
		if info and info.name then
			active[slot] = ns.Hunter_SlimPet(info)
			active[slot].slot = slot
			count = count + 1
		end
	end
	local stabled = {}
	for _, info in ipairs(C_StableInfo.GetStabledPetList() or {}) do
		if info.name then
			stabled[#stabled + 1] = ns.Hunter_SlimPet(info)
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
	for _, pet in ipairs(tames) do
		if ns.Moments_Trigger then
			ns.Moments_Trigger("tame", {
				title = pet.name,
				subtitle = pet.family and (pet.exotic and ("Exotic " .. pet.family) or pet.family) or nil,
				icon = pet.icon,
				displayID = pet.displayID,
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
	for i, spellID in ipairs(ns.CALL_PET_SPELLS) do
		if C_Spell.IsCurrentSpell(spellID) then
			return i
		end
	end
	return nil
end

ns.CALL_PET_SPELLS = { 883, 83242, 83243, 83244, 83245 }
