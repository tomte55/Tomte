local addonName, ns = ...

-- Settings panel. One frame, used standalone (/tomte, addon compartment; Esc closes it) and embedded in
-- Options > AddOns (re-parented into a canvas category while that page is open). Built on first use.
-- Left: search + categories. Center: modules with on/off checkboxes. Right: the hovered module's
-- description, or the selected module's options (built from its options schema) and/or its custom page
-- (Options and page tabs when it has both).

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local WIDTH, HEIGHT = 760, 480
local LEFT_W, CENTER_W = 170, 240
local TITLE_H = 36
local ROW_H = 24
local OPT_H = 28
local SCROLL_STEP = 40
local TAB_H = 22
local ALL = "All"

local panel, holder, escape
local mode -- "standalone" | "embedded"
local selected, hovered -- modules
local searchText = ""
local categoryButtons, moduleRows, listHeaders = {}, {}, {}
local pools, used = {}, {}
local builtFor -- module whose options are in the pane
local tabFor = {} -- [module] = "options" | "page" (modules with both), for this session
local Refresh, RefreshDetail -- forward declarations

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
	GameTooltip:SetText(spec.label, 1, 1, 1)
	GameTooltip:AddLine(spec.tooltip, nil, nil, nil, true)
	GameTooltip:Show()
end

-- Options rows: one factory per schema type. Rows are pooled per type and rebuilt per module.
local Factory, Setup = {}, {}

local function NewRow(kind)
	local row = CreateFrame("Frame", nil, panel.detail.content)
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

-- Long labels end at the control instead of running under it (the options column is narrow).
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
	local row = CreateFrame("Frame", nil, panel.detail.content)
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
	row:SetScript("OnMouseUp", function()
		row.check:Click() -- the label toggles too
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
	d.getValue = function()
		return GetOption(row.module, row.spec.key)
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
	row.label:SetText(spec.label)
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

local function ReleaseOptions()
	for _, row in ipairs(used) do
		row:Hide()
		row:ClearAllPoints()
		local pool = pools[row.kind]
		pool[#pool + 1] = row
	end
	wipe(used)
end

local function UpdateScrollThumb()
	local detail = panel.detail
	local viewH, contentH = detail.scroll:GetHeight(), detail.content:GetHeight()
	if contentH <= viewH + 1 then
		detail.thumb:Hide()
		return
	end
	local thumbH = math.max(viewH * viewH / contentH, 20)
	local offset = detail.scroll:GetVerticalScroll() / (contentH - viewH) * (viewH - thumbH)
	detail.thumb:SetHeight(thumbH)
	detail.thumb:ClearAllPoints()
	detail.thumb:SetPoint("TOPLEFT", detail.scroll, "TOPRIGHT", 4, -offset)
	detail.thumb:Show()
end

local function SetScroll(value)
	local detail = panel.detail
	local maxScroll = math.max(detail.content:GetHeight() - detail.scroll:GetHeight(), 0)
	detail.scroll:SetVerticalScroll(math.min(math.max(value, 0), maxScroll))
	UpdateScrollThumb()
end

local function BuildOptions(module)
	local detail = panel.detail
	local keepScroll = builtFor == module and detail.scroll:GetVerticalScroll() or 0
	builtFor = module
	local y = 0
	for _, spec in ipairs(module.options) do
		local row = Acquire(spec.type)
		row.module, row.spec = module, spec
		row:SetPoint("TOPLEFT", detail.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", detail.content, "RIGHT")
		Setup[spec.type](row, module, spec)
		y = y + row:GetHeight()
	end
	detail.content:SetHeight(math.max(y, 1))
	SetScroll(keepScroll)
end

function RefreshDetail()
	local detail = panel.detail
	local module = hovered or selected
	ReleaseOptions()
	if not module then
		detail.title:SetText("")
		detail.desc:SetText("")
		detail.reason:Hide()
		detail.scroll:Hide()
		detail.tabs:Hide()
		for _, frame in pairs(detail.pages) do
			frame:Hide()
		end
		detail.thumb:Hide()
		detail.empty:Show()
		return
	end
	detail.empty:Hide()
	detail.title:SetText(module.name)
	detail.desc:SetText(module.description or "")
	local reason = ns.ModuleBlockedReason(module)
	detail.reason:SetText(reason or "")
	detail.reason:SetShown(reason ~= nil)
	-- Options (or a custom page) only for the selected module, and not while it is blocked (its data is
	-- being replaced).
	local open = module == selected and reason == nil
	local hasTabs = open and module.page ~= nil and module.options ~= nil
	local tab = tabFor[module] or "options"
	detail.tabs:SetShown(hasTabs)
	-- Content starts under the description, or under the tabs.
	local top, topY = detail.desc, -14
	if hasTabs then
		detail.tabs.module = module
		detail.tabs.options:Set("Options", tab == "options")
		detail.tabs.page:Set(module.page.title or "Overview", tab == "page")
		top, topY = detail.tabs, -8
	end
	local showPage = open and module.page ~= nil and (not hasTabs or tab == "page")
	for owner, frame in pairs(detail.pages) do
		if owner ~= module or not showPage then
			frame:Hide()
		end
	end
	if showPage then
		local frame = detail.pages[module]
		if not frame then
			frame = CreateFrame("Frame", nil, detail)
			frame:Hide()
			module.page.Create(frame)
			detail.pages[module] = frame
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", top, "BOTTOMLEFT", -8, topY)
		frame:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -14, 12)
		if not frame:IsShown() then
			frame:Show()
			if module.page.Refresh then
				module.page.Refresh(frame) -- only when it becomes visible, not on every hover
			end
		end
	end
	local showOptions = open and not showPage and module.options ~= nil
	detail.scroll:SetShown(showOptions)
	if showOptions then
		detail.scroll:ClearAllPoints()
		detail.scroll:SetPoint("TOPLEFT", top, "BOTTOMLEFT", -8, topY)
		detail.scroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -14, 12)
		BuildOptions(module)
	else
		detail.thumb:Hide()
	end
end

local function SelectModule(module)
	selected = module
	Refresh()
end

local function CreateModuleRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.05)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.check = UI.Checkbox(row)
	row.check:SetPoint("LEFT", 12, 0)
	row.name = UI.Text(row, 13, WHITE)
	row.name:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
	row.name:SetPoint("RIGHT", -32, 0)
	row.name:SetWordWrap(false)
	row.gear = CreateFrame("Button", nil, row)
	row.gear:SetSize(16, 16)
	row.gear:SetPoint("RIGHT", -8, 0)
	row.gear.tex = row.gear:CreateTexture(nil, "ARTWORK")
	row.gear.tex:SetAllPoints()
	row.gear.tex:SetTexture(UI.GEAR)
	row.gear.tex:SetTexCoord(0, 0.5, 0, 0.5)
	row.gear.tex:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.7)

	-- Typing in an option's text box: hovering the list mustn't rebuild the options under it.
	local function Typing()
		local focus = GetCurrentKeyBoardFocus()
		return focus ~= nil and focus.isOptionInput == true
	end
	local function Enter()
		if Typing() then
			return
		end
		hovered = row.module
		row.bg:Show()
		row.gear.tex:SetAlpha(1)
		RefreshDetail()
	end
	local function Leave()
		if Typing() then
			return
		end
		if hovered == row.module then
			hovered = nil
		end
		row.bg:SetShown(selected == row.module)
		row.gear.tex:SetAlpha(0.7)
		RefreshDetail()
	end
	row:SetScript("OnEnter", Enter)
	row:SetScript("OnLeave", Leave)
	row.gear:SetScript("OnEnter", Enter)
	row.gear:SetScript("OnLeave", Leave)
	row.check:HookScript("OnEnter", Enter)
	row.check:HookScript("OnLeave", Leave)
	row:SetScript("OnClick", function()
		SelectModule(row.module)
	end)
	row.gear:SetScript("OnClick", function()
		SelectModule(row.module)
	end)
	row.check.onChange = function(checked)
		ns.SetModuleEnabled(row.module.key, checked)
		Refresh()
	end
	return row
end

local function SetRow(row, module)
	row.module = module
	local reason = ns.ModuleBlockedReason(module)
	row.check:SetChecked(ns.ModuleEnabled(module))
	row.check:SetEnabled(reason == nil)
	local c = reason and DIM or WHITE
	row.name:SetTextColor(c[1], c[2], c[3])
	row.name:SetText(module.name)
	row.bar:SetShown(selected == module)
	row.bg:SetShown(selected == module or hovered == module)
	row.gear:SetShown(module.options ~= nil)
end

local function RefreshList()
	local center = panel.center
	local category = ns.db.panel.category
	local all = category == ALL or searchText ~= ""
	local rowCount, headerCount, y = 0, 0, 12
	for _, cat in ipairs(ns.ModuleCategories()) do
		if all or cat == category then
			local first = true
			for _, module in ipairs(ns.modules) do
				if module.category == cat and ns.ModuleMatches(module, searchText) then
					if first then
						first = false
						headerCount = headerCount + 1
						local header = listHeaders[headerCount] or UI.Text(center, 11, GREY)
						listHeaders[headerCount] = header
						header:SetText(cat:upper())
						header:ClearAllPoints()
						header:SetPoint("TOPLEFT", center, "TOPLEFT", 14, -y - 6)
						header:Show()
						y = y + 24
					end
					rowCount = rowCount + 1
					local row = moduleRows[rowCount] or CreateModuleRow(center)
					moduleRows[rowCount] = row
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", center, "TOPLEFT", 4, -y)
					row:SetPoint("RIGHT", center, "RIGHT", -4, 0)
					SetRow(row, module)
					row:Show()
					y = y + ROW_H
				end
			end
		end
	end
	for i = rowCount + 1, #moduleRows do
		moduleRows[i]:Hide()
	end
	for i = headerCount + 1, #listHeaders do
		listHeaders[i]:Hide()
	end
	panel.noMatches:SetShown(rowCount == 0)
end

local function CreateCategoryButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(LEFT_W - 24, 22)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.1)
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(2)
	b.text = UI.Text(b, 13, WHITE)
	b.text:SetPoint("LEFT", 10, 0)
	b:SetScript("OnEnter", function(self)
		self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end)
	b:SetScript("OnLeave", function(self)
		local c = self.isSelected and GOLD or WHITE
		self.text:SetTextColor(c[1], c[2], c[3])
	end)
	b:SetScript("OnClick", function(self)
		ns.db.panel.category = self.category
		panel.search:SetText("") -- picking a category ends the search
		Refresh()
	end)
	return b
end

local function RefreshCategories()
	local cats = ns.ModuleCategories()
	local current = ns.db.panel.category
	local list = { ALL }
	local valid = current == ALL
	for _, cat in ipairs(cats) do
		list[#list + 1] = cat
		valid = valid or cat == current
	end
	if not valid then
		current = ALL
		ns.db.panel.category = ALL
	end
	for i, name in ipairs(list) do
		local b = categoryButtons[i] or CreateCategoryButton(panel.left)
		categoryButtons[i] = b
		b.category = name
		b.text:SetText(name)
		b.isSelected = name == current and searchText == ""
		b.bg:SetShown(b.isSelected)
		b.bar:SetShown(b.isSelected)
		local c = b.isSelected and GOLD or WHITE
		b.text:SetTextColor(c[1], c[2], c[3])
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", panel.left, "TOPLEFT", 12, -50 - (i - 1) * 24)
		b:Show()
	end
	for i = #list + 1, #categoryButtons do
		categoryButtons[i]:Hide()
	end
end

function Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	RefreshCategories()
	RefreshList()
	RefreshDetail()
end

local function CreateSearch(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(LEFT_W - 24, 22)
	box:SetPoint("TOPLEFT", 12, -14)
	box:SetAutoFocus(false)
	box:SetFont(STANDARD_TEXT_FONT, 12, "")
	box:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	box:SetTextInsets(8, 8, 0, 0)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, GOLD[1], GOLD[2], GOLD[3], 0.35)
	local placeholder = UI.Text(box, 12, DIM)
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search")
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText()
		placeholder:SetShown(text == "")
		searchText = text:lower()
		Refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.35)
	end)
	return box
end

local function CreateDetail(parent)
	local detail = CreateFrame("Frame", nil, parent)
	detail.title = UI.Text(detail, 20, GOLD, "Fonts\\MORPHEUS.TTF")
	detail.title:SetPoint("TOPLEFT", 20, -14)
	detail.title:SetPoint("RIGHT", -20, 0)
	detail.desc = UI.Text(detail, 12, GREY)
	detail.desc:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -6)
	detail.desc:SetPoint("RIGHT", -20, 0)
	detail.desc:SetWordWrap(true)
	detail.reason = UI.Text(detail, 12, { 1, 0.45, 0.35 })
	detail.reason:SetPoint("TOPLEFT", detail.desc, "BOTTOMLEFT", 0, -10)
	detail.reason:SetPoint("RIGHT", -20, 0)
	detail.reason:SetWordWrap(true)
	detail.empty = UI.Text(detail, 13, GREY)
	detail.empty:SetPoint("CENTER")
	detail.empty:SetText("Select a module to see its options.")
	detail.pages = {} -- [module] = frame for modules with a custom page

	-- Options / page tabs, for a module that has both.
	local tabs = CreateFrame("Frame", nil, detail)
	tabs:SetPoint("TOPLEFT", detail.desc, "BOTTOMLEFT", 0, -12)
	tabs:SetPoint("RIGHT", -20, 0)
	tabs:SetHeight(TAB_H)
	tabs:Hide()
	local baseline = tabs:CreateTexture(nil, "BACKGROUND")
	baseline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	baseline:SetHeight(1)
	baseline:SetPoint("BOTTOMLEFT")
	baseline:SetPoint("BOTTOMRIGHT")
	local function Tab(which)
		local b = CreateFrame("Button", nil, tabs)
		b:SetHeight(TAB_H)
		b.text = UI.Text(b, 12, GREY)
		b.text:SetPoint("BOTTOMLEFT", 0, 6)
		b.bar = b:CreateTexture(nil, "ARTWORK")
		b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		b.bar:SetHeight(2)
		b.bar:SetPoint("BOTTOMLEFT")
		b.bar:SetPoint("BOTTOMRIGHT")
		function b:Set(text, isSelected)
			self.isSelected = isSelected
			self.text:SetText(text)
			self:SetWidth(self.text:GetStringWidth())
			local c = isSelected and GOLD or GREY
			self.text:SetTextColor(c[1], c[2], c[3])
			self.bar:SetShown(isSelected)
		end
		b:SetScript("OnEnter", function(self)
			self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		end)
		b:SetScript("OnLeave", function(self)
			local c = self.isSelected and GOLD or GREY
			self.text:SetTextColor(c[1], c[2], c[3])
		end)
		b:SetScript("OnClick", function()
			if tabFor[tabs.module] ~= which then
				tabFor[tabs.module] = which
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				RefreshDetail()
			end
		end)
		return b
	end
	tabs.options = Tab("options")
	tabs.options:SetPoint("BOTTOMLEFT")
	tabs.page = Tab("page")
	tabs.page:SetPoint("BOTTOMLEFT", tabs.options, "BOTTOMRIGHT", 18, 0)
	detail.tabs = tabs

	detail.scroll = CreateFrame("ScrollFrame", nil, detail)
	detail.scroll:EnableMouseWheel(true)
	detail.content = CreateFrame("Frame", nil, detail.scroll)
	detail.content:SetSize(1, 1)
	detail.scroll:SetScrollChild(detail.content)
	detail.scroll:SetScript("OnSizeChanged", function(self, width)
		detail.content:SetWidth(width)
		UpdateScrollThumb()
	end)
	detail.scroll:SetScript("OnMouseWheel", function(self, delta)
		SetScroll(self:GetVerticalScroll() - delta * SCROLL_STEP)
	end)
	detail.thumb = detail:CreateTexture(nil, "OVERLAY")
	detail.thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	detail.thumb:SetWidth(2)
	detail.thumb:Hide()
	return detail
end

local function SetMode(newMode)
	mode = newMode
	local standalone = mode == "standalone"
	panel.titleBar:SetShown(standalone)
	panel.body:ClearAllPoints()
	panel.body:SetPoint("TOPLEFT", 0, standalone and -TITLE_H or 0)
	panel.body:SetPoint("BOTTOMRIGHT")
end

local function Build()
	panel = CreateFrame("Frame", "TomtePanel", UIParent)
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:Hide()
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(panel, GOLD[1], GOLD[2], GOLD[3], 0.45)

	-- Title bar: standalone only (Blizzard's settings frame has its own).
	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(TITLE_H)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
	end)
	local title = UI.Text(titleBar, 20, GOLD, "Fonts\\MORPHEUS.TTF")
	title:SetPoint("LEFT", 16, -2)
	title:SetText("Tomte")
	local close = UI.Button(titleBar, 20, "x")
	close:SetPoint("RIGHT", -10, 0)
	close:SetScript("OnClick", function()
		panel:Hide()
	end)
	local titleLine = UI.Hairline(titleBar, WIDTH - 40, 0.5)
	titleLine:SetPoint("BOTTOM")
	panel.titleBar = titleBar

	local body = CreateFrame("Frame", nil, panel)
	panel.body = body

	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LEFT_W)
	panel.left = left
	panel.search = CreateSearch(left)

	local center = CreateFrame("Frame", nil, body)
	center:SetPoint("TOPLEFT", left, "TOPRIGHT")
	center:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
	center:SetWidth(CENTER_W)
	panel.center = center
	panel.noMatches = UI.Text(center, 12, GREY)
	panel.noMatches:SetPoint("TOP", 0, -30)
	panel.noMatches:SetText("No matching modules.")

	local detail = CreateDetail(body)
	detail:SetPoint("TOPLEFT", center, "TOPRIGHT")
	detail:SetPoint("BOTTOMRIGHT")
	panel.detail = detail

	for _, column in ipairs({ left, center }) do
		local line = UI.VLine(body)
		line:SetPoint("TOP", column, "TOPRIGHT", 0, -12)
		line:SetPoint("BOTTOM", column, "BOTTOMRIGHT", 0, 12)
	end

	panel:SetScript("OnShow", function()
		if mode == "standalone" then
			escape:Show()
		end
		Refresh()
	end)
	panel:SetScript("OnHide", function()
		escape:Hide()
		hovered = nil
		HideTooltip()
		for _, module in ipairs(ns.modules) do
			if module.panelClosed then
				module.panelClosed()
			end
		end
	end)
end

function ns.Panel_Toggle()
	if holder:IsVisible() then
		return -- shown inside Options > AddOns right now
	end
	if not panel then
		Build()
	end
	if panel:IsShown() then
		panel:Hide()
		return
	end
	SetMode("standalone")
	panel:SetParent(UIParent)
	panel:SetFrameStrata("HIGH")
	panel:ClearAllPoints()
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetPoint("CENTER")
	panel:Show()
end

-- Called on ADDON_LOADED: registers the Options > AddOns page (a small holder frame). The panel itself
-- is built the first time it is shown.
function ns.Panel_Init()
	holder = CreateFrame("Frame")
	holder:Hide()
	local category = Settings.RegisterCanvasLayoutCategory(holder, "Tomte")
	Settings.RegisterAddOnCategory(category)
	holder:SetScript("OnShow", function(self)
		if not panel then
			Build()
		end
		panel:Hide()
		SetMode("embedded")
		panel:SetParent(self)
		-- The standalone strata would draw it under (or over) Blizzard's settings frame.
		panel:SetFrameStrata(self:GetFrameStrata())
		panel:SetFrameLevel(self:GetFrameLevel() + 1)
		panel:ClearAllPoints()
		panel:SetAllPoints(self)
		panel:Show()
	end)
	holder:SetScript("OnHide", function()
		if panel and mode == "embedded" then
			panel:Hide()
		end
	end)

	-- Esc closes the standalone panel: UISpecialFrames hides this dummy, which hides the panel.
	escape = CreateFrame("Frame", "TomtePanelEscape", UIParent)
	escape:Hide()
	table.insert(UISpecialFrames, "TomtePanelEscape")
	escape:SetScript("OnHide", function()
		if panel and mode == "standalone" then
			panel:Hide()
		end
	end)
end

-- Addon compartment (minimap addons button); named in the TOC, so it has to be global.
function Tomte_OnAddonCompartmentClick()
	ns.Panel_Toggle()
end
