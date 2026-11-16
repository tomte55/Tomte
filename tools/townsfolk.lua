-- Builds Data/Forever/Townsfolk.lua: where World of Warcraft: Forever's town services are (mailboxes, auctioneers,
-- bankers, innkeepers, trainers, repair, stable and flight masters, battlemasters), for the Tomte map's town markers
-- (Modules/Map/Pins.lua). From QuestieDB's Forever data (github.com/Questie/QuestieDB, GPL-3.0; see its LICENSE.md):
-- only facts are taken, the NPCs' and objects' IDs, names, titles, service flags, factions and positions.
--
-- Fetch these files from one QuestieDB commit into one folder, keeping their paths, then, from the Tomte folder:
--     lua tools/townsfolk.lua <folder> <commit>
--   data/Forever/foreverNpcDB.lua, data/Forever/foreverObjectDB.lua
--   src/corrections/Forever/legacy/classicNPCFixes.lua, .../legacy/classicObjectFixes.lua
--   src/corrections/Forever/generated/foreverBaseNpc.lua, .../generated/foreverBaseObject.lua
--   src/corrections/Forever/foreverNPCFixes.lua, .../foreverObjectFixes.lua
--   src/corrections/enum/zones.lua, support/Forever/Zones/areaIdToUiMapId.lua
-- The corrections apply in that order over the raw tables, as QuestieDB's own generation does (each generated file's
-- header). They run in a sandbox where anything but the few tables they read is a stand-in.

local DIR, COMMIT = arg[1], arg[2]
assert(DIR and COMMIT, "usage: lua tools/townsfolk.lua <QuestieDB folder> <commit>")

local OUT = "Data/Forever/Townsfolk.lua"

-- npcFlags bits on Forever (QuestieDB src/corrections/enum/expansions.lua, Forever).
local FLAGS = {
	flightmaster = 8, trainer = 16, innkeeper = 128, banker = 256, battlemaster = 2048, auctioneer = 4096,
	stablemaster = 8192, repair = 16384,
}
-- The kinds written, in this order (the map's menu order is its own).
-- Flight masters aren't among them: the map reads those from the game (C_TaxiMap).
local KINDS = { "auctioneer", "banker", "battlemaster", "innkeeper", "mailbox", "class", "profession", "repair",
	"stablemaster" }

-- A trainer's title names what it teaches: "Warrior Trainer", "Pet Trainer", "Journeyman Blacksmith".
local CLASS_TITLES = {
	["Warrior Trainer"] = "WARRIOR", ["Paladin Trainer"] = "PALADIN", ["Hunter Trainer"] = "HUNTER",
	["Pet Trainer"] = "HUNTER", ["Rogue Trainer"] = "ROGUE", ["Priest Trainer"] = "PRIEST",
	["Shaman Trainer"] = "SHAMAN", ["Mage Trainer"] = "MAGE", ["Warlock Trainer"] = "WARLOCK",
	["Druid Trainer"] = "DRUID", ["Grand Master Rogue"] = "ROGUE", ["Master Mage"] = "MAGE", ["High Priest"] = "PRIEST",
}
local PROFESSION_WORDS = { "Alchemist", "Alchemy", "Blacksmith", "Cook", "Enchant", "Engineer", "First Aid",
	"Fisherman", "Fishing", "Herbalis", "Leatherwork", "Miner", "Mining", "Skinner", "Skinning", "Tailor",
	"Physician", "Surgeon", "Fisher", "Leathercraft", "Armorsmith", "Weaponsmith", "Armor Crafter", "Weapon Crafter",
	"Medic", "Butcher" }

-- Sandbox ---------------------------------------------------------------------------------------------------------------

-- A stand-in: indexing, calling or doing sums with it gives itself, so code the corrections run for other fields
-- (phases, waypoint presets) passes.
local stand = setmetatable({}, {})
do
	local mt = getmetatable(stand)
	local function self()
		return stand
	end
	mt.__index, mt.__call, mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__concat, mt.__unm = self, self, self, self,
		self, self, self, self
end

-- Keys that aren't in a table's enum (questStarts_add ...) become names of their own, so they can't clash.
local function Keys(t)
	return setmetatable(t, { __index = function(_, k)
		return "?" .. tostring(k)
	end })
end

local modules = {}
local function Module(name)
	modules[name] = modules[name] or {}
	return modules[name]
end
local QuestieDB = Module("QuestieDB")
local ZoneDB = Module("ZoneDB")
ZoneDB.private = {}
QuestieDB.npcFlags = setmetatable({ VENDOR = 4, QUEST_GIVER = 2, GOSSIP = 1, NONE = 0, SPIRIT_HEALER = 32,
	SPIRIT_GUIDE = 64, PETITIONER = 512, TABARD_DESIGNER = 1024, BARBER = 33554432, TRANSMOGRIFIER = 536870912,
	FLIGHT_MASTER = FLAGS.flightmaster, TRAINER = FLAGS.trainer, INNKEEPER = FLAGS.innkeeper, BANKER = FLAGS.banker,
	BATTLEMASTER = FLAGS.battlemaster, AUCTIONEER = FLAGS.auctioneer, STABLEMASTER = FLAGS.stablemaster,
	REPAIR = FLAGS.repair }, { __index = function(_, k)
	error("unknown npc flag " .. tostring(k))
end })
setmetatable(QuestieDB, { __index = function()
	return stand
end })
Module("Phasing").phases = stand

local Loader = {}
function Loader:ImportModule(name)
	return Module(name)
end
function Loader:CreateModule(name)
	return Module(name)
end

local env = setmetatable({ QuestieLoader = Loader }, { __index = function(_, k)
	if k == "math" or k == "string" or k == "table" or k == "pairs" or k == "ipairs" or k == "tostring"
		or k == "tonumber" or k == "type" or k == "select" or k == "next" or k == "unpack" then
		return _G[k]
	end
	return stand
end })

local function Run(path, ...)
	local f = assert(io.open(DIR .. "/" .. path, "rb"), "missing " .. path)
	local text = f:read("*a")
	f:close()
	local chunk = assert(load(text, "@" .. path, "t", env))
	return chunk(...)
end

-- The raw tables are strings ("return { ... }") set on QuestieDB.
local function Table(text)
	return assert(load(text, "=data", "t", {}))()
end

-- Reading -----------------------------------------------------------------------------------------------------------------

local enum = { Enum = {} }
Run("src/corrections/enum/zones.lua", nil, enum)
ZoneDB.zoneIDs = Keys(enum.Enum.zoneIDs)
Run("support/Forever/Zones/areaIdToUiMapId.lua")
local areaToMap = Table(ZoneDB.private.areaIdToUiMapId)
for area, map in pairs(Table(ZoneDB.private.areaIdToUiMapIdOverride)) do
	areaToMap[area] = map
end

Run("data/Forever/foreverNpcDB.lua")
Run("data/Forever/foreverObjectDB.lua")
local npcKeys, objectKeys = QuestieDB.npcKeys, QuestieDB.objectKeys
local npcs, objects = Table(QuestieDB.npcData), Table(QuestieDB.objectData)
Keys(npcKeys)
Keys(objectKeys)

local function Apply(db, fixes)
	for id, fields in pairs(fixes) do
		local entry = db[id]
		if not entry then
			entry = {}
			db[id] = entry
		end
		for k, v in pairs(fields) do
			if type(k) == "number" then
				entry[k] = v
			end
		end
	end
end

local function Fixes(path, module, db)
	Run(path)
	Apply(db, Module(module):Load())
end

Fixes("src/corrections/Forever/legacy/classicNPCFixes.lua", "QuestieNPCFixes", npcs)
Fixes("src/corrections/Forever/generated/foreverBaseNpc.lua", "ForeverBaseNpc", npcs)
Fixes("src/corrections/Forever/foreverNPCFixes.lua", "ForeverNpcFixes", npcs)
Fixes("src/corrections/Forever/legacy/classicObjectFixes.lua", "QuestieObjectFixes", objects)
Fixes("src/corrections/Forever/generated/foreverBaseObject.lua", "ForeverBaseObject", objects)
Fixes("src/corrections/Forever/foreverObjectFixes.lua", "ForeverObjectFixes", objects)

-- Sorting into kinds ----------------------------------------------------------------------------------------------------

local function Has(flags, bit)
	return flags and flags % (bit * 2) >= bit
end

local function IsProfession(title)
	for _, word in ipairs(PROFESSION_WORDS) do
		if title:find(word, 1, true) then
			return true
		end
	end
	return false
end

local out = {}
for _, kind in ipairs(KINDS) do
	out[kind] = {}
end

-- One row per spawn: { map, x, y, name, title, side, class }. Instance spawns (-1, -1) and zones without a map are left
-- out; so are the same NPC's spawns within a yard or so of each other.
local function Add(kind, spawns, name, title, side, class)
	for area, points in pairs(spawns) do
		local map = areaToMap[area]
		if map and map > 0 and type(points) == "table" then
			local seen = {}
			for _, p in ipairs(points) do
				local x, y = p[1], p[2]
				if type(x) == "number" and x >= 0 and y >= 0 then
					local key = ("%d,%d"):format(math.floor(x * 2 + 0.5), math.floor(y * 2 + 0.5))
					if not seen[key] then
						seen[key] = true
						local rows = out[kind]
						rows[#rows + 1] = { map, x, y, name, title, side, class }
					end
				end
			end
		end
	end
end

local skippedClassless = {}
for id, n in pairs(npcs) do
	local name, spawns, side, title, flags = n[npcKeys.name], n[npcKeys.spawns], n[npcKeys.friendlyToFaction],
		n[npcKeys.subName], n[npcKeys.npcFlags]
	if type(name) == "string" and type(spawns) == "table" and side and flags and flags > 0
		and not name:find("^%[DND%]") and not name:find("Only GM", 1, true) then
		if side ~= "A" and side ~= "H" then
			side = nil -- "AH": both
		end
		for _, kind in ipairs(KINDS) do
			local bit = FLAGS[kind]
			if bit and bit ~= FLAGS.trainer and Has(flags, bit) then
				Add(kind, spawns, name, title, side)
			end
		end
		if Has(flags, FLAGS.trainer) and title then
			local class = CLASS_TITLES[title]
			if class then
				Add("class", spawns, name, title, side, class)
			elseif IsProfession(title) then
				Add("profession", spawns, name, title, side)
			else
				skippedClassless[title] = (skippedClassless[title] or 0) + 1
			end
		end
	end
end

for id, o in pairs(objects) do
	local name, spawns = o[objectKeys.name], o[objectKeys.spawns]
	if name == "Mailbox" and type(spawns) == "table" then
		Add("mailbox", spawns, nil, nil, nil)
	end
end

-- Writing -----------------------------------------------------------------------------------------------------------------

local function Num(v)
	local s = ("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function Str(v)
	return v and ("%q"):format(v) or "nil"
end

local lines = {}
local function Line(s)
	lines[#lines + 1] = s
end

Line("local addonName, ns = ...")
Line("")
Line("-- Generated by tools/townsfolk.lua: don't edit. From QuestieDB's Forever data (github.com/Questie/QuestieDB,")
Line("-- commit " .. COMMIT .. "), GPL-3.0. townsfolk: [kind] = { { map (uiMapID), x, y (percent),")
Line("-- name (English, nil for a mailbox), title, side (\"A\", \"H\" or nil for both), class (class trainers' class token) } }.")
Line("-- Read by the Tomte map's town markers (Modules/Map/Pins.lua).")
Line("")
Line("ns.Content_Register(ns.CONTENT_FOREVER, \"townsfolk\", {")
for _, kind in ipairs(KINDS) do
	local rows = out[kind]
	table.sort(rows, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		elseif a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[3] < b[3]
	end)
	Line("\t" .. kind .. " = {")
	for _, r in ipairs(rows) do
		local parts = { tostring(r[1]), Num(r[2]), Num(r[3]), Str(r[4]), Str(r[5]), Str(r[6]), Str(r[7]) }
		while parts[#parts] == "nil" do
			parts[#parts] = nil
		end
		Line("\t\t{ " .. table.concat(parts, ", ") .. " },")
	end
	Line("\t},")
end
Line("})")

local f = assert(io.open(OUT, "wb"))
f:write(table.concat(lines, "\r\n"), "\r\n")
f:close()

for _, kind in ipairs(KINDS) do
	print(kind, #out[kind])
end
local titles = {}
for t, n in pairs(skippedClassless) do
	titles[#titles + 1] = t .. " (" .. n .. ")"
end
table.sort(titles)
print("trainers left out: " .. table.concat(titles, ", "))
