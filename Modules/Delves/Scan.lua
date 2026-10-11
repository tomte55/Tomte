local addonName, ns = ...

-- Delves: today's delve entrances for the character's content expansion and tracking one. Entrances come from
-- C_AreaPoiInfo per zone (the expansion's list plus its continent's zones), cached until AREA_POIS_UPDATED, a zone
-- change or the daily reset:
-- - GetDelvesForMap, as Blizzard's DelveEntranceDataProvider reads it;
-- - GetAreaPOIForMap entries with the bountiful atlas (bountiful entrances are their own POIs and may only be there);
-- - the expansion's known bountiful POI IDs, probed with GetAreaPOIInfo on their zone (Plumber's way: the POI only
--   exists while that delve is bountiful).
-- Tracking: an AreaPOI super-track on the same continent (the Waypoints marker shows the delve's name and atlas),
-- else a map pin at the entrance so Waypoints routes it.

local MAX_DEPTH = 10
local MAX_PROBED = 8 -- more bountiful finds than this from the ID probe alone means it isn't telling active ones

local cache, cacheKey, cacheUntil

local function MapOfType(mapID, mapType)
	local info = mapID and C_Map.GetMapInfo(mapID)
	for _ = 1, MAX_DEPTH do
		if not info then
			return nil
		end
		if info.mapType == mapType then
			return info.mapID
		end
		info = (info.parentMapID or 0) > 0 and C_Map.GetMapInfo(info.parentMapID) or nil
	end
	return nil
end

function ns.DelvesScan_PlayerZone()
	return MapOfType(C_Map.GetBestMapForUnit("player"), Enum.UIMapType.Zone)
end

local function Zones(def)
	local seen, list = {}, {}
	local function Add(id)
		if id and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	for _, id in ipairs(def.zones or {}) do
		Add(id)
	end
	for _, child in ipairs(def.continent and C_Map.GetMapChildrenInfo(def.continent, Enum.UIMapType.Zone) or {}) do
		Add(child.mapID)
	end
	return list
end

local function Read(def)
	local list, seen = {}, {}
	local function Add(map, poi, bountifulOnly)
		if seen[poi] then
			return
		end
		local info = C_AreaPoiInfo.GetAreaPOIInfo(map, poi)
		if not (info and info.position) then
			return
		end
		local e = { poi = poi, map = map, name = info.name, atlas = info.atlasName, widgetSet = info.tooltipWidgetSet }
		e.bountiful = ns.Delves_IsBountiful(e, def.bountifulPOIs)
		if bountifulOnly and not e.bountiful then
			return
		end
		seen[poi] = true
		e.x, e.y = info.position:GetXY()
		list[#list + 1] = e
	end
	for _, map in ipairs(Zones(def)) do
		for _, poi in ipairs(C_AreaPoiInfo.GetDelvesForMap(map) or {}) do
			Add(map, poi)
		end
		for _, poi in ipairs(C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIForMap(map) or {}) do
			Add(map, poi, true)
		end
	end
	-- Only a handful are bountiful on a given day. If the probe alone finds more, the game returned inactive POIs
	-- too, so its finds are dropped rather than marking every delve bountiful.
	local before = #list
	for poi, map in pairs(def.bountifulPOIs or {}) do
		Add(map, poi, true)
	end
	if #list - before > MAX_PROBED then
		for i = #list, before + 1, -1 do
			list[i] = nil
		end
	end
	return ns.Delves_Dedupe(list)
end

function ns.DelvesScan_Invalidate()
	cache = nil
end

-- Below the level the game opens delves at (nil when it doesn't say).
function ns.DelvesScan_MinLevel()
	local minLevel = C_DelvesUI and C_DelvesUI.GetDelvesMinRequiredLevel and C_DelvesUI.GetDelvesMinRequiredLevel()
	local level = UnitLevel("player")
	if minLevel and not (issecretvalue and issecretvalue(level)) and level < minLevel then
		return minLevel
	end
	return nil
end

function ns.DelvesScan_List()
	local expansion = ns.ContentExpansion()
	local def = ns.Content_Get(expansion, "delves")
	if not def or ns.DelvesScan_MinLevel() then
		return {}
	end
	local stale = not cache or cacheKey ~= expansion or GetTime() >= (cacheUntil or 0)
	-- In combat the old list stays: no scans mid-fight, the same precaution as Read.lua's readers.
	if stale and not InCombatLockdown() then
		local ok, list = pcall(Read, def)
		if ok then
			cache, cacheKey = list, expansion
			local reset = C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset() or 3600
			-- Nothing found may mean the zones' data isn't loaded yet: look again in a minute.
			cacheUntil = GetTime() + (#list > 0 and math.max(reset or 3600, 60) + 5 or 60)
		end
	end
	local copy = {}
	for i, e in ipairs(cache or {}) do
		copy[i] = e
	end
	return ns.Delves_Sort(copy, ns.DelvesScan_PlayerZone())
end

function ns.Delves_Track(e)
	local here = MapOfType(C_Map.GetBestMapForUnit("player"), Enum.UIMapType.Continent)
	local mode = ns.Delves_TrackMode(here, MapOfType(e.map, Enum.UIMapType.Continent))
	if mode == "pin" and not C_Map.CanSetUserWaypointOnMap(e.map) then
		ns.Print("can't place a map pin there.")
		return
	end
	local now = ns.SafeTrack(function()
		if mode == "poi" then
			C_SuperTrack.SetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI, e.poi)
		else
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.map, e.x, e.y))
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
	ns.Print(("%s %s."):format(now and "tracking" or "after combat: tracking", e.name or "the delve"))
end

function ns.DelvesScan_ZoneName(map)
	local info = map and C_Map.GetMapInfo(map)
	return info and info.name or nil
end

-- The game's own entrance tooltip under the name: the story variant comes from the POI's widget set.
function ns.Delves_Tooltip(owner, e)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(e.name or "?", ns.UI.RGB("heading"))
	if e.bountiful then
		GameTooltip:AddLine("Bountiful", ns.UI.RGB("accent"))
	end
	local zone = ns.DelvesScan_ZoneName(e.map)
	if zone then
		GameTooltip:AddLine(zone, ns.UI.RGB("textMuted"))
	end
	if e.widgetSet and GameTooltip_AddWidgetSet then
		GameTooltip_AddWidgetSet(GameTooltip, e.widgetSet)
	end
	GameTooltip:AddLine("Click to track it", ns.UI.RGB("textMuted"))
	GameTooltip:Show()
end
