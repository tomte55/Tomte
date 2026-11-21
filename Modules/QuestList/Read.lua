local addonName, ns = ...

-- Quest list: reads the game into plain tables for Data.lua and List.lua. The quest log, positions and quest spots come
-- from Leveling's readers (Modules/Leveling/Read.lua, loaded before this file on Forever); this file adds what only the
-- list needs: each quest's objectives, the zone you're in, the quest items in your bags (the quest item button) and
-- the flight masters you know (the flight hint).

local MAP_ZONE = 3 -- Enum.UIMapType.Zone: caves, buildings and sub-zones (4 and up) sit under a zone map
local LAST_CARRIED_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear

-- A quest's objectives as Data.lua reads them: { { label, have, need, finished } }, in the game's order.
function ns.QuestListRead_Objectives(questID)
	local list = {}
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		if o.text and o.text ~= "" then
			list[#list + 1] = ns.QuestList_Objective(o)
		end
	end
	return list
end

-- The zone you're in, by name and map: the zone-level map above a cave, building or sub-zone map you may be on, as
-- quest spots name their zone. Used to put your zone first and to name stops in it by direction.
-- Kept per map you stand on: maps don't move in the tree, and the list asks several times per update and tick.
local zoneOf = {} -- [best map ID] = { name, zone map ID } (false fields when there's no zone above it)

function ns.QuestListRead_Zone()
	local best = C_Map.GetBestMapForUnit("player")
	if not best or ns.IsSecret(best) then
		return nil, nil
	end
	local known = zoneOf[best]
	if not known then
		local mapID, seen = best, {}
		local info = C_Map.GetMapInfo(mapID)
		while info and info.mapType > MAP_ZONE and info.parentMapID and info.parentMapID > 0 and not seen[mapID] do
			seen[mapID] = true
			mapID = info.parentMapID
			info = C_Map.GetMapInfo(mapID)
		end
		known = { info and info.name or false, info and mapID or false }
		zoneOf[best] = known
	end
	return known[1] or nil, known[2] or nil
end

-- Which way east and north run in world coordinates on mapID, as unit vectors: { ex, ey, nx, ny }, or nil where the map
-- has no world position. Measured from the map itself (its x runs east, its y south), so it holds whatever way the
-- client's world axes turn.
function ns.QuestListRead_Axes(mapID)
	local function W(x, y)
		local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
		if pos then
			return pos:GetXY()
		end
	end
	local cx, cy = W(0.5, 0.5)
	local ex, ey = W(0.6, 0.5)
	local sx, sy = W(0.5, 0.6)
	if not (cx and ex and sx) then
		return nil
	end
	ex, ey = ex - cx, ey - cy
	local nx, ny = cx - sx, cy - sy
	local el, nl = math.sqrt(ex * ex + ey * ey), math.sqrt(nx * nx + ny * ny)
	if el == 0 or nl == 0 then
		return nil
	end
	return { ex = ex / el, ey = ey / el, nx = nx / nl, ny = ny / nl }
end

-- The dungeon or raid you're in, by name (as the quest log heads its quests), or nil outside one.
function ns.QuestListRead_Instance()
	local name, kind = GetInstanceInfo()
	if kind == "party" or kind == "raid" then
		return name
	end
	return nil
end

-- The usable items in your bags that questItems (Forever's quest item data) ties to a quest, for QuestList_BagItems:
-- { itemID, ... } in bag order, each once, and [itemID] = how many you carry. Usable means it has a "Use:" spell; items
-- without one never get one (Value's scrolls and essences), so nil is final.
function ns.QuestListRead_CarriedQuestItems(questItems)
	local list, counts = {}, {}
	for bag = 0, LAST_CARRIED_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			-- The slot info table only for a quest item's slot: one per slot made 40 KB a bag update.
			local itemID = ns.BagSlotItemID(bag, slot)
			if itemID and questItems[itemID] then
				if not counts[itemID] and C_Item.GetItemSpell(itemID) then
					list[#list + 1] = itemID
					counts[itemID] = 0
				end
				if counts[itemID] then
					local info = C_Container.GetContainerItemInfo(bag, slot)
					counts[itemID] = counts[itemID] + (info and info.stackCount or 1)
				end
			end
		end
	end
	return list, counts
end

-- Flight masters ------------------------------------------------------------------------------------------------------

local MAP_CONTINENT = 2 -- Enum.UIMapType.Continent
local FACTION = { Neutral = 0, Horde = 1, Alliance = 2 } -- Enum.FlightPathFaction
local RUN_SPEED = 7 -- yards per second on foot (BASE_MOVEMENT_SPEED)
local MOUNT_SPEED = RUN_SPEED * 1.6 -- the first riding skill's 60%
-- A taxi's yards per second, about: its paths are drawn in straight lines in Data.lua's estimate, which allows for bends.
local FLIGHT_SPEED = 30

local masters, mastersMap -- the flight masters you know on mastersMap's continent, as world yards

local function Continent(mapID)
	local seen = {}
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType > MAP_CONTINENT and info.parentMapID and info.parentMapID > 0 and not seen[mapID] do
		seen[mapID] = true
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	return info and info.mapType == MAP_CONTINENT and mapID or nil
end

-- The open flight map's flight masters you know: the one you're at and those you can fly to, { [name] = true }, through
-- the taxi window's API as Modules/Map/Flights.lua reads it. Away from a flight map nothing says which you know: on
-- Forever every flight master comes back without isUndiscovered, unused ones ("zzOLD...") too (measured 2026-11-19).
local LEARNED = { CURRENT = true, REACHABLE = true }

function ns.QuestListRead_TaxiLearned()
	local names = {}
	for slot = 1, NumTaxiNodes() or 0 do
		local name = TaxiNodeName(slot)
		if name and LEARNED[TaxiNodeGetType(slot) or ""] then
			names[name] = true
		end
	end
	return names
end

-- The flight masters you know (known: { [name] = true }, from QuestListRead_TaxiLearned) and your faction may use on
-- the continent of mapID: { { x, y, continent, name, short, mapID, mapX, mapY } }, world yards and the spot on the
-- continent map for a map pin. Kept until you leave the continent or learn more (QuestListRead_ForgetFlightMasters).
function ns.QuestListRead_FlightMasters(mapID, known)
	local continent = Continent(mapID)
	if not continent then
		return {}
	end
	if masters and mastersMap == continent then
		return masters
	end
	masters, mastersMap = {}, continent
	local mine = FACTION[UnitFactionGroup("player")]
	for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(continent) or {}) do
		local pos = node.position
		local x, y = pos and pos.x, pos and pos.y
		local usable = not node.faction or node.faction == FACTION.Neutral or node.faction == mine
		if x and y and usable and not node.isUndiscovered and node.name and known[node.name] then
			local world, at = C_Map.GetWorldPosFromMapPos(continent, CreateVector2D(x, y))
			if world and at then
				local wx, wy = at:GetXY()
				-- short: the name without its zone ("Camp Taurajo, The Barrens"), for the list's narrow line.
				masters[#masters + 1] = { x = wx, y = wy, continent = world, name = node.name,
					short = node.name and node.name:match("^([^,]+)") or "?", mapID = continent, mapX = x, mapY = y }
			end
		end
	end
	return masters
end

function ns.QuestListRead_ForgetFlightMasters()
	masters, mastersMap = nil, nil
end

local fastestMount = 0 -- the fastest you've ridden this session (an epic mount), yards per second

-- Yards per second on the ground (running, or riding once you have a mount, as fast as you've ridden this session)
-- and on a flight.
function ns.QuestListRead_Speeds()
	if IsMounted() and not UnitOnTaxi("player") then
		local now = GetUnitSpeed("player")
		if now and not ns.IsSecret(now) and now > fastestMount then
			fastestMount = now
		end
	end
	local ground = ns.LevelingRead_Mounts() > 0 and math.max(MOUNT_SPEED, fastestMount) or RUN_SPEED
	return ground, FLIGHT_SPEED
end

-- In a dungeon, raid or battleground (the "hide in dungeons and raids" setting).
function ns.QuestListRead_InInstance()
	local inInstance, kind = IsInInstance()
	return inInstance and kind ~= "none"
end
