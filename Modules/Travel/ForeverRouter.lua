local addonName, ns = ...

-- Waypoints on World of Warcraft: Forever: routes by flight path, zeppelin and boat to a tracked map pin that's quicker
-- to reach that way (docs/superpowers/specs/2026-11-21-tomte-forever-routes-design.md). Every second the way is planned
-- again from where you stand (ForeverRouteData.lua), and the map pin moves to the place to act next: the flight master
-- to fly from, the zeppelin tower or the dock. Once walking is the way, your own pin comes back. The real pin is saved
-- per character (db.routes, the shape Router.lua saves) so a /reload mid-route keeps it. Loaded only on Forever, in
-- Router.lua's place: it provides the same ns.WayRouter_* functions, so Waypoint.lua and Target.lua need no branch.

local TICK = 1 -- seconds between plans while routing
local AIM_SAME = 30 -- yards: a target spot that moved less (a quest's spot read again) keeps its route
-- Seconds a route for the arrow (see Aim below) lasts without the arrow asking for it; then it's dropped and the arrow
-- asked again, so one for a target no longer followed ends.
local AIM_IDLE = 20
local SPOT = 0.0005 -- map pins this close (0-1 map coordinates) are the same pin
local MAP_CONTINENT = 2 -- Enum.UIMapType.Continent
local FACTION = { Neutral = 0, Horde = 1, Alliance = 2 } -- Enum.FlightPathFaction
local SIDE = { Horde = "H", Alliance = "A" } -- Transports.lua's sides

local db, active
-- { dest = the real pin { mapID, x, y }, target = its world point { map, x, y }, plan (ForeverRouteData.lua's),
-- leg = the step's pin { mapID, x, y }, legPlace = the place it stands on (a graph place), memo = the planner's }
local route
-- A route for the arrow alone, to a target that isn't a map pin (the quest the Quest list follows): { target = its
-- world point, name, plan, legPlace, asked = GetTime() of the arrow's last ask, memo = the planner's }. Nothing is
-- placed on the map: an addon's super-tracking taints Forever's tracker and map.
local aim
local failedKey -- the destination and start map that had no way: not searched (or said) again until one changes
-- The places and links (ForeverRouteData.lua; each place also has pin = { mapID, x, y }, the spot it was read at):
-- read when first needed, again after a flight master's map.
local graph
local events = ns.Way_Events
local OWNER = "foreverrouter"
local ticker = CreateFrame("Frame")
ticker:Hide()

-- Positions ------------------------------------------------------------------------------------------------------------

local function World(mapID, x, y)
	local map, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if map and pos then
		return { map = map, x = pos.x, y = pos.y }
	end
end

-- Where you stand in world yards (the same as GetWorldPosFromMapPos gives), or nil inside an instance.
local function PlayerPoint()
	local x, y, _, instance = UnitPosition("player")
	if x and y and instance and ns.Readable(x, y, instance) then
		return { map = instance, x = x, y = y }
	end
end

local function SameSpot(point, spot)
	return point and spot and point.uiMapID == spot.mapID and math.abs(point.position.x - spot.x) < SPOT
		and math.abs(point.position.y - spot.y) < SPOT
end

local function Key(mapID, x, y, map)
	return ("%d:%.4f:%.4f:%s"):format(mapID, x, y, tostring(map))
end

local function MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or "your pin"
end

-- The pin's own name (a guide's /way text, an NPC's name), or nil.
local function Title(dest)
	return ns.WayTarget_PinTitle and ns.WayTarget_PinTitle(dest.mapID, dest.x, dest.y)
end

-- The graph ------------------------------------------------------------------------------------------------------------

-- The continent a zone map is on, or nil.
local function ContinentOf(mapID)
	for _ = 1, 6 do -- a safety cap: zone > continent is one or two steps
		local info = mapID and C_Map.GetMapInfo(mapID)
		if not info then
			return nil
		end
		if info.mapType == MAP_CONTINENT then
			return info.mapID
		end
		mapID = info.parentMapID
	end
end

local function TaxiPos(v)
	if type(v) ~= "table" then
		return nil
	end
	if type(v.GetXY) == "function" then
		return v:GetXY()
	end
	return v.x, v.y
end

-- The flight paths this character knows: { [the game's node name] = true }, learned at flight masters.
local function KnownFlights()
	local guid = UnitGUID("player")
	if not (guid and db) then
		return {}
	end
	db.flights[guid] = db.flights[guid] or {}
	return db.flights[guid]
end

-- At a flight master: its window lists the continent's flight paths, "CURRENT" (here) and "REACHABLE" being the ones
-- you know; "DISTANT" marked unknown ones too (The Sepulcher, never visited, measured 2026-11-21), and a placeholder
-- "Generic, World target". GetTaxiNodesForMap's isUndiscovered didn't say which (Grom'gol unknown yet used), so this
-- list is what routes go by, kept per character and read again on every visit: one the window no longer counts as
-- known (saved before this was measured) is dropped.
local LEARNED = { CURRENT = true, REACHABLE = true }
local function LearnFlights()
	local known = KnownFlights()
	for slot = 1, NumTaxiNodes() or 0 do
		local name = TaxiNodeName(slot)
		if name then
			local learned = LEARNED[TaxiNodeGetType(slot) or ""] or nil
			if known[name] ~= learned then
				known[name] = learned
				graph = nil
			end
		end
	end
end

-- The continents a zeppelin or boat reaches (their map IDs), from the transports' zone maps: read once.
local continents
local function Continents()
	if continents then
		return continents
	end
	continents = {}
	local seen = {}
	for _, t in ipairs(ns.Content_Get(ns.CONTENT_FOREVER, "transports") or {}) do
		for _, side in ipairs({ t.a, t.b }) do
			local c = ContinentOf(side[1])
			if c and not seen[c] then
				seen[c] = true
				continents[#continents + 1] = c
			end
		end
	end
	return continents
end

-- The flight masters you know and your side may use, on every continent a zeppelin or boat reaches; then each
-- zeppelin's and boat's two ends.
local function ReadGraph()
	local places, links = {}, {}
	local transports = ns.Content_Get(ns.CONTENT_FOREVER, "transports") or {}
	local faction = UnitFactionGroup("player")
	local mine = FACTION[faction]
	local known = KnownFlights()
	for _, c in ipairs(Continents()) do
		for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(c) or {}) do
			local x, y = TaxiPos(node.position)
			local usable = not node.faction or node.faction == FACTION.Neutral or node.faction == mine
			local w = x and usable and node.name and known[node.name] and World(c, x, y)
			if w then
				-- "Ratchet, The Barrens": the town alone reads better in "Fly to Ratchet, then ...".
				local name = node.name and (node.name:match("^(.-),") or node.name)
				places[#places + 1] = { map = w.map, x = w.x, y = w.y, name = name, fullName = node.name, kind = "taxi",
					pin = { c, x, y } }
			end
		end
	end
	local side = SIDE[faction]
	for _, t in ipairs(transports) do
		if not t.side or t.side == side then
			local a = World(t.a[1], t.a[2] / 100, t.a[3] / 100)
			local b = World(t.b[1], t.b[2] / 100, t.b[3] / 100)
			if a and b then
				places[#places + 1] = { map = a.map, x = a.x, y = a.y, name = t.a[4], kind = "dock",
					pin = { t.a[1], t.a[2] / 100, t.a[3] / 100 } }
				places[#places + 1] = { map = b.map, x = b.x, y = b.y, name = t.b[4], kind = "dock",
					pin = { t.b[1], t.b[2] / 100, t.b[3] / 100 } }
				links[#links + 1] = { a = #places - 1, b = #places, kind = t.kind }
			end
		end
	end
	return { places = places, links = links }
end

local function Graph()
	if not graph then
		graph = ReadGraph()
	end
	return graph
end

-- Places with continents of their own: on any other map (a dungeon) the route waits until you're back.
local function OnNetwork(map)
	for _, p in ipairs(Graph().places) do
		if p.map == map then
			return true
		end
	end
	return false
end

-- A place's index in the graph now (it's read again after a flight master's map), or nil.
local function IndexOf(place)
	if not place then
		return nil
	end
	for i, p in ipairs(Graph().places) do
		if p == place or (p.kind == place.kind and p.map == place.map and p.name == place.name
			and math.abs(p.x - place.x) < 1 and math.abs(p.y - place.y) < 1) then
			return i
		end
	end
end

-- Route ----------------------------------------------------------------------------------------------------------------

local function Save()
	local guid = UnitGUID("player")
	if not guid then
		return
	end
	if route and route.leg then
		db.routes[guid] = { dest = { route.dest.mapID, route.dest.x, route.dest.y },
			leg = { route.leg.mapID, route.leg.x, route.leg.y } }
	else
		db.routes[guid] = nil
	end
end

local function Changed()
	if ns.Way_TargetChanged then
		ns.Way_TargetChanged()
	end
	if ns.MapWindow_Relayout then
		ns.MapWindow_Relayout() -- the route's line on the Tomte map (Modules/Map/RouteLine.lua)
	end
end

local function Stop()
	route = nil
	if not aim then
		ticker:Hide()
	end
	Save()
	Changed()
end

local Track = ns.TrackPin

-- Your own pin back, tracked. failMap: the route broke on this map, so the pin coming back isn't routed again from here.
local function Finish(message, failMap)
	local dest = route.dest
	if failMap then
		failedKey = Key(dest.mapID, dest.x, dest.y, failMap)
	end
	Stop()
	Track(dest.mapID, dest.x, dest.y)
	if message then
		ns.Print("Waypoints: " .. message)
	end
end

-- The plan's first step: the map pin moves to where it starts, when that's a new place.
local function Use(plan)
	local place = Graph().places[plan.steps[1].from]
	if place == route.legPlace then
		if not ns.WayForever_SamePlan(route.plan, plan) then
			route.plan = plan
			Changed() -- the steps after it changed
		end
		return
	end
	route.plan = plan
	-- The most detailed map's spot; else the map the place was read on (pin: { mapID, x, y }), for a client without
	-- GetMapPosFromWorldPos (not measured on Forever).
	local mapID, x, y
	if C_Map.GetMapPosFromWorldPos then
		mapID, x, y = ns.MapPinSpot(place.map, place.x, place.y)
	end
	if not mapID and C_Map.CanSetUserWaypointOnMap(place.pin[1]) then
		mapID, x, y = place.pin[1], place.pin[2], place.pin[3]
	end
	if not mapID then
		Finish("can't place a map pin at the next step, back to your pin.", place.map)
		return
	end
	route.legPlace = place
	route.leg = { mapID = mapID, x = x, y = y }
	Save()
	Track(mapID, x, y)
	Changed()
end

-- Planned again from where you stand: landing, a crossing or a hearthstone just leads to the next step. Not while
-- flying (you move along the flight) or inside an instance (the route waits).
local function Advance()
	if UnitOnTaxi("player") then
		return
	end
	local pos = PlayerPoint()
	if not pos or not OnNetwork(pos.map) and pos.map ~= route.target.map then
		return
	end
	route.memo = route.memo or {}
	local plan = ns.WayForever_Plan(Graph(), pos, route.target, IndexOf(route.legPlace), route.memo)
	plan.graph = Graph()
	if #plan.steps == 0 then
		if plan.cost then
			Finish(("the rest of the way is on foot, back to %s."):format(Title(route.dest) or "your pin"))
		else
			Finish("lost the route from here, back to your pin.", pos.map)
		end
		return
	end
	Use(plan)
end

-- point: a UiMapPoint-like { uiMapID, position = { x, y } }. quiet: resuming a saved route, no chat line.
local function Start(point, quiet)
	local mapID, x, y = point.uiMapID, point.position.x, point.position.y
	local target = World(mapID, x, y)
	local pos = PlayerPoint()
	if not target or not pos or UnitOnTaxi("player") then
		return false
	end
	if not OnNetwork(pos.map) and pos.map ~= target.map then
		return false -- a dungeon: nothing to route from, and nothing to say
	end
	local key = Key(mapID, x, y, pos.map)
	if key == failedKey then
		return false
	end
	local plan = ns.WayForever_Plan(Graph(), pos, target)
	plan.graph = Graph()
	if #plan.steps == 0 then
		if not plan.cost then
			failedKey = key
			ns.Print(("Waypoints: no flight path, zeppelin or boat you can use leads to %s from here."):format(
				MapName(mapID)))
		end
		return false
	end
	failedKey = nil
	route = { dest = { mapID = mapID, x = x, y = y }, target = target }
	if not quiet then
		local texts = {}
		for i, step in ipairs(plan.steps) do
			texts[i] = ns.WayForever_StepText(Graph(), step)
		end
		ns.Print(("Waypoints: route to %s: %s."):format(Title(route.dest) or MapName(mapID),
			table.concat(texts, ", then ")))
	end
	if not quiet and next(KnownFlights()) == nil then
		ns.Print("Waypoints: talk to any flight master once, so routes know your flight paths.")
	end
	ticker:Show()
	Use(plan)
	return route ~= nil
end

local function Check()
	if not active or ns.SafeTrack_Waiting() then
		return -- a pin of ours waits for the end of combat: its update checks again then
	end
	local point = C_Map.GetUserWaypoint()
	if not point then
		failedKey = nil -- the pin was removed: placing it again tries again (a flight path may be known since)
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
	if ns.Way_RestoreName then
		ns.Way_RestoreName() -- the pin's name, before a route to it is announced
	end
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
	if not Start({ uiMapID = saved.dest[1], position = { x = saved.dest[2], y = saved.dest[3] } }, true) then
		-- Walking is the way now, or you're in a dungeon or on a flight: the real pin comes back (a flight's
		-- landing finds the route again once it's tracked).
		Track(saved.dest[1], saved.dest[2], saved.dest[3])
	end
end

-- Events ---------------------------------------------------------------------------------------------------------------

-- Next frame, after the game's own handling of the event (as Router.lua), and several events in one frame make one check.
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

events:On(OWNER, "USER_WAYPOINT_UPDATED", CheckSoon)
events:On(OWNER, "SUPER_TRACKING_CHANGED", CheckSoon)
events:On(OWNER, "ZONE_CHANGED_NEW_AREA", CheckSoon)
-- A flight master's map: the flight paths you know, maybe one more than before. Next frame, when the taxi window has its
-- nodes (they're read on its own TAXIMAP_OPENED; not measured whether they're there before).
events:On(OWNER, "TAXIMAP_OPENED", function()
	C_Timer.After(0, LearnFlights)
end)
events:On(OWNER, "TAXIMAP_CLOSED", function()
	graph = nil
end)

local resumed
events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
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
end)

-- Aim (a route for the arrow alone) ------------------------------------------------------------------------------------

local function Near(a, b)
	if a.map ~= b.map then
		return false
	end
	local dx, dy = a.x - b.x, a.y - b.y
	return dx * dx + dy * dy <= AIM_SAME * AIM_SAME
end

-- Planned again from where you stand. Returns true when the arrow should change: a new first step, or the route ended
-- (aim is nil then: the rest is on foot).
local function AimPlan()
	if UnitOnTaxi("player") then
		return false
	end
	local pos = PlayerPoint()
	if not pos or not OnNetwork(pos.map) and pos.map ~= aim.target.map then
		return false
	end
	aim.memo = aim.memo or {}
	local plan = ns.WayForever_Plan(Graph(), pos, aim.target, IndexOf(aim.legPlace), aim.memo)
	if #plan.steps == 0 then
		aim = nil
		return true
	end
	plan.graph = Graph()
	if ns.WayForever_SamePlan(aim.plan, plan) then
		return false -- the same steps: the plan on show stays (the map's line watches it, Window.lua)
	end
	local place = Graph().places[plan.steps[1].from]
	local changed = place ~= aim.legPlace or #plan.steps ~= #(aim.plan and aim.plan.steps or {})
	aim.plan, aim.legPlace = plan, place
	return changed
end

local function AimStep()
	local g, steps = Graph(), aim.plan.steps
	local place = g.places[steps[1].from]
	return {
		text = ns.WayForever_StepText(g, steps[1]),
		nextText = steps[2] and ns.WayForever_StepText(g, steps[2]) or nil,
		destName = aim.name,
		destTitle = aim.name,
		indoor = { map = place.map, x = place.x, y = place.y },
	}
end

local function AimTick()
	if not aim then
		return
	end
	if GetTime() - aim.asked > AIM_IDLE then
		aim = nil -- the arrow asks again on the change below if it's still the target
		Changed()
	elseif AimPlan() then
		Changed()
	end
end

local elapsed = 0
ticker:SetScript("OnUpdate", ns.Perf_Wrap(function(self, dt)
	elapsed = elapsed + dt
	if elapsed >= TICK then
		elapsed = 0
		Check()
		AimTick()
		if not route and not aim then
			self:Hide()
		end
	end
end, "OnUpdate"))

-- API (Router.lua's) ---------------------------------------------------------------------------------------------------

-- The step being tracked, for the arrow and its text: { text, nextText, destName, destTitle }, or nil when the tracked
-- pin isn't a step.
function ns.WayRouter_Step()
	if not route or not route.plan or not SameSpot(C_Map.GetUserWaypoint(), route.leg) then
		return nil
	end
	local g, steps = Graph(), route.plan.steps
	return {
		text = ns.WayForever_StepText(g, steps[1]),
		nextText = steps[2] and ns.WayForever_StepText(g, steps[2]) or nil,
		destName = MapName(route.dest.mapID),
		destTitle = Title(route.dest),
	}
end

-- Target.lua, on Forever, for a target that isn't a map pin (the followed quest): point is its world spot { map, x, y },
-- name its name. When it's quicker to reach by flight path, zeppelin or boat, the step for the arrow: { text,
-- nextText, destName, destTitle, indoor = the step's world point }; else nil. Planned again every second meanwhile.
-- point nil: nothing to aim for now (no quest followed, or a map pin tracked), so the arrow's route goes at once.
-- Either way, a new or dropped route draws its line on the Tomte map again right away (picking another quest there).
function ns.WayRouter_Aim(point, name)
	if not active or not db.portals or not point then
		if aim then
			aim = nil
			Changed()
		end
		return nil
	end
	if aim and Near(aim.target, point) then
		aim.asked, aim.name = GetTime(), name
		return aim.plan and AimStep() or nil
	end
	local had = aim ~= nil
	aim = { target = point, name = name, asked = GetTime() }
	AimPlan()
	if had or aim then
		Changed()
	end
	if not aim then
		return nil
	end
	ticker:Show()
	-- No plan yet on a flight or in a dungeon (AimPlan waits): the ticker plans it once you're back on the network.
	return aim.plan and AimStep() or nil
end

-- The route on show: the map pin's, else the arrow's. Its plan and the name of where it ends.
local function Shown()
	if route and route.plan then
		return route.plan, Title(route.dest) or MapName(route.dest.mapID)
	end
	if aim and aim.plan then
		return aim.plan, aim.name
	end
end

-- The plan on show, the same table until its steps change: the Tomte map draws its line again when this changes
-- (Modules/Map/Window.lua), whatever changed it.
function ns.WayRouter_Shown()
	return (Shown())
end

-- The flight master the route flies to next, for the Tomte map's flight mode to ring (Modules/Map/Flights.lua):
-- { name = the game's full name ("Ratchet, The Barrens"), note = its tooltip line }, or nil.
function ns.WayRouter_FlyTo()
	local plan, destName = Shown()
	local step = plan and plan.steps[1]
	if not step or step.kind ~= "fly" then
		return nil
	end
	local to = Graph().places[step.to]
	if not to then
		return nil
	end
	return { name = to.fullName, note = ("On your route to %s"):format(destName or "your target") }
end

-- The continents' map IDs routes know, for Target.lua to find a followed quest's spot on another continent.
function ns.WayRouter_Continents()
	return Continents()
end

-- The route's points for the Tomte map's line (Modules/Map/RouteLine.lua): { { mapID, x, y, kind }, ... } from the
-- first step's place to your pin, kind being how you get to that point ("start", "fly", "zeppelin", "boat", "walk");
-- nil without a route. The arrow's route ends at its last landing: its target has no map spot here, only a world one.
function ns.WayRouter_Path()
	local plan = Shown()
	if not plan then
		return nil
	end
	local places, path = Graph().places, {}
	for i, step in ipairs(plan.steps) do
		local from, to = places[step.from], places[step.to]
		if not (from and to) then
			return nil
		end
		path[#path + 1] = { from.pin[1], from.pin[2], from.pin[3], i == 1 and "start" or "walk" }
		path[#path + 1] = { to.pin[1], to.pin[2], to.pin[3], step.kind }
	end
	if route and route.plan then
		path[#path + 1] = { route.dest.mapID, route.dest.x, route.dest.y, "walk" }
	end
	return path
end

-- /tomte way route
function ns.WayRouter_Print()
	local plan, name = Shown()
	if not plan then
		ns.Print("Waypoints: no route. Track a map pin or follow a quest that's quicker to reach by flight path, "
			.. "zeppelin or boat.")
		return
	end
	ns.Print(("Waypoints: route to %s:"):format(name))
	for i, line in ipairs(ns.WayForever_Lines(Graph(), plan, name)) do
		print((i == 1 and "  > " or "    ") .. line)
	end
end

-- /tomte way flights: the flight paths routes take as known for this character, and at a flight master what its window
-- says of each one (which of them it counts as known is LEARNED above). "reset" forgets this character's list.
function ns.WayRouter_Flights(arg)
	local known = KnownFlights()
	if arg == "reset" then
		for name in pairs(known) do
			known[name] = nil
		end
		graph = nil
		ns.Print("Waypoints: this character's flight paths forgotten. Open a flight master's map to learn them again.")
		return
	end
	local names = {}
	for name in pairs(known) do
		names[#names + 1] = name
	end
	table.sort(names)
	ns.Print(("Waypoints: %d flight paths taken as known: %s"):format(#names, table.concat(names, "; ")))
	local count = NumTaxiNodes() or 0
	if count == 0 then
		print("  Open a flight master's map and type this again to see what its window says of each one.")
		return
	end
	for slot = 1, count do
		print(("  %d. %s: %s"):format(slot, tostring(TaxiNodeName(slot)), tostring(TaxiNodeGetType(slot))))
	end
end

-- Turning routes (or the module) off brings the real pin back.
function ns.WayRouter_Toggle(on, saved)
	db = saved
	if on == active then
		return
	end
	active = on
	failedKey, graph, aim = nil, nil, nil
	if on then
		for _, event in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA",
			"PLAYER_ENTERING_WORLD", "TAXIMAP_OPENED", "TAXIMAP_CLOSED" }) do
			events:Watch(OWNER, event)
		end
		if IsLoggedIn() then
			resumed = true
			Resume()
			CheckSoon()
		end
	else
		events:UnwatchAll(OWNER)
		if route then
			Finish()
		end
	end
end
