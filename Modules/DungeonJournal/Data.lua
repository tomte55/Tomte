local addonName, ns = ...

-- Dungeon journal: pure logic (no WoW API calls; unit-tested in tests/test_dungeonjournal.lua). Reads the generated
-- table (Data/Forever/DungeonJournal.lua): which quests are yours, what state each is in, the boss list and search.
-- The page is Page.lua; the module is registered in DungeonJournal.lua.

local EXTRA_NAME = "Rares and trash" -- the last entry on the boss list: rare spawns' loot, then trash drops
local NO_MAX_SPAN = 8 -- levels a dungeon with no known top level counts as right for you, from its lowest
local GROUPS = {
	{ key = "now", name = "Right for your level" },
	{ key = "later", name = "Coming up" },
	{ key = "past", name = "Behind you" },
}

-- Where a dungeon sits against your level: "now" (in its range), "later" (above you, or unknown) or "past".
function ns.DJ_LevelGroup(min, max, level)
	if not min then
		return "later"
	end
	local top = max or (min + NO_MAX_SPAN)
	if level < min then
		return "later"
	elseif level > top then
		return "past"
	end
	return "now"
end

-- The dungeon list (already in level order) as { key, name, list } groups in GROUPS order, empty ones left out.
function ns.DJ_Groups(list, level)
	local byKey, out = {}, {}
	for _, g in ipairs(GROUPS) do
		byKey[g.key] = { key = g.key, name = g.name, list = {} }
	end
	for _, d in ipairs(list) do
		local group = byKey[ns.DJ_LevelGroup(d.min, d.max, level)]
		group.list[#group.list + 1] = d
	end
	for _, g in ipairs(GROUPS) do
		if #byKey[g.key].list > 0 then
			out[#out + 1] = byKey[g.key]
		end
	end
	return out
end

function ns.DJ_LevelText(min, max)
	if not min then
		return nil
	end
	if max and max > min then
		return ("Level %d-%d"):format(min, max)
	end
	return ("Level %d+"):format(min)
end

-- side: "A" or "H" (yours); class: your class token ("MAGE").
function ns.DJ_QuestFits(q, side, class)
	if q.side and q.side ~= side then
		return false
	end
	if q.classes then
		for _, c in ipairs(q.classes) do
			if c == class then
				return true
			end
		end
		return false
	end
	return true
end

-- ctx = { level, side, class, done(questID) -> bool, active(questID) -> bool }
function ns.DJ_QuestState(q, ctx)
	if ctx.done(q.id) then
		return "done"
	elseif ctx.active(q.id) then
		return "active"
	elseif not ns.DJ_QuestFits(q, ctx.side, ctx.class) then
		return "other"
	elseif q.lvl and q.lvl > ctx.level then
		return "low"
	end
	return "open"
end

-- The dungeon's quests as { wing, quest }, wing by wing: yours, then (showOther) everyone else's in that wing, so a
-- wing's heading is drawn once.
function ns.DJ_Quests(inst, side, class, showOther)
	local list = {}
	for _, wing in ipairs(inst.wings) do
		local rest = {}
		for _, q in ipairs(wing.quests) do
			local entry = { wing = wing, quest = q }
			if ns.DJ_QuestFits(q, side, class) then
				list[#list + 1] = entry
			elseif showOther then
				rest[#rest + 1] = entry
			end
		end
		for _, entry in ipairs(rest) do
			list[#list + 1] = entry
		end
	end
	return list
end

-- The bosses as { wing, boss } in kill order, wing by wing; then one entry with every rare's loot and the trash drops
-- (boss.extra = true), when there are any.
function ns.DJ_Bosses(inst)
	local list, loot, seen = {}, {}, {}
	local function Add(id)
		if not seen[id] then
			seen[id] = true
			loot[#loot + 1] = id
		end
	end
	for _, wing in ipairs(inst.wings) do
		for _, boss in ipairs(wing.bosses) do
			list[#list + 1] = { wing = wing, boss = boss }
		end
	end
	for _, wing in ipairs(inst.wings) do
		for _, rare in ipairs(wing.rares) do
			for _, id in ipairs(rare.loot) do
				Add(id)
			end
		end
	end
	for _, wing in ipairs(inst.wings) do
		for _, id in ipairs(wing.trash) do
			Add(id)
		end
	end
	if #loot > 0 then
		list[#list + 1] = { boss = { name = EXTRA_NAME, loot = loot, extra = true } }
	end
	return list
end

local function Has(name, text)
	return name ~= nil and name:lower():find(text, 1, true) ~= nil
end

local function Clean(text)
	return ((text or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

-- What a search found in the dungeon, so it can open on it: {} for the dungeon's or a wing's own name (just open it),
-- { tab = "bosses", boss, item } for a boss or its loot, { tab = "bosses", extra = true, item } for a rare or trash,
-- { tab = "quests", quest, item } for a quest or its reward; nil for nothing (or no text). Bosses are looked at
-- first, then quests, then rares and trash. nameOf as for DJ_Matches.
function ns.DJ_Hit(inst, text, nameOf)
	text = Clean(text)
	if text == "" then
		return nil
	end
	if Has(inst.name, text) then
		return {}
	end
	local function ItemIn(list)
		for _, id in ipairs(list or {}) do
			if Has(nameOf("item", id, nil), text) then
				return id
			end
		end
	end
	for _, wing in ipairs(inst.wings) do
		if Has(wing.name, text) then
			return {}
		end
	end
	-- Its own name first (nothing to mark), then an item it gives.
	local function Found(name, ids)
		if Has(name, text) then
			return true, nil
		end
		local item = ItemIn(ids)
		return item ~= nil, item
	end
	for _, wing in ipairs(inst.wings) do
		for _, boss in ipairs(wing.bosses) do
			local hit, item = Found(boss.name, boss.loot)
			if hit then
				return { tab = "bosses", boss = boss, item = item }
			end
		end
	end
	for _, wing in ipairs(inst.wings) do
		for _, q in ipairs(wing.quests) do
			local hit, item = Found(nameOf("quest", q.id, q.name), q.rewards)
			if hit then
				return { tab = "quests", quest = q, item = item }
			end
		end
	end
	for _, wing in ipairs(inst.wings) do
		for _, rare in ipairs(wing.rares) do
			local hit, item = Found(rare.name, rare.loot)
			if hit then
				return { tab = "bosses", extra = true, item = item }
			end
		end
		local item = ItemIn(wing.trash)
		if item then
			return { tab = "bosses", extra = true, item = item }
		end
	end
	return nil
end

-- Does any name in the dungeon contain text (plain, any case)? nameOf(kind, id, fallback) gives the shown name of an
-- "item" or "quest" (the client's, in the player's language, or fallback). No text matches everything.
function ns.DJ_Matches(inst, text, nameOf)
	return Clean(text) == "" or ns.DJ_Hit(inst, text, nameOf) ~= nil
end

-- Before you go: your quests for the dungeon that you can take now and that start at a spot on the map, as
-- { { map, list = { quest, ... } } } by the zone (uiMapID) they start in, zones in the order their first quest comes.
-- ctx as for DJ_QuestState.
function ns.DJ_Prep(inst, ctx)
	local groups, byMap = {}, {}
	for _, entry in ipairs(ns.DJ_Quests(inst, ctx.side, ctx.class, false)) do
		local q = entry.quest
		if q.map and q.x and ns.DJ_QuestState(q, ctx) == "open" then
			local g = byMap[q.map]
			if not g then
				g = { map = q.map, list = {} }
				byMap[q.map] = g
				groups[#groups + 1] = g
			end
			g.list[#g.list + 1] = q
		end
	end
	return groups
end

-- The dungeon whose area (areaName(id): its name in the client's language) or own English name is zone, or nil.
function ns.DJ_FindByZone(list, zone, areaName)
	if not zone or zone == "" then
		return nil
	end
	for _, d in ipairs(list) do
		if (d.area and areaName(d.area) == zone) or d.name == zone then
			return d
		end
	end
	return nil
end

-- Every item the dungeon drops (bosses, then rares, then trash), each once.
function ns.DJ_Loot(inst)
	local list, seen = {}, {}
	local function Add(ids)
		for _, id in ipairs(ids) do
			if not seen[id] then
				seen[id] = true
				list[#list + 1] = id
			end
		end
	end
	for _, key in ipairs({ "bosses", "rares" }) do
		for _, wing in ipairs(inst.wings) do
			for _, boss in ipairs(wing[key]) do
				Add(boss.loot)
			end
		end
	end
	for _, wing in ipairs(inst.wings) do
		Add(wing.trash)
	end
	return list
end
