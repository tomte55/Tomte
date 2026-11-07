local addonName, ns = ...

-- Which flight masters exist where: every zone with flight masters for the player's faction (plus neutral),
-- grouped by continent. The zone list is built once per session on first use; the flight masters and their
-- discovery state are read again on every build (they change as the character plays).

local COSMIC_MAP = 946

local zones -- { mapID, name, depth, continentID, continentName }, deepest maps first

-- The top of the map tree: retail's cosmic map, or (on World of Warcraft: Forever, whose world map starts at Azeroth
-- and has no cosmic map) the highest map above where the player stands.
local function RootMaps()
	local children = C_Map.GetMapChildrenInfo(COSMIC_MAP, Enum.UIMapType.Zone, true)
	if children and #children > 0 then
		return children
	end
	local top = C_Map.GetBestMapForUnit("player")
	local info = top and C_Map.GetMapInfo(top)
	while info and info.parentMapID and info.parentMapID ~= 0 do
		local parent = C_Map.GetMapInfo(info.parentMapID)
		if not parent then
			break
		end
		info = parent
	end
	return info and C_Map.GetMapChildrenInfo(info.mapID, Enum.UIMapType.Zone, true) or {}
end

local function BuildZones()
	local roots = RootMaps()
	if #roots == 0 then
		return -- no map for the player yet (a loading screen): read again on the next build
	end
	zones = {}
	for _, info in ipairs(roots) do
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
	if ns.Coverage_Retired(info.name) then
		return false
	end
	-- Enum.FlightPathFaction may be missing on Forever: its values are Neutral 0, Horde 1, Alliance 2.
	local sides = Enum.FlightPathFaction or { Horde = 1, Alliance = 2 }
	if info.faction == sides.Horde then
		return faction == "Horde"
	elseif info.faction == sides.Alliance then
		return faction == "Alliance"
	end
	return true
end

-- x, y: where it is on the map it was read from (0..1, the position the world map places its pin at; callers keep
-- only nodes on that map, ns.Coverage_OnMap).
local function Node(info)
	local pos = info.position
	return { nodeID = info.nodeID, name = info.name, undiscovered = info.isUndiscovered, x = pos and pos.x,
		y = pos and pos.y }
end

-- { continents = { { mapID, name, zones = { { mapID, name, nodes = { { nodeID, name, undiscovered, x, y } } } } } } },
-- continents in map ID order (roughly expansion order). Each flight master is in one zone only.
-- The zone (or city) at a point of a continent map: the map the world map would open there.
local function ZoneAt(continentID, x, y, known)
	local hit = C_Map.GetMapInfoAtPosition(continentID, x, y)
	while hit and not known[hit.mapID] and hit.parentMapID and hit.parentMapID ~= 0 and hit.mapType > Enum.UIMapType.Zone do
		hit = C_Map.GetMapInfo(hit.parentMapID)
	end
	return hit and known[hit.mapID] and hit.mapID or nil
end

-- Forever: [zone map ID] = nodes. Its zone maps hand out flight masters with positions that don't place them in their
-- own zone (The Barrens listed Camp Mojache and Sun Rock Retreat, measured), and ShouldMapShowTaxiNodes says no even for
-- The Barrens. So each continent's flight masters are read once and put in the zone the map shows at their spot; a
-- city inside that zone, when it's one of ours, takes its own. x, y stay the zone map's, read from that zone.
local function ForeverNodes(faction)
	local known, continents = {}, {}
	for _, zone in ipairs(zones) do
		known[zone.mapID] = true
		continents[zone.continentID] = true
	end
	local byZone, zonePositions = {}, {}
	local function PositionOn(zoneID, nodeID)
		local positions = zonePositions[zoneID]
		if not positions then
			positions = {}
			for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(zoneID) or {}) do
				positions[info.nodeID] = info.position
			end
			zonePositions[zoneID] = positions
		end
		return positions[nodeID]
	end
	for continentID in pairs(continents) do
		for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(continentID) or {}) do
			local pos = info.position
			local zoneID = pos and ForPlayer(info, faction) and ZoneAt(continentID, pos.x, pos.y, known)
			if zoneID then
				local zonePos = PositionOn(zoneID, info.nodeID)
				local city = zonePos and ZoneAt(zoneID, zonePos.x, zonePos.y, known)
				if city and city ~= zoneID then
					zoneID, zonePos = city, PositionOn(city, info.nodeID) or zonePos
				end
				local node = Node(info)
				node.x, node.y = zonePos and zonePos.x, zonePos and zonePos.y
				byZone[zoneID] = byZone[zoneID] or {}
				table.insert(byZone[zoneID], node)
			end
		end
	end
	return byZone
end

function ns.Atlas_Build()
	if not zones then
		BuildZones()
	end
	local faction = UnitFactionGroup("player")
	local claimed, byContinent, list = {}, {}, {}
	local foreverNodes = ns.FOREVER and zones and C_TaxiMap.GetTaxiNodesForMap and ForeverNodes(faction) or nil
	for _, zone in ipairs(zones or {}) do
		local nodes
		if foreverNodes then
			nodes = foreverNodes[zone.mapID] or {}
		elseif C_TaxiMap.GetTaxiNodesForMap and C_TaxiMap.ShouldMapShowTaxiNodes
			and C_TaxiMap.ShouldMapShowTaxiNodes(zone.mapID) then
			nodes = {}
			for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(zone.mapID) or {}) do
				-- Off-map nodes belong to a neighbor: a city mustn't claim the flight masters of the zone around it.
				if not claimed[info.nodeID] and ForPlayer(info, faction) and ns.Coverage_OnMap(info.position) then
					claimed[info.nodeID] = true
					nodes[#nodes + 1] = Node(info)
				end
			end
		end
		if nodes then
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

-- Flight masters for the player on one map (any map type), each once, with their x, y on that map. Neighbors'
-- flight masters the API also returns (off the map) are left out.
function ns.Atlas_MapNodes(mapID)
	local faction = UnitFactionGroup("player")
	local nodes, seen = {}, {}
	if not C_TaxiMap.GetTaxiNodesForMap then
		return nodes
	end
	for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
		if not seen[info.nodeID] and ForPlayer(info, faction) and ns.Coverage_OnMap(info.position) then
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
