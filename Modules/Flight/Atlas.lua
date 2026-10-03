local addonName, ns = ...

-- Which flight masters exist where: every zone with flight masters for the player's faction (plus neutral),
-- grouped by continent. The zone list is built once per session on first use; the flight masters and their
-- discovery state are read again on every build (they change as the character plays).

local COSMIC_MAP = 946

local zones -- { mapID, name, depth, continentID, continentName }, deepest maps first

local function BuildZones()
	zones = {}
	for _, info in ipairs(C_Map.GetMapChildrenInfo(COSMIC_MAP, Enum.UIMapType.Zone, true) or {}) do
		local depth, top, continent = 0, info, nil
		local parentID = info.parentMapID
		while parentID and parentID ~= 0 do
			local parent = C_Map.GetMapInfo(parentID)
			if not parent then
				break
			end
			depth = depth + 1
			if parent.mapType == Enum.UIMapType.Continent then
				continent = continent or parent -- the nearest one
			end
			if parent.mapType > Enum.UIMapType.World then
				top = parent
			end
			parentID = parent.parentMapID
		end
		continent = continent or top
		zones[#zones + 1] = {
			mapID = info.mapID,
			name = info.name,
			depth = depth,
			continentID = continent.mapID,
			continentName = continent.name,
		}
	end
	-- Deeper maps claim first: a city's flight master belongs to the city, not to the zone around it.
	table.sort(zones, function(a, b)
		if a.depth ~= b.depth then
			return a.depth > b.depth
		end
		return a.mapID < b.mapID
	end)
end

local function ForPlayer(info, faction)
	if info.faction == Enum.FlightPathFaction.Horde then
		return faction == "Horde"
	elseif info.faction == Enum.FlightPathFaction.Alliance then
		return faction == "Alliance"
	end
	return true
end

local function Node(info)
	return { nodeID = info.nodeID, name = info.name, undiscovered = info.isUndiscovered }
end

-- { continents = { { mapID, name, zones = { { mapID, name, nodes = { { nodeID, name, undiscovered } } } } } } },
-- continents in map ID order (roughly expansion order). Each flight master is in one zone only.
function ns.Atlas_Build()
	if not zones then
		BuildZones()
	end
	local faction = UnitFactionGroup("player")
	local claimed, byContinent, list = {}, {}, {}
	for _, zone in ipairs(zones) do
		if C_TaxiMap.ShouldMapShowTaxiNodes(zone.mapID) then
			local nodes = {}
			for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(zone.mapID) or {}) do
				if not claimed[info.nodeID] and ForPlayer(info, faction) then
					claimed[info.nodeID] = true
					nodes[#nodes + 1] = Node(info)
				end
			end
			if #nodes > 0 then
				local c = byContinent[zone.continentID]
				if not c then
					c = { mapID = zone.continentID, name = zone.continentName, zones = {} }
					byContinent[zone.continentID] = c
					list[#list + 1] = c
				end
				c.zones[#c.zones + 1] = { mapID = zone.mapID, name = zone.name, nodes = nodes }
			end
		end
	end
	table.sort(list, function(a, b)
		return a.mapID < b.mapID
	end)
	return { continents = list }
end

-- Flight masters for the player on one map (any map type), each once.
function ns.Atlas_MapNodes(mapID)
	local faction = UnitFactionGroup("player")
	local nodes, seen = {}, {}
	for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
		if not seen[info.nodeID] and ForPlayer(info, faction) then
			seen[info.nodeID] = true
			nodes[#nodes + 1] = Node(info)
		end
	end
	return nodes
end

-- The zone the player is in (going up from a dungeon or micro map), or nil.
function ns.Atlas_PlayerZone()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID ~= 0 do
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	if info and info.mapType == Enum.UIMapType.Zone then
		return info
	end
	return nil
end
