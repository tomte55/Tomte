local addonName, ns = ...

-- Sessions page (Home rail): past sessions from the recap's history. A bar chart of the latest sessions (gold per
-- hour or net gold, with loot value beside it when Gold & value prices loot), filters for this character / all and
-- this week / all time with totals, and a list; click a row for its recap card. History logic in History.lua.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN, RED = { 0.45, 0.85, 0.45 }, { 1, 0.45, 0.35 }
local VALUE_BLUE = { 0.56, 0.78, 1 }
local CHART_H = 130
local CHART_BARS = 30
local ROW_H = 24
local NIGHT_H = 26
local NIGHT_GAP = 3600
local COLUMNS = { -- x and width as fractions of the list width
	{ key = "when", x = 0, w = 0.2 },
	{ key = "char", x = 0.2, w = 0.15 },
	{ key = "time", x = 0.35, w = 0.09, right = true },
	{ key = "zone", x = 0.46, w = 0.2 },
	{ key = "net", x = 0.66, w = 0.11, right = true },
	{ key = "hour", x = 0.77, w = 0.11, right = true },
	{ key = "value", x = 0.88, w = 0.12, right = true },
}
local HEADS = { when = "When", char = "Character", time = "Time", zone = "Mostly in", net = "Net gold", hour = "Gold / h",
	value = "Loot worth" }

local page, db

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function Signed(copper)
	if not copper then
		return ""
	end
	return (copper < 0 and "-" or "+") .. ns.Alts_Gold(math.abs(copper))
end

local function ClassColor(class)
	local c = class and C_ClassColor.GetClassColor(class)
	return c and { c.r, c.g, c.b } or WHITE
end

local function WeekStart()
	local left = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if not left then
		return nil
	end
	return GetServerTime() + left - 7 * 86400
end

local function List()
	local since = db.pageRange == "week" and WeekStart() or nil
	return ns.Recap_HistoryFilter(db.history, db.pageScope, UnitGUID("player"), since)
end

local function Main(n)
	if db.mainNumber == "net" then
		return n.net, n.value
	end
	return n.perHour, n.valuePerHour
end

local function SessionTooltip(owner, h)
	local n = ns.Recap_HistoryNumbers(h)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(("%s, %s"):format(h.name or "?", date("%a %d %b %H:%M", h.start)), unpack(ClassColor(h.class)))
	GameTooltip:AddLine(("%s%s"):format(ns.Recap_Duration(n.duration), h.zone and (", mostly in " .. h.zone) or ""), 1, 1, 1)
	GameTooltip:AddDoubleLine("Net gold", Signed(n.net), GREY[1], GREY[2], GREY[3], 1, 1, 1)
	GameTooltip:AddDoubleLine("Gold per hour", Signed(n.perHour), GREY[1], GREY[2], GREY[3], 1, 1, 1)
	if n.value then
		GameTooltip:AddDoubleLine("Loot worth", ns.Alts_Gold(n.value), GREY[1], GREY[2], GREY[3], VALUE_BLUE[1],
			VALUE_BLUE[2], VALUE_BLUE[3])
	end
	local line = h.counts and ns.Recap_CountsLine and ns.Recap_CountsLine(h.counts)
	if line and line ~= "" then
		GameTooltip:AddLine(line, GREY[1], GREY[2], GREY[3], true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click for the recap card", GOLD[1], GOLD[2], GOLD[3])
	GameTooltip:Show()
end

local function Open(h)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	ns.Panel_Hide()
	ns.Recap_ShowStored(h)
end

-- Chart ----------------------------------------------------------------------------------------------------------

local function CreateChart(parent)
	local chart = CreateFrame("Frame", nil, parent)
	chart:SetHeight(CHART_H)
	chart.bg = chart:CreateTexture(nil, "BACKGROUND")
	chart.bg:SetAllPoints()
	chart.bg:SetColorTexture(1, 1, 1, 0.025)
	chart.zero = chart:CreateTexture(nil, "ARTWORK")
	chart.zero:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
	chart.zero:SetHeight(1)
	chart.label = UI.Text(chart, 11, GREY)
	chart.label:SetPoint("TOPLEFT", 6, -4)
	chart.max = chart:CreateFontString(nil, "OVERLAY")
	chart.max:SetFont(ns.HomeKit.NARROW_FONT, 12, "")
	chart.max:SetPoint("TOPRIGHT", -6, -4)
	chart.max:SetTextColor(GREY[1], GREY[2], GREY[3])
	chart.slots = {}
	return chart
end

local function Slot(chart, i)
	local slot = chart.slots[i]
	if not slot then
		slot = CreateFrame("Button", nil, chart)
		slot.hl = slot:CreateTexture(nil, "BACKGROUND")
		slot.hl:SetAllPoints()
		slot.hl:SetColorTexture(1, 1, 1, 0.05)
		slot.hl:Hide()
		slot.gold = slot:CreateTexture(nil, "ARTWORK")
		slot.value = slot:CreateTexture(nil, "ARTWORK")
		slot:SetScript("OnEnter", function(self)
			self.hl:Show()
			SessionTooltip(self, self.h)
		end)
		slot:SetScript("OnLeave", function(self)
			self.hl:Hide()
			GameTooltip:Hide()
		end)
		slot:SetScript("OnClick", function(self)
			Open(self.h)
		end)
		chart.slots[i] = slot
	end
	return slot
end

-- Oldest on the left. Bars from a zero line that sits higher when there are losses.
local function DrawChart(chart, list)
	local n = math.min(#list, CHART_BARS)
	local width, height = chart:GetWidth(), CHART_H - 26
	local high, low = 0, 0
	local numbers = {}
	for i = 1, n do
		local h = list[n - i + 1]
		local main, value = Main(ns.Recap_HistoryNumbers(h))
		numbers[i] = { h = h, main = main, value = value }
		high = math.max(high, main, value or 0)
		low = math.min(low, main)
	end
	local span = math.max(high - low, 1)
	local zeroY = 6 + (-low / span) * height
	chart.zero:ClearAllPoints()
	chart.zero:SetPoint("BOTTOMLEFT", 0, zeroY)
	chart.zero:SetPoint("BOTTOMRIGHT", 0, zeroY)
	chart.label:SetText(db.mainNumber == "net" and "Net gold per session" or "Gold per hour")
	chart.max:SetText(n > 0 and ns.Alts_Gold(high) or "")
	local slotW = n > 0 and math.min(width / n, 48) or 0
	for i, num in ipairs(numbers) do
		local slot = Slot(chart, i)
		slot.h = num.h
		slot:ClearAllPoints()
		slot:SetPoint("BOTTOMLEFT", (i - 1) * slotW, 0)
		slot:SetSize(slotW, CHART_H - 20)
		local hasValue = num.value ~= nil
		local barW = math.max(math.floor(slotW * (hasValue and 0.36 or 0.6)), 2)
		local gh = math.max(math.abs(num.main) / span * height, 1)
		slot.gold:ClearAllPoints()
		if num.main >= 0 then
			slot.gold:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", math.floor(slotW * 0.15), zeroY)
			slot.gold:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
		else
			slot.gold:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", math.floor(slotW * 0.15), zeroY - gh)
			slot.gold:SetColorTexture(RED[1], RED[2], RED[3], 0.85)
		end
		slot.gold:SetSize(barW, gh)
		slot.value:SetShown(hasValue)
		if hasValue then
			local vh = math.max(num.value / span * height, 1)
			slot.value:ClearAllPoints()
			slot.value:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", math.floor(slotW * 0.15) + barW + 2, zeroY)
			slot.value:SetSize(barW, vh)
			slot.value:SetColorTexture(VALUE_BLUE[1], VALUE_BLUE[2], VALUE_BLUE[3], 0.75)
		end
		slot:Show()
	end
	for i = n + 1, #chart.slots do
		chart.slots[i]:Hide()
	end
	chart.none = chart.none or UI.Text(chart, 13, GREY)
	chart.none:SetPoint("CENTER")
	chart.none:SetText("No sessions here yet. A session is kept when you log in again after it (2 minutes or longer).")
	chart.none:SetShown(n == 0)
end

-- List -----------------------------------------------------------------------------------------------------------

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.04)
	row.bg:Hide()
	row.cells = {}
	for i, col in ipairs(COLUMNS) do
		local fs
		if col.right or col.key == "time" then
			fs = row:CreateFontString(nil, "OVERLAY")
			fs:SetFont(ns.HomeKit.NARROW_FONT, 14, "")
			fs:SetShadowOffset(1, -1)
		else
			fs = UI.Text(row, 12, WHITE)
		end
		fs:SetWordWrap(false)
		fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
		row.cells[i] = fs
	end
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		if self.h then
			SessionTooltip(self, self.h)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if self.h then
			Open(self.h)
		end
	end)
	return row
end

local function PlaceCells(row, width, indent)
	for i, col in ipairs(COLUMNS) do
		local fs = row.cells[i]
		local x = math.floor(col.x * width) + 6 + (i == 1 and indent or 0)
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(math.floor(col.w * width) - 8 - (i == 1 and indent or 0))
	end
end

local function FillSession(row, h, width, indent)
	row.h = h
	row:SetHeight(ROW_H)
	PlaceCells(row, width, indent)
	local n = ns.Recap_HistoryNumbers(h)
	local c = row.cells
	c[1]:SetText(date(indent > 0 and "%H:%M" or "%a %d %b  %H:%M", h.start))
	SetColor(c[1], GREY)
	c[2]:SetText(h.name or "?")
	SetColor(c[2], ClassColor(h.class))
	c[3]:SetText(ns.Recap_Duration(n.duration))
	SetColor(c[3], WHITE)
	c[4]:SetText(h.zone or "")
	SetColor(c[4], GREY)
	c[5]:SetText(Signed(n.net))
	SetColor(c[5], n.net < 0 and RED or GOLD)
	c[6]:SetText(Signed(n.perHour))
	SetColor(c[6], n.perHour < 0 and RED or WHITE)
	c[7]:SetText(n.value and ns.Alts_Gold(n.value) or "")
	SetColor(c[7], VALUE_BLUE)
end

local function FillNight(row, night, width)
	row.h = nil
	row:SetHeight(NIGHT_H)
	PlaceCells(row, width, 0)
	local t = ns.Recap_HistoryTotals(night.sessions)
	local c = row.cells
	c[1]:SetText(("%s  %s-%s"):format(date("%a %d %b", night.first), date("%H:%M", night.first), date("%H:%M", night.last)))
	SetColor(c[1], GOLD)
	c[2]:SetText(#night.sessions == 1 and "1 session" or (#night.sessions .. " sessions"))
	SetColor(c[2], GREY)
	c[3]:SetText(ns.Recap_Duration(t.duration))
	SetColor(c[3], GOLD)
	c[4]:SetText("")
	c[5]:SetText(Signed(t.net))
	SetColor(c[5], t.net < 0 and RED or GOLD)
	c[6]:SetText(Signed(t.perHour))
	SetColor(c[6], GOLD)
	c[7]:SetText(t.value > 0 and ns.Alts_Gold(t.value) or "")
	SetColor(c[7], VALUE_BLUE)
end

local function Toggle(parent, width, get, texts, set)
	local b = UI.Button(parent, width, "")
	b:SetHeight(22)
	function b:Update()
		self.label:SetText(texts[get()])
	end
	b:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		set()
		page.Refresh()
	end)
	return b
end

local function Refresh()
	local list = List()
	page.scope:Update()
	page.range:Update()
	local t = ns.Recap_HistoryTotals(list)
	page.totals:SetText(("%d session%s · %s · net %s · %s/h%s"):format(t.count, t.count == 1 and "" or "s",
		ns.Recap_Duration(t.duration), Signed(t.net), Signed(t.perHour),
		t.value > 0 and (" · loot worth " .. ns.Alts_Gold(t.value)) or ""))
	DrawChart(page.chart, list)

	local width = math.max(page.scroll:GetWidth(), 400)
	for i, col in ipairs(COLUMNS) do
		local fs = page.heads[i]
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", math.floor(col.x * width) + 6, 0)
		fs:SetWidth(math.floor(col.w * width) - 8)
		fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
	end
	local y, used = 0, 0
	local function Next()
		used = used + 1
		local row = page.rows[used]
		if not row then
			row = CreateRow(page.scroll.content)
			page.rows[used] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		return row
	end
	if db.nights then
		for _, night in ipairs(ns.Recap_HistoryNights(list, NIGHT_GAP)) do
			FillNight(Next(), night, width)
			y = y + NIGHT_H
			for _, h in ipairs(night.sessions) do
				FillSession(Next(), h, width, 16)
				y = y + ROW_H
			end
		end
	else
		for _, h in ipairs(list) do
			FillSession(Next(), h, width, 0)
			y = y + ROW_H
		end
	end
	for i = used + 1, #page.rows do
		page.rows[i]:Hide()
	end
	page.scroll:SetContentHeight(y)
end

ns.RecapSessionsPage = {
	title = "Sessions",
	Create = function(frame)
		page = frame
		db = ns.recapDB
		frame.Refresh = Refresh
		frame.scope = Toggle(frame, 120, function()
			return db.pageScope
		end, { char = "This character", all = "All characters" }, function()
			db.pageScope = db.pageScope == "char" and "all" or "char"
		end)
		frame.scope:SetPoint("TOPLEFT", 8, 2)
		frame.range = Toggle(frame, 90, function()
			return db.pageRange
		end, { week = "This week", all = "All time" }, function()
			db.pageRange = db.pageRange == "week" and "all" or "week"
		end)
		frame.range:SetPoint("LEFT", frame.scope, "RIGHT", 8, 0)
		frame.totals = UI.Text(frame, 12, GREY)
		frame.totals:SetPoint("LEFT", frame.range, "RIGHT", 14, 0)
		frame.totals:SetPoint("RIGHT", -8, 0)
		frame.totals:SetJustifyH("RIGHT")
		frame.totals:SetWordWrap(false)

		frame.chart = CreateChart(frame)
		frame.chart:SetPoint("TOPLEFT", 8, -32)
		frame.chart:SetPoint("RIGHT", -8, 0)

		local head = CreateFrame("Frame", nil, frame)
		head:SetPoint("TOPLEFT", frame.chart, "BOTTOMLEFT", 0, -10)
		head:SetPoint("RIGHT", -18, 0)
		head:SetHeight(20)
		frame.heads = {}
		for i, col in ipairs(COLUMNS) do
			local fs = UI.Text(head, 11, GREY)
			fs:SetText(HEADS[col.key])
			frame.heads[i] = fs
		end
		local line = head:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")

		frame.scroll = UI.Scroll(frame)
		frame.scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
		frame.scroll:SetPoint("BOTTOMRIGHT", -18, 0)
		frame.scroll.onWidthChanged = function()
			if frame:IsVisible() then
				Refresh()
			end
		end
		frame.rows = {}
	end,
	Refresh = function()
		Refresh()
	end,
}
