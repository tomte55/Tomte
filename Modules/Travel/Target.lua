local addonName, ns = ...

-- Waypoints: what is super-tracked, as { kind, name, icon, lines, questID, redirect }. icon is { atlas = } or
-- { texture = }, lines are the card's text lines (objectives, turn-in text, descriptions). Rebuilt on events,
-- not per frame. API facts checked against the 12.1.0 docs (GetNextWaypointForMap moved to C_Navigation).

local ST = Enum.SuperTrackingType
local PIN = Enum.SuperTrackingMapPinType
local MAX_LINES = 3

local ICON_PIN = { atlas = "Waypoint-MapPin-Tracked" }
local ICON_DEFAULT = { atlas = "Navigation-Tracked-Icon" }
local ICON_CORPSE = { atlas = "Navigation-Tombstone-Icon" }
local ICON_TAXI = { atlas = "Crosshair_Taxi_128" }
local ICON_DIG = { atlas = "ArchBlob" }
local PORTAL_ATLAS = { Horde = "MagePortalHorde", Alliance = "MagePortalAlliance" }
local OWNER = Enum.HousingPlotOwnerType or {}
local HOUSING_DEFAULT = "housing-map-plot-unoccupied"
local HOUSING_ATLAS = {}
if OWNER.Self then
	HOUSING_ATLAS[OWNER.Self] = "housing-map-plot-player-house"
	HOUSING_ATLAS[OWNER.Friend] = "housing-map-plot-occupied-friend"
	HOUSING_ATLAS[OWNER.Stranger] = "housing-map-plot-occupied"
end

local function Asset(asset, isAtlas)
	if not asset then
		return nil
	end
	return isAtlas and { atlas = asset } or { texture = asset }
end

local function ItemName()
	local name, description = C_SuperTrack.GetSuperTrackedItemName()
	return name, description
end

local function AddLine(lines, text)
	if text and text ~= "" and #lines < MAX_LINES then
		lines[#lines + 1] = text
	end
end

local function QuestIcon(questID, offer)
	-- Blizzard's world quest helper indexes the tag info unchecked; it's nil until the quest is cached.
	local tagInfo = C_QuestLog.IsWorldQuest(questID) and C_QuestLog.GetQuestTagInfo(questID)
	if tagInfo then
		return { atlas = QuestUtil.GetWorldQuestAtlasInfo(questID, tagInfo, false) }
	end
	if offer then
		return Asset(QuestUtil.GetQuestIconOfferForQuestID(questID))
	end
	return Asset(QuestUtil.GetQuestIconActiveForQuestID(questID))
end

-- Unfinished objectives first; a finished quest shows its turn-in text instead.
local function QuestLines(questID)
	local lines = {}
	if C_QuestLog.IsComplete(questID) then
		local index = C_QuestLog.GetLogIndexForQuestID(questID)
		local text = index and GetQuestLogCompletionText(index)
		AddLine(lines, (text and text ~= "") and text or "Ready for turn-in")
		return lines
	end
	for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		if not objective.finished then
			AddLine(lines, objective.text)
		end
	end
	return lines
end

local function Quest(questID)
	return {
		kind = "quest",
		questID = questID,
		name = C_QuestLog.GetTitleForQuestID(questID) or ItemName(),
		icon = QuestIcon(questID) or ICON_DEFAULT,
		lines = QuestLines(questID),
	}
end

-- A step of a portal route (Router.lua) stands in for the pin: the step, the next way on, and where it ends.
local function RouteStep(step)
	local icon = ICON_DEFAULT
	local atlas = PORTAL_ATLAS[UnitFactionGroup("player")]
	if atlas and step.text:lower():find("portal") and C_Texture.GetAtlasInfo(atlas) then
		icon = { atlas = atlas }
	end
	local target = { kind = "route", name = step.text, icon = icon, lines = {} }
	if step.nextText then
		AddLine(target.lines, "Then: " .. step.nextText)
	end
	AddLine(target.lines, "On the way to your pin in " .. step.destName)
	return target
end

local function UserWaypoint()
	local step = ns.WayRouter_Step and ns.WayRouter_Step()
	if step and step.text then
		return RouteStep(step)
	end
	return { kind = "pin", name = ItemName() or "Map pin", icon = ICON_PIN, lines = {} }
end

local function HousingIcon(plotDataID)
	local ok, plots = pcall(C_HousingNeighborhood.GetNeighborhoodMapData)
	for _, plot in ipairs(ok and plots or {}) do
		if plot.plotDataID == plotDataID then
			return { atlas = HOUSING_ATLAS[plot.ownerType] or HOUSING_DEFAULT }
		end
	end
	return ICON_PIN
end

local function MapPin()
	local pinType, id = C_SuperTrack.GetSuperTrackedMapPin()
	local name, description = ItemName()
	local target = { kind = "mappin", name = name, icon = ICON_PIN, lines = {} }
	if pinType == PIN.AreaPOI and id then
		local info = C_AreaPoiInfo.GetAreaPOIInfo(nil, id)
		if info then
			target.name = info.name or name
			description = info.description or description
			if info.atlasName then
				target.icon = { atlas = info.atlasName }
			end
		end
	elseif pinType == PIN.QuestOffer and id then
		target.name = C_QuestLog.GetTitleForQuestID(id) or name
		target.icon = QuestIcon(id, true) or ICON_DEFAULT
		target.questID = nil -- not in the log yet: no quest area to hide in
	elseif pinType == PIN.TaxiNode then
		target.icon = ICON_TAXI
	elseif pinType == PIN.DigSite then
		target.icon = ICON_DIG
	elseif pinType == PIN.HousingPlot and id then
		target.icon = HousingIcon(id)
	end
	AddLine(target.lines, description)
	return target
end

local function Vignette()
	local guid = C_SuperTrack.GetSuperTrackedVignette()
	local info = guid and C_VignetteInfo.GetVignetteInfo(guid)
	return {
		kind = "vignette",
		name = info and info.name or ItemName(),
		icon = info and info.atlasName and { atlas = info.atlasName } or ICON_DEFAULT,
		lines = {},
	}
end

-- The tracked target, or nil when nothing is tracked.
function ns.WayTarget_Get()
	local trackType = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	if trackType == nil then
		return nil
	end
	local target
	if trackType == ST.Quest then
		local questID = C_SuperTrack.GetSuperTrackedQuestID()
		target = questID and Quest(questID)
	elseif trackType == ST.UserWaypoint then
		target = UserWaypoint()
	elseif trackType == ST.Corpse then
		target = { kind = "corpse", name = "Your corpse", icon = ICON_CORPSE, lines = {} }
	elseif trackType == ST.MapPin then
		target = MapPin()
	elseif trackType == ST.Vignette then
		target = Vignette()
	end
	if not target then
		local name, description = ItemName()
		target = { kind = "other", name = name, icon = ICON_DEFAULT, lines = {} }
		AddLine(target.lines, description)
	end
	target.name = target.name or ""

	-- A route step on the way (portal, boat, zone exit) replaces the name in the footer and leads the card.
	local mapID = C_Map.GetBestMapForUnit("player")
	if mapID then
		local _, _, description = C_Navigation.GetNextWaypointForMap(mapID)
		if description and description ~= "" then
			target.redirect = description
			table.insert(target.lines, 1, "|cffffd173" .. description .. "|r")
			target.lines[MAX_LINES + 1] = nil
		end
	end
	return target
end

-- Inside the tracked quest's area the objective tracker and the area itself take over.
function ns.WayTarget_InQuestArea(target)
	return target.questID ~= nil and C_Minimap.IsInsideQuestBlob(target.questID) == true
end
