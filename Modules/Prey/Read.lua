local addonName, ns = ...

-- Prey: reads the game for the page, the Hunt Table and the waypoint: the active hunt (C_QuestLog.GetActivePreyQuest),
-- its hunt progress widget (the trail's state, from the widget Blizzard draws for it), the journey rank, this week's
-- hunts and the achievement collection. Also the waypoint to the active prey. Creates the module's event bus
-- (ns.Prey_Events); pure rules in Data.lua, registered in Prey.lua.

local WAYPOINT_DELAY = 0.5 -- after Blizzard's own click on the hunt icon has opened the map and pinged the quest

local events = ns.NewEvents()
ns.Prey_Events = events
local OWNER = "read"
local PING_OWNER = {} -- our own key in Blizzard's EventRegistry (a string could clash with another addon's)

local widgetID -- the hunt progress widget, once seen
local watchingWidgets = false

local function Def()
	return ns.Content_Get(ns.ContentExpansion(), "prey")
end
ns.Prey_Def = Def

local function PreyWidgetType()
	return Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.PreyHuntProgress
end

-- The hunt progress widget among the sets Blizzard shows it in (power bar, top center, under the minimap, quest
-- tracker); nil when none is up.
local function FindWidget()
	local kind = PreyWidgetType()
	if not kind then
		return nil
	end
	local m = C_UIWidgetManager
	for _, getter in ipairs({ m.GetPowerBarWidgetSetID, m.GetTopCenterWidgetSetID, m.GetBelowMinimapWidgetSetID,
		m.GetObjectiveTrackerWidgetSetID }) do
		local setID = getter and getter()
		for _, w in ipairs(setID and m.GetAllWidgetsBySetID(setID) or {}) do
			if w.widgetType == kind then
				return w.widgetID
			end
		end
	end
	return nil
end

-- The trail: progressState (Enum.PreyHuntProgressState) and Blizzard's tooltip text; nil when it isn't shown.
local function ReadWidget()
	widgetID = widgetID or FindWidget()
	local info = widgetID and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widgetID)
	if not info or ns.IsSecret(info.shownState, info.progressState) then
		return nil
	end
	if Enum.WidgetShownState and info.shownState == Enum.WidgetShownState.Hidden then
		return nil
	end
	local tip = not ns.IsSecret(info.tooltip) and info.tooltip or nil
	return info.progressState, tip ~= "" and tip or nil
end

-- The active hunt: { questID, title, mapID, mapName, state, tip, ready } or nil.
function ns.PreyRead_Active()
	local questID = C_QuestLog.GetActivePreyQuest()
	if not questID or ns.IsSecret(questID) or questID == 0 then
		return nil
	end
	local a = { questID = questID, title = C_QuestLog.GetTitleForQuestID(questID) }
	local mapID = GetQuestUiMapID(questID, true) -- true: the quest's own map, not a waypoint's (as Blizzard's widget)
	if mapID and not ns.IsSecret(mapID) and mapID > 0 then
		local info = C_Map.GetMapInfo(mapID)
		a.mapID, a.mapName = mapID, info and info.name or nil
	end
	a.ready = C_QuestLog.ReadyForTurnIn(questID) == true
	a.state, a.tip = ReadWidget()
	return a
end

-- Journey rank and the journey's name; nil when the game doesn't know the faction.
function ns.PreyRead_Rank(def)
	def = def or Def()
	if not (def and def.journey) then
		return nil
	end
	local data = C_MajorFactions.GetMajorFactionData(def.journey)
	if data and data.renownLevel and not ns.IsSecret(data.renownLevel) then
		return data.renownLevel, data.name
	end
	local level = C_MajorFactions.GetCurrentRenownLevel(def.journey)
	if level and not ns.IsSecret(level) then
		return level, nil
	end
	return nil
end

local function IsDone(questID)
	return C_QuestLog.IsQuestFlaggedCompleted(questID)
end

local function CriteriaDone(achievement, criteria)
	local _, _, completed = GetAchievementCriteriaInfoByID(achievement, criteria)
	return completed == true
end
ns.PreyRead_CriteriaDone = CriteriaDone

-- Everything the page shows: { def, active, rank, journeyName, week, collection }.
function ns.PreyRead_State()
	local def = Def()
	local rank, journeyName = ns.PreyRead_Rank(def)
	return {
		def = def, active = ns.PreyRead_Active(), rank = rank, journeyName = journeyName,
		week = ns.Prey_Week(def, rank, IsDone), collection = ns.Prey_Collection(def, CriteriaDone),
	}
end

function ns.PreyRead_Week(def, rank)
	return ns.Prey_Week(def, rank, IsDone)
end

-- Waypoint --------------------------------------------------------------------------------------------------------

-- A point on the map for the active prey, through Waypoints (ns.Way_SetPoint, Modules/Travel) when it's there, else
-- a map pin. While the prey's place isn't revealed yet, the quest is super-tracked instead (Blizzard's arrow leads
-- to its area). quiet: no chat line (the hunt icon click).
function ns.Prey_SetWaypoint(quiet)
	local a = ns.PreyRead_Active()
	if not a then
		if not quiet then
			ns.Print("no prey hunt active. Pick a target at the Hunt Table.")
		end
		return
	end
	local mapID, x, y = a.mapID, nil, nil
	if mapID then
		x, y = ns.Prey_FindOnMap(C_QuestLog.GetQuestsOnMap(mapID), a.questID)
	end
	if not x then
		local m, wx, wy = C_QuestLog.GetNextWaypoint(a.questID)
		if m and not ns.IsSecret(m, wx, wy) then
			mapID, x, y = m, wx, wy
		end
	end
	local title = a.title or "Prey"
	if x and mapID and not ns.IsSecret(x, y) then
		local setPoint = ns.Way_SetPoint -- Waypoints (Modules/Travel), looked up now: it may be off or not loaded
		if setPoint then
			setPoint(mapID, x, y, title)
		elseif C_Map.CanSetUserWaypointOnMap(mapID) then
			ns.TrackPin(mapID, x, y)
		end
		if not quiet then
			local info = C_Map.GetMapInfo(mapID)
			ns.Print(("waypoint to %s, %s %.1f %.1f"):format(title, info and info.name or "?", x * 100, y * 100))
		end
		return
	end
	local questID = a.questID
	ns.SafeTrack(function()
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end)
	if not quiet then
		ns.Print(("tracking %s; its exact place shows once the trail is hot."):format(title))
	end
end

-- Blizzard's hunt icon, clicked in its final state, opens the map and pings the prey quest (Blizzard_UIWidgets
-- PreyHuntProgress); the waypoint follows a moment later so the ping is seen first. Plumber's PreyQuestSuperTrack
-- tells the icon apart the same way (by its progressState).
local function OnPing(_, questID)
	if not ns.Prey_WidgetWaypoint() then
		return
	end
	-- Quest log and tracker POI buttons ping the same quest; only the hunt icon's frame carries progressState.
	local focus = GetMouseFoci()[1]
	local progressState = focus and focus.progressState
	if not (ns.IsSecret(progressState) or progressState ~= nil) then
		return
	end
	local active = C_QuestLog.GetActivePreyQuest()
	if active and not ns.IsSecret(active) and active == questID then
		C_Timer.After(WAYPOINT_DELAY, function()
			if ns.Prey_WidgetWaypoint() then
				ns.Prey_SetWaypoint(true)
			end
		end)
	end
end

-- Events ----------------------------------------------------------------------------------------------------------

local function Changed()
	if ns.Prey_Changed then
		ns.Prey_Changed()
	end
end

-- UPDATE_UI_WIDGET fires for every widget everywhere: watched only while a hunt is active.
local function WatchWidgets()
	local questID = C_QuestLog.GetActivePreyQuest()
	local want = ns.IsSecret(questID) or (questID ~= nil and questID ~= 0) -- 0 like PreyRead_Active: no hunt
	if want ~= watchingWidgets then
		watchingWidgets = want
		if want then
			events:Watch(OWNER, "UPDATE_UI_WIDGET")
		else
			events:Unwatch(OWNER, "UPDATE_UI_WIDGET")
			widgetID = nil
		end
	end
end

events:On(OWNER, "UPDATE_UI_WIDGET", function(_, info)
	if info and info.widgetType == PreyWidgetType() then
		widgetID = info.widgetID
		Changed()
	end
end)

for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
	events:On(OWNER, event, function()
		WatchWidgets()
		Changed()
	end)
end

events:On(OWNER, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", Changed)

function ns.PreyRead_Start()
	for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD",
		"MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }) do
		events:Watch(OWNER, event)
	end
	EventRegistry:RegisterCallback("MapCanvas.PingQuestID", OnPing, PING_OWNER)
	WatchWidgets()
end

function ns.PreyRead_Stop()
	events:UnwatchAll(OWNER)
	EventRegistry:UnregisterCallback("MapCanvas.PingQuestID", PING_OWNER)
	watchingWidgets, widgetID = false, nil
end
