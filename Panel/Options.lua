local addonName, ns = ...

-- Options for the panel's module page, built from a module's options schema as cards: each `header` row starts a
-- card (rows before the first header share an untitled one), dealt into one or two columns by width (Layout.lua).
-- One factory per row type; rows and cards are pooled and rebuilt per module. The reset buttons sit under the cards
-- as quiet links. Schema extras read here: tooltip (a faint "?" after the label), parent = "<key>" (indented and
-- dimmed while that option is off), shown() (hides the row; re-checked after every change on the page). Besides the
-- settings rows there is a read-only `status` row (status() -> text, color role on the right).

local UI = ns.UI
local OPT_H = 28
local CARD_TITLE_H = 30
local CARD_PAD = 8 -- above the first row of an untitled card and under the last row
local CARD_INSET = 6 -- row edges inside a card
local INDENT = 16 -- rows with a parent
local GAP = 14 -- between cards and columns
local MIN_COLUMN = 360 -- narrowest card in two columns: a long label beside a 150 px control
local MAX_CARD = 540 -- widest card: past this a switch ends up far from its label
local CONTROL_W = 150
local SEGMENTS_MAX_W, SEGMENTS_MAX = 170, 3
local FOOTER_H = 34
local DIMMED = 0.45

local parent -- the options scroll's content frame
local scrollFrame
local pools, used = {}, {}
local cardPool, cards = {}, {}
local links = {}
local builtFor -- module whose options are built
local builtVisibility -- ns.PanelLayout_Visibility of builtFor's options when they were built

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

local function IsParent(module, key)
	for _, spec in ipairs(module.options or {}) do
		if spec.parent == key then
			return true
		end
	end
	return false
end

-- Rebuilds module's options when rows hang on what just changed: a parent option (rows dim or light up) or a shown()
-- that answers differently now. After the switch has finished sliding: a rebuild would cut its animation short.
local function RebuildIfChanged(module, key)
	if builtFor ~= module or not scrollFrame then
		return
	end
	if not (key and IsParent(module, key)) and ns.PanelLayout_Visibility(module.options) == builtVisibility then
		return
	end
	local scroll = scrollFrame
	C_Timer.After(UI.SWITCH_SECONDS, function()
		if builtFor == module and scroll:IsVisible() then
			ns.PanelOptions_Build(scroll, module)
		end
	end)
end

local function SetOption(module, spec, value)
	local tbl, field = Resolve(module.db, spec.key)
	tbl[field] = value
	if spec.onChange then
		spec.onChange(value)
	end
	RebuildIfChanged(module, spec.key)
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

-- The label, with a faint "?" when the row has a tooltip.
local function SetLabel(row, spec)
	local text = LabelText(spec) or ""
	if spec.tooltip then
		text = text .. "  " .. UI.Wrap("?", "textFaint")
	end
	row.label:SetText(text)
end

local Factory, Setup = {}, {}

local function NewRow(kind)
	local row = CreateFrame("Frame", nil, parent)
	row.kind = kind
	row:SetHeight(OPT_H)
	row:EnableMouse(true)
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", HideTooltip)
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
		RowTooltip(row)
	end)
	control:HookScript("OnLeave", HideTooltip)
end

function Factory.checkbox()
	local row = NewRow("checkbox")
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

function Factory.slider()
	local row = NewRow("slider")
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
function Factory.dropdown()
	local row = NewRow("dropdown")
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
	local seg = UI.Segmented(row)
	seg:SetPoint("RIGHT", -8, 0)
	seg.getValue, seg.setValue, seg.choices = getValue, setValue, choices
	seg.onEnter = function()
		RowTooltip(row)
	end
	seg.onLeave = HideTooltip
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

function Factory.button()
	local row = NewRow("button")
	row.button = UI.Button(row, 80, "")
	row.button:SetPoint("RIGHT", -8, 0)
	LabelUpTo(row, row.button)
	row.button:SetScript("OnClick", function()
		local spec, module = row.spec, row.module
		local function Run()
			spec.onClick()
			RebuildIfChanged(module)
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
function Factory.input()
	local row = NewRow("input")
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
		UI.SetBorderColor(self, "accent", 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "frame", 0.35)
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

-- Read-only: the label and, on the right, spec.status() -> text, color role (asked on every build).
function Factory.status()
	local row = NewRow("status")
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

-- Cards -------------------------------------------------------------------------------------------------------

local function AcquireCard()
	local card = table.remove(cardPool)
	if not card then
		card = CreateFrame("Frame", nil, parent)
		UI.Surface(card, 0.35)
		card.title = UI.Text(card, 11, "accent", "label")
		card.title:SetPoint("TOPLEFT", 14, -11)
		card.title:SetPoint("RIGHT", -14, 0)
		card.title:SetWordWrap(false)
	end
	card:Show()
	cards[#cards + 1] = card
	return card
end

-- Reset links under the cards ---------------------------------------------------------------------------------

local function Link(i)
	local b = links[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, parent)
	b:SetHeight(18)
	b.text = UI.Text(b, 12, "textMuted")
	b.text:SetPoint("RIGHT")
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetColorTexture(UI.Color("textFaint"))
	b.line:SetHeight(1)
	b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
	b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
	b:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.text, "accent")
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.spec.label, 1, 1, 1)
		GameTooltip:AddLine(self.spec.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.text, "textMuted")
		HideTooltip()
	end)
	b:SetScript("OnClick", function(self)
		ns.Confirm_Show(self.spec.confirm, self.spec.onClick)
	end)
	links[i] = b
	return b
end

-- Reset links under every module's own options. Both reload the UI: modules keep state in closures.
local function ResetSpecs(module)
	local specs = {}
	if not module.defaults then
		return specs
	end
	local kept = "\n\nKept: what Tomte collected (history, alt data, flight times, tame log, caches) and lists you "
		.. "built (favorites, pins, hidden entries). Your UI reloads."
	specs[1] = { label = "Reset " .. module.name .. " to defaults",
		confirm = "Reset " .. module.name .. "'s settings to their defaults?" .. kept,
		onClick = function()
			ns.ResetModuleSettings(module)
			C_UI.Reload() -- needs a hardware event: the popup's Yes click is one
		end,
		tooltip = "Puts this module's settings back to how they start. Collected data and your lists stay." }
	if module.key == "window" then -- the Tomte window's page is the general one
		specs[2] = { label = "Reset all Tomte settings",
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

-- Layout ------------------------------------------------------------------------------------------------------

local shownLinks = 0

-- The cards a module's options make: a header starts one, rows before the first header get an untitled one, and a
-- section whose rows are all hidden (shown()) makes none. { title, specs }
local function Sections(module)
	local sections, section = {}, nil
	for _, spec in ipairs(module.options or {}) do
		if not spec.shown or spec.shown() then -- shown: optional function, false hides the row for now
			if spec.type == "header" then
				section = { title = spec.label, specs = {} }
				sections[#sections + 1] = section
			else
				if not section then
					section = { specs = {} }
					sections[#sections + 1] = section
				end
				section.specs[#section.specs + 1] = spec
			end
		end
	end
	local cardsOnly = {}
	for _, sec in ipairs(sections) do
		if #sec.specs > 0 then
			cardsOnly[#cardsOnly + 1] = sec
		end
	end
	return cardsOnly
end

-- How wide module's cards end up in width (the header lines its switch up with their right edge).
function ns.PanelOptions_Width(module, width)
	local count = #Sections(module)
	if count == 0 then
		return width
	end
	local _, _, cardsW = ns.PanelLayout_Cards(width, GAP, MIN_COLUMN, MAX_CARD, count)
	return cardsW
end

-- Places the built cards for the content width and sizes the scroll content.
local function Layout(width)
	if #cards == 0 and shownLinks == 0 then
		scrollFrame:SetContentHeight(1) -- every row hidden for now: no leftover height from the last module
		return
	end
	local columns, cardW, cardsW = ns.PanelLayout_Cards(width, GAP, MIN_COLUMN, MAX_CARD, #cards)
	local heights = {}
	for i, card in ipairs(cards) do
		heights[i] = card.height
	end
	local places, total = ns.PanelLayout_Deal(heights, columns, GAP)
	for i, card in ipairs(cards) do
		local place = places[i]
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", parent, "TOPLEFT", (place.column - 1) * (cardW + GAP), -place.y)
		card:SetWidth(cardW)
	end
	-- The links end at the cards' right edge.
	local x = 0
	for i = shownLinks, 1, -1 do
		local b = links[i]
		b:ClearAllPoints()
		b:SetPoint("TOPRIGHT", parent, "TOPLEFT", (#cards > 0 and cardsW or width) - x - 4, -(total + 12))
		x = x + b:GetWidth() + 20
	end
	scrollFrame:SetContentHeight(total + (shownLinks > 0 and FOOTER_H or 8))
end

function ns.PanelOptions_Release()
	-- Taken out of `used` first: hiding a focused input saves it, and that save can rebuild the options from inside
	-- this loop (a parent option, an onChange that refreshes the panel).
	local released = used
	used = {}
	for _, row in ipairs(released) do
		row:Hide()
		row:ClearAllPoints()
		row:SetParent(parent)
		row:SetAlpha(1)
		local pool = pools[row.kind]
		pool[#pool + 1] = row
	end
	local releasedCards = cards
	cards = {}
	for _, card in ipairs(releasedCards) do
		card:Hide()
		card:ClearAllPoints()
		cardPool[#cardPool + 1] = card
	end
	for _, b in ipairs(links) do
		b:Hide()
	end
	shownLinks = 0
end

local Build -- forward declaration
local building = false

-- Builds module's options into scroll.content (a UI.Scroll). Rebuilding the same module keeps the scroll offset.
function ns.PanelOptions_Build(scroll, module)
	if building then
		-- Asked again from inside a build (an input saving as it's hidden): once this one is done.
		C_Timer.After(0, function()
			if not building and builtFor == module and scroll:IsVisible() then
				ns.PanelOptions_Build(scroll, module)
			end
		end)
		return
	end
	building = true
	-- An error in a module's choices() or label() still reaches BugSack, and the guard comes off either way.
	xpcall(Build, ns.errorHandler, scroll, module)
	building = false
end

function Build(scroll, module)
	parent = scroll.content
	scrollFrame = scroll
	local keepScroll = builtFor == module and scroll:GetVerticalScroll() or 0
	ns.PanelOptions_Release()
	builtFor = module
	builtVisibility = ns.PanelLayout_Visibility(module.options)

	for _, sec in ipairs(Sections(module)) do
		local card = AcquireCard()
		card.title:SetText(sec.title and sec.title:upper() or "")
		card.title:SetShown(sec.title ~= nil)
		local y = sec.title and CARD_TITLE_H or CARD_PAD
		for i, spec in ipairs(sec.specs) do
			local row = Acquire(spec.type)
			row:SetParent(card)
			row.module, row.spec = module, spec
			local indent = spec.parent and INDENT or 0
			row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET + indent, -y)
			row:SetPoint("RIGHT", card, "RIGHT", -CARD_INSET, 0)
			row.rule:SetShown(i > 1 and not spec.parent)
			row:SetAlpha(spec.parent and not GetOption(module, spec.parent) and DIMMED or 1)
			Setup[spec.type](row, module, spec)
			y = y + row:GetHeight()
		end
		card.height = y + CARD_PAD
		card:SetHeight(card.height)
	end

	for i, spec in ipairs(ResetSpecs(module)) do
		local b = Link(i)
		b.spec = spec
		b.text:SetText(spec.label)
		b:SetWidth(b.text:GetStringWidth())
		b:Show()
		shownLinks = i
	end

	scroll.onWidthChanged = Layout
	Layout(scroll:GetWidth())
	scroll:SetScroll(keepScroll)
end
