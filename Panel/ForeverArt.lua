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

local SWITCH_SIZE, CHECK_SIZE = 24, 18 -- the game's are 26: a little less fits Tomte's rows
local DISABLED_ALPHA = 0.35

local Theme = ns.Theme
local UI = ns.UI

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
function UI.Forever_BarArt(bar)
	local h = bar:GetHeight()
	local artH = math.max(h * BAR_ART_H / BAR_FILL_H, BAR_MIN_ART_H)
	local overY = (artH - h) / 2
	local overX = artH * BAR_ART_X / BAR_ART_H
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
