local addonName, ns = ...

-- Bags: the frame kit every Bags window is built from, so they read as one case: a header or footer band, a recessed
-- tray for items or lists, joined button clusters, a search box sunk into the band, a fill meter, and tabs attached
-- to a window's edge. Colors by theme role; darkening and light edges in black and white shading, so every theme
-- gets them without new art (docs/superpowers/specs/2026-10-27-tomte-bags-ui-design.md).

local BAND_SHADE = 0.25 -- black over the window: a band reads a step darker
local TRAY_SHADE = 0.35 -- black over the window inside a tray
local TRAY_EDGE = 0.9 -- a tray's dark outline
local SHADOW_H = 4 -- the inner shadow along a tray's or a search box's top edge
local SHADOW = 0.6
local LIGHT_EDGE = 0.04 -- the faint light line under a tray (its lower lip catching light)
local BUTTON_H = 22
local ICON = 14
local ICON_BUTTON_W = 24
local TEXT_PAD = 16 -- a text button's width beyond its label
local SEARCH_SHADE = 0.45
local LIT = 0.18 -- the accent wash on a lit cluster button

local UI = ns.UI

local function Fill(frame, layer, sub, alpha)
	local t = frame:CreateTexture(nil, layer, nil, sub)
	t:SetAllPoints()
	t:SetColorTexture(0, 0, 0, alpha)
	return t
end

-- A dark gradient along the inside of frame's top edge.
local function TopShadow(frame)
	local t = frame:CreateTexture(nil, "BORDER", nil, 1)
	t:SetPoint("TOPLEFT", 1, -1)
	t:SetPoint("TOPRIGHT", -1, -1)
	t:SetHeight(SHADOW_H)
	t:SetColorTexture(1, 1, 1, 1)
	t:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, SHADOW))
	return t
end

local function Line(frame, role, alpha, layer)
	local t = frame:CreateTexture(nil, layer or "BORDER", nil, 2)
	t:SetColorTexture(UI.RGBA(role, alpha))
	t:SetTexelSnappingBias(0)
	t:SetSnapToPixelGrid(false)
	PixelUtil.SetHeight(t, 1, 1)
	return t
end

-- Band -------------------------------------------------------------------------------------------------------------

-- A band across a window (header or footer): a step darker, a rule on its bottom edge (band:SetRuleTop(true) for a
-- footer). The caller anchors it and sets its height.
function ns.BagsKit_Band(parent)
	local band = CreateFrame("Frame", nil, parent)
	Fill(band, "BACKGROUND", 2, BAND_SHADE)
	band.rule = Line(band, "rule", nil, "ARTWORK")
	function band:SetRuleTop(top)
		self.rule:ClearAllPoints()
		self.rule:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT")
		self.rule:SetPoint(top and "TOPRIGHT" or "BOTTOMRIGHT")
	end
	band:SetRuleTop(false)
	return band
end

-- Tray -------------------------------------------------------------------------------------------------------------

-- A recessed tray: darker inside, a dark outline, an inner shadow along the top, a faint light lip under it.
function ns.BagsKit_Tray(parent)
	local tray = CreateFrame("Frame", nil, parent)
	Fill(tray, "BACKGROUND", 2, TRAY_SHADE)
	UI.Border(tray, { 0, 0, 0 }, TRAY_EDGE)
	TopShadow(tray)
	local lip = Line(tray, { 1, 1, 1 }, LIGHT_EDGE, "BORDER")
	lip:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, 0)
	lip:SetPoint("TOPRIGHT", tray, "BOTTOMRIGHT", 0, 0)
	return tray
end

-- Cluster ----------------------------------------------------------------------------------------------------------

local function ClusterButton(cluster, spec)
	local b = CreateFrame("Button", nil, cluster)
	b:SetHeight(BUTTON_H)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	UI.HoverWash(b)
	b.lit = Fill(b, "BACKGROUND", 3, 0)
	if spec.icon then
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(ICON, ICON)
		b.icon:SetPoint("CENTER")
		if type(spec.icon) == "string" and not spec.icon:find("\\") then
			b.icon:SetAtlas(spec.icon)
		else
			b.icon:SetTexture(spec.icon)
		end
		b:SetWidth(ICON_BUTTON_W)
	else
		b.label = UI.Text(b, 11, "heading", "label")
		b.label:SetPoint("CENTER", 0, -1)
		b.label:SetText(spec.text)
		b:SetWidth(math.ceil(b.label:GetStringWidth()) + TEXT_PAD)
	end
	b:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
		if spec.tip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(spec.tip)
			if spec.tipLine then
				UI.TipLine(spec.tipLine, "textMuted", true)
			end
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", spec.onClick)
	return b
end

-- Buttons joined in one frame, divided by rules. specs: { { icon | text, tip, tipLine, onClick } }. The cluster sizes
-- itself; cluster.buttons[i]; cluster:SetLit(i, on) lights one (a switch's chosen part); cluster:Layout() after
-- showing or hiding buttons or changing a label.
function ns.BagsKit_Cluster(parent, specs)
	local cluster = CreateFrame("Frame", nil, parent)
	cluster:SetHeight(BUTTON_H + 2)
	Fill(cluster, "BACKGROUND", 1, 0.15)
	UI.Border(cluster, "frame")
	cluster.buttons, cluster.dividers = {}, {}
	for i, spec in ipairs(specs) do
		cluster.buttons[i] = ClusterButton(cluster, spec)
	end
	function cluster:Layout()
		local x = 1
		local shown = 0
		for _, d in ipairs(self.dividers) do
			d:Hide()
		end
		for _, b in ipairs(self.buttons) do
			if b:IsShown() then
				if b.label then
					b:SetWidth(math.ceil(b.label:GetStringWidth()) + TEXT_PAD)
				end
				if shown > 0 then
					local d = self.dividers[shown]
					if not d then
						d = self:CreateTexture(nil, "ARTWORK")
						d:SetColorTexture(UI.Color("rule"))
						PixelUtil.SetWidth(d, 1, 1)
						self.dividers[shown] = d
					end
					d:ClearAllPoints()
					d:SetPoint("TOPLEFT", self, "TOPLEFT", x, -1)
					d:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 1)
					d:Show()
					x = x + 1
				end
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -1)
				x = x + b:GetWidth()
				shown = shown + 1
			end
		end
		self:SetWidth(x + 1)
	end
	function cluster:SetLit(i, on)
		local b = self.buttons[i]
		b.lit:SetColorTexture(UI.RGBA("accent", on and LIT or 0))
		if b.label then
			UI.SetTextRole(b.label, on and "text" or "textMuted")
		end
	end
	cluster:Layout()
	return cluster
end

-- Search -----------------------------------------------------------------------------------------------------------

-- A search box sunk into a band: darker, an inner shadow, the placeholder, a "?" inside at its right end
-- (search.help, its tooltip is the caller's). search:SetError(text) frames it in the danger color with the reason in
-- its tooltip (nil clears). onChange runs once typing pauses; right-click empties it.
function ns.BagsKit_Search(parent, placeholder, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(BUTTON_H)
	box:SetAutoFocus(false)
	UI.SearchBoxClear(box)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 22, 0, 0)
	Fill(box, "BACKGROUND", 2, SEARCH_SHADE)
	UI.Border(box, "rule")
	TopShadow(box)
	box.placeholder = UI.Text(box, 12, "textFaint")
	box.placeholder:SetPoint("LEFT", 8, 0)
	box.placeholder:SetText(placeholder)
	box.help = CreateFrame("Button", nil, box)
	box.help:SetSize(18, BUTTON_H)
	box.help:SetPoint("RIGHT", -2, 0)
	box.help.text = UI.Text(box.help, 12, "textMuted")
	box.help.text:SetPoint("CENTER")
	box.help.text:SetText("?")
	box.help:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	local refresh = UI.Debounce(UI.SEARCH_DELAY, onChange)
	box:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
		refresh()
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEnter", function(self)
		if self.error then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText("This search doesn't work yet")
			UI.TipLine(self.error, "danger", true)
			GameTooltip:Show()
		end
	end)
	box:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	function box:SetError(text)
		self.error = text
		UI.SetBorderColor(self, text and "danger" or "rule")
	end
	return box
end

-- Meter ------------------------------------------------------------------------------------------------------------

-- A thin fill meter: meter:SetValue(0..1).
function ns.BagsKit_Meter(parent, width)
	local meter = CreateFrame("Frame", nil, parent)
	meter:SetSize(width, 5)
	Fill(meter, "BACKGROUND", 1, 0.5)
	UI.Border(meter, "rule")
	meter.bar = meter:CreateTexture(nil, "ARTWORK")
	meter.bar:SetPoint("TOPLEFT", 1, -1)
	meter.bar:SetPoint("BOTTOMLEFT", 1, 1)
	meter.bar:SetColorTexture(UI.Color("accentDeep"))
	function meter:SetValue(v)
		v = math.max(0, math.min(1, v or 0))
		self.bar:SetWidth(math.max((self:GetWidth() - 2) * v, 0.01))
		self.bar:SetShown(v > 0)
	end
	return meter
end

-- Tab --------------------------------------------------------------------------------------------------------------

local EDGE_INDEX = { top = 2, right = 3 } -- UI.Border's edges: top, bottom, left, right; the side open to the window

-- A tab attached to a window edge: side "top" (it stands on the window's top edge) or "right" (it hangs off the right
-- edge). Its open side has no line, so it joins the window. tab.icon; tab:SetSelected(on) frames it in the accent.
function ns.BagsKit_Tab(parent, size, side)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(size, size)
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local fill = tab:CreateTexture(nil, "BACKGROUND", nil, 0) -- under the hover wash (sublevel 1)
	fill:SetAllPoints()
	fill:SetColorTexture(UI.Color("bg"))
	Fill(tab, "BACKGROUND", 2, BAND_SHADE)
	UI.HoverWash(tab)
	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetPoint("TOPLEFT", 4, -4)
	tab.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	UI.Border(tab, "frame")
	local open = tab.borderEdges[EDGE_INDEX[side] or 2]
	open:SetAlpha(0)
	function tab:SetSelected(on)
		UI.SetBorderColor(self, on and "accent" or "frame")
	end
	return tab
end
