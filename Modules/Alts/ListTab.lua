local addonName, ns = ...

-- Alts page, List tab: the crafting list. Every tracked craft (amount - n +, remove), all their materials added
-- up (with an Auctionator shopping list link for what's missing), and the full to-do: yours first, then what other
-- characters have to do. Data from List.lua.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local GREEN, RED = { 0.45, 0.85, 0.45 }, { 1, 0.45, 0.35 }
local ROW_H = 26
local LINE_H = 18
local HEADER_H = 34

local tab
local rows, lines, headers = {}, {}, {}

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function Header(i, text, y)
	local fs = headers[i]
	if not fs then
		-- The plain font: the display font is hard to read this small.
		fs = UI.Text(tab.scroll.content, 15, GOLD)
		fs.line = tab.scroll.content:CreateTexture(nil, "ARTWORK")
		fs.line:SetHeight(1)
		fs.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
		headers[i] = fs
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 4, -(y + 10))
	fs.line:ClearAllPoints()
	fs.line:SetPoint("TOPLEFT", 4, -(y + 30))
	fs.line:SetPoint("RIGHT", tab.scroll.content, "RIGHT", -8, 0)
	fs:Show()
	fs.line:Show()
	return y + HEADER_H
end

local function CreateEntryRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.name = UI.Text(row, 13, WHITE)
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWordWrap(false)
	row.remove = UI.Button(row, 22, "x")
	row.remove:SetHeight(20)
	row.remove:SetPoint("RIGHT", -4, 0)
	row.plus = UI.Button(row, 22, "+")
	row.plus:SetHeight(20)
	row.plus:SetPoint("RIGHT", row.remove, "LEFT", -10, 0)
	row.count = UI.Text(row, 13, WHITE)
	row.count:SetPoint("RIGHT", row.plus, "LEFT", -6, 0)
	row.count:SetWidth(36)
	row.count:SetJustifyH("CENTER")
	row.minus = UI.Button(row, 22, "-")
	row.minus:SetHeight(20)
	row.minus:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row.crafter = UI.Text(row, 12, GREY)
	row.crafter:SetPoint("RIGHT", row.minus, "LEFT", -12, 0)
	row.crafter:SetJustifyH("RIGHT")
	row.name:SetPoint("RIGHT", row.crafter, "LEFT", -10, 0)
	row.plus:SetScript("OnClick", function()
		row.entry.crafts = row.entry.crafts + 1
		ns.AltsList_Changed()
	end)
	row.minus:SetScript("OnClick", function()
		if row.entry.crafts > 1 then
			row.entry.crafts = row.entry.crafts - 1
			ns.AltsList_Changed()
		end
	end)
	row.remove:SetScript("OnClick", function()
		ns.AltsList_Remove(row.entry.recipeID)
	end)
	return row
end

local function CreateLine(parent)
	local l = CreateFrame("Frame", nil, parent)
	l:SetHeight(LINE_H)
	l:EnableMouse(true)
	l.text = UI.Text(l, 12, WHITE)
	l.text:SetPoint("LEFT", 12, 0)
	l.text:SetPoint("RIGHT", -4, 0)
	l.text:SetWordWrap(false)
	l.right = UI.Text(l, 12, GREY)
	l.right:SetPoint("RIGHT", -4, 0)
	l.right:SetJustifyH("RIGHT")
	l:SetScript("OnEnter", function(self)
		if self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:Show()
		end
	end)
	l:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	l:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.search and not InCombatLockdown() then
			ns.AltsList_Search(self.itemID)
		end
	end)
	return l
end

local function Line(i)
	local l = lines[i] or CreateLine(tab.scroll.content)
	lines[i] = l
	l.itemID, l.search = nil, nil
	l.right:SetText("")
	l:Show()
	return l
end

local function RecipeName(id)
	local r = ns.altsDB.recipes[id]
	return r and r.name or "?"
end

function ns.AltsListTab_Refresh()
	if not (tab and tab:IsVisible()) then
		return
	end
	for _, list in ipairs({ rows, lines, headers }) do
		for _, f in ipairs(list) do
			f:Hide()
			if f.line then
				f.line:Hide() -- a header's rule
			end
		end
	end
	tab.shop:Hide()
	local alts = ns.altsDB
	local todos = ns.AltsList_Todos()
	local content = tab.scroll.content
	tab.empty:SetShown(#alts.list == 0)
	local y = 0
	if #alts.list == 0 then
		tab.scroll:SetContentHeight(1)
		return
	end
	y = Header(1, "Tracked crafts", y)
	for i, t in ipairs(todos) do
		local row = rows[i] or CreateEntryRow(content)
		rows[i] = row
		row.entry = t.entry
		row.name:SetText(ns.Alts_RecipeLabel(t.entry.recipeID, 18))
		row.count:SetText(t.entry.crafts)
		local c = t.crafter and alts.chars[t.crafter]
		local color = c and c.class and C_ClassColor.GetClassColor(c.class)
		row.crafter:SetText(c and c.name or "nobody knows it")
		if color then
			row.crafter:SetTextColor(color.r, color.g, color.b)
		else
			SetColor(row.crafter, RED)
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + ROW_H
	end

	-- Materials across the list.
	local mats, order = {}, {}
	for _, t in ipairs(todos) do
		for _, m in ipairs(t.plan.materials) do
			local key = table.concat(m.items, ",")
			local agg = mats[key]
			if not agg then
				agg = { itemID = m.items[1], need = 0, missing = 0 }
				mats[key] = agg
				order[#order + 1] = key
			end
			agg.need = agg.need + m.need
			agg.missing = agg.missing + m.missing
		end
	end
	local plans = {}
	for _, t in ipairs(todos) do
		plans[#plans + 1] = t.plan
	end
	tab.shop:ClearAllPoints()
	tab.shop:SetPoint("TOPRIGHT", -8, -(y + 6 + 12))
	tab.shop:Set("Tomte: Crafting list", ns.Alts_ShoppingItems(plans, alts.chain))
	y = Header(2, "Materials (all crafts)", y + 6)
	local n = 0
	for _, key in ipairs(order) do
		local agg = mats[key]
		n = n + 1
		local l = Line(n)
		l.itemID = agg.itemID
		l.text:SetText(ns.Alts_ItemLabel(agg.itemID, 14))
		SetColor(l.text, WHITE)
		l.right:SetText(agg.missing > 0 and ("|cffff7359%d missing|r  ·  %d needed"):format(agg.missing, agg.need)
			or ("%d needed"):format(agg.need))
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, -y)
		l:SetPoint("RIGHT")
		y = y + LINE_H
	end

	-- To do: yours, then everyone else's.
	local mine, others = {}, {}
	for _, t in ipairs(todos) do
		for _, line in ipairs(t.lines) do
			table.insert(line.mine and mine or others, { line = line, todo = t })
		end
	end
	y = Header(3, ("To do on %s"):format(UnitName("player")), y + 6)
	if #mine == 0 then
		n = n + 1
		local l = Line(n)
		l.text:SetText("Nothing here: this character has nothing to move or craft.")
		SetColor(l.text, GREY)
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, -y)
		l:SetPoint("RIGHT")
		y = y + LINE_H
	end
	for _, item in ipairs(mine) do
		n = n + 1
		local l = Line(n)
		l.itemID = item.line.itemID
		l.search = item.line.kind ~= "missing" and item.line.itemID ~= nil
		l.text:SetText(item.line.text)
		SetColor(l.text, item.line.kind == "missing" and RED or (item.line.kind == "ready" and GREEN or WHITE))
		l.right:SetText(RecipeName(item.todo.entry.recipeID))
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, -y)
		l:SetPoint("RIGHT")
		y = y + LINE_H
	end
	if #others > 0 then
		y = Header(4, "Elsewhere", y + 6)
		for _, item in ipairs(others) do
			n = n + 1
			local l = Line(n)
			l.itemID = item.line.itemID
			l.text:SetText(item.line.text)
			SetColor(l.text, GREY)
			l.right:SetText(RecipeName(item.todo.entry.recipeID))
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", 0, -y)
			l:SetPoint("RIGHT")
			y = y + LINE_H
		end
	end
	tab.scroll:SetContentHeight(y + 8)
end

function ns.AltsListTab_Create(frame)
	tab = frame
	frame.scroll = UI.Scroll(frame)
	frame.scroll:SetPoint("TOPLEFT")
	frame.scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	frame.shop = ns.AltsShop_CreateLink(frame.scroll.content) -- on the materials heading's line
	frame.empty = UI.Text(frame, 13, GREY)
	frame.empty:SetPoint("TOPLEFT", 8, -8)
	frame.empty:SetPoint("RIGHT", -8, 0)
	frame.empty:SetWordWrap(true)
	frame.empty:SetText("Nothing on the crafting list yet. In the Crafting tab, pick a recipe, set how many and click "
		.. "Add to list. The list works out who needs what from where, shows it in a tracker on screen, and the "
		.. "mailbox can send each craft's materials.")
	frame:HookScript("OnShow", ns.AltsListTab_Refresh)
end
