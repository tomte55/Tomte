local addonName, ns = ...

-- Widgets: the input controls of ns.UI: checkbox, buttons (sized to their text, collapse, follow box), slider
-- and dropdown, and UI.TopLeftPoint for saving where a frame sits. The rest of the widget kit is in Widgets.lua,
-- Scroll.lua and Controls.lua.

local COLLAPSE_POLL = 0.1 -- seconds between hover checks for the collapse button
local Theme = ns.Theme
local UI = ns.UI

-- Controls ----------------------------------------------------------------------------------------------------

function UI.Checkbox(parent)
	if Theme.panel == "forever" then
		return UI.Forever_Checkbox(parent)
	end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(14, 14)
	b:SetHitRectInsets(-4, -4, -4, -4)
	UI.Surface(b, 0.7)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", 3, -3)
	b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
	b.fill:SetColorTexture(Theme.Color("accent"))
	function b:SetChecked(on)
		self.checked = on and true or false
		self.fill:SetShown(self.checked)
	end
	b:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if self.checked then
			UI.Pop(self.fill, 0.4)
		end
		UI.Sound(self.checked and "on" or "off")
		if self.onChange then
			self.onChange(self.checked)
		end
	end)
	b:SetScript("OnEnter", function(self)
		UI.BorderTo(self, "accent", 1)
	end)
	b:SetScript("OnLeave", function(self)
		UI.BorderTo(self, "frame", 0.7)
	end)
	b:SetScript("OnEnable", function(self)
		self:SetAlpha(1)
	end)
	b:SetScript("OnDisable", function(self)
		self:SetAlpha(0.35)
	end)
	b:SetChecked(false)
	return b
end

-- Button: a dark fill with a thin frame-colored border (accent while hovered), label in the title font (a one-letter
-- label like x, + or - in the body font). b.label is the font string; UI.SetBorderColor(b, ...) recolors the border.
local BUTTON_RULE = 0.5
-- Cinzel has no descenders but its line box keeps room for them, so centered capitals sit high: nudge them down.
local LABEL_Y = -1
UI.BUTTON_RULE = BUTTON_RULE -- for buttons that recolor their rules themselves

function UI.Button(parent, width, text)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 20)
	-- The Forever theme draws the game's own buttons: its art has rounded ends, so no square wash or border on it.
	local forever = Theme.panel == "forever"
	if not forever then
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(Theme.Color("surface"))
	end
	UI.HoverWash(b)
	UI.Border(b, "frame", BUTTON_RULE)
	if forever then
		b.hoverWash:Hide()
		for _, t in ipairs(b.borderEdges) do
			t:Hide()
		end
		if text == "x" then
			UI.Forever_CloseArt(b)
		else
			UI.Forever_ButtonArt(b)
		end
	end
	local single = text ~= nil and #text == 1
	b.label = single and UI.Text(b, 13, "heading") or UI.Text(b, 11, "heading", "label")
	b.label:SetJustifyH("CENTER")
	b.label:SetPoint("CENTER", 0, single and 0 or LABEL_Y)
	b.label:SetText((forever and text == "x") and "" or text) -- the close art has its own x
	b.labelY = single and 0 or LABEL_Y
	b:SetScript("OnEnter", function(self)
		UI.HoverOn(self)
	end)
	b:SetScript("OnLeave", function(self)
		UI.HoverOff(self, "frame", BUTTON_RULE)
	end)
	b:SetScript("OnMouseDown", function(self)
		self.label:SetPoint("CENTER", 1, self.labelY - 1)
		if self:IsEnabled() then
			UI.Press(self)
		end
		if self.artState then
			self.artState(self, "Down")
		end
	end)
	b:SetScript("OnMouseUp", function(self)
		self.label:SetPoint("CENTER", 0, self.labelY)
		if self.artState then
			self.artState(self, "Up")
		end
	end)
	return b
end

-- Sizes a UI.Button to its label: at least minWidth, label width + pad (default 24). unbounded uses
-- GetUnboundedStringWidth.
function UI.FitButton(button, minWidth, pad, unbounded)
	local fs = button.label
	local w = unbounded and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	button:SetWidth(math.max(minWidth or 0, math.ceil(w) + (pad or 24)))
end

-- On-screen widgets (Almost Done, Crafting list): a minus/plus in the top-right corner that shows while the mouse is
-- over the widget and folds it down to its title. isCollapsed() reads the saved state, onToggle() flips it and
-- redraws. The widget's own OnEnter can't tell (its rows take the mouse), so the button polls IsMouseOver, a few
-- times a second.
function UI.CollapseButton(frame, isCollapsed, onToggle)
	local b = CreateFrame("Button", nil, frame)
	b:SetSize(16, 16)
	b:SetPoint("TOPRIGHT", -4, -3)
	b:SetFrameLevel(frame:GetFrameLevel() + 20) -- above the unlocked drag cover
	b:SetHitRectInsets(-3, -3, -3, -3)
	b.across = b:CreateTexture(nil, "ARTWORK")
	b.across:SetSize(9, 2)
	b.across:SetPoint("CENTER")
	b.down = b:CreateTexture(nil, "ARTWORK")
	b.down:SetSize(2, 9)
	b.down:SetPoint("CENTER")
	local function Color(role)
		b.across:SetColorTexture(Theme.Color(role))
		b.down:SetColorTexture(Theme.Color(role))
	end
	function b:Update()
		self.down:SetShown(isCollapsed())
		Color(self:IsMouseOver() and "accent" or "textMuted")
	end
	b:SetScript("OnEnter", function(self)
		self:Update()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(isCollapsed() and "Expand" or "Minimize", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self:Update()
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		onToggle()
		UI.Sound("pick")
		self:Update()
		if self:IsMouseOver() then
			self:GetScript("OnEnter")(self)
		end
	end)
	b:Hide()
	local sinceCheck = 0
	frame:HookScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < COLLAPSE_POLL then
			return
		end
		sinceCheck = 0
		local over = frame:IsMouseOver()
		if over ~= b:IsShown() then
			b:SetShown(over)
			b:Update()
		end
	end)
	frame:HookScript("OnHide", function()
		b:Hide()
	end)
	b:Update()
	return b
end

-- On-screen widgets with a follow mode (Next quests, Quest list): a small box left of the widget's UI.CollapseButton,
-- shown with it on mouseover, filled while isOn() (drawn from color bars like the minimize button); its outline lights
-- up on hover. onToggle() flips the state and redraws; tip(on) returns the tooltip's title and line.
local FOLLOW_BOX, FOLLOW_FILL, FOLLOW_EDGE = 10, 4, 1 -- pixels: the outline's size, the filling's, the outline's width

function UI.FollowBox(frame, isOn, onToggle, tip)
	local b = CreateFrame("Button", nil, frame)
	b:SetSize(16, 16)
	b:SetPoint("RIGHT", frame.collapse, "LEFT", -2, 0)
	b:SetFrameLevel(frame.collapse:GetFrameLevel())
	b:SetHitRectInsets(-3, -3, -3, -3)
	b.edges = {}
	local half = (FOLLOW_BOX - FOLLOW_EDGE) / 2
	for i, side in ipairs({ { 0, half, FOLLOW_BOX, FOLLOW_EDGE }, { 0, -half, FOLLOW_BOX, FOLLOW_EDGE },
		{ -half, 0, FOLLOW_EDGE, FOLLOW_BOX }, { half, 0, FOLLOW_EDGE, FOLLOW_BOX } }) do
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetSize(side[3], side[4])
		t:SetPoint("CENTER", side[1], side[2])
		b.edges[i] = t
	end
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetSize(FOLLOW_BOX - FOLLOW_FILL, FOLLOW_BOX - FOLLOW_FILL)
	b.fill:SetPoint("CENTER")
	function b:Update()
		local edge = self:IsMouseOver() and "accent" or "textMuted"
		for _, t in ipairs(self.edges) do
			t:SetColorTexture(Theme.Color(edge))
		end
		self.fill:SetColorTexture(Theme.Color("accent"))
		self.fill:SetShown(isOn())
	end
	local function Tip(self)
		local title, line = tip(isOn())
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(title, 1, 1, 1)
		UI.TipLine(line, "textMuted", true)
		GameTooltip:Show()
	end
	b:SetScript("OnEnter", function(self)
		self:Update()
		Tip(self)
	end)
	b:SetScript("OnLeave", function(self)
		self:Update()
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		onToggle()
		UI.Sound("pick")
		self:Update()
		Tip(self)
	end)
	b:Hide()
	frame.collapse:HookScript("OnShow", function()
		b:Update()
		b:Show()
	end)
	frame.collapse:HookScript("OnHide", function()
		b:Hide()
	end)
	return b
end

-- Saves a moved widget by its top-left corner, so growing, shrinking or folding it keeps the title where it was
-- (StopMovingOrSizing can leave it anchored by its center or bottom). Returns { point, relPoint, x, y }.
function UI.TopLeftPoint(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top) then
		local point, _, relPoint, x, y = frame:GetPoint(1)
		return { point, relPoint, x, y }
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	return { "TOPLEFT", "BOTTOMLEFT", left, top }
end

-- Drag-only slider (no mouse wheel: the options pane scrolls with the wheel).
local SLIDER_THUMB_W, SLIDER_THUMB_H = 6, 12 -- grows a little while hovered or dragged
function UI.Slider(parent, width)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, 14)
	s:SetHitRectInsets(0, 0, -4, -4)
	s:SetObeyStepOnDrag(true)
	-- Track and fill are one screen pixel high and unsnapped, as Edges does: a snapped 1-unit line rounds to nothing
	-- on some rows (the opacity slider showed only its thumb).
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(Theme.Color("frame"))
	track:SetAlpha(0.45)
	track:SetTexelSnappingBias(0)
	track:SetSnapToPixelGrid(false)
	PixelUtil.SetHeight(track, 1, 1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(Theme.Color("accent"))
	thumb:SetSize(SLIDER_THUMB_W, SLIDER_THUMB_H)
	s:SetThumbTexture(thumb)
	local function Grow(on)
		local fromW, fromH = thumb:GetSize()
		local toW, toH = SLIDER_THUMB_W + (on and 2 or 0), SLIDER_THUMB_H + (on and 4 or 0)
		UI.Tween(thumb, "grow", 0.12, function(t)
			thumb:SetSize(UI.Lerp(fromW, toW, t), UI.Lerp(fromH, toH, t))
		end, nil, on and UI.EaseOutBack or nil)
	end
	s:SetScript("OnEnter", function()
		Grow(true)
	end)
	s:SetScript("OnLeave", function(self)
		if not self.dragging then
			Grow(false)
		end
	end)
	s:SetScript("OnMouseDown", function(self)
		self.dragging = true
	end)
	s:SetScript("OnMouseUp", function(self)
		self.dragging = false
		if not self:IsMouseOver() then
			Grow(false)
		end
	end)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(Theme.Color("accent"))
	fill:SetAlpha(0.8)
	fill:SetTexelSnappingBias(0)
	fill:SetSnapToPixelGrid(false)
	PixelUtil.SetHeight(fill, 1, 1)
	fill:SetPoint("LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")
	s:SetScript("OnValueChanged", function(self, value, userInput)
		if self.valueText then
			self.valueText:SetText((self.format or tostring)(value))
		end
		if userInput and self.valueText and value ~= self.lastPopped then
			self.lastPopped = value
			UI.Pop(self.valueText, 0.12)
		end
		if userInput and self.onChange then
			self.onChange(value)
		end
	end)
	return s
end

-- Button showing the current choice; a click opens the themed choice list (UI.OpenChoiceList, Menu.lua). Set
-- getValue, setValue and choices; optional onHover(value, text, item) follows the mouse over the open list.
function UI.Dropdown(parent, width)
	local b = UI.Button(parent, width, "")
	if b.artPlain then
		b.artPlain(b) -- a field, not a red button
	end
	b.label:ClearAllPoints()
	Theme.SetFont(b.label, "body", 12)
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -18, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	UI.SetTextRole(b.label, "text")
	b:SetScript("OnMouseDown", nil)
	b:SetScript("OnMouseUp", nil)
	local arrow = UI.Text(b, 11, "accent")
	arrow:SetPoint("RIGHT", -7, 0)
	arrow:SetText("v")
	b.arrow = arrow -- "^" while its list is open
	function b:Refresh()
		local value = self.getValue()
		for _, choice in ipairs(self.choices()) do
			if choice.value == value then
				self.label:SetText(choice.text)
				return
			end
		end
		self.label:SetText("")
	end
	local function IsSelected(value)
		return b.getValue() == value
	end
	local function SetSelected(value)
		b.setValue(value)
		b:Refresh()
	end
	b:SetScript("OnClick", function(self)
		if UI.ChoiceListOwner() == self then
			UI.CloseChoiceList()
		else
			UI.OpenChoiceList(self, self.choices(), IsSelected, SetSelected, self.onHover)
		end
	end)
	b:HookScript("OnHide", function(self)
		if UI.ChoiceListOwner() == self then
			UI.CloseChoiceList()
		end
	end)
	return b
end
