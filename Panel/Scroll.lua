local addonName, ns = ...

-- Widgets: UI.Scroll, a scroll frame with a thin accent thumb (UI.ScrollThumb) and fades at its top and bottom
-- edges. The rest of the widget kit is in Widgets.lua, Inputs.lua and Controls.lua.

local Theme = ns.Theme
local UI = ns.UI
local RGBA = UI.RGBA

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
	local DragTimed = ns.Perf_Wrap(Drag, "OnUpdate")
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
		self:SetScript("OnUpdate", DragTimed)
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
