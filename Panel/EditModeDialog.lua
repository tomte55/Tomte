local addonName, ns = ...

-- Edit Mode settings dialog: the selected Tomte widget's few settings, like Blizzard's EditModeSystemSettingsDialog.
-- Selection lives in Core/EditMode.lua; the rows are the module's own options rows (OptionRows.lua), picked by key in
-- the widget's EditMode_Register spec (options = { ... }). Under them: Reset position, Hide (until Edit Mode closes)
-- and All settings (the module's page in the Tomte window). Closing it deselects the widget.

local UI = ns.UI
local WIDTH = 340
local PAD = 14
local TITLE_H = 40 -- title and the space under it
local ROW_INSET = 6 -- row edges inside the dialog
local INDENT = 16 -- rows with a parent
local BUTTONS_H = 44 -- the button row and the space under it
local GAP = 12 -- between the widget and the dialog
local DIMMED = 0.45

local dialog
local shownSpec -- the spec the dialog is showing
local rows = {}

local function Module()
	return shownSpec and shownSpec.module and ns.modulesByKey[shownSpec.module]
end

-- The module's options rows the spec names, in the spec's order, minus rows hidden for now (shown()).
local function PickedOptions(module)
	local byKey = {}
	for _, opt in ipairs(module and module.options or {}) do
		if opt.key and opt.type ~= "header" then
			byKey[opt.key] = opt
		end
	end
	local picked = {}
	for _, key in ipairs(shownSpec.options or {}) do
		local opt = byKey[key]
		if opt and (not opt.shown or opt.shown()) then
			picked[#picked + 1] = opt
		end
	end
	return picked
end

local function ReleaseRows()
	-- Taken out first: hiding a focused input saves it, which can ask for a rebuild from inside this loop.
	local released = rows
	rows = {}
	for _, row in ipairs(released) do
		ns.OptionRows_Release(row)
	end
end

local function Build()
	ReleaseRows()
	local module = Module()
	dialog.title:SetText(shownSpec.name)
	local picked = PickedOptions(module)
	dialog.visibility = ns.PanelLayout_Visibility(module and module.options or {})
	local inDialog = {}
	for _, opt in ipairs(picked) do
		inDialog[opt.key] = true
	end
	local y = TITLE_H
	for i, opt in ipairs(picked) do
		local row = ns.OptionRows_Acquire(opt.type, dialog)
		rows[#rows + 1] = row
		-- Indented under its parent switch when that's here too; dimmed while it's off either way.
		local under = opt.parent and inDialog[opt.parent]
		row:SetPoint("TOPLEFT", dialog, "TOPLEFT", ROW_INSET + (under and INDENT or 0), -y)
		row:SetPoint("RIGHT", dialog, "RIGHT", -ROW_INSET, 0)
		row.rule:SetShown(i > 1 and not under)
		row:SetAlpha(opt.parent and not ns.OptionRows_Get(module, opt.parent) and DIMMED or 1)
		ns.OptionRows_Setup(row, module, opt)
		y = y + row:GetHeight()
	end
	dialog.empty:SetShown(#rows == 0)
	if #rows == 0 then
		y = y + dialog.empty:GetStringHeight() + 4
	end

	dialog.reset:SetShown(shownSpec.reset ~= nil)
	dialog.all:SetShown(module ~= nil)
	dialog:SetHeight(y + 8 + BUTTONS_H)
end

-- Beside the widget's box: on its right when there's room, else on its left; top edges lined up.
local function Place(box)
	local scale = box:GetEffectiveScale() / dialog:GetEffectiveScale()
	local left, right, top = box:GetLeft() * scale, box:GetRight() * scale, box:GetTop() * scale
	local width = dialog:GetWidth()
	dialog:ClearAllPoints()
	if right + GAP + width <= UIParent:GetWidth() then
		dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + GAP, top)
	else
		dialog:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - GAP, top)
	end
end

local function Create()
	dialog = UI.Dialog("TomteEditModeDialog", WIDTH, 120) -- Escape closes it
	dialog.title = UI.Text(dialog, 14, "heading", "title")
	dialog.title:SetPoint("TOPLEFT", PAD, -12)
	dialog.title:SetPoint("RIGHT", -36, 0)
	dialog.title:SetJustifyH("LEFT")
	dialog.title:SetWordWrap(false)
	dialog.close = CreateFrame("Button", nil, dialog, "UIPanelCloseButtonNoScripts")
	dialog.close:SetPoint("TOPRIGHT", -2, -2)
	dialog.close:SetScript("OnClick", function()
		dialog:Hide()
	end)
	dialog.empty = UI.Text(dialog, 12, "textMuted")
	dialog.empty:SetPoint("TOPLEFT", PAD, -TITLE_H)
	dialog.empty:SetPoint("RIGHT", -PAD, 0)
	dialog.empty:SetJustifyH("LEFT")
	dialog.empty:SetText("Nothing to set here; drag it to move it.")

	dialog.all = UI.Button(dialog, 90, "All settings")
	dialog.all:SetHeight(22)
	UI.FitButton(dialog.all, 90, 24)
	dialog.all:SetPoint("BOTTOMRIGHT", -PAD, 14)
	dialog.all:SetScript("OnClick", function()
		local key = shownSpec.module
		dialog:Hide()
		ns.Panel_OpenModule(key)
	end)
	dialog.hide = UI.Button(dialog, 60, "Hide")
	dialog.hide:SetHeight(22)
	dialog.hide:SetPoint("BOTTOMLEFT", PAD, 14)
	dialog.hide:SetScript("OnClick", function()
		ns.EditMode_HideWidget(shownSpec)
	end)
	dialog.hide:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Hide", 1, 1, 1)
		GameTooltip:AddLine("Hides it until you close Edit Mode, to see what's under it.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	dialog.hide:HookScript("OnLeave", GameTooltip_Hide)
	dialog.reset = UI.Button(dialog, 110, "Reset position")
	dialog.reset:SetHeight(22)
	UI.FitButton(dialog.reset, 110, 24)
	dialog.reset:SetPoint("LEFT", dialog.hide, "RIGHT", 8, 0)
	dialog.reset:SetScript("OnClick", function()
		shownSpec.reset()
	end)

	dialog:HookScript("OnHide", function()
		ReleaseRows()
		shownSpec = nil
		ns.EditMode_Deselect()
	end)

	-- A setting that other rows hang on (a parent, a shown()) re-lays the rows; after the switch has slid, as on the
	-- module page. Any other change leaves them be: re-laying swaps the rows, which would end a slider's drag.
	ns.OptionRows_OnChange(function(module, key)
		if not (dialog:IsShown() and module == Module()) then
			return
		end
		local isParent = false
		for _, opt in ipairs(module.options or {}) do
			if key and opt.parent == key then
				isParent = true
			end
		end
		if not isParent and ns.PanelLayout_Visibility(module.options or {}) == dialog.visibility then
			return
		end
		local spec = shownSpec
		C_Timer.After(UI.SWITCH_SECONDS, function()
			if dialog:IsShown() and shownSpec == spec then
				Build()
			end
		end)
	end)
end

function ns.EditModeDialog_Show(spec)
	if not dialog then
		Create()
	end
	shownSpec = spec
	Build()
	Place(spec.box)
	dialog:Show()
	dialog:Raise()
end

function ns.EditModeDialog_Hide()
	if dialog and dialog:IsShown() then
		dialog:Hide()
	end
end
