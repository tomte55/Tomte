local addonName, ns = ...

-- Showcase module: a character view in the game world. The camera glides in on your character (left of center),
-- the UI fades out, and your gear and stats sit around it (Scene.lua); the camera turns slowly until you take it
-- (Camera.lua). Built on the cinematic engine (Cinematic/Engine.lua): zoom, pitch, UI fade, vignette, Esc.
-- Opens with /tomte showcase, a key binding or its minimap button; Esc, the binding, the panel's x or combat closes it.
-- Design: docs/superpowers/specs/2026-10-11-tomte-showcase-design.md. Behavior studied from Narcissus; no code from it.

local OWNER = "showcase"
local PITCH = 2 -- degrees: the camera settles level with the character's head
local HEIGHT_CHANGE = 0.1 -- re-zoom when a fresh measurement differs this much (a fraction)
-- The game's saved camera view the player's camera is kept in while open (close goes back to it exactly). 5, as
-- Narcissus uses: the views players bind are mostly 1-3.
local SAVED_VIEW = 5

local module, db
local state -- the open showcase's cinematic state (db.current), nil when closed
local events = ns.NewEvents()
local refreshTimer

local function Blocked()
	return InCombatLockdown() or ns.Cinematic.IsActive() or UnitOnTaxi("player")
		or C_PetBattles.IsInBattle()
		or (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene())
		or (MovieFrame and MovieFrame:IsShown())
end

local function Zoom(height)
	return ns.CharShow_Zoom(height, IsMounted(), db.distance)
end

local function RefreshSoon(statsOnly)
	if not state then
		return
	end
	if refreshTimer then
		refreshTimer:Cancel()
	end
	refreshTimer = C_Timer.NewTimer(0.2, function()
		refreshTimer = nil
		if state then
			if statsOnly then
				ns.CharShowScene.RefreshStats()
			else
				ns.CharShowScene.Refresh()
			end
		end
	end)
end

local function WatchOpen(on)
	local list = { "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "UNIT_STATS", "COMBAT_RATING_UPDATE",
		"MASTERY_UPDATE", "SPEED_UPDATE", "LIFESTEAL_UPDATE", "AVOIDANCE_UPDATE", "UNIT_MAXHEALTH",
		"PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_STARTED_MOVING" }
	for _, event in ipairs(list) do
		if on then
			events:Watch(OWNER, event)
		else
			events:Unwatch(OWNER, event)
		end
	end
end

-- The measured height arrived while open: if it's quite different from the one we zoomed for, zoom again.
local function ReZoom(height)
	if not (state and height and state.height) then
		return
	end
	if math.abs(height - state.height) / state.height < HEIGHT_CHANGE then
		return
	end
	local delta = Zoom(height) - Zoom(state.height)
	state.height = height
	if delta > 0 then
		CameraZoomOut(delta)
	else
		CameraZoomIn(-delta)
	end
	state.zoomedOut = (state.zoomedOut or 0) + delta -- the engine undoes it on close
end

function ns.CharShow_Open()
	if state then
		return
	end
	if not module.active then
		ns.Print("Showcase is off.")
		return
	end
	if Blocked() then
		ns.Print("the Showcase can't open right now (combat, a flight or another cinematic).")
		return
	end
	local height = ns.CharShowCamera.Height()
	state = { height = height or 2, hints = db.hints }
	db.current = state
	-- Measure again (form, race change); the zoom follows if it's quite different.
	ns.CharShowCamera.MeasureHeight(ReZoom)
	ns.Cinematic.Enter(ns.CharShowScene, state, {
		zoom = Zoom(height),
		pitch = PITCH,
		interactive = true,
		instantHide = true,
		noLift = true,
		zoomTime = 1.4,
		saveView = SAVED_VIEW,
		viewDelay = 0.3, -- after dynamic pitch is released (Camera.lua, PAD_CLOSE)
		bands = db.bands,
		hint = "Drag to turn, scroll to zoom, Esc to close",
		onDismiss = function()
			ns.CharShow_Close()
		end,
	})
	if not ns.Cinematic.IsOwner(state) then
		state, db.current = nil, nil -- the engine said no
		return
	end
	ns.CharShowCamera.Start(state, {
		toSide = db.toSide,
		dynamicPitch = db.dynamicPitch,
		turnSpeed = db.turn and db.turnSpeed or 0,
		isOverOwn = ns.CharShowScene.MouseOverOwn,
	})
	WatchOpen(true)
end

function ns.CharShow_Close()
	if state then
		ns.Cinematic.Release(state) -- calls the scene's End, which lands in CharShow_OnEnd
	end
end

-- The scene ended: closed by us, by combat (the engine pauses it) or the module turning off.
function ns.CharShow_OnEnd()
	local ended = state
	if not ended then
		return
	end
	state = nil
	db.current = nil
	WatchOpen(false)
	ns.CharShowCamera.Stop(ended)
	-- Combat ends it with a pause that would come back later: forget it instead.
	C_Timer.After(0, function()
		ns.Cinematic.Release(ended)
	end)
end

function ns.CharShow_Toggle()
	if state then
		ns.CharShow_Close()
	else
		ns.CharShow_Open()
	end
end

ns.bindings.SHOWCASE = function()
	if module and module.active then
		ns.CharShow_Toggle()
	end
end
BINDING_NAME_TOMTE_SHOWCASE = "Showcase (character view)"

-- A showcase open at a /reload or crash: its camera changes are still there. Undo them.
local function CleanupSaved()
	local saved = db.current
	if saved and saved ~= state then
		ns.Cinematic.Release(saved)
		db.current = nil
	end
	if not state then
		ns.CharShowCamera.RestoreCVars()
	end
end

events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	CleanupSaved()
	C_Timer.After(3, function()
		if module.active and not state then
			ns.CharShowCamera.MeasureHeight()
		end
	end)
end)
events:On(OWNER, "PLAYER_LOGOUT", function()
	-- Before the client saves its CVars: never with our values in them.
	ns.CharShowCamera.StopNow()
end)
events:On(OWNER, "PLAYER_STARTED_MOVING", function()
	ns.CharShowCamera.Grab()
end)
events:On(OWNER, "PLAYER_EQUIPMENT_CHANGED", function()
	RefreshSoon(false)
end)
events:On(OWNER, "GET_ITEM_INFO_RECEIVED", function()
	RefreshSoon(false)
end)
for _, event in ipairs({ "COMBAT_RATING_UPDATE", "MASTERY_UPDATE", "SPEED_UPDATE", "LIFESTEAL_UPDATE",
	"AVOIDANCE_UPDATE", "PLAYER_AVG_ITEM_LEVEL_UPDATE" }) do
	events:On(OWNER, event, function()
		RefreshSoon(true)
	end)
end
for _, event in ipairs({ "UNIT_STATS", "UNIT_MAXHEALTH" }) do
	events:On(OWNER, event, function(_, unit)
		if unit == "player" then
			RefreshSoon(true)
		end
	end)
end

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

module = ns.RegisterModule({
	key = "showcase",
	name = "Showcase",
	category = "Gear",
	description = "A character view in the game world: the camera glides in on your character, the UI fades out, "
		.. "and your gear (item level, upgrade track, enchants and gems) and stats sit around it. The camera turns "
		.. "slowly until you drag it; scroll to zoom. Open it with /tomte showcase, a key binding or its minimap "
		.. "button. Esc closes it, and so does combat.",
	enabledByDefault = true,
	minimapButton = {
		name = "Showcase",
		icon = "Interface\\Icons\\INV_Chest_Chain",
		onClick = function()
			ns.CharShow_Toggle()
		end,
		tooltip = function(tooltip)
			tooltip:AddLine("Click to show your character, gear and stats", 1, 1, 1)
		end,
	},
	defaults = {
		turn = true,
		turnSpeed = 1,
		toSide = true,
		dynamicPitch = false, -- on: a one-frame camera twitch on close (12.1), not solved yet
		hints = true,
		bands = false,
		distance = 1,
		cvarBackup = {}, -- [cvar] = the player's value while we've changed it (Camera.lua)
		heights = {}, -- [character GUID] = model height in yards
	},
	init = function(saved)
		db = saved
		ns.charShowDB = saved
	end,
	toggle = function(active)
		if active then
			events:Watch(OWNER, "PLAYER_ENTERING_WORLD")
			events:Watch(OWNER, "PLAYER_LOGOUT")
			if ns.inWorld then
				CleanupSaved()
			end
		else
			ns.CharShow_Close()
			ns.CharShowCamera.StopNow()
			CleanupSaved()
			events:UnwatchAll(OWNER)
		end
	end,
	cinematicState = function()
		return state
	end,
	commands = {
		{ "", "open or close the Showcase", ns.CharShow_Toggle, hidden = true },
		{ "open", "show your character, gear and stats", ns.CharShow_Open },
		{ "debug", "chat lines for each camera step on close", function()
			db.debugCamera = not db.debugCamera
			ns.Print("Showcase camera debug " .. (db.debugCamera and "on" or "off") .. ".")
		end, hidden = true },
	},
	options = {
		{ type = "header", label = "Showcase" },
		{ type = "button", label = "Show your character", text = "Open", onClick = function()
			ns.CharShow_Open()
		end, tooltip = "Also /tomte showcase, a key binding (Key Bindings > Tomte) or the minimap button." },
		{ type = "header", label = "Camera" },
		{ type = "checkbox", key = "turn", label = "Slow turn",
			tooltip = "The camera slowly circles your character until you drag it or walk." },
		{ type = "slider", key = "turnSpeed", label = "Turn speed", min = 0.25, max = 3, step = 0.25,
			format = Percent },
		{ type = "slider", key = "distance", label = "Camera distance", min = 0.7, max = 1.6, step = 0.05,
			format = Percent, tooltip = "How far the camera stays from your character. 100% frames the whole body." },
		{ type = "checkbox", key = "dynamicPitch", label = "Head above center",
			tooltip = "ActionCam's dynamic pitch while the Showcase is open: the camera aims a little lower, so your head "
				.. "sits above the middle of the screen." },
		{ type = "checkbox", key = "toSide", label = "Character to the side",
			tooltip = "Your character stands left of center, between the gear columns. Off: in the middle." },
		{ type = "checkbox", key = "bands", label = "Letterbox bars",
			tooltip = "Black bars at the top and bottom of the screen, as in the other cinematics." },
		{ type = "header", label = "Gear" },
		{ type = "checkbox", key = "hints", label = "Gear hints on slots",
			tooltip = "Upgrade track, enchant (or \"No enchant\" at max level) and gems under each item." },
	},
})
