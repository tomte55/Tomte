local addonName, ns = ...

-- Widgets and panel art for the theme (Core/Theme.lua), drawn from color textures, a few small tiles in
-- Media/Theme and font strings. Everything asks the theme for colors and fonts by role. Checkboxes, buttons,
-- sliders and dropdowns are in Inputs.lua, UI.Scroll in Scroll.lua, more controls in Controls.lua.

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
	if Theme.panel == "forever" then
		UI.Forever_SearchArt(box)
	end
end

-- Where a search box's text and placeholder start, past the magnifying glass on the Forever theme's field.
function UI.SearchTextX()
	return Theme.panel == "forever" and UI.FOREVER_SEARCH_X or 8
end

-- Puts a link into the open chat edit box (shift-click). Does nothing for a nil link.
function UI.InsertLink(link)
	if link then
		ns.Chat_InsertLink(link)
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
	UI.Panel(frame, opts.look) -- opts.look: UI.Panel's options (the Tomte map's portrait frame)
	if opts.escape ~= false then
		UI.CloseOnEscape(frame) -- Escape.lua: only this dialog closes, not the Tomte window under it
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
	if frame.artField then -- the game's own field (UI.Forever_SearchArt) has its border in its art
		for _, t in ipairs(frame.borderEdges) do
			t:Hide()
		end
	end
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
-- opts.toast: a toast card; the Forever theme gives it the game's tooltip frame (Panel/ForeverArt.lua).
-- Returns a handle: handle:SetAlpha(a) changes the fill's opacity (the Tomte window's Background opacity).
-- A theme whose panel is "blizzard" draws the game's tooltip border and fill instead (BlizzardPanel).
function UI.Panel(frame, opts)
	opts = opts or {}
	if Theme.panel == "forever" and opts.toast then
		return UI.Forever_TooltipPanel(frame)
	end
	if Theme.panel == "blizzard" and not opts.subtle then
		return BlizzardPanel(frame, opts.size)
	end
	if Theme.panel == "forever" and not opts.subtle and opts.size ~= "small" then
		return UI.Forever_Panel(frame, opts)
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
	bg:SetShown(not frame.artField) -- square, under the game's rounded field (UI.Forever_SearchArt)
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
	if Theme.panel == "forever" then
		UI.Forever_BarArt(bar) -- replaces SetColorRole and wraps SetValue
	end
	bar:SetColorRole(nil)
	bar:SetValue(0)
	return bar
end

-- Action icons ------------------------------------------------------------------------------------------------

-- The look of a spell or item icon you press, on b (a Button, or a settings preview's plain frame): a crop and a hover
-- light, or on the Forever theme the game's action button (UI.Forever_IconFrame). borderAlpha: a frame-colored border at
-- this alpha, nil for none (the Forever theme's frame stands in for it). size: b's, which may not be resolved yet.
function UI.ActionIcon(b, icon, size, borderAlpha)
	if Theme.panel == "forever" then
		UI.Forever_IconFrame(b, icon, size)
		if b.SetHighlightAtlas then
			UI.Forever_IconHighlight(b)
		end
		if borderAlpha then
			UI.Border(b, "frame", 0) -- invisible, so callers' UI.SetBorderColor still works
		end
		return
	end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if b.SetHighlightTexture then
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	if borderAlpha then
		UI.Border(b, "frame", borderAlpha)
	end
end

-- How far a cooldown swipe stays inside an action icon this size.
function UI.ActionIconInset(size)
	return Theme.panel == "forever" and UI.Forever_IconInset(size) or 0
end

-- A texture that marks an action icon as needing attention, colored with SetVertexColor: a colored edge around it, or on
-- the Forever theme the action button's light.
function UI.ActionIconMark(b, size)
	if Theme.panel == "forever" then
		local light = UI.Forever_IconLight(b, size)
		light:Show()
		return light
	end
	local mark = b:CreateTexture(nil, "BACKGROUND")
	mark:SetPoint("TOPLEFT", -2, 2)
	mark:SetPoint("BOTTOMRIGHT", 2, -2)
	mark:SetColorTexture(1, 1, 1)
	return mark
end
