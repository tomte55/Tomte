local addonName, ns = ...

-- Dressing room pure logic (no WoW API calls; unit-tested in tests/test_dressup.lua): the slot bar's groups, the
-- window's scale, the item list's lines, outfit names, ensemble counts, the transmogrifier's pending changes and the
-- title list.

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

-- Outfits ------------------------------------------------------------------------------------------------------------

-- The entry named `query` (any case): the exact name first, else the only name that starts with it, else the only
-- name that holds it. entries: { { name = ... }, ... }. Returns the entry, or nil and the names that matched (more
-- than one: the query is ambiguous; none: nothing matched).
function ns.DressUp_FindByName(entries, query)
	query = (query or ""):lower():match("^%s*(.-)%s*$")
	if query == "" then
		return nil, {}
	end
	local starts, holds = {}, {}
	for _, e in ipairs(entries) do
		local name = (e.name or ""):lower()
		if name == query then
			return e
		end
		if name:sub(1, #query) == query then
			starts[#starts + 1] = e
		elseif name:find(query, 1, true) then
			holds[#holds + 1] = e
		end
	end
	local list = #starts > 0 and starts or holds
	if #list == 1 then
		return list[1]
	end
	local names = {}
	for i, e in ipairs(list) do
		names[i] = e.name
	end
	return nil, names
end

-- Ensembles ----------------------------------------------------------------------------------------------------------

-- How many of an ensemble's looks are collected. items: { { appearanceID = n, collected = bool }, ... }, one per
-- piece; pieces that share a look count once, collected when any of them is. Returns have, total.
function ns.DressUp_EnsembleCounts(items)
	local seen, total, have = {}, 0, 0
	for _, item in ipairs(items or {}) do
		local id = item.appearanceID
		if id then
			if seen[id] == nil then
				seen[id] = false
				total = total + 1
			end
			if item.collected and not seen[id] then
				seen[id] = true
				have = have + 1
			end
		end
	end
	return have, total
end

-- The tooltip line and its color role, or nil for an empty set.
function ns.DressUp_EnsembleLine(have, total)
	if not total or total == 0 then
		return nil
	end
	if have >= total then
		return ("All %d appearances collected"):format(total), "success"
	end
	return ("%d of %d appearances collected"):format(have, total), have == 0 and "warning" or "accent"
end

-- An item's appearance for the tooltip line, from C_TransmogCollection.GetAppearanceInfoBySource (info) and
-- PlayerCanCollectSource (canCollect): "new" (not collected, this character can learn it), "other" (not collected,
-- only another class or armor type can), "source" (the look is collected, from another item) or "known" (collected
-- from this one). nil without info.
function ns.DressUp_AppearanceState(info, canCollect)
	if not info then
		return nil
	end
	if not info.appearanceIsCollected then
		return canCollect and "new" or "other"
	end
	return info.sourceIsCollected and "known" or "source"
end

local APPEARANCE_LINES = {
	new = { "Appearance not collected", "accent" },
	other = { "Appearance not collected (another class)", "textMuted" },
	source = { "Appearance collected from another item", "textMuted" },
	known = { "Appearance collected", "success" },
}

-- The tooltip line for a state: text, color role; nil for none.
function ns.DressUp_AppearanceLine(state)
	local line = APPEARANCE_LINES[state]
	if line then
		return line[1], line[2]
	end
	return nil
end

-- The Catalyst's line under its result: whether the piece's look is new. collected: nil when the item has no look
-- (or isn't loaded yet). Returns text, color role, or nil.
function ns.DressUp_LookText(collected)
	if collected == nil then
		return nil
	end
	if collected then
		return "Look collected", "textMuted"
	end
	return "New look", "success"
end

-- Transmogrifier ----------------------------------------------------------------------------------------------------

-- The transmogrifier's pending changes. slots: { { slot = n, type = n, options = { option, ... } }, ... } (every
-- appearance and illusion slot with the weapon options it has); read(slot, type, option) returns that slot's viewed
-- info ({ hasPending, transmogID, displayType }) or nil. Returns a list of
-- { slot, type, option, transmogID, displayType }, or nil when nothing is pending.
function ns.DressUp_PendingChanges(slots, read)
	local list = {}
	for _, s in ipairs(slots or {}) do
		for _, option in ipairs(s.options) do
			local info = read(s.slot, s.type, option)
			if info and info.hasPending and info.transmogID then
				list[#list + 1] = { slot = s.slot, type = s.type, option = option, transmogID = info.transmogID,
					displayType = info.displayType }
			end
		end
	end
	return #list > 0 and list or nil
end

-- Titles -------------------------------------------------------------------------------------------------------------

ns.DRESSUP_TITLE_FILTERS = {
	{ value = "owned", text = "Owned" },
	{ value = "missing", text = "Missing" },
	{ value = "all", text = "All" },
}

local function Trim(s)
	return (s or ""):match("^%s*(.-)%s*$")
end

-- titles: { { id = n, name = "Corporal ", known = bool }, ... }; query: search text (any case, "" for all); filter:
-- "owned", "missing" or "all". Returns { { id, name (trimmed), known }, ... } sorted by name.
function ns.DressUp_FilterTitles(titles, query, filter)
	query = Trim(query):lower()
	local list = {}
	for _, t in ipairs(titles or {}) do
		local name = Trim(t.name)
		local wanted = filter == "all" or (filter == "missing") == not t.known
		if name ~= "" and wanted and (query == "" or name:lower():find(query, 1, true)) then
			list[#list + 1] = { id = t.id, name = name, known = t.known and true or false }
		end
	end
	table.sort(list, function(a, b)
		local la, lb = a.name:lower(), b.name:lower()
		if la ~= lb then
			return la < lb
		end
		return a.id < b.id
	end)
	return list
end
