local addonName, ns = ...

-- Drawers: pure logic (no WoW API calls; unit-tested in tests/test_drawers.lua). What a drawer entry is, reading one
-- from a link or from the cursor, the list operations the editor needs (add, remove, move, clean), and where each
-- button of an open drawer sits.
--
-- An entry is { kind = "item" | "toy" | "spell" | "mount", id = number }: an item ID, a toy's item ID, a spell ID
-- or a mount journal ID (MountID).

ns.DRAWERS_COUNT = 4 -- drawers, each with its own button and key binding (TomteDrawer1..4)
ns.DRAWERS_MAX = 24 -- entries per drawer
ns.DRAWERS_DIRECTIONS = { "UP", "DOWN", "LEFT", "RIGHT" }

local KINDS = { item = true, toy = true, spell = true, mount = true }

function ns.Drawers_IsEntry(entry)
	return type(entry) == "table" and KINDS[entry.kind] == true and type(entry.id) == "number" and entry.id > 0
		and entry.id == math.floor(entry.id)
end

function ns.Drawers_Same(a, b)
	return a.kind == b.kind and a.id == b.id
end

-- The first link in text: "item", itemID; "spell", spellID; "mountSpell", spellID (the mount journal links a
-- mount by its summon spell). Also takes a bare "item:123" or "spell:123". nil when there's none.
function ns.Drawers_ParseLink(text)
	if type(text) ~= "string" then
		return nil
	end
	local kind, id = text:match("|H(%a+):(%d+)")
	if not kind then
		kind, id = text:match("^%s*(%a+):(%d+)")
	end
	id = tonumber(id)
	if not id or id <= 0 then
		return nil
	end
	if kind == "item" or kind == "spell" then
		return kind, id
	elseif kind == "mount" then
		return "mountSpell", id
	end
	return nil
end

-- What GetCursorInfo() holds: "item", itemID; "spell", spellID (its 4th return, else the base spell, its 5th);
-- "mount", mountID. nil for anything else (macros, money, battle pets).
function ns.Drawers_ParseCursor(cursorType, a, _, c, d)
	if cursorType == "item" and type(a) == "number" then
		return "item", a
	elseif cursorType == "spell" then
		local id = type(c) == "number" and c > 0 and c or (type(d) == "number" and d > 0 and d) or nil
		return id and "spell" or nil, id
	elseif cursorType == "mount" and type(a) == "number" then
		return "mount", a
	end
	return nil
end

function ns.Drawers_Find(entries, entry)
	for i, e in ipairs(entries) do
		if ns.Drawers_Same(e, entry) then
			return i
		end
	end
	return nil
end

-- Adds entry at the end. Returns its index, or nil and why: "invalid", "duplicate" or "full".
function ns.Drawers_Add(entries, entry, max)
	if not ns.Drawers_IsEntry(entry) then
		return nil, "invalid"
	end
	if ns.Drawers_Find(entries, entry) then
		return nil, "duplicate"
	end
	if #entries >= (max or ns.DRAWERS_MAX) then
		return nil, "full"
	end
	entries[#entries + 1] = { kind = entry.kind, id = entry.id }
	return #entries
end

function ns.Drawers_Remove(entries, index)
	if type(index) ~= "number" or not entries[index] then
		return nil
	end
	return table.remove(entries, index)
end

-- Moves the entry at `from` by delta places (-1 earlier, 1 later). Returns its new index, or nil at an end.
function ns.Drawers_Move(entries, from, delta)
	local to = from + delta
	if not entries[from] or to < 1 or to > #entries then
		return nil
	end
	local entry = table.remove(entries, from)
	table.insert(entries, to, entry)
	return to
end

-- Drops anything that isn't an entry, duplicates and anything past max, in place (saved data from an older or
-- hand-edited file). Returns how many it dropped.
function ns.Drawers_Clean(entries, max)
	local kept, dropped = {}, 0
	for _, e in ipairs(entries) do
		if ns.Drawers_IsEntry(e) and not ns.Drawers_Find(kept, e) and #kept < (max or ns.DRAWERS_MAX) then
			kept[#kept + 1] = e
		else
			dropped = dropped + 1
		end
	end
	for i = #entries, 1, -1 do
		entries[i] = nil
	end
	for i, e in ipairs(kept) do
		entries[i] = e
	end
	return dropped
end

-- Where the n buttons of an open drawer sit: centers relative to the drawer button's center, in pixels. They run
-- out in `direction` from the drawer button, perLine to a line; further lines stack to the right (UP, DOWN) or
-- downward (LEFT, RIGHT). Also returns the box around them all: { left, right, top, bottom } in the same space.
function ns.Drawers_Layout(n, direction, perLine, size, gap)
	perLine = math.max(1, math.floor(perLine or 1))
	local step = size + gap
	local points = {}
	local box = { left = 0, right = 0, top = 0, bottom = 0 }
	for i = 1, n do
		local along = (i - 1) % perLine + 1
		local line = math.floor((i - 1) / perLine)
		local x, y
		if direction == "DOWN" then
			x, y = line * step, -along * step
		elseif direction == "LEFT" then
			x, y = -along * step, -line * step
		elseif direction == "RIGHT" then
			x, y = along * step, -line * step
		else -- UP
			x, y = line * step, along * step
		end
		points[i] = { x = x, y = y }
		local half = size / 2
		if i == 1 then
			box.left, box.right, box.top, box.bottom = x - half, x + half, y + half, y - half
		else
			box.left = math.min(box.left, x - half)
			box.right = math.max(box.right, x + half)
			box.top = math.max(box.top, y + half)
			box.bottom = math.min(box.bottom, y - half)
		end
	end
	return points, box
end

-- Drawer i's saved settings and its entry list. Entries live apart from the settings (db.entries.d<i>, a collection)
-- so "Reset settings" keeps them; a missing list (cleared by hand) comes back empty.
function ns.Drawers_Saved(db, i)
	local key = "d" .. i
	db.entries[key] = db.entries[key] or {}
	return db[key], db.entries[key]
end

-- The drawer's name as the player sees it: the saved name, or "Drawer <n>" when it's blank.
function ns.Drawers_Name(name, index)
	if type(name) == "string" and name:match("%S") then
		return (name:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	return "Drawer " .. index
end
