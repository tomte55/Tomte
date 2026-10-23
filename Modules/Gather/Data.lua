local addonName, ns = ...

-- Gathering sessions: pure logic (unit-tested with plain Lua, no WoW calls). Detect.lua turns casts and loot windows
-- into plain tables; this file classifies them, learns gathering spells, keeps the run model and its numbers, the
-- run history and the totals the page shows, and when the Resilient Seeds button shows.

ns.GATHER_KINDS = { "mining", "herbalism", "skinning", "fishing" }
ns.GATHER_SKILL_LINES = { mining = 186, herbalism = 182, skinning = 393, fishing = 356 }
-- "mixed" is a run's main kind when two or more kinds each have a real share of its nodes (Gather_RunKinds).
ns.GATHER_KIND_NAMES = { mining = "Mining", herbalism = "Herbalism", skinning = "Skinning", fishing = "Fishing",
	mixed = "Mixed" }
ns.GATHER_KIND_ICONS = { mining = "Interface\\Icons\\Trade_Mining", herbalism = "Interface\\Icons\\Trade_Herbalism",
	skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", fishing = "Interface\\Icons\\Trade_Fishing" }

-- A kind counts toward a mixed run with at least this many nodes and this share of the run's nodes: a herbalist
-- who taps one ore vein on the way is still on a Herbalism run.
local MIXED_MIN_NODES = 2
local MIXED_MIN_SHARE = 0.2

-- kinds (a run's Gather_RunKinds) -> "Mining & Herbalism", "Mining, Herbalism & Skinning".
function ns.Gather_KindsText(kinds)
	local names = {}
	for i, kind in ipairs(kinds) do
		names[i] = ns.GATHER_KIND_NAMES[kind] or kind
	end
	if #names <= 1 then
		return names[1] or "Gathering"
	end
	return table.concat(names, ", ", 1, #names - 1) .. " & " .. names[#names]
end

-- "Mining run", "Mining & Herbalism run" for a mixed one (kinds from Gather_Numbers), "Gathering run" when nothing
-- was gathered yet.
function ns.Gather_RunTitle(kind, kinds)
	if kind == "mixed" and kinds then
		return ns.Gather_KindsText(kinds) .. " run"
	end
	return (kind and kind ~= "mixed" and ns.GATHER_KIND_NAMES[kind] or "Gathering") .. " run"
end

-- The icon for a run's numbers: its biggest kind's.
function ns.Gather_RunIcon(n)
	return ns.GATHER_KIND_ICONS[n.kinds and n.kinds[1] or n.mainKind] or ns.GATHER_KIND_ICONS.mining
end

-- Gathering spell IDs as listed in GatherMate2's collector (https://github.com/Nevcairiel/GatherMate2) and on
-- Wowhead. IDs only (game facts), no code. Ranks and expansions Tomte doesn't list are learned (Gather_Learn).
ns.GATHER_SPELLS = {
	[2575] = "mining", [195122] = "mining", [423341] = "mining", [471013] = "mining",
	[2366] = "herbalism",
	[8613] = "skinning",
	[7620] = "fishing", [131476] = "fishing",
}

-- Casts that open things but aren't gathering: Opening (3365, 22810), Pick Lock, Survey, Logging (housing lumber).
ns.GATHER_NOT = { [3365] = true, [22810] = true, [1804] = true, [73979] = true, [167895] = true, [1239682] = true }
local OPENING = { [3365] = true, [22810] = true }

local CAST_FRESH = 3 -- seconds a cast stays linked to the loot window that follows
ns.GATHER_CAST_FRESH = CAST_FRESH -- Detect.lua's FreshCast uses the same window
local SEEN_MAX = 500
local FINDS_MAX = 20
local ITEMS_KEPT = 15
local LIVE_TAIL = 120 -- a live run's clock stops this long after its last gather
local MIN_DURATION = 60

local TRADEGOODS = 7 -- Enum.ItemClass.Tradegoods
local ITEM_KINDS = { [7] = "mining", [9] = "herbalism", [6] = "skinning" } -- Tradeskill subclasses

-- "GameObject-0-1-2-3-410000-0001" -> "GameObject", 410000. The id is the 6th field (nil for Item GUIDs).
function ns.Gather_ParseGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind = guid:match("^(%a+)%-")
	if not kind then
		return nil
	end
	local i, id = 0, nil
	for field in guid:gmatch("[^%-]+") do
		i = i + 1
		if i == 6 then
			id = tonumber(field)
			break
		end
	end
	return kind, id
end

-- names = { [localized anchor spell name] = kind }, learned = db.spells.
function ns.Gather_SpellKind(spellID, spellName, names, learned)
	if spellID and ns.GATHER_NOT[spellID] then
		return nil
	end
	if spellID and ns.GATHER_SPELLS[spellID] then
		return ns.GATHER_SPELLS[spellID]
	end
	if spellID and learned and learned[spellID] then
		return learned[spellID]
	end
	if spellName and names and names[spellName] then
		return names[spellName]
	end
	return nil
end

function ns.Gather_ItemKind(classID, subClassID)
	if classID ~= TRADEGOODS then
		return nil
	end
	return ITEM_KINDS[subClassID]
end

-- What the window's sources are: "GameObject" or "Creature" when they all are, "Item" when any is, "mixed",
-- or nil when none could be read.
local function SourceType(win)
	local found
	for _, slot in ipairs(win.slots or {}) do
		for _, guid in ipairs(slot.sources or {}) do
			local kind = ns.Gather_ParseGUID(guid)
			if kind == "Item" then
				return "Item"
			elseif kind then
				if found and found ~= kind then
					found = "mixed"
				elseif not found then
					found = kind
				end
			end
		end
	end
	return found
end

-- The gathering kind most of the window's gather items are (more than half of their units), and the source type.
function ns.Gather_ContentsKind(win)
	local units, total = {}, 0
	for _, slot in ipairs(win.slots or {}) do
		local kind = ns.Gather_ItemKind(slot.classID, slot.subClassID)
		if kind then
			local n = slot.count or 1
			units[kind] = (units[kind] or 0) + n
			total = total + n
		end
	end
	local best
	for kind, n in pairs(units) do
		if n * 2 > total then
			best = kind
		end
	end
	return best, SourceType(win)
end

local function Fits(kind, sourceType)
	if sourceType == nil then
		return true -- sources unreadable: the cast decides
	end
	if kind == "mining" or kind == "herbalism" then
		return sourceType == "GameObject"
	elseif kind == "skinning" then
		return sourceType == "Creature"
	end
	return false
end

local function Fresh(cast, now)
	return cast and cast.spellID and cast.at and now and now - cast.at <= CAST_FRESH
end

-- win = { fromItem, fishing, slots = { { link, itemID, count, quality, classID, subClassID, sources } } }
-- cast = { spellID, kind, at } or nil; opts = { now, fishing }. Returns kind or nil, and a reason for "why".
function ns.Gather_Classify(win, cast, opts)
	opts = opts or {}
	if win.fromItem then
		return nil, "container"
	end
	if not win.slots or #win.slots == 0 then
		return nil, "empty"
	end
	local contents, sourceType = ns.Gather_ContentsKind(win)
	if sourceType == "Item" then
		return nil, "container"
	end
	if win.fishing then
		if opts.fishing == false then
			return nil, "fishing (not counted)"
		end
		return "fishing", "fishing loot"
	end
	if Fresh(cast, opts.now) then
		if ns.GATHER_NOT[cast.spellID] then
			return nil, OPENING[cast.spellID] and "opening" or ("not gathering (spell " .. cast.spellID .. ")")
		end
		if cast.kind and cast.kind ~= "fishing" then
			if Fits(cast.kind, sourceType) then
				return cast.kind, "cast " .. cast.spellID
			end
			return nil, ("cast %d doesn't fit %s loot"):format(cast.spellID, sourceType)
		end
	end
	if sourceType == "GameObject" and (contents == "mining" or contents == "herbalism") then
		return contents, contents == "mining" and "contents: ore" or "contents: herbs"
	end
	if sourceType == "Creature" then
		return nil, "creature loot without a gathering cast"
	end
	return nil, "not gathering loot"
end

-- Learns an unknown, readable cast after it opened two windows of the same gathering kind. pending[spellID] =
-- { kind, n }. Returns the kind when it was just learned.
function ns.Gather_Learn(learned, pending, cast, win, kindFromContents)
	local id = cast and cast.spellID
	if not id or not kindFromContents or kindFromContents == "fishing" then
		return nil
	end
	if ns.GATHER_NOT[id] or ns.GATHER_SPELLS[id] or learned[id] then
		return nil
	end
	local p = pending[id]
	if not p or p.kind ~= kindFromContents then
		pending[id] = { kind = kindFromContents, n = 1 }
		return nil
	end
	p.n = p.n + 1
	if p.n >= 2 then
		learned[id] = kindFromContents
		pending[id] = nil
		return kindFromContents
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- The run

-- baseline = { name, class, manual }
function ns.Gather_NewRun(guid, now, baseline)
	baseline = baseline or {}
	return {
		guid = guid, name = baseline.name, class = baseline.class, manual = baseline.manual or nil,
		start = now, lastAt = now, gathers = 0, nodes = 0, seen = {}, seenList = {},
		kinds = {}, items = {}, finds = {}, zones = {}, nodeTypes = {}, skill = {}, knowledge = {}, drops = {},
	}
end

local function Remember(run, guid)
	run.seen[guid] = true
	local list = run.seenList
	list[#list + 1] = guid
	if #list > SEEN_MAX then
		local keep = {}
		for i = math.floor(SEEN_MAX / 2) + 1, #list do
			keep[#keep + 1] = list[i]
		end
		for i = 1, #list - #keep do
			run.seen[list[i]] = nil
		end
		run.seenList = keep
	end
end

-- The run's entry for a zone, created on first use.
local function Zone(run, mapID)
	local zone = run.zones[mapID]
	if not zone then
		zone = { nodes = 0, v = 0 }
		run.zones[mapID] = zone
	end
	return zone
end

-- g = { at, kind, sources = { guid... }, mapID, objectID, nodeName }. One gather per source; a source GUID not seen
-- before in this run is a new node (a rich vein mined three times is one node). No readable source: one of each.
function ns.Gather_AddGather(run, g)
	local kind = g.kind or "mining"
	local k = run.kinds[kind]
	if not k then
		k = { nodes = 0, gathers = 0 }
		run.kinds[kind] = k
	end
	local zone = g.mapID and Zone(run, g.mapID)
	local sources = g.sources or {}
	local newNodes, gathers = 0, math.max(#sources, 1)
	if #sources == 0 then
		newNodes = 1
	else
		for _, guid in ipairs(sources) do
			if not run.seen[guid] then
				Remember(run, guid)
				newNodes = newNodes + 1
			end
		end
	end
	run.gathers = run.gathers + gathers
	run.nodes = run.nodes + newNodes
	k.gathers = k.gathers + gathers
	k.nodes = k.nodes + newNodes
	if zone then
		zone.nodes = zone.nodes + newNodes
	end
	if g.objectID and newNodes > 0 then
		local t = run.nodeTypes[g.objectID]
		if not t then
			t = { n = 0 }
			run.nodeTypes[g.objectID] = t
		end
		t.n = t.n + newNodes
		t.name = g.nodeName or t.name
		t.kind = kind
	end
	if g.at and g.at > run.lastAt then
		run.lastAt = g.at
	end
end

-- it = { itemID, link, count, unit, rank, quality, kind, mapID }. Returns the item's entry.
function ns.Gather_AddItem(run, it)
	local e = ns.Value_LootAdd(run.items, it.itemID, it.link, it.count or 1, it.unit, "gathered")
	e.rank = it.rank or e.rank
	e.q = it.quality or e.q
	e.kind = it.kind or e.kind
	if it.mapID then
		local zone = Zone(run, it.mapID)
		zone.v = zone.v + (it.unit or 0) * (it.count or 1)
	end
	return e
end

-- f = { kind = "item" | "drop", itemID, link, skillLine, at }
function ns.Gather_AddFind(run, f)
	run.finds[#run.finds + 1] = f
	while #run.finds > FINDS_MAX do
		table.remove(run.finds, 1)
	end
end

function ns.Gather_IsFind(quality)
	return type(quality) == "number" and quality >= 3
end

-- pending[slot] = item read when the window opened. Returns it once, when its slot was looted.
function ns.Gather_Booked(pending, slot)
	local it = pending[slot]
	pending[slot] = nil
	return it
end

function ns.Gather_Skill(run, skillLine, level)
	if type(level) ~= "number" then
		return
	end
	local s = run.skill[skillLine]
	if not s then
		run.skill[skillLine] = { from = level, to = level }
	else
		s.to = level
	end
end

-- Only increases count: spending points mid-run isn't a loss.
function ns.Gather_Knowledge(run, skillLine, available)
	if type(available) ~= "number" then
		return
	end
	local k = run.knowledge[skillLine]
	if not k then
		run.knowledge[skillLine] = { last = available, gained = 0 }
		return
	end
	if available > k.last then
		k.gained = k.gained + available - k.last
	end
	k.last = available
end

-- Finished: last gather - start. Live: now - start, the clock stopping two minutes after the last gather.
function ns.Gather_Duration(run, now, live)
	local endAt = run.lastAt or run.start
	if live and now then
		endAt = math.min(now, endAt + LIVE_TAIL)
	end
	return math.max(endAt - run.start, MIN_DURATION)
end

local function PerHour(n, seconds)
	return math.floor(n * 3600 / seconds + 0.5)
end

local function ItemsValue(items, priceNow)
	local priced = false
	for key, e in pairs(items or {}) do
		if e.v > 0 or (priceNow and priceNow(key, e)) then
			priced = true
			break
		end
	end
	if not priced then
		return nil
	end
	return (ns.Value_LootTotals(items, priceNow))
end

-- The kinds that make up a run, most nodes first (ties in GATHER_KINDS order): the biggest always, others with a
-- real share (MIXED_MIN_NODES and MIXED_MIN_SHARE). Empty for a run without nodes.
function ns.Gather_RunKinds(run)
	local list, total = {}, 0
	for i, kind in ipairs(ns.GATHER_KINDS) do
		local k = run.kinds and run.kinds[kind]
		if k and k.nodes > 0 then
			list[#list + 1] = { kind = kind, nodes = k.nodes, order = i }
			total = total + k.nodes
		end
	end
	table.sort(list, function(a, b)
		if a.nodes ~= b.nodes then
			return a.nodes > b.nodes
		end
		return a.order < b.order
	end)
	local kinds = {}
	for i, e in ipairs(list) do
		if i == 1 or (e.nodes >= MIXED_MIN_NODES and e.nodes >= total * MIXED_MIN_SHARE) then
			kinds[#kinds + 1] = e.kind
		end
	end
	return kinds
end

-- The run's kind, "mixed" when Gather_RunKinds has more than one, nil without nodes.
function ns.Gather_MainKind(run)
	local kinds = ns.Gather_RunKinds(run)
	return #kinds > 1 and "mixed" or kinds[1]
end

-- priceNow(key, entry) -> copper or nil (Value_LootTotals), or nil to use the value when gathered.
function ns.Gather_Numbers(run, now, live, priceNow)
	local duration = ns.Gather_Duration(run, now, live)
	local value = ItemsValue(run.items, priceNow)
	local kinds = ns.Gather_RunKinds(run)
	return {
		kinds = kinds,
		duration = duration, nodes = run.nodes or 0, gathers = run.gathers or 0,
		nodesPerHour = PerHour(run.nodes or 0, duration),
		value = value, valuePerHour = value and PerHour(value, duration) or nil,
		mainKind = #kinds > 1 and "mixed" or kinds[1],
	}
end

function ns.Gather_Idle(run, now, idle)
	return now - (run.lastAt or run.start) >= idle
end

-- What to do with a saved run at login or reload: "continue", "finish" (another character, or timed out) or "none".
function ns.Gather_Resume(run, guid, now, idle)
	if type(run) ~= "table" or not run.start then
		return "none"
	end
	if run.guid ~= guid or ns.Gather_Idle(run, now, idle) then
		return "finish"
	end
	return "continue"
end

-- Kept when started by hand or big enough; a run without a single node never is.
function ns.Gather_Keep(run, minNodes)
	if (run.nodes or 0) == 0 then
		return false
	end
	return run.manual == true or run.nodes >= minNodes
end

---------------------------------------------------------------------------------------------------------------
-- History

-- Sort order for { key, v, n } rows: value, then count, then key.
local function MostValuable(a, b)
	if a.v ~= b.v then
		return a.v > b.v
	end
	if a.n ~= b.n then
		return a.n > b.n
	end
	return tostring(a.key) < tostring(b.key)
end

-- The copy kept for a finished run: no seen GUIDs, only the ITEMS_KEPT (15) most valuable items.
function ns.Gather_Compact(run)
	local copy = {}
	for k, v in pairs(run) do
		if k ~= "seen" and k ~= "seenList" and k ~= "items" then
			copy[k] = v
		end
	end
	local list = {}
	for key, e in pairs(run.items or {}) do
		list[#list + 1] = { key = key, v = e.v or 0, n = e.n or 0, e = e }
	end
	table.sort(list, MostValuable)
	copy.items = {}
	for i = 1, math.min(#list, ITEMS_KEPT) do
		copy.items[list[i].key] = list[i].e
	end
	return copy
end

-- Newest first, at most keepCount runs per character.
function ns.Gather_Archive(runs, copy, keepCount)
	table.insert(runs, 1, copy)
	local perChar = {}
	local i = 1
	while i <= #runs do
		local g = runs[i].guid or "?"
		perChar[g] = (perChar[g] or 0) + 1
		if perChar[g] > keepCount then
			table.remove(runs, i)
		else
			i = i + 1
		end
	end
end

-- scope "char" (with guid) or "all"; since = server time (nil: all time); kind = a gathering kind or nil/"all".
function ns.Gather_Filter(runs, scope, guid, since, kind)
	local list = {}
	for _, r in ipairs(runs or {}) do
		local ok = not (scope == "char" and r.guid ~= guid)
		if ok and since and (r.lastAt or r.start) < since then
			ok = false
		end
		if ok and kind and kind ~= "all" then
			local k = r.kinds and r.kinds[kind]
			ok = k ~= nil and k.nodes > 0
		end
		if ok then
			list[#list + 1] = r
		end
	end
	return list
end

-- live: the run in list that's still going (its clock counts to now).
function ns.Gather_Totals(list, now, priceNow, live)
	local t = { count = 0, duration = 0, nodes = 0 }
	local value
	for _, r in ipairs(list) do
		local n = ns.Gather_Numbers(r, now, r == live, priceNow)
		t.count = t.count + 1
		t.duration = t.duration + n.duration
		t.nodes = t.nodes + n.nodes
		if n.value then
			value = (value or 0) + n.value
		end
	end
	t.value = value
	t.nodesPerHour = t.duration > 0 and PerHour(t.nodes, t.duration) or 0
	t.valuePerHour = value and t.duration > 0 and PerHour(value, t.duration) or nil
	return t
end

-- { { itemID, link, rank, ranks = { [rank] = n }, n, v } }, most valuable first (by count without prices).
function ns.Gather_ItemTotals(list)
	local byKey, rows = {}, {}
	for _, r in ipairs(list) do
		for key, e in pairs(r.items or {}) do
			local row = byKey[key]
			if not row then
				row = { key = key, itemID = type(key) == "number" and key or nil, link = e.link, rank = e.rank,
					kind = e.kind, q = e.q, ranks = {}, n = 0, v = 0 }
				byKey[key] = row
				rows[#rows + 1] = row
			end
			row.n = row.n + (e.n or 0)
			row.v = row.v + (e.v or 0)
			row.rank = row.rank or e.rank
			if e.rank then
				row.ranks[e.rank] = (row.ranks[e.rank] or 0) + (e.n or 0)
			end
		end
	end
	table.sort(rows, MostValuable)
	return rows
end

-- Per zone and the run's main kind: { mapID, kind, runs, nodes, seconds, value, nodesPerHour, valuePerHour }.
-- A run's time is split over its zones by their share of its nodes.
function ns.Gather_ZoneStats(list, now, live)
	local byKey, rows = {}, {}
	for _, r in ipairs(list) do
		local duration = ns.Gather_Duration(r, now, r == live)
		local kind = ns.Gather_MainKind(r) or "mining"
		local total = r.nodes or 0
		for mapID, z in pairs(r.zones or {}) do
			if z.nodes > 0 or z.v > 0 then
				local key = mapID .. ":" .. kind
				local row = byKey[key]
				if not row then
					row = { mapID = mapID, kind = kind, runs = 0, nodes = 0, seconds = 0 }
					byKey[key] = row
					rows[#rows + 1] = row
				end
				row.runs = row.runs + 1
				row.nodes = row.nodes + z.nodes
				row.seconds = row.seconds + (total > 0 and duration * z.nodes / total or 0)
				if z.v > 0 then
					row.value = (row.value or 0) + z.v
				end
			end
		end
	end
	for _, row in ipairs(rows) do
		row.seconds = math.floor(row.seconds + 0.5)
		row.nodesPerHour = row.seconds > 0 and PerHour(row.nodes, row.seconds) or 0
		row.valuePerHour = row.value and row.seconds > 0 and PerHour(row.value, row.seconds) or nil
	end
	table.sort(rows, function(a, b)
		local x, y = a.valuePerHour or -1, b.valuePerHour or -1
		if x ~= y then
			return x > y
		end
		return a.nodesPerHour > b.nodesPerHour
	end)
	return rows
end

---------------------------------------------------------------------------------------------------------------
-- Play session

-- The play session's gathering: session.gather = { runs, nodes, value }, added to as nodes and items come in (so a
-- logout mid-run still counts), and a run when a kept run ends. Returns session.gather.
function ns.Gather_SessionAdd(session, nodes, value, runs)
	local g = session.gather
	if type(g) ~= "table" then
		g = { runs = 0, nodes = 0, value = 0 }
		session.gather = g
	end
	g.nodes = (g.nodes or 0) + (nodes or 0)
	g.value = (g.value or 0) + (value or 0)
	g.runs = (g.runs or 0) + (runs or 0)
	return g
end

-- "gathered 42 nodes · 3,860g" (no value part without prices), or nil when nothing was gathered.
function ns.Gather_SessionLine(g, money)
	if type(g) ~= "table" or (g.nodes or 0) == 0 then
		return nil
	end
	local text = ("gathered %d %s"):format(g.nodes, g.nodes == 1 and "node" or "nodes")
	if money and (g.value or 0) > 0 then
		text = text .. " · " .. money(g.value)
	end
	return text
end

-- Seeds ---------------------------------------------------------------------------------------------------------------
-- The seed button (Seeds.lua) with the "seeds" content (Data/Midnight/Seeds.lua).

ns.GATHER_SOIL_LINGER = 30 -- seconds the seed button stays after you last pointed at Rich Soil
ns.GATHER_SOIL_LEARN = 60 -- a plant cast this soon after pointing at an object teaches that object as Rich Soil

-- Whether an object ID is a Rich Soil spot: shipped in the content data or learned in game.
function ns.Gather_IsSoil(objectID, shipped, learned)
	if type(objectID) ~= "number" then
		return false
	end
	return (shipped and shipped[objectID]) == true or (learned and learned[objectID]) == true
end

-- The seed spell's entry in content.items, or nil.
function ns.Gather_SeedForSpell(items, spellID)
	for _, seed in ipairs(items or {}) do
		if seed.spell == spellID then
			return seed
		end
	end
	return nil
end

-- A plant cast just succeeded: the object pointed at last ({ id, at, map }) is Rich Soil when it was seen within
-- GATHER_SOIL_LEARN seconds, on a seed map. -> its object ID, or nil.
function ns.Gather_SoilLearn(last, now, maps)
	if type(last) ~= "table" or type(last.id) ~= "number" or not last.at or not now then
		return nil
	end
	if now - last.at > ns.GATHER_SOIL_LEARN or not (maps and last.map and maps[last.map]) then
		return nil
	end
	return last.id
end

-- Whether the seed button shows. s = { on (setting), herbalist, onMap (a seed map), held (seed types in the bags),
-- soilAt (when Rich Soil was last pointed at), now }.
function ns.Gather_SeedsShown(s)
	if not (s.on and s.herbalist and s.onMap) or (s.held or 0) == 0 then
		return false
	end
	return s.soilAt ~= nil and s.now ~= nil and s.now - s.soilAt <= ns.GATHER_SOIL_LINGER
end
