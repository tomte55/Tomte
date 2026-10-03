local addonName, ns = ...

-- Almost Done: meta achievements. A meta's children are its criteria of type 8 (the asset is the child's ID),
-- plus a short override list for metas whose children aren't all criteria. The built-in roots are the big
-- expansion metas; achievements under a root get its expansion when their category doesn't name one.

local CRITERIA_TYPE_ACHIEVEMENT = 8
local MAX_DEPTH = 3 -- how deep the expansion fill follows nested metas

-- Newest first. IDs from AlmostCompletedAchievements' meta list.
local ROOTS = {
	{ id = 62386, expansion = "Midnight" }, -- Light Up the Night
	{ id = 61451, expansion = "The War Within" }, -- Worldsoul-Searching
	{ id = 19458, expansion = "Dragonflight" }, -- A World Awoken
	{ id = 20501, expansion = "Shadowlands" }, -- Back from the Beyond
	{ id = 40953, expansion = "Battle for Azeroth" }, -- A Farewell to Arms
	{ id = 11446, expansion = "Legion" }, -- Broken Isles Pathfinder
	{ id = 10018, expansion = "Warlords of Draenor" }, -- Draenor Pathfinder
}

-- Children that aren't criteria of the meta (Light Up the Night tracks some through other achievements).
local EXTRA_CHILDREN = {
	[62386] = { 62261, 61453, 62260, 62256, 62873, 62874, 62563, 61906, 61380, 61568, 61839 },
}

local childCache = {} -- [metaID] = { child ids }, this session
local metaExpansion = {} -- [achievement id] = expansion, from the roots

function ns.Ach_MetaRoots()
	return ROOTS
end

function ns.Ach_MetaChildren(metaID)
	local cached = childCache[metaID]
	if cached then
		return cached
	end
	local list, seen = {}, {}
	for _, c in ipairs(ns.Ach_ReadCriteria(metaID)) do
		if c.type == CRITERIA_TYPE_ACHIEVEMENT and c.asset and c.asset > 0 and not seen[c.asset] then
			seen[c.asset] = true
			list[#list + 1] = c.asset
		end
	end
	for _, id in ipairs(EXTRA_CHILDREN[metaID] or {}) do
		if not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	childCache[metaID] = list
	return list
end

function ns.Ach_IsMeta(id)
	return #ns.Ach_MetaChildren(id) > 0
end

-- Metas an achievement is part of: from the scan, plus the extra children lists.
function ns.Ach_ParentsOf(id)
	local parents, seen = {}, {}
	local function Add(metaID)
		if not seen[metaID] then
			seen[metaID] = true
			parents[#parents + 1] = metaID
		end
	end
	for _, p in ipairs(ns.Ach_MetaLinks()[id] or {}) do
		Add(p)
	end
	for metaID, children in pairs(EXTRA_CHILDREN) do
		for _, child in ipairs(children) do
			if child == id then
				Add(metaID)
			end
		end
	end
	return parents
end

-- The expansion of the root meta an achievement sits under (known after the first scan), or nil.
function ns.Ach_MetaExpansion(id)
	return metaExpansion[id]
end

local function FillFrom(id, expansion, depth)
	if depth > MAX_DEPTH then
		return
	end
	for _, child in ipairs(ns.Ach_MetaChildren(id)) do
		if not metaExpansion[child] then
			metaExpansion[child] = expansion
			FillFrom(child, expansion, depth + 1)
		end
	end
end

-- After a scan: records without an expansion get their root meta's.
function ns.Ach_FillMetaExpansions(records)
	if not next(metaExpansion) then
		for _, root in ipairs(ROOTS) do
			FillFrom(root.id, root.expansion, 1)
		end
	end
	for id, record in pairs(records) do
		if not record.expansion and metaExpansion[id] then
			record.expansion = metaExpansion[id]
		end
	end
end

-- A meta for the browser: its own read plus its children's ({ id, name, icon, completed, percent, isMeta }),
-- incomplete first by percent, then completed by name.
function ns.Ach_MetaNode(metaID)
	local meta = ns.Ach_ReadAchievement(metaID)
	if not meta then
		return nil
	end
	local children = {}
	for _, id in ipairs(ns.Ach_MetaChildren(metaID)) do
		local child = ns.Ach_ReadAchievement(id)
		if child then
			child.isMeta = ns.Ach_IsMeta(id)
			children[#children + 1] = child
		end
	end
	table.sort(children, function(a, b)
		if a.completed ~= b.completed then
			return not a.completed
		end
		if not a.completed and (a.percent or 0) ~= (b.percent or 0) then
			return (a.percent or 0) > (b.percent or 0)
		end
		return a.name < b.name
	end)
	meta.children = children
	meta.metaPercent, meta.metaDone, meta.metaTotal = ns.Ach_MetaPercent(children)
	return meta
end

-- Metas that contain a listed record, for the browser's "close on" section (ids, most listed children first).
function ns.Ach_MetasOf(list)
	local count = {}
	for _, record in ipairs(list) do
		for _, p in ipairs(ns.Ach_ParentsOf(record.id)) do
			count[p] = (count[p] or 0) + 1
		end
	end
	local ids = {}
	for id in pairs(count) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		if count[a] ~= count[b] then
			return count[a] > count[b]
		end
		return a < b
	end)
	return ids, count
end
