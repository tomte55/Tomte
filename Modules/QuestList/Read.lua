local addonName, ns = ...

-- Quest list: reads the game into plain tables for Data.lua and List.lua. The quest log, positions and quest spots come
-- from Leveling's readers (Modules/Leveling/Read.lua, loaded before this file on Forever); this file adds what only the
-- list needs: each quest's objectives and the zone you're in.

local MAP_ZONE = 3 -- Enum.UIMapType.Zone: caves, buildings and sub-zones (4 and up) sit under a zone map

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
function ns.QuestListRead_Zone()
	local mapID, seen = C_Map.GetBestMapForUnit("player"), {}
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType > MAP_ZONE and info.parentMapID and info.parentMapID > 0 and not seen[mapID] do
		seen[mapID] = true
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	return info and info.name or nil, info and mapID or nil
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

-- In a dungeon, raid or battleground (the "hide in dungeons and raids" setting).
function ns.QuestListRead_InInstance()
	local inInstance, kind = IsInInstance()
	return inInstance and kind ~= "none"
end
