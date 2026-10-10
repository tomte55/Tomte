local addonName, ns = ...

-- Waypoints: routes to map pins on another continent. The game routes quests through portals, but not map pins:
-- a pin on another continent gets no navigation at all. When the tracked map pin is on another map (instance), the
-- route through Blizzard's waypoint network (Network.lua, Route.lua) is walked one step at a time: the map pin moves
-- to the next step (a portal, a zeppelin, a doorway) and is tracked, and once you're on the pin's continent your own
-- pin comes back. The real pin is saved per character (db.routes) so a /reload mid-route keeps it.

local TICK = 1 -- seconds between step checks while routing
local SPOT = 0.0005 -- map pins this close (0-1 map coordinates) are the same pin

local db
local active
-- { dest = the real pin { mapID, x, y }, target = its world point, path, index, leg = the step's pin { mapID, x, y },
-- legNode, map = the instance the path was found on }
local route
local failedKey -- the destination and start map that had no route: not searched (or said) again until one changes
local reached -- the step node the game said you reached (NAVIGATION_DESTINATION_REACHED)

local NET = { nodes = ns.WAY_NET_NODES, edges = ns.WAY_NET_EDGES, volumes = ns.WAY_NET_VOLUMES,
	conds = ns.WAY_NET_CONDS }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

-- Positions ------------------------------------------------------------------------------------------------

local function World(mapID, x, y)
	local map, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if map and pos then
		return { map = map, x = pos.x, y = pos.y }
	end
end

local function PlayerPoint()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		local point = World(mapID, pos.x, pos.y)
		if point then
			return point
		end
	end
	local x, y, _, map = UnitPosition("player")
	if x and map then
		return { map = map, x = x, y = y }
	end
end

-- A node's spot as a map pin on the most detailed map that takes one (a city, not the continent).
local function PinFor(node)
	local world = CreateVector2D(node[2], node[3])
	local mapID, pos = C_Map.GetMapPosFromWorldPos(node[1], world)
	if not mapID or not pos then
		return nil
	end
	local bestID, bestX, bestY
	if C_Map.CanSetUserWaypointOnMap(mapID) then
		bestID, bestX, bestY = mapID, pos.x, pos.y
	end
	for _ = 1, 5 do
		local child = C_Map.GetMapInfoAtPosition(mapID, pos.x, pos.y)
		if not child or child.mapID == mapID then
			break
		end
		local childID, childPos = C_Map.GetMapPosFromWorldPos(node[1], world, child.mapID)
		if not childID or not childPos or childPos.x < 0 or childPos.x > 1 or childPos.y < 0 or childPos.y > 1 then
			break
		end
		mapID, pos = childID, childPos
		if C_Map.CanSetUserWaypointOnMap(mapID) then
			bestID, bestX, bestY = mapID, pos.x, pos.y
		end
	end
	return bestID, bestX, bestY
end

local function SameSpot(point, spot)
	return point and spot and point.uiMapID == spot.mapID and math.abs(point.position.x - spot.x) < SPOT
		and math.abs(point.position.y - spot.y) < SPOT
end

-- A destination searched from a map, for failedKey.
local function Key(mapID, x, y, map)
	return ("%d:%.4f:%.4f:%s"):format(mapID, x, y, tostring(map))
end

-- Maps with network nodes: on any other (a dungeon, a delve) the route waits until you're back.
local netMaps
local function OnNetwork(map)
	if not netMaps then
		netMaps = {}
		for _, node in pairs(NET.nodes) do
			netMaps[node[1]] = true
		end
	end
	return netMaps[map] == true
end

local function MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or "your pin"
end

-- Conditions -----------------------------------------------------------------------------------------------

local function IsSpellKnown(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(id)
	end
	return IsPlayerSpell(id)
end

local function Api()
	return {
		faction = UnitFactionGroup("player"),
		class = select(3, UnitClass("player")),
		level = UnitLevel("player"),
		quest = function(id)
			return C_QuestLog.IsQuestFlaggedCompleted(id)
		end,
		onQuest = function(id)
			return C_QuestLog.IsOnQuest(id)
		end,
		ready = function(id)
			return C_QuestLog.ReadyForTurnIn(id)
		end,
		spell = IsSpellKnown,
		ach = function(id)
			return select(4, GetAchievementInfo(id)) == true
		end,
	}
end

-- Route ----------------------------------------------------------------------------------------------------

local function Save()
	local guid = UnitGUID("player")
	if not guid then
		return
	end
	if route then
		db.routes[guid] = { dest = { route.dest.mapID, route.dest.x, route.dest.y },
			leg = route.leg and { route.leg.mapID, route.leg.x, route.leg.y } }
	else
		db.routes[guid] = nil
	end
end

local function Changed()
	if ns.Way_TargetChanged then
		ns.Way_TargetChanged()
	end
end

local function Stop()
	route, reached = nil, nil
	ticker:Hide()
	Save()
	Changed()
end

local function Track(mapID, x, y)
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
end

-- On the pin's continent: your own pin back, tracked. failMap: the route broke on this map, so the pin coming back
-- isn't routed again from here (that would loop, or say "no route" a second time).
local function Finish(arrived, failMap)
	local dest = route.dest
	if failMap then
		failedKey = Key(dest.mapID, dest.x, dest.y, failMap)
	end
	Stop()
	Track(dest.mapID, dest.x, dest.y)
	if arrived then
		ns.Print(("Waypoints: on %s's continent, back to your pin."):format(MapName(dest.mapID)))
	end
end

local function Find(start)
	return ns.WayRoute_Find(NET, start, route.target, Api())
end

local function PlaceStep()
	local node = NET.nodes[route.path[route.index]]
	local mapID, x, y = PinFor(node)
	if not mapID then
		ns.Print("Waypoints: can't place a map pin at the next step, back to your pin.")
		Finish(false, route.map)
		return
	end
	route.leg = { mapID = mapID, x = x, y = y }
	Save()
	Track(mapID, x, y)
	Changed()
end

-- Where you are on the route: a new map means a portal was taken (or a hearthstone), so the route is found again
-- from here; on the same map the step moves on when you reach it.
local function Advance()
	local pos = PlayerPoint()
	if not pos then
		return
	end
	if pos.map == route.target.map then
		Finish(true)
		return
	end
	local atStep = reached ~= nil and reached == route.path[route.index]
	reached = nil
	if pos.map ~= route.map then
		if not OnNetwork(pos.map) then
			return -- a dungeon or a delve: the route waits, and is found again on the map you come out on
		end
		local path = Find(pos)
		if not path or #path == 0 then
			ns.Print("Waypoints: lost the route from here, back to your pin.")
			Finish(false, pos.map)
			return
		end
		route.path, route.index, route.map, route.legNode = path, 1, pos.map, nil
		atStep = false
	end
	route.index = ns.WayRoute_NextIndex(NET, route.path, route.index, pos, atStep)
	local nodeID = route.path[route.index]
	if nodeID ~= route.legNode then
		route.legNode = nodeID
		PlaceStep()
	end
end

-- point: a UiMapPoint-like { uiMapID, position = { x, y } }. quiet: resuming a saved route, no chat line.
local function Start(point, quiet)
	local mapID, x, y = point.uiMapID, point.position.x, point.position.y
	local target = World(mapID, x, y)
	local pos = PlayerPoint()
	if not target or not pos or target.map == pos.map then
		return false
	end
	if not OnNetwork(pos.map) then
		return false -- a dungeon or a delve: nothing to route from, and nothing to say
	end
	local key = Key(mapID, x, y, pos.map)
	if key == failedKey then
		return false
	end
	local path = ns.WayRoute_Find(NET, pos, target, Api())
	if not path or #path == 0 then
		failedKey = key
		ns.Print(("Waypoints: no portal route to %s from here. Try a Hearthstone or a teleport."):format(
			MapName(mapID)))
		return false
	end
	-- The first step must take a map pin, or the route would end and start again on every pin update.
	if not PinFor(NET.nodes[path[ns.WayRoute_NextIndex(NET, path, 1, pos)]]) then
		failedKey = key
		ns.Print(("Waypoints: can't place a map pin on the route to %s."):format(MapName(mapID)))
		return false
	end
	failedKey = nil
	route = { dest = { mapID = mapID, x = x, y = y }, target = target, path = path, index = 1, map = pos.map }
	if not quiet then
		ns.Print(("Waypoints: %s is on another continent. Route: %s."):format(MapName(mapID),
			table.concat(ns.WayRoute_Summary(NET, path), ", then ")))
	end
	ticker:Show()
	Advance()
	return true
end

local function Check()
	if not active then
		return
	end
	local point = C_Map.GetUserWaypoint()
	if not point then
		failedKey = nil -- the pin was removed: placing it again tries again (a portal may have opened up since)
	end
	if route then
		if not point then
			Stop() -- the pin was removed: the route goes with it
			return
		end
		if SameSpot(point, route.leg) then
			Advance()
			return
		end
		Stop() -- another pin was placed: that's the new destination
	end
	if not db.portals or not point or not C_SuperTrack.IsSuperTrackingUserWaypoint() then
		return
	end
	Start(point)
end

-- After a /reload or login: the saved route goes on if the map pin is still its step.
local function Resume()
	local guid = UnitGUID("player")
	local saved = guid and db.routes[guid]
	if not saved then
		return
	end
	db.routes[guid] = nil
	local point = C_Map.GetUserWaypoint()
	if not (saved.leg and point and SameSpot(point, { mapID = saved.leg[1], x = saved.leg[2], y = saved.leg[3] })) then
		return
	end
	local target = World(saved.dest[1], saved.dest[2], saved.dest[3])
	local pos = PlayerPoint()
	if target and pos and target.map ~= pos.map and not OnNetwork(pos.map) then
		-- Reloaded in a dungeon or a delve: the route waits (route.map false), found again on the map you come out on.
		route = { dest = { mapID = saved.dest[1], x = saved.dest[2], y = saved.dest[3] }, target = target, path = {},
			index = 1, map = false, leg = { mapID = saved.leg[1], x = saved.leg[2], y = saved.leg[3] } }
		Save()
		ticker:Show()
		Changed()
		return
	end
	if not Start({ uiMapID = saved.dest[1], position = { x = saved.dest[2], y = saved.dest[3] } }, true) then
		-- Already on the pin's continent (or no route any more): the real pin comes back.
		Track(saved.dest[1], saved.dest[2], saved.dest[3])
	end
end

-- Events ---------------------------------------------------------------------------------------------------

local pending
local function CheckSoon()
	if pending then
		return
	end
	pending = true
	C_Timer.After(0, function()
		pending = false
		Check()
	end)
end

events.USER_WAYPOINT_UPDATED = CheckSoon
events.SUPER_TRACKING_CHANGED = CheckSoon
events.ZONE_CHANGED_NEW_AREA = CheckSoon

local resumed
function events:PLAYER_ENTERING_WORLD()
	if not resumed then
		resumed = true
		C_Timer.After(0, function()
			if active then
				Resume()
				Check()
			end
		end)
		return
	end
	CheckSoon()
end

-- Blizzard stops tracking a map pin you reach (its radius can be wider than WAY_ROUTE_AT, so reaching it counts as
-- standing at the step). A step with the next one on this map moves on (and that one is tracked); at a portal
-- tracking stays off until you've taken it, so the two don't fight over it.
-- Only when you're near the step itself: a quest destination reached mid-route mustn't skip a step.
function events:NAVIGATION_DESTINATION_REACHED()
	local node = route and route.legNode and NET.nodes[route.legNode]
	local pos = node and PlayerPoint()
	if pos and pos.map == node[1] then
		local dx, dy = pos.x - node[2], pos.y - node[3]
		if math.sqrt(dx * dx + dy * dy) <= 3 * ns.WAY_ROUTE_AT then
			reached = route.legNode
		end
	end
	CheckSoon()
end

local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed >= TICK then
		elapsed = 0
		Check()
	end
end)

-- API ------------------------------------------------------------------------------------------------------

-- The step being tracked, for the marker: { text, nextText, destName }, or nil when the tracked pin isn't a step.
function ns.WayRouter_Step()
	if not route or not route.leg or not route.path[route.index] or not SameSpot(C_Map.GetUserWaypoint(), route.leg) then
		return nil
	end
	local text, nextText = ns.WayRoute_Texts(NET, route.path, route.index)
	return { text = text, nextText = nextText, destName = MapName(route.dest.mapID) }
end

-- /tomte way route
function ns.WayRouter_Print()
	if not route then
		ns.Print("Waypoints: no route. Track a map pin on another continent to get one.")
		return
	end
	ns.Print(("Waypoints: route to %s:"):format(MapName(route.dest.mapID)))
	for i, id in ipairs(route.path) do
		local node = NET.nodes[id]
		print((i == route.index and "  > " or "    ") .. node[7])
	end
end

-- Turning routes (or the module) off brings the real pin back.
function ns.WayRouter_Toggle(on, saved)
	db = saved
	if on == active then
		return
	end
	active = on
	failedKey, reached = nil, nil
	if on then
		for _, event in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA",
			"PLAYER_ENTERING_WORLD", "NAVIGATION_DESTINATION_REACHED" }) do
			events:RegisterEvent(event)
		end
		if IsLoggedIn() then
			resumed = true
			Resume()
			CheckSoon()
		end
	else
		events:UnregisterAllEvents()
		if route then
			Finish(false)
		end
	end
end
