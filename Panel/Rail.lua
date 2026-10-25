local addonName, ns = ...

-- The rail beside every panel view but Settings: Home, the pages and the world map tabs, each with an optional count
-- pill. Exports ns.PanelRail_Create. The Home view is Home.lua; the kit is HomeKit.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local SetColor, TipLine, Snap = Kit.SetColor, Kit.TipLine, Kit.Snap
local NARROW_FONT = Kit.NARROW_FONT

local RAIL_ROW_H, RAIL_HEADER_H = 24, 30
local RAIL_W = 170

local function SetIcon(texture, entry)
	if entry.atlas then
		texture:SetAtlas(entry.atlas)
	else
		texture:SetTexture(entry.icon or ns.ICON)
	end
end

-- Rail -----------------------------------------------------------------------------------------------------

local function CreateRailRow(parent, onSelect)
	-- Map rows open the world map first (ns.MapTabs_Opener); the row's own click is its PostClick.
	local row = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
	ns.MapTabs_Opener(row, function(self)
		return self.entry ~= nil and self.entry.kind == "map"
	end, true)
	row:SetHeight(RAIL_ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(UI.Color("accent"))
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 12, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.text = UI.Text(row, 13, "text")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row.text:SetWordWrap(false)
	-- Count pill at the right end: accent digits on a dark backing (the text ends at it while it shows).
	row.pill = CreateFrame("Frame", nil, row)
	row.pill:SetHeight(16)
	row.pill:SetPoint("RIGHT", -8, 0)
	local pillBg = row.pill:CreateTexture(nil, "BACKGROUND")
	pillBg:SetAllPoints()
	pillBg:SetColorTexture(0, 0, 0, 0.6)
	UI.Border(row.pill, "frame", 0.3)
	row.pill.text = row.pill:CreateFontString(nil, "OVERLAY")
	UI.SetFont(row.pill.text, NARROW_FONT, 12)
	row.pill.text:SetPoint("CENTER", 0, 0)
	SetColor(row.pill.text, "accent")
	row.pill:Hide()
	function row:SetPill(text, tip)
		if self.pillSet and text == self.pillText and tip == self.pillTipGiven then
			return -- polled every second: only lay out a change
		end
		self.pillSet, self.pillText, self.pillTipGiven = true, text, tip
		self.pillTip = text ~= "" and tip or nil
		self.pill:SetShown(text ~= "")
		self.text:SetPoint("RIGHT", self, "RIGHT", -6, 0)
		if text ~= "" then
			self.pill.text:SetText(text)
			self.pill:SetWidth(math.max(Snap(self.pill.text:GetUnboundedStringWidth()) + 10, 18))
			self.text:SetPoint("RIGHT", self.pill, "LEFT", -6, 0)
		end
	end
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		local entry = self.entry
		if entry then
			local summary = ns.HomeCall(entry.summary)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(entry.name, UI.Color("heading"))
			if type(summary) == "string" and summary ~= "" then
				TipLine(GameTooltip, summary, "text")
			end
			if self.pillTip then
				TipLine(GameTooltip, self.pillTip, "heading")
			end
			if entry.kind == "map" then
				TipLine(GameTooltip, "Opens the world map on this tab", "accent")
			end
			ns.MapTabs_CombatTip(self)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetShown(self.selected)
		GameTooltip:Hide()
	end)
	row:SetScript("PostClick", function(self)
		onSelect(self.entry)
	end)
	return row
end

-- onSelect(entry) runs on a click; entry is nil for the Home row.
function ns.PanelRail_Create(parent, onSelect)
	local rail = CreateFrame("Frame", nil, parent)
	rail:SetWidth(RAIL_W)
	local bg = rail:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.25)
	rail.rows = {}
	rail.header = UI.Text(rail, 12, "textFaint")
	rail.header:SetText("On the world map")

	local function Row(i)
		local row = rail.rows[i]
		if not row then
			row = CreateRailRow(rail, onSelect)
			rail.rows[i] = row
		end
		return row
	end

	-- A page's pill (entry.pill, "Counts on the rail"); map entries never have one.
	local function Pill(entry)
		local window = ns.db.window
		if not (entry and entry.kind == "page" and entry.pill and (not window or window.pills ~= false)) then
			return ""
		end
		local n = ns.HomeCall(entry.pill)
		local tip = entry.pillTip
		if type(tip) == "function" then
			tip = ns.HomeCall(tip, n)
		end
		return ns.Home_PillText(n), tip
	end

	local function Place(row, entry, y, selected)
		row.entry = entry
		ns.MapTabs_OpenerSync(row)
		row.selected = selected
		if entry then
			SetIcon(row.icon, entry)
			row.text:SetText(entry.name)
		else
			row.icon:SetTexture(ns.ICON)
			row.text:SetText("Home")
		end
		row:SetPill(Pill(entry))
		SetColor(row.text, selected and "heading" or (entry and entry.kind == "map" and "accent" or "text"))

		row.bar:SetShown(selected)
		row.bg:SetShown(selected or row:IsMouseOver())
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", rail, "RIGHT")
		row:Show()
	end

	-- Counts change without the rail redrawing (a craft made, the vault, Concentration filling over time), so the
	-- pills alone are re-read once a second while the rail shows.
	local PILL_EVERY = 1
	local since = 0
	rail:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < PILL_EVERY then
			return
		end
		since = 0
		for _, row in ipairs(rail.rows) do
			if row:IsShown() and row.entry then
				row:SetPill(Pill(row.entry))
			end
		end
	end)

	-- selected: the open page's entry, or nil on Home.
	function rail:Refresh(selected)
		local n, y = 1, 10
		Place(Row(1), nil, y, selected == nil)
		y = y + RAIL_ROW_H + 6
		for _, entry in ipairs(ns.HomeEntries("page")) do
			n = n + 1
			Place(Row(n), entry, y, entry == selected)
			y = y + RAIL_ROW_H
		end
		local maps = ns.HomeEntries("map")
		self.header:SetShown(#maps > 0)
		if #maps > 0 then
			self.header:ClearAllPoints()
			self.header:SetPoint("TOPLEFT", 12, -(y + 14))
			y = y + RAIL_HEADER_H
			for _, entry in ipairs(maps) do
				n = n + 1
				Place(Row(n), entry, y, false)
				y = y + RAIL_ROW_H
			end
		end
		for i = n + 1, #self.rows do
			self.rows[i]:Hide()
		end
	end

	return rail
end
