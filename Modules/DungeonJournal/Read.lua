local addonName, ns = ...

-- Dungeon journal: what the page reads from the game (names, your quest state, Gear Check's verdicts, wanted items,
-- the dungeon you're in, a dungeon's entrance) and the state its files share, through ns.DJKit. Rules in Data.lua;
-- the page is Page.lua and the files it loads before it.

local PRELOAD_BATCH = 20 -- items asked for per step while the dungeon list counts upgrades
local PRELOAD_STEP = 0.25 -- seconds between steps

local J = {}
ns.DJKit = J

-- What the page shows: inst (the dungeon, nil: the list), tab ("quests" | "bosses"), pick (the entry picked on the
-- left), mark (an item ID a search found: its tile is marked and scrolled to).
J.state = { tab = "quests" }

function J.DB()
	return ns.DJ_DB()
end

function J.List()
	return ns.Content_Get(ns.CONTENT_FOREVER, "dungeonJournal") or {}
end

-- Names -----------------------------------------------------------------------------------------------------------------

local waiting = {} -- item and quest IDs asked for, so each is asked once
local missing = {} -- item IDs the server says this client doesn't have (ITEM_DATA_LOAD_RESULT false): left out
J.missing = missing

function J.ItemName(id)
	local name = C_Item.GetItemNameByID(id)
	if not name and not waiting[id] then
		waiting[id] = true
		C_Item.RequestLoadItemDataByID(id)
	end
	return name
end

-- The quest's title in the client's language once the server sent it; fallback (the data's English name) until then.
function J.QuestName(id, fallback)
	local title = C_QuestLog.GetTitleForQuestID(id)
	if (not title or title == "") and not waiting["q" .. id] then
		waiting["q" .. id] = true
		C_QuestLog.RequestLoadQuestByID(id)
	end
	return (title and title ~= "") and title or fallback
end

function J.QuestTitle(q)
	return J.QuestName(q.id, q.name)
end

-- For search: only names the client already has. Asking the server here would ask for every item in every dungeon
-- (about 2000) the first time a search finds nothing.
function J.KnownName(kind, id, fallback)
	if kind == "item" then
		return C_Item.GetItemNameByID(id) or fallback
	end
	local title = C_QuestLog.GetTitleForQuestID(id)
	return (title and title ~= "") and title or fallback
end

function J.MapName(map)
	local info = map and C_Map.GetMapInfo(map)
	return info and info.name
end

-- You -------------------------------------------------------------------------------------------------------------------

function J.Context()
	return {
		level = UnitLevel("player"),
		side = UnitFactionGroup("player") == "Horde" and "H" or "A",
		class = select(2, UnitClass("player")),
		done = C_QuestLog.IsQuestFlaggedCompleted,
		active = function(id)
			return C_QuestLog.GetLogIndexForQuestID(id) ~= nil
		end,
	}
end

function J.SideName(side)
	return side == "H" and "Horde" or "Alliance"
end

J.STATE_TEXT = { done = "Done", active = "You have it", low = "Too low", other = "Not for you" }
J.STATE_COLOR = { done = "success", active = "accent", low = "warning", other = "textFaint", open = "textMuted" }

-- Gear Check's verdicts -------------------------------------------------------------------------------------------------

local gearCtx -- made once per layout; nil while Gear Check is off (no upgrade marks, nothing hidden)
local verdicts = {} -- [itemID] = verdict or false (none); cleared when your gear, level or skills change

function J.NewPass()
	gearCtx = ns.Gear_Context and ns.Gear_Context()
end

function J.ResetVerdicts()
	wipe(verdicts)
end

-- Gear Check's verdict on an item the client has loaded, else nil.
function J.Verdict(id)
	if not gearCtx then
		return nil
	end
	local v = verdicts[id]
	if v == nil then
		local link = select(2, C_Item.GetItemInfo(id))
		if not link then
			return nil
		end
		v = ns.Gear_Verdict(link, gearCtx) or false
		verdicts[id] = v
	end
	return v or nil
end

function J.IsUpgrade(id)
	local v = J.Verdict(id)
	return v ~= nil and ns.Gear_IsCleanUpgrade ~= nil and ns.Gear_IsCleanUpgrade(v)
end

function J.NotForYou(id)
	local v = J.Verdict(id)
	return v ~= nil and v.kind == "notForYou"
end

function J.Owned(id)
	return C_Item.GetItemCount(id, true) > 0
end

-- Upgrades in a dungeon -------------------------------------------------------------------------------------------------

local loot = {} -- [inst] = its item IDs (ns.DJ_Loot)
local queue, queued = {}, {}
local ticker

function J.Loot(inst)
	loot[inst] = loot[inst] or ns.DJ_Loot(inst)
	return loot[inst]
end

local function Step()
	for _ = 1, PRELOAD_BATCH do
		local id = table.remove(queue)
		if not id then
			ticker:Cancel()
			ticker = nil
			return
		end
		C_Item.RequestLoadItemDataByID(id)
	end
end

-- How many of the dungeon's drops are upgrades for you, and whether some are still loading (asked for a few at a
-- time: the count grows as they come in). nil while Gear Check is off.
function J.Upgrades(inst)
	if not gearCtx then
		return nil
	end
	local n, loading = 0, false
	for _, id in ipairs(J.Loot(inst)) do
		if not missing[id] then
			if C_Item.IsItemDataCachedByID(id) then
				if J.IsUpgrade(id) then
					n = n + 1
				end
			else
				loading = true
				if not queued[id] then
					queued[id] = true
					queue[#queue + 1] = id
				end
			end
		end
	end
	if #queue > 0 and not ticker then
		ticker = C_Timer.NewTicker(PRELOAD_STEP, Step)
	end
	return n, loading
end

-- The page closed: stop asking. Items not asked for yet are asked again next time.
function J.StopPreload()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	for _, id in ipairs(queue) do
		queued[id] = nil
	end
	wipe(queue)
end

-- Wanted items (per character) ------------------------------------------------------------------------------------------

local function Wanted()
	local db = J.DB()
	local guid = UnitGUID("player")
	db.chars[guid] = db.chars[guid] or { wanted = {} }
	return db.chars[guid].wanted
end

function J.IsWanted(id)
	return Wanted()[id] == true
end

-- Returns whether it's wanted now.
function J.ToggleWanted(id)
	local w = Wanted()
	w[id] = not w[id] or nil
	return w[id] == true
end

function J.WantedIn(ids)
	local w, n = Wanted(), 0
	for _, id in ipairs(ids) do
		if w[id] then
			n = n + 1
		end
	end
	return n
end

-- Where -----------------------------------------------------------------------------------------------------------------

-- The dungeon you're in, or nil.
function ns.DJ_Here()
	local inside, kind = IsInInstance()
	if not inside or kind ~= "party" then
		return nil
	end
	local name = GetInstanceInfo()
	return ns.DJ_FindByZone(J.List(), name, function(area)
		return C_Map.GetAreaInfo(area)
	end)
end

-- The dungeon's entrance as map, x, y (percent): from the data, else an entrance the game shows on a zone map for it
-- (only ones you've discovered). nil when neither knows.
function J.Entrance(inst)
	if inst.door then
		return inst.door.map, inst.door.x, inst.door.y
	end
	for _, continent in ipairs({ 1414, 1415 }) do -- Kalimdor, the Eastern Kingdoms
		for _, zone in ipairs(C_Map.GetMapChildrenInfo(continent, Enum.UIMapType.Zone) or {}) do
			for _, e in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(zone.mapID) or {}) do
				if e.journalInstanceID == inst.id and e.position then
					return zone.mapID, e.position.x * 100, e.position.y * 100
				end
			end
		end
	end
	return nil
end
