local addonName, ns = ...

-- Showcase camera, on top of the cinematic engine's zoom and pitch (Cinematic/Engine.lua):
--   * the side offset: test_cameraOverShoulder follows the zoom, so the character stays left of center. The
--     motion-sickness options block it and are turned off meanwhile. Every CVar we change is backed up in the
--     module's saved table first and restored on close, at logout, and at the next login after a /reload or crash.
--   * the turn: one motion that ramps up, swings round to the front and eases down into the slow turn, driven
--     with MoveViewLeftStart (degrees per second = cameraYawMoveSpeed x speed). A press on the world or walking ends
--     it. Closing goes back to the camera as it was through the engine's saved view, so nothing is turned back here.
--   * the "experimental feature" popup 12.1 shows when a test_ CVar changes: hidden by us, but only while UIParent
--     is visible (a popup hidden while it's invisible never runs OnHide and keeps later Esc presses from working).
--     Blizzard's event routing is left alone.
--   * the model's height (a hidden ModelScene actor), for the zoom.

-- Degrees per second. The swing ramps up to SWING_PEAK over SWING_RAMP and eases down to the slow turn by SWING_TIME:
-- about 135 degrees in all, from behind the character round to a 3/4 front view (tests/test_showcase.lua).
local SWING_PEAK = 220
local SWING_RAMP = 0.4
local SWING_TIME = 1.6
local TURN_RATE = 2.2 -- slow turn at 100%
local SHOULDER_RATE = 3 -- per second: how fast the offset eases toward its target
local POPUP_GIVE_UP = 120 -- seconds after closing to keep trying to hide the popup
local MEASURE_TIMEOUT = 5
local CVAR_SHOULDER = "test_cameraOverShoulder"
local CVARS_OFF = { "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }
-- ActionCam's dynamic pitch: up close the camera aims lower, so the head sits above the middle of the screen. It's on
-- or off, which jolts the camera, so its strength (the pad) is eased and it's only switched while the pad is 0.
local CVAR_PITCH = "test_cameraDynamicPitch"
local CVAR_PAD = "test_cameraDynamicPitchBaseFovPad"
local PAD_FALLBACK = 0.4 -- when the client has no default for the pad
-- On close the pad goes to 0 this fast (linear) and dynamic pitch switches off, all before the engine's view glides
-- back (Showcase.lua's viewDelay): a pad still easing during that glide fights it (a dip, then a pitch-back).
local PAD_CLOSE = 0.25
local POPUP = "EXPERIMENTAL_CVAR_WARNING"

local Cam = {}
ns.CharShowCamera = Cam

local db -- the module's saved table: cvarBackup = { [cvar] = value }, heights = { [guid] = yards }
local driver = CreateFrame("Frame")
driver:Hide()
local popupEvents = CreateFrame("Frame")

local live -- the open showcase's camera state, nil when closed
local phase -- "swing", "turn", "still", "back", nil
local swingT = 0 -- seconds into the swing
local rate = 0 -- degrees per second of the current MoveView
local shoulderNow, shoulderTarget, toSide
local padNow, padTarget -- nil: we don't drive dynamic pitch (the player had it on already, or the client lacks it)
local finishing -- easing the offset back after close
local popupPending, popupSince
local mouseWasDown
local isOverOwn -- function: the mouse is over the scene's own frames

local function GetCVarNumber(name)
	return tonumber(C_CVar.GetCVar(name)) or 0
end

-- /tomte showcase debug: a timestamped chat line per camera step on close (to find what moves the camera).
local closedAt
function Cam.Debug(text)
	if ns.charShowDB and ns.charShowDB.debugCamera then
		ns.Print(("showcase camera +%.2fs: %s"):format(closedAt and GetTime() - closedAt or 0, text))
	end
end

local function Backup(name)
	if db.cvarBackup[name] == nil then
		db.cvarBackup[name] = C_CVar.GetCVar(name) or "0"
	end
end

-- Every backed-up CVar back to the player's value, at once.
function Cam.RestoreCVars()
	db = ns.charShowDB -- also at login, before anything else here ran
	if not db then
		return
	end
	-- Dynamic pitch first: switched off, its strength changes nothing on screen.
	if db.cvarBackup[CVAR_PITCH] ~= nil then
		C_CVar.SetCVar(CVAR_PITCH, db.cvarBackup[CVAR_PITCH])
		Cam.Debug(CVAR_PITCH .. " = " .. db.cvarBackup[CVAR_PITCH])
	end
	for name, value in pairs(db.cvarBackup) do
		if name ~= CVAR_PITCH then
			C_CVar.SetCVar(name, value)
			Cam.Debug(name .. " = " .. value)
		end
	end
	wipe(db.cvarBackup)
	shoulderNow, shoulderTarget, finishing = nil, nil, nil
	padNow, padTarget = nil, nil
end

-- MoveView speed for a turn of `degrees` per second (the speed scales cameraYawMoveSpeed).
local function Speed(degrees)
	return degrees / ns.CharShow_YawRate(C_CVar.GetCVar("cameraYawMoveSpeed"), 1)
end

local function StartTurn(degrees)
	rate = degrees
	if degrees > 0 then
		MoveViewLeftStart(Speed(degrees))
	else
		MoveViewLeftStop()
	end
end

local function StopTurning()
	if phase == "swing" or phase == "turn" then
		MoveViewLeftStop()
	end
	rate = 0
end

-- The player took the camera (a press on the world, walking): no more turning, and no turning back.
function Cam.Grab()
	if live and (phase == "swing" or phase == "turn") then
		StopTurning()
	end
	if live then
		phase = "still"
		live.grabbed = true
	end
end

local function UpdatePopup()
	if not popupPending then
		return
	end
	if GetTime() - popupSince > POPUP_GIVE_UP then
		popupPending = nil
		return
	end
	-- Only while it can really hide: UIParent visible (see the header).
	if UIParent:IsVisible() and StaticPopup_Visible and StaticPopup_Visible(POPUP) then
		StaticPopup_Hide(POPUP)
		popupPending = nil
	end
end

popupEvents:SetScript("OnEvent", function()
	if live or finishing then
		popupPending, popupSince = true, GetTime()
		driver:Show()
	end
end)

-- One easing step of a CVar toward target; returns the new value.
local function Ease(name, now, target, elapsed)
	local diff = target - now
	local step = diff * math.min(elapsed * SHOULDER_RATE, 1)
	if math.abs(diff) < 0.01 then
		step = diff
	end
	if step ~= 0 then
		now = now + step
		C_CVar.SetCVar(name, tostring(now))
	end
	return now
end

local function UpdateEased(elapsed)
	if not shoulderTarget then
		return
	end
	if live then
		shoulderTarget = ns.CharShow_Shoulder(GetCameraZoom(), toSide)
	end
	shoulderNow = Ease(CVAR_SHOULDER, shoulderNow or GetCVarNumber(CVAR_SHOULDER), shoulderTarget, elapsed)
	if padTarget and finishing then
		padNow = math.max((padNow or 0) - padTarget * elapsed / PAD_CLOSE, 0) -- padTarget: the pad it eases down from
		C_CVar.SetCVar(CVAR_PAD, tostring(padNow))
		if padNow <= 0 then
			-- At 0 dynamic pitch changes nothing on screen: off now. The pad stays 0 until RestoreCVars at the end: "off"
			-- takes effect a frame late, and a pad restored in the same frame showed for that frame (a one-frame jump).
			C_CVar.SetCVar(CVAR_PITCH, db.cvarBackup[CVAR_PITCH] or "0")
			Cam.Debug("dynamic pitch off")
			db.cvarBackup[CVAR_PITCH] = nil
			padNow, padTarget = nil, nil
		end
	elseif padTarget then
		padNow = Ease(CVAR_PAD, padNow or 0, padTarget, elapsed)
	end
	local settled = math.abs(shoulderNow - shoulderTarget) < 1e-4 and not padTarget
	if finishing and settled then
		-- Everything eased back: the player's exact values (dynamic pitch goes off while its pad is 0, the
		-- motion-sickness options come back once the offset is back).
		Cam.RestoreCVars()
	end
end

driver:SetScript("OnUpdate", function(self, elapsed)
	if live and (phase == "swing" or phase == "turn") then
		local down = IsMouseButtonDown() and true or false
		if down and not mouseWasDown and not (isOverOwn and isOverOwn()) then
			Cam.Grab()
		end
		mouseWasDown = down
	end
	if phase == "swing" or phase == "turn" then
		if phase == "swing" then
			swingT = swingT + elapsed
			local orbit = TURN_RATE * (live and live.turnSpeed or 0)
			if swingT >= SWING_TIME then
				if orbit > 0 then
					phase = "turn"
					StartTurn(orbit)
				else
					StopTurning()
					phase = "still"
				end
			else
				StartTurn(ns.CharShow_SwingRate(swingT, SWING_TIME, SWING_PEAK, orbit, SWING_RAMP))
			end
		end
	end
	UpdateEased(elapsed)
	UpdatePopup()
	if not live and not phase and not finishing and not popupPending then
		popupEvents:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
		self:Hide()
	end
end)

-- opts: { toSide, turnSpeed (0 = no slow turn; 1 = 100%), isOverOwn = function }. state: the cinematic state (saved),
-- (grabbed is kept on it).
function Cam.Start(state, opts)
	db = ns.charShowDB
	live = state
	state.grabbed, state.turnSpeed = false, opts.turnSpeed
	toSide = opts.toSide
	isOverOwn = opts.isOverOwn
	mouseWasDown = IsMouseButtonDown() and true or false
	finishing = nil
	for _, name in ipairs(CVARS_OFF) do
		if C_CVar.GetCVar(name) ~= nil then -- only the ones this client has
			Backup(name)
			C_CVar.SetCVar(name, "0")
		end
	end
	padNow, padTarget = nil, nil
	local pitchOn = C_CVar.GetCVar(CVAR_PITCH)
	if opts.dynamicPitch and pitchOn ~= nil and pitchOn ~= "1" and C_CVar.GetCVar(CVAR_PAD) ~= nil then
		-- Switched on at strength 0 (no change on screen), then the strength eases up.
		Backup(CVAR_PAD)
		Backup(CVAR_PITCH)
		C_CVar.SetCVar(CVAR_PAD, "0")
		C_CVar.SetCVar(CVAR_PITCH, "1")
		padNow = 0
		local default = C_CVar.GetCVarDefault and tonumber(C_CVar.GetCVarDefault(CVAR_PAD))
		padTarget = (default and default > 0) and default or PAD_FALLBACK
	end
	Backup(CVAR_SHOULDER)
	shoulderNow = GetCVarNumber(CVAR_SHOULDER)
	shoulderTarget = shoulderNow
	popupEvents:RegisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
	phase = "swing"
	swingT = 0
	StartTurn(ns.CharShow_SwingRate(0, SWING_TIME, SWING_PEAK, TURN_RATE * (opts.turnSpeed or 0), SWING_RAMP))
	driver:Show()
end

-- Close: stop turning, ease the offset and the dynamic pitch strength back to the player's. Their exact values (and
-- dynamic pitch off, the motion-sickness options) come back once both are there: switching earlier jolts the camera.
function Cam.Stop(state)
	if not live or (state and state ~= live) then
		return
	end
	StopTurning()
	live = nil
	phase = nil
	closedAt = GetTime()
	Cam.Debug(("closing (offset %.2f, pad %s)"):format(shoulderNow or 0, padNow and ("%.2f"):format(padNow) or "-"))
	if padTarget then
		padTarget = math.max(padNow or 0, 0.01) -- the closing step eases down from where it is
	end
	finishing = true
	shoulderTarget = tonumber(db.cvarBackup[CVAR_SHOULDER]) or 0
	driver:Show()
end

-- At logout, and when the module turns off: everything back now, no easing.
function Cam.StopNow()
	if live or phase then
		StopTurning()
	end
	live, phase = nil, nil
	Cam.RestoreCVars()
	popupEvents:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
	if not popupPending then
		driver:Hide()
	end
end

function Cam.IsOpen()
	return live ~= nil
end

-- Model height ------------------------------------------------------------------------------------------------------

local measurer, actor
local measureStarted
local measureCallbacks = {}

local function MeasureDone(height)
	measurer:SetScript("OnUpdate", nil)
	measurer:Hide()
	measureStarted = nil
	if height and db then
		db.heights[UnitGUID("player")] = height
	end
	local callbacks = measureCallbacks
	measureCallbacks = {}
	for _, fn in ipairs(callbacks) do
		fn(height)
	end
end

-- Measures the player's model (current race, form) and saves it. onDone(height or nil) runs when known.
function Cam.MeasureHeight(onDone)
	db = ns.charShowDB
	if onDone then
		measureCallbacks[#measureCallbacks + 1] = onDone
	end
	if measureStarted then
		return
	end
	if not measurer then
		-- Shown but invisible: a model frame that's hidden may never load its model.
		measurer = CreateFrame("ModelScene", nil, UIParent)
		measurer:SetSize(4, 4)
		measurer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
		measurer:SetAlpha(0)
		actor = measurer:CreateActor()
	end
	measurer:Show()
	measureStarted = GetTime()
	actor:ClearModel()
	actor:SetModelByUnit("player")
	measurer:SetScript("OnUpdate", function()
		local bx, by, bz, tx, ty, tz = actor:GetActiveBoundingBox()
		if bz and tz and tz - bz > 0.2 then
			MeasureDone(tz - bz)
		elseif GetTime() - measureStarted > MEASURE_TIMEOUT then
			MeasureDone(nil)
		end
	end)
end

-- The saved height of this character's model, nil before the first measurement.
function Cam.Height()
	db = ns.charShowDB
	return db and db.heights[UnitGUID("player")]
end
