local addonName, ns = ...

-- The kit Home's sections draw with (ns.HomeKit): heading, list row, row pool, and the small helpers the Home files
-- share (SetColor, TipLine, Snap, hairlines, Count for numbers that run to a new value). Loaded before the modules that capture it. The hero is in HomeHero.lua,
-- "Around you" in HomeAround.lua, the view in Home.lua, the rail in Rail.lua.

local UI = ns.UI
-- Font roles (UI.Text's 4th argument, UI.SetFont's 2nd): headings and numbers.
local DISPLAY_FONT, NARROW_FONT = "title", "number"

local PAD = 22
local ROW_H = 24
local ROW2_H = 36 -- a row with a second line
local RIGHT_MIN_LINE = 24 -- narrowest progress line under a row's right-hand text (when it's short or empty)

-- c: a color role, or a color table (sections pass item quality and class colors).
local function SetColor(fs, c)
	local r, g, b = UI.RGBA(c)
	fs:SetTextColor(r, g, b)
end

-- A tooltip line in a role (AddLine's 5th argument is wrap, so not UI.Color's alpha).
local function TipLine(tip, text, role)
	local r, g, b = UI.Color(role)
	tip:AddLine(text, r, g, b)
end

-- Pixel-exact sizes: fractional widths drop 1 px borders.
local function Snap(value)
	return math.floor(value + 0.5)
end

-- Kit for sections --------------------------------------------------------------------------------------------

local Kit = {}
ns.HomeKit = Kit
Kit.DISPLAY_FONT, Kit.NARROW_FONT = DISPLAY_FONT, NARROW_FONT -- font role names
Kit.ROW_H, Kit.ROW2_H = ROW_H, ROW2_H
Kit.PAD, Kit.SetColor, Kit.TipLine, Kit.Snap = PAD, SetColor, TipLine, Snap

-- Section heading: title (title font), meta (muted, after the title) and an optional link on the right.
-- heading:Set(title, meta, linkText, onLink, linkColor) (linkColor: a role, "accent" by default)
function Kit.Heading(parent)
	local h = CreateFrame("Frame", nil, parent)
	h:SetHeight(30)
	h.title = UI.Text(h, 19, "heading", DISPLAY_FONT)
	h.title:SetPoint("BOTTOMLEFT", 0, 4)
	h.meta = UI.Text(h, 12, "textMuted")
	h.meta:SetPoint("BOTTOMLEFT", h.title, "BOTTOMRIGHT", 12, 3)
	h.link = CreateFrame("Button", nil, h)
	h.link:SetPoint("BOTTOMRIGHT", 0, 6)
	h.link:SetHeight(16)
	h.link.text = UI.Text(h.link, 12, "accent")
	h.link.text:SetPoint("RIGHT")
	h.link:SetScript("OnEnter", function(self)
		SetColor(self.text, "text")
	end)
	h.link:SetScript("OnLeave", function(self)
		SetColor(self.text, self.color)
	end)
	h.link:SetScript("OnClick", function(self)
		UI.Sound("nav")
		self.onClick()
	end)
	function h:Set(title, meta, linkText, onLink, linkColor)
		self.title:SetText(title or "")
		self.meta:SetText(meta or "")
		self.link:SetShown(linkText ~= nil)
		if linkText then
			self.link.text:SetText(linkText)
			self.link.color = linkColor or "accent"
			SetColor(self.link.text, self.link.color)
			self.link:SetWidth(self.link.text:GetStringWidth())
			self.link.onClick = onLink
		end
	end
	return h
end

-- List row: icon, text and right-aligned text (number font). row:Set(icon, text, color, right, rightColor, sub)
-- (colors: roles or color tables). With sub the row gets a small muted second line and is Kit.ROW2_H tall (else
-- ROW_H); sub "" is tall, one line.
-- Optional row.onClick / row.onRightClick / row.onEnter(row).
-- With opensMap(row) the row opens the world map first on a left-click when that says so (ns.MapTabs_Opener), and the
-- click runs as its PostClick.
function Kit.Row(parent, opensMap)
	local row = CreateFrame("Button", nil, parent, opensMap and "InsecureActionButtonTemplate" or nil)
	if opensMap then
		ns.MapTabs_Opener(row, function(self, mouseButton)
			return mouseButton == "LeftButton" and opensMap(self)
		end, true)
	end
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bg:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 0, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.right = row:CreateFontString(nil, "OVERLAY")
	UI.SetFont(row.right, NARROW_FONT, 14)
	row.right:SetShadowOffset(1, -1)
	row.right:SetPoint("RIGHT", 0, 0)
	row.right:SetJustifyH("RIGHT")
	row.text = UI.Text(row, 13, "text")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
	row.text:SetWordWrap(false)
	row.sub = UI.Text(row, 11, "textMuted")
	row.sub:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		if self.onClick then
			self.bg:Show()
		end
		if self.onEnter then
			self.onEnter(self)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- OnClick would replace the template's, which opens the map.
	row:SetScript(opensMap and "PostClick" or "OnClick", function(self, button)
		if button == "RightButton" then
			if self.onRightClick then
				self.onRightClick(self)
			end
		elseif self.onClick then
			self.onClick(self)
		end
	end)
	function row:Set(icon, text, color, right, rightColor, sub)
		local two = sub ~= nil and sub ~= ""
		local tall = sub ~= nil -- "" keeps the tall row (it lines up with two-line ones) with the text centered
		local size = tall and 26 or 20
		-- Only touch the height when it changes kind: a caller may have set its own (Weekly's to-do rows).
		if tall then
			self:SetHeight(ROW2_H)
		elseif self.tall then
			self:SetHeight(ROW_H)
		end
		self.tall = tall
		self.icon:SetSize(size, size)
		self.icon:SetShown(icon ~= nil)
		if icon then
			self.icon:SetTexture(icon)
		end
		self.text:ClearAllPoints()
		self.sub:ClearAllPoints()
		local anchor, side, x = self, "LEFT", 0
		if icon then
			anchor, side, x = self.icon, "RIGHT", 8
		end
		if two then
			self.text:SetPoint("BOTTOMLEFT", anchor, side, x, 1)
			self.sub:SetPoint("TOPLEFT", anchor, side, x, -2)
			self.sub:SetPoint("RIGHT", self.right, "LEFT", -10, 0)
		else
			self.text:SetPoint("LEFT", anchor, side, x, 0)
		end
		self.sub:SetText(two and sub or "")
		self.sub:SetShown(two)
		self.text:SetPoint("RIGHT", self.right, "LEFT", -10, 0)
		self.text:SetText(text or "")
		SetColor(self.text, color or "text")
		self.right:SetText(right or "")
		SetColor(self.right, rightColor or "textMuted")
		self.right:SetWidth(math.min(self.right:GetUnboundedStringWidth() + 2, 160))
	end
	return row
end

-- Rows kept per owner: Kit.PoolRow(pool, i, parent) gives the i-th row, creating it the first time, shown and with
-- its click and hover handlers cleared.
function Kit.PoolRow(pool, i, parent, opensMap)
	local row = pool[i]
	if not row then
		row = Kit.Row(parent, opensMap)
		pool[i] = row
	end
	row.onClick, row.onRightClick, row.onEnter = nil, nil, nil
	if row.progress then
		row.progress:Stop()
	end
	row:Show()
	return row
end

-- A progress line (UI.ProgressLine) under the row's right-hand text, as wide as it, while read() says so. Call after
-- row:Set; Kit.PoolRow stops it.
function Kit.RowProgress(row, read)
	if not row.progress then
		row.progress = UI.ProgressLine(row)
		row.progress:SetPoint("TOPRIGHT", row.right, "BOTTOMRIGHT", 0, -2)
	end
	if row.progress:Track(read) then
		row.progress:SetWidth(math.max(row.right:GetStringWidth(), RIGHT_MIN_LINE))
	end
end

-- A number on fs that runs to value (UI.CountTo through format). With deltaAnchor, a change seen while fs shows also
-- floats deltaText(change) beside deltaAnchor, green for a gain and red for a loss; deltaText may return nil for a
-- change too small to mention.
function Kit.Count(fs, value, format, deltaAnchor, deltaText)
	local from = fs.countValue
	local live = fs:IsVisible()
	UI.CountTo(fs, value, format)
	if not (deltaAnchor and live and from and fs.countValue) or from == value then
		return
	end
	local change = value - from
	local text = deltaText(change)
	if text then
		UI.Delta(deltaAnchor, text, change > 0 and "success" or "danger")
	end
end

-- A gold change for Kit.Count's deltaText: whole gold only (ns.Gold drops the silver, so less reads as "+0g").
function Kit.GoldDelta(change)
	if math.abs(change) < 10000 then
		return nil
	end
	return ns.SignedGold(change)
end

function Kit.HideFrom(pool, first)
	for i = first, #pool do
		pool[i]:Hide()
	end
end

-- Hairlines ------------------------------------------------------------------------------------------------

local function HLine(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(UI.RGBA("frame", 0.18))
	t:SetHeight(1)
	return t
end

local function VLine(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(UI.RGBA("frame", 0.18))
	t:SetWidth(1)
	return t
end

Kit.HLine, Kit.VLine = HLine, VLine
