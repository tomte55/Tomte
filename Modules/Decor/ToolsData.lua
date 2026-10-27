local addonName, ns = ...

-- Decorating tools: pure logic (no WoW API calls; unit-tested in tests/test_decor_tools.lua). The clipboard and the
-- recent list, what a quickbar key does, rotation steps, saved groups of favorites and tags, the share string, the
-- placed-list search and the hover key hints. The module is registered in Decorate.lua.

local SHARE_PREFIX = "TomteDecor1:"
-- Basic mode's RotateDecor turns one 15 degree step per call, whatever number it's given (measured by
-- AdvancedDecorationTools' players).
local ROTATE_STEP = 15
-- Expert mode's rotate increment turns about 45 degrees per second while it's held (same source).
local PULSE_DEGREES_PER_SECOND = 45

ns.DECORTOOLS_ROTATE_STEP = ROTATE_STEP

-- Clipboard -----------------------------------------------------------------------------------------------------------

local function IndexOf(list, decorID)
	for i, e in ipairs(list) do
		if e.id == decorID then
			return i
		end
	end
	return nil
end

-- Puts decorID at the top of the clipboard list ({ { id, cut } }, newest first). cut: true when it was cut out of the
-- house (its "to put back" count goes up by one). The list keeps at most max entries; the oldest fall off.
function ns.DecorTools_ClipAdd(list, decorID, cut, max)
	local i = IndexOf(list, decorID)
	local entry = i and table.remove(list, i) or { id = decorID, cut = 0 }
	if cut then
		entry.cut = (entry.cut or 0) + 1
	end
	table.insert(list, 1, entry)
	while #list > (max or #list) do
		table.remove(list)
	end
	return entry
end

-- One of decorID was placed from the clipboard: one fewer to put back.
function ns.DecorTools_ClipPlaced(list, decorID)
	local i = IndexOf(list, decorID)
	if i and (list[i].cut or 0) > 0 then
		list[i].cut = list[i].cut - 1
	end
end

function ns.DecorTools_ClipRemove(list, decorID)
	local i = IndexOf(list, decorID)
	if i then
		table.remove(list, i)
	end
end

-- Recent placements: decor IDs, newest first, no repeats, at most max.
function ns.DecorTools_RecentPush(list, decorID, max)
	for i = #list, 1, -1 do
		if list[i] == decorID then
			table.remove(list, i)
		end
	end
	table.insert(list, 1, decorID)
	while #list > max do
		table.remove(list)
	end
end

-- Quickbar --------------------------------------------------------------------------------------------------------------

-- What a quickbar key does: "place" the slot's decor, "bind" the decor you're holding to the empty slot, or "none".
function ns.DecorTools_SlotAction(slotDecorID, holdingDecorID)
	if slotDecorID then
		return "place"
	elseif holdingDecorID then
		return "bind"
	end
	return "none"
end

-- Rotation ------------------------------------------------------------------------------------------------------------

-- Basic-mode RotateDecor calls for a turn of `degrees` (positive = the game's +1 direction): count and direction.
function ns.DecorTools_RotateSteps(degrees, step)
	step = step or ROTATE_STEP
	local n = math.floor(math.abs(degrees or 0) / step + 0.5)
	return n, (degrees or 0) < 0 and -1 or 1
end

-- Seconds to hold Expert mode's rotate increment for a turn of `degrees`.
function ns.DecorTools_PulseSeconds(degrees)
	return math.abs(degrees or 0) / PULSE_DEGREES_PER_SECOND
end

-- Favorites and tags --------------------------------------------------------------------------------------------------

-- Tags: [tag name] = { [decorID] = true }. Adds decorID to the tag, or takes it out (an empty tag stays: the
-- player made it).
function ns.DecorTools_TagToggle(tags, name, decorID)
	local set = tags[name]
	if not set then
		set = {}
		tags[name] = set
	end
	if set[decorID] then
		set[decorID] = nil
		return false
	end
	set[decorID] = true
	return true
end

-- Tag names in order (case-insensitive).
function ns.DecorTools_TagNames(tags)
	local names = {}
	for name in pairs(tags or {}) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		local la, lb = a:lower(), b:lower()
		if la ~= lb then
			return la < lb
		end
		return a < b
	end)
	return names
end

-- A tag name the player typed, cleaned: trimmed, at most 30 characters. nil when nothing is left.
function ns.DecorTools_TagName(text)
	local name = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
	name = name:sub(1, 30)
	return name ~= "" and name or nil
end

local function SortedIDs(set, nameOf)
	local ids = {}
	for id in pairs(set or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		local na, nb = nameOf(a) or "", nameOf(b) or ""
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return ids
end

-- The Saved tab's groups: favorites first, then each tag by name, each list by decor name (nameOf(decorID)), empty
-- ones left out: { { title, tag (nil for favorites), ids } }.
function ns.DecorTools_SavedGroups(favorites, tags, nameOf)
	local groups = {}
	local fav = SortedIDs(favorites, nameOf)
	if #fav > 0 then
		groups[#groups + 1] = { title = "Favorites", ids = fav }
	end
	for _, name in ipairs(ns.DecorTools_TagNames(tags)) do
		local ids = SortedIDs(tags[name], nameOf)
		if #ids > 0 then
			groups[#groups + 1] = { title = name, tag = name, ids = ids }
		end
	end
	return groups
end

-- Share strings -----------------------------------------------------------------------------------------------------

-- Decor IDs (one per placed piece) as { { id, count } } sorted by ID.
function ns.DecorTools_CountIDs(ids)
	local counts, order = {}, {}
	for _, id in ipairs(ids or {}) do
		if not counts[id] then
			order[#order + 1] = id
		end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(order)
	local items = {}
	for i, id in ipairs(order) do
		items[i] = { id = id, count = counts[id] }
	end
	return items
end

-- { { id, count } } -> "TomteDecor1:1234x2,5678" (a count of 1 is left out).
function ns.DecorTools_ShareEncode(items)
	local parts = {}
	for _, item in ipairs(items or {}) do
		local count = item.count or 1
		parts[#parts + 1] = count > 1 and ("%dx%d"):format(item.id, count) or tostring(item.id)
	end
	return SHARE_PREFIX .. table.concat(parts, ",")
end

-- A share string -> { { id, count } } (same ID twice adds up, first-seen order), or nil and the reason.
function ns.DecorTools_ShareDecode(text)
	if type(text) ~= "string" then
		return nil, "That isn't a decor list."
	end
	local body = text:match("^%s*" .. SHARE_PREFIX:gsub("%p", "%%%0") .. "(.-)%s*$")
	if not body then
		return nil, "That isn't a Tomte decor list (it starts with " .. SHARE_PREFIX .. ")."
	end
	local items, at = {}, {}
	for part in body:gmatch("[^,]+") do
		local id, count = part:match("^%s*(%d+)x(%d+)%s*$")
		if not id then
			id = part:match("^%s*(%d+)%s*$")
			count = 1
		end
		if not id then
			return nil, ("Can't read \"%s\" in the list."):format(part)
		end
		id, count = tonumber(id), tonumber(count)
		if count > 0 then
			if at[id] then
				items[at[id]].count = items[at[id]].count + count
			else
				items[#items + 1] = { id = id, count = count }
				at[id] = #items
			end
		end
	end
	if #items == 0 then
		return nil, "The list is empty."
	end
	return items
end

-- Search and hints ----------------------------------------------------------------------------------------------------

-- Whether a decor name matches the placed-list search (case-insensitive, plain text; an empty search matches all).
function ns.DecorTools_Matches(name, query)
	query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
	if query == "" then
		return true
	end
	return type(name) == "string" and name:lower():find(query:lower(), 1, true) ~= nil
end

-- How many to destroy: what was asked, within what can be destroyed and the most one run does. nil for no number.
function ns.DecorTools_DestroyCount(text, destroyable, max)
	local n = tonumber(type(text) == "string" and text:match("^%s*(%d+)%s*$") or nil)
	if not n or n < 1 then
		return nil
	end
	return math.min(n, destroyable or 0, max)
end

-- The hover hint line from the keys (binding strings, "" for none) and keyText (binding -> "Ctrl+D"): nil when no key
-- of the hinted actions is set.
function ns.DecorTools_HintLine(keys, keyText)
	local parts = {}
	for _, hint in ipairs({ { "duplicate", "another" }, { "copy", "copy" }, { "cut", "cut" }, { "lock", "lock" } }) do
		local key = keys[hint[1]]
		if type(key) == "string" and key ~= "" then
			parts[#parts + 1] = keyText(key) .. " " .. hint[2]
		end
	end
	return #parts > 0 and table.concat(parts, "  ·  ") or nil
end
