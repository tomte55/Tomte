local addonName, ns = ...

-- The rail beside every panel view but Settings: Home, the pages and the world map tabs, each with an optional count
-- pill. Exports ns.PanelRail_Create. The Home view is Home.lua; the kit is HomeKit.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local SetColor, TipLine, Snap = Kit.SetColor, Kit.TipLine, Kit.Snap
local NARROW_FONT = Kit.NARROW_FONT

local RAIL_ROW_H, RAIL_HEADER_H = 24, 30
local RAIL_W = 170
local PILL_RULE = 0.3 -- the pill's border alpha at rest
local PILL_FLASH = 0.3 -- peak of the accent wash behind a count that changed
local PILL_FLASH_SECONDS = 0.6

local function SetIcon(texture, entry)
	if entry.atlas then
		texture:SetAtlas(entry.atlas)
	else
		texture:SetTexture(entry.icon or ns.ICON)
	end
end

-- A count that changed while shown: its digits light up and ease back to accent, the border brightens and settles,
-- and an accent wash rises behind them. Text flashes rather than scales (scaled text steps; Motion.lua).
local function FlashPill(pill)
	local r, g, b = UI.Color("heading")
	local ar, ag, ab = UI.Color("accent")
	UI.Tween(pill.text, "flash", PILL_FLASH_SECONDS, function(t)
		pill.text:SetTextColor(UI.Lerp(r, ar, t), UI.Lerp(g, ag, t), UI.Lerp(b, ab, t))
	end, nil, ns.Smoothstep)
	UI.SetBorderColor(pill, "accent", 1)
	UI.BorderTo(pill, "frame", PILL_RULE, PILL_FLASH_SECONDS)
	UI.Flash(pill, "accent", PILL_FLASH)
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
	row.bg:SetAlpha(0) -- eased in on hover and while selected (UI.WashTo)
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
	UI.Border(row.pill, "frame", PILL_RULE)
	row.pill.text = row.pill:CreateFontString(nil, "OVERLAY")
	UI.SetFont(row.pill.text, NARROW_FONT, 12)
	row.pill.text:SetPoint("CENTER", 0, 0)
	SetColor(row.pill.text, "accent")
	row.pill:Hide()
	function row:SetPill(text, tip)
		if self.pillSet and text == self.pillText and tip == self.pillTipGiven and self.pillFor == self.entry then
			return -- polled every second: only lay out a change
		end
		-- The same page's count, seen changing on screen: a new pill fades in, a changed one flashes.
		local live = self.pillSet and self.pillFor == self.entry and self:IsVisible()
		local was = self.pill:IsShown() and self.pillText or ""
		self.pillSet, self.pillText, self.pillTipGiven, self.pillFor = true, text, tip, self.entry
		self.pillTip = text ~= "" and tip or nil
		self.pill:SetShown(text ~= "")
		self.text:SetPoint("RIGHT", self, "RIGHT", -6, 0)
		if text ~= "" then
			self.pill.text:SetText(text)
			self.pill:SetWidth(math.max(Snap(self.pill.text:GetUnboundedStringWidth()) + 10, 18))
			self.text:SetPoint("RIGHT", self.pill, "LEFT", -6, 0)
			if live and was == "" then
				UI.Appear(self.pill)
			elseif live and was ~= text then
				FlashPill(self.pill)
			end
		end
	end
	row:SetScript("OnEnter", function(self)
		UI.WashTo(self.bg, true)
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
		UI.WashTo(self.bg, self.selected)
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
	-- The accent bar on the open page's row, gliding to the next one (UI.SlideTo). A frame above the rows, so their
	-- hover wash doesn't cover it; it takes no mouse.
	rail.marker = CreateFrame("Frame", nil, rail)
	rail.marker:SetFrameLevel(rail:GetFrameLevel() + 5)
	rail.marker:SetWidth(2)
	local markerBar = rail.marker:CreateTexture(nil, "ARTWORK")
	markerBar:SetAllPoints()
	markerBar:SetColorTexture(UI.Color("accent"))
	rail.marker:Hide()

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

		-- A row that now holds another entry (the rail's pages changed) starts from nothing.
		UI.WashTo(row.bg, selected or row:IsMouseOver(), row.placed ~= entry)
		row.placed = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", rail, "RIGHT")
		row:Show()
		if selected then
			UI.SlideTo(rail.marker, 0, y, RAIL_ROW_H)
			rail.marked = true
		end
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

	-- Pages that came or went since the rail last showed (a module turned on or off in Settings): a new row fades in
	-- and the rows that moved glide from where they were, so the rail opens or closes instead of jumping. lastY is
	-- where each entry's row (and the map header) sat the last time; the first draw has none and animates nothing.
	local lastY
	local function Arrivals(placedY, n, headerY)
		local previous = lastY
		lastY = placedY
		lastY.header = headerY
		if not (previous and rail:IsVisible()) then
			return
		end
		for i = 1, n do
			local row = rail.rows[i]
			local was = previous[row.entry or "home"]
			local now = placedY[row.entry or "home"]
			if was == nil then
				UI.FadeIn(row)
			elseif was < now then
				UI.SlideDown(rail.rows, i, i, now - was)
			elseif was > now then
				UI.SlideUp(rail.rows, i, i, was - now)
			end
		end
		if headerY and previous.header then
			local list = { rail.header }
			if previous.header < headerY then
				UI.SlideDown(list, 1, 1, headerY - previous.header)
			elseif previous.header > headerY then
				UI.SlideUp(list, 1, 1, previous.header - headerY)
			end
		end
	end

	-- selected: the open page's entry, or nil on Home.
	function rail:Refresh(selected)
		local n, y = 1, 10
		local placedY = { home = y }
		self.marked = false
		Place(Row(1), nil, y, selected == nil)
		y = y + RAIL_ROW_H + 6
		for _, entry in ipairs(ns.HomeEntries("page")) do
			n = n + 1
			Place(Row(n), entry, y, entry == selected)
			placedY[entry] = y
			y = y + RAIL_ROW_H
		end
		local maps = ns.HomeEntries("map")
		local headerY
		self.header:SetShown(#maps > 0)
		if #maps > 0 then
			self.header:ClearAllPoints()
			self.header:SetPoint("TOPLEFT", 12, -(y + 14))
			headerY = y
			y = y + RAIL_HEADER_H
			for _, entry in ipairs(maps) do
				n = n + 1
				Place(Row(n), entry, y, false)
				placedY[entry] = y
				y = y + RAIL_ROW_H
			end
		end
		for i = n + 1, #self.rows do
			self.rows[i]:Hide()
		end
		if not self.marked then
			self.marker:Hide()
		end
		Arrivals(placedY, n, headerY)
	end

	return rail
end
