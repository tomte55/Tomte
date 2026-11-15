local addonName, ns = ...

-- Decorating tools: Expert mode extras. Keys that reset the selected decor's move, turn or size (one transform or all
-- of them) and pick the rotation axis; two buttons above the submode bar that turn the selected decor by a set amount
-- while rotating; and a bigger or smaller gizmo (the move arrows and turn rings, game CVars put back to their defaults
-- when the module stops). Registered in Decorate.lua.

-- The gizmo's size CVars (Blizzard's house editor), by which slider sets them.
local GIZMO_CVARS = {
	move = { "housingExpertGizmos_Translation_BaseArrowHeadScale", "housingExpertGizmos_Translation_BaseArrowStemScale",
		"housingExpertGizmos_Translation_BaseCubeScale" },
	turn = { "housingExpertGizmos_Rotation_BaseRingScale", "housingExpertGizmos_Rotation_BaseOrbScale" },
}
local SUBMODE_TRANSLATE, SUBMODE_ROTATE = 0, 1 -- Enum.HousingPrecisionSubmode, when the enum is missing
local ROTATE_LEFT, ROTATE_RIGHT = 64, 128 -- Enum.HousingIncrementType, when the enum is missing
local RESTRICTION_NONE = 0 -- Enum.HousingExpertSubmodeRestriction.None
local UI = ns.UI

local OWNER = "expert"
local events = ns.Decorate_Events

local db
local active, editing = false, false
local mode = 0
local buttons
local pulsing = false
local changedCVars = {} -- [cvar] = true while it's set to something other than its default

local function Submode(name, fallback)
	return Enum.HousingPrecisionSubmode and Enum.HousingPrecisionSubmode[name] or fallback
end

local function InExpert()
	return mode == ns.DecorPlace_Mode("ExpertDecor")
end

local function Selected()
	local ok, selected = pcall(C_HousingExpertMode.IsDecorSelected)
	return ok and selected == true
end

-- Why an Expert key can't act now, or nil.
local function NotReady()
	if not InExpert() then
		return "Switch to Expert mode first."
	elseif not Selected() then
		return "Select a decor first."
	end
	return nil
end

-- Keys ------------------------------------------------------------------------------------------------------------------

-- all: every transform; else only the open submode's (move, turn or size).
function ns.DecorateExpert_Reset(all)
	local why = NotReady()
	if why then
		ns.DecorPlace_Error(why)
		return
	end
	pcall(C_HousingExpertMode.ResetPrecisionChanges, not all)
	if SOUNDKIT.HOUSING_EXPERTMODE_RESET_CHANGES then
		PlaySound(SOUNDKIT.HOUSING_EXPERTMODE_RESET_CHANGES)
	end
end

-- axis: 1, 2 or 3 for X, Y or Z. Leaving and re-entering the rotate submode starts the axis over at X; each
-- SelectNextRotationAxis then moves it one on.
function ns.DecorateExpert_Axis(axis)
	local why = NotReady()
	if why then
		ns.DecorPlace_Error(why)
		return
	end
	pcall(C_HousingExpertMode.SetPrecisionSubmode, Submode("Translate", SUBMODE_TRANSLATE))
	pcall(C_HousingExpertMode.SetPrecisionSubmode, Submode("Rotate", SUBMODE_ROTATE))
	for _ = 2, axis do
		pcall(C_HousingExpertMode.SelectNextRotationAxis)
	end
end

-- Rotate buttons ------------------------------------------------------------------------------------------------------

local function Increment(name, fallback)
	return Enum.HousingIncrementType and Enum.HousingIncrementType[name] or fallback
end

local function UpdateButtons()
	if not buttons then
		return
	end
	local ok, submode = pcall(C_HousingExpertMode.GetPrecisionSubmode)
	local shown = active and editing and db.rotateButtons and InExpert() and Selected()
		and ok and submode == Submode("Rotate", SUBMODE_ROTATE)
	buttons:SetShown(shown == true)
	local text = ("%d°"):format(db.pulse)
	buttons.left.label:SetText("-" .. text)
	buttons.right.label:SetText("+" .. text)
	buttons.left:SetEnabled(not pulsing)
	buttons.right:SetEnabled(not pulsing)
end

-- Holds the game's rotate increment for as long as the set turn takes, then lets go.
local function Pulse(kind)
	if pulsing or not Selected() then
		return
	end
	if not pcall(C_HousingExpertMode.SetPrecisionIncrementingActive, kind, true) then
		return
	end
	pulsing = true
	UpdateButtons()
	C_Timer.After(ns.DecorTools_PulseSeconds(db.pulse), function()
		pcall(C_HousingExpertMode.SetPrecisionIncrementingActive, kind, false)
		pulsing = false
		UpdateButtons()
	end)
end

local function PulseButton(label, kind, tip)
	local b = UI.Button(buttons, 60, label)
	b:SetScript("OnClick", function()
		Pulse(kind)
	end)
	b:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip, UI.Color("heading"))
		UI.TipLine("Turns around the axis picked on the gizmo. The turn is close, not exact: the game turns while the button holds it.", "textMuted", true)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", GameTooltip_Hide)
	return b
end

local function CreateButtons()
	local expert = HouseEditorFrame and HouseEditorFrame.ExpertDecorModeFrame
	if buttons or not expert then
		return
	end
	buttons = CreateFrame("Frame", nil, expert)
	buttons:SetSize(132, 24)
	local bar = expert.SubmodeBar
	if bar then
		buttons:SetPoint("BOTTOM", bar, "TOP", 0, 10)
	else
		buttons:SetPoint("BOTTOM", 0, 150)
	end
	buttons.left = PulseButton("-", Increment("RotateLeft", ROTATE_LEFT), "Turn left")
	buttons.left:SetPoint("LEFT")
	buttons.right = PulseButton("+", Increment("RotateRight", ROTATE_RIGHT), "Turn right")
	buttons.right:SetPoint("RIGHT")
	buttons:Hide()
end

events:On(OWNER, "HOUSING_DECOR_PRECISION_SUBMODE_CHANGED", UpdateButtons)
events:On(OWNER, "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED", UpdateButtons)

-- Gizmo size ----------------------------------------------------------------------------------------------------------

-- A CVar's value as a number, or nil. The gizmo CVars only exist once Blizzard's house editor has loaded: before that
-- the game returns nothing for them.
local function Number(get, name)
	local value = get(name)
	return value ~= nil and tonumber(value) or nil
end

-- restore: back to the defaults (the module stops). force: a slider was set back to 100%, so its CVars go back to the
-- defaults even when this session didn't change them (the game keeps CVars, so an earlier session may have).
local function SetGizmo(names, scale, restore, force)
	for _, name in ipairs(names) do
		local default = Number(C_CVar.GetCVarDefault, name)
		if default then
			if restore or scale == 1 then
				if changedCVars[name] or (force and Number(C_CVar.GetCVar, name) ~= default) then
					C_CVar.SetCVar(name, default)
				end
				changedCVars[name] = nil
			else
				C_CVar.SetCVar(name, default * scale)
				changedCVars[name] = true
			end
		end
	end
end

-- The gizmo is drawn again only when the submode is entered: leave it for a frame and come back.
local function RedrawGizmo()
	if not InExpert() then
		return
	end
	local ok, submode = pcall(C_HousingExpertMode.GetPrecisionSubmode)
	if not ok or submode == nil then
		return
	end
	local okR, restriction = pcall(C_HousingExpertMode.GetPrecisionSubmodeRestriction,
		Submode("Translate", SUBMODE_TRANSLATE))
	if not okR or restriction ~= (Enum.HousingExpertSubmodeRestriction
		and Enum.HousingExpertSubmodeRestriction.None or RESTRICTION_NONE) then
		return
	end
	pcall(C_HousingExpertMode.SetPrecisionSubmode, Submode("Translate", SUBMODE_TRANSLATE))
	C_Timer.After(0, function()
		if InExpert() then
			pcall(C_HousingExpertMode.SetPrecisionSubmode, submode)
		end
	end)
end

local function ApplyGizmo(restore, force)
	SetGizmo(GIZMO_CVARS.move, db.gizmoMove, restore, force)
	SetGizmo(GIZMO_CVARS.turn, db.gizmoTurn, restore, force)
end

-- A gizmo slider moved.
function ns.DecorateExpert_GizmoChanged()
	if active then
		ApplyGizmo(false, true)
		RedrawGizmo()
	end
end

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateExpert_Init(saved)
	db = saved
end

function ns.DecorateExpert_Start()
	active = true
end

function ns.DecorateExpert_Stop()
	active = false
	ApplyGizmo(true)
	events:UnwatchAll(OWNER)
	UpdateButtons()
end

function ns.DecorateExpert_Editing(on, newMode)
	local opened = on and not editing
	editing, mode = on, newMode or 0
	-- Each time the editor opens (its CVars exist from then on): also puts a slider that a reset or an imported
	-- profile set back to 100% without its onChange back to the game's size.
	if opened then
		ApplyGizmo(false, true)
	end
	if on and InExpert() then
		CreateButtons()
		events:TryWatch(OWNER, "HOUSING_DECOR_PRECISION_SUBMODE_CHANGED")
		events:TryWatch(OWNER, "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED")
		if next(changedCVars) then
			C_Timer.After(0, RedrawGizmo)
		end
	else
		events:UnwatchAll(OWNER)
	end
	UpdateButtons()
end

function ns.DecorateExpert_Apply()
	UpdateButtons()
end
