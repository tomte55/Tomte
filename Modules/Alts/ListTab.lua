local addonName, ns = ...

-- Alts page, List tab: the crafting list as a planning and shopping board. Left, a card per tracked craft (amount
-- - n +, remove, what it costs and sells for, how far along it is) and the whole list's totals; right, every
-- material the list needs with what's missing and what that costs, and the Auctionator shopping list. The to-do
-- lines fold away underneath (the tracker and the mailbox walk you through them). Narrow, the columns stack.
-- Data from List.lua.

local UI = ns.UI
local HEADER_H = 34
local CARD_H = 84
local CARD_GAP = 8
local MAT_H = 22
local LINE_H = 18
local GAP = 28 -- between the columns
local STACK_W = 760 -- narrower than this, the columns stack
local COL_COST, COL_MISSING, COL_HAVE = 84, 70, 96 -- shopping columns, widths from the right edge
local STEP_BIG = 5 -- shift-click on - or +

local tab
local cards, matRows, lines, headers = {}, {}, {}, {}
local totals, tableHead, buyText, todoToggle, partialNote

local function SetColor(fs, role)
	UI.SetTextRole(fs, role)
end

local function RecipeName(id)
	local r = ns.altsDB.recipes[id]
	return r and r.name or "?"
end

local function CharName(guid)
	local c = guid and ns.altsDB.chars[guid]
	if not c then
		return nil
	end
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	return color and color:WrapTextInColorCode(c.name) or c.name
end

-- A section heading with its rule, x and w being the column.
local function Header(i, text, x, y, w)
	local fs = headers[i]
	if not fs then
		-- The plain font: the display font is hard to read this small.
		fs = UI.Text(tab.scroll.content, 15, "heading")
		fs.line = tab.scroll.content:CreateTexture(nil, "ARTWORK")
		fs.line:SetHeight(1)
		fs.line:SetColorTexture(UI.RGBA("frame", 0.25))
		headers[i] = fs
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x + 4, -(y + 10))
	fs.line:ClearAllPoints()
	fs.line:SetPoint("TOPLEFT", x, -(y + 30)) -- as wide as the cards and rows under it
	fs.line:SetWidth(math.max(w, 1))
	fs:Show()
	fs.line:Show()
	return y + HEADER_H
end

-- An inset box; fade (0..1) makes the fill lighter than a card's.
local function Box(frame, fade)
	local bg = UI.Surface(frame, 0.2)
	if fade then
		bg:SetAlpha(fade)
	end
end

-- "Materials 148g · sells for 5g · loss 142g" (value from ns.Value_Plan, or summed for the list).
local function ValueText(value)
	local parts = { ("Materials %s%s"):format(value.complete and "" or "at least ", ns.Alts_Gold(value.cost)) }
	if value.sells then
		parts[#parts + 1] = "sells for " .. ns.Alts_Gold(value.sells)
		local profit = value.sells - value.cost
		parts[#parts + 1] = UI.Wrap(("%s %s"):format(profit >= 0 and "profit" or "loss", ns.Alts_Gold(math.abs(profit))),
			profit >= 0 and "success" or "danger")
	end
	return table.concat(parts, "  ·  ")
end

-- Crafts (left) ---------------------------------------------------------------------------------------------------

local function Step(card, delta)
	local entry = card.entry
	if delta < 0 and entry.crafts <= 1 then
		return
	end
	local n = math.max(entry.crafts + delta, 1)
	if n ~= entry.crafts then
		entry.crafts = n
		ns.AltsList_Changed()
	end
end

local function StepButton(card, text, tip)
	local b = UI.Button(card, 22, text)
	b:SetHeight(20)
	b:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip, 1, 1, 1)
		if text ~= "x" then
			local r, g, b = UI.Color("textMuted")
			GameTooltip:AddLine(("Shift-click: %d at a time"):format(STEP_BIG), r, g, b)
		end
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", GameTooltip_Hide)
	return b
end

local function CreateCard(parent)
	local card = CreateFrame("Frame", nil, parent)
	card:SetHeight(CARD_H)
	card:EnableMouse(true)
	Box(card)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(32, 32)
	card.icon:SetPoint("TOPLEFT", 10, -10)
	card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	card.status = UI.Text(card, 12, "textMuted")
	card.status:SetPoint("TOPRIGHT", -10, -12)
	card.status:SetJustifyH("RIGHT")
	card.status:SetWordWrap(false)
	card.name = UI.Text(card, 14, "text")
	card.name:SetPoint("TOPLEFT", 52, -11)
	card.name:SetPoint("TOPRIGHT", card.status, "TOPLEFT", -12, 1)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.crafter = UI.Text(card, 12, "textMuted")
	card.crafter:SetPoint("TOPLEFT", 52, -32)
	card.crafter:SetPoint("TOPRIGHT", -10, -32)
	card.crafter:SetJustifyH("LEFT")
	card.crafter:SetWordWrap(false)

	card.remove = StepButton(card, "x", "Remove from the list")
	card.remove:SetPoint("BOTTOMRIGHT", -10, 12)
	card.plus = StepButton(card, "+", "One more")
	card.plus:SetPoint("RIGHT", card.remove, "LEFT", -14, 0)
	card.count = UI.Text(card, 14, "text", "number")
	card.count:SetWidth(36)
	card.count:SetJustifyH("CENTER")
	card.count:SetPoint("RIGHT", card.plus, "LEFT", -2, 0)
	card.minus = StepButton(card, "-", "One less")
	card.minus:SetPoint("RIGHT", card.count, "LEFT", -2, 0)
	-- Quality, for recipes with more than one: at the end of the crafter's line.
	card.quality = UI.Dropdown(card, 112)
	card.quality:SetHeight(20)
	card.quality:SetPoint("TOPRIGHT", -10, -28)
	card.quality.getValue = function()
		local r = ns.altsDB.recipes[card.entry.recipeID]
		return ns.Alts_ClampQuality(r, card.entry.quality) or 0
	end
	card.quality.setValue = function(value)
		card.entry.quality = value ~= 0 and value or nil
		ns.AltsList_Changed()
	end
	card.quality.choices = function()
		local id = card.entry.recipeID
		local list = { { value = 0, text = "Any quality" } }
		for q = 1, ns.Alts_Qualities(ns.altsDB.recipes[id]) do
			list[#list + 1] = { value = q, text = ("%s Quality %d"):format(ns.Alts_QualityMarkup(id, q), q) }
		end
		return list
	end
	card.quality:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Quality", 1, 1, 1)
		local r, g, b = UI.Color("textMuted")
		GameTooltip:AddLine("The quality you mean to make, shown with the craft here and in the tracker.", r, g, b, true)
		GameTooltip:Show()
	end)
	card.quality:HookScript("OnLeave", GameTooltip_Hide)
	card.value = UI.Text(card, 12, "textMuted")
	card.value:SetPoint("LEFT", card, "BOTTOMLEFT", 10, 22) -- level with the buttons' middle
	card.value:SetPoint("RIGHT", card.minus, "LEFT", -12, 0)
	card.value:SetJustifyH("LEFT")
	card.value:SetWordWrap(false)

	-- How much of the material is in the crafter's bags, along the bottom edge.
	card.track = card:CreateTexture(nil, "ARTWORK")
	card.track:SetColorTexture(1, 1, 1, 0.06)
	card.track:SetPoint("BOTTOMLEFT", 1, 1)
	card.track:SetPoint("BOTTOMRIGHT", -1, 1)
	card.track:SetHeight(2)
	card.fill = card:CreateTexture(nil, "ARTWORK", nil, 1)
	card.fill:SetPoint("BOTTOMLEFT", 1, 1)
	card.fill:SetHeight(2)

	card.plus:SetScript("OnClick", function()
		Step(card, IsShiftKeyDown() and STEP_BIG or 1)
	end)
	card.minus:SetScript("OnClick", function()
		Step(card, -(IsShiftKeyDown() and STEP_BIG or 1))
	end)
	card.remove:SetScript("OnClick", function()
		ns.AltsList_Remove(card.entry.recipeID)
	end)
	card:SetScript("OnEnter", function(self)
		local r = ns.altsDB.recipes[self.entry.recipeID]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if r and r.item then
			GameTooltip:SetItemByID(r.item)
		else
			GameTooltip:SetText(RecipeName(self.entry.recipeID))
		end
		GameTooltip:AddLine(" ")
		local r, g, b = UI.Color("textMuted")
		GameTooltip:AddLine("Click: open it in the Crafting tab", r, g, b)
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", GameTooltip_Hide)
	card:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			ns.AltsCraft_Open(self.entry.recipeID, nil, self.entry)
		end
	end)
	return card
end

-- The card's tag: what stands between you and the craft.
local function Status(t)
	local plan = t.plan
	if t.entry.crafts <= 0 then
		return "Done: remove it", "success"
	elseif plan.missing > 0 then
		return ns.Alts_MissingText(plan), "danger"
	elseif plan.unknown > 0 then
		for _, l in ipairs(t.lines) do
			if l.kind == "craft" and l.nobody then
				return ("Nobody knows %s"):format(RecipeName(l.recipeID)), "warning"
			end
		end
		return "A recipe on the way isn't known", "warning"
	elseif t.done then
		return t.crafter == UnitGUID("player") and "Ready to craft" or "Ready on " .. (CharName(t.crafter) or "?"), "success"
	end
	return ("%d%% in place"):format(math.floor(ns.Alts_CraftProgress(t) * 100)), "textMuted"
end

local function PlaceCard(i, t, x, y, w)
	local card = cards[i] or CreateCard(tab.scroll.content)
	cards[i] = card
	local entry = t.entry
	local r = ns.altsDB.recipes[entry.recipeID]
	card.entry = entry
	card.icon:SetTexture(r and r.icon or 134400) -- the question mark
	card.name:SetText(ns.Alts_RecipeLabel(entry.recipeID, nil, entry.quality))
	card.count:SetText(entry.crafts)
	local hasQuality = ns.Alts_Qualities(r) > 1
	card.quality:SetShown(hasQuality)
	if hasQuality then
		card.crafter:SetPoint("TOPRIGHT", card.quality, "TOPLEFT", -10, -4) -- the dropdown's top is 4 above the text's
	else
		card.crafter:SetPoint("TOPRIGHT", -10, -32)
	end
	if hasQuality then
		card.quality:Refresh()
	end
	local status, color = Status(t)
	card.status:SetText(status)
	SetColor(card.status, color)

	local who = CharName(t.crafter)
	local crafter = who and (who .. " crafts it") or UI.Wrap("nobody knows it", "danger")
	-- Crafts that come before it: "2 Core Alloy first", or how many when there are several.
	local before = #t.plan.steps - 1
	if before == 1 then
		local step = t.plan.steps[1]
		crafter = crafter .. ("  ·  %d %s first"):format(step.crafts, step.quality
			and ns.Alts_RecipeLabel(step.recipeID, nil, step.quality) or RecipeName(step.recipeID))
	elseif before > 1 then
		crafter = crafter .. ("  ·  %d crafts first"):format(before)
	end
	card.crafter:SetText(crafter)

	local value = entry.crafts > 0 and ns.Value_Plan and ns.Value_Plan(t.plan, r, entry.crafts)
	if value then
		card.value:SetText(ValueText(value))
	elseif t.needed > 0 then
		card.value:SetText(("%d of %d materials in the crafter's bags"):format(t.inPlace, t.needed))
	else
		card.value:SetText("")
	end

	local progress = entry.crafts <= 0 and 1 or ns.Alts_CraftProgress(t)
	card.fill:SetColorTexture(UI.RGBA(t.done and "success" or "accent", 0.8))
	card.fill:SetWidth(math.max((w - 2) * progress, 0.01))
	card.fill:SetShown(progress > 0)

	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", x, -y)
	card:SetWidth(w)
	card:Show()
	return value
end

local function PlaceTotals(x, y, w, sum, n)
	if not totals then
		totals = CreateFrame("Frame", nil, tab.scroll.content)
		totals:SetHeight(48)
		Box(totals, 0.6)
		totals.title = UI.Text(totals, 12, "heading")
		totals.title:SetPoint("TOPLEFT", 10, -9)
		totals.text = UI.Text(totals, 12, "text")
		totals.text:SetPoint("TOPLEFT", totals.title, "BOTTOMLEFT", 0, -5)
		totals.text:SetPoint("RIGHT", -10, 0)
		totals.text:SetJustifyH("LEFT")
		totals.text:SetWordWrap(false)
	end
	totals.title:SetText(("Whole list: %d craft%s"):format(n, n == 1 and "" or "s"))
	totals.text:SetText(ValueText(sum))
	totals:ClearAllPoints()
	totals:SetPoint("TOPLEFT", x, -y)
	totals:SetWidth(w)
	totals:Show()
	return y + 48
end

-- Shopping (right) -----------------------------------------------------------------------------------------------

-- Right-click on a ranked material: its rank for every craft on the list that uses it (Alts_ListSetRank).
local function RankMenu(row)
	local slot = row.agg.slot
	local key = table.concat(slot, ",")
	local users = {} -- [entry] = true: the crafts whose plan has this slot
	for _, t in ipairs(ns.AltsList_Todos()) do
		for _, m in ipairs(t.plan.materials) do
			if m.slot and table.concat(m.slot, ",") == key then
				users[t.entry] = true
			end
		end
	end
	local current = #row.agg.items == 1 and row.agg.items[1] or 0
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle("Use which rank? (every craft on the list)")
		local function IsSelected(itemID)
			return current == itemID
		end
		local function Select(itemID)
			ns.Alts_ListSetRank(ns.altsDB.list, key, itemID ~= 0 and itemID or nil, function(e)
				return users[e]
			end)
			ns.AltsList_Changed()
		end
		root:CreateRadio("Any rank", IsSelected, Select, 0)
		for i, itemID in ipairs(slot) do
			local mark = ns.Alts_RankMarkup(itemID)
			root:CreateRadio(("%s %s"):format(mark ~= "" and mark or ("Rank %d"):format(i),
				C_Item.GetItemNameByID(itemID) or ("item " .. itemID)), IsSelected, Select, itemID)
		end
	end)
end

local function CreateMatRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(MAT_H)
	row:EnableMouse(true)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.03)
	row.cost = UI.Text(row, 12, "text", "number")
	row.cost:SetPoint("RIGHT", -6, 0)
	row.cost:SetWidth(COL_COST - 6)
	row.cost:SetJustifyH("RIGHT")
	row.missing = UI.Text(row, 12, "danger", "number")
	row.missing:SetPoint("RIGHT", -COL_COST, 0)
	row.missing:SetWidth(COL_MISSING - 6)
	row.missing:SetJustifyH("RIGHT")
	row.have = UI.Text(row, 12, "text", "number")
	row.have:SetPoint("RIGHT", -(COL_COST + COL_MISSING), 0)
	row.have:SetWidth(COL_HAVE - 6)
	row.have:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("LEFT", 6, 0)
	row.name:SetPoint("RIGHT", row.have, "LEFT", -8, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.agg.itemID)
		local _, where = ns.Alts_Have(self.agg.items)
		if #where > 0 then
			GameTooltip:AddLine(" ")
			local r, g, b = UI.Color("heading")
			GameTooltip:AddLine("Where you have it", r, g, b)
			for i, w in ipairs(where) do
				if i > 8 then
					break
				end
				local color = w.class and C_ClassColor.GetClassColor(w.class)
				local r, g, b = 1, 1, 1
				if color then
					r, g, b = color:GetRGB()
				end
				GameTooltip:AddDoubleLine(w.name, w.n, r, g, b, 1, 1, 1)
			end
		end
		if self.agg.slot then
			GameTooltip:AddLine(" ")
			local r, g, b = UI.Color("textMuted")
			GameTooltip:AddLine("Right-click: choose the rank for the whole list", r, g, b)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and not InCombatLockdown() then
			ns.AltsList_Search(self.agg.itemID)
		elseif button == "RightButton" and self.agg and self.agg.slot then
			RankMenu(self)
		end
	end)
	return row
end

-- Every material across the list ({ itemID, items, need, missing, unit, cost }), missing ones first by cost.
local function Materials(todos)
	local byKey, list = {}, {}
	for _, t in ipairs(todos) do
		for _, m in ipairs(t.plan.materials) do
			local key = table.concat(m.items, ",")
			local agg = byKey[key]
			if not agg then
				agg = { itemID = m.items[1], items = m.items, need = 0, missing = 0, order = #list + 1,
					slot = m.slot and #m.slot > 1 and m.slot or nil }
				byKey[key] = agg
				list[#list + 1] = agg
			end
			agg.need = agg.need + m.need
			agg.missing = agg.missing + m.missing
		end
	end
	for _, agg in ipairs(list) do
		agg.unit = ns.Value_ItemPrice and (ns.Value_ItemPrice(agg.itemID)) or nil
		agg.cost = agg.unit and agg.unit * agg.missing or nil
	end
	table.sort(list, function(a, b)
		if (a.missing > 0) ~= (b.missing > 0) then
			return a.missing > 0
		end
		if a.missing > 0 and (a.cost or -1) ~= (b.cost or -1) then
			return (a.cost or -1) > (b.cost or -1)
		end
		return a.order < b.order
	end)
	return list
end

local function PlaceShopping(todos, x, y, w)
	local content = tab.scroll.content
	y = Header(2, "Shopping", x, y, w)
	local list = Materials(todos)
	if not tableHead then
		tableHead = CreateMatRow(content)
		tableHead:EnableMouse(false)
		tableHead.stripe:Hide()
		for _, fs in ipairs({ tableHead.name, tableHead.have, tableHead.missing, tableHead.cost }) do
			SetColor(fs, "textMuted")
		end
		tableHead.name:SetText("Material")
		tableHead.have:SetText("Have / need")
		tableHead.missing:SetText("Missing")
		tableHead.cost:SetText("Cost")
	end
	tableHead:ClearAllPoints()
	tableHead:SetPoint("TOPLEFT", x, -(y - 6))
	tableHead:SetWidth(w)
	tableHead:Show()
	y = y + MAT_H - 4

	local buy, complete, missingCount = 0, true, 0
	for i, agg in ipairs(list) do
		local row = matRows[i] or CreateMatRow(content)
		matRows[i] = row
		row.agg = agg
		-- A ranked material shows its rank, or "any rank".
		local label = ns.Alts_ItemLabel(agg.itemID, 16, #agg.items > 1)
		if #agg.items > 1 and agg.slot then
			label = label .. " " .. UI.Wrap("(any rank)", "textMuted")
		end
		row.name:SetText(label)
		row.have:SetText(("%d / %d"):format(agg.need - agg.missing, agg.need))
		if agg.missing > 0 then
			missingCount = missingCount + 1
			row.missing:SetText(agg.missing)
			row.cost:SetText(agg.cost and ns.Alts_Price(agg.cost) or UI.Wrap("?", "textMuted"))
			if agg.cost then
				buy = buy + agg.cost
			else
				complete = false
			end
			row:SetAlpha(1)
		else
			row.missing:SetText(UI.Wrap("-", "textFaint"))
			row.cost:SetText("")
			row:SetAlpha(0.55)
		end
		row.stripe:SetShown(i % 2 == 1)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", x, -y)
		row:SetWidth(w)
		row:Show()
		y = y + MAT_H
	end

	-- Footer: what buying the rest costs, and the shopping list.
	if not buyText then
		buyText = UI.Text(content, 13, "text")
		buyText:SetJustifyH("LEFT")
	end
	if missingCount == 0 then
		buyText:SetText(UI.Wrap("Everything's covered.", "success"))
	elseif ns.Value_ItemPrice and buy > 0 then
		buyText:SetText(("Buy what's missing: %s~%s"):format(complete and "" or "at least ", ns.Alts_Gold(buy)))
	else
		buyText:SetText(("%d material%s to get"):format(missingCount, missingCount == 1 and "" or "s"))
	end
	buyText:ClearAllPoints()
	buyText:SetPoint("TOPLEFT", x + 6, -(y + 16))
	buyText:Show()
	local plans = {}
	for _, t in ipairs(todos) do
		plans[#plans + 1] = t.plan
	end
	tab.shop:Set("Tomte: Crafting list", ns.Alts_ShoppingItems(plans, ns.altsDB.chain))
	tab.shop:ClearAllPoints()
	tab.shop:SetPoint("TOPRIGHT", content, "TOPLEFT", x + w - 4, -(y + 10))
	y = y + 44
	-- Without Syndicator, "missing" may be on another character (List.lua).
	if missingCount > 0 and ns.AltsList_PartialCounts(todos) then
		if not partialNote then
			partialNote = UI.Text(content, 12, "textMuted")
			partialNote:SetJustifyH("LEFT")
			partialNote:SetWordWrap(true)
		end
		partialNote:SetText(ns.ALTS_PARTIAL_NOTE)
		partialNote:SetWidth(math.max(w - 12, 1))
		partialNote:ClearAllPoints()
		partialNote:SetPoint("TOPLEFT", x + 6, -y)
		partialNote:Show()
		y = y + math.ceil(partialNote:GetStringHeight()) + 8
	end
	return y
end

-- To do (under both) ---------------------------------------------------------------------------------------------

local function CreateLine(parent)
	local l = CreateFrame("Frame", nil, parent)
	l:SetHeight(LINE_H)
	l:EnableMouse(true)
	l.text = UI.Text(l, 12, "text")
	l.text:SetPoint("LEFT", 12, 0)
	l.text:SetPoint("RIGHT", -4, 0)
	l.text:SetWordWrap(false)
	l.right = UI.Text(l, 12, "textMuted")
	l.right:SetPoint("RIGHT", -4, 0)
	l.right:SetJustifyH("RIGHT")
	l:SetScript("OnEnter", function(self)
		if self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:Show()
		end
	end)
	l:SetScript("OnLeave", GameTooltip_Hide)
	l:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.search and not InCombatLockdown() then
			ns.AltsList_Search(self.itemID)
		end
	end)
	return l
end

local function Line(i, y)
	local l = lines[i] or CreateLine(tab.scroll.content)
	lines[i] = l
	l.itemID, l.search = nil, nil
	l.right:SetText("")
	l:ClearAllPoints()
	l:SetPoint("TOPLEFT", 0, -y)
	l:SetPoint("RIGHT")
	l:Show()
	return l
end

local function CreateTodoToggle(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(HEADER_H - 4)
	b.text = UI.Text(b, 15, "heading")
	b.text:SetPoint("TOPLEFT", 4, -10)
	b.meta = UI.Text(b, 12, "textMuted")
	b.meta:SetPoint("LEFT", b.text, "RIGHT", 12, 0)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetHeight(1)
	b.line:SetColorTexture(UI.RGBA("frame", 0.25))
	b.line:SetPoint("TOPLEFT", 0, -30)
	b.line:SetPoint("TOPRIGHT", 0, -30)
	b:SetScript("OnEnter", function(self)
		SetColor(self.text, "text")
	end)
	b:SetScript("OnLeave", function(self)
		SetColor(self.text, "heading")
	end)
	b:SetScript("OnClick", function()
		ns.altsDB.listTodoOpen = not ns.altsDB.listTodoOpen or nil
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.AltsListTab_Refresh()
	end)
	return b
end

-- Lines that move the same item the same way (Mail 10, Mail 15 and Mail 6 Bismuth to Tomten) are one trip: their
-- counts are added up ("Mail 31 ..."), and a missing material's price is worked out again for the total.
local MERGE = { mail = true, deposit = true, take = true, grab = true, collect = true, fetch = true, missing = true }

local function Merged(todos)
	local mine, others, byKey = {}, {}, {}
	for _, t in ipairs(todos) do
		for _, line in ipairs(t.lines) do
			-- "Tomten crafts 1 ..." lines: the card already says who crafts it and whether it's ready.
			if line.kind ~= "wait" then
				local key = MERGE[line.kind] and line.itemID
					and table.concat({ line.kind, line.itemID, tostring(line.from), tostring(line.where), tostring(line.to) }, ":")
				local item = key and byKey[key]
				if item then
					item.n = item.n + line.n
					item.recipes[t.entry.recipeID] = true
				else
					item = { line = line, n = line.n, recipes = { [t.entry.recipeID] = true }, first = t.entry.recipeID }
					if key then
						byKey[key] = item
					end
					table.insert(line.mine and mine or others, item)
				end
			end
		end
	end
	return mine, others
end

local function ItemText(item)
	local line = item.line
	if item.n == line.n then
		return line.text
	end
	local text = line.text:gsub("^(%D-)%d+", "%1" .. item.n, 1)
	if line.kind == "missing" then
		text = text:gsub(" %(~[^)]*%)$", "")
		local unit = ns.Value_ItemPrice and ns.altsDB and (ns.Value_ItemPrice(line.itemID))
		if unit then
			text = text .. (" (~%s)"):format(ns.Alts_Price(unit * item.n))
		end
	end
	return text
end

local function CraftsText(item)
	local n = 0
	for _ in pairs(item.recipes) do
		n = n + 1
	end
	return n == 1 and RecipeName(item.first) or ("%d crafts"):format(n)
end

local function PlaceTodo(todos, y)
	local mine, others = Merged(todos)
	local open = ns.altsDB.listTodoOpen
	todoToggle = todoToggle or CreateTodoToggle(tab.scroll.content)
	todoToggle.text:SetText(("%s  To do on %s"):format(open and "-" or "+", UnitName("player")))
	local meta = ("%d step%s here"):format(#mine, #mine == 1 and "" or "s")
	if #others > 0 then
		meta = meta .. ("  ·  %d elsewhere"):format(#others)
	end
	todoToggle.meta:SetText(meta .. (open and "" or "  ·  the tracker and the mailbox walk you through them"))
	todoToggle:ClearAllPoints()
	todoToggle:SetPoint("TOPLEFT", 0, -y)
	todoToggle:SetPoint("RIGHT")
	todoToggle:Show()
	y = y + HEADER_H
	if not open then
		return y
	end
	-- Which craft a line is for only matters with more than one.
	local showCraft = #todos > 1
	local n = 0
	if #mine == 0 then
		n = n + 1
		local l = Line(n, y)
		l.text:SetText("Nothing here: this character has nothing to move or craft.")
		SetColor(l.text, "textMuted")
		y = y + LINE_H
	end
	for _, item in ipairs(mine) do
		n = n + 1
		local l = Line(n, y)
		l.itemID = item.line.itemID
		l.search = item.line.kind ~= "missing" and item.line.itemID ~= nil
		l.text:SetText(ItemText(item))
		SetColor(l.text, item.line.kind == "missing" and "danger" or (item.line.kind == "ready" and "success" or "text"))
		l.right:SetText(showCraft and CraftsText(item) or "")
		y = y + LINE_H
	end
	if #others > 0 then
		n = n + 1
		local l = Line(n, y + 6)
		l.text:SetText("Elsewhere")
		SetColor(l.text, "heading")
		y = y + LINE_H + 6
		for _, item in ipairs(others) do
			n = n + 1
			local l = Line(n, y)
			l.itemID = item.line.itemID
			l.text:SetText(ItemText(item))
			SetColor(l.text, "textMuted")
			l.right:SetText(showCraft and CraftsText(item) or "")
			y = y + LINE_H
		end
	end
	return y
end

-- Refresh --------------------------------------------------------------------------------------------------------

function ns.AltsListTab_Refresh()
	if not (tab and tab:IsVisible()) then
		return
	end
	for _, list in ipairs({ cards, matRows, lines, headers }) do
		for _, f in pairs(list) do
			f:Hide()
			if f.line then
				f.line:Hide() -- a header's rule
			end
		end
	end
	for _, f in pairs({ totals = totals, tableHead = tableHead, buyText = buyText, todoToggle = todoToggle,
		partialNote = partialNote }) do
		f:Hide() -- made on first use
	end
	tab.shop:Hide()
	local alts = ns.altsDB
	tab.empty:SetShown(#alts.list == 0)
	if #alts.list == 0 then
		tab.scroll:SetContentHeight(1)
		return
	end
	local todos = ns.AltsList_Todos()

	local width = tab.scroll.content:GetWidth()
	if width <= 1 then
		width = tab:GetWidth() - 10
	end
	local stacked = width < STACK_W
	local leftW = stacked and width or math.floor((width - GAP) * 0.42)
	local rightX = stacked and 0 or leftW + GAP
	local rightW = stacked and width or width - rightX

	-- Crafts.
	local y = Header(1, "Your crafts", 0, 0, leftW)
	local sum, priced, allSell = { cost = 0, sells = 0, complete = true }, false, true
	for i, t in ipairs(todos) do
		local value = PlaceCard(i, t, 0, y, leftW)
		if value then
			priced = true
			sum.cost = sum.cost + value.cost
			sum.complete = sum.complete and value.complete
			if value.sells then
				sum.sells = sum.sells + value.sells
			else
				allSell = false
			end
		end
		y = y + CARD_H + CARD_GAP
	end
	if not allSell then
		sum.sells = nil -- a craft without an auction price: a list profit would be made up
	end
	if priced and #todos > 1 then
		y = PlaceTotals(0, y, leftW, sum, #todos) + CARD_GAP
	end

	-- Shopping, beside the crafts or under them.
	local rightY = PlaceShopping(todos, rightX, stacked and y + 6 or 0, rightW)
	y = math.max(y, rightY)

	y = PlaceTodo(todos, y + 10)
	tab.scroll:SetContentHeight(y + 12)
end

function ns.AltsListTab_Create(frame)
	tab = frame
	frame.scroll = UI.Scroll(frame)
	frame.scroll:SetPoint("TOPLEFT")
	frame.scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	frame.scroll.onWidthChanged = function()
		ns.AltsListTab_Refresh()
	end
	-- The Auctionator shopping list, as a button under the shopping table.
	local shop = ns.AltsShop_CreateLink(frame.scroll.content)
	shop:SetSize(124, 22)
	UI.Surface(shop, 0.45)
	shop.text:ClearAllPoints()
	shop.text:SetPoint("CENTER")
	frame.shop = shop
	frame.empty = UI.Text(frame, 13, "textMuted")
	frame.empty:SetPoint("TOPLEFT", 8, -8)
	frame.empty:SetPoint("RIGHT", -8, 0)
	frame.empty:SetWordWrap(true)
	frame.empty:SetText("Nothing on the crafting list yet. In the Crafting tab, pick a recipe, set how many and click "
		.. "Add to list. The list works out who needs what from where, shows it in a tracker on screen, and the "
		.. "mailbox can send each craft's materials.")
	frame:HookScript("OnShow", ns.AltsListTab_Refresh)
end
