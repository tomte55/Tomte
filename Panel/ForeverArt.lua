local addonName, ns = ...

-- The Forever theme's art: panels, buttons, heading plaques and row stripes from the client's own textures (see
-- Themes/Forever.lua). Forever only (tools/forever_list.lua); shared widgets call in when Theme.panel is "forever".
-- Atlas names and layouts: branch forever of Gethe/wow-ui-source, SharedUIPanelTemplates.xml and Camelot/CharacterFrame.xml.

local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local WINDOW_LAYOUT = "PortraitFrameTemplate" -- the Tomte window: metal, title strip and a round badge
-- Every other window: no title strip, as they lay their own headers out to the top edge. SimplePanelTemplate has none
-- either but is grey on Forever (seen in game), so this is the window frame's bronze bottom, flipped for the top (below).
-- Offsets as ButtonFrameTemplateNoPortrait's with Forever's corrections (Camelot/NineSliceLayoutOverrides.lua).
local PANEL_LAYOUT = {
	disableSharpening = true,
	TopLeftCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft", x = -8, y = 8 },
	TopRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight", x = 2, y = 8 },
	BottomLeftCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft", x = -8, y = -8 },
	BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight", x = 2, y = -8 },
	TopEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom" },
	BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom" },
	LeftEdge = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft" },
	RightEdge = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight" },
}
local FLIPPED_PIECES = { "TopLeftCorner", "TopRightCorner", "TopEdge" }
local WINDOW_BG_TOP = 21 -- px the window's title strip takes before the rock starts (PortraitFrameTexturedBaseTemplate)
local BG_INSET = 2 -- the rock stops under the metal, or it shows past the frame's rounded corners
-- The rock alone is a pale grey beside the game's warm dark windows (seen in game): the theme's bg over it at this alpha.
local ROCK_SHADE = 0.72
-- The frame draws above a window's own children: the metal has to stay on top of anything laid out to the edge.
local EDGE_LEVEL = 12
local MIN_FRAME_W, MIN_FRAME_H = 120, 80 -- smaller than this the metal's corners would meet

local BUTTON_ART = "Interface\\Buttons\\UI-Panel-Button-"
local BUTTON_CAP = 12 -- px of each rounded end
-- Where the art sits in the file (UIPanelButtonUpTexture), and its end caps.
local BUTTON_RIGHT, BUTTON_BOTTOM, BUTTON_CAP_U = 0.625, 0.6875, 0.09375

local PLAQUE_ATLAS = "UI-Character-Info-Title"
local PLAQUE_CAP = 0.14 -- each end's part of the art: it holds the ornament, so it mustn't stretch
local STRIPE_ATLAS = "UI-Character-Info-Line-Bounce"
local STRIPE_ALPHA = 0.8

-- ColoredProgressBarTemplate (Camelot): a 29 px high frame around a 15 px fill, 6 px in from each end.
local BAR_ART_H, BAR_FILL_H, BAR_ART_X = 29, 15, 6
local BAR_MIN_ART_H = 14 -- thinner than this the frame's two edges would touch
local BAR_ATLAS = { success = "common-stat-bar-green", danger = "common-stat-bar-red", info = "common-stat-bar-blue" }
local BAR_DEFAULT = "common-stat-bar-blue" -- what the game's skill bars use
local BAR_TINTED = "common-stat-bar-white" -- any other color role: its color on the white bar

-- ActionButtonTemplate: a 45 px button in a 46 x 45 frame, its cooldown swipe 3 px inside the icon.
local ICON_FRAME_ATLAS, ICON_LIGHT_ATLAS = "UI-HUD-ActionBar-IconFrame", "UI-HUD-ActionBar-IconFrame-Mouseover"
local ICON_FRAME_W, ICON_FRAME_H, ICON_COOLDOWN_INSET = 46, 45, 3
local ICON_MASK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mask"

local SWITCH_SIZE, CHECK_SIZE = 24, 18 -- the game's are 26: a little less fits Tomte's rows
local DISABLED_ALPHA = 0.35

local WELL_ATLAS = "common-insideframe" -- the inner frame of the Character and Professions windows
local WELL_CORNER = 20 -- px of the art's corners and edges drawn unstretched: it holds their ornament
local WELL_SHADE = 0.55 -- how dark a well is over the rock, in frameDark

local CHAT_INPUT = "Interface\\ChatFrame\\UI-ChatInputBorder" -- ChatFrameEditBoxTemplate's slices
local CHAT_INPUT_SIZE = 32

local SEARCH_CAP_W, SEARCH_H = 8, 20 -- InputBoxVisualTemplate's slices
local SEARCH_ICON, SEARCH_ICON_X = 12, 6

local Theme = ns.Theme
local UI = ns.UI
UI.FOREVER_SEARCH_X = 22 -- past the magnifying glass (UI.SearchTextX)

-- Panels ---------------------------------------------------------------------------------------------------------------

-- UI.Panel's look on this theme. opts.portrait: the Tomte window's frame. The handle's SetAlpha does nothing: the game's
-- windows are solid. It sets no frame.themePanel, so UI.Scroll finds no flat color to fade to and keeps a hard edge.
function UI.Forever_Panel(frame, opts)
	local p = { frame = frame }
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetTexture(ROCK, "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	bg:SetPoint("TOPLEFT", BG_INSET, opts.portrait and -WINDOW_BG_TOP or -BG_INSET)
	bg:SetPoint("BOTTOMRIGHT", -BG_INSET, BG_INSET)
	p.bg = bg
	local shade = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	shade:SetAllPoints(bg)
	local r, g, b = Theme.RGB("bg")
	shade:SetColorTexture(r, g, b, ROCK_SHADE)

	local edge = CreateFrame("Frame", nil, frame)
	edge:SetAllPoints()
	edge:SetFrameLevel(frame:GetFrameLevel() + EDGE_LEVEL)
	if opts.portrait then
		NineSliceUtil.ApplyLayoutByName(edge, WINDOW_LAYOUT)
	else
		NineSliceUtil.ApplyLayout(edge, PANEL_LAYOUT)
		-- Coordinates before the atlas, the way NineSlice.lua itself mirrors a piece.
		for _, key in ipairs(FLIPPED_PIECES) do
			local piece = edge[key]
			local atlas = piece:GetAtlas()
			piece:SetTexCoord(0, 1, 1, 0)
			piece:SetAtlas(atlas, true)
		end
	end
	p.edge = edge
	UI.Border(frame, "frame", 0) -- invisible, so UI.SetBorderColor still works on the frame

	function p:SetAlpha()
	end

	function p:Layout()
		local w, h = frame:GetSize()
		edge:SetShown(opts.portrait or (w >= MIN_FRAME_W and h >= MIN_FRAME_H))
	end

	frame:HookScript("OnSizeChanged", function()
		p:Layout()
	end)
	p:Layout()
	return p
end

-- Toasts: the game's tooltip frame and fill, so they look like its own messages over the world without a window's
-- weight. The pieces are on `frame` itself, under its own text, as UI.Panel's BlizzardPanel. The fill is that theme's
-- bgTop, the game's tooltip color; this theme's own is brown.
function UI.Forever_TooltipPanel(frame)
	local p = { frame = frame }
	NineSliceUtil.ApplyLayoutByName(frame, "TooltipDefaultLayout")
	local fill = Theme.Get("blizzard").colors.bgTop
	frame.Center:SetVertexColor(fill[1], fill[2], fill[3], 1)
	UI.Border(frame, "frame", 0) -- invisible, so UI.SetBorderColor still works on the frame

	function p:SetAlpha()
	end

	function p:Layout()
	end

	return p
end

-- The theme preview's mock window (Panel/Window.lua).
function UI.Forever_MockPanel(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints()
	holder:SetFrameLevel(parent:GetFrameLevel())
	UI.Forever_Panel(holder, {})
	return holder
end

-- The window's round badge, in the frame's portrait hole (PortraitFrameBaseTemplate's anchors). Above the metal.
function UI.Forever_Badge(window, texture)
	local holder = CreateFrame("Frame", nil, window)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT")
	holder:SetFrameLevel(window:GetFrameLevel() + EDGE_LEVEL + 2)
	local badge = holder:CreateTexture(nil, "OVERLAY")
	badge:SetSize(62, 62)
	badge:SetPoint("TOPLEFT", -5, 7)
	badge:SetTexture(texture)
	UI.CircleMask(badge, holder)
	return holder
end

-- Buttons ---------------------------------------------------------------------------------------------------------------

-- The game's red close button on any Button: normal, pressed, disabled and highlight. Above the metal, as it sits in a
-- corner of the frame.
function UI.Forever_CloseArt(b)
	b:SetNormalAtlas("RedButton-Exit")
	b:SetPushedAtlas("RedButton-exit-pressed")
	b:SetDisabledAtlas("RedButton-Exit-Disabled")
	b:SetHighlightAtlas("RedButton-Highlight", "ADD")
	b:SetFrameLevel(b:GetFrameLevel() + EDGE_LEVEL + 2)
end

local function SetSlices(b, state)
	local file = BUTTON_ART .. state
	b.sliceL:SetTexture(file)
	b.sliceM:SetTexture(file)
	b.sliceR:SetTexture(file)
end

-- The game's red panel button under b: three slices, so any width works. b.artState(b, "Down" | "Up") shows pressed or
-- not (UI.Button's own mouse scripts call it; SetScript would drop a hook here). b.artPlain(b) makes it a dark field.
function UI.Forever_ButtonArt(b)
	b.sliceL = b:CreateTexture(nil, "BACKGROUND")
	b.sliceR = b:CreateTexture(nil, "BACKGROUND")
	b.sliceM = b:CreateTexture(nil, "BACKGROUND")
	b.sliceL:SetPoint("TOPLEFT")
	b.sliceL:SetPoint("BOTTOMLEFT")
	b.sliceR:SetPoint("TOPRIGHT")
	b.sliceR:SetPoint("BOTTOMRIGHT")
	b.sliceM:SetPoint("TOPLEFT", b.sliceL, "TOPRIGHT")
	b.sliceM:SetPoint("BOTTOMRIGHT", b.sliceR, "BOTTOMLEFT")
	b.sliceL:SetTexCoord(0, BUTTON_CAP_U, 0, BUTTON_BOTTOM)
	b.sliceM:SetTexCoord(BUTTON_CAP_U, BUTTON_RIGHT - BUTTON_CAP_U, 0, BUTTON_BOTTOM)
	b.sliceR:SetTexCoord(BUTTON_RIGHT - BUTTON_CAP_U, BUTTON_RIGHT, 0, BUTTON_BOTTOM)
	SetSlices(b, b:IsEnabled() and "Up" or "Disabled")

	local function Caps(self, width)
		local cap = math.min(BUTTON_CAP, width / 2)
		self.sliceL:SetWidth(cap)
		self.sliceR:SetWidth(cap)
	end
	Caps(b, b:GetWidth())
	b:HookScript("OnSizeChanged", Caps)
	b:HookScript("OnEnable", function(self)
		SetSlices(self, "Up")
	end)
	b:HookScript("OnDisable", function(self)
		SetSlices(self, "Disabled")
	end)

	b:SetHighlightTexture(BUTTON_ART .. "Highlight", "ADD")
	local glow = b:GetHighlightTexture()
	glow:SetTexCoord(0, BUTTON_RIGHT, 0, BUTTON_BOTTOM)
	glow:SetAllPoints()

	function b.artState(self, state)
		if self:IsEnabled() then
			SetSlices(self, state)
		end
	end

	function b.artPlain(self)
		self.sliceL:Hide()
		self.sliceM:Hide()
		self.sliceR:Hide()
		self:GetHighlightTexture():SetAlpha(0)
		local fill = self:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(Theme.Color("surface"))
		for _, t in ipairs(self.borderEdges) do
			t:Show()
		end
		self.hoverWash:Show()
	end
end

-- Headings --------------------------------------------------------------------------------------------------------------

-- The stat list's heading plaque on `parent`, from left to right inside it and top to bottom from its top edge. Its ends
-- keep their shape at any width. Returns a table of the three textures for Forever_PlaqueShow, nil if the art is missing.
function UI.Forever_Plaque(parent, left, right, top, height)
	local info = C_Texture.GetAtlasInfo(PLAQUE_ATLAS)
	if not info then
		return nil
	end
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local capU = (r - l) * PLAQUE_CAP
	local capW = height * (info.width * PLAQUE_CAP) / info.height
	local function Slice(u1, u2)
		local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
		tex:SetTexture(info.file or info.filename)
		tex:SetTexCoord(u1, u2, t, b)
		tex:SetHeight(height)
		return tex
	end
	local leftEnd, middle, rightEnd = Slice(l, l + capU), Slice(l + capU, r - capU), Slice(r - capU, r)
	leftEnd:SetPoint("TOPLEFT", left, top)
	leftEnd:SetWidth(capW)
	rightEnd:SetPoint("TOPRIGHT", -right, top)
	rightEnd:SetWidth(capW)
	middle:SetPoint("TOPLEFT", leftEnd, "TOPRIGHT")
	middle:SetPoint("TOPRIGHT", rightEnd, "TOPLEFT")
	return { leftEnd, middle, rightEnd }
end

function UI.Forever_PlaqueShow(plaque, shown)
	if plaque then
		for _, tex in ipairs(plaque) do
			tex:SetShown(shown)
		end
	end
end

-- A section heading (Kit.Heading) on the plaque: white and smaller, as the stat list's, with its parts moved inside the
-- plaque's ends.
function UI.Forever_Heading(h)
	UI.Forever_Plaque(h, 0, 0, 0, h:GetHeight())
	h.title:ClearAllPoints()
	h.title:SetPoint("LEFT", 16, 1)
	UI.SetFont(h.title, "title", 14)
	UI.SetTextRole(h.title, "text")
	h.meta:ClearAllPoints()
	h.meta:SetPoint("LEFT", h.title, "RIGHT", 10, 0)
	h.link:ClearAllPoints()
	h.link:SetPoint("RIGHT", -16, 1)
end

-- Bars ------------------------------------------------------------------------------------------------------------------

-- UI.Bar in the game's progress bar. The bar's own rect stays the caller's, so layouts don't change: the frame hangs
-- outside it, and a thin bar's fill grows into the frame's track.
-- How far the frame of a bar this high hangs outside it, up and down, then to the sides, then the frame's height.
function UI.Forever_BarOverhang(h)
	local artH = math.max(h * BAR_ART_H / BAR_FILL_H, BAR_MIN_ART_H)
	return (artH - h) / 2, artH * BAR_ART_X / BAR_ART_H, artH
end

-- A StatusBar (a unit's health, which can be secret, so it can't be a UI.Bar) in the same art. Its fill is the white
-- bar: the owner tints it with SetStatusBarColor. height: the bar's, as its anchors may not be resolved yet.
function UI.Forever_StatusBarArt(bar, height)
	local overY, overX = UI.Forever_BarOverhang(height)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPLEFT", -overX, overY)
	track:SetPoint("BOTTOMRIGHT", overX, -overY)
	track:SetAtlas("common-stat-bar-BG")
	bar:SetStatusBarTexture(BAR_TINTED)
	local mask = bar:CreateMaskTexture()
	mask:SetAtlas("common-stat-bar-Mask")
	mask:SetAllPoints(track)
	bar:GetStatusBarTexture():AddMaskTexture(mask)
end

-- The warning version of a bar's frame: the frame's art in a color, added over the bar (`parent` draws above it).
function UI.Forever_BarGlow(parent, bar, height, r, g, b)
	local overY, overX = UI.Forever_BarOverhang(height)
	local glow = parent:CreateTexture(nil, "OVERLAY")
	glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -overX, overY)
	glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", overX, -overY)
	glow:SetAtlas("common-stat-bar-BG")
	glow:SetVertexColor(r, g, b)
	glow:SetBlendMode("ADD")
	return glow
end

function UI.Forever_BarArt(bar)
	local h = bar:GetHeight()
	local overY, overX, artH = UI.Forever_BarOverhang(h)
	local fillOver = (artH * BAR_FILL_H / BAR_ART_H - h) / 2

	bar.shade:Hide()
	bar.track:ClearAllPoints()
	bar.track:SetPoint("TOPLEFT", -overX, overY)
	bar.track:SetPoint("BOTTOMRIGHT", overX, -overY)
	bar.track:SetAtlas("common-stat-bar-BG")

	bar.fill:ClearAllPoints()
	bar.fill:SetPoint("TOPLEFT", 0, fillOver)
	bar.fill:SetPoint("BOTTOMLEFT", 0, -fillOver)
	local mask = bar:CreateMaskTexture()
	mask:SetAtlas("common-stat-bar-Mask")
	mask:SetAllPoints(bar.track)
	bar.fill:AddMaskTexture(mask)

	-- ColoredProgressBarMixin:SetFillPercent's coordinates: the fill is cut, not squeezed.
	local function Cut(self)
		self.fill:SetTexCoord(0, self.value or 0, 1, 0)
	end

	local function Paint(texture, role)
		local atlas = role and (BAR_ATLAS[role] or BAR_TINTED) or BAR_DEFAULT
		texture:SetAtlas(atlas)
		if atlas == BAR_TINTED then
			texture:SetVertexColor(Theme.RGB(role))
		else
			texture:SetVertexColor(1, 1, 1)
		end
	end

	function bar:SetColorRole(role)
		Paint(self.fill, role)
		Cut(self)
	end

	-- A second fill laid over the bar by its owner (Leveling's finished quests), in the same art as the main fill. The
	-- owner places it, then cuts it with SetPartRange(part, from, to) (shares of the bar's width).
	function bar:SetPartRole(part, role)
		Paint(part, role)
		if not part.masked then
			part:AddMaskTexture(mask)
			part.masked = true
		end
	end

	function bar:SetPartRange(part, from, to)
		part:SetTexCoord(from, to, 1, 0)
	end

	local setValue = bar.SetValue
	function bar:SetValue(value)
		setValue(self, value)
		Cut(self)
	end
end

-- Action icons ----------------------------------------------------------------------------------------------------------

-- A spell icon on `parent` (`size` px square) in the game's action button frame (ActionButtonTemplate): the icon is cut
-- to the frame's shape, and the frame goes on top.
function UI.Forever_IconFrame(parent, icon, size)
	icon:SetTexCoord(0, 1, 0, 1)
	local mask = parent:CreateMaskTexture()
	mask:SetAtlas(ICON_MASK_ATLAS)
	-- The art has a margin around its opening: fitted to the icon it cuts the icon too small (seen in game). The template
	-- leaves it at its own size on a 45 px button, so it's that, scaled to this button.
	local info = C_Texture.GetAtlasInfo(ICON_MASK_ATLAS)
	if info then
		mask:SetSize(info.width * size / ICON_FRAME_H, info.height * size / ICON_FRAME_H)
		mask:SetPoint("CENTER", icon)
	else
		mask:SetAllPoints(icon)
	end
	icon:AddMaskTexture(mask)
	local frame = parent:CreateTexture(nil, "OVERLAY")
	frame:SetAtlas(ICON_FRAME_ATLAS)
	frame:SetPoint("TOPLEFT")
	frame:SetSize(size * ICON_FRAME_W / ICON_FRAME_H, size)
	return frame
end

-- The action button's light (a hovered button's, or here a marked one's), `size` as the frame. Hidden until shown.
function UI.Forever_IconLight(parent, size)
	local light = parent:CreateTexture(nil, "OVERLAY", nil, 1)
	light:SetAtlas(ICON_LIGHT_ATLAS)
	light:SetPoint("TOPLEFT")
	light:SetSize(size * ICON_FRAME_W / ICON_FRAME_H, size)
	light:SetBlendMode("ADD")
	light:Hide()
	return light
end

-- How far a button's cooldown swipe stays inside an icon this size, so it stops at the frame's inner edge.
function UI.Forever_IconInset(size)
	return math.floor(size * ICON_COOLDOWN_INSET / ICON_FRAME_H + 0.5)
end

-- Toggles ---------------------------------------------------------------------------------------------------------------

-- The game's checkbox, with the API of UI.Switch and UI.Checkbox (SetChecked, .checked, .onChange, disabling dims it).
local function Check(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b:SetHitRectInsets(-2, -2, -2, -2)
	local box = b:CreateTexture(nil, "ARTWORK")
	box:SetAtlas("checkbox-minimal")
	box:SetAllPoints()
	b.mark = b:CreateTexture(nil, "OVERLAY")
	b.mark:SetAtlas("checkmark-minimal")
	b.mark:SetAllPoints()
	-- A texture rather than the HIGHLIGHT layer: a settings row lights its checkbox too, through these scripts.
	b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.glow:SetAtlas("checkbox-minimal")
	b.glow:SetAllPoints()
	b.glow:SetBlendMode("ADD")
	b.glow:Hide()
	UI.Border(b, "frame", 0) -- invisible, so callers' UI.SetBorderColor and UI.BorderTo still work

	function b:SetChecked(on)
		self.checked = on and true or false
		self.mark:SetShown(self.checked)
	end

	b:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if self.checked then
			UI.Pop(self.mark, 0.25)
		end
		UI.Sound(self.checked and "on" or "off")
		if self.onChange then
			self.onChange(self.checked)
		end
	end)
	b:SetScript("OnEnter", function(self)
		self.glow:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.glow:Hide()
	end)
	b:SetScript("OnEnable", function(self)
		self:SetAlpha(1)
	end)
	b:SetScript("OnDisable", function(self)
		self:SetAlpha(DISABLED_ALPHA)
	end)
	b:SetChecked(false)
	return b
end

function UI.Forever_Switch(parent)
	return Check(parent, SWITCH_SIZE)
end

function UI.Forever_Checkbox(parent)
	return Check(parent, CHECK_SIZE)
end

-- Wells ------------------------------------------------------------------------------------------------------------------

-- A sunken panel inside a window, as the game's windows have: a darker fill in the inner frame's art, its corners and
-- edges cut out of the atlas so it fits any size. The caller anchors the frame it returns; it sits under parent's other
-- children and takes no mouse.
function UI.Forever_Well(parent)
	local well = CreateFrame("Frame", nil, parent)
	well:SetFrameLevel(parent:GetFrameLevel())
	local fill = well:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	local r, g, b = Theme.RGB("frameDark")
	fill:SetColorTexture(r, g, b, WELL_SHADE)
	local info = C_Texture.GetAtlasInfo(WELL_ATLAS)
	if not info then
		return well
	end
	local l, t = info.leftTexCoord, info.topTexCoord
	local ri, bo = info.rightTexCoord, info.bottomTexCoord
	local cu, cv = (ri - l) * WELL_CORNER / info.width, (bo - t) * WELL_CORNER / info.height
	local function Piece(u1, u2, v1, v2)
		local tex = well:CreateTexture(nil, "BORDER")
		tex:SetTexture(info.file or info.filename)
		tex:SetTexCoord(u1, u2, v1, v2)
		return tex
	end
	local function Corner(point, u1, u2, v1, v2)
		local tex = Piece(u1, u2, v1, v2)
		tex:SetSize(WELL_CORNER, WELL_CORNER)
		tex:SetPoint(point)
		return tex
	end
	local tl = Corner("TOPLEFT", l, l + cu, t, t + cv)
	local tr = Corner("TOPRIGHT", ri - cu, ri, t, t + cv)
	local bl = Corner("BOTTOMLEFT", l, l + cu, bo - cv, bo)
	local br = Corner("BOTTOMRIGHT", ri - cu, ri, bo - cv, bo)
	-- Stretches between two corners: its top left at one's point, its bottom right at the other's.
	local function Edge(from, fromPoint, to, toPoint, u1, u2, v1, v2)
		local tex = Piece(u1, u2, v1, v2)
		tex:SetPoint("TOPLEFT", from, fromPoint)
		tex:SetPoint("BOTTOMRIGHT", to, toPoint)
	end
	Edge(tl, "TOPRIGHT", tr, "BOTTOMLEFT", l + cu, ri - cu, t, t + cv)
	Edge(bl, "TOPRIGHT", br, "BOTTOMLEFT", l + cu, ri - cu, bo - cv, bo)
	Edge(tl, "BOTTOMLEFT", bl, "TOPRIGHT", l, l + cu, t + cv, bo - cv)
	Edge(tr, "BOTTOMLEFT", br, "TOPRIGHT", ri - cu, ri, t + cv, bo - cv)
	return well
end

-- Chat input ---------------------------------------------------------------------------------------------------------------

-- The game's chat line under an edit box, with its brighter look while typing: box.artFocus(box, focused). box.artField
-- tells UI.Border and UI.Surface to draw nothing of their own.
function UI.Forever_ChatInput(box)
	box.artField = true
	local function Slices(suffixL, suffixM, suffixR, layer)
		local left = box:CreateTexture(nil, layer)
		left:SetTexture(CHAT_INPUT .. suffixL)
		left:SetSize(CHAT_INPUT_SIZE, CHAT_INPUT_SIZE)
		left:SetPoint("LEFT")
		local right = box:CreateTexture(nil, layer)
		right:SetTexture(CHAT_INPUT .. suffixR)
		right:SetSize(CHAT_INPUT_SIZE, CHAT_INPUT_SIZE)
		right:SetPoint("RIGHT")
		local mid = box:CreateTexture(nil, layer)
		mid:SetTexture(CHAT_INPUT .. suffixM, "REPEAT")
		mid:SetHorizTile(true)
		mid:SetHeight(CHAT_INPUT_SIZE)
		mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
		mid:SetPoint("TOPRIGHT", right, "TOPLEFT")
		return { left, mid, right }
	end
	Slices("-Left2", "-Mid2", "-Right2", "BACKGROUND")
	local focus = Slices("Focus-Left", "Focus-Mid", "Focus-Right", "BORDER")
	function box.artFocus(_, focused)
		for _, tex in ipairs(focus) do
			tex:SetShown(focused)
		end
	end
	box.artFocus(box, false)
end

-- Search boxes ----------------------------------------------------------------------------------------------------------

-- The game's search field under a search box (InputBoxVisualTemplate, SearchBoxTemplate): three slices and a magnifying
-- glass. box.artField tells UI.Border and UI.Surface, which the box's creator calls next, to draw nothing of their own.
function UI.Forever_SearchArt(box)
	box.artField = true
	local left = box:CreateTexture(nil, "BACKGROUND")
	left:SetAtlas("common-search-border-left")
	left:SetSize(SEARCH_CAP_W, SEARCH_H)
	left:SetPoint("LEFT")
	local right = box:CreateTexture(nil, "BACKGROUND")
	right:SetAtlas("common-search-border-right")
	right:SetSize(SEARCH_CAP_W, SEARCH_H)
	right:SetPoint("RIGHT")
	local middle = box:CreateTexture(nil, "BACKGROUND")
	middle:SetAtlas("common-search-border-middle")
	middle:SetHeight(SEARCH_H)
	middle:SetPoint("LEFT", left, "RIGHT")
	middle:SetPoint("RIGHT", right, "LEFT")
	local glass = box:CreateTexture(nil, "OVERLAY")
	glass:SetAtlas("common-search-magnifyingglass")
	glass:SetSize(SEARCH_ICON, SEARCH_ICON)
	glass:SetPoint("LEFT", SEARCH_ICON_X, -1)
end

-- Rows ------------------------------------------------------------------------------------------------------------------

-- The stat list's alternating stripe behind a list row.
function UI.Forever_Stripe(row, on)
	if not row.stripe then
		row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
		row.stripe:SetAtlas(STRIPE_ATLAS)
		row.stripe:SetAllPoints()
		row.stripe:SetAlpha(STRIPE_ALPHA)
	end
	row.stripe:SetShown(on)
end
