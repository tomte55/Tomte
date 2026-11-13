local addonName, ns = ...

-- Send to alt, "To disenchant": at the mailbox, the gear in your bags whose materials are worth more than selling it
-- (Gold & value's disenchant marker, with TSM's prices) goes to your enchanter, the character with the most
-- Enchanting skill that mail reaches. Only gear that isn't bound: a bound item can't be mailed. Nothing when you're
-- an enchanter yourself. Drawn and attached by Send.lua; the enchanter is picked in SendData.lua.

local ENCHANTING = 333 -- Enchanting's skill line (GetProfessionInfo's skillLine)
local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass

-- { group } or {}: the group as Alts_GearGroups makes them (guid, stacks, count) with disenchant = true; each stack
-- carries destroy (what its materials are worth, copper, or nil). skip: [bag .. ":" .. slot] = true for stacks another
-- group already takes.
function ns.AltsSend_DisenchantGroups(skip)
	local alts = ns.altsDB
	local me = UnitGUID("player")
	local mine = alts.chars[me]
	if not (alts.sendDisenchant and ns.Value_BagMarker) or (mine and mine.profs and mine.profs[ENCHANTING]) then
		return {}
	end
	local to = ns.Alts_Enchanter(alts.chars, me, ns.Alts_MailRealms(), ENCHANTING)
	if not to then
		return {}
	end
	local g = { guid = to, stacks = {}, count = 0, disenchant = true }
	for _, s in ipairs(ns.AltsSend_BagStacks()) do
		if not s.bound and (s.classID == WEAPON or s.classID == ARMOR) and not skip[s.bag .. ":" .. s.slot] then
			local marker = ns.Value_BagMarker(s.bag, s.slot)
			if marker and marker.kind == "disenchant" then
				s.destroy = marker.facts and marker.facts.destroy
				g.stacks[#g.stacks + 1] = s
				g.count = g.count + (s.count or 1)
			end
		end
	end
	return #g.stacks > 0 and { g } or {}
end
