local addonName, ns = ...

-- Widgets and panel art for the theme (Core/Theme.lua), drawn from color textures, a few small tiles in
-- Media/Theme and font strings. Everything asks the theme for colors and fonts by role.

local Theme = ns.Theme
local UI = {}
ns.UI = UI

UI.Color = Theme.Color
UI.RGB = Theme.RGB
UI.Hex = Theme.Hex
UI.Wrap = Theme.Wrap
UI.Font = Theme.Font
UI.SetFont = Theme.SetFont
-- The top-left quarter of this texture is a gear (used the same way by Leatrix Maps).
UI.GEAR = "Interface\\WorldMap\\Gear_64.png"

-- A role name or (during the migration) a color table → r, g, b, a.
local function RGBA(color, alpha)
	if type(color) == "string" then
		local r, g, b, a = Theme.Color(color)
		return r, g, b, alpha or a
	end
	return color[1], color[2], color[3], alpha or color[4] or 1
end
UI.RGBA = RGBA

local function ColorObject(role, alpha)
	local r, g, b, a = RGBA(role, alpha)
	return CreateColor(r, g, b, a)
end
UI.ColorObject = ColorObject

-- color: a role ("text" by default); fontRole: "body" (default), "title", "number" or "chat".
function UI.Text(parent, size, color, fontRole)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Theme.SetFont(fs, fontRole or "body", size)
	fs:SetTextColor(RGBA(color or "text"))
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.8)
	fs:SetJustifyH("LEFT")
	return fs
end

function UI.SetTextRole(fs, role, alpha)
	fs:SetTextColor(RGBA(role, alpha))
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

-- Four edges `pixels` screen pixels thick (default 1), `inset` units inside the frame. Returns
-- { top, bottom, left, right }.
local function Edges(frame, inset, layer, sublevel, r, g, b, a, pixels)
	pixels = pixels or 1
	local edges = {}
	local sides = {
		{ "TOPLEFT", inset, -inset, "TOPRIGHT", -inset, -inset },
		{ "BOTTOMLEFT", inset, inset, "BOTTOMRIGHT", -inset, inset },
		{ "TOPLEFT", inset, -inset, "BOTTOMLEFT", inset, inset },
		{ "TOPRIGHT", -inset, -inset, "BOTTOMRIGHT", -inset, inset },
	}
	for i, p in ipairs(sides) do
		local t = frame:CreateTexture(nil, layer or "BORDER", nil, sublevel or 0)
		t:SetColorTexture(r, g, b, a)
		t:SetPoint(p[1], p[2], p[3])
		t:SetPoint(p[4], p[5], p[6])
		-- Exactly one screen pixel: below a UI scale of 1 a 1-unit edge can round to nothing (clipped-looking buttons),
		-- and pixel-grid snapping rounds an edge's two sides on their own, so boxes off the pixel grid got edges of 0, 1
		-- or 2 pixels (measured 2026-10-08 on the vault slots). Unsnapped, a solid 1-pixel quad always fills one row.
		t:SetTexelSnappingBias(0)
		t:SetSnapToPixelGrid(false)
		if i <= 2 then
			PixelUtil.SetHeight(t, pixels, pixels)
		else
			PixelUtil.SetWidth(t, pixels, pixels)
		end
		edges[i] = t
	end
	return edges
end

-- 1px border inside the frame's edges: UI.Border(frame, role, alpha) (role defaults to "frame"); the old
-- UI.Border(frame, r, g, b, a) form still works.
function UI.Border(frame, r, g, b, a)
	if type(r) ~= "number" then
		r, g, b, a = RGBA(r or "frame", g)
	end
	frame.borderEdges = Edges(frame, 0, "BORDER", 0, r, g, b, a or 1)
end

-- UI.SetBorderColor(frame, role, alpha) or (frame, r, g, b, a).
function UI.SetBorderColor(frame, r, g, b, a)
	if type(r) ~= "number" then
		r, g, b, a = RGBA(r or "frame", g)
	end
	for _, t in ipairs(frame.borderEdges) do
		t:SetColorTexture(r, g, b, a or 1)
	end
end

-- Line that fades out at both ends. Returns a frame `width` wide. role defaults to "frame".
function UI.Hairline(parent, width, alpha, role)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, 1)
	local solid, clear = ColorObject(role or "frame", alpha or 0.7), ColorObject(role or "frame", 0)
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
function UI.VLine(parent, alpha)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(1)
	local solid, clear = ColorObject("frame", alpha or 0.4), ColorObject("frame", 0)
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

-- Panel art ---------------------------------------------------------------------------------------------------

local CONTOUR_SIZE = 512
local CONTOUR_ALPHA = 0.06
local GRAIN_ALPHA = 0.06
local GLOW_ALPHA = 0.05
local VIGNETTE = 26
local LARGE_W, LARGE_H = 600, 400 -- contours from this size up
local SMALL_H = 60 -- below this: no inner rule, no vignette

-- Texcoords that show the `w` x `h` part of the contour file nearest its origin corner (bottom-right in the file),
-- mirrored to `corner`. Cropped, not scaled, so the rings keep their size on every panel.
local function ContourCoords(corner, w, h)
	local fw, fh = math.min(w / CONTOUR_SIZE, 1), math.min(h / CONTOUR_SIZE, 1)
	local l, r, t, b = 1 - fw, 1, 1 - fh, 1
	if corner == "BOTTOMLEFT" or corner == "TOPLEFT" then
		l, r = r, l
	end
	if corner == "TOPRIGHT" or corner == "TOPLEFT" then
		t, b = b, t
	end
	return l, r, t, b
end

-- The theme's panel look on `frame`: gradient fill, soft light top-left, grain, contour rings in one corner (large
-- panels), an inner vignette, a 2 px dark outer edge and a thin rule inset 5 px.
-- opts.size: "large" | "medium" | "small", or nil to pick from the frame's size whenever it changes.
-- opts.corner: where the contours sit (default "BOTTOMRIGHT"). opts.alpha: fill opacity (default 1).
-- opts.subtle: for widgets and toasts over the game world (Almost Done, Crafting list, flight bar, toasts): only the
-- fill and a faint rule on the edge; no grain, glow, contours, vignette or dark outer edge.
-- Returns a handle: handle:SetAlpha(a) changes the fill's opacity (the Tomte window's Background opacity).
function UI.Panel(frame, opts)
	opts = opts or {}
	local p = { frame = frame, corner = opts.corner or "BOTTOMRIGHT" }

	p.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	p.fill:SetAllPoints()
	p.fill:SetColorTexture(1, 1, 1, 1)

	p.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	p.glow:SetTexture(Theme.media.glow)
	p.glow:SetPoint("TOPLEFT")
	p.glow:SetTexCoord(0.5, 1, 0.5, 1) -- the quarter of the spot whose center is the panel's top-left corner
	p.glow:SetAlpha(GLOW_ALPHA)

	p.contours = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	p.contours:SetTexture(Theme.media.contours)
	p.contours:SetVertexColor(Theme.Color("contour"))
	p.contours:SetAlpha(CONTOUR_ALPHA)
	p.contours:SetPoint(p.corner)

	p.grain = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
	p.grain:SetAllPoints()
	p.grain:SetTexture(Theme.media.grain, "REPEAT", "REPEAT")
	p.grain:SetHorizTile(true)
	p.grain:SetVertTile(true)
	p.grain:SetAlpha(GRAIN_ALPHA)

	p.vignette = {}
	local dark, clear = CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0)
	for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
		t:SetColorTexture(1, 1, 1, 1)
		if i <= 2 then
			t:SetPoint(side .. "LEFT")
			t:SetPoint(side .. "RIGHT")
			t:SetHeight(VIGNETTE)
			t:SetGradient("VERTICAL", side == "TOP" and clear or dark, side == "TOP" and dark or clear)
		else
			t:SetPoint("TOP" .. side)
			t:SetPoint("BOTTOM" .. side)
			t:SetWidth(VIGNETTE)
			t:SetGradient("HORIZONTAL", side == "LEFT" and dark or clear, side == "LEFT" and clear or dark)
		end
		p.vignette[i] = t
	end

	local r, g, b = Theme.Color("frameDark")
	p.outer = Edges(frame, 0, "BORDER", 1, r, g, b, 1, 2)
	local fr, fg, fb = Theme.Color("frame")
	p.inner = Edges(frame, opts.subtle and 0 or 5, "BORDER", 2, fr, fg, fb, opts.subtle and 0.22 or 0.45)
	frame.borderEdges = p.inner -- so UI.SetBorderColor recolors the visible rule

	-- The opacity setting fades every layer, so a see-through panel doesn't keep opaque edges and grain.
	function p:SetAlpha(alpha)
		self.alpha = alpha
		local top, bottom = ColorObject("bgTop", alpha), ColorObject("bgBottom", alpha)
		self.fill:SetGradient("VERTICAL", bottom, top)
		self.glow:SetAlpha(GLOW_ALPHA * alpha)
		self.contours:SetAlpha(CONTOUR_ALPHA * alpha)
		self.grain:SetAlpha(GRAIN_ALPHA * alpha)
		for _, t in ipairs(self.vignette) do
			t:SetAlpha(alpha)
		end
		for _, t in ipairs(self.outer) do
			t:SetAlpha(alpha)
		end
	end

	function p:Layout()
		local w, h = frame:GetSize()
		if not (w and w > 1) then
			return
		end
		local size = opts.size or (w >= LARGE_W and h >= LARGE_H and "large") or (h < SMALL_H and "small") or "medium"
		local large, small = size == "large", size == "small"
		if opts.subtle then
			self.contours:Hide()
			self.glow:Hide()
			self.grain:Hide()
			for _, t in ipairs(self.vignette) do
				t:Hide()
			end
			for _, t in ipairs(self.outer) do
				t:Hide()
			end
			return
		end
		self.contours:SetShown(large)
		if large then
			local cw, ch = math.min(w, CONTOUR_SIZE), math.min(h, CONTOUR_SIZE)
			self.contours:SetSize(cw, ch)
			self.contours:SetTexCoord(ContourCoords(self.corner, cw, ch))
		end
		self.glow:SetSize(math.min(w * 0.7, 700), math.min(h * 0.8, 500))
		self.glow:SetShown(not small)
		local depth = math.min(VIGNETTE, math.floor(math.min(w, h) * 0.2))
		for i, t in ipairs(self.vignette) do
			t:SetShown(not small)
			if i <= 2 then
				t:SetHeight(depth)
			else
				t:SetWidth(depth)
			end
		end
		for _, t in ipairs(self.inner) do
			t:SetShown(not small)
		end
	end

	p:SetAlpha(opts.alpha or 1)
	frame:HookScript("OnSizeChanged", function()
		p:Layout()
	end)
	p:Layout()
	frame.themePanel = p
	return p
end

-- Inset box (vault slots, cards, input fields): a darker fill with a faint rule. Returns the fill texture.
function UI.Surface(frame, borderAlpha)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(Theme.Color("surface"))
	UI.Border(frame, "frame", borderAlpha or 0.35)
	return bg
end

-- Centered title in the title font with the ink flourish under it. Returns the font string (fs.flourish is the
-- flourish texture; hide it where there's no room).
function UI.Title(parent, text, size)
	local fs = UI.Text(parent, size or 18, "heading", "title")
	fs:SetJustifyH("CENTER")
	fs:SetText(text or "")
	local f = parent:CreateTexture(nil, "ARTWORK")
	f:SetTexture(Theme.media.flourish)
	f:SetSize(160, 10)
	f:SetPoint("TOP", fs, "BOTTOM", 0, -2)
	f:SetVertexColor(Theme.Color("frame"))
	f:SetAlpha(0.8)
	fs.flourish = f
	return fs
end

-- Progress bar: a sunken track and a fill that runs from accentDeep to accent (or a status role).
-- bar:SetValue(0..1), bar:SetColorRole(role) (nil = the accent gradient).
function UI.Bar(parent, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height or 5)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints()
	bar.track:SetColorTexture(0, 0, 0, 0.4)
	bar.shade = bar:CreateTexture(nil, "BORDER")
	bar.shade:SetPoint("TOPLEFT")
	bar.shade:SetPoint("TOPRIGHT")
	bar.shade:SetHeight(1)
	bar.shade:SetColorTexture(0, 0, 0, 0.6)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetPoint("TOPLEFT")
	bar.fill:SetPoint("BOTTOMLEFT")
	bar.fill:SetColorTexture(1, 1, 1, 1)
	bar.value = 0
	function bar:SetColorRole(role)
		if role then
			self.fill:SetGradient("HORIZONTAL", ColorObject(role, 0.75), ColorObject(role))
		else
			self.fill:SetGradient("HORIZONTAL", ColorObject("accentDeep"), ColorObject("accent"))
		end
	end
	function bar:SetValue(value)
		self.value = math.min(math.max(value or 0, 0), 1)
		local w = self:GetWidth()
		self.fill:SetWidth(math.max(w * self.value, 0.001))
		self.fill:SetShown(self.value > 0)
	end
	bar:SetScript("OnSizeChanged", function(self)
		self:SetValue(self.value)
	end)
	bar:SetColorRole(nil)
	bar:SetValue(0)
	return bar
end

-- Controls ----------------------------------------------------------------------------------------------------

function UI.Checkbox(parent)
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
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if self.onChange then
			self.onChange(self.checked)
		end
	end)
	b:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, "accent", 1)
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", 0.7)
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
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(Theme.Color("surface"))
	UI.Border(b, "frame", BUTTON_RULE)
	local single = text ~= nil and #text == 1
	b.label = single and UI.Text(b, 13, "heading") or UI.Text(b, 11, "heading", "title")
	b.label:SetJustifyH("CENTER")
	b.label:SetPoint("CENTER", 0, single and 0 or LABEL_Y)
	b.label:SetText(text)
	b.labelY = single and 0 or LABEL_Y
	b:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, "accent", 1)
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", BUTTON_RULE)
	end)
	b:SetScript("OnMouseDown", function(self)
		self.label:SetPoint("CENTER", 1, self.labelY - 1)
	end)
	b:SetScript("OnMouseUp", function(self)
		self.label:SetPoint("CENTER", 0, self.labelY)
	end)
	return b
end

-- On-screen widgets (Almost Done, Crafting list): a minus/plus in the top-right corner that shows while the mouse is
-- over the widget and folds it down to its title. isCollapsed() reads the saved state, onToggle() flips it and
-- redraws. The widget's own OnEnter can't tell (its rows take the mouse), so the button polls IsMouseOver.
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
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		self:Update()
		if self:IsMouseOver() then
			self:GetScript("OnEnter")(self)
		end
	end)
	b:Hide()
	frame:HookScript("OnUpdate", function()
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
function UI.Slider(parent, width)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, 14)
	s:SetHitRectInsets(0, 0, -4, -4)
	s:SetObeyStepOnDrag(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(Theme.Color("frame"))
	track:SetAlpha(0.45)
	track:SetHeight(1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(Theme.Color("accent"))
	thumb:SetSize(6, 12)
	s:SetThumbTexture(thumb)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(Theme.Color("accent"))
	fill:SetAlpha(0.8)
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

-- Scroll frame with a scroll child (scroll.content, as wide as the frame) and a thin accent thumb right of it.
-- The caller anchors the frame and calls SetContentHeight after laying out the content. Optional
-- scroll.onWidthChanged(width) runs when the width changes (for content that lays out by width).
local SCROLL_STEP = 40

-- Draggable thumb: a 2 px bar (4 px while hovered or dragged) in a 10 px wide grab area. The owner positions it
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
		local r, g, b = Theme.Color("accent")
		thumb.bar:SetColorTexture(r, g, b, active and 0.9 or 0.4)
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
