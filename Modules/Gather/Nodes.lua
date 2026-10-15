local addonName, ns = ...

-- Gathering node spots: pure logic (no WoW API calls; unit-tested in tests/test_gather_nodes.lua). Where mining and
-- herbalism nodes were gathered, per map, with duplicates merged, and the "nodes" data set for Friend sharing
-- (Modules/Share). Recorded from Gather.lua, drawn on the world map by MapPins.lua.
-- Saved shape: db.nodes[uiMapID][pos] = objectID or kind letter, pos = x * 10000 + y with x, y in 0..9999;
-- db.nodeTypes[objectID] = { kind, name, item }.

local STEPS = 10000 -- a spot is kept to 1/10000 of the map: under a yard in any zone
local MERGE_YARDS = 10 -- spots of the same kind this close are one node (gathered from either side of it)
local FALLBACK_SHARE = 0.002 -- merge radius as a share of the map when the game doesn't know its size
local MAX_NODES = 50000 -- per payload; far more than every node in an expansion
local MAX_TYPES = 5000
local MAX_NAME = 60 -- bytes of a node name in the payload (display text only)
local HASH_MOD = 2147483648 -- 2^31: djb2 stays exact in Lua 5.1 doubles

local LETTERS = { mining = "m", herbalism = "h" } -- the kinds that are nodes: skinning is corpses, fishing pools move
local KINDS = { m = "mining", h = "herbalism" }

-- Merge grids: [spots table] = { rx, ry, cells = { [cell] = { pos... } } }, built on first use. Weak keys: a map
-- whose spots were forgotten takes its grid with it.
local grids = setmetatable({}, { __mode = "k" })

function ns.GatherNodes_Pack(x, y)
	local function Step(v)
		return math.max(0, math.min(STEPS - 1, math.floor(v * STEPS + 0.5)))
	end
	return Step(x) * STEPS + Step(y)
end

function ns.GatherNodes_Unpack(pos)
	return math.floor(pos / STEPS) / STEPS, (pos % STEPS) / STEPS
end

-- A spot's value (object ID or letter) -> its kind, or nil.
function ns.GatherNodes_Kind(db, value)
	if type(value) == "string" then
		return KINDS[value]
	end
	local t = db.nodeTypes[value]
	return t and t.kind
end

-- The merge radius in steps, x and y. sizeOf(mapID) -> width, height in yards (C_Map.GetMapWorldSize).
local function Radius(mapID, sizeOf)
	local w, h = sizeOf(mapID)
	local rx = (w and w > 0) and MERGE_YARDS / w or FALLBACK_SHARE
	local ry = (h and h > 0) and MERGE_YARDS / h or FALLBACK_SHARE
	return rx * STEPS, ry * STEPS
end

local function Cell(cx, cy)
	return cx * 100000 + cy
end

local function GridAdd(grid, pos)
	local x, y = math.floor(pos / STEPS), pos % STEPS
	local key = Cell(math.floor(x / grid.rx), math.floor(y / grid.ry))
	local list = grid.cells[key]
	if not list then
		list = {}
		grid.cells[key] = list
	end
	list[#list + 1] = pos
end

local function Grid(spots, mapID, sizeOf)
	local grid = grids[spots]
	if not grid then
		local rx, ry = Radius(mapID, sizeOf)
		grid = { rx = rx, ry = ry, cells = {} }
		grids[spots] = grid
		for pos in pairs(spots) do
			GridAdd(grid, pos)
		end
	end
	return grid
end

-- The spot of this kind within the merge radius of pos, or nil.
local function Near(db, spots, grid, pos, kind)
	local x, y = math.floor(pos / STEPS), pos % STEPS
	local cx, cy = math.floor(x / grid.rx), math.floor(y / grid.ry)
	for i = cx - 1, cx + 1 do
		for j = cy - 1, cy + 1 do
			for _, other in ipairs(grid.cells[Cell(i, j)] or {}) do
				local dx, dy = (math.floor(other / STEPS) - x) / grid.rx, (other % STEPS - y) / grid.ry
				if dx * dx + dy * dy <= 1 and ns.GatherNodes_Kind(db, spots[other]) == kind then
					return other
				end
			end
		end
	end
	return nil
end

-- Adds a spot unless it merges with one there. Returns true when it was added, and the spot's pos (the one it merged
-- into, or the new one).
local function Put(db, mapID, pos, value, kind, sizeOf)
	local spots = db.nodes[mapID]
	if not spots then
		spots = {}
		db.nodes[mapID] = spots
	end
	local grid = Grid(spots, mapID, sizeOf)
	local near = Near(db, spots, grid, pos, kind)
	if near then
		return false, near
	end
	-- Another kind's node on the very same step (an herb growing on an ore vein): one step over, a tenth of a yard.
	local base, step = pos, 0
	while spots[pos] ~= nil do
		step = step + 1
		pos = base % STEPS + step < STEPS and base + step or base - step
	end
	spots[pos] = value
	GridAdd(grid, pos)
	return true, pos
end

-- A gather of yours: kind "mining"/"herbalism" (others are ignored), objectID from the loot source (or nil),
-- info = { name, item } of the node type (yours replace what a friend sent). Returns true when it's a new spot, and
-- the spot's pos (merged into or new).
function ns.GatherNodes_Add(db, mapID, x, y, kind, objectID, sizeOf, info)
	local letter = LETTERS[kind]
	if not letter then
		return false, nil
	end
	if objectID then
		local t = db.nodeTypes[objectID]
		if not t or t.kind ~= kind then
			t = { kind = kind }
			db.nodeTypes[objectID] = t
		end
		if info then
			t.name = info.name or t.name
			t.item = info.item or t.item
		end
	end
	return Put(db, mapID, ns.GatherNodes_Pack(x, y), objectID or letter, kind, sizeOf)
end

-- Sorted { mapID, { pos... } } of every spot whose kind is known.
local function Sorted(db)
	local maps = {}
	for mapID, spots in pairs(db.nodes) do
		local list = {}
		for pos, value in pairs(spots) do
			if ns.GatherNodes_Kind(db, value) then
				list[#list + 1] = pos
			end
		end
		if #list > 0 then
			table.sort(list)
			maps[#maps + 1] = { mapID, list }
		end
	end
	table.sort(maps, function(a, b)
		return a[1] < b[1]
	end)
	return maps
end

local function CleanName(name)
	return (tostring(name or ""):gsub("[;,:=%^|]", "")):sub(1, MAX_NAME)
end

-- "t<objectID>=<m|h>:<item>:<name>;" for each node type in use, then "n<mapID>:<pos>=<value>,...;" per map.
function ns.GatherNodes_Export(db)
	local maps = Sorted(db)
	local used, typeIDs = {}, {}
	for _, m in ipairs(maps) do
		for _, pos in ipairs(m[2]) do
			local value = db.nodes[m[1]][pos]
			if type(value) == "number" and not used[value] then
				used[value] = true
				typeIDs[#typeIDs + 1] = value
			end
		end
	end
	table.sort(typeIDs)
	local out = {}
	for _, id in ipairs(typeIDs) do
		local t = db.nodeTypes[id]
		out[#out + 1] = ("t%d=%s:%s:%s;"):format(id, LETTERS[t.kind], t.item and tostring(t.item) or "",
			CleanName(t.name))
	end
	for _, m in ipairs(maps) do
		local spots, parts = db.nodes[m[1]], {}
		for i, pos in ipairs(m[2]) do
			parts[i] = pos .. "=" .. spots[pos]
		end
		out[#out + 1] = "n" .. m[1] .. ":" .. table.concat(parts, ",") .. ";"
	end
	return table.concat(out)
end

-- A hash of the spots only (map and position): node type names may differ between friends' game languages.
function ns.GatherNodes_Revision(db)
	local h = 5381
	for _, m in ipairs(Sorted(db)) do
		for _, pos in ipairs(m[2]) do
			local id = m[1] .. ":" .. pos .. ";"
			for i = 1, #id do
				h = (h * 33 + id:byte(i)) % HASH_MOD
			end
		end
	end
	return h
end

local function PositiveInt(text)
	local n = text:match("^%d+$") and tonumber(text)
	return n and n >= 1 and n or nil
end

-- Parses a whole payload: { types = { [id] = { kind, item, name } }, spots = { { mapID, pos, value } } } or nil, reason.
local function Parse(db, payload)
	if payload ~= "" and payload:sub(-1) ~= ";" then
		return nil, "unfinished payload"
	end
	local types, spots, nTypes = {}, {}, 0
	for entry in payload:gmatch("([^;]*);") do
		local id, letter, item, name = entry:match("^t(%d+)=(%a):(%d*):(.*)$")
		local mapID, list = entry:match("^n(%d+):(.+)$")
		if id then
			id = PositiveInt(id)
			if not (id and KINDS[letter]) then
				return nil, "bad node type"
			end
			nTypes = nTypes + 1
			if nTypes > MAX_TYPES then
				return nil, "too many node types"
			end
			types[id] = { kind = KINDS[letter], item = item ~= "" and tonumber(item) or nil, name = CleanName(name) }
		elseif mapID then
			mapID = PositiveInt(mapID)
			if not mapID then
				return nil, "bad map"
			end
			for spot in (list .. ","):gmatch("([^,]*),") do
				local pos, value = spot:match("^(%d+)=(%w+)$")
				pos = pos and tonumber(pos)
				if not pos or pos > STEPS * STEPS - 1 then
					return nil, "bad spot"
				end
				if not KINDS[value] then
					value = PositiveInt(value)
					if not value then
						return nil, "bad node"
					end
				end
				if #spots >= MAX_NODES then
					return nil, "too many nodes"
				end
				spots[#spots + 1] = { mapID, pos, value }
			end
		else
			return nil, "bad entry"
		end
	end
	for _, s in ipairs(spots) do
		local value = s[3]
		if type(value) == "number" and not (types[value] or db.nodeTypes[value]) then
			return nil, "node without a type"
		end
	end
	return { types = types, spots = spots }
end

-- A friend's payload: node types fill gaps, spots are added unless they merge with one there. Returns how many spots
-- were added, or nil, reason (then nothing was added).
function ns.GatherNodes_Import(db, payload, sizeOf)
	local parsed, why = Parse(db, payload)
	if not parsed then
		return nil, why
	end
	for id, t in pairs(parsed.types) do
		if not db.nodeTypes[id] then
			db.nodeTypes[id] = { kind = t.kind, item = t.item, name = t.name ~= "" and t.name or nil }
		end
	end
	local added = 0
	for _, s in ipairs(parsed.spots) do
		local kind = ns.GatherNodes_Kind(db, s[3])
		if kind and Put(db, s[1], s[2], s[3], kind, sizeOf) then
			added = added + 1
		end
	end
	return added
end

-- Spots per kind on one map and everywhere: here = { mining = n, herbalism = n }, all = { ... }.
function ns.GatherNodes_Counts(db, mapID)
	local here, all = {}, {}
	for id, spots in pairs(db.nodes) do
		for _, value in pairs(spots) do
			local kind = ns.GatherNodes_Kind(db, value)
			if kind then
				all[kind] = (all[kind] or 0) + 1
				if id == mapID then
					here[kind] = (here[kind] or 0) + 1
				end
			end
		end
	end
	return here, all
end

-- The spots on a map, by pos: { { x, y, kind, objectID, pos } }; kinds = { [kind] = true } to keep, nil for all;
-- hidden = { [objectID] = true } node types left out (spots of an unknown type are never hidden).
function ns.GatherNodes_List(db, mapID, kinds, hidden)
	local list = {}
	for pos, value in pairs(db.nodes[mapID] or {}) do
		local kind = ns.GatherNodes_Kind(db, value)
		if kind and (not kinds or kinds[kind]) and not (hidden and hidden[value]) then
			local x, y = ns.GatherNodes_Unpack(pos)
			list[#list + 1] = { x = x, y = y, kind = kind, objectID = type(value) == "number" and value or nil,
				pos = pos }
		end
	end
	-- In pos order, so the same spots always give the same route (Route.lua).
	table.sort(list, function(a, b)
		return a.pos < b.pos
	end)
	return list
end

-- The node types with spots on a map, for the type filter: { { objectID, kind, name, item, count } }, by kind, then
-- name. kinds as in GatherNodes_List. Spots of an unknown type aren't listed (they can't be hidden).
function ns.GatherNodes_Types(db, mapID, kinds)
	local byID, list = {}, {}
	for _, value in pairs(db.nodes[mapID] or {}) do
		local t = type(value) == "number" and db.nodeTypes[value]
		if t and (not kinds or kinds[t.kind]) then
			local entry = byID[value]
			if not entry then
				entry = { objectID = value, kind = t.kind, name = t.name, item = t.item, count = 0 }
				byID[value] = entry
				list[#list + 1] = entry
			end
			entry.count = entry.count + 1
		end
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		if (a.name or "") ~= (b.name or "") then
			return (a.name or "") < (b.name or "")
		end
		return a.objectID < b.objectID
	end)
	return list
end

-- GatherNodes_Types merged by what they drop, for the filter: a node's variants (Lush, Rich, Crystallized ...) are
-- their own node types with the same ore or herb. nameOf(type) -> the item's name (the same for every quality rank),
-- or nil when it isn't known (the type's own name then). { { name, kind, ids = { objectID... }, count } }, by kind,
-- then name.
function ns.GatherNodes_Groups(types, nameOf)
	local byKey, list = {}, {}
	for _, t in ipairs(types) do
		local name = nameOf(t) or t.name or ""
		local key = t.kind .. ":" .. name
		local group = byKey[key]
		if not group then
			group = { name = name, kind = t.kind, ids = {}, count = 0 }
			byKey[key] = group
			list[#list + 1] = group
		end
		group.ids[#group.ids + 1] = t.objectID
		group.count = group.count + t.count
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return a.name < b.name
	end)
	return list
end

-- Forgets every spot on one map. Returns how many there were.
function ns.GatherNodes_Forget(db, mapID)
	local n = 0
	for _ in pairs(db.nodes[mapID] or {}) do
		n = n + 1
	end
	db.nodes[mapID] = nil
	return n
end
