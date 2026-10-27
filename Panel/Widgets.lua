local addonName, ns = ...

-- Widgets and panel art for the theme (Core/Theme.lua), drawn from color textures, a few small tiles in
-- Media/Theme and font strings. Everything asks the theme for colors and fonts by role.

local COLLAPSE_POLL = 0.1 -- seconds between hover checks for the collapse button

local Theme = ns.Theme
local UI = {}
ns.UI = UI

UI.Color = Theme.Color
UI.RGB = Theme.RGB
UI.Hex = Theme.Hex
UI.Wrap = Theme.Wrap
UI.SetFont = Theme.SetFont
-- The top-left quarter of this texture is a gear (used the same way by Leatrix Maps).
UI.GEAR = "Interface\\WorldMap\\Gear_64.png"

-- A role name, or a color table { r, g, b[, a] } for colors with game meaning (item quality, class) -> r, g, b, a.
-- alpha overrides the color's own.
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

-- color: a role ("text" by default); fontRole: "body" (default), "title", "label", "number" or "chat".
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

-- Every search box: a right-click empties it and puts the cursor in it, ready for a new search. SetText fires the
-- box's own OnTextChanged, so its list follows as if the text had been deleted by hand.
function UI.SearchBoxClear(box)
	box:HookScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			self:SetText("")
			self:SetFocus()
		end
	end)
end

-- Puts a link into the open chat edit box (shift-click). Does nothing for a nil link.
function UI.InsertLink(link)
	if link then
		ChatFrameUtil.InsertLink(link)
	end
end

-- A GameTooltip line in a theme color role ("text" by default). AddLine's 5th argument is wrap, so not UI.Color's alpha.
function UI.TipLine(text, role, wrap)
	local r, g, b = UI.Color(role or "text")
	GameTooltip:AddLine(text, r, g, b, wrap)
end

-- name in its class color (class: the English class file name, e.g. "PALADIN"); name unchanged for a nil or unknown
-- class.
function UI.ClassColored(name, class)
	local color = class and C_ClassColor.GetClassColor(class)
	return color and color:WrapTextInColorCode(name) or name
end

-- A hidden, movable, themed dialog window named `name`, centered (opts.y above the middle, default 0). height may be
-- nil when the caller sizes it later. opts.parent defaults to UIParent; opts.escape (default true) lets Escape close
-- it (UI.CloseOnEscape; callers HookScript OnShow/OnHide, SetScript would drop it). Callers that can show it while
-- UIParent is hidden call UI.PlaceDialog on every show.
function UI.Dialog(name, width, height, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", name, opts.parent or UIParent)
	if height then
		frame:SetSize(width, height)
	else
		frame:SetWidth(width)
	end
	frame:SetPoint("CENTER", 0, opts.y or 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	UI.Panel(frame)
	if opts.escape ~= false then
		UI.CloseOnEscape(frame) -- Controls.lua: only this dialog closes, not the Tomte window under it
	end
	return frame
end

-- Puts a UI.Dialog on UIParent, like every other window (WorldFrame's children draw under all of UIParent whatever
-- their strata, so there it would sit behind the Tomte window). Only while a dialogue addon hides UIParent does it go
-- on WorldFrame, scaled to UIParent's size (the trick Cinematic/Engine.lua uses for its hint). DialogueUI hides it
-- by fading it to alpha 0 while it stays shown, so a faded UIParent counts as hidden. SetParent can carry the
-- parent's strata over, so it's set again. On WorldFrame it goes above a cinematic's letterbox (FULLSCREEN: the
-- Cashier asks from the flight cinematic's games drawer) and is marked ours, so the cinematic doesn't fade it out.
function UI.PlaceDialog(frame)
	if UIParent:IsShown() and UIParent:GetAlpha() >= 0.99 then
		frame:SetParent(UIParent)
		frame:SetScale(1)
		frame:SetFrameStrata("DIALOG")
	elseif HouseEditorFrame and HouseEditorFrame:IsVisible() then
		-- Blizzard's house editor hides UIParent; on WorldFrame the dialog would draw under the editor's frames
		-- (the Decorating panel's Export, Import and questions).
		frame:SetParent(HouseEditorFrame)
		frame:SetScale(UIParent:GetEffectiveScale() / HouseEditorFrame:GetEffectiveScale())
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
	else
		frame:SetParent(WorldFrame)
		frame:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
		ns.ownFrames[frame] = true
	end
end

-- Clips texture to a circle: a mask created on parent (the frame that owns texture), covering texture. Returns it.
function UI.CircleMask(texture, parent)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return mask
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

-- 1px border inside the frame's edges in a color role (default "frame"). UI.SetBorderColor recolors it.
function UI.Border(frame, role, alpha)
	local r, g, b, a = RGBA(role or "frame", alpha)
	frame.borderEdges = Edges(frame, 0, "BORDER", 0, r, g, b, a or 1)
	frame.borderColor = { r, g, b, a or 1 } -- where UI.BorderTo (Motion.lua) eases from
end

function UI.SetBorderColor(frame, role, alpha)
	local r, g, b, a = RGBA(role or "frame", alpha)
	if UI.TweenStop then
		UI.TweenStop(frame, "border")
	end
	for _, t in ipairs(frame.borderEdges) do
		t:SetColorTexture(r, g, b, a or 1)
	end
	frame.borderColor = { r, g, b, a or 1 }
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

-- Layer alphas, the rule's inset and so on come from the theme (Theme.art; defaults in Core/Theme.lua).
local VIGNETTE = 26
local LARGE_W, LARGE_H = 600, 400 -- contours from this size up
local SMALL_H = 60 -- below this: no inner rule, no vignette

-- Texcoords that show the `w` x `h` part of the contour file nearest its origin corner (bottom-right in the file),
-- mirrored to `corner`. Cropped, not scaled, so the rings keep their size on every panel.
local function ContourCoords(corner, w, h)
	local size = Theme.art.contourSize
	local fw, fh = math.min(w / size, 1), math.min(h / size, 1)
	local l, r, t, b = 1 - fw, 1, 1 - fh, 1
	if corner == "BOTTOMLEFT" or corner == "TOPLEFT" then
		l, r = r, l
	end
	if corner == "TOPRIGHT" or corner == "TOPLEFT" then
		t, b = b, t
	end
	return l, r, t, b
end

-- The Blizzard theme's panel: the tooltip's nine-slice border (NineSliceUtil, Blizzard_SharedXML NineSlice.lua;
-- layout in Mainline/NineSliceLayouts.lua). The pieces are textures on `frame` itself (frame.TopLeftCorner ...
-- frame.Center), so they stay under the frame's own text. The fill is bgTop, as GameTooltip tints it with
-- TOOLTIP_DEFAULT_BACKGROUND_COLOR. frame.borderEdges are invisible 1 px edges, so UI.SetBorderColor still works.
-- size "large" (the Tomte window) gets a darker layer under the fill: a tooltip-thin fill over a whole window let
-- nameplates and the world show through the text.
local NINE_SLICE_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge" }
local LARGE_BACKING_ALPHA = 0.55

local function BlizzardPanel(frame, size)
	local p = { frame = frame }
	NineSliceUtil.ApplyLayoutByName(frame, "TooltipDefaultLayout")
	local fr, fg, fb = Theme.Color("bgTop")
	frame.Center:SetVertexColor(fr, fg, fb, 1)
	if size == "large" then
		p.backing = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		p.backing:SetAllPoints(frame.Center)
		local br, bg, bb = Theme.Color("bgBottom")
		p.backing:SetColorTexture(br, bg, bb, LARGE_BACKING_ALPHA)
	end
	for _, key in ipairs(NINE_SLICE_PIECES) do
		frame[key]:SetVertexColor(1, 1, 1, 1) -- TOOLTIP_DEFAULT_COLOR: the border art as it comes
	end
	local r, g, b = Theme.Color("frame")
	p.inner = Edges(frame, 0, "BORDER", 2, r, g, b, 0)
	frame.borderEdges = p.inner

	-- Always exactly a tooltip's look: the Background opacity setting is Cartographer's only (Panel/Window.lua).
	function p:SetAlpha(a)
		self.alpha = a
	end

	function p:Layout()
	end

	p:SetAlpha(1)
	frame.themePanel = p
	return p
end

-- The theme's panel look on `frame`: gradient fill, soft light top-left, grain, corner art (large panels), an inner
-- vignette, a dark outer edge and a thin rule inset from the edge. Theme.art sets each layer's strength (0 = off).
-- opts.size: "large" | "medium" | "small", or nil to pick from the frame's size whenever it changes.
-- opts.corner: where the contours sit (default "BOTTOMRIGHT"). opts.alpha: fill opacity (default 1).
-- opts.subtle: for widgets and toasts over the game world (Almost Done, Crafting list, flight bar, toasts): only the
-- fill and a faint rule on the edge; no grain, glow, contours, vignette or dark outer edge.
-- Returns a handle: handle:SetAlpha(a) changes the fill's opacity (the Tomte window's Background opacity).
-- A theme whose panel is "blizzard" draws the game's tooltip border and fill instead (BlizzardPanel).
function UI.Panel(frame, opts)
	opts = opts or {}
	if Theme.panel == "blizzard" and not opts.subtle then
		return BlizzardPanel(frame, opts.size)
	end
	local art = Theme.art
	local GLOW_ALPHA, CONTOUR_ALPHA, GRAIN_ALPHA = art.glow, art.contours, art.grain
	local p = { frame = frame, corner = opts.corner or "BOTTOMRIGHT" }

	p.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	p.fill:SetAllPoints()
	p.fill:SetColorTexture(1, 1, 1, 1)

	p.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	p.glow:SetTexture(Theme.media.glow)
	p.glow:SetPoint("TOPLEFT")
	p.glow:SetTexCoord(0.5, 1, 0.5, 1) -- the quarter of the spot whose center is the panel's top-left corner
	p.glow:SetAlpha(GLOW_ALPHA)
	if art.glowTint then
		p.glow:SetVertexColor(Theme.RGB(art.glowTint))
	end

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
	local dark, clear = CreateColor(0, 0, 0, art.vignette), CreateColor(0, 0, 0, 0)
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
	p.outer = Edges(frame, 0, "BORDER", 1, r, g, b, 1, math.max(art.outer, 1))
	local fr, fg, fb = Theme.Color("frame")
	p.inner = Edges(frame, opts.subtle and 0 or art.inset, "BORDER", 2, fr, fg, fb,
		opts.subtle and art.subtleRule or art.rule)
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
		self.contours:SetShown(large and CONTOUR_ALPHA > 0)
		self.grain:SetShown(GRAIN_ALPHA > 0)
		for _, t in ipairs(self.outer) do
			t:SetShown(art.outer > 0)
		end
		if large then
			local cw, ch = math.min(w, art.contourSize), math.min(h, art.contourSize)
			self.contours:SetSize(cw, ch)
			self.contours:SetTexCoord(ContourCoords(self.corner, cw, ch))
		end
		self.glow:SetSize(math.min(w * 0.7, 700), math.min(h * 0.8, 500))
		self.glow:SetShown(not small and GLOW_ALPHA > 0)
		local depth = math.min(VIGNETTE, math.floor(math.min(w, h) * 0.2))
		for i, t in ipairs(self.vignette) do
			t:SetShown(not small and art.vignette > 0)
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
	frame.surfaceFill = bg -- a scroll inside matches its edge fades to it (UI.Scroll)
	return bg
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
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(Theme.Color("surface"))
	UI.HoverWash(b)
	UI.Border(b, "frame", BUTTON_RULE)
	local single = text ~= nil and #text == 1
	b.label = single and UI.Text(b, 13, "heading") or UI.Text(b, 11, "heading", "label")
	b.label:SetJustifyH("CENTER")
	b.label:SetPoint("CENTER", 0, single and 0 or LABEL_Y)
	b.label:SetText(text)
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
	end)
	b:SetScript("OnMouseUp", function(self)
		self.label:SetPoint("CENTER", 0, self.labelY)
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

-- Scroll frame with a scroll child (scroll.content, as wide as the frame) and a thin accent thumb right of it.
-- The caller anchors the frame and calls SetContentHeight after laying out the content. Optional
-- scroll.onWidthChanged(width) runs when the width changes (for content that lays out by width).
local SCROLL_STEP = 40
local SCROLL_SECONDS = 0.18 -- the wheel's ease to the next step
local EDGE_FADE = 18 -- height of the fades at a scroll's top and bottom edges
local EDGE_LEVEL = 30 -- the fades' frame sits this many levels above the scroll, over its rows' own frames

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
	local function Look(active, now)
		local r, g, b = Theme.Color("accent")
		thumb.bar:SetColorTexture(r, g, b, active and 0.9 or 0.4)
		local from, to = thumb.bar:GetWidth(), active and 4 or 2
		if now then
			UI.TweenStop(thumb.bar, "width")
			thumb.bar:SetWidth(to)
			return
		end
		UI.Tween(thumb.bar, "width", 0.12, function(t)
			thumb.bar:SetWidth(UI.Lerp(from, to, t))
		end)
	end
	Look(false, true)
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
	thumb:SetScript("OnHide", function(self)
		-- Hidden mid-drag (the page changed, the window closed): OnMouseUp never comes.
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		Look(false, true)
	end)
	function thumb:Place(owner, height, offset)
		self:SetHeight(height)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, -offset)
		self:Show()
	end
	return thumb
end

-- Edge fades --------------------------------------------------------------------------------------------------

-- The color behind a scroll at height y (screen units): the panel under it (UI.Panel's fill gradient, or the tooltip
-- fill of the Blizzard theme) seen through every UI.Surface box between them. nil when no panel is found.
local function BackdropColor(scroll, y)
	local surfaces = {}
	local frame = scroll:GetParent()
	while frame do
		local p = frame.themePanel
		if p then
			local r, g, b
			if p.fill then
				local top, bottom = frame:GetTop(), frame:GetBottom()
				local t = (top and bottom and top > bottom) and math.min(math.max((y - bottom) / (top - bottom), 0), 1)
					or 0.5
				local tr, tg, tb = Theme.Color("bgTop")
				local br, bg, bb = Theme.Color("bgBottom")
				r, g, b = br + (tr - br) * t, bg + (tg - bg) * t, bb + (tb - bb) * t
				-- Near the panel's top or bottom edge its vignette darkens the fill.
				local shade = p.vignette and p.vignette[1]
				local depth = shade and shade:IsShown() and shade:GetHeight() or 0
				local d = (top and bottom) and math.min(y - bottom, top - y) or depth
				if depth > 0 and d < depth then
					local k = Theme.art.vignette * (1 - math.max(d, 0) / depth) * (p.alpha or 1)
					r, g, b = r * (1 - k), g * (1 - k), b * (1 - k)
				end
			else
				r, g, b = Theme.Color("bgTop")
			end
			-- The boxes in between, outermost first: each lays its own color over what's under it.
			for i = #surfaces, 1, -1 do
				local sr, sg, sb, sa = RGBA("surface")
				sa = sa or 1
				r, g, b = r + (sr - r) * sa, g + (sg - g) * sa, b + (sb - b) * sa
			end
			return r, g, b, p.alpha or 1
		end
		if frame.surfaceFill then
			surfaces[#surfaces + 1] = frame
		end
		frame = frame:GetParent()
	end
	return nil
end

-- Soft fades at a scroll's top and bottom edges, in the color behind it, while there's more beyond that edge: a
-- ScrollFrame can't fade its own content (no alpha masks), so they're overlays above it that take no mouse. Each fade
-- is a frame holding its gradient (edges.top.tex): it's faded in and out by the frame's alpha, as a texture's own
-- alpha didn't hide a gradient (both fades always showed, measured in game).
local function EdgeFade(edges)
	local fade = CreateFrame("Frame", nil, edges)
	fade:SetHeight(EDGE_FADE)
	fade.tex = fade:CreateTexture(nil, "OVERLAY")
	fade.tex:SetAllPoints()
	fade.tex:SetColorTexture(1, 1, 1, 1)
	fade:SetAlpha(0)
	return fade
end

local function EdgeFades(scroll)
	local edges = CreateFrame("Frame", nil, scroll)
	edges:SetAllPoints()
	edges:SetFrameLevel(scroll:GetFrameLevel() + EDGE_LEVEL)
	-- Each one screen pixel past the scroll's edge: the first and last pixel row of content showed beyond the fades
	-- (seen in game).
	edges.top = EdgeFade(edges)
	PixelUtil.SetPoint(edges.top, "TOPLEFT", edges, "TOPLEFT", 0, 1)
	PixelUtil.SetPoint(edges.top, "TOPRIGHT", edges, "TOPRIGHT", 0, 1)
	edges.bottom = EdgeFade(edges)
	PixelUtil.SetPoint(edges.bottom, "BOTTOMLEFT", edges, "BOTTOMLEFT", 0, -1)
	PixelUtil.SetPoint(edges.bottom, "BOTTOMRIGHT", edges, "BOTTOMRIGHT", 0, -1)
	return edges
end

-- Recolors the fades for where the scroll sits now (its place in the panel's gradient). False when there's no plain
-- panel behind it to match.
local function PaintEdges(scroll)
	local top, bottom = scroll:GetTop(), scroll:GetBottom()
	if not (top and bottom) then
		return false
	end
	-- Painted for this place and theme already (UpdateEdges runs every frame of a wheel scroll).
	if scroll.edgeTop == top and scroll.edgeBottom == bottom and scroll.edgeTheme == Theme.name then
		return scroll.edgePainted
	end
	scroll.edgeTop, scroll.edgeBottom, scroll.edgeTheme = top, bottom, Theme.name
	local tr, tg, tb, ta = BackdropColor(scroll, top)
	local br, bg, bb, ba = BackdropColor(scroll, bottom)
	scroll.edgePainted = tr ~= nil
	if tr then
		local edges = scroll.edges
		edges.top.tex:SetGradient("VERTICAL", CreateColor(tr, tg, tb, 0), CreateColor(tr, tg, tb, ta))
		edges.bottom.tex:SetGradient("VERTICAL", CreateColor(br, bg, bb, ba), CreateColor(br, bg, bb, 0))
	end
	return scroll.edgePainted
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
	scroll.edges = EdgeFades(scroll)

	-- scroll.noEdgeFade = true turns the fades off (a scroll over a picture or a busy background).
	function scroll:UpdateEdges()
		local viewH, contentH = self:GetHeight(), self.content:GetHeight()
		local offset = self:GetVerticalScroll()
		local fades = not self.noEdgeFade and self:IsVisible() and contentH > viewH + 1 and PaintEdges(self)
		local wantTop = fades and offset > 1 or false
		local wantBottom = fades and offset < contentH - viewH - 1 or false
		local edges = self.edges
		if wantTop ~= edges.topOn then
			edges.topOn = wantTop
			UI.WashTo(edges.top, wantTop, not fades)
		end
		if wantBottom ~= edges.bottomOn then
			edges.bottomOn = wantBottom
			UI.WashTo(edges.bottom, wantBottom, not fades)
		end
	end

	function scroll:UpdateThumb()
		self:UpdateEdges()
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
		UI.TweenStop(self, "wheel")
		self.wheelTarget = nil
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
	-- The wheel eases to where it's going; a turn while it eases goes on from the target, so fast turns add up.
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(self.content:GetHeight() - self:GetHeight(), 0)
		local from = self:GetVerticalScroll()
		local to = math.min(math.max((self.wheelTarget or from) - delta * SCROLL_STEP, 0), maxScroll)
		self.wheelTarget = to
		UI.Tween(self, "wheel", SCROLL_SECONDS, function(t)
			self:SetVerticalScroll(UI.Lerp(from, to, t))
			self:UpdateThumb()
		end, function()
			self.wheelTarget = nil
		end)
	end)
	scroll:SetScript("OnShow", scroll.UpdateThumb)
	scroll:SetScript("OnHide", function(self)
		self.thumb:Hide()
	end)
	return scroll
end
