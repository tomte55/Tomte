local addonName, ns = ...

-- Housing decor: extras in Blizzard's house editor. Decorate mode: hovering a placed decor shows how many you have in
-- storage, how many are placed and its decor budget cost, and Alt places another of it (Blizzard's own "place from
-- storage", C_HousingBasicMode.StartPlacingNewDecor). Customize mode: right-click a dyed decor to copy its dyes, and a
-- Paste dyes button under Blizzard's dye pane previews them on the selected decor (Blizzard's Apply saves them). A
-- clock above the mode bar, with the time spent editing in its tooltip. Each piece has its own setting. Pure rules in
-- EditorData.lua; registered in Decor.lua, which also uses this file's event bus (ns.Decor_Events).

local CLOCK_TICK = 1 -- seconds between clock updates while editing
local CLOCK_GAP = 8 -- pixels between the clock and Blizzard's mode bar
-- A right-click counts as a click (copy dyes), not a camera turn, when the mouse moved less than this many pixels
-- and was let go within CLICK_TIME seconds: right-drag turns the camera in the editor.
local CLICK_MOVE = 6
local CLICK_TIME = 0.4
local MODE_NONE = 0 -- Enum.HouseEditorMode.None
local MODE_BASIC = 1 -- Enum.HouseEditorMode.BasicDecor, when the enum is missing
local MODE_CUSTOMIZE = 4 -- Enum.HouseEditorMode.Customize, when the enum is missing
local ENTRY_DECOR = 1 -- Enum.HousingCatalogEntryType.Decor, when the enum is missing
local MOUSE_OVER = "HousingDecorInstance.MouseOver" -- EventRegistry event of Blizzard_HouseEditorTemplates.lua
local ALT_KEYS = { LALT = true, RALT = true }
local UI = ns.UI

local OWNER = "editor"
local events = ns.NewEvents()
ns.Decor_Events = events

local db
local active = false
local mode = MODE_NONE
local hoverOwner = {} -- our EventRegistry owner
local hoverRegistered = false
local hovered -- { decorID, dyeSlots } of the decor hovered in decorate mode
local copied -- the copied dye colors (ns.DecorEditor_DyeColors), until the editor closes
local rightDown -- { x, y, t } at the last right mouse press in customize mode
local clock, ticker, paste
local editStart -- GetTime() when editing started, nil while not editing
local sessionSeconds = 0 -- finished editing stretches this session

local function Mode(name, fallback)
	return Enum.HouseEditorMode and Enum.HouseEditorMode[name] or fallback
end

local function DecorType()
	return Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor or ENTRY_DECOR
end

local function Editing()
	return mode ~= MODE_NONE
end

-- The catalog's entry for a decor ID (HousingCatalogEntryInfo), or nil.
local function CatalogInfo(decorID)
	if type(decorID) ~= "number" then
		return nil
	end
	local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, DecorType(), decorID)
	return ok and type(info) == "table" and info or nil
end

local function ErrorText(text)
	UIErrorsFrame:AddExternalErrorMessage(text)
end

-- Hover info and dye lines ------------------------------------------------------------------------------------------

local function HoverLines(tooltip, info)
	for _, line in ipairs(ns.DecorEditor_HoverLines(info, db.dupe)) do
		tooltip:AddLine(line[1], UI.Color(line[2]))
	end
end

local function DyeLines(tooltip, info)
	if not (info and info.canBeCustomized and not info.isLocked and ns.DecorEditor_DyeColors(info.dyeSlots)) then
		return
	end
	if copied and ns.DecorEditor_DyesMatch(copied, info.dyeSlots) then
		tooltip:AddLine("Has the copied dyes", UI.Color("textMuted"))
	else
		tooltip:AddLine("Right-click: copy dyes", UI.Color("accent"))
	end
end

-- Blizzard's house editor calls this on every hovered decor, with the tooltip it drew (customize mode) or nil
-- (decorate mode draws none).
local function OnMouseOver(_, modeFrame, tooltip)
	if not active then
		return
	end
	if mode == Mode("BasicDecor", MODE_BASIC) then
		local instance = C_HousingDecor.GetHoveredDecorInfo()
		if not instance then
			return
		end
		hovered = { decorID = instance.decorID, dyeSlots = instance.dyeSlots }
		if not db.hover then
			return
		end
		if not tooltip then
			GameTooltip:SetOwner(modeFrame, "ANCHOR_CURSOR_RIGHT")
			GameTooltip:SetText(instance.name or "", UI.Color("heading"))
			tooltip = GameTooltip
		end
		HoverLines(tooltip, CatalogInfo(instance.decorID))
		tooltip:Show()
	elseif mode == Mode("Customize", MODE_CUSTOMIZE) and db.dyeCopy and tooltip then
		DyeLines(tooltip, C_HousingCustomizeMode.GetHoveredDecorInfo())
		tooltip:Show()
	end
end

-- Place another (decorate mode, Alt) ----------------------------------------------------------------------------------

local function PlaceAnother()
	local target = hovered
	if not target or C_HousingBasicMode.IsDecorSelected() or C_HousingBasicMode.IsPlacingNewDecor()
		or C_HousingDecor.IsPreviewState() then
		return
	end
	local info = CatalogInfo(target.decorID)
	if not info or ns.DecorEditor_Stored(info) == 0 then
		ErrorText("You have none of this decor in storage.")
		return
	end
	if not ns.DecorEditor_BudgetAllows(C_HousingDecor.GetSpentPlacementBudget(),
		C_HousingDecor.GetMaxPlacementBudget(), C_HousingDecor.HasMaxPlacementBudget(), info.placementCost) then
		ErrorText("No room left in this house's decor budget.")
		return
	end
	local ok, variants = pcall(C_HousingCatalog.GetAllVariantInfosForEntry,
		{ recordID = target.decorID, entryType = DecorType() })
	local variantID = ns.DecorEditor_PickVariant(ok and variants or nil, target.dyeSlots,
		(info.remainingRedeemable or 0) > 0)
	if not variantID then
		ErrorText("Tomte can't find this decor in your storage.")
		return
	end
	C_HousingBasicMode.StartPlacingNewDecor(variantID)
end

events:On(OWNER, "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED", function(_, isHovering)
	if not isHovering then
		hovered = nil
	end
end)

-- On the key's release, like a click: the key is up by the time the new decor follows the mouse.
events:On(OWNER, "MODIFIER_STATE_CHANGED", function(_, key, down)
	if ALT_KEYS[key] and down == 0 and db.dupe and mode == Mode("BasicDecor", MODE_BASIC) then
		PlaceAnother()
	end
end)

-- Copy and paste dyes (customize mode) ----------------------------------------------------------------------------

local function CustomizePane()
	local frame = HouseEditorFrame and HouseEditorFrame.CustomizeModeFrame
	return frame and frame.DecorCustomizationsPane
end

local function SelectedDyeable()
	local info = C_HousingCustomizeMode.IsDecorSelected() and C_HousingCustomizeMode.GetSelectedDecorInfo()
	if info and info.canBeCustomized and ns.DecorEditor_DyeColors(info.dyeSlots) then
		return info
	end
	return nil
end

local function UpdatePaste()
	if not paste then
		return
	end
	local pane = CustomizePane()
	paste:SetShown(active and db.dyeCopy and copied ~= nil and mode == Mode("Customize", MODE_CUSTOMIZE)
		and pane ~= nil and pane:IsShown() and SelectedDyeable() ~= nil)
end

local function Paste()
	local info = SelectedDyeable()
	if not (info and copied) then
		return
	end
	local plan = ns.DecorEditor_DyePlan(copied, info.dyeSlots)
	if #plan == 0 then
		ErrorText("This decor already has the copied dyes.")
		return
	end
	for _, change in ipairs(plan) do
		C_HousingCustomizeMode.ApplyDyeToSelectedDecor(change.slotID, change.colorID)
	end
end

local function PasteEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Paste dyes", UI.Color("heading"))
	UI.TipLine("Shows the copied dyes on this decor. Blizzard's Apply button saves them and uses the dyes.",
		"text", true)
	GameTooltip:Show()
end

-- Lazily, once Blizzard's house editor is loaded. On the customize frame, anchored under the dye pane (not inside
-- it, so the pane's own layout never counts it).
local function CreatePaste()
	local pane = CustomizePane()
	if paste or not pane then
		return
	end
	paste = UI.Button(pane:GetParent(), 110, "Paste dyes")
	UI.FitButton(paste, 110)
	paste:SetPoint("TOPRIGHT", pane, "BOTTOMRIGHT", 0, -6)
	paste:SetFrameLevel(pane:GetFrameLevel() + 5)
	paste:SetScript("OnClick", Paste)
	paste:SetScript("OnEnter", PasteEnter)
	paste:SetScript("OnLeave", GameTooltip_Hide)
	paste:Hide()
end

local function Copy()
	if not C_HousingCustomizeMode.IsHoveringDecor() then
		return
	end
	local info = C_HousingCustomizeMode.GetHoveredDecorInfo()
	if not (info and info.canBeCustomized and not info.isLocked) then
		return
	end
	local colors = ns.DecorEditor_DyeColors(info.dyeSlots)
	if not colors then
		return
	end
	copied = colors
	local sound = SOUNDKIT.HOUSING_CUSTOMIZE_DYE_SELECT
	if sound then
		PlaySound(sound)
	end
	if GameTooltip:IsShown() then
		GameTooltip:AddLine("Dyes copied", UI.Color("success"))
		GameTooltip:Show()
	end
	CreatePaste()
	UpdatePaste()
end

events:On(OWNER, "GLOBAL_MOUSE_DOWN", function(_, button)
	if button == "RightButton" then
		local x, y = GetCursorPosition()
		rightDown = { x = x, y = y, t = GetTime() }
	end
end)

events:On(OWNER, "GLOBAL_MOUSE_UP", function(_, button)
	if button ~= "RightButton" or not rightDown then
		return
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	local moved = math.max(math.abs(x - rightDown.x), math.abs(y - rightDown.y)) / scale
	local quick = GetTime() - rightDown.t <= CLICK_TIME
	rightDown = nil
	if moved < CLICK_MOVE and quick and db.dyeCopy and mode == Mode("Customize", MODE_CUSTOMIZE) then
		Copy()
	end
end)

-- The pane opens or closes with the selection: after Blizzard's handler has shown or hidden it.
local function SelectionChanged()
	C_Timer.After(0, UpdatePaste)
end
events:On(OWNER, "HOUSING_CUSTOMIZE_MODE_SELECTED_TARGET_CHANGED", SelectionChanged)
events:On(OWNER, "HOUSING_DECOR_CUSTOMIZATION_CHANGED", SelectionChanged)

-- Clock -------------------------------------------------------------------------------------------------------------

local function EditedNow()
	return editStart and math.floor(GetTime() - editStart) or 0
end

local function ClockTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Time spent editing", UI.Color("heading"))
	GameTooltip:AddDoubleLine("This session", ns.Clock(sessionSeconds + EditedNow()), UI.Color("textMuted"))
	GameTooltip:AddDoubleLine("In total", ns.Clock((db.editorSeconds or 0) + EditedNow()), UI.Color("textMuted"))
	GameTooltip:Show()
end

local function ClockText()
	local t = date("*t")
	local military = C_CVar.GetCVarBool("timeMgrUseMilitaryTime")
	return ns.DecorEditor_ClockText(t.hour, t.min, military, TIMEMANAGER_AM, TIMEMANAGER_PM)
end

local function Tick()
	if clock then
		clock.text:SetText(ClockText())
		clock:SetWidth(math.ceil(clock.text:GetStringWidth()) + 20)
		if clock:IsMouseOver() and GameTooltip:GetOwner() == clock then
			ClockTooltip(clock)
		end
	end
end

local function CreateClock()
	if clock or not HouseEditorFrame then
		return
	end
	clock = CreateFrame("Frame", nil, HouseEditorFrame)
	clock:SetSize(80, 24)
	local bar = HouseEditorFrame.ModeBar
	if bar then
		clock:SetPoint("BOTTOM", bar, "TOP", 0, CLOCK_GAP)
	else
		clock:SetPoint("BOTTOM", 0, 90)
	end
	UI.Surface(clock, 0.5)
	clock.text = UI.Text(clock, 14, "heading", "number")
	clock.text:SetPoint("CENTER")
	clock:EnableMouse(true)
	clock:SetScript("OnEnter", ClockTooltip)
	clock:SetScript("OnLeave", GameTooltip_Hide)
	clock:Hide()
end

local function UpdateClock()
	local shown = active and db.clock and Editing()
	if shown then
		CreateClock()
	end
	if clock then
		clock:SetShown(shown == true)
	end
	if shown and not ticker then
		ticker = C_Timer.NewTicker(CLOCK_TICK, Tick)
		Tick()
	elseif not shown and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Modes -----------------------------------------------------------------------------------------------------------

local function Watch(event, on)
	if on then
		events:Watch(OWNER, event)
	else
		events:Unwatch(OWNER, event)
	end
end

-- Events and the hover callback only for the mode that's open and the pieces that are on.
local function Apply()
	local basic = active and mode == Mode("BasicDecor", MODE_BASIC)
	local customize = active and mode == Mode("Customize", MODE_CUSTOMIZE) and db.dyeCopy
	Watch("HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED", basic and db.dupe)
	Watch("MODIFIER_STATE_CHANGED", basic and db.dupe)
	Watch("GLOBAL_MOUSE_DOWN", customize)
	Watch("GLOBAL_MOUSE_UP", customize)
	Watch("HOUSING_CUSTOMIZE_MODE_SELECTED_TARGET_CHANGED", customize)
	Watch("HOUSING_DECOR_CUSTOMIZATION_CHANGED", customize)
	local wantHover = (basic and (db.hover or db.dupe)) or customize
	if wantHover and not hoverRegistered then
		EventRegistry:RegisterCallback(MOUSE_OVER, OnMouseOver, hoverOwner)
		hoverRegistered = true
	elseif not wantHover and hoverRegistered then
		EventRegistry:UnregisterCallback(MOUSE_OVER, hoverOwner)
		hoverRegistered = false
	end
	if not basic then
		hovered = nil
	end
	if customize then
		CreatePaste()
	end
	UpdatePaste()
	UpdateClock()
end

-- Editing time goes into the saved total when the editor closes (and when the module stops mid-edit).
local function StopEditing()
	if editStart then
		local seconds = EditedNow()
		sessionSeconds = sessionSeconds + seconds
		db.editorSeconds = (db.editorSeconds or 0) + seconds
		editStart = nil
	end
	copied = nil
end

local function SetMode(newMode)
	newMode = newMode or MODE_NONE
	if newMode ~= MODE_NONE and not editStart then
		editStart = GetTime()
	elseif newMode == MODE_NONE then
		StopEditing()
	end
	mode = newMode
	Apply()
end

events:On(OWNER, "HOUSE_EDITOR_MODE_CHANGED", function(_, newMode)
	SetMode(newMode)
end)

-- Called by Decor.lua -------------------------------------------------------------------------------------------------

function ns.DecorEditor_Init(moduleDB)
	db = moduleDB
end

function ns.DecorEditor_Start()
	active = true
	if not events:TryWatch(OWNER, "HOUSE_EDITOR_MODE_CHANGED") then
		return -- a client without the house editor
	end
	local now = C_HouseEditor.IsHouseEditorActive() and C_HouseEditor.GetActiveHouseEditorMode() or MODE_NONE
	SetMode(now)
end

function ns.DecorEditor_Stop()
	active = false
	StopEditing()
	mode = MODE_NONE
	Apply()
	events:UnwatchAll(OWNER)
	rightDown = nil
end

-- A setting changed: show or hide the pieces it covers.
function ns.DecorEditor_Apply()
	if active then
		Apply()
	end
end
