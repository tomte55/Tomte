local addonName, ns = ...

-- Options rows for the panel's module page, built from a module's options schema. One factory per schema type;
-- rows are pooled per type and rebuilt per module.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local OPT_H = 28

local parent -- the options scroll's content frame
local pools, used = {}, {}
local builtFor -- module whose options are built

StaticPopupDialogs.TOMTE_CONFIRM = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, onAccept)
		onAccept()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

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

local function SetOption(module, spec, value)
	local tbl, field = Resolve(module.db, spec.key)
	tbl[field] = value
	if spec.onChange then
		spec.onChange(value)
	end
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function RowTooltip(row)
	local spec = row.spec
	if not (spec and spec.tooltip) then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(type(spec.label) == "function" and spec.label() or spec.label, 1, 1, 1)
	GameTooltip:AddLine(spec.tooltip, nil, nil, nil, true)
	GameTooltip:Show()
end

local Factory, Setup = {}, {}

local function NewRow(kind)
	local row = CreateFrame("Frame", nil, parent)
	row.kind = kind
	row:SetHeight(OPT_H)
	row:EnableMouse(true)
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", HideTooltip)
	row.label = UI.Text(row, 13, WHITE)
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetWordWrap(false)
	return row
end

-- Long labels end at the control instead of running under it.
local function LabelUpTo(row, control)
	row.label:SetPoint("RIGHT", control, "LEFT", -8, 0)
end

local function ForwardHover(row, control)
	control:HookScript("OnEnter", function()
		RowTooltip(row)
	end)
	control:HookScript("OnLeave", HideTooltip)
end

function Factory.header()
	local row = CreateFrame("Frame", nil, parent)
	row.kind = "header"
	row:SetHeight(34)
	row.label = UI.Text(row, 14, GOLD)
	row.label:SetPoint("BOTTOMLEFT", 4, 9)
	local line = row:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 4, 4)
	line:SetPoint("BOTTOMRIGHT", -4, 4)
	return row
end

function Setup.header(row, module, spec)
	row.label:SetText(spec.label)
end

function Factory.checkbox()
	local row = NewRow("checkbox")
	row.check = UI.Checkbox(row)
	row.check:SetPoint("LEFT", 8, 0)
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
	row.check.onChange = function(checked)
		SetOption(row.module, row.spec, checked)
	end
	row:SetScript("OnMouseUp", function(self, button)
		-- The label toggles too: a left click released over the row (mouse-up also fires after a drag that
		-- started here and ended elsewhere).
		if button == "LeftButton" and self:IsMouseOver() then
			self.check:Click()
		end
	end)
	ForwardHover(row, row.check)
	return row
end

function Setup.checkbox(row, module, spec)
	row.label:SetText(spec.label)
	row.check:SetChecked(GetOption(module, spec.key))
end

function Factory.slider()
	local row = NewRow("slider")
	row.value = UI.Text(row, 12, WHITE)
	row.value:SetJustifyH("RIGHT")
	row.value:SetWidth(40)
	row.value:SetPoint("RIGHT", -6, 0)
	row.slider = UI.Slider(row, 150)
	row.slider:SetPoint("RIGHT", row.value, "LEFT", -10, 0)
	row.slider.valueText = row.value
	LabelUpTo(row, row.slider)
	row.slider.onChange = function(value)
		SetOption(row.module, row.spec, value)
	end
	ForwardHover(row, row.slider)
	return row
end

function Setup.slider(row, module, spec)
	row.label:SetText(spec.label)
	local s = row.slider
	s.format = spec.format or tostring
	s:SetMinMaxValues(spec.min, spec.max)
	s:SetValueStep(spec.step or 1)
	s:SetValue(GetOption(module, spec.key))
	row.value:SetText(s.format(s:GetValue()))
end

function Factory.dropdown()
	local row = NewRow("dropdown")
	local d = UI.Dropdown(row, 170)
	d:SetPoint("RIGHT", -6, 0)
	-- A saved value that's no longer a choice (renamed or removed) shows as the default. Display only: choices can
	-- depend on what's loaded right now (characters, addons), so the saved value isn't overwritten.
	d.getValue = function()
		local spec = row.spec
		return ns.ChoiceOrDefault(GetOption(row.module, spec.key), spec.choices(), DefaultOption(row.module, spec.key))
	end
	d.setValue = function(value)
		SetOption(row.module, row.spec, value)
	end
	d.choices = function()
		return row.spec.choices()
	end
	row.dropdown = d
	LabelUpTo(row, d)
	ForwardHover(row, d)
	return row
end

function Setup.dropdown(row, module, spec)
	row.label:SetText(spec.label)
	row.dropdown:Refresh()
end

function Factory.button()
	local row = NewRow("button")
	row.button = UI.Button(row, 80, "")
	row.button:SetPoint("RIGHT", -6, 0)
	LabelUpTo(row, row.button)
	row.button:SetScript("OnClick", function()
		local spec = row.spec
		if spec.confirm then
			-- data on the returned dialog reaches OnAccept (warcraft.wiki.gg: Creating simple pop-up dialog boxes).
			local dialog = StaticPopup_Show("TOMTE_CONFIRM", spec.confirm)
			if dialog then
				dialog.data = spec.onClick
			end
		else
			spec.onClick()
		end
	end)
	ForwardHover(row, row.button)
	return row
end

function Setup.button(row, module, spec)
	row.label:SetText(type(spec.label) == "function" and spec.label() or spec.label)
	row.button.label:SetText(spec.text)
end

-- Text box; the value is saved on Enter or when the box loses focus (Esc restores the saved text).
function Factory.input()
	local row = NewRow("input")
	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(170, 20)
	box:SetPoint("RIGHT", -6, 0)
	box:SetAutoFocus(false)
	box.isOptionInput = true
	box:SetFont(STANDARD_TEXT_FONT, 12, "")
	box:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	box:SetTextInsets(6, 6, 0, 0)
	box:SetScript("OnHide", box.ClearFocus) -- saves before the row is reused for another option
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, GOLD[1], GOLD[2], GOLD[3], 0.35)
	box.placeholder = UI.Text(box, 12, DIM)
	box.placeholder:SetPoint("LEFT", 6, 0)
	box:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(GetOption(row.module, row.spec.key) or "")
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.35)
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
	row.label:SetText(spec.label)
	row.box:SetText(GetOption(module, spec.key) or "")
	row.box.placeholder:SetText(spec.placeholder or "")
	row.box:SetCursorPosition(0)
end

local function Acquire(kind)
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	local row = table.remove(pool) or Factory[kind]()
	row:Show()
	used[#used + 1] = row
	return row
end

function ns.PanelOptions_Release()
	for _, row in ipairs(used) do
		row:Hide()
		row:ClearAllPoints()
		local pool = pools[row.kind]
		pool[#pool + 1] = row
	end
	wipe(used)
end

-- Reset rows added below every module's own options. Both reload the UI: modules keep state in closures.
local function ResetSpecs(module)
	local specs = {}
	if not module.defaults then
		return specs
	end
	local kept = "\n\nKept: what Tomte collected (history, alt data, flight times, tame log, caches) and lists you "
		.. "built (favorites, pins, hidden entries). Your UI reloads."
	specs[1] = { type = "header", label = "Reset" }
	specs[2] = { type = "button", label = "Reset " .. module.name .. " to defaults", text = "Reset",
		confirm = "Reset " .. module.name .. "'s settings to their defaults?" .. kept,
		onClick = function()
			ns.ResetModuleSettings(module)
			C_UI.Reload() -- needs a hardware event: the popup's Yes click is one
		end,
		tooltip = "Puts this module's settings back to how they start. Collected data and your lists stay." }
	if module.key == "window" then -- the Tomte window's page is the general one
		specs[3] = { type = "button", label = "Reset all Tomte settings", text = "Reset all",
			confirm = "Reset every Tomte setting to its default, including which modules are on and where the window "
				.. "sits?" .. kept,
			onClick = function()
				ns.ResetAll()
				C_UI.Reload() -- needs a hardware event: the popup's Yes click is one
			end,
			tooltip = "Every module's settings, which modules are on, and the window's size and place back to "
				.. "defaults. Collected data and your lists stay." }
	end
	return specs
end

-- Builds module's options into scroll.content (a UI.Scroll). Rebuilding the same module keeps the scroll offset.
function ns.PanelOptions_Build(scroll, module)
	parent = scroll.content
	local keepScroll = builtFor == module and scroll:GetVerticalScroll() or 0
	ns.PanelOptions_Release()
	builtFor = module
	local y = 0
	local specs = {}
	for _, spec in ipairs(module.options or {}) do
		specs[#specs + 1] = spec
	end
	for _, spec in ipairs(ResetSpecs(module)) do
		specs[#specs + 1] = spec
	end
	for _, spec in ipairs(specs) do
		local row = Acquire(spec.type)
		row.module, row.spec = module, spec
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", parent, "RIGHT")
		Setup[spec.type](row, module, spec)
		y = y + row:GetHeight()
	end
	scroll:SetContentHeight(y)
	scroll:SetScroll(keepScroll)
end
