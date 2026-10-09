local addonName, ns = ...

-- Waypoints module: replaces WaypointUI. Follows Blizzard's navigation frame (C_Navigation.GetFrame) with our own
-- marker, close-up card and edge arrow, hides Blizzard's SuperTrackedFrame while on, and super-tracks map pins as
-- soon as they're placed. Pure logic is in Data.lua, target info in Target.lua, frames in Marker.lua.
-- The update frame only runs while a navigation frame exists.

local TICK = 0.1 -- seconds between distance/state/text updates (position updates every frame)
local FADE_IN = 0.25 -- seconds to fade in after the target changes
local OCCLUDED_ALPHA = 0.6 -- target behind terrain or a wall (Blizzard uses the same)
local LOADING_GRACE = 3 -- seconds after a loading screen when a USER_WAYPOINT_UPDATED isn't a new pin
local TEST_DISTANCE = 150 -- yards ahead of the player for /tomte way test
local EVENTS = {
	"SUPER_TRACKING_CHANGED", "SUPER_TRACKING_PATH_UPDATED", "QUEST_LOG_UPDATE", "USER_WAYPOINT_UPDATED",
	"NAVIGATION_FRAME_CREATED", "NAVIGATION_FRAME_DESTROYED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED",
	"ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
}

local module, db
local navFrame
local target -- from ns.WayTarget_Get, or nil
local targetDirty = true
local arrival = ns.Way_NewArrival()
local elapsed = 0
local state, footer, distanceText, scale = "none", nil, nil, 1
local alpha, alphaGoal = 0, 1
local loadedAt = 0
local hooked

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

-- Blizzard's marker ----------------------------------------------------------------------------------------

-- Blizzard re-shows it through SetShown when a navigation frame is created, so both are hooked. It isn't protected;
-- hiding it keeps its OnEvent (which clears tracking on arrival) running.
local function HideBlizzard()
	if module.active and SuperTrackedFrame:IsShown() then
		SuperTrackedFrame:Hide()
	end
end

local function HookBlizzard()
	if hooked or not SuperTrackedFrame then
		return
	end
	hooked = true
	hooksecurefunc(SuperTrackedFrame, "Show", HideBlizzard)
	hooksecurefunc(SuperTrackedFrame, "SetShown", HideBlizzard)
end

-- Update loop ----------------------------------------------------------------------------------------------

local function RefreshTarget()
	targetDirty = false
	local previous = target
	target = ns.WayTarget_Get()
	if target then
		ns.WayMarker_SetTarget(target)
	end
	local changed = (previous and previous.name) ~= (target and target.name)
		or (previous and previous.kind) ~= (target and target.kind)
	if changed then
		arrival = ns.Way_NewArrival()
		alpha = 0
	end
end

local function UpdateInfo()
	if targetDirty then
		RefreshTarget()
	end
	if not target or not navFrame then
		state = "none"
		return
	end
	local navState = C_Navigation.GetTargetState()
	local valid = C_Navigation.HasValidScreenPosition()
		and navState ~= Enum.NavigationState.Invalid and navState ~= Enum.NavigationState.Disabled
	local distance = C_Navigation.GetDistance()
	state = ns.Way_State({
		valid = valid,
		distance = distance,
		inQuestArea = ns.WayTarget_InQuestArea(target),
		offscreen = C_Navigation.WasClampedToScreen(),
		hasDetails = #target.lines > 0,
	}, db)
	if state == "offscreen" and not db.arrow then
		state = "hidden"
	end
	alphaGoal = (navState == Enum.NavigationState.Occluded and state ~= "offscreen") and OCCLUDED_ALPHA or 1

	local seconds = ns.Way_UpdateArrival(arrival, distance, GetTime())
	distanceText = ns.Way_FormatDistance(distance, db.metric)
	footer = ns.Way_FooterText(db.footer, distanceText, ns.Way_FormatArrival(seconds), target.redirect or target.name)
	scale = ns.Way_DistanceScale(distance)
end

local function OnUpdate(_, dt)
	elapsed = elapsed + dt
	if elapsed >= TICK then
		elapsed = 0
		UpdateInfo()
	end
	if state == "none" or state == "hidden" then
		ns.WayMarker_Hide()
		alpha = 0 -- fade in again when it comes back
		return
	end
	local sx, sy = ns.WayMarker_NavPoint(navFrame)
	if not sx then
		ns.WayMarker_Hide()
		return
	end
	alpha = math.min(alpha + dt / FADE_IN, alphaGoal)
	if alpha > alphaGoal then
		alpha = alphaGoal
	end
	ns.WayMarker_SetAlpha(alpha * db.alpha)
	ns.WayMarker_Show(state, navFrame, sx, sy, footer, distanceText, scale)
end
ticker:SetScript("OnUpdate", OnUpdate)

local function Start()
	navFrame = C_Navigation.GetFrame()
	targetDirty = true
	elapsed = TICK -- update info on the first frame
	ticker:SetShown(navFrame ~= nil)
	if not navFrame then
		ns.WayMarker_Hide()
	end
end

-- Events ---------------------------------------------------------------------------------------------------

local function MarkDirty()
	targetDirty = true
	elapsed = TICK -- don't leave the old name up while the navigation frame already moved
end

events.SUPER_TRACKING_CHANGED = MarkDirty
events.SUPER_TRACKING_PATH_UPDATED = MarkDirty
events.QUEST_LOG_UPDATE = MarkDirty
events.ZONE_CHANGED = MarkDirty
events.ZONE_CHANGED_NEW_AREA = MarkDirty
events.ZONE_CHANGED_INDOORS = MarkDirty

function events:NAVIGATION_FRAME_CREATED()
	Start()
end

function events:NAVIGATION_FRAME_DESTROYED()
	navFrame = nil
	ticker:Hide()
	ns.WayMarker_Hide()
end

function events:PLAYER_ENTERING_WORLD()
	loadedAt = GetTime()
	Start()
end

-- A new map pin gets tracked right away (next frame, after the map's own handling), like WaypointUI.
function events:USER_WAYPOINT_UPDATED()
	targetDirty = true
	if db.autoTrack and C_Map.HasUserWaypoint() and GetTime() - loadedAt > LOADING_GRACE then
		C_Timer.After(0, function()
			if module.active and C_Map.HasUserWaypoint() and not C_SuperTrack.IsSuperTrackingUserWaypoint() then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		end)
	end
end

local function ApplyLook()
	ns.WayMarker_Apply(db)
	targetDirty = true
end

function events:UI_SCALE_CHANGED()
	ApplyLook()
end
events.DISPLAY_SIZE_CHANGED = events.UI_SCALE_CHANGED

-- Commands -------------------------------------------------------------------------------------------------

local function RequireActive()
	if not module.active then
		ns.Print("Waypoints is off. Turn it on in /tomte.")
		return false
	end
	return true
end

local function TestPin()
	if not RequireActive() then
		return
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos or not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print("can't place a map pin here.")
		return
	end
	local width, height = C_Map.GetMapWorldSize(mapID)
	local x, y = pos.x, pos.y
	local facing = GetPlayerFacing() or 0
	if width and width > 0 and height and height > 0 then
		-- Facing 0 is north; map y grows southward.
		x = x - math.sin(facing) * TEST_DISTANCE / width
		y = y - math.cos(facing) * TEST_DISTANCE / height
	end
	x, y = math.min(math.max(x, 0), 1), math.min(math.max(y, 0), 1)
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
end

-- "45.2 67.8", "45.2, 67.8" or TomTom's "#2248 45.2 67.8" (a map ID first). Anything after the coordinates
-- (TomTom's description) is ignored: a map pin can't carry a name.
local function PinAt(text)
	if not RequireActive() then
		return
	end
	local mapID, rest = text:match("^#(%d+)%s+(.*)$")
	mapID = tonumber(mapID) or C_Map.GetBestMapForUnit("player")
	local x, y = (rest or text):match("^([%d.]+)[%s,]+([%d.]+)")
	x, y = tonumber(x), tonumber(y)
	if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
		local cmd = SlashCmdList.TOMTEWAY and "/way" or "/tomte way"
		ns.Print(("usage: %s <x> <y>, for example %s 45.2 67.8 (or %s #mapID <x> <y>)."):format(cmd, cmd, cmd))
		return
	end
	if not mapID or not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print("can't place a map pin on that map.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	local info = C_Map.GetMapInfo(mapID)
	ns.Print(("tracking %.1f, %.1f in %s."):format(x, y, info and info.name or ("map " .. mapID)))
end

-- /way is TomTom's: Tomte claims it only when TomTom isn't loaded, and only once Waypoints is on (an off or blocked
-- module doesn't take a command name). TomTom loads after Tomte, so the check waits for PLAYER_LOGIN. A slash command
-- can't be taken back, so turning Waypoints off later leaves /way saying it's off. /tomte way <x> <y> always works.
local wayClaimed, waitingForLogin
local function ClaimWay()
	if wayClaimed or waitingForLogin then
		return
	end
	if not IsLoggedIn() then
		waitingForLogin = true
		local login = CreateFrame("Frame")
		login:RegisterEvent("PLAYER_LOGIN")
		login:SetScript("OnEvent", function(self)
			self:UnregisterAllEvents()
			waitingForLogin = false
			if module.active then
				ClaimWay()
			end
		end)
		return
	end
	wayClaimed = true
	if C_AddOns.IsAddOnLoaded("TomTom") then
		return
	end
	SLASH_TOMTEWAY1 = "/way"
	SlashCmdList.TOMTEWAY = function(msg)
		PinAt(strtrim(msg or ""))
	end
end

local function Clear()
	if C_SuperTrack.IsSuperTrackingUserWaypoint() or C_Map.HasUserWaypoint() then
		C_Map.ClearUserWaypoint()
	end
	C_SuperTrack.ClearAllSuperTracked()
end

-- Module ---------------------------------------------------------------------------------------------------

local function Refresh()
	ApplyLook()
	if ns.Panel_OpenModule then
		ns.Panel_OpenModule(module.key)
	end
end

local function DistanceFormat(v)
	return ns.Way_FormatSetting(v, db and db.metric)
end

local function Percent(v)
	return math.floor(v * 100 + 0.5) .. "%"
end

local function Times(v)
	return ("%.2f"):format(v)
end

module = ns.RegisterModule({
	key = "way",
	conflicts = { { addon = "WaypointUI", why = "Waypoints stays off while it's enabled" } },
	name = "Waypoints",
	category = "Travel",
	description = "An in-world marker for whatever you track: icon, beam, distance and arrival time, a close-up card "
		.. "with the objective, and an arrow at the screen edge when it's off-screen. Map pins are tracked as soon as "
		.. "you place them. Replaces WaypointUI.",
	enabledByDefault = true,
	defaults = {
		style = "classic",
		scale = 1,
		alpha = 1,
		beam = true,
		beamAlpha = 0.8,
		footer = "all",
		card = true,
		cardDistance = 110, -- yards (~100 m)
		hideDistance = 25, -- yards
		arrow = true,
		arrowScale = 1,
		metric = true,
		autoTrack = true,
		showWhenHidden = false,
	},
	init = function(saved)
		db = saved
		if db.cardDistance == 325 then
			db.cardDistance = 110 -- the first test build's default was too far out
		end
	end,
	blocked = function()
		if C_AddOns.IsAddOnLoaded("WaypointUI") then
			return "The WaypointUI addon is still enabled. Disable it and /reload to switch over."
		end
	end,
	toggle = function(active)
		if active then
			HookBlizzard()
			ApplyLook()
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			HideBlizzard()
			Start()
			ClaimWay()
		else
			events:UnregisterAllEvents()
			ticker:Hide()
			ns.WayMarker_Hide()
			navFrame, target = nil, nil
			if SuperTrackedFrame and C_Navigation.GetFrame() then
				SuperTrackedFrame:Show()
			end
		end
	end,
	commands = {
		{ "test", "place a map pin ahead of you and track it", TestPin },
		{ "clear", "stop tracking (and remove the map pin)", Clear },
	},
	fallbackCommand = { "<x> <y>", "pin and track a spot on this map (also /way <x> <y> when TomTom isn't loaded)", PinAt, pattern = "^[#%d.]" },
	options = {
		{ type = "header", label = "Look" },
		{ type = "dropdown", key = "style", label = "Style",
			tooltip = "Classic: beam, name, distance and arrival time, full card up close. Minimal: no beam, just the "
				.. "distance, a compact card. Sets the options below; you can still change each one.",
			choices = function()
				local list = {}
				for i, key in ipairs(ns.WAY_STYLE_ORDER) do
					list[i] = { value = key, text = ns.WAY_STYLE_NAMES[key] }
				end
				return list
			end, onChange = function(value)
				ns.Way_ApplyStyle(db, value)
				Refresh()
			end },
		{ type = "slider", key = "scale", label = "Marker size", min = 0.6, max = 1.6, step = 0.05, format = Times,
			onChange = ApplyLook },
		{ type = "slider", key = "alpha", label = "Opacity", min = 0.3, max = 1, step = 0.05, format = Percent,
			onChange = ApplyLook },
		{ type = "checkbox", key = "beam", label = "Beam", onChange = ApplyLook,
			tooltip = "A light rising from the marker, easy to spot from far away." },
		{ type = "slider", key = "beamAlpha", label = "Beam opacity", min = 0.1, max = 1, step = 0.05, format = Percent,
			onChange = ApplyLook },
		{ type = "dropdown", key = "footer", label = "Text under the marker",
			choices = function()
				local list = {}
				for i, key in ipairs(ns.WAY_FOOTERS) do
					list[i] = { value = key, text = ns.WAY_FOOTER_NAMES[key] }
				end
				return list
			end },

		{ type = "header", label = "Close up" },
		{ type = "checkbox", key = "card", label = "Close-up card", onChange = ApplyLook,
			tooltip = "Near the target, show a card with its name, objectives and distance instead of the marker." },
		{ type = "slider", key = "cardDistance", label = "Card within", min = 50, max = 500, step = 5,
			format = DistanceFormat },
		{ type = "slider", key = "hideDistance", label = "Hide within", min = 5, max = 100, step = 5,
			format = DistanceFormat, tooltip = "Hide the marker when you're this close. It also hides inside the "
				.. "tracked quest's area." },

		{ type = "header", label = "Edge arrow" },
		{ type = "checkbox", key = "arrow", label = "Edge arrow",
			tooltip = "When the target is off-screen, an arrow near the screen edge points toward it." },
		{ type = "slider", key = "arrowScale", label = "Arrow size", min = 0.6, max = 1.6, step = 0.05, format = Times,
			onChange = ApplyLook },

		{ type = "header", label = "General" },
		{ type = "checkbox", key = "metric", label = "Use meters", onChange = Refresh },
		{ type = "checkbox", key = "autoTrack", label = "Track map pins when placed",
			tooltip = "Placing a pin on the world map tracks it right away." },
		{ type = "checkbox", key = "showWhenHidden", label = "Show when the UI is hidden", onChange = ApplyLook,
			tooltip = "Keep the marker visible after Alt+Z." },
		{ type = "button", label = "Pin ahead of you", text = "Test", onClick = TestPin,
			tooltip = ("Places a map pin about %d yards ahead and tracks it."):format(TEST_DISTANCE) },
		{ type = "button", label = "Stop tracking", text = "Clear", onClick = Clear },
	},
})
