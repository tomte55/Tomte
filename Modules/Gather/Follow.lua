local addonName, ns = ...

-- Gathering routes: the loop per map (built by Route.lua, cached here) and follow mode, a map pin on the next spot of
-- the loop that moves on as you reach each spot. The pin goes through ns.TrackPin, so Waypoints (or Blizzard's
-- arrow) shows the way; Waypoints' card reads GatherFollow_Target. Following is kept in db.follow, so it goes on
-- after a /reload. Drawn by MapPins.lua and MinimapPins.lua, registered in Gather.lua.

local CHECK = 0.2 -- seconds between distance checks while following
local ARRIVE = 30 -- yards from the spot (on the map, height ignored) that count as reached
-- Blizzard's arrow clears tracking on arrival with a wider radius than ARRIVE (see Travel/Router.lua): a pin that's
-- gone while you're this close was reached, not replaced.
local ARRIVED_NEAR = 3 * ARRIVE
local RECENT = 300 -- seconds: a spot gathered this recently is skipped (and dimmed on the maps)
local AWAY = 60 -- seconds off the route's map that stop following
local SAME_SPOT = 0.0005 -- map share: the user waypoint is still ours (SetUserWaypoint rounds a little)

ns.GATHER_RECENT = RECENT

local ST = Enum.SuperTrackingType

local db, module
local cache = {} -- [mapID] = { key, route, spots, why } (route nil when there is no loop)
local follow -- { mapID, route, spots, w, h, k, dir, startK, steps, prev, awaySince }
local ticker

local events = ns.Gather_Events

-- Routes -------------------------------------------------------------------------------------------------------------

local function KindsKey(kinds)
	if not kinds then
		return "all"
	end
	local list = {}
	for kind in pairs(kinds) do
		list[#list + 1] = kind
	end
	table.sort(list)
	return table.concat(list, "+")
end

-- The kinds a route goes through: what the maps show, or your professions' when node pins are off.
local function RouteKinds()
	local kinds = ns.GatherPins_Kinds()
	if kinds == false then
		kinds = ns.GatherPins_Kinds("mine")
	end
	return kinds
end

-- The loop on mapID and the spots it indexes (GatherNodes_List), or nil, nil, why.
function ns.GatherRoute_For(mapID)
	if not (module and module.active and mapID) then
		return nil, nil, "Gathering is off"
	end
	local kinds = RouteKinds()
	if kinds == false then
		return nil, nil, "Gathering is off"
	end
	local key = KindsKey(kinds) .. (db.routeTight and ":tight" or "")
	local c = cache[mapID]
	if not (c and c.key == key) then
		local spots = ns.GatherNodes_List(db, mapID, kinds)
		local w, h = C_Map.GetMapWorldSize(mapID)
		local route, why = ns.GatherRoute_Build(spots, w, h, { tight = db.routeTight })
		c = { key = key, route = route, spots = spots, why = why }
		cache[mapID] = c
	end
	return c.route, c.spots, c.why
end

-- The spots changed (mapID, or every map when nil): routes are built again when next asked for.
function ns.GatherRoute_Changed(mapID)
	if mapID then
		cache[mapID] = nil
	else
		wipe(cache)
	end
end

-- True when the spot at pos on mapID was gathered in the last few minutes.
local function IsRecent(mapID, pos)
	local age = ns.Gather_SpotAge(mapID, pos)
	return age ~= nil and age < RECENT
end
ns.GatherRoute_IsRecent = IsRecent

-- Following ----------------------------------------------------------------------------------------------------------

local function Facing()
	local f = GetPlayerFacing()
	return f and ns.Readable(f) and f or nil
end

local function Current()
	return follow.spots[follow.route.order[follow.k]]
end

local function IsOurs()
	local point = C_Map.GetUserWaypoint()
	if not (point and point.uiMapID == follow.mapID) then
		return false
	end
	local spot = Current()
	local x, y = point.position.x, point.position.y
	return math.abs(x - spot.x) < SAME_SPOT and math.abs(y - spot.y) < SAME_SPOT
end

-- What is tracked now, to give it back when following stops. Plain numbers: it's saved in db.follow.
local function Remember()
	local prev = { type = C_SuperTrack.GetHighestPrioritySuperTrackingType() }
	local point = C_Map.GetUserWaypoint()
	if point then
		prev.map = point.uiMapID
		prev.x, prev.y = point.position.x, point.position.y
	end
	if prev.type == ST.Quest then
		prev.quest = C_SuperTrack.GetSuperTrackedQuestID()
	elseif prev.type == ST.MapPin then
		prev.pinType, prev.pinID = C_SuperTrack.GetSuperTrackedMapPin()
	end
	return prev
end

local function Restore(prev)
	ns.SafeTrack(function()
		if prev.map then
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(prev.map, prev.x, prev.y))
			C_SuperTrack.SetSuperTrackedUserWaypoint(prev.type == ST.UserWaypoint)
		else
			C_Map.ClearUserWaypoint()
		end
	end)
	if not ((prev.quest and prev.quest ~= 0) or (prev.pinType and prev.pinID)) then
		return
	end
	-- A frame later: Waypoints tracks a new map pin on the next frame (its autoTrack) and would take over again.
	C_Timer.After(0, function()
		ns.SafeTrack(function()
			if prev.quest and prev.quest ~= 0 then
				C_SuperTrack.SetSuperTrackedQuestID(prev.quest)
			else
				C_SuperTrack.SetSuperTrackedMapPin(prev.pinType, prev.pinID)
			end
		end)
	end)
end

local function Redraw()
	ns.GatherPins_Refresh()
	ns.GatherMini_Refresh()
end

local function Place()
	local spot = Current()
	ns.TrackPin(follow.mapID, spot.x, spot.y)
	db.follow = { mapID = follow.mapID, pos = spot.pos, dir = follow.dir, prev = follow.prev }
	Redraw()
end

local function Recent()
	local mapID, spots = follow.mapID, follow.spots
	return function(s)
		return IsRecent(mapID, spots[s].pos)
	end
end

local function Advance()
	local k, steps = ns.GatherRoute_Next(follow.route, follow.k, follow.dir, Recent())
	follow.k = k
	follow.steps = follow.steps + steps
	Place()
end

local function Near(yards)
	local x, y = ns.Gather_PlayerPos(follow.mapID)
	return x ~= nil and ns.GatherRoute_Dist({ x = x, y = y }, Current(), follow.w, follow.h) <= yards
end

local function Check()
	if not follow then
		return
	end
	local x, y = ns.Gather_PlayerPos(follow.mapID)
	if not x then
		follow.awaySince = follow.awaySince or GetTime()
		if GetTime() - follow.awaySince > AWAY then
			ns.GatherFollow_Stop("away")
		end
		return
	end
	follow.awaySince = nil
	if ns.GatherRoute_Dist({ x = x, y = y }, Current(), follow.w, follow.h) <= ARRIVE then
		Advance()
	end
end

-- A frame after a waypoint or tracking change (after the map's own handling): if the player tracked something else
-- (a quest, a map pin of their own), following ends and leaves that alone. Not while our own pin waits for the end
-- of combat (SafeTrack), when the map still has the previous one. Our pin cleared by Blizzard's arrival check while
-- you're at the spot means it was reached: on to the next one.
local function CheckTracking()
	if not follow or ns.SafeTrack_Waiting() then
		return
	end
	if C_SuperTrack.IsSuperTrackingUserWaypoint() and IsOurs() then
		return
	end
	local other = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	if (other == nil or other == ST.UserWaypoint) and Near(ARRIVED_NEAR) then
		Advance()
	else
		ns.GatherFollow_Stop("tracked")
	end
end

local function LaterCheckTracking()
	C_Timer.After(0, CheckTracking)
end

events:On("follow", "USER_WAYPOINT_UPDATED", LaterCheckTracking)
events:On("follow", "SUPER_TRACKING_CHANGED", LaterCheckTracking)

-- The map to follow: the player's, or the zone around a cave or building map that has no loop of its own.
-- Returns mapID or nil, why.
local function RouteMap()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not (mapID and ns.Readable(mapID)) then
		return nil, "no map here."
	end
	local why
	while mapID do
		local route, _, reason = ns.GatherRoute_For(mapID)
		if route then
			return mapID
		end
		why = why or reason
		local info = C_Map.GetMapInfo(mapID)
		if not (info and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0) then
			break
		end
		mapID = info.parentMapID
	end
	if why == "fewer than 2 spots" then
		return nil, "Tomte doesn't know enough node spots in this zone yet. Gather a few, or get some from a friend."
	end
	return nil, ("no route in this zone (%s)."):format(why or "no spots")
end

local function Begin(mapID, route, spots, k, dir, prev)
	local w, h = C_Map.GetMapWorldSize(mapID)
	follow = { mapID = mapID, route = route, spots = spots, w = w, h = h, k = k, dir = dir, startK = k, steps = 0,
		prev = prev }
	events:Watch("follow", "USER_WAYPOINT_UPDATED")
	events:Watch("follow", "SUPER_TRACKING_CHANGED")
	ticker = C_Timer.NewTicker(CHECK, Check)
end

function ns.GatherFollow_Start()
	if not (module and module.active) or follow then
		return
	end
	local mapID, why = RouteMap()
	if not mapID then
		ns.Print(why)
		return
	end
	local x, y = ns.Gather_PlayerPos(mapID)
	if not x then
		ns.Print("no position here (instances have none).")
		return
	end
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print("this map doesn't take map pins.")
		return
	end
	local route, spots = ns.GatherRoute_For(mapID)
	local w, h = C_Map.GetMapWorldSize(mapID)
	local recent = function(s)
		return IsRecent(mapID, spots[s].pos)
	end
	local k, dir = ns.GatherRoute_Start(route, spots, { x = x, y = y }, Facing(), w, h, recent)
	Begin(mapID, route, spots, k, dir, Remember())
	Place()
	ns.Print(("following the gathering route: %s."):format(ns.GatherRoute_Text(route)))
end

-- After a /reload or relog: following goes on when our pin is still the map pin; otherwise what was tracked before
-- comes back (unless the player set a pin of their own meanwhile).
function ns.GatherFollow_Resume()
	local saved = db.follow
	if follow or type(saved) ~= "table" then
		return
	end
	db.follow = false
	local point = C_Map.GetUserWaypoint()
	local route, spots = ns.GatherRoute_For(saved.mapID)
	local k
	for i, s in ipairs(route and route.order or {}) do
		if spots[s].pos == saved.pos then
			k = i
		end
	end
	local x, y = ns.GatherNodes_Unpack(saved.pos)
	local ours = point and point.uiMapID == saved.mapID
	if ours then
		local px, py = point.position.x, point.position.y
		ours = math.abs(px - x) < SAME_SPOT and math.abs(py - y) < SAME_SPOT
	end
	if not ours then
		return
	end
	if not (module.active and k) then
		Restore(saved.prev or {})
		return
	end
	Begin(saved.mapID, route, spots, k, saved.dir or 1, saved.prev or {})
	db.follow = { mapID = saved.mapID, pos = saved.pos, dir = follow.dir, prev = follow.prev }
	Redraw()
end

-- reason: "user" (button, command, key) or "off" give back what was tracked before; "away" too, with a note;
-- "tracked" (the player tracked something else) leaves that alone.
function ns.GatherFollow_Stop(reason)
	if not follow then
		return
	end
	local prev = follow.prev
	follow = nil
	db.follow = false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	events:UnwatchAll("follow")
	if reason ~= "tracked" then
		Restore(prev)
	end
	if reason == "away" then
		ns.Print("stopped following the gathering route: you left its zone.")
	elseif reason == "tracked" then
		ns.Print("stopped following the gathering route: you tracked something else.")
	elseif reason == "user" then
		ns.Print("stopped following the gathering route.")
	end
	Redraw()
end

function ns.GatherFollow_Toggle()
	if follow then
		ns.GatherFollow_Stop("user")
	else
		ns.GatherFollow_Start()
	end
end

function ns.GatherFollow_Skip()
	if follow then
		Advance()
	else
		ns.Print("not following a gathering route (/tomte gather follow starts one).")
	end
end

function ns.GatherFollow_Active()
	return follow ~= nil
end

-- The followed spot: mapID, pos (to mark it on the maps), or nil.
function ns.GatherFollow_Spot()
	if not follow then
		return nil
	end
	return follow.mapID, Current().pos
end

-- The route being followed, for the minimap: route, spots, mapID, w, h and the followed spot.
function ns.GatherFollow_Route()
	if not follow then
		return nil
	end
	return follow.route, follow.spots, follow.mapID, follow.w, follow.h, Current()
end

-- For Waypoints' card (Modules/Travel/Target.lua): { name, icon, line } while our pin is the tracked one.
function ns.GatherFollow_Target()
	if not (follow and IsOurs()) then
		return nil
	end
	local spot = Current()
	local t = spot.objectID and db.nodeTypes[spot.objectID]
	local icon = t and t.item and C_Item.GetItemIconByID(t.item) or ns.GATHER_KIND_ICONS[spot.kind]
	local n = #follow.route.order
	local index = ((follow.k - follow.startK) * follow.dir) % n + 1
	return {
		name = t and t.name or (ns.GATHER_KIND_NAMES[spot.kind] .. " node"),
		icon = { texture = icon },
		line = ("Gathering route, spot %d of %d, lap %d"):format(index, n, math.floor(follow.steps / n) + 1),
	}
end

-- /tomte gather route: the loop here and what following does.
function ns.GatherFollow_Info()
	local mapID, why = RouteMap()
	if not mapID then
		ns.Print(why)
		return
	end
	local route = ns.GatherRoute_For(mapID)
	local info = C_Map.GetMapInfo(mapID)
	ns.Print(("route in %s: %s."):format(info and info.name or "this zone", ns.GatherRoute_Text(route)))
	if follow then
		local t = ns.GatherFollow_Target()
		ns.Print(t and t.line or "following, but another pin is tracked.")
	else
		ns.Print("/tomte gather follow starts following it; a key binding does too (Key Bindings > Tomte).")
	end
end

function ns.GatherFollow_Init(saved, owner)
	db, module = saved, owner
end
