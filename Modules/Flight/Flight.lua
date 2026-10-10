local addonName, ns = ...

-- Flight Timer module: times flight paths account-wide, shows a countdown bar and drives the cinematic
-- flight scene. Pure logic is in Data.lua. Nothing ticks on the ground: the ticker frame is only shown
-- while a picked route waits for takeoff or a flight is in progress.

local TICK = 0.2 -- seconds between taxi/position checks
local START_TIMEOUT = 10 -- seconds to wait for the taxi to start after TakeTaxiNode
local MAX_RESUME_AGE = 3600 -- don't resume a saved flight older than this
local LOADING_GRACE = 3 -- seconds after a loading screen before UnitOnTaxi is trusted again
local ALERT_SOUND = SOUNDKIT.ALARM_CLOCK_WARNING_3
local ALERT_GAP = 0.2 -- seconds between the two dings
local PREVIEW_SECONDS = 15
local EVENTS = { "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }

local module
local pending -- route picked on the taxi map, waiting for UnitOnTaxi
local flight -- active flight (same table as ns.flightDB.current)
local tracker
local landing = {} -- ns.UpdateLanding state
local loadingUntil = 0 -- GetTime() before which off-taxi readings are ignored
local hooked
local previewHandle

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

-- Resolves the hop path to a destination slot. Only valid while the taxi map is open.
function ns.BuildRoute(destSlot)
	local mapID = GetTaxiMapID()
	if not mapID then
		return nil
	end
	local bySlot = {}
	for _, info in ipairs(C_TaxiMap.GetAllTaxiNodes(mapID)) do
		bySlot[info.slotIndex] = info
	end
	local numHops = GetNumRoutes(destSlot)
	if not numHops or numHops < 1 then
		return nil
	end
	local nodes = { bySlot[TaxiGetNodeSlot(destSlot, 1, true)] }
	if not nodes[1] then
		return nil
	end
	for hop = 1, numHops do
		local info = bySlot[TaxiGetNodeSlot(destSlot, hop, false)]
		if not info then
			return nil
		end
		nodes[hop + 1] = info
	end

	local route = {
		mapID = mapID,
		path = {},
		points = {},
		originName = nodes[1].name,
		destName = nodes[#nodes].name,
		cost = TaxiNodeCost(destSlot),
	}
	for i, info in ipairs(nodes) do
		route.path[i] = info.nodeID
		local x, y = info.position:GetXY()
		if i == 1 then
			route.origin = { x = x, y = y }
		elseif i == #nodes then
			route.dest = { x = x, y = y }
		elseif i > 1 then
			route.points[#route.points + 1] = { index = i, x = x, y = y, name = info.name }
		end
	end
	return route
end

local function PlayAlert()
	PlaySound(ALERT_SOUND, "Master")
	C_Timer.After(ALERT_GAP, function()
		PlaySound(ALERT_SOUND, "Master")
	end)
	FlashClientIcon()
end

local function ResetTimes()
	local db = ns.flightDB
	wipe(db.routes)
	wipe(db.hops)
	wipe(db.paces)
	db.calibration.offset, db.calibration.samples = 0, 0
	ns.Print("all recorded flight times cleared.")
end

local function ResetStats()
	ns.flightDB.stats = nil
	ns.InitDB(ns.flightDB)
	ns.Print("flight stats cleared.")
end

local function PrintStats()
	local st = ns.flightDB.stats
	ns.Print("flight stats")
	print(("  Flights: %d   In the air: %s   Gold spent: %s"):format(
		st.flights, ns.FormatTime(st.seconds), C_CurrencyInfo.GetCoinTextureString(st.copper)))
	if st.longest > 0 then
		print(("  Longest: %s (%s)"):format(st.longestRoute, ns.FormatTime(st.longest)))
	end
	local visited, visits = ns.TopEntry(st.departures)
	if visited then
		print(("  Most visited: %s (%d departures)"):format(visited, visits))
	end
	local route, count = ns.TopEntry(st.routeCounts)
	if route then
		print(("  Most flown: %s (%d times)"):format(route, count))
	end
	for mapID, seconds in pairs(st.byMap) do
		local info = C_Map.GetMapInfo(mapID)
		print(("  %s: %s"):format(info and info.name or ("Map " .. mapID), ns.FormatTime(seconds)))
	end
end

local function StopPreview()
	if previewHandle then
		StopSound(previewHandle, 1500)
		previewHandle = nil
	end
end

local function PreviewMusic()
	if previewHandle then
		StopPreview()
		return
	end
	local track = ns.MUSIC_TRACKS[ns.flightDB.musicTrack] or ns.MUSIC_TRACKS[1]
	local kit = SOUNDKIT[track.kit]
	if not kit then
		return
	end
	local _, handle = PlaySound(kit, "Master")
	previewHandle = handle
	C_Timer.After(PREVIEW_SECONDS, function()
		if previewHandle == handle then
			StopPreview()
		end
	end)
end

local function PlayerPos(mapID)
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		return pos:GetXY()
	end
end

local function StartFlight(route, startTime)
	local db = ns.flightDB
	flight = route
	flight.start = startTime
	flight.passes = flight.passes or {}
	local remaining = {}
	for _, p in ipairs(flight.points) do
		if not flight.passes[p.index] then
			remaining[#remaining + 1] = p
		end
	end
	tracker = ns.NewPassTracker(remaining)
	tracker.passes = flight.passes
	landing.offSince = nil
	db.current = flight
	local expected, isEstimate, raw, rough = ns.LookupTime(db, flight.path, flight)
	flight.expected = expected
	flight.isEstimate = isEstimate
	-- Only hop-based estimates feed calibration; pace-based ones already include takeoff/landing.
	flight.rawEstimate = isEstimate and not rough and raw or nil
	flight.stops = expected and ns.StopFractions(db, flight) or nil
	ns.Bar_Start(flight.destName, expected, isEstimate, flight.start, flight.stops)
	ticker:Show()
end

-- Once per flight: 5s before a known landing, or on landing when the time was unknown.
local function Alert()
	flight.alerted = true
	if ns.flightDB.alert then
		PlayAlert()
	end
end

local function EndFlight(endTime)
	local db = ns.flightDB
	local duration = endTime - flight.start
	local distance
	local x, y = PlayerPos(flight.mapID)
	if x then
		local dx, dy = x - flight.dest.x, y - flight.dest.y
		distance = math.sqrt(dx * dx + dy * dy)
	end
	if ns.IsArrival(distance, duration, flight.expected) then
		if flight.rawEstimate then
			ns.CalibrateEstimate(db, flight.rawEstimate, duration)
		end
		ns.RecordFlight(db, flight.path, duration, flight.passes)
		ns.RecordPace(db, flight, duration)
		ns.RecordStats(db, duration, (flight.originName or "?") .. " to " .. flight.destName, flight.originName, flight.mapID)
	end
	if not flight.alerted then
		Alert()
	end
	ns.Cinematic.Release(flight)
	flight, tracker = nil, nil
	db.current = nil
	ns.Bar_Stop()
end

-- Built only when the cinematic actually starts, so the tick allocates nothing.
local function CinematicOptions(elapsed)
	local db = ns.flightDB
	return {
		orbit = db.orbit,
		showcase = db.showcase,
		music = db.music and db.musicTrack or nil,
		resumeDelay = db.resumeDelay,
		-- Resumed during the arrival shot (after /reload): don't zoom out just to zoom straight back in.
		skipCamera = ns.OrbitFactor(flight.expected, elapsed) < 1,
	}
end

local function Tick()
	local db = ns.flightDB
	if pending then
		if UnitOnTaxi("player") then
			local route = pending
			pending = nil
			db.stats.copper = db.stats.copper + (route.cost or 0)
			StartFlight(route, GetTime())
		elseif GetTime() - pending.requested > START_TIMEOUT then
			pending = nil
		end
	elseif flight then
		local now = GetTime()
		local elapsed = now - flight.start
		local onTaxi = UnitOnTaxi("player")
		local landedAt = ns.UpdateLanding(landing, onTaxi, now, now < loadingUntil)
		if not onTaxi and now >= loadingUntil and (ns.Cinematic.IsOwner(flight) or flight.cinematic) then
			-- Off the taxi (maybe landed): restore the UI now rather than after the landing is confirmed.
			ns.Cinematic.Exit(flight)
			flight.cinematicDone = true
		end
		if landedAt then
			EndFlight(landedAt)
		elseif onTaxi then
			if not flight.alerted and ns.ShouldAlert(flight.expected, elapsed) then
				Alert()
			end
			local paused = flight.resumeAt and now < flight.resumeAt
			if paused then
				ns.Cinematic.Watch(flight)
			end
			local wanted = db.cinematic and not flight.cinematicDone and not paused
				and ns.CinematicWanted(flight.expected, elapsed, db.cinematicMin)
			if wanted and not ns.Cinematic.IsActive() then
				ns.Cinematic.Enter(ns.FlightScene, flight, CinematicOptions(elapsed))
			elseif not wanted and (ns.Cinematic.IsOwner(flight) or flight.cinematic) then
				ns.Cinematic.Exit(flight)
				flight.cinematicDone = true
			end
			if ns.Cinematic.IsOwner(flight) then
				ns.Cinematic.Update(flight, ns.OrbitFactor(flight.expected, elapsed))
			end
			local x, y = PlayerPos(flight.mapID)
			if x then
				ns.UpdatePassTracker(tracker, x, y, elapsed)
			end
		end
	end
end

local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick < TICK then
		return
	end
	sinceTick = 0
	Tick()
	if not (pending or flight) then
		self:Hide()
	end
end)

-- After /reload mid-flight: GetTime() keeps counting across reloads, so the saved start is still valid.
local function ResumeOrCleanup()
	if flight then
		return
	end
	local cur = ns.flightDB.current
	if not cur then
		return
	end
	local age = GetTime() - (cur.start or -math.huge)
	if UnitOnTaxi("player") and age >= 0 and age < MAX_RESUME_AGE then
		StartFlight(cur, cur.start)
		return
	end
	ns.Cinematic.Release(cur)
	ns.flightDB.current = nil
end

function events:PLAYER_ENTERING_WORLD()
	-- Backstop in case LOADING_SCREEN_DISABLED doesn't fire.
	loadingUntil = math.min(loadingUntil, GetTime() + LOADING_GRACE)
	ResumeOrCleanup()
end

function events:LOADING_SCREEN_ENABLED()
	loadingUntil = math.huge
end

function events:LOADING_SCREEN_DISABLED()
	loadingUntil = GetTime() + LOADING_GRACE
end

function events:ZONE_CHANGED_NEW_AREA()
	if flight and ns.Cinematic.IsOwner(flight) then
		local zone = GetZoneText()
		if zone and zone ~= "" then
			ns.ZoneText_Show(zone)
		end
	end
end

-- Only registered until Blizzard_FlightMap loads (see InstallHooks).
function events:ADDON_LOADED(name)
	if name == "Blizzard_FlightMap" then
		ns.HookFlightMap()
		self:UnregisterEvent("ADDON_LOADED")
	end
end

-- hooksecurefunc can't be undone: install once, on first activation, and check module.active inside.
local function InstallHooks()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc("TakeTaxiNode", function(slot)
		if not module.active then
			return
		end
		local route = ns.BuildRoute(slot)
		if route then
			route.requested = GetTime()
			pending = route
			ticker:Show()
		end
	end)
	ns.HookTaxiFrame()
	if C_AddOns.IsAddOnLoaded("Blizzard_FlightMap") then
		ns.HookFlightMap()
	else
		events:RegisterEvent("ADDON_LOADED")
	end
end

local function Activate()
	InstallHooks()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	if not ns.flightDB.frame.locked then
		ns.Bar_SetLocked(false) -- shows the preview so the bar can be placed
	end
	-- Turned on from the panel: the world is already there, so resume a flight now instead of waiting
	-- for the next loading screen.
	if ns.inWorld then
		ResumeOrCleanup()
	end
end

-- Must undo everything: UI, camera, pitch limit, music, bar, ticker, events.
local function Deactivate()
	for _, event in ipairs(EVENTS) do
		events:UnregisterEvent(event)
	end
	pending = nil
	if flight then
		ns.Cinematic.Release(flight) -- the interrupted flight is not recorded
		flight, tracker = nil, nil
	end
	local cur = ns.flightDB.current
	if cur then
		ns.Cinematic.Release(cur)
		ns.flightDB.current = nil
	end
	ticker:Hide()
	ns.Bar_Hide()
	StopPreview()
end

local function RequireActive()
	if module.active then
		return true
	end
	ns.Print("Flight Timer is off.")
	return false
end

local function Seconds(value)
	return value .. "s"
end

-- Home's "Around you": flight masters in your zone you haven't timed a route from ---------------------------------

local COVERAGE_ICON = "Interface\\Icons\\Ability_Mount_Wyvern_01"

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Untimed flight masters in the zone you're in, nearest first (Coverage_Untimed), and that zone's map ID.
local function UntimedHere()
	local zone = ns.Atlas_PlayerZone()
	if not zone then
		return {}, nil
	end
	local px, py
	local pos = C_Map.GetPlayerMapPosition(zone.mapID, "player")
	if pos and not Secret(pos.x) then
		px, py = pos.x, pos.y
	end
	local w, h = C_Map.GetMapWorldSize(zone.mapID)
	return ns.Coverage_Untimed(ns.Atlas_MapNodes(zone.mapID), ns.Coverage_Timed(ns.flightDB), px, py, w, h), zone.mapID
end

-- Map pin + super-track (Waypoints and Blizzard's arrow pick it up), as Weekly's knowledge waypoints.
local function Waypoint(node, mapID)
	if not (node.x and C_Map.CanSetUserWaypointOnMap(mapID)) then
		ns.Print("can't place a map pin there.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, node.x, node.y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	ns.Print(("waypoint: %s."):format(node.name))
end

local function DistanceText(yards)
	local way = ns.modulesByKey.way
	return ns.Way_FormatDistance(yards, way and way.db and way.db.metric)
end

local AROUND = {
	kind = "around", key = "flightaround", order = 4, name = "Flight masters", maxRows = 2, icon = COVERAGE_ICON,
	openText = "Opens the world map on this zone",
	open = function()
		if InCombatLockdown() then
			ns.Print("not in combat.")
			return
		end
		local zone = ns.Atlas_PlayerZone()
		OpenWorldMap(zone and zone.mapID or C_Map.GetBestMapForUnit("player"))
	end,
	title = function()
		return ("Flight masters: %d not timed here"):format(#(UntimedHere()))
	end,
	items = function(limit)
		local list, mapID = UntimedHere()
		local rows = {}
		for i = 1, math.min(limit, #list) do
			local node = list[i]
			local hidden = node.state == "undiscovered"
			rows[i] = {
				icon = COVERAGE_ICON, text = node.name, color = hidden and "textFaint" or nil,
				right = DistanceText(node.yards),
				onClick = function()
					Waypoint(node, mapID)
				end,
				onEnter = function(row)
					GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
					GameTooltip:SetText(node.name, 1, 1, 1)
					GameTooltip:AddLine(hidden and "Not discovered yet." or "No timed flight from or to here yet.",
						ns.UI.RGB("textMuted"))
					GameTooltip:AddLine("Click: waypoint", ns.UI.RGB("accent"))
					GameTooltip:Show()
				end,
			}
		end
		return rows
	end,
}

ns.EditMode_Register({
	name = "Flight Timer",
	frame = ns.Bar_Frame,
	refresh = function()
		if module.active then
			ns.Bar_EditMode(ns.EditMode_Active())
		end
	end,
	saved = ns.Bar_SavePosition,
})

module = ns.RegisterModule({
	key = "flight",
	name = "Flight Timer",
	category = "Travel",
	description = "Times flight paths account-wide and shows a countdown while flying, with an optional cinematic flight mode.",
	enabledByDefault = true,
	defaults = ns.defaults,
	keep = { "calibration", "stats" }, -- collected data: a settings reset keeps it
	init = function(db)
		ns.flightDB = db
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	cinematicState = function()
		return flight
	end,
	home = {
		{ kind = "page", key = "coverage", order = 4, name = "Flight coverage", icon = "Interface\\Icons\\Ability_Mount_Wyvern_01",
			page = ns.CoveragePage,
			summary = function()
				local n = 0
				for _ in pairs((ns.Coverage_Timed(ns.flightDB))) do
					n = n + 1
				end
				return n == 1 and "1 flight master timed" or (n .. " flight masters timed")
			end },
		AROUND,
	},
	panelClosed = StopPreview,
	commands = {
		{ "stats", "show flight stats", PrintStats },
		{ "resetstats", "clear flight stats", ResetStats },
		{ "reset", "forget all recorded flight times", ResetTimes },
		{ "lock", "lock the timer bar", function()
			if RequireActive() then
				ns.Bar_SetLocked(true)
				ns.Print("bar locked.")
			end
		end },
		{ "unlock", "move the timer bar", function()
			if RequireActive() then
				ns.Bar_SetLocked(false)
				ns.Print("drag the bar, then /tomte flight lock.")
			end
		end },
		{ "testalert", "play the arrival alert", PlayAlert },
	},
	options = {
		{ type = "header", label = "Timer" },
		{ type = "checkbox", key = "frame.locked", label = "Lock timer bar",
			tooltip = "Unlock to drag the timer bar somewhere else. Blizzard's Edit Mode moves it too.",
			onChange = function(value)
				if module.active then
					ns.Bar_SetLocked(value)
				end
			end },
		{ type = "checkbox", key = "alert", label = "Arrival alert",
			tooltip = "Two dings and a flashing taskbar icon 5 seconds before landing." },
		{ type = "button", label = "Arrival alert sound", text = "Test", onClick = PlayAlert,
			tooltip = "Play the arrival alert." },

		{ type = "header", label = "Cinematic flights" },
		{ type = "checkbox", key = "cinematic", label = "Cinematic mode",
			tooltip = "Hide the UI, letterbox the screen and show a title card while flying." },
		{ type = "checkbox", key = "orbit", label = "Camera orbit",
			tooltip = "Zoomed-out camera slowly circles your character." },
		{ type = "checkbox", key = "showcase", label = "Character showcase",
			tooltip = "Your character model and gear on the left side of the screen." },
		{ type = "slider", key = "cinematicMin", label = "Minimum flight length", min = 10, max = 60, step = 5,
			format = Seconds,
			tooltip = "Known flights shorter than this stay normal. Unknown flights always go cinematic." },
		{ type = "slider", key = "resumeDelay", label = "Resume after idle", min = 10, max = 60, step = 5,
			format = Seconds,
			tooltip = "Click or Esc pauses the cinematic. It comes back after this long without clicks, key presses or open windows." },
		{ type = "checkbox", key = "music", label = "Flight music",
			tooltip = "Play an expansion main theme during cinematic flights (zone music is paused meanwhile)." },
		{ type = "dropdown", key = "musicTrack", label = "Music track", tooltip = "Which main theme plays.",
			choices = function()
				local list = {}
				for i, track in ipairs(ns.MUSIC_TRACKS) do
					list[i] = { value = i, text = track.name }
				end
				return list
			end },
		{ type = "button", label = "Preview track", text = "Play", onClick = PreviewMusic,
			tooltip = ("Play the selected track for %d seconds (click again to stop)."):format(PREVIEW_SECONDS) },

		{ type = "header", label = "Data" },
		{ type = "button", label = "Recorded flight times", text = "Reset", onClick = ResetTimes,
			confirm = "Forget all recorded flight times?",
			tooltip = "Forget all route, hop and pace data." },
		{ type = "button", label = "Flight stats", text = "Reset", onClick = ResetStats,
			confirm = "Clear all flight stats?",
			tooltip = "Clear flights, time in the air, gold spent and the rest." },
	},
})
ns.flightModule = module
