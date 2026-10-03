local addonName, ns = ...

-- Coverage tab of the Flight Timer entry in the panel: how many flight masters have a recorded time, as
-- continents > zones > flight masters (click a continent or zone to expand it). Rebuilt every time the tab
-- is shown, so a flight that just landed counts.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local ROW_H, NODE_H = 22, 18
local SCROLL_STEP = 40
local INDENT_ZONE, INDENT_NODE = 14, 30
local STATE_COLOR = { timed = GOLD, known = WHITE, undiscovered = DIM }
local STATE_TEXT = { timed = "", known = "no time yet", undiscovered = "undiscovered" }

local REBUILD_AFTER = 30 -- seconds

local page
local data
local builtFlights, builtAt = nil, 0
local expandedContinents, expandedZones = {}, {} -- [mapID] = true, for this session
local autoExpanded
local rows, used = {}, 0
local Layout

-- "Dornogal, Isle of Dorn" -> "Dornogal" (the zone is the row above)
local function Place(name)
	return name:match("^(.-),") or name
end

local function Count(entry)
	return ("%d / %d"):format(entry.timed, entry.total)
end

local function Legs(entry)
	return entry.legs == 1 and "1 leg" or (entry.legs .. " legs")
end

local function NewRow()
	local row = CreateFrame("Button", nil, page.content)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.04)
	row.hover:Hide()
	row.toggle = UI.Text(row, 12, GREY)
	row.toggle:SetWidth(10)
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetWordWrap(false)
	row.count = UI.Text(row, 12, WHITE)
	row.count:SetJustifyH("RIGHT")
	row.count:SetPoint("RIGHT", -6, 1)
	row.extra = UI.Text(row, 11, GREY)
	row.extra:SetJustifyH("RIGHT")
	row.track = row:CreateTexture(nil, "ARTWORK")
	row.track:SetColorTexture(1, 1, 1, 0.08)
	row.track:SetHeight(1)
	row.track:SetPoint("BOTTOMRIGHT", -6, 1)
	row.fill = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	row.fill:SetHeight(1)
	row.fill:SetPoint("LEFT", row.track, "LEFT")
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetColorTexture(1, 1, 1, 1)
	row.dot:SetSize(6, 6)
	local mask = row:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(row.dot)
	row.dot:AddMaskTexture(mask)
	row:SetScript("OnEnter", function(self)
		self.hover:SetShown(self.onClick ~= nil)
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if self.onClick then
			self.onClick()
			Layout()
		end
	end)
	return row
end

local function Acquire(y, height)
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", page.content, "RIGHT")
	row:SetHeight(height)
	row:Show()
	return row
end

-- Continent or zone row: toggle, name, legs, count and a progress hairline.
local function GroupRow(y, width, indent, entry, expanded, nameColor, onClick)
	local row = Acquire(y, ROW_H)
	row.onClick = onClick
	row.toggle:ClearAllPoints()
	row.toggle:SetPoint("LEFT", indent + 4, 1)
	row.toggle:SetText(expanded and "-" or "+")
	row.toggle:Show()
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(entry.name)
	row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
	row.count:SetText(Count(entry))
	local done = entry.timed == entry.total
	local c = done and GOLD or WHITE
	row.count:SetTextColor(c[1], c[2], c[3])
	row.count:Show()
	row.extra:ClearAllPoints()
	row.extra:SetPoint("RIGHT", row.count, "LEFT", -10, 0)
	row.extra:SetText(Legs(entry))
	row.extra:Show()
	row.track:SetPoint("BOTTOMLEFT", indent + 18, 1)
	row.track:Show()
	local trackWidth = math.max(width - indent - 24, 1)
	row.fill:SetWidth(math.max(trackWidth * entry.timed / math.max(entry.total, 1), 0.01))
	row.fill:Show()
	row.dot:Hide()
	return row
end

local function NodeRow(y, node)
	local row = Acquire(y, NODE_H)
	row.onClick = nil
	row.toggle:Hide()
	row.track:Hide()
	row.fill:Hide()
	row.count:Hide()
	local c = STATE_COLOR[node.state]
	row.dot:ClearAllPoints()
	row.dot:SetPoint("LEFT", INDENT_NODE, 0)
	row.dot:SetVertexColor(c[1], c[2], c[3], node.state == "undiscovered" and 0.6 or 1)
	row.dot:Show()
	row.extra:ClearAllPoints()
	row.extra:SetPoint("RIGHT", -6, 0)
	row.extra:SetText(STATE_TEXT[node.state])
	row.extra:Show()
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.extra, "LEFT", -8, 0)
	row.name:SetText(Place(node.name))
	row.name:SetTextColor(c[1], c[2], c[3])
	return row
end

local function UpdateThumb()
	local viewH, contentH = page.scroll:GetHeight(), page.content:GetHeight()
	if contentH <= viewH + 1 then
		page.thumb:Hide()
		return
	end
	local thumbH = math.max(viewH * viewH / contentH, 20)
	local offset = page.scroll:GetVerticalScroll() / (contentH - viewH) * (viewH - thumbH)
	page.thumb:SetHeight(thumbH)
	page.thumb:ClearAllPoints()
	page.thumb:SetPoint("TOPLEFT", page.scroll, "TOPRIGHT", 4, -offset)
	page.thumb:Show()
end

local function SetScroll(value)
	local maxScroll = math.max(page.content:GetHeight() - page.scroll:GetHeight(), 0)
	page.scroll:SetVerticalScroll(math.min(math.max(value, 0), maxScroll))
	UpdateThumb()
end

function Layout()
	local width = page.scroll:GetWidth()
	if not data or width <= 1 then
		return -- OnSizeChanged lays out again once the page has a size
	end
	used = 0
	local y = 0
	for _, continent in ipairs(data.continents) do
		local cOpen = expandedContinents[continent.mapID]
		GroupRow(y, width, 0, continent, cOpen, GOLD, function()
			expandedContinents[continent.mapID] = not cOpen or nil
		end)
		y = y + ROW_H
		if cOpen then
			for _, zone in ipairs(continent.zones) do
				local zOpen = expandedZones[zone.mapID]
				GroupRow(y, width, INDENT_ZONE, zone, zOpen, WHITE, function()
					expandedZones[zone.mapID] = not zOpen or nil
				end)
				y = y + ROW_H
				if zOpen then
					for _, node in ipairs(zone.nodes) do
						NodeRow(y, node)
						y = y + NODE_H
					end
				end
			end
			y = y + 4
		end
	end
	for i = used + 1, #rows do
		rows[i]:Hide()
	end
	page.content:SetHeight(math.max(y, 1))
	SetScroll(page.scroll:GetVerticalScroll())
end

-- The first time: open the continent and zone the player is in.
local function AutoExpand()
	if autoExpanded then
		return
	end
	autoExpanded = true
	local here = ns.Atlas_PlayerZone()
	if not here then
		return
	end
	for _, continent in ipairs(data.continents) do
		for _, zone in ipairs(continent.zones) do
			if zone.mapID == here.mapID then
				expandedContinents[continent.mapID] = true
				expandedZones[zone.mapID] = true
				return
			end
		end
	end
end

local function Refresh()
	-- The panel shows the page again after every hover elsewhere; only rebuild (a few hundred map lookups)
	-- after a flight or once the data is a little old.
	local flights = ns.flightDB.stats.flights
	if not data or flights ~= builtFlights or GetTime() - builtAt > REBUILD_AFTER then
		data = ns.Coverage_Summarize(ns.Atlas_Build(), ns.flightDB)
		builtFlights, builtAt = flights, GetTime()
	end
	if data.total == 0 then
		page.summary:SetText("No flight masters found.")
		page.fill:SetWidth(0.01)
	else
		page.summary:SetText(("%d / %d flight masters timed   -   %s"):format(data.timed, data.total, Legs(data)))
		page.fill:SetWidth(math.max(page.track:GetWidth() * data.timed / data.total, 0.01))
	end
	AutoExpand()
	Layout()
end

local function Create(frame)
	page = frame
	page.summary = UI.Text(page, 13, WHITE)
	page.summary:SetPoint("TOPLEFT", 8, -2)
	page.summary:SetPoint("RIGHT", -8, 0)
	page.track = page:CreateTexture(nil, "ARTWORK")
	page.track:SetColorTexture(1, 1, 1, 0.1)
	page.track:SetHeight(2)
	page.track:SetPoint("TOPLEFT", page.summary, "BOTTOMLEFT", 0, -8)
	page.track:SetPoint("RIGHT", -8, 0)
	page.fill = page:CreateTexture(nil, "ARTWORK", nil, 1)
	page.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	page.fill:SetHeight(2)
	page.fill:SetPoint("LEFT", page.track, "LEFT")
	page.fill:SetWidth(0.01)

	page.scroll = CreateFrame("ScrollFrame", nil, page)
	page.scroll:SetPoint("TOPLEFT", page.track, "BOTTOMLEFT", -8, -10)
	page.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	page.scroll:EnableMouseWheel(true)
	page.content = CreateFrame("Frame", nil, page.scroll)
	page.content:SetSize(1, 1)
	page.scroll:SetScrollChild(page.content)
	page.scroll:SetScript("OnSizeChanged", function(self, width)
		page.content:SetWidth(width)
		Layout()
		if data and data.total > 0 then
			page.fill:SetWidth(math.max(page.track:GetWidth() * data.timed / data.total, 0.01))
		end
	end)
	page.scroll:SetScript("OnMouseWheel", function(self, delta)
		SetScroll(self:GetVerticalScroll() - delta * SCROLL_STEP)
	end)
	page.thumb = page:CreateTexture(nil, "OVERLAY")
	page.thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	page.thumb:SetWidth(2)
	page.thumb:Hide()
end

ns.CoveragePage = { title = "Coverage", Create = Create, Refresh = Refresh }
