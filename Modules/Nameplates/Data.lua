local addonName, ns = ...

-- Nameplates: pure logic (no WoW API calls; unit-tested in tests/test_nameplates.lua). Which quest objective a
-- unit's nameplate shows, the short progress text for it, which widget sets get an item count, and how far a
-- cast is. Read.lua turns the game's tooltip data into the plain lines these functions take.

-- The War Within, Hallowfall: the Keyflame spots' nameplate widget sets, each showing how many Radiant Remnants
-- you carry (the item you feed the Keyflames). Game IDs; first gathered by Plumber (see README Credits).
ns.PLATES_RADIANT_REMNANT = 206350
ns.PLATES_KEYFLAME_SETS = {
	837, -- Fungal Field
	838, -- Whirring Field
	839, -- Light's Blooming
	846, -- Stillstone Pond
	847, -- Torchlight Mine
	848, -- Duskrise Acreage
	849, -- Faded Shore
	850, -- Bleak Sand
	989, 990, 991, 992, 993, 1034, 1059, 1081, -- later Keyflame spots
}

-- { [widgetSetID] = { item = itemID } } for a list of widget set IDs that all count one item.
function ns.Plates_ItemSets(setIDs, itemID)
	local map = {}
	for _, id in ipairs(setIDs) do
		map[id] = { item = itemID }
	end
	return map
end

-- Merges several { [widgetSetID] = info } maps (one per expansion) into one; later ones win.
function ns.Plates_MergeSets(maps)
	local merged = {}
	for _, map in ipairs(maps) do
		for id, info in pairs(map) do
			merged[id] = info
		end
	end
	return merged
end

-- The short progress of an objective's text, in any client language: "3/8" from "3/8 Boars slain" or
-- "Boars slain: 3 / 8", "45%" from "Slay boars (45%)". nil when the text carries no count.
function ns.Plates_Progress(text)
	if type(text) ~= "string" then
		return nil
	end
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have then
		return have .. "/" .. need
	end
	local percent = text:match("(%d+)%s*%%")
	if percent then
		return percent .. "%"
	end
	return nil
end

-- What a unit's nameplate shows for quests, from its tooltip lines in order. Each line is a plain table:
--   { kind = "title" }                          a quest's title
--   { kind = "player", mine = true|false }      in a group: whose objectives follow
--   { kind = "objective", text = s, completed = bool }
-- Objectives right under a title are yours; under a "player" line, that player's. Returns nil when no
-- objective of yours (or, with showParty, of your group) is left to do, else
-- { progress = "3/8" or nil, party = true when only a group member still needs this unit }.
function ns.Plates_QuestState(lines, showParty)
	local mine = true
	local partyText, partyFound
	for _, line in ipairs(lines or {}) do
		if line.kind == "title" then
			mine = true
		elseif line.kind == "player" then
			mine = line.mine and true or false
		elseif line.kind == "objective" and not line.completed then
			if mine then
				return { progress = ns.Plates_Progress(line.text), party = false }
			elseif showParty and not partyFound then
				partyFound, partyText = true, line.text
			end
		end
	end
	if partyFound then
		return { progress = ns.Plates_Progress(partyText), party = true }
	end
	return nil
end

-- How far a cast is, 0..1, from the start and end times in milliseconds and now (also in milliseconds).
-- A channel runs down instead of up. nil when the times make no sense.
function ns.Plates_CastFraction(startMs, endMs, nowMs, channel)
	if type(startMs) ~= "number" or type(endMs) ~= "number" or type(nowMs) ~= "number" or endMs <= startMs then
		return nil
	end
	local f = (nowMs - startMs) / (endMs - startMs)
	f = math.min(math.max(f, 0), 1)
	return channel and (1 - f) or f
end
