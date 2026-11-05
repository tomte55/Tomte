local addonName, ns = ...

-- Gathering page of the Tomte window: three views behind buttons. Runs (the live run first, then past runs with
-- totals; click one for its detail), Items (totals per item over the filtered runs, ranks side by side) and Zones
-- (per zone and kind: runs, nodes and gold per hour). Filters: character, week, kind.

local UI = ns.UI
local VIEWS = {
	{ key = "runs", text = "Runs" },
	{ key = "items", text = "Items" },
	{ key = "zones", text = "Zones" },
}
local KINDS = { "all", "mining", "herbalism", "skinning", "fishing" }
local ROW_H = 20
local TOP = 30 -- below the view buttons
local FILTER_H = 28
local MAX_ROWS = 300

-- Runs view columns: { header, x, width, justify }
local RUN_COLS = {
	{ "When", 0, 104 }, { "Character", 106, 90 }, { "Kind", 198, 72 }, { "Time", 272, 52, "RIGHT" },
	{ "Nodes", 326, 46, "RIGHT" }, { "Nodes/h", 374, 52, "RIGHT" }, { "Value", 430, 78, "RIGHT" },
	{ "Gold/h", 510, 78, "RIGHT" }, { "Zone", 598, 160 },
}
local ITEM_COLS = { { "Item", 0, 230 }, { "Ranks", 232, 250 }, { "Count", 484, 50, "RIGHT" }, { "Value", 536, 90, "RIGHT" } }
local ZONE_COLS = {
	{ "Zone", 0, 200 }, { "Kind", 202, 80 }, { "Runs", 284, 44, "RIGHT" }, { "Nodes", 330, 54, "RIGHT" },
	{ "Time", 386, 60, "RIGHT" }, { "Nodes/h", 448, 60, "RIGHT" }, { "Gold/h", 510, 90, "RIGHT" },
}

local db
local page
local rows, used = {}, 0
local detail -- the run whose detail is open

function ns.GatherPage_Init(saved)
	db = saved
end

local function MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or (mapID and ("map " .. mapID) or "?")
end

local function ClassName(name, class)
	return UI.ClassColored(name or "?", class)
end

-- Money, or a faint dash for nil (no price).
local function Money(v)
	return v and ns.Gather_Money(v) or UI.Wrap("-", "textFaint")
end

-- Rows ----------------------------------------------------------------------------------------------------------

local function NewRow()
	local row = CreateFrame("Button", nil, page.scroll.content)
	row:SetHeight(ROW_H)
	row.hl = row:CreateTexture(nil, "BACKGROUND")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(UI.RGBA("hover"))
	row.hl:Hide()
	row.cols = {}
	row.full = UI.Text(row, 12, "text")
	row.full:SetPoint("LEFT", 6, 0)
	row.full:SetPoint("RIGHT", -6, 0)
	row.full:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		if self.onClick then
			self.hl:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hl:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if self.onClick then
			UI.Sound("pick")
			self.onClick()
		end
	end)
	return row
end

local function Col(row, i)
	local fs = row.cols[i]
	if not fs then
		fs = UI.Text(row, 12, "text")
		fs:SetWordWrap(false)
		row.cols[i] = fs
	end
	return fs
end

local function Row(y)
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, -y)
	row:SetPoint("RIGHT")
	row.onClick = nil
	row.hl:Hide()
	row.full:Hide()
	for _, fs in ipairs(row.cols) do
		fs:Hide()
	end
	row:Show()
	return row
end

-- A table row: texts per column; role for all of them (default "text").
local function TableRow(y, cols, texts, role, font)
	local row = Row(y)
	for i, c in ipairs(cols) do
		local fs = Col(row, i)
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 6 + c[2], 0)
		fs:SetWidth(c[3])
		fs:SetJustifyH(c[4] or "LEFT")
		UI.SetFont(fs, (c[4] == "RIGHT" and font ~= "label") and "number" or (font or "body"), font == "label" and 11 or 12)
		UI.SetTextRole(fs, role or "text")
		fs:SetText(texts[i] or "")
		fs:Show()
	end
	return row
end

local function Header(y, cols)
	local texts = {}
	for i, c in ipairs(cols) do
		texts[i] = c[1]
	end
	TableRow(y, cols, texts, "textMuted", "label")
	return y + ROW_H
end

local function TextRow(y, text, role)
	local row = Row(y)
	row.full:SetText(text)
	UI.SetTextRole(row.full, role or "text")
	row.full:Show()
	return row
end

-- Filters --------------------------------------------------------------------------------------------------------

local function FilterText()
	return {
		scope = db.pageScope == "char" and "This character" or "All characters",
		range = db.pageRange == "week" and "This week" or "All time",
		kind = db.pageKind == "all" and "All kinds" or (ns.GATHER_KIND_NAMES[db.pageKind] or "All kinds"),
	}
end

-- The live run (when it matches the filters) and the kept runs.
local function Filtered()
	local since = db.pageRange == "week" and ns.WeekStart() or nil
	local list = {}
	local live = ns.Gather_Current()
	if live then
		for _, r in ipairs(ns.Gather_Filter({ live }, db.pageScope, UnitGUID("player"), since, db.pageKind)) do
			list[#list + 1] = r
		end
	end
	for _, r in ipairs(ns.Gather_Filter(db.runs, db.pageScope, UnitGUID("player"), since, db.pageKind)) do
		list[#list + 1] = r
	end
	return list, live
end

local function MainZone(run)
	local best, most = nil, -1
	for mapID, z in pairs(run.zones or {}) do
		if z.nodes > most then
			best, most = mapID, z.nodes
		end
	end
	return best
end

-- Views ----------------------------------------------------------------------------------------------------------

local function RunsView(y)
	local list, live = Filtered()
	local now = GetServerTime()
	local t = ns.Gather_Totals(list, now, nil, live)
	page.total:SetText(("%s %s · %s · %s nodes (%s/h) · %s%s"):format(ns.Thousands(t.count),
		t.count == 1 and "run" or "runs", ns.Gather_DurationText(t.duration), ns.Thousands(t.nodes),
		ns.Thousands(t.nodesPerHour), t.value and ns.Gather_Money(t.value) or "no prices",
		t.valuePerHour and (" (" .. ns.Gather_Money(t.valuePerHour) .. "/h)") or ""))
	if #list == 0 then
		TextRow(y, "No runs here yet. Gather a few nodes, or start one with /tomte gather start.", "textMuted")
		return y + ROW_H
	end
	y = Header(y, RUN_COLS)
	for i = 1, math.min(#list, MAX_ROWS) do
		local r = list[i]
		local n = ns.Gather_Numbers(r, now, r == live)
		local zone = MainZone(r)
		local row = TableRow(y, RUN_COLS, {
			r == live and UI.Wrap("now", "accent") or date("%a %d %b %H:%M", r.start),
			ClassName(r.name, r.class),
			ns.GATHER_KIND_NAMES[n.mainKind] or "-", -- "Mixed": the column is too narrow for the kinds' names
			ns.Gather_DurationText(n.duration),
			tostring(n.nodes),
			tostring(n.nodesPerHour),
			Money(n.value),
			Money(n.valuePerHour),
			zone and MapName(zone) or "",
		})
		row.onClick = function()
			detail = r
			ns.GatherPage_Refresh()
		end
		y = y + ROW_H
	end
	return y
end

local function ItemsView(y)
	local list = Filtered()
	local totals = ns.Gather_ItemTotals(list)
	page.total:SetText(("%s %s over %s %s"):format(ns.Thousands(#totals), #totals == 1 and "item" or "items",
		ns.Thousands(#list), #list == 1 and "run" or "runs"))
	if #totals == 0 then
		TextRow(y, "Nothing gathered here yet.", "textMuted")
		return y + ROW_H
	end
	-- One row per item name: the ranks of one reagent are different item IDs.
	local groups, order = {}, {}
	for _, it in ipairs(totals) do
		local name = it.itemID and C_Item.GetItemNameByID(it.itemID) or (it.link and it.link:match("%[(.-)%]")) or tostring(it.key)
		local g = groups[name]
		if not g then
			g = { name = name, first = it, parts = {}, n = 0, v = 0 }
			groups[name] = g
			order[#order + 1] = g
		end
		g.n, g.v = g.n + it.n, g.v + it.v
		local text = ("%s %s"):format(ns.Gather_RankMarkup(it.itemID, it.rank, 14), ns.Thousands(it.n))
		g.parts[#g.parts + 1] = { rank = it.rank or 0, text = text }
	end
	y = Header(y, ITEM_COLS)
	for i = 1, math.min(#order, MAX_ROWS) do
		local g = order[i]
		table.sort(g.parts, function(a, b)
			return a.rank < b.rank
		end)
		local ranks = {}
		for _, p in ipairs(g.parts) do
			ranks[#ranks + 1] = p.text
		end
		local ranked = #g.parts > 1 or g.parts[1].rank > 0
		TableRow(y, ITEM_COLS, {
			ns.Gather_ItemIcon(g.first.itemID, 14) .. ns.Gather_ItemName(g.first.itemID, g.first.link),
			ranked and table.concat(ranks, " · ") or "",
			tostring(g.n),
			Money(g.v > 0 and g.v or nil),
		})
		y = y + ROW_H
	end
	return y
end

local function ZonesView(y)
	local list, live = Filtered()
	local stats = ns.Gather_ZoneStats(list, GetServerTime(), live)
	page.total:SetText(("%d %s"):format(#stats, #stats == 1 and "zone" or "zones"))
	if #stats == 0 then
		TextRow(y, "No zones yet.", "textMuted")
		return y + ROW_H
	end
	y = Header(y, ZONE_COLS)
	for i = 1, math.min(#stats, MAX_ROWS) do
		local z = stats[i]
		TableRow(y, ZONE_COLS, {
			MapName(z.mapID), ns.GATHER_KIND_NAMES[z.kind] or z.kind, tostring(z.runs), tostring(z.nodes),
			ns.Gather_DurationText(z.seconds), tostring(z.nodesPerHour), Money(z.valuePerHour),
		})
		y = y + ROW_H
	end
	return y
end

local function DetailView(y)
	local r = detail
	local live = r == ns.Gather_Current()
	local n = ns.Gather_Numbers(r, GetServerTime(), live)
	page.total:SetText(("%s, %s, %s"):format(ns.Gather_RunTitle(n.mainKind, n.kinds), ClassName(r.name, r.class),
		live and "going on now" or date("%a %d %b %H:%M", r.start)))
	local back = TextRow(y, "< Back to the runs", "accent")
	back.onClick = function()
		detail = nil
		ns.GatherPage_Refresh()
	end
	y = y + ROW_H + 4
	TextRow(y, ("%s · %s nodes (%s gathers) · %s/h · %s%s"):format(ns.Gather_DurationText(n.duration),
		ns.Thousands(n.nodes), ns.Thousands(n.gathers), ns.Thousands(n.nodesPerHour), n.value and ns.Gather_Money(n.value) or "no prices",
		n.valuePerHour and (" (" .. ns.Gather_Money(n.valuePerHour) .. "/h)") or ""))
	y = y + ROW_H + 6

	TextRow(y, "Items", "heading")
	y = y + ROW_H
	local items = ns.Gather_ItemTotals({ r })
	for _, it in ipairs(items) do
		TextRow(y, ("%s%s %s  %s   %s"):format(ns.Gather_ItemIcon(it.itemID, 14), ns.Gather_ItemName(it.itemID, it.link),
			ns.Gather_RankMarkup(it.itemID, it.rank, 14), UI.Wrap("x" .. it.n, "textMuted"),
			it.v > 0 and ns.Gather_Money(it.v) or ""))
		y = y + ROW_H
	end
	if #items == 0 then
		TextRow(y, "none", "textMuted")
		y = y + ROW_H
	end

	if #(r.finds or {}) > 0 then
		y = y + 6
		TextRow(y, "Finds", "heading")
		y = y + ROW_H
		for _, f in ipairs(r.finds) do
			TextRow(y, f.kind == "item" and (ns.Gather_ItemIcon(f.itemID, 14) .. ns.Gather_ItemName(f.itemID, f.link))
				or "Weekly knowledge drop", "accent")
			y = y + ROW_H
		end
	end

	local progress = ns.Gather_ProgressText(r)
	if progress then
		y = y + 6
		TextRow(y, "Skill and knowledge", "heading")
		y = y + ROW_H
		TextRow(y, progress)
		y = y + ROW_H
	end

	y = y + 6
	TextRow(y, "Zones", "heading")
	y = y + ROW_H
	for mapID, z in pairs(r.zones or {}) do
		TextRow(y, ("%s: %s %s%s"):format(MapName(mapID), ns.Thousands(z.nodes), z.nodes == 1 and "node" or "nodes",
			z.v > 0 and (" · " .. ns.Gather_Money(z.v)) or ""))
		y = y + ROW_H
	end

	local types = {}
	for objectID, t in pairs(r.nodeTypes or {}) do
		types[#types + 1] = { name = t.name or ("Node " .. objectID), n = t.n }
	end
	if #types > 0 then
		table.sort(types, function(a, b)
			return a.n > b.n
		end)
		y = y + 6
		TextRow(y, "Nodes", "heading")
		y = y + ROW_H
		for _, t in ipairs(types) do
			TextRow(y, ("%s: %s"):format(t.name, ns.Thousands(t.n)))
			y = y + ROW_H
		end
	end
	return y
end

-- Page ---------------------------------------------------------------------------------------------------------

local MAKERS = { runs = RunsView, items = ItemsView, zones = ZonesView }

local function Layout()
	local view = db.pageView
	if not MAKERS[view] then
		view = "runs"
		db.pageView = view
	end
	for _, b in ipairs(page.buttons) do
		UI.SetTextRole(b.label, b.key == view and "heading" or "textMuted")
		b.selected:SetShown(b.key == view)
	end
	local f = FilterText()
	page.scope.label:SetText(f.scope)
	page.range.label:SetText(f.range)
	page.kind.label:SetText(f.kind)
	for i = 1, used do
		rows[i]:Hide()
	end
	used = 0
	local y
	if detail and view == "runs" then
		y = DetailView(0)
	else
		detail = nil
		y = MAKERS[view](0)
	end
	page.scroll:SetContentHeight(y + 8)
end

function ns.GatherPage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

local function Cycle(value, list)
	for i, v in ipairs(list) do
		if v == value then
			return list[i % #list + 1]
		end
	end
	return list[1]
end

local function FilterButton(width, onClick)
	local b = UI.Button(page, width, "")
	b:SetScript("OnClick", function()
		UI.Sound("pick")
		onClick()
		detail = nil
		Layout()
	end)
	return b
end

ns.GatherPage = {
	title = "Gathering",
	Create = function(frame)
		page = frame
		page.buttons = {}
		local prev
		for _, view in ipairs(VIEWS) do
			local b = UI.Button(page, 80, view.text)
			UI.FitButton(b, 56, 22, true)
			b.key = view.key
			b.selected = b:CreateTexture(nil, "ARTWORK")
			b.selected:SetColorTexture(UI.RGBA("accent", 0.9))
			b.selected:SetHeight(2)
			b.selected:SetPoint("BOTTOMLEFT", 4, 2)
			b.selected:SetPoint("BOTTOMRIGHT", -4, 2)
			b:SetScript("OnClick", function()
				db.pageView = view.key
				detail = nil
				Layout()
			end)
			if prev then
				b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
			else
				b:SetPoint("TOPLEFT", 8, 0)
			end
			prev = b
			page.buttons[#page.buttons + 1] = b
		end
		page.kind = FilterButton(96, function()
			db.pageKind = Cycle(db.pageKind, KINDS)
		end)
		page.kind:SetPoint("TOPRIGHT", -8, 0)
		page.range = FilterButton(86, function()
			db.pageRange = db.pageRange == "week" and "all" or "week"
		end)
		page.range:SetPoint("RIGHT", page.kind, "LEFT", -8, 0)
		page.scope = FilterButton(116, function()
			db.pageScope = db.pageScope == "char" and "all" or "char"
		end)
		page.scope:SetPoint("RIGHT", page.range, "LEFT", -8, 0)

		page.total = UI.Text(page, 12, "textMuted")
		page.total:SetPoint("TOPLEFT", 8, -TOP)
		page.total:SetPoint("RIGHT", -8, 0)
		page.total:SetWordWrap(false)

		page.scroll = UI.Scroll(page)
		page.scroll:SetPoint("TOPLEFT", 8, -(TOP + FILTER_H - 6))
		page.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	end,
	Refresh = function()
		Layout()
	end,
}
