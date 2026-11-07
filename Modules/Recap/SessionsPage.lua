local addonName, ns = ...

-- Sessions page (Home rail): past sessions from the recap's history. A bar chart of the latest sessions (gold per
-- hour or net gold, with loot value beside it when Gold & value prices loot), filters for this character / all and
-- this week / all time with totals, and a list; click a row for its recap card. History logic in History.lua.

local UI = ns.UI
-- Colors by role: money text in "heading", its bars in "accentDeep" (the heading's full yellow was loud as a block, and
-- on Forever the same as loot), loot value in "info" so a session's two bars differ in every theme, losses "danger".
local MONEY, MONEY_BAR, VALUE, LOSS = "heading", "accentDeep", "info", "danger"
local LEVELS = "success" -- the levels bar
local SWATCH = 9 -- the legend's color squares, in pixels
local CHART_H = 130
local CHART_BARS = 30
local ROW_H = 24
local NIGHT_H = 26
local NIGHT_GAP = 3600
local NIGHT_SPACE = 6 -- pixels between two play nights in the list
local LIVE_EVERY = 30 -- seconds between redraws while the page is open, so the session going on now keeps counting
local COLUMNS = { -- x and width as fractions of the list width; cells are filled by index, so new ones go last
	{ key = "when", x = 0, w = 0.18 },
	{ key = "char", x = 0.18, w = 0.13 },
	{ key = "time", x = 0.31, w = 0.08, right = true },
	{ key = "zone", x = 0.4, w = 0.17 },
	{ key = "net", x = 0.66, w = 0.11, right = true },
	{ key = "hour", x = 0.77, w = 0.11, right = true },
	{ key = "value", x = 0.88, w = 0.12, right = true },
	{ key = "levels", x = 0.57, w = 0.09, right = true },
}
local HEADS = { when = "When", char = "Character", time = "Time", zone = "Mostly in", net = "Net gold", hour = "Gold / h",
	value = "Loot worth", levels = "Levels" }

local page, db

-- c: a theme role or an r, g, b table (class colors).
local function SetColor(fs, c)
	fs:SetTextColor(UI.RGBA(c))
end

local Signed = ns.SignedGold

local function ClassColor(class)
	local c = class and C_ClassColor.GetClassColor(class)
	return c and { c.r, c.g, c.b } or { UI.Color("text") }
end

-- The session going on now, as a history record (History.lua's Recap_Live).
local function LiveRecord()
	local session = ns.Session_Current()
	local now = GetServerTime()
	local value, by
	if ns.Value_SessionLoot then
		value, by = ns.Value_SessionLoot(session)
	end
	return ns.Recap_Live(session, now, GetMoney(), { zone = ns.Session_TopZone(session, now), lootValue = value,
		lootBy = by })
end

-- Newest first, the session going on now on top: history only gets a session once the next one starts.
local function List()
	local since = db.pageRange == "week" and ns.WeekStart() or nil
	local list = ns.Recap_HistoryFilter(db.history, db.pageScope, UnitGUID("player"), since)
	local live = LiveRecord()
	if live and (not since or live.start >= since) then
		table.insert(list, 1, live)
	end
	return list
end

-- What a session's bars show: gold, loot worth and levels, per session or per hour by the "Chart shows" setting.
local function Main(n)
	if db.mainNumber == "net" then
		return n.net, n.value, n.levels
	end
	return n.perHour, n.valuePerHour, n.levelsPerHour
end

-- "+1.25": levels gained, "" for none.
local function LevelsText(levels)
	return levels and ("+%.2f"):format(levels) or ""
end

local function SessionTooltip(owner, h)
	local n = ns.Recap_HistoryNumbers(h)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local when = h.live and ("now, since %s"):format(date("%H:%M", h.start)) or date("%a %d %b %H:%M", h.start)
	GameTooltip:SetText(("%s, %s"):format(h.name or "?", when), unpack(ClassColor(h.class)))
	GameTooltip:AddLine(("%s%s"):format(ns.Recap_Duration(n.duration), h.zone and (", mostly in " .. h.zone) or ""), 1, 1, 1)
	local mr, mg, mb = UI.Color("textMuted")
	-- Each number in its bar's color, so the tooltip says which bar is which.
	local function Line(label, text, role)
		local r, g, b = UI.Color(role)
		GameTooltip:AddDoubleLine(label, text, mr, mg, mb, r, g, b)
	end
	Line("Net gold", Signed(n.net), n.net < 0 and LOSS or MONEY_BAR)
	Line("Gold per hour", Signed(n.perHour), n.perHour < 0 and LOSS or MONEY_BAR)
	if n.value then
		Line("Loot worth", ns.Gold(n.value), VALUE)
	end
	if n.levels then
		Line("Levels", ("%s (%d to %d)"):format(LevelsText(n.levels), h.level, h.levelNow), LEVELS)
	end
	if n.xp then
		Line("XP", ("%s, %s per hour"):format(ns.Thousands(n.xp), ns.Thousands(n.xpPerHour)), LEVELS)
	end
	local gathered = h.gather and ns.Gather_SessionLine and ns.Gather_SessionLine(h.gather, ns.Gold)
	if gathered then
		GameTooltip:AddDoubleLine("Gathering", gathered, mr, mg, mb, 1, 1, 1)
	end
	local line = h.counts and ns.Recap_CountsLine and ns.Recap_CountsLine(h.counts)
	if line and line ~= "" then
		GameTooltip:AddLine(line, mr, mg, mb, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click for the recap card", UI.RGB("heading"))
	GameTooltip:Show()
end

local function Open(h)
	UI.Sound("open")
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
	chart.zero:SetColorTexture(UI.RGBA("frame", 0.5))
	chart.zero:SetHeight(1)
	chart.label = UI.Text(chart, 11, "textMuted")
	chart.label:SetPoint("TOPLEFT", 6, -4)
	chart.max = chart:CreateFontString(nil, "OVERLAY")
	UI.SetFont(chart.max, "number", 12)
	chart.max:SetPoint("TOPRIGHT", -6, -4)
	UI.SetTextRole(chart.max, "textMuted")
	chart.slots = {}
	-- What the colors mean, along the top: the main bar, loot worth (only when a session has it) and losses.
	chart.legend = CreateFrame("Frame", nil, chart)
	chart.legend:SetPoint("TOP", 0, -5)
	chart.legend:SetSize(1, 12)
	chart.keys = {}
	for i, role in ipairs({ MONEY_BAR, VALUE, LEVELS, LOSS }) do -- in the order DrawLegend's texts come
		local key = CreateFrame("Frame", nil, chart.legend)
		key.role = role
		key.swatch = key:CreateTexture(nil, "ARTWORK")
		key.swatch:SetSize(SWATCH, SWATCH)
		key.swatch:SetPoint("LEFT")
		key.text = UI.Text(key, 11, "textMuted")
		key.text:SetPoint("LEFT", key.swatch, "RIGHT", 4, 0)
		key:SetHeight(12)
		chart.keys[i] = key
	end
	return chart
end

-- Lays the legend out for what the chart shows. texts: one per key, nil hides that key.
local function DrawLegend(chart, texts)
	local x = 0
	for i, key in ipairs(chart.keys) do
		local text = texts[i]
		key:SetShown(text ~= nil)
		if text then
			key.swatch:SetColorTexture(UI.RGBA(key.role, 0.9))
			key.text:SetText(text)
			local w = SWATCH + 4 + key.text:GetStringWidth()
			key:SetWidth(w)
			key:ClearAllPoints()
			key:SetPoint("LEFT", chart.legend, "LEFT", x, 0)
			x = x + w + 14
		end
	end
	chart.legend:SetWidth(math.max(x - 14, 1))
end

local function Slot(chart, i)
	local slot = chart.slots[i]
	if not slot then
		slot = CreateFrame("Button", nil, chart)
		slot.hl = slot:CreateTexture(nil, "BACKGROUND")
		slot.hl:SetAllPoints()
		slot.hl:SetColorTexture(UI.Color("hover"))
		slot.hl:Hide()
		slot.gold = slot:CreateTexture(nil, "ARTWORK")
		slot.value = slot:CreateTexture(nil, "ARTWORK")
		slot.levels = slot:CreateTexture(nil, "ARTWORK")
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

-- Oldest on the left. Gold and loot worth share a scale, from a zero line that sits higher when there are losses;
-- levels have their own scale (the tallest levels bar reaches the top), so the chart is an overview of both.
local function DrawChart(chart, list)
	local n = math.min(#list, CHART_BARS)
	local width, height = chart:GetWidth(), CHART_H - 26
	local high, low, highLevels = 0, 0, 0
	local numbers = {}
	for i = 1, n do
		local h = list[n - i + 1]
		local main, value, levels = Main(ns.Recap_HistoryNumbers(h))
		numbers[i] = { h = h, main = main, value = value, levels = levels }
		high = math.max(high, main, value or 0)
		low = math.min(low, main)
		highLevels = math.max(highLevels, levels or 0)
	end
	local span = math.max(high - low, 1)
	local zeroY = 6 + (-low / span) * height
	local levelsRoom = 6 + height - zeroY -- above the zero line
	chart.zero:ClearAllPoints()
	chart.zero:SetPoint("BOTTOMLEFT", 0, zeroY)
	chart.zero:SetPoint("BOTTOMRIGHT", 0, zeroY)
	local anyValue, anyLoss = false, false
	for _, num in ipairs(numbers) do
		anyValue = anyValue or num.value ~= nil
		anyLoss = anyLoss or num.main < 0
	end
	DrawLegend(chart, { "Gold", anyValue and "Loot worth" or nil, highLevels > 0 and "Levels" or nil,
		anyLoss and "Loss" or nil })
	chart.legend:SetShown(n > 0)
	local net = db.mainNumber == "net"
	chart.label:SetText(net and "Per session" or "Per hour")
	local top = n > 0 and ns.Gold(high) or ""
	if highLevels > 0 then
		top = ("%s · %.2f levels"):format(top, highLevels)
	end
	chart.max:SetText(top)
	local slotW = n > 0 and math.min(width / n, 48) or 0
	for i, num in ipairs(numbers) do
		local slot = Slot(chart, i)
		slot.h = num.h
		slot:ClearAllPoints()
		slot:SetPoint("BOTTOMLEFT", (i - 1) * slotW, 0)
		slot:SetSize(slotW, CHART_H - 20)
		local hasValue, hasLevels = num.value ~= nil, num.levels ~= nil
		local bars = 1 + (hasValue and 1 or 0) + (hasLevels and 1 or 0)
		local barW = math.max(math.floor((slotW * 0.7 - (bars - 1) * 2) / bars), 2)
		local x = math.floor(slotW * 0.15)
		local gh = math.max(math.abs(num.main) / span * height, 1)
		slot.gold:ClearAllPoints()
		if num.main >= 0 then
			slot.gold:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", x, zeroY)
			slot.gold:SetColorTexture(UI.RGBA(MONEY_BAR, 0.9))
		else
			slot.gold:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", x, zeroY - gh)
			slot.gold:SetColorTexture(UI.RGBA(LOSS, 0.85))
		end
		slot.gold:SetSize(barW, gh)
		x = x + barW + 2
		slot.value:SetShown(hasValue)
		if hasValue then
			local vh = math.max(num.value / span * height, 1)
			slot.value:ClearAllPoints()
			slot.value:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", x, zeroY)
			slot.value:SetSize(barW, vh)
			slot.value:SetColorTexture(UI.RGBA(VALUE, 0.75))
			x = x + barW + 2
		end
		slot.levels:SetShown(hasLevels)
		if hasLevels then
			slot.levels:ClearAllPoints()
			slot.levels:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", x, zeroY)
			slot.levels:SetSize(barW, math.max(num.levels / highLevels * levelsRoom, 1))
			slot.levels:SetColorTexture(UI.RGBA(LEVELS, 0.8))
		end
		slot:Show()
	end
	for i = n + 1, #chart.slots do
		chart.slots[i]:Hide()
	end
	chart.none = chart.none or UI.Text(chart, 13, "textMuted")
	chart.none:SetPoint("CENTER")
	-- "2 minutes" is History.lua's MIN_SECONDS.
	chart.none:SetText("No sessions here yet. A session is kept when you log in again after it (2 minutes or longer).")
	chart.none:SetShown(n == 0)
end

-- List -----------------------------------------------------------------------------------------------------------

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bg:Hide()
	-- A play night's first row: a faint band and a rule above it, so each night reads as one block.
	row.band = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.band:SetAllPoints()
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetHeight(1)
	row.rule:SetPoint("TOPLEFT")
	row.rule:SetPoint("TOPRIGHT")
	row.cells = {}
	for i, col in ipairs(COLUMNS) do
		local fs
		if col.right or col.key == "time" then
			fs = row:CreateFontString(nil, "OVERLAY")
			UI.SetFont(fs, "number", 14)
			fs:SetShadowOffset(1, -1)
		else
			fs = UI.Text(row, 12, "text")
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

-- banded: the row starts a play night (its band and rule show).
local function Band(row, banded)
	row.band:SetShown(banded)
	row.rule:SetShown(banded)
	if banded then
		row.band:SetColorTexture(UI.RGBA("surface", 0.6))
		row.rule:SetColorTexture(UI.RGBA("rule"))
	end
end

-- A session's row. Plain text colors: the color is kept for the night totals, losses and loot worth. banded: it's a
-- night of its own (no header above it), so it carries the band and its full date.
local function FillSession(row, h, width, indent, banded)
	row.h = h
	row:SetHeight(banded and NIGHT_H or ROW_H)
	Band(row, banded)
	PlaceCells(row, width, indent)
	local n = ns.Recap_HistoryNumbers(h)
	local c = row.cells
	if h.live then
		c[1]:SetText(("Now, since %s"):format(date("%H:%M", h.start)))
		SetColor(c[1], "heading")
	else
		c[1]:SetText(date(indent > 0 and "%H:%M" or "%a %d %b  %H:%M", h.start))
		SetColor(c[1], banded and "heading" or "textMuted")
	end
	c[2]:SetText(h.name or "?")
	SetColor(c[2], ClassColor(h.class))
	c[3]:SetText(ns.Recap_Duration(n.duration))
	SetColor(c[3], "text")
	c[4]:SetText(h.zone or "")
	SetColor(c[4], "textMuted")
	c[5]:SetText(Signed(n.net))
	SetColor(c[5], n.net < 0 and LOSS or "text")
	c[6]:SetText(Signed(n.perHour))
	SetColor(c[6], n.perHour < 0 and LOSS or "text")
	c[7]:SetText(n.value and ns.Gold(n.value) or "")
	SetColor(c[7], VALUE)
	c[8]:SetText(LevelsText(n.levels))
	SetColor(c[8], "text")
end

-- A night of several sessions: its date, when it ran and how many sessions, then its totals.
local function FillNight(row, night, width)
	row.h = nil
	row:SetHeight(NIGHT_H)
	Band(row, true)
	PlaceCells(row, width, 0)
	local t = ns.Recap_HistoryTotals(night.sessions)
	local c = row.cells
	c[1]:SetText(date("%a %d %b", night.first))
	SetColor(c[1], "heading")
	c[2]:SetText(("%s-%s"):format(date("%H:%M", night.first), date("%H:%M", night.last)))
	SetColor(c[2], "textMuted")
	c[3]:SetText(ns.Recap_Duration(t.duration))
	SetColor(c[3], "heading")
	c[4]:SetText(("%d sessions"):format(#night.sessions))
	SetColor(c[4], "textMuted")
	c[5]:SetText(Signed(t.net))
	SetColor(c[5], t.net < 0 and LOSS or MONEY)
	c[6]:SetText(Signed(t.perHour))
	SetColor(c[6], t.perHour < 0 and LOSS or MONEY)
	c[7]:SetText(t.value > 0 and ns.Gold(t.value) or "")
	SetColor(c[7], VALUE)
	c[8]:SetText(LevelsText(t.levels > 0 and t.levels or nil))
	SetColor(c[8], "heading")
end

local function Toggle(parent, width, get, texts, set)
	local b = UI.Button(parent, width, "")
	b:SetHeight(22)
	function b:Update()
		self.label:SetText(texts[get()])
	end
	b:SetScript("OnClick", function(self)
		UI.Sound("pick")
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
	page.totals:SetText(("%d session%s · %s · net %s · %s/h%s%s"):format(t.count, t.count == 1 and "" or "s",
		ns.Recap_Duration(t.duration), Signed(t.net), Signed(t.perHour),
		t.value > 0 and (" · loot worth " .. ns.Gold(t.value)) or "",
		t.levels > 0 and (" · " .. LevelsText(t.levels) .. " levels") or ""))
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
		for i, night in ipairs(ns.Recap_HistoryNights(list, NIGHT_GAP)) do
			if i > 1 then
				y = y + NIGHT_SPACE
			end
			if #night.sessions == 1 then
				FillSession(Next(), night.sessions[1], width, 0, true) -- a header would only repeat it
				y = y + NIGHT_H
			else
				FillNight(Next(), night, width)
				y = y + NIGHT_H
				for _, h in ipairs(night.sessions) do
					FillSession(Next(), h, width, 16, false)
					y = y + ROW_H
				end
			end
		end
	else
		for _, h in ipairs(list) do
			FillSession(Next(), h, width, 0, false)
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
		frame.totals = UI.Text(frame, 12, "textMuted")
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
			local fs = UI.Text(head, 11, "textMuted")
			fs:SetText(HEADS[col.key])
			frame.heads[i] = fs
		end
		local line = head:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(UI.RGBA("frame", 0.35))
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
		-- The session going on now keeps counting while the page is open.
		local ticker
		local function Start()
			if not ticker then
				ticker = C_Timer.NewTicker(LIVE_EVERY, function()
					if frame:IsVisible() then
						Refresh()
					end
				end)
			end
		end
		frame:HookScript("OnShow", Start)
		if frame:IsShown() then
			Start()
		end
		frame:HookScript("OnHide", function()
			if ticker then
				ticker:Cancel()
				ticker = nil
			end
		end)
	end,
	Refresh = function()
		Refresh()
	end,
}
