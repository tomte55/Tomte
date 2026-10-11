local addonName, ns = ...

-- Waypoints: guard directions. When a guard (or another NPC) gives directions, the game puts a gossip POI on the
-- map (DYNAMIC_GOSSIP_POI_UPDATED, read the way Blizzard's GossipDataProvider does). db.guard decides what happens:
-- "never" leaves it alone, "ask" offers a map pin, "always" pins and tracks it right away.

local GOSSIP_WINDOW = 5 -- seconds after a gossip window was open that a new POI counts as directions

local db
local gossipAt = -math.huge
local lastKey -- the POI already handled, so a repeat event doesn't ask again

-- The module's event bus (Router.lua and Waypoint.lua share it). Guard loads first, so it runs before Router and
-- Waypoint on shared events; that is harmless because Router defers every shared event by a frame.
local events = ns.NewEvents()
ns.Way_Events = events
local OWNER = "guard"

-- The POI on the player's map, or on a parent map up to zone level (directions can point out of a sub-map).
local function FindPoi()
	local mapID = C_Map.GetBestMapForUnit("player")
	while mapID and mapID ~= 0 do
		local poiID = C_GossipInfo.GetPoiForUiMapID(mapID)
		local info = poiID and C_GossipInfo.GetPoiInfo(mapID, poiID)
		if info then
			return mapID, poiID, info
		end
		local mapInfo = C_Map.GetMapInfo(mapID)
		if not mapInfo or mapInfo.mapType <= Enum.UIMapType.Zone then
			return nil
		end
		mapID = mapInfo.parentMapID
	end
end

local function Place(mapID, info)
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print("can't place a map pin on that map.")
		return
	end
	ns.TrackPin(mapID, info.position.x, info.position.y)
end

events:On(OWNER, "DYNAMIC_GOSSIP_POI_UPDATED", function()
	local mapID, poiID, info = FindPoi()
	if not mapID then
		lastKey = nil
		return
	end
	local key = ("%d:%d:%.3f:%.3f"):format(mapID, poiID, info.position.x, info.position.y)
	if key == lastKey or GetTime() - gossipAt > GOSSIP_WINDOW then
		return
	end
	lastKey = key
	if db.guard == "always" then
		Place(mapID, info)
	elseif db.guard == "ask" then
		local dialog = StaticPopup_Show("TOMTE_CONFIRM", ("Set a waypoint to %s?"):format(info.name))
		if dialog then
			dialog.data = function()
				Place(mapID, info)
			end
		end
	end
end)

local function GossipOpened()
	gossipAt = GetTime()
end
events:On(OWNER, "GOSSIP_SHOW", GossipOpened)
events:On(OWNER, "GOSSIP_CLOSED", GossipOpened)

function ns.WayGuard_Toggle(active, saved)
	db = saved
	if active then
		events:Watch(OWNER, "DYNAMIC_GOSSIP_POI_UPDATED")
		events:Watch(OWNER, "GOSSIP_SHOW")
		events:Watch(OWNER, "GOSSIP_CLOSED")
	else
		events:UnwatchAll(OWNER)
		lastKey = nil
	end
end
