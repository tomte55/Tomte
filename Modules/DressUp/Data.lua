local addonName, ns = ...

-- Dressing room pure logic (unit-tested in tests/test_dressup.lua): the slot bar's groups, the window's scale, the
-- item list's lines.

-- The slot bar, left to right: armor, then hands to feet, weapons, then shirt and tabard. false: a group gap.
ns.DRESSUP_SLOTS = { 1, 3, 15, 5, 9, false, 10, 6, 7, 8, false, 16, 17, false, 4, 19 }
-- GetInventorySlotInfo names (empty-slot art, the slot's name).
ns.DRESSUP_SLOT_NAMES = {
	[1] = "HEADSLOT", [3] = "SHOULDERSLOT", [4] = "SHIRTSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT", [7] = "LEGSSLOT",
	[8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [15] = "BACKSLOT", [16] = "MAINHANDSLOT",
	[17] = "SECONDARYHANDSLOT", [19] = "TABARDSLOT",
}

local MIN_SCALE, MAX_SCALE = 0.6, 3

-- The scale that makes a frame `frameH` tall take `share` of a screen `screenH` tall (both in the same units).
function ns.DressUp_FitScale(share, frameH, screenH)
	if not (frameH and frameH > 0 and screenH and screenH > 0) then
		return 1
	end
	local scale = (share or 0.8) * screenH / frameH
	return math.max(MIN_SCALE, math.min(scale, MAX_SCALE))
end

-- Where an appearance comes from, as the item list says it. drop: { encounter, instance, difficulty } for a boss
-- drop; sourceType: Blizzard's TRANSMOG_SOURCE_n index; names: [n] = that string (the client's language).
function ns.DressUp_SourceText(sourceType, drop, names)
	if drop and drop.encounter and drop.instance then
		local text = ("%s, %s"):format(drop.encounter, drop.instance)
		if drop.difficulty and drop.difficulty ~= "" then
			text = ("%s (%s)"):format(text, drop.difficulty)
		end
		return text
	end
	return sourceType and names[sourceType] or nil
end

-- "Head: Swarmcall Helm - Gate of the Setting Sun". Without a name: nil (the slot is left out).
function ns.DressUp_ListLine(slotName, itemName, source)
	if not itemName or itemName == "" then
		return nil
	end
	local line = ("%s: %s"):format(slotName, itemName)
	if source and source ~= "" then
		line = line .. " - " .. source
	end
	return line
end
