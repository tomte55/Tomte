local addonName, ns = ...

-- Bags: the list on the Bag categories page (EditPage.lua), in a tray (Kit.lua): sections with a hairline after their
-- name, their categories indented, dividers, each category with a pill of how many of your items it holds now, the
-- automatic ones quieter, the picked one marked. Rows drag: a ghost follows the cursor, a drop line shows where it
-- lands (before or after a row, or into a section), the list scrolls near its edges, and the page moves the node
-- (EditData.lua's BagsEdit_MoveTo).

local ROW_H = 22
local INDENT = 16
local GRIP_W = 14 -- the drag grip's room at a row's left
local EDGE_SCROLL = 18 -- pixels from the list's top or bottom where a drag scrolls it
local SCROLL_STEP = 6 -- pixels per frame while it does
local INTO = 1 / 3 -- on a section row, the right two thirds drop into it
local PICKED_WASH = 0.12

local UI = ns.UI

-- Drag ---------------------------------------------------------------------------------------------------------------

local function CursorY(frame)
	local _, y = GetCursorPosition()
	return y / frame:GetEffectiveScale()
end

local function CursorX(frame)
	local x = GetCursorPosition()
	return x / frame:GetEffectiveScale()
end

-- Where a drop would land: the row under the cursor and "before" | "after" | "into", or nil.
local function DropTarget(list)
	if not list.scroll:IsMouseOver() then
		return nil -- rows scrolled out of view still answer IsMouseOver
	end
	for _, row in ipairs(list.rows) do
		if row:IsShown() and row.key and row:IsMouseOver() and row.key ~= list.dragKey then
			local top, bottom = row:GetTop(), row:GetBottom()
			local y = CursorY(row)
			if row.kind == "section" and list.dragKind == "category"
				and CursorX(row) > row:GetLeft() + row:GetWidth() * INTO then
				return row, "into"
			end
			return row, (y > (top + bottom) / 2) and "before" or "after"
		end
	end
	return nil
end

local function DragUpdate(list)
	local scroll = list.scroll
	local y = CursorY(scroll)
	if y > scroll:GetTop() - EDGE_SCROLL then
		scroll:SetScroll(scroll:GetVerticalScroll() - SCROLL_STEP)
	elseif y < scroll:GetBottom() + EDGE_SCROLL then
		scroll:SetScroll(scroll:GetVerticalScroll() + SCROLL_STEP)
	end
	local ghost = list.ghost
	ghost:ClearAllPoints()
	ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", CursorX(UIParent) + 12, CursorY(UIParent))
	local row, where = DropTarget(list)
	list.dropRow, list.dropWhere = row, where
	local line = list.dropLine
	line:ClearAllPoints()
	list.intoWash:Hide()
	line:Hide()
	if row and where == "into" then
		list.intoWash:ClearAllPoints()
		list.intoWash:SetAllPoints(row)
		list.intoWash:Show()
	elseif row then
		line:SetPoint(where == "before" and "BOTTOMLEFT" or "TOPLEFT", row, where == "before" and "TOPLEFT" or "BOTTOMLEFT",
			row.indent or 0, -1)
		line:SetPoint(where == "before" and "BOTTOMRIGHT" or "TOPRIGHT", row, where == "before" and "TOPRIGHT" or "BOTTOMRIGHT",
			0, -1)
		line:Show()
	end
end

local function StartDrag(list, row)
	list.dragKey, list.dragKind = row.key, row.kind
	list.ghost.text:SetText(row.name:GetText())
	list.ghost:SetWidth(math.max(row.name:GetStringWidth() + 24, 80))
	list.ghost:Show()
	row:SetAlpha(0.4)
	list.dragRow = row
	list:SetScript("OnUpdate", DragUpdate)
end

-- cancel: the list hid mid-drag (the window closed): clean up without moving anything.
local function StopDrag(list, cancel)
	list:SetScript("OnUpdate", nil)
	list.ghost:Hide()
	list.dropLine:Hide()
	list.intoWash:Hide()
	if list.dragRow then
		list.dragRow:SetAlpha(1)
	end
	local key, row, where = list.dragKey, list.dropRow, list.dropWhere
	list.dragKey, list.dragKind, list.dragRow, list.dropRow, list.dropWhere = nil, nil, nil, nil, nil
	if key and row and where and not cancel then
		list.onMove(key, row.key, where)
	end
end

-- Rows ---------------------------------------------------------------------------------------------------------------

local function Grip(row)
	local grip = {}
	for i = 1, 2 do
		local bar = row:CreateTexture(nil, "ARTWORK")
		bar:SetSize(7, 1)
		bar:SetColorTexture(UI.Color("textFaint"))
		bar:SetPoint("LEFT", row, "LEFT", 5, i == 1 and 2 or -1)
		grip[i] = bar
	end
	return grip
end

local function Row(list, i)
	local rows = list.rows
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, list.scroll.content)
	row:SetHeight(ROW_H)
	row:RegisterForDrag("LeftButton")
	UI.HoverWash(row)
	row.picked = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.picked:SetAllPoints()
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(2)
	row.grip = Grip(row)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.pill = CreateFrame("Frame", nil, row)
	row.pill:SetHeight(14)
	row.pill:SetPoint("RIGHT", -6, 0)
	local pillFill = row.pill:CreateTexture(nil, "BACKGROUND")
	pillFill:SetAllPoints()
	pillFill:SetColorTexture(1, 1, 1, 0.06)
	row.pill.text = UI.Text(row.pill, 11, "textMuted", "number")
	row.pill.text:SetPoint("CENTER")
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetColorTexture(UI.Color("rule"))
	PixelUtil.SetHeight(row.rule, 1, 1)
	row:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
	end)
	row:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
	end)
	row:SetScript("OnClick", function(self)
		list.onPick(self.key)
	end)
	row:SetScript("OnDragStart", function(self)
		StartDrag(list, self)
	end)
	row:SetScript("OnDragStop", function()
		StopDrag(list)
	end)
	rows[i] = row
	return row
end

-- The list (a tray holding a UI.Scroll) in page. onPick(key) runs when a row is clicked; onMove(key, targetKey, where)
-- when one is dropped.
function ns.BagsEditList_Create(page, onPick, onMove)
	local list = ns.BagsKit_Tray(page)
	list.rows, list.onPick, list.onMove = {}, onPick, onMove
	list.scroll = UI.Scroll(list)
	list.scroll:SetPoint("TOPLEFT", 4, -4)
	list.scroll:SetPoint("BOTTOMRIGHT", -12, 4)
	list.ghost = CreateFrame("Frame", nil, UIParent)
	list.ghost:SetFrameStrata("TOOLTIP")
	list.ghost:SetHeight(ROW_H)
	UI.Panel(list.ghost, { subtle = true })
	list.ghost.text = UI.Text(list.ghost, 12, "text")
	list.ghost.text:SetPoint("LEFT", 10, 0)
	list.ghost:Hide()
	list.dropLine = list.scroll.content:CreateTexture(nil, "OVERLAY")
	list.dropLine:SetColorTexture(UI.Color("accent"))
	list.dropLine:SetHeight(2)
	list.dropLine:Hide()
	list.intoWash = list.scroll.content:CreateTexture(nil, "OVERLAY")
	list.intoWash:SetColorTexture(UI.RGBA("accent", 0.2))
	list.intoWash:Hide()
	list:HookScript("OnHide", function(self)
		if self.dragKey then
			StopDrag(self, true)
		end
	end)
	return list
end

function ns.BagsEditList_Draw(list, layout, byKey, selected)
	local n, y = 0, 0
	local width = list.scroll:GetWidth()
	local function Add(node, depth)
		n = n + 1
		local row = Row(list, n)
		row.key, row.kind = node.key, node.kind
		row.indent = depth * INDENT
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list.scroll.content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", GRIP_W + 4 + row.indent, 0)
		for _, bar in ipairs(row.grip) do
			bar:SetPoint("LEFT", row, "LEFT", 5 + row.indent, bar == row.grip[1] and 2 or -1)
		end
		row.rule:Hide()
		row.pill:Hide()
		if node.kind == "section" then
			UI.SetFont(row.name, "title", 13)
			UI.SetTextRole(row.name, "heading")
			row.name:SetText(node.name)
			row.rule:ClearAllPoints()
			row.rule:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
			row.rule:SetPoint("RIGHT", -8, 0)
			row.rule:Show()
		elseif node.kind == "divider" then
			row.name:SetText("")
			row.rule:ClearAllPoints()
			row.rule:SetPoint("LEFT", GRIP_W + 4 + row.indent, 0)
			row.rule:SetPoint("RIGHT", -8, 0)
			row.rule:Show()
		else
			UI.SetFont(row.name, "body", 12)
			UI.SetTextRole(row.name, (node.hidden or node.auto) and "textMuted" or "text")
			row.name:SetText(node.name .. (node.hidden and " (hidden)" or ""))
			local items = byKey and byKey[node.key]
			if items and #items > 0 then
				row.pill.text:SetText(#items)
				row.pill:SetWidth(math.max(row.pill.text:GetStringWidth() + 12, 20))
				row.pill:Show()
				row.name:SetPoint("RIGHT", row.pill, "LEFT", -6, 0)
			else
				row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			end
		end
		local picked = node.key == selected
		row.mark:SetColorTexture(UI.Color("accent"))
		row.mark:SetShown(picked)
		row.picked:SetColorTexture(UI.RGBA("accent", picked and PICKED_WASH or 0))
		row:Show()
		y = y + ROW_H
		if node.kind == "section" then
			for _, child in ipairs(node.children or {}) do
				Add(child, depth + 1)
			end
		end
	end
	for _, node in ipairs(layout) do
		Add(node, 0)
	end
	for i = n + 1, #list.rows do
		list.rows[i]:Hide()
	end
	list.scroll:SetContentHeight(y)
end
