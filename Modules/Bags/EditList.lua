local addonName, ns = ...

-- Bags: the list on the Bag categories page (EditPage.lua): sections, their categories, dividers, each category with
-- how many of your items it holds now, the picked one marked. Picking a row calls the page back.

local ROW_H = 20
local INDENT = 14

local UI = ns.UI

local function Row(list, i)
	local rows = list.rows
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, list.content)
	row:SetHeight(ROW_H)
	UI.HoverWash(row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(2)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.count = UI.Text(row, 11, "textMuted", "number")
	row.count:SetPoint("RIGHT", -6, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
	end)
	row:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
	end)
	row:SetScript("OnClick", function(self)
		list.onPick(self.key)
	end)
	rows[i] = row
	return row
end

-- The list (a UI.Scroll) in page; onPick(key) runs when a row is clicked.
function ns.BagsEditList_Create(page, onPick)
	local list = UI.Scroll(page)
	list.rows, list.onPick = {}, onPick
	return list
end

function ns.BagsEditList_Draw(list, layout, byKey, selected)
	local n, y = 0, 0
	local width = list:GetWidth()
	local function Add(node, depth)
		n = n + 1
		local row = Row(list, n)
		row.key = node.key
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", 8 + depth * INDENT, 0)
		row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		if node.kind == "section" then
			UI.SetFont(row.name, "title", 13)
			UI.SetTextRole(row.name, "heading")
			row.name:SetText(node.name)
			row.count:SetText("")
		elseif node.kind == "divider" then
			UI.SetFont(row.name, "body", 12)
			UI.SetTextRole(row.name, "textFaint")
			row.name:SetText("divider")
			row.count:SetText("")
		else
			UI.SetFont(row.name, "body", 12)
			UI.SetTextRole(row.name, node.hidden and "textFaint" or "text")
			row.name:SetText(node.name .. (node.hidden and " (hidden)" or ""))
			local items = byKey and byKey[node.key]
			row.count:SetText(items and #items > 0 and #items or "")
		end
		local picked = node.key == selected
		row.mark:SetColorTexture(UI.Color("accent"))
		row.mark:SetShown(picked)
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
	list:SetContentHeight(y)
end
