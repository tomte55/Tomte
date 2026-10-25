local addonName, ns = ...

-- Waypoints module: replaces WaypointUI. Follows Blizzard's navigation frame (C_Navigation.GetFrame) with our own
-- marker, close-up card and edge arrow (or a compass of our own for a route step indoors), hides Blizzard's SuperTrackedFrame while on, and super-tracks map pins as
-- soon as they're placed. Pure logic is in Data.lua, target info in Target.lua, frames in Marker.lua, guard
-- directions in Guard.lua, portal routes to other continents in Router.lua (Route.lua, Network*.lua), the ping on
-- your arrow when the map opens in MapPing.lua. Here too: keys that cycle the focus through tracked quests, and
-- ns.Way_SetPoint for other modules. The update frame only runs while a navigation frame exists.

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
local timeText, timeRole -- the countdown of a timed target
local alpha, alphaGoal = 0, 1
local loadedAt = 0
local hooked

local events = ns.Way_Events
local OWNER = "way"
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

-- An indoor route step (Target.lua): the distance and arrow angle from your own position and facing, or nil when
-- they can't be read (another map, or secret values).
local function Compass()
	local spot = target and target.indoor
	if not spot then
		return nil
	end
	local x, y, _, map = UnitPosition("player")
	local facing = GetPlayerFacing()
	if not x or not facing or ns.IsSecret(x, y, map, facing) or map ~= spot.map then
		return nil
	end
	return ns.Way_Compass(x, y, facing, spot.x, spot.y)
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
	local compassDistance = Compass()
	if compassDistance then
		valid, distance = true, compassDistance
	end
	state = ns.Way_State({
		valid = valid,
		distance = distance,
		inQuestArea = ns.WayTarget_InQuestArea(target),
		offscreen = C_Navigation.WasClampedToScreen(),
		-- A countdown is a detail too: a timed target gets its card up close.
		hasDetails = #target.lines > 0 or (target.endsAt ~= nil and db.countdown),
		compass = compassDistance ~= nil,
	}, db)
	if state == "offscreen" and not db.arrow then
		state = "hidden"
	end
	local occluded = navState == Enum.NavigationState.Occluded and (state == "far" or state == "card")
	alphaGoal = occluded and OCCLUDED_ALPHA or 1

	local seconds = ns.Way_UpdateArrival(arrival, distance, GetTime())
	distanceText = ns.Way_FormatDistance(distance, db.metric)
	timeText, timeRole = nil, nil
	if db.countdown and target.endsAt then
		timeText, timeRole = ns.Way_TimeLeftText(ns.Way_TimeLeft(target.endsAt, GetServerTime()))
	end
	footer = ns.Way_FooterText(db.footer, distanceText, ns.Way_FormatArrival(seconds), target.redirect or target.name,
		timeText and ns.UI.Wrap(timeText, timeRole))
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
	if state == "compass" then
		local _, angle = Compass() -- every frame: the arrow turns with you
		if angle then
			alpha = math.min(alpha + dt / FADE_IN, alphaGoal)
			ns.WayMarker_SetAlpha(alpha * db.alpha)
			ns.WayMarker_ShowCompass(angle, footer)
		end
		return
	end
	local sx, sy = ns.WayMarker_NavPoint(navFrame)
	if not sx then
		ns.WayMarker_Hide()
		return
	end
	alpha = math.min(alpha + dt / FADE_IN, alphaGoal)
	ns.WayMarker_SetAlpha(alpha * db.alpha)
	ns.WayMarker_Show(state, navFrame, sx, sy, footer, distanceText, scale, timeText, timeRole)
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

ns.Way_TargetChanged = MarkDirty
events:On(OWNER, "SUPER_TRACKING_CHANGED", MarkDirty)
events:On(OWNER, "SUPER_TRACKING_PATH_UPDATED", MarkDirty)
events:On(OWNER, "QUEST_LOG_UPDATE", MarkDirty)
events:On(OWNER, "ZONE_CHANGED", MarkDirty)
events:On(OWNER, "ZONE_CHANGED_NEW_AREA", MarkDirty)
events:On(OWNER, "ZONE_CHANGED_INDOORS", MarkDirty)

events:On(OWNER, "NAVIGATION_FRAME_CREATED", function()
	Start()
end)

events:On(OWNER, "NAVIGATION_FRAME_DESTROYED", function()
	navFrame = nil
	ticker:Hide()
	ns.WayMarker_Hide()
end)

events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	loadedAt = GetTime()
	Start()
end)

-- A new map pin gets tracked right away (next frame, after the map's own handling), like WaypointUI.
events:On(OWNER, "USER_WAYPOINT_UPDATED", function()
	targetDirty = true
	if db.autoTrack and C_Map.HasUserWaypoint() and GetTime() - loadedAt > LOADING_GRACE then
		C_Timer.After(0, function()
			ns.SafeTrack(function()
				if module.active and C_Map.HasUserWaypoint() and not C_SuperTrack.IsSuperTrackingUserWaypoint() then
					C_SuperTrack.SetSuperTrackedUserWaypoint(true)
				end
			end)
		end)
	end
end)

local function ApplyLook()
	ns.WayMarker_Apply(db)
	targetDirty = true
end

local function ScaleChanged()
	ApplyLook()
end
events:On(OWNER, "UI_SCALE_CHANGED", ScaleChanged)
events:On(OWNER, "DISPLAY_SIZE_CHANGED", ScaleChanged)

-- Commands -------------------------------------------------------------------------------------------------

local function TestPin()
	if not ns.Module_RequireOn(module) then
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
	ns.TrackPin(mapID, x, y)
end

-- For other modules (Tips, Prey, ...): a map pin at x, y (0..1) on mapID, tracked, with a name for the marker and
-- card (the game's map pin carries none) and, optionally, opts.endsAt (server time, GetServerTime) for a countdown.
-- Places the pin with Waypoints off too (the game's own arrow then shows it). Prints nothing. Returns true when
-- placed now, false when it waits for the end of combat, nil when that map can't take a pin.
function ns.Way_SetPoint(mapID, x, y, title, opts)
	if not (mapID and x and y) or not C_Map.CanSetUserWaypointOnMap(mapID) then
		return nil
	end
	ns.WayTarget_NamePin({ mapID = mapID, x = x, y = y, title = title, endsAt = opts and opts.endsAt })
	MarkDirty()
	return ns.TrackPin(mapID, x, y)
end

-- "45.2 67.8", "45.2, 67.8" or TomTom's "#2248 45.2 67.8" (a map ID first). Text after the coordinates (TomTom's
-- description) names the pin. text: as typed (Core passes the fallback both lower-cased and raw).
local function PinAt(text, rawText)
	if not ns.Module_RequireOn(module) then
		return
	end
	text = rawText or text
	local mapID, rest = text:match("^#(%d+)%s+(.*)$")
	mapID = tonumber(mapID) or C_Map.GetBestMapForUnit("player")
	local x, y, title = (rest or text):match("^([%d.]+)[%s,]+([%d.]+)%s*(.-)%s*$")
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
	local now = ns.Way_SetPoint(mapID, x / 100, y / 100, title ~= "" and title or nil)
	local info = C_Map.GetMapInfo(mapID)
	ns.Print(("%s %.1f, %.1f in %s."):format(now and "tracking" or "after combat: tracking", x, y,
		info and info.name or ("map " .. mapID)))
end

-- Quest focus: the next or previous tracked quest becomes the one the marker (and the game's arrow) leads to.
local function WatchedQuests()
	local regular, world = {}, {}
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		regular[#regular + 1] = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
	end
	for i = 1, C_QuestLog.GetNumWorldQuestWatches() do
		world[#world + 1] = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
	end
	return ns.Way_WatchList(regular, world)
end

local function CycleFocus(step)
	local questID = ns.Way_CycleQuest(WatchedQuests(), C_SuperTrack.GetSuperTrackedQuestID(), step)
	if not questID then
		ns.Print("no tracked quests to focus.")
		return
	end
	ns.SafeTrack(function()
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end)
end

-- /way is TomTom's: Tomte claims it only when TomTom isn't loaded, and only once Waypoints is on (an off or blocked
-- module doesn't take a command name). TomTom loads after Tomte, so the check waits for PLAYER_LOGIN. A slash command
-- can't be taken back, so turning Waypoints off later leaves /way saying it's off. /tomte way <x> <y> always works.
local wayClaimed, waitingForLogin
local ClaimWay
events:On("login", "PLAYER_LOGIN", function()
	events:Unwatch("login", "PLAYER_LOGIN")
	waitingForLogin = false
	if module.active then
		ClaimWay()
	end
end)
function ClaimWay()
	if wayClaimed or waitingForLogin then
		return
	end
	if not IsLoggedIn() then
		waitingForLogin = true
		events:Watch("login", "PLAYER_LOGIN")
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
	ns.SafeTrack(function()
		if C_SuperTrack.IsSuperTrackingUserWaypoint() or C_Map.HasUserWaypoint() then
			C_Map.ClearUserWaypoint()
		end
		C_SuperTrack.ClearAllSuperTracked()
	end)
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

-- Settings previews (Panel/Preview.lua): a sample marker drawn by Marker.lua. A hovered Style choice (choosing) shows
-- its preset, what picking it would set; the row itself shows the settings as they are.
local LOOK_KEYS = { "style", "scale", "alpha", "beam", "beamAlpha", "footer", "card", "arrowScale", "metric",
	"countdown" }

local function Look(get, choosing)
	local s = {}
	for _, key in ipairs(LOOK_KEYS) do
		s[key] = get(key)
	end
	if choosing then
		ns.Way_ApplyStyle(s, s.style)
	end
	return s
end

local function MarkerPreview(host, get)
	return ns.WayMarker_DrawSample(host, Look(get), "far")
end

local function BothPreview(host, get, choosing)
	local s = Look(get, choosing)
	return ns.WayMarker_DrawSample(host, s, s.card and "both" or "far")
end

local function CardPreview(host, get)
	local s = Look(get)
	return ns.WayMarker_DrawSample(host, s, s.card and "card" or "far")
end

local function ArrowPreview(host, get)
	return ns.WayMarker_DrawSample(host, Look(get), "arrow")
end

-- "Use meters", for other modules' distances (Flight's Around rows).
function ns.Way_Metric()
	if not db then
		return true -- the setting's default
	end
	return db.metric
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("WAY_NEXT", "way", function()
	CycleFocus(1)
end)
ns.Binding_Add("WAY_PREV", "way", function()
	CycleFocus(-1)
end)
BINDING_NAME_TOMTE_WAY_NEXT = "Waypoints: focus the next tracked quest"
BINDING_NAME_TOMTE_WAY_PREV = "Waypoints: focus the previous tracked quest"

module = ns.RegisterModule({
	key = "way",
	conflicts = { { addon = "WaypointUI", why = "Waypoints stays off while it's enabled" } },
	replaces = { { addon = "Plumber", why = "the map ping on your arrow and the keys that cycle quest focus" } },
	name = "Waypoints",
	category = "travel",
	icon = 237381, -- inv_misc_map02
	summary = "A marker in the world that shows the way to what you track.",
	description = "An in-world marker for whatever you track: icon, beam, distance and arrival time, a close-up card "
		.. "with the objective, and an arrow at the screen edge when it's off-screen. Map pins are tracked as soon as "
		.. "you place them, world quests and events show a countdown, the map pings your arrow when it opens, and two "
		.. "keys cycle the focus through your tracked quests. Replaces WaypointUI.",
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
		guard = "ask",
		portals = true,
		routes = {}, -- per character GUID: the real map pin while a portal route has the pin on a step
		showWhenHidden = false,
		countdown = true,
		mapPing = true,
	},
	init = function(saved)
		db = saved
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
				events:Watch(OWNER, event)
			end
			HideBlizzard()
			Start()
			ClaimWay()
			ns.WayGuard_Toggle(true, db)
			ns.WayRouter_Toggle(db.portals, db)
			ns.WayPing_Toggle(db.mapPing)
		else
			ns.WayGuard_Toggle(false, db)
			ns.WayRouter_Toggle(false, db)
			ns.WayPing_Toggle(false)
			events:UnwatchAll(OWNER)
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
		{ "route", "show the portal route to a map pin on another continent", function()
			if ns.Module_RequireOn(module) then
				ns.WayRouter_Print()
			end
		end },
		{ "next", "focus the next tracked quest (also a key binding)", function()
			CycleFocus(1)
		end },
		{ "prev", "focus the previous tracked quest (also a key binding)", function()
			CycleFocus(-1)
		end },
		{ "ping", "ping your arrow on the open world map", function()
			if not ns.WayPing_Play() then
				ns.Print("open the world map on the zone you're in first.")
			end
		end },
	},
	fallbackCommand = { "<x> <y> [name]", "pin and track a spot on this map (also /way <x> <y> when TomTom isn't loaded)",
		PinAt, pattern = "^[#%d.]" },
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
			end, preview = BothPreview },
		{ type = "slider", key = "scale", label = "Marker size", min = 0.6, max = 1.6, step = 0.05, format = Times,
			onChange = ApplyLook, preview = BothPreview },
		{ type = "slider", key = "alpha", label = "Opacity", min = 0.3, max = 1, step = 0.05, format = Percent,
			onChange = ApplyLook, preview = MarkerPreview },
		{ type = "checkbox", key = "beam", label = "Beam", onChange = ApplyLook, preview = MarkerPreview,
			tooltip = "A light rising from the marker, easy to spot from far away." },
		{ type = "slider", key = "beamAlpha", label = "Beam opacity", min = 0.1, max = 1, step = 0.05, format = Percent,
			onChange = ApplyLook, parent = "beam", preview = MarkerPreview },
		{ type = "dropdown", key = "footer", label = "Text under the marker", preview = MarkerPreview,
			choices = function()
				local list = {}
				for i, key in ipairs(ns.WAY_FOOTERS) do
					list[i] = { value = key, text = ns.WAY_FOOTER_NAMES[key] }
				end
				return list
			end },

		{ type = "header", label = "Close up" },
		{ type = "checkbox", key = "card", label = "Close-up card", onChange = ApplyLook, preview = CardPreview,
			tooltip = "Near the target, show a card with its name, objectives and distance instead of the marker." },
		{ type = "slider", key = "cardDistance", label = "Card within", min = 50, max = 500, step = 5,
			format = DistanceFormat, parent = "card" },
		{ type = "slider", key = "hideDistance", label = "Hide within", min = 5, max = 100, step = 5,
			format = DistanceFormat, tooltip = "Hide the marker when you're this close. It also hides inside the "
				.. "tracked quest's area." },

		{ type = "header", label = "Edge arrow" },
		{ type = "checkbox", key = "arrow", label = "Edge arrow", preview = ns.Preview_When("arrow", ArrowPreview),
			tooltip = "When the target is off-screen, an arrow near the screen edge points toward it." },
		{ type = "slider", key = "arrowScale", label = "Arrow size", min = 0.6, max = 1.6, step = 0.05, format = Times,
			onChange = ApplyLook, parent = "arrow", preview = ns.Preview_When("arrow", ArrowPreview) },

		{ type = "header", label = "General" },
		{ type = "checkbox", key = "metric", label = "Use meters", onChange = Refresh, preview = MarkerPreview },
		{ type = "checkbox", key = "autoTrack", label = "Track map pins when placed",
			tooltip = "Placing a pin on the world map tracks it right away." },
		{ type = "checkbox", key = "portals", label = "Route to other continents",
			onChange = function()
				ns.WayRouter_Toggle(module.active and db.portals, db)
			end,
			tooltip = "A map pin on another continent gets no navigation from the game. Tomte moves the pin to each "
				.. "portal, zeppelin or boat on the way, using the same network the game uses for quests, and puts "
				.. "your pin back once you're on its continent. /tomte way route shows the whole route." },
		{ type = "dropdown", key = "guard", label = "Waypoint for guard directions",
			tooltip = "When a guard shows you the way, place and track a map pin there. Ask: a Yes/No question first.",
			choices = function()
				local list = {}
				for i, key in ipairs(ns.WAY_GUARD_MODES) do
					list[i] = { value = key, text = ns.WAY_GUARD_NAMES[key] }
				end
				return list
			end },
		{ type = "checkbox", key = "showWhenHidden", label = "Show when the UI is hidden", onChange = ApplyLook,
			tooltip = "Keep the marker visible after Alt+Z." },
		{ type = "checkbox", key = "countdown", label = "Countdown on timed waypoints", onChange = ApplyLook,
			preview = BothPreview,
			tooltip = "World quests and events that end soon show the time left under the marker and on the card." },
		{ type = "checkbox", key = "mapPing", label = "Ping your arrow when the map opens",
			onChange = function()
				ns.WayPing_Toggle(module.active and db.mapPing)
			end,
			tooltip = "Rings spread out from where you stand for a moment, so you find yourself on the map." },
		{ type = "button", label = "Pin ahead of you", text = "Test", onClick = TestPin,
			tooltip = ("Places a map pin about %d yards ahead and tracks it."):format(TEST_DISTANCE) },
		{ type = "button", label = "Stop tracking", text = "Clear", onClick = Clear },
	},
})
