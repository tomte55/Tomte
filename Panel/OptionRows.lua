local addonName, ns = ...

-- Settings rows: one factory per option row type (checkbox, slider, dropdown, button, input, key, status), pooled and
-- shared by everything that draws a module's options schema: the module page's cards (Options.lua) and the Edit Mode
-- settings dialog (EditModeDialog.lua). Schema extras read here: label (text or function), tooltip (a faint "?"
-- after the label), preview (a card drawn while the mouse is on the row, Preview.lua; only where the drawer sets
-- row.allowPreview). After a row changes a setting it tells the listeners (ns.OptionRows_OnChange), so whoever drew
-- it can rebuild rows that hang on it.

local UI = ns.UI
local OPT_H = 28
local CONTROL_W = 150
local SEGMENTS_MAX_W, SEGMENTS_MAX = 170, 3

local pools = {}
local listeners = {}

-- "frame.locked" -> db.frame, "locked"
local function Resolve(db, key)
	local tbl, last = db, nil
	for part in key:gmatch("[^.]+") do
		if last then
			tbl = tbl[last]
		end
		last = part
	end
	return tbl, last
end

local function GetOption(module, key)
	local tbl, field = Resolve(module.db, key)
	return tbl[field]
end

-- The default for an options key ("frame.locked" -> defaults.frame.locked), or nil.
local function DefaultOption(module, key)
	local value = module.defaults
	for part in key:gmatch("[^.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[part]
	end
	return value
end

-- fn(module, key) after a row changed module's setting key (key nil after a button ran).
function ns.OptionRows_OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Changed(module, key)
	for _, fn in ipairs(listeners) do
		fn(module, key)
	end
	ns.Preview_Refresh(module)
end

local function SetOption(module, spec, value)
	local tbl, field = Resolve(module.db, spec.key)
	tbl[field] = value
	if spec.onChange then
		spec.onChange(value)
	end
	Changed(module, spec.key)
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function LabelText(spec)
	return type(spec.label) == "function" and spec.label() or spec.label
end

-- The row's tooltip text, or its full label when the control cut it off.
local function RowTooltip(row)
	local spec = row.spec
	if not spec or not (spec.tooltip or row.label:IsTruncated()) then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(LabelText(spec), 1, 1, 1, 1, true)
	if spec.tooltip then
		GameTooltip:AddLine(spec.tooltip, nil, nil, nil, true)
	end
	GameTooltip:Show()
end

-- The mouse is on row (or one of its controls): its tooltip and, on the module pages, its preview (Preview.lua). has:
-- value is the choice under the mouse, label its text; anchor: the dropdown list's item it's on.
local function RowEnter(row, value, has, label, anchor)
	if not anchor then
		RowTooltip(row)
		UI.CardHoverPing(row) -- the card it sits on (Options.lua): reached straight onto a row, its OnEnter never came
	end
	-- previewInList: a dropdown whose preview only follows its open list (the theme), not the row itself.
	if row.allowPreview and (anchor or not row.spec.previewInList) then
		ns.Preview_Show(row, value, has, label, anchor)
	end
end

-- A slider being dragged keeps both until the drag ends.
local function RowLeave(row)
	if row.dragging then
		return
	end
	HideTooltip()
	ns.Preview_Hide(row)
end

-- The label, with a faint "?" when the row has a tooltip.
local function SetLabel(row, spec)
	local text = LabelText(spec) or ""
	if spec.tooltip then
		text = text .. "  " .. UI.Wrap("?", "textFaint")
	end
	row.label:SetText(text)
end

local Factory, Setup = {}, {}

local function NewRow(kind, parent)
	local row = CreateFrame("Frame", nil, parent)
	row.kind = kind
	row:SetHeight(OPT_H)
	row:EnableMouse(true)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	-- Released, or the page closed under the mouse (a drag cut short this way never gets its mouse-up).
	row:SetScript("OnHide", function(self)
		self.dragging = false
		ns.Preview_Hide(self)
	end)
	row.label = UI.Text(row, 13, "text")
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetWordWrap(false)
	row.rule = row:CreateTexture(nil, "BORDER")
	row.rule:SetColorTexture(UI.Color("rule"))
	row.rule:SetAlpha(0.35)
	row.rule:SetHeight(1)
	row.rule:SetPoint("TOPLEFT", 8, 0)
	row.rule:SetPoint("TOPRIGHT", -8, 0)
	return row
end

-- Long labels end at the control instead of running under it.
local function LabelUpTo(row, control)
	row.label:SetPoint("RIGHT", control, "LEFT", -8, 0)
end

local function ForwardHover(row, control)
	control:HookScript("OnEnter", function()
		RowEnter(row)
	end)
	control:HookScript("OnLeave", function()
		RowLeave(row)
	end)
end

function Factory.checkbox(parent)
	local row = NewRow("checkbox", parent)
	row.switch = UI.Switch(row)
	row.switch:SetPoint("RIGHT", -8, 0)
	LabelUpTo(row, row.switch)
	row.switch.onChange = function(checked)
		SetOption(row.module, row.spec, checked)
	end
	row:SetScript("OnMouseUp", function(self, button)
		-- The label toggles too: a left click released over the row (mouse-up also fires after a drag that
		-- started here and ended elsewhere).
		if button == "LeftButton" and self:IsMouseOver() then
			self.switch:Click()
		end
	end)
	ForwardHover(row, row.switch)
	return row
end

function Setup.checkbox(row, module, spec)
	SetLabel(row, spec)
	row.switch:SetChecked(GetOption(module, spec.key))
end

function Factory.slider(parent)
	local row = NewRow("slider", parent)
	row.value = UI.Text(row, 12, "text", "number")
	row.value:SetJustifyH("RIGHT")
	row.value:SetWidth(40)
	row.value:SetPoint("RIGHT", -8, 0)
	row.slider = UI.Slider(row, CONTROL_W - 50)
	row.slider:SetPoint("RIGHT", row.value, "LEFT", -10, 0)
	row.slider.valueText = row.value
	LabelUpTo(row, row.slider)
	row.slider.onChange = function(value)
		SetOption(row.module, row.spec, value)
	end
	ForwardHover(row, row.slider)
	row.slider:HookScript("OnMouseDown", function()
		row.dragging = true
	end)
	row.slider:HookScript("OnMouseUp", function()
		row.dragging = false
		if not row:IsMouseOver() then
			RowLeave(row)
		end
	end)
	return row
end

function Setup.slider(row, module, spec)
	SetLabel(row, spec)
	local s = row.slider
	s.format = spec.format or tostring
	s:SetMinMaxValues(spec.min, spec.max)
	s:SetValueStep(spec.step or 1)
	s:SetValue(GetOption(module, spec.key))
	row.value:SetText(s.format(s:GetValue()))
end

-- A dropdown, or segmented buttons when its few choices fit (decided per build: choices can change).
function Factory.dropdown(parent)
	local row = NewRow("dropdown", parent)
	-- A saved value that's no longer a choice (renamed or removed) shows as the default. Display only: choices can
	-- depend on what's loaded right now (characters, addons), so the saved value isn't overwritten.
	local function getValue()
		local spec = row.spec
		return ns.ChoiceOrDefault(GetOption(row.module, spec.key), spec.choices(), DefaultOption(row.module, spec.key))
	end
	local function setValue(value)
		SetOption(row.module, row.spec, value)
	end
	local function choices()
		return row.spec.choices()
	end
	local d = UI.Dropdown(row, CONTROL_W)
	d:SetPoint("RIGHT", -8, 0)
	d.getValue, d.setValue, d.choices = getValue, setValue, choices
	row.dropdown = d
	ForwardHover(row, d)
	-- An item under the mouse in the open list: its preview beside the list (nil when the mouse leaves the list).
	d.onHover = function(value, text, item)
		if item then
			RowEnter(row, value, true, text, item)
		else
			ns.Preview_Hide(row)
		end
	end
	local seg = UI.Segmented(row)
	seg:SetPoint("RIGHT", -8, 0)
	seg.getValue, seg.setValue, seg.choices = getValue, setValue, choices
	seg.onEnter = function(value, text)
		RowEnter(row, value, true, text)
	end
	seg.onLeave = function()
		RowLeave(row)
	end
	row.segments = seg
	return row
end

function Setup.dropdown(row, module, spec)
	SetLabel(row, spec)
	local seg = row.segments
	local useSegments = ns.PanelLayout_UseSegments(seg:Widths(spec.choices()), SEGMENTS_MAX_W, SEGMENTS_MAX)
	seg:SetShown(useSegments)
	row.dropdown:SetShown(not useSegments)
	if useSegments then
		seg:Refresh()
		LabelUpTo(row, seg)
	else
		row.dropdown:Refresh()
		LabelUpTo(row, row.dropdown)
	end
end

function Factory.button(parent)
	local row = NewRow("button", parent)
	row.button = UI.Button(row, 80, "")
	row.button:SetPoint("RIGHT", -8, 0)
	LabelUpTo(row, row.button)
	row.button:SetScript("OnClick", function()
		local spec, module = row.spec, row.module
		local function Run()
			spec.onClick()
			Changed(module)
		end
		if spec.confirm then
			ns.Confirm_Show(spec.confirm, Run)
		else
			Run()
		end
	end)
	ForwardHover(row, row.button)
	return row
end

function Setup.button(row, module, spec)
	SetLabel(row, spec)
	row.button.label:SetText(spec.text)
	UI.FitButton(row.button, 80, 24) -- room for "Reload now"
end

-- Text box; the value is saved on Enter or when the box loses focus (Esc restores the saved text).
function Factory.input(parent)
	local row = NewRow("input", parent)
	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(CONTROL_W, 20)
	box:SetPoint("RIGHT", -8, 0)
	box:SetAutoFocus(false)
	box.isOptionInput = true
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(6, 6, 0, 0)
	box:SetScript("OnHide", box.ClearFocus) -- saves before the row is reused for another option
	UI.Surface(box, 0.35)
	box.placeholder = UI.Text(box, 12, "textFaint")
	box.placeholder:SetPoint("LEFT", 6, 0)
	box.placeholder:SetPoint("RIGHT", -6, 0) -- a long hint ends in "..." inside the box
	box.placeholder:SetWordWrap(false)
	box:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(GetOption(row.module, row.spec.key) or "")
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		UI.BorderTo(self, "accent", 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.BorderTo(self, "frame", 0.35)
		local text = strtrim(self:GetText())
		if text ~= (GetOption(row.module, row.spec.key) or "") then
			SetOption(row.module, row.spec, text)
		end
	end)
	row.box = box
	LabelUpTo(row, box)
	ForwardHover(row, box)
	return row
end

function Setup.input(row, module, spec)
	SetLabel(row, spec)
	row.box:SetText(GetOption(module, spec.key) or "")
	row.box.placeholder:SetText(spec.placeholder or "")
	row.box:SetCursorPosition(0)
end

-- A key: click, then press a key combination to set it (saved as a binding string like "CTRL-C"); Esc cancels and a
-- right-click clears it (saved as ""). The row only listens while it waits for the key, and never in combat (keyboard
-- propagation can't be changed then).
local function KeyText(value)
	if type(value) ~= "string" or value == "" then
		return UI.Wrap("Not set", "textFaint")
	end
	return ns.KeyText(value)
end

local function StopListening(row)
	local button = row.keyButton
	if not (button.listening and row.module) then
		return
	end
	button.listening = false
	button:EnableKeyboard(false)
	UI.BorderTo(button, "frame", 0.35)
	button.label:SetText(KeyText(GetOption(row.module, row.spec.key)))
end

function Factory.key(parent)
	local row = NewRow("key", parent)
	local button = UI.Button(row, 110, "")
	button:SetPoint("RIGHT", -8, 0)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:EnableKeyboard(false)
	row.keyButton = button
	LabelUpTo(row, button)
	button:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			StopListening(row)
			SetOption(row.module, row.spec, "")
			self.label:SetText(KeyText(""))
			return
		end
		if self.listening then
			StopListening(row)
			return
		end
		if InCombatLockdown() then
			return
		end
		self.listening = true
		self:EnableKeyboard(true)
		UI.BorderTo(self, "accent", 0.8)
		self.label:SetText(UI.Wrap("Press a key...", "accent"))
	end)
	button:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			StopListening(row)
			return
		end
		self:SetPropagateKeyboardInput(false)
		if key == "ESCAPE" then
			StopListening(row)
			return
		end
		local chord = ns.KeyChord(key, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown())
		if chord then
			SetOption(row.module, row.spec, chord)
			StopListening(row)
		end
	end)
	button:SetScript("OnHide", function()
		StopListening(row)
	end)
	ForwardHover(row, button)
	return row
end

function Setup.key(row, module, spec)
	SetLabel(row, spec)
	row.keyButton.listening = false
	row.keyButton:EnableKeyboard(false)
	row.keyButton.label:SetText(KeyText(GetOption(module, spec.key)))
end

-- Read-only: the label and, on the right, spec.status() -> text, color role (asked on every build).
function Factory.status(parent)
	local row = NewRow("status", parent)
	row.value = UI.Text(row, 12, "textMuted")
	row.value:SetJustifyH("RIGHT")
	row.value:SetPoint("RIGHT", -8, 0)
	LabelUpTo(row, row.value)
	return row
end

function Setup.status(row, module, spec)
	SetLabel(row, spec)
	local text, role = spec.status()
	row.value:SetText(text or "")
	UI.SetTextRole(row.value, role or "textMuted")
end

-- A row of kind (a schema `type`) from the pool, shown, in parent.
-- spec: the option it's for. A rebuild hands each option the row it had before when it can, so a switch flipped by a
-- setting whose onChange rebuilds the page (the Tomte window's) keeps sliding instead of showing up already flipped.
function ns.OptionRows_Acquire(kind, parent, spec)
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	local row
	for i = #pool, 1, -1 do
		if spec and pool[i].spec == spec then
			row = table.remove(pool, i)
			break
		end
	end
	row = row or table.remove(pool) or Factory[kind](parent)
	row:SetParent(parent)
	row:Show()
	return row
end

-- Hides row and puts it back in its pool.
function ns.OptionRows_Release(row)
	row:Hide()
	row:ClearAllPoints()
	row:SetAlpha(1)
	row.allowPreview, row.dragging = nil, false
	local pool = pools[row.kind]
	pool[#pool + 1] = row
end

-- Fills an acquired row for module's option spec.
function ns.OptionRows_Setup(row, module, spec)
	row.module, row.spec = module, spec
	Setup[spec.type](row, module, spec)
end

-- The saved value of module's options key ("frame.locked").
function ns.OptionRows_Get(module, key)
	return GetOption(module, key)
end

-- The table that holds module's options key and the field in it ("frame.locked" -> db.frame, "locked").
function ns.OptionRows_Resolve(module, key)
	return Resolve(module.db, key)
end
