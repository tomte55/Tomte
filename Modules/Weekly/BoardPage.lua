local addonName, ns = ...

-- Weekly tab of the panel: three views behind buttons at the top. This week (the current character), Characters
-- (a grid, one column per character) and Professions (knowledge and Concentration per character). The rows come
-- from Data.lua's models; ns.WeeklyList draws a list of them and is shared with the popup.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.45, 0.85, 0.45 }
local ORANGE = { 1, 0.6, 0.2 }
local STATE_COLORS = { done = GREEN, open = WHITE, warn = ORANGE, dim = DIM }
local ROW_H, HEADER_H, BANNER_H = 20, 28, 30
local LABEL_W, CELL_MIN, CELL_MAX, GRID_HEAD_H = 210, 56, 96, 34

local function SetColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3])
end

local function ClassColor(class)
	local color = class and C_ClassColor.GetClassColor(class)
	return color and { color.r, color.g, color.b } or WHITE
end

-- A list of model rows in a UI.Scroll: ns.WeeklyList(parent) -> list; list:Render(items); list.scroll to anchor.
function ns.WeeklyList(parent)
	local list = { rows = {}, used = 0 }
	list.scroll = UI.Scroll(parent)
	local content = list.scroll.content

	local function NewRow()
		local row = CreateFrame("Frame", nil, content)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.left = UI.Text(row, 12, WHITE)
		row.left:SetWordWrap(false)
		row.right = UI.Text(row, 12, WHITE)
		row.right:SetJustifyH("RIGHT")
		row.right:SetWordWrap(false)
		row.right:SetPoint("RIGHT", -8, 0)
		row.left:SetPoint("RIGHT", row.right, "LEFT", -12, 0)
		row.line = row:CreateTexture(nil, "ARTWORK")
		row.line:SetHeight(1)
		row.line:SetPoint("BOTTOMLEFT", 8, 2)
		row.line:SetPoint("BOTTOMRIGHT", -8, 2)
		row.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
		row.bar = CreateFrame("StatusBar", nil, row)
		row.bar:SetHeight(2)
		row.bar:SetPoint("BOTTOMLEFT", 8, 0)
		row.bar:SetPoint("BOTTOMRIGHT", -8, 0)
		row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
		row.bar:SetMinMaxValues(0, 1)
		local track = row.bar:CreateTexture(nil, "BACKGROUND")
		track:SetAllPoints()
		track:SetColorTexture(1, 1, 1, 0.08)
		-- Rows with a hint show it on hover; rows with a place set a waypoint on click.
		row.hover = row:CreateTexture(nil, "BACKGROUND")
		row.hover:SetAllPoints()
		row.hover:SetColorTexture(1, 1, 1, 0.05)
		row.hover:Hide()
		row:SetScript("OnEnter", function(self)
			self.hover:Show()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tipTitle or "", 1, 1, 1)
			if self.tip then
				GameTooltip:AddLine(self.tip, nil, nil, nil, true)
			end
			if self.loc then
				GameTooltip:AddLine("Click to set a waypoint", 0.45, 0.85, 0.45)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(self)
			self.hover:Hide()
			GameTooltip:Hide()
		end)
		row:SetScript("OnMouseUp", function(self)
			if self.loc and self:IsMouseOver() then
				ns.Weekly_SetWaypoint(self.loc)
			end
		end)
		return row
	end

	function list:Render(items)
		for i = 1, self.used do
			self.rows[i]:Hide()
		end
		self.used = 0
		local y = 0
		for _, item in ipairs(items) do
			self.used = self.used + 1
			local row = self.rows[self.used] or NewRow()
			self.rows[self.used] = row
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("RIGHT")
			row.left:ClearAllPoints()
			row.left:SetPoint("RIGHT", row.right, "LEFT", -12, 0)
			row.bg:Hide()
			row.line:Hide()
			row.bar:Hide()
			row.hover:Hide()
			row.right:SetText("")
			row.tip, row.loc, row.tipTitle = item.tip, item.loc, item.left
			row:EnableMouse(item.tip ~= nil or item.loc ~= nil)
			if item.kind == "header" then
				row:SetHeight(HEADER_H)
				row.left:SetFont(STANDARD_TEXT_FONT, 14, "")
				row.left:SetPoint("BOTTOMLEFT", 8, 6)
				row.left:SetText(item.text)
				SetColor(row.left, item.class and ClassColor(item.class) or GOLD)
				row.line:Show()
			elseif item.kind == "banner" then
				row:SetHeight(BANNER_H)
				row.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.14)
				row.bg:Show()
				row.left:SetFont(STANDARD_TEXT_FONT, 13, "")
				row.left:SetPoint("LEFT", 10, 0)
				row.left:SetText(item.text)
				SetColor(row.left, GOLD)
			else
				row:SetHeight(ROW_H)
				row.left:SetFont(STANDARD_TEXT_FONT, 12, "")
				row.left:SetPoint("LEFT", item.indent and 26 or 12, 0)
				row.left:SetText(item.left or "")
				local color = STATE_COLORS[item.state] or WHITE
				SetColor(row.left, item.state == "dim" and DIM or (item.indent and GREY or WHITE))
				row.right:SetText(item.right or "")
				SetColor(row.right, color)
				if item.frac then
					row.bar:SetValue(item.frac)
					row.bar:SetStatusBarColor(color[1], color[2], color[3], 0.7)
					row.bar:Show()
				end
			end
			row:Show()
			y = y + row:GetHeight()
		end
		self.scroll:SetContentHeight(y)
		return y
	end

	function list:Clear()
		self:Render({})
	end

	return list
end

local page, list, grid
local VIEWS = { { key = "week", text = "This week" }, { key = "chars", text = "Characters" }, { key = "profs", text = "Professions" } }

-- The grid draws into its own scroll so the list's rows and the grid's cells never mix.
local function NewGrid(parent)
	local g = { cells = {}, used = 0, labels = {}, labelsUsed = 0 }
	g.scroll = UI.Scroll(parent)
	local content = g.scroll.content

	local function Cell()
		g.used = g.used + 1
		local cell = g.cells[g.used]
		if not cell then
			cell = CreateFrame("Frame", nil, content)
			cell.text = UI.Text(cell, 12, WHITE)
			cell.text:SetJustifyH("CENTER")
			cell.text:SetPoint("LEFT")
			cell.text:SetPoint("RIGHT")
			cell.text:SetWordWrap(false)
			cell.sub = UI.Text(cell, 10, ORANGE)
			cell.sub:SetJustifyH("CENTER")
			cell.sub:SetPoint("TOP", cell.text, "BOTTOM", 0, -2)
			cell.bg = cell:CreateTexture(nil, "BACKGROUND")
			cell.bg:SetAllPoints()
			cell:SetScript("OnEnter", function(self)
				if self.tip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.tipTitle or "", 1, 1, 1)
					GameTooltip:AddLine(self.tip, nil, nil, nil, true)
					GameTooltip:Show()
				end
			end)
			cell:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			g.cells[g.used] = cell
		end
		cell.tip, cell.tipTitle = nil, nil
		cell.sub:SetText("")
		cell.bg:Hide()
		cell:EnableMouse(false)
		cell:Show()
		return cell
	end

	function g:Render(model, width)
		for i = 1, self.used do
			self.cells[i]:Hide()
		end
		self.used = 0
		local columns = model.columns
		local cellW = #columns > 0 and math.max(CELL_MIN, math.min(CELL_MAX, (width - LABEL_W) / #columns)) or CELL_MAX
		local y = 0

		-- Character names, the vault mark under them.
		for i, v in ipairs(columns) do
			local cell = Cell()
			cell:SetSize(cellW, GRID_HEAD_H)
			cell:SetPoint("TOPLEFT", LABEL_W + (i - 1) * cellW, 0)
			cell.text:ClearAllPoints()
			cell.text:SetPoint("TOPLEFT", 0, -6)
			cell.text:SetPoint("TOPRIGHT", 0, -6)
			cell.text:SetJustifyH("CENTER")
			cell.text:SetText(v.name or "?")
			SetColor(cell.text, ClassColor(v.class))
			if v.vaultReady then
				cell.sub:SetText("vault waiting")
				SetColor(cell.sub, ORANGE)
			elseif v.stale then
				cell.sub:SetText("reset since")
				SetColor(cell.sub, DIM)
			end
			cell.tipTitle = (v.name or "?") .. (v.realm and (" - " .. v.realm) or "")
			cell.tip = v.at and ("Last updated " .. date("%a %d %b %H:%M", v.at)) or nil
			cell:EnableMouse(true)
		end
		y = GRID_HEAD_H

		for _, row in ipairs(model.rows) do
			local label = Cell()
			label:SetSize(LABEL_W, row.header and HEADER_H or ROW_H)
			label:SetPoint("TOPLEFT", 0, -y)
			label.text:ClearAllPoints()
			if row.header then
				label.text:SetPoint("BOTTOMLEFT", 8, 6)
				label.text:SetJustifyH("LEFT")
				label.text:SetText(row.header)
				SetColor(label.text, GOLD)
				y = y + HEADER_H
			else
				label.text:SetPoint("LEFT", 12, 0)
				label.text:SetPoint("RIGHT", -4, 0)
				label.text:SetJustifyH("LEFT")
				label.text:SetText(row.label)
				SetColor(label.text, GREY)
				for i, c in ipairs(row.cells) do
					local cell = Cell()
					cell:SetSize(cellW, ROW_H)
					cell:SetPoint("TOPLEFT", LABEL_W + (i - 1) * cellW, -y)
					cell.text:ClearAllPoints()
					cell.text:SetPoint("LEFT")
					cell.text:SetPoint("RIGHT")
					cell.text:SetJustifyH("CENTER")
					cell.text:SetText(c.text)
					SetColor(cell.text, STATE_COLORS[c.state] or WHITE)
					if i % 2 == 1 then
						cell.bg:SetColorTexture(1, 1, 1, 0.03)
						cell.bg:Show()
					end
					if c.tip then
						cell.tipTitle, cell.tip = row.label, c.tip
						cell:EnableMouse(true)
					end
				end
				y = y + ROW_H
			end
		end
		self.scroll:SetContentHeight(y)
	end

	return g
end

local function SetView(key)
	ns.weeklyDB.view = key
	ns.WeeklyBoard_Refresh()
end

local function Layout()
	local db = ns.weeklyDB
	local view = db.view
	for _, b in ipairs(page.buttons) do
		SetColor(b.label, b.key == view and GOLD or GREY)
		b.selected:SetShown(b.key == view)
	end
	local now = GetServerTime()
	page.note:Hide()
	list.scroll:SetShown(view ~= "chars")
	grid.scroll:SetShown(view == "chars")
	if view == "week" then
		local v = ns.Weekly_CurrentView()
		if not v then
			list:Clear()
			page.note:SetText("The weekly board tracks max-level characters. Nothing to show for this one yet.")
			page.note:Show()
			return
		end
		local items = ns.Weekly_WeekModel(v, db.quests, now, db.learned)
		if #items == 0 then
			page.note:SetText("No weekly data yet. It fills in a moment after login.")
			page.note:Show()
		end
		list:Render(items)
	elseif view == "profs" then
		local items = ns.Weekly_ProfModel(ns.Weekly_Views(), now)
		if #items == 0 then
			page.note:SetText("No tracked character has a profession yet.")
			page.note:Show()
		end
		list:Render(items)
	else
		local views = ns.Weekly_Views()
		if #views == 0 then
			page.note:SetText("No characters tracked yet.")
			page.note:Show()
		end
		grid:Render(ns.Weekly_GridModel(views, db.quests, now), grid.scroll:GetWidth())
	end
end

function ns.WeeklyBoard_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

ns.WeeklyBoardPage = {
	title = "Weekly",
	Create = function(frame)
		page = frame
		page.buttons = {}
		local prev
		for _, view in ipairs(VIEWS) do
			local b = UI.Button(page, 100, view.text)
			b.key = view.key
			b.selected = b:CreateTexture(nil, "ARTWORK")
			b.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
			b.selected:SetHeight(2)
			b.selected:SetPoint("BOTTOMLEFT", 4, 2)
			b.selected:SetPoint("BOTTOMRIGHT", -4, 2)
			b:SetScript("OnClick", function()
				SetView(view.key)
			end)
			if prev then
				b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
			else
				b:SetPoint("TOPLEFT", 8, 0)
			end
			prev = b
			page.buttons[#page.buttons + 1] = b
		end
		list = ns.WeeklyList(page)
		list.scroll:SetPoint("TOPLEFT", 0, -30)
		list.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
		grid = NewGrid(page)
		grid.scroll:SetPoint("TOPLEFT", 0, -30)
		grid.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
		grid.scroll.onWidthChanged = function()
			ns.WeeklyBoard_Refresh()
		end
		page.note = UI.Text(page, 12, GREY)
		page.note:SetPoint("TOPLEFT", 8, -38)
		page.note:SetPoint("RIGHT", -8, 0)
		page.note:SetWordWrap(true)
		-- The panel only runs Refresh the first time; this also covers reopening the panel on this page.
		page:HookScript("OnShow", function()
			ns.WeeklyCollect_Request()
			Layout()
		end)
	end,
	Refresh = function()
		ns.WeeklyCollect_Request()
		Layout()
	end,
}
