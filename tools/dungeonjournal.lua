-- Builds Data/Forever/DungeonJournal.lua: each World of Warcraft: Forever dungeon's quests, bosses and loot, for the
-- Dungeon journal (Modules/DungeonJournal). From AllTheThings' Forever database (github.com/ATTWoWAddon/AllTheThings,
-- .contrib/.db/forever/: "dungeons & raids" and .config/constants), MIT License. Only facts are taken: IDs, levels,
-- coordinates, which quest gives which item, which boss drops what, and the English names in its comments.
--
-- Fetch both folders at one commit into folders of their own, then, from the Tomte folder:
--     lua tools/dungeonjournal.lua <dungeons folder> <constants folder> <commit>
-- ATT's files are Lua. They run here in an empty sandbox: no io, os, load or debug, only stub constructors that
-- record what they're given, and a stand-in for any other name. Names live in ATT's comments
-- ("q(96395, {	-- An Ancient Grudge"), so a text pass first copies each into the table as _name.

local DUNGEONS_DIR, CONSTANTS_DIR, COMMIT = arg[1], arg[2], arg[3]
assert(DUNGEONS_DIR and CONSTANTS_DIR and COMMIT, "usage: lua tools/dungeonjournal.lua <dungeons folder> <constants folder> <commit>")

local OUT = "Data/Forever/DungeonJournal.lua"
local DUNGEON_LEVELS = "Data/Forever/Dungeons.lua" -- Classic's level ranges, for a dungeon whose ATT file has no max

-- Raids, and dungeons not open yet: left out (instance IDs). Molten Core, Blackwing Lair, Ahn'Qiraj and Naxxramas use
-- inst() rather than instanceroot() and are never read.
local SKIP = { [760] = true, [78789] = true, [78790] = true }

-- Kill order where ATT's file order isn't (creature IDs; bosses not listed keep their place after these).
local ORDER = {
	[63] = { 644, 642, 643, 1763, 646, 647, 645, 639 }, -- Deadmines: Cookie on the ship before VanCleef
}

-- Headings at a dungeon's top level are its wings, except these, which only group bosses (ATT's readable names).
local BOSS_GROUPS = { ["Atal'ai Defenders"] = true }

-- Dungeons.lua names some dungeons differently (for its max level): ATT's name, lowercase without "The ", to its.
local LEVEL_NAMES = { ["temple of atal'hakkar"] = "sunken temple", ["blackrock spire"] = "upper blackrock spire" }

local ALLIANCE_RACES = { HUMAN = true, DWARF = true, NIGHTELF = true, GNOME = true, SKYBORNE_ALLIANCE = true }
local HORDE_RACES = { ORC = true, UNDEAD = true, TAUREN = true, TROLL = true, SKYBORNE_HORDE = true }
local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
	MAGE = true, WARLOCK = true, DRUID = true }

-- Files ---------------------------------------------------------------------------------------------------------------

local function ReadFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local function ListLua(dir)
	local files = {}
	local p = io.popen('ls -1 "' .. dir .. '"')
	for name in p:lines() do
		if name:match("%.lua$") then
			files[#files + 1] = name
		end
	end
	p:close()
	table.sort(files)
	return files
end

-- Names out of comments -----------------------------------------------------------------------------------------------

local function CleanName(s)
	s = s:gsub("%s*<.->", "") -- "Edwin VanCleef <Defias Kingpin>"
	s = s:gsub("%s*%[.*$", "") -- "Rhahk'Zor's Hammer [Classic] / Foe Reaper [TBC+]"
	s = s:gsub("%s*%(%u[%u%s]*!%)", "") -- "(PET!)", "(RECIPE!)", "(QS!)"
	s = s:gsub("^\"(.*)\"$", "%1")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Long(s)
	return "[==[" .. s .. "]==]"
end

local function InjectNames(text)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\r?\n") do
		if not line:match("^%s*%-%-") then
			-- X(id, {	-- Name   /   header(HEADERS.Item, id, {	-- Name
			local head, comment = line:match("^(%s*[%w_]+%(.-{)%s*%-%-%s*(.-)%s*$")
			if head then
				line = head .. " _name = " .. Long(CleanName(comment)) .. ","
			else
				-- i(id),	-- Name
				local indent, fn, id, tail, c2 = line:match("^(%s*)([%w_]+)%(%s*(%d+)%s*%)(%s*[,;]?)%s*%-%-%s*(.-)%s*$")
				if indent then
					line = indent .. fn .. "(" .. id .. ", { _name = " .. Long(CleanName(c2)) .. " })" .. tail
				else
					-- qg = 265002,	-- Ghostly Attendant
					local i3, key, num, c3 = line:match("^(%s*)([%a_][%w_]*)%s*=%s*(%d+)%s*,%s*%-%-%s*(.-)%s*$")
					if i3 then
						line = i3 .. key .. " = " .. num .. ", " .. key .. "_name = " .. Long(CleanName(c3)) .. ","
					end
				end
			end
		end
		out[#out + 1] = line
	end
	return table.concat(out, "\n")
end

-- The sandbox ---------------------------------------------------------------------------------------------------------

local SymMT = {}
local function Sym(name)
	return setmetatable({ __sym = name }, SymMT)
end
local function IsSym(v)
	return type(v) == "table" and getmetatable(v) == SymMT
end
SymMT.__index = function(s, k)
	return Sym(rawget(s, "__sym") .. "." .. tostring(k))
end
SymMT.__newindex = function() end
SymMT.__call = function(s)
	return Sym(rawget(s, "__sym") .. "()")
end
SymMT.__concat = function(a, b)
	return Sym(tostring(IsSym(a) and rawget(a, "__sym") or a) .. tostring(IsSym(b) and rawget(b, "__sym") or b))
end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow" }) do
	SymMT[op] = function()
		return Sym("?")
	end
end

local instances = {} -- every instanceroot() call, in file order

local function IsTable(v)
	return type(v) == "table" and not IsSym(v)
end

-- Any constructor: kind, the first argument as id, the last plain table as its fields; a table with an array part
-- has those as its groups.
local function Node(kind)
	return function(a, b, c)
		local t = IsTable(c) and c or IsTable(b) and b or {}
		local id = a
		if kind == "header" then
			id = b
		end
		local groups = t.groups
		if not groups and #t > 0 then
			groups = {}
			for i = 1, #t do
				groups[i] = t[i]
			end
		end
		return { kind = kind, id = id, t = t, groups = groups or {} }
	end
end

local function NewEnv()
	local env = {
		setmetatable = setmetatable, getmetatable = getmetatable, pairs = pairs, ipairs = ipairs, type = type,
		tostring = tostring, tonumber = tonumber, print = function() end, error = error, select = select,
		table = { insert = table.insert, remove = table.remove, concat = table.concat, sort = table.sort },
		string = string, math = math, unpack = table.unpack or unpack, rawget = rawget, rawset = rawset,
	}
	env._G = env
	env.MAP = {} -- filled by maps.lua
	for _, kind in ipairs({ "q", "i", "n", "e", "o", "objective", "cl", "r", "prof", "m", "ach", "faction", "recipe",
		"mount", "ig", "container", "filter", "inst", "root", "header", "achWithRep", "addRepInfo", "pet", "spell",
		"title", "heir", "toy", "currency", "race", "map", "npc", "item", "quest", "object" }) do
		env[kind] = Node(kind)
	end
	env.createHeader = function(t)
		return { kind = "createHeader", name = t.readable, t = t, groups = {} }
	end
	env.instanceroot = function(id, t)
		local node = Node("instanceroot")(id, t)
		instances[#instances + 1] = node
		return node
	end
	return setmetatable(env, { __index = function(_, k)
		return Sym(k)
	end })
end

local function Run(env, path, text)
	local chunk, err
	if setfenv then
		chunk, err = loadstring(text, "@" .. path)
		if chunk then
			setfenv(chunk, env)
		end
	else
		chunk, err = load(text, "@" .. path, "t", env)
	end
	assert(chunk, err)
	local ok, runErr = pcall(chunk)
	if not ok then
		io.stderr:write("skipped the rest of " .. path .. ": " .. tostring(runErr) .. "\n")
	end
end

-- Shape ---------------------------------------------------------------------------------------------------------------

local function Num(v)
	return type(v) == "number" and v or nil
end

local function SymName(v)
	return IsSym(v) and rawget(v, "__sym") or nil
end

local function Side(races)
	local name = SymName(races)
	if name then
		if name:find("ALLIANCE") then
			return "A"
		elseif name:find("HORDE") then
			return "H"
		end
		return nil
	end
	if not IsTable(races) then
		return nil
	end
	local a, h = false, false
	for _, r in ipairs(races) do
		local rn = SymName(r) or ""
		a = a or ALLIANCE_RACES[rn] or rn:find("ALLIANCE") ~= nil
		h = h or HORDE_RACES[rn] or rn:find("HORDE") ~= nil
	end
	if a ~= h then
		return a and "A" or "H"
	end
	return nil
end

local function Classes(list)
	if not IsTable(list) then
		return nil
	end
	local out = {}
	for _, c in ipairs(list) do
		local cn = SymName(c)
		if cn and CLASSES[cn] then
			out[#out + 1] = cn
		end
	end
	return #out > 0 and out or nil
end

-- Every item below a node, file order, once each (quest givers' items too: a boss's loot is all of it).
local function Items(node, out, seen)
	out, seen = out or {}, seen or {}
	for _, g in ipairs(node.groups) do
		if IsTable(g) and g.kind then
			if g.kind == "i" and Num(g.id) and not seen[g.id] then
				seen[g.id] = true
				out[#out + 1] = g.id
			end
			if g.kind ~= "q" then
				Items(g, out, seen)
			end
		end
	end
	return out, seen
end

local function Quest(node)
	local t = node.t
	local q = { id = node.id, name = t._name or ("Quest " .. node.id), lvl = Num(t.lvl), side = Side(t.races),
		classes = Classes(t.classes) }
	if Num(t.qg) then
		q.giver, q.giverName = t.qg, t.qg_name
	elseif IsTable(t.qgs) and Num(t.qgs[1]) then
		q.giver = t.qgs[1]
	end
	if IsTable(t.coord) and Num(t.coord[1]) and Num(t.coord[3]) then
		q.x, q.y, q.map = t.coord[1], t.coord[2], t.coord[3]
	end
	if Num(t.sourceQuest) then
		q.after = { t.sourceQuest }
	elseif IsTable(t.sourceQuests) then
		q.after = {}
		for _, id in ipairs(t.sourceQuests) do
			if Num(id) then
				q.after[#q.after + 1] = id
			end
		end
	end
	q.item = Num(t.qs)
	local goals, rewards = {}, {}
	for _, g in ipairs(node.groups) do
		if IsTable(g) and g.kind == "objective" and g.t._name then
			goals[#goals + 1] = g.t._name
		elseif IsTable(g) and g.kind == "i" and Num(g.id) then
			rewards[#rewards + 1] = g.id
		end
	end
	q.goals = #goals > 0 and goals or nil
	q.rewards = #rewards > 0 and rewards or nil
	return q
end

local function IsRare(node)
	local d = node.t.description
	return type(d) == "string" and d:find("Rare Creature") ~= nil
end

local function Boss(node)
	local npc = Num(node.t.creatureID) or (IsTable(node.t.creatureIDs) and Num(node.t.creatureIDs[1]))
	if node.kind == "n" then
		npc = node.id
	end
	return { name = node.t._name or "?", npc = npc, loot = (Items(node)) }
end

local function NewWing(name, lvl)
	return { name = name, min = lvl, quests = {}, bosses = {}, rares = {}, trash = {} }
end

local function HeaderOf(node)
	if node.kind == "n" and IsTable(node.id) and node.id.kind == "createHeader" then
		return node.id
	end
	if node.kind == "m" and IsTable(node.t.headerID) and node.t.headerID.kind == "createHeader" then
		return node.t.headerID
	end
end

local Fill

-- One group at instance or wing level, into wing (wings: where new wings go).
local function Place(g, wing, wings)
	if not (IsTable(g) and g.kind) then
		return
	end
	local header = HeaderOf(g)
	local sym = SymName(g.id)
	if header and wings and not BOSS_GROUPS[header.name or ""] then
		local w = NewWing(header.name or g.t._name, Num(g.t.lvl) or wing.min)
		wings[#wings + 1] = w
		Fill(g, w, nil)
	elseif header or (g.kind == "m") then
		Fill(g, wing, wings) -- a group of bosses under a heading (Atal'ai Defenders): its bosses count here
	elseif sym == "QUESTS" then
		for _, qn in ipairs(g.groups) do
			if IsTable(qn) and qn.kind == "q" and Num(qn.id) then
				wing.quests[#wing.quests + 1] = Quest(qn)
			end
		end
	elseif sym == "RARES" then
		for _, rn in ipairs(g.groups) do
			if IsTable(rn) and rn.kind == "n" and Num(rn.id) then
				wing.rares[#wing.rares + 1] = Boss(rn)
			end
		end
	elseif sym == "ZONE_DROPS" then
		local items = Items(g)
		for _, id in ipairs(items) do
			wing.trash[#wing.trash + 1] = id
		end
	elseif g.kind == "e" then
		wing.bosses[#wing.bosses + 1] = Boss(g)
	elseif g.kind == "n" and Num(g.id) then
		if IsRare(g) then
			wing.rares[#wing.rares + 1] = Boss(g)
		else
			wing.bosses[#wing.bosses + 1] = Boss(g)
		end
	end
end

Fill = function(node, wing, wings)
	for _, g in ipairs(node.groups) do
		Place(g, wing, wings)
	end
end

local function Reorder(bosses, order)
	if not order then
		return bosses
	end
	local rank = {}
	for i, npc in ipairs(order) do
		rank[npc] = i
	end
	local indexed = {}
	for i, b in ipairs(bosses) do
		indexed[i] = { b = b, k = rank[b.npc] or (#order + i) }
	end
	table.sort(indexed, function(x, y)
		return x.k < y.k
	end)
	for i, v in ipairs(indexed) do
		bosses[i] = v.b
	end
	return bosses
end

-- "Blizzard lists it for levels 48-53." in the comments just after instanceroot(...)
local function CommentLevels(text, id)
	local at = text:find("instanceroot%(" .. id .. "%D")
	if not at then
		return nil
	end
	local a, b = text:sub(at, at + 400):match("levels (%d+)%-(%d+)")
	return tonumber(a), tonumber(b)
end

local function NormName(s)
	return (s:lower():gsub("^the ", ""))
end

local function ClassicMax()
	local max = {}
	for name, hi in ReadFile(DUNGEON_LEVELS):gmatch('name = "([^"]+)", min = %d+, max = (%d+)') do
		max[NormName(name)] = tonumber(hi)
	end
	return max
end

-- Writing -------------------------------------------------------------------------------------------------------------

local function Str(s)
	return string.format("%q", s):gsub("\\\n", "\\n")
end

local function List(t)
	local parts = {}
	for i, v in ipairs(t) do
		parts[i] = type(v) == "string" and Str(v) or tostring(v)
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function Fields(pairs_)
	local parts = {}
	for _, kv in ipairs(pairs_) do
		local k, v = kv[1], kv[2]
		if v ~= nil then
			local s
			if type(v) == "table" then
				s = List(v)
			elseif type(v) == "string" then
				s = Str(v)
			else
				s = tostring(v)
			end
			parts[#parts + 1] = k .. " = " .. s
		end
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function WriteInstance(lines, inst)
	local door = inst.door and (" door = { map = %d, x = %s, y = %s },"):format(inst.door[3], inst.door[1], inst.door[2])
		or ""
	lines[#lines + 1] = "\t{ " .. ("id = %d, name = %s, area = %s, min = %s, max = %s,%s wings = {"):format(inst.id,
		Str(inst.name), tostring(inst.area), tostring(inst.min), tostring(inst.max), door)
	for _, w in ipairs(inst.wings) do
		lines[#lines + 1] = "\t\t{ " .. (w.name and ("name = " .. Str(w.name) .. ", ") or "") .. "min = "
			.. tostring(w.min) .. ","
		lines[#lines + 1] = "\t\t\tquests = {"
		for _, q in ipairs(w.quests) do
			lines[#lines + 1] = "\t\t\t\t" .. Fields({ { "id", q.id }, { "name", q.name }, { "lvl", q.lvl },
				{ "side", q.side }, { "classes", q.classes }, { "giver", q.giver }, { "giverName", q.giverName },
				{ "map", q.map }, { "x", q.x }, { "y", q.y }, { "after", q.after }, { "item", q.item },
				{ "goals", q.goals }, { "rewards", q.rewards } }) .. ","
		end
		lines[#lines + 1] = "\t\t\t},"
		for _, key in ipairs({ "bosses", "rares" }) do
			lines[#lines + 1] = "\t\t\t" .. key .. " = {"
			for _, b in ipairs(w[key]) do
				lines[#lines + 1] = "\t\t\t\t" .. Fields({ { "name", b.name }, { "npc", b.npc }, { "loot", b.loot } }) .. ","
			end
			lines[#lines + 1] = "\t\t\t},"
		end
		lines[#lines + 1] = "\t\t\ttrash = " .. List(w.trash) .. ","
		lines[#lines + 1] = "\t\t},"
	end
	lines[#lines + 1] = "\t} },"
end

-- Main ----------------------------------------------------------------------------------------------------------------

local env = NewEnv()
Run(env, "maps.lua", ReadFile(CONSTANTS_DIR .. "/maps.lua"))
Run(env, "races.lua", ReadFile(CONSTANTS_DIR .. "/races.lua"))

local texts = {}
for _, file in ipairs(ListLua(DUNGEONS_DIR)) do
	if not file:match("^%d") then -- "0.5 - dungeon sets", "1.0 - molten core": sets, world bosses, raids
		local text = ReadFile(DUNGEONS_DIR .. "/" .. file)
		local before = #instances
		Run(env, file, InjectNames(text))
		for i = before + 1, #instances do
			texts[instances[i]] = text
		end
	end
end

local classicMax = ClassicMax()
local result = {}
for _, node in ipairs(instances) do
	local id = node.id
	if Num(id) and not SKIP[id] then
		local text = texts[node]
		local min = Num(node.t.lvl)
		local cMin, cMax = CommentLevels(text, id)
		local name = node.t._name or ("Instance " .. id)
		local main = NewWing(nil, min or cMin)
		local wings = { main }
		Fill(node, main, wings)
		local any = false
		for _, w in ipairs(wings) do
			Reorder(w.bosses, ORDER[id])
			if #w.quests + #w.bosses > 0 then
				any = true
			end
		end
		-- The instance's own groups only make a wing of their own when they hold something.
		if #main.quests + #main.bosses + #main.rares + #main.trash == 0 and #wings > 1 then
			table.remove(wings, 1)
		end
		if any then
			local lo = min or cMin
			for _, w in ipairs(wings) do
				lo = (w.min and (not lo or w.min < lo)) and w.min or lo
			end
			-- The entrance: coord, or the first of coords (a dungeon with several doors). 50, 50 is ATT's stand-in for
			-- "somewhere in this city", not a spot: left out.
			local c = node.t.coord or (IsTable(node.t.coords) and node.t.coords[1])
			local door = IsTable(c) and Num(c[1]) and Num(c[2]) and Num(c[3]) and not (c[1] == 50 and c[2] == 50) and c
				or nil
			result[#result + 1] = { id = id, name = name, area = Num(node.t.zoneTextAreaID), min = lo,
				max = cMax or classicMax[LEVEL_NAMES[NormName(name)] or NormName(name)], door = door, wings = wings }
		end
	end
end
table.sort(result, function(a, b)
	if (a.min or 99) ~= (b.min or 99) then -- no known level: last
		return (a.min or 99) < (b.min or 99)
	end
	return a.name < b.name
end)

local lines = {
	"local addonName, ns = ...",
	"",
	"-- Generated by tools/dungeonjournal.lua: don't edit. From AllTheThings' Forever database (github.com/ATTWoWAddon/AllTheThings,",
	"-- .contrib/.db/forever/, commit " .. COMMIT .. "), MIT License, Copyright (c) the AllTheThings team.",
	"-- dungeonJournal: the Forever dungeons, by lowest level: { id (instance), name (English), area (area ID), min, max (levels;",
	"-- max can be nil), door ({ map (uiMapID), x, y (percent) }: the entrance, or nil), wings }. A wing: { name (nil: the dungeon itself), min, quests, bosses, rares, trash (item IDs) }.",
	"-- A quest: { id, name (English), lvl (level to take it), side (\"A\", \"H\" or nil for both), classes (class tokens or",
	"-- nil), giver (NPC ID), giverName, map (uiMapID), x, y (percent), after (quest IDs before it), item (an item that",
	"-- starts it), goals (English objective lines), rewards (item IDs) }. A boss or rare: { name, npc, loot (item IDs) }.",
	"-- Read by the Dungeon journal (Modules/DungeonJournal).",
	"",
	'ns.Content_Register(ns.CONTENT_FOREVER, "dungeonJournal", {',
}
for _, inst in ipairs(result) do
	WriteInstance(lines, inst)
end
lines[#lines + 1] = "})"
lines[#lines + 1] = ""

local f = assert(io.open(OUT, "wb"))
f:write(table.concat(lines, "\r\n"))
f:close()

for _, inst in ipairs(result) do
	local q, b = 0, 0
	local names = {}
	for _, w in ipairs(inst.wings) do
		q, b = q + #w.quests, b + #w.bosses
		names[#names + 1] = (w.name or "-") .. ":" .. #w.bosses
	end
	print(("%-28s %5d  %s-%s  quests %2d  bosses %2d  [%s]"):format(inst.name, inst.id, tostring(inst.min),
		tostring(inst.max), q, b, table.concat(names, " ")))
end
