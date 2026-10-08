local addonName, ns = ...

-- Dark/gold widgets for the settings panel, drawn from color textures and font strings (no art files).

local UI = {}
ns.UI = UI

UI.GOLD = { 1, 0.82, 0.45 }
UI.WHITE = { 0.92, 0.92, 0.92 }
UI.GREY = { 0.62, 0.62, 0.62 }
UI.DIM = { 0.4, 0.4, 0.4 }
UI.BG = { 0.06, 0.06, 0.07, 0.96 }
UI.BOX = { 0.11, 0.11, 0.12, 1 }
-- The top-left quarter of this texture is a gear (used the same way by Leatrix Maps).
UI.GEAR = "Interface\\WorldMap\\Gear_64.png"

local GOLD = UI.GOLD

function UI.Text(parent, size, color, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(font or STANDARD_TEXT_FONT, size, "")
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowOffset(1, -1)
	fs:SetJustifyH("LEFT")
	return fs
end

-- Search boxes: fn runs once typing pauses for `seconds` (each call restarts the wait).
UI.SEARCH_DELAY = 0.25

function UI.Debounce(seconds, fn)
	local timer
	return function()
		if timer then
			timer:Cancel()
		end
		timer = C_Timer.NewTimer(seconds, function()
			timer = nil
			fn()
		end)
	end
end

-- 1px border inside the frame's edges.
function UI.Border(frame, r, g, b, a)
	local edges = {}
	local sides = {
		{ "TOPLEFT", "TOPRIGHT" },
		{ "BOTTOMLEFT", "BOTTOMRIGHT" },
		{ "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" },
	}
	for i, points in ipairs(sides) do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(r, g, b, a or 1)
		t:SetPoint(points[1])
		t:SetPoint(points[2])
		-- Exactly one screen pixel: below a UI scale of 1 a 1-unit edge can round to nothing (clipped-looking buttons),
		-- and pixel-grid snapping rounds an edge's two sides on their own, so boxes off the pixel grid got edges of 0, 1
		-- or 2 pixels (measured 2026-10-08 on the vault slots). Unsnapped, a solid 1-pixel quad always fills one row.
		t:SetTexelSnappingBias(0)
		t:SetSnapToPixelGrid(false)
		if i <= 2 then
			PixelUtil.SetHeight(t, 1, 1)
		else
			PixelUtil.SetWidth(t, 1, 1)
		end
		edges[i] = t
	end
	frame.borderEdges = edges
end

function UI.SetBorderColor(frame, r, g, b, a)
	for _, t in ipairs(frame.borderEdges) do
		t:SetColorTexture(r, g, b, a or 1)
	end
end

-- Gold hairline that fades out at both ends, like the cinematic's. Returns a frame `width` wide.
function UI.Hairline(parent, width, alpha)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, 1)
	local solid, clear = CreateColor(GOLD[1], GOLD[2], GOLD[3], alpha or 0.7), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0)
	local left = f:CreateTexture(nil, "ARTWORK")
	left:SetColorTexture(1, 1, 1, 1)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
	left:SetGradient("HORIZONTAL", clear, solid)
	local right = f:CreateTexture(nil, "ARTWORK")
	right:SetColorTexture(1, 1, 1, 1)
	right:SetPoint("TOPLEFT", f, "TOP")
	right:SetPoint("BOTTOMRIGHT")
	right:SetGradient("HORIZONTAL", solid, clear)
	return f
end

-- Vertical version for column dividers. The caller sets its TOP and BOTTOM points.
function UI.VLine(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(1)
	local solid, clear = CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.35), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0)
	local upper = f:CreateTexture(nil, "ARTWORK")
	upper:SetColorTexture(1, 1, 1, 1)
	upper:SetPoint("TOPLEFT")
	upper:SetPoint("BOTTOMRIGHT", f, "RIGHT")
	upper:SetGradient("VERTICAL", solid, clear) -- VERTICAL: first color is the bottom
	local lower = f:CreateTexture(nil, "ARTWORK")
	lower:SetColorTexture(1, 1, 1, 1)
	lower:SetPoint("TOPLEFT", f, "LEFT")
	lower:SetPoint("BOTTOMRIGHT")
	lower:SetGradient("VERTICAL", clear, solid)
	return f
end

local function Box(frame, borderAlpha)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(frame, GOLD[1], GOLD[2], GOLD[3], borderAlpha)
end

function UI.Checkbox(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(14, 14)
	b:SetHitRectInsets(-4, -4, -4, -4)
	Box(b, 0.6)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", 3, -3)
	b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
	b.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	function b:SetChecked(on)
		self.checked = on and true or false
		self.fill:SetShown(self.checked)
	end
	b:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if self.onChange then
			self.onChange(self.checked)
		end
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

function UI.Button(parent, width, text)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 20)
	Box(b, 0.45)
	b.label = UI.Text(b, 12, GOLD)
	b.label:SetJustifyH("CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 1)
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.45)
	end)
	b:SetScript("OnMouseDown", function(self)
		self.label:SetPoint("CENTER", 1, -1)
	end)
	b:SetScript("OnMouseUp", function(self)
		self.label:SetPoint("CENTER")
	end)
	return b
end

-- Drag-only slider (no mouse wheel: the options pane scrolls with the wheel).
function UI.Slider(parent, width)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, 14)
	s:SetHitRectInsets(0, 0, -4, -4)
	s:SetObeyStepOnDrag(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(1, 1, 1, 0.18)
	track:SetHeight(1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	thumb:SetSize(6, 12)
	s:SetThumbTexture(thumb)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	fill:SetHeight(1)
	fill:SetPoint("LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")
	s:SetScript("OnValueChanged", function(self, value, userInput)
		if self.valueText then
			self.valueText:SetText((self.format or tostring)(value))
		end
		if userInput and self.onChange then
			self.onChange(value)
		end
	end)
	return s
end

-- Button showing the current choice; the list opens with Blizzard's menu system.
function UI.Dropdown(parent, width)
	local b = UI.Button(parent, width, "")
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -18, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	b.label:SetTextColor(UI.WHITE[1], UI.WHITE[2], UI.WHITE[3])
	b:SetScript("OnMouseDown", nil)
	b:SetScript("OnMouseUp", nil)
	local arrow = UI.Text(b, 11, GOLD)
	arrow:SetPoint("RIGHT", -7, 0)
	arrow:SetText("v")
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
		MenuUtil.CreateContextMenu(self, function(_, root)
			for _, choice in ipairs(self.choices()) do
				root:CreateRadio(choice.text, IsSelected, SetSelected, choice.value)
			end
		end)
	end)
	return b
end

-- Scroll frame with a scroll child (scroll.content, as wide as the frame) and a thin gold thumb right of it.
-- The caller anchors the frame and calls SetContentHeight after laying out the content. Optional
-- scroll.onWidthChanged(width) runs when the width changes (for content that lays out by width).
local SCROLL_STEP = 40

-- Draggable thumb: a 2 px gold bar (4 px while hovered or dragged) in a 10 px wide grab area. The owner positions it
-- with thumb:Place(scroll, thumbH, offset) and scrolls with setScroll(value) while it's dragged.
function UI.ScrollThumb(parent, scroll, setScroll)
	local thumb = CreateFrame("Button", nil, parent)
	thumb:SetWidth(10)
	thumb:SetFrameLevel(scroll:GetFrameLevel() + 5)
	thumb.bar = thumb:CreateTexture(nil, "OVERLAY")
	thumb.bar:SetPoint("TOPLEFT", 4, 0)
	thumb.bar:SetPoint("BOTTOMLEFT", 4, 0)
	thumb:Hide()
	local function Look(active)
		thumb.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], active and 0.9 or 0.45)
		thumb.bar:SetWidth(active and 4 or 2)
	end
	Look(false)
	local function CursorY()
		return select(2, GetCursorPosition()) / thumb:GetEffectiveScale()
	end
	local function Drag(self)
		local viewH, contentH = scroll:GetHeight(), scroll:GetScrollChild():GetHeight()
		local track = viewH - self:GetHeight()
		if track > 0 then
			setScroll(self.startScroll + (self.startY - CursorY()) * (contentH - viewH) / track)
		end
	end
	thumb:SetScript("OnEnter", function()
		Look(true)
	end)
	thumb:SetScript("OnLeave", function(self)
		if not self.dragging then
			Look(false)
		end
	end)
	thumb:SetScript("OnMouseDown", function(self)
		self.dragging = true
		self.startY, self.startScroll = CursorY(), scroll:GetVerticalScroll()
		self:SetScript("OnUpdate", Drag)
	end)
	thumb:SetScript("OnMouseUp", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		Look(self:IsMouseOver())
	end)
	function thumb:Place(owner, height, offset)
		self:SetHeight(height)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, -offset)
		self:Show()
	end
	return thumb
end

function UI.Scroll(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:EnableMouseWheel(true)
	scroll.content = CreateFrame("Frame", nil, scroll)
	scroll.content:SetSize(1, 1)
	scroll:SetScrollChild(scroll.content)
	scroll.thumb = UI.ScrollThumb(parent, scroll, function(value)
		scroll:SetScroll(value)
	end)

	function scroll:UpdateThumb()
		local viewH, contentH = self:GetHeight(), self.content:GetHeight()
		if not self:IsShown() or contentH <= viewH + 1 then
			self.thumb:Hide()
			return
		end
		local thumbH = math.max(viewH * viewH / contentH, 20)
		local offset = self:GetVerticalScroll() / (contentH - viewH) * (viewH - thumbH)
		self.thumb:Place(self, thumbH, offset)
	end

	function scroll:SetScroll(value)
		local maxScroll = math.max(self.content:GetHeight() - self:GetHeight(), 0)
		self:SetVerticalScroll(math.min(math.max(value, 0), maxScroll))
		self:UpdateThumb()
	end

	function scroll:SetContentHeight(height)
		self.content:SetHeight(math.max(height, 1))
		self:SetScroll(self:GetVerticalScroll())
	end

	scroll:SetScript("OnSizeChanged", function(self, width)
		self.content:SetWidth(width)
		if self.onWidthChanged then
			self.onWidthChanged(width)
		end
		self:UpdateThumb()
	end)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetScroll(self:GetVerticalScroll() - delta * SCROLL_STEP)
	end)
	scroll:SetScript("OnShow", scroll.UpdateThumb)
	scroll:SetScript("OnHide", function(self)
		self.thumb:Hide()
	end)
	return scroll
end
