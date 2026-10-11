local addonName, ns = ...

-- Showcase camera, on top of the cinematic engine's zoom and pitch (Cinematic/Engine.lua):
--   * the side offset: test_cameraOverShoulder follows the zoom, so the character stays left of center. The
--     motion-sickness options block it and are turned off meanwhile. Every CVar we change is backed up in the
--     module's saved table first and restored on close, at logout, and at the next login after a /reload or crash.
--   * the turn: a swing round to the front, then the slow turn, driven here with MoveViewLeftStart so the degrees
--     turned are known (cameraYawMoveSpeed x speed x time) and can be turned back on close. A press on the world or
--     walking ends the turn; the player has the camera then, and it isn't turned back.
--   * the "experimental feature" popup 12.1 shows when a test_ CVar changes: hidden by us, but only while UIParent
--     is visible (a popup hidden while it's invisible never runs OnHide and keeps later Esc presses from working).
--     Blizzard's event routing is left alone.
--   * the model's height (a hidden ModelScene actor), for the zoom.

local SWING_DEGREES = 150 -- from behind the character round to a 3/4 front view
local SWING_SPEED = 0.7 -- MoveViewLeftStart speed of the swing
local TURN_SPEED = 0.012 -- slow turn at 100% (0.03 was too fast)
local BACK_SPEED = 0.9
local SHOULDER_RATE = 3 -- per second: how fast the offset eases toward its target
local POPUP_GIVE_UP = 120 -- seconds after closing to keep trying to hide the popup
local MEASURE_TIMEOUT = 5
local CVAR_SHOULDER = "test_cameraOverShoulder"
local CVARS_OFF = { "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }
-- ActionCam's dynamic pitch: up close the camera aims lower, so the head sits above the middle of the screen.
local CVAR_PITCH = "test_cameraDynamicPitch"
local POPUP = "EXPERIMENTAL_CVAR_WARNING"

local Cam = {}
ns.CharShowCamera = Cam

local db -- the module's saved table: cvarBackup = { [cvar] = value }, heights = { [guid] = yards }
local driver = CreateFrame("Frame")
driver:Hide()
local popupEvents = CreateFrame("Frame")

local live -- the open showcase's camera state, nil when closed
local phase -- "swing", "turn", "still", "back", nil
local turned = 0 -- degrees turned left since opening
local backLeft = 0 -- degrees still to turn back
local rate = 0 -- degrees per second of the current MoveView
local shoulderNow, shoulderTarget, toSide
local finishing -- easing the offset back after close
local popupPending, popupSince
local mouseWasDown
local isOverOwn -- function: the mouse is over the scene's own frames

local function GetCVarNumber(name)
	return tonumber(C_CVar.GetCVar(name)) or 0
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
	for name, value in pairs(db.cvarBackup) do
		C_CVar.SetCVar(name, value)
	end
	wipe(db.cvarBackup)
	shoulderNow, shoulderTarget, finishing = nil, nil, nil
end

local function Rate(speed)
	return ns.CharShow_YawRate(C_CVar.GetCVar("cameraYawMoveSpeed"), speed)
end

local function StartTurn(speed)
	rate = Rate(speed)
	MoveViewLeftStart(speed)
end

local function StopTurning()
	if phase == "swing" or phase == "turn" or phase == "back" then
		MoveViewLeftStop()
		MoveViewRightStop()
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

local function UpdateShoulder(elapsed)
	if not shoulderTarget then
		return
	end
	if live then
		shoulderTarget = ns.CharShow_Shoulder(GetCameraZoom(), toSide)
	end
	shoulderNow = shoulderNow or GetCVarNumber(CVAR_SHOULDER)
	local diff = shoulderTarget - shoulderNow
	local step = diff * math.min(elapsed * SHOULDER_RATE, 1)
	if math.abs(diff) < 0.01 then
		step = diff
	end
	if step ~= 0 then
		shoulderNow = shoulderNow + step
		C_CVar.SetCVar(CVAR_SHOULDER, tostring(shoulderNow))
	end
	if finishing and math.abs(shoulderTarget - shoulderNow) < 0.01 then
		Cam.RestoreCVars() -- exactly the player's values (also the motion-sickness ones)
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
		turned = turned + rate * elapsed
		if live then
			live.turned = turned
		end
		if phase == "swing" and turned >= SWING_DEGREES then
			if live and live.turnSpeed and live.turnSpeed > 0 then
				phase = "turn"
				StartTurn(TURN_SPEED * live.turnSpeed)
			else
				StopTurning()
				phase = "still"
			end
		end
	elseif phase == "back" then
		backLeft = backLeft - rate * elapsed
		if backLeft <= 0 then
			StopTurning()
			phase = nil
		end
	end
	UpdateShoulder(elapsed)
	UpdatePopup()
	if not live and not phase and not finishing and not popupPending then
		popupEvents:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
		self:Hide()
	end
end)

-- opts: { toSide, turnSpeed (0 = no slow turn; 1 = 100%), isOverOwn = function }. state: the cinematic state (saved),
-- which keeps turned/grabbed for the way back.
function Cam.Start(state, opts)
	db = ns.charShowDB
	if phase == "back" then
		StopTurning()
	end
	live = state
	state.turned, state.grabbed, state.turnSpeed = 0, false, opts.turnSpeed
	turned = 0
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
	if C_CVar.GetCVar(CVAR_PITCH) ~= nil then
		Backup(CVAR_PITCH)
		C_CVar.SetCVar(CVAR_PITCH, "1")
	end
	Backup(CVAR_SHOULDER)
	shoulderNow = GetCVarNumber(CVAR_SHOULDER)
	shoulderTarget = shoulderNow
	popupEvents:RegisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
	phase = "swing"
	StartTurn(SWING_SPEED)
	driver:Show()
end

-- Close: stop turning, turn back what we turned (unless the player took the camera), ease the offset back.
function Cam.Stop(state)
	if not live or (state and state ~= live) then
		return
	end
	StopTurning()
	local grabbed = live.grabbed
	live = nil
	phase = nil
	local dir, degrees = ns.CharShow_TurnBack(turned)
	if dir and not grabbed then
		phase, backLeft = "back", degrees
		rate = Rate(BACK_SPEED)
		if dir == "LEFT" then
			MoveViewLeftStart(BACK_SPEED)
		else
			MoveViewRightStart(BACK_SPEED)
		end
	end
	turned = 0
	finishing = true
	shoulderTarget = tonumber(db.cvarBackup[CVAR_SHOULDER]) or 0
	driver:Show()
end

-- At logout, and when the module turns off: everything back now, no easing.
function Cam.StopNow()
	if live or phase then
		StopTurning()
	end
	live, phase, turned = nil, nil, 0
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
