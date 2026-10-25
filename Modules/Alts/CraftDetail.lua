local addonName, ns = ...

-- Alts page, Crafting tab: the selected recipe on the right (title, craft count, quality, materials, steps, value and
-- the gear line). CraftTab.lua has the shared helpers and entry points, CraftResults.lua the list that selects it.

local S = ns.AltsCraft_State
local UI = ns.UI
local MAT_H, STEP_H, HEADER_H, QUALITY_H = 20, 20, 26, 28

local matRows, stepRows, headers = {}, {}, {}

local SetColor, ClassName, Names, ItemName = ns.AltsCraft_SetColor, ns.AltsCraft_ClassName, ns.AltsCraft_Names, ns.AltsCraft_ItemName -- CraftTab.lua
local QualityColor, RecipeName, ProfName = ns.AltsCraft_QualityColor, ns.AltsCraft_RecipeName, ns.AltsCraft_ProfName
local ForChar, CompareQuality, ForInfo, ForText = ns.AltsCraft_ForChar, ns.AltsCraft_CompareQuality, ns.AltsCraft_ForInfo, ns.AltsCraft_ForText -- CraftGear.lua

-- Detail ---------------------------------------------------------------------------------------------------

local LayoutDetail -- below

-- The detail's text lines in headers[], each made on first use: the materials and steps headings, the "Syndicator
-- isn't loaded" note, the Gold & value line and the "For <name>:" line.
local H_MATERIALS, H_STEPS, H_SYNDICATOR, H_VALUE, H_FOR = 1, 2, 3, 4, 5

local function Header(i, text, y)
	local fs = headers[i]
	if not fs then
		fs = UI.Text(S.tab.detail.content, 11, "textMuted")
		headers[i] = fs
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 4, -(y + 10))
	fs:Show()
	return y + HEADER_H
end

-- A reagent slot's rank for this craft: db.ranks[slot key] = itemID, nil for any rank.
local function SetRank(slot, itemID)
	local key = table.concat(slot, ",")
	S.db.ranks = S.db.ranks or {}
	S.db.ranks[key] = itemID
	if next(S.db.ranks) == nil then
		S.db.ranks = nil
	end
	LayoutDetail()
end

-- The rank menu of a material row: any rank, or one of the slot's ranks.
local function RankMenu(row)
	local slot = row.slot
	local key = table.concat(slot, ",")
	UI.ContextMenu(row, function(_, root)
		root:CreateTitle("Use which rank?")
		local function IsSelected(itemID)
			return (S.db.ranks and S.db.ranks[key] or 0) == itemID
		end
		local function Select(itemID)
			SetRank(slot, itemID ~= 0 and itemID or nil)
		end
		root:CreateRadio("Any rank", IsSelected, Select, 0)
		for i, itemID in ipairs(slot) do
			local mark = ns.Alts_RankMarkup(itemID)
			root:CreateRadio(("%s %s"):format(mark ~= "" and mark or ("Rank %d"):format(i), ItemName(itemID)), IsSelected,
				Select, itemID)
		end
	end)
end

local function CreateMatRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(MAT_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self)
		if self.slot then
			RankMenu(self)
		end
	end)
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWidth(190)
	row.name:SetWordWrap(false)
	row.count = UI.Text(row, 12, "text", "number")
	row.count:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.count:SetWidth(70)
	row.count:SetJustifyH("RIGHT")
	row.where = UI.Text(row, 11, "textMuted")
	row.where:SetPoint("LEFT", row.count, "RIGHT", 12, 0)
	row.where:SetPoint("RIGHT", -4, 0)
	row.where:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.itemID)
		if self.whereFull then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(self.whereFull, 1, 1, 1, true)
		end
		local unit, _, stale
		if ns.Value_ItemPrice then
			unit, _, stale = ns.Value_ItemPrice(self.itemID) -- not "a and f()": that keeps only the first value
		end
		if unit then
			local hr, hg, hb = UI.Color("heading")
			GameTooltip:AddLine(("Worth %s each, %s for %d"):format(ns.Value_Text(unit, stale), ns.Value_Text(unit * self.need, stale),
				self.need), hr, hg, hb)
		end
		if self.slot then
			GameTooltip:AddLine(" ")
			local r, g, b = UI.Color("textMuted")
			GameTooltip:AddLine("Click: choose the rank (counted, bought and sent only at that rank)", r, g, b, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return row
end

local function CreateStepRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(STEP_H)
	row.num = UI.Text(row, 12, "heading", "number")
	row.num:SetPoint("LEFT", 4, 0)
	row.num:SetWidth(18)
	row.text = UI.Text(row, 12, "text")
	row.text:SetPoint("LEFT", row.num, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetWordWrap(false)
	return row
end

-- "Kesha 5, Warband bank 1": names in class color (the Warband bank in the accent), counts in the text color.
local function WhereText(list, limit)
	local parts = {}
	for i, w in ipairs(list) do
		if i > limit then
			parts[#parts + 1] = UI.Wrap("...", "textMuted")
			break
		end
		local color = w.class and C_ClassColor.GetClassColor(w.class)
		local name = color and color:WrapTextInColorCode(w.name) or UI.Wrap(w.name, "accent")
		parts[#parts + 1] = ("%s %s"):format(name, UI.Wrap(w.n, "text"))
	end
	return table.concat(parts, "  ")
end

-- quality: the final craft's picked quality (a material's step has its own).
local function StepText(step, quality)
	local q = step.quality or quality
	local what = ("%dx %s"):format(step.crafts, q and ns.Alts_RecipeLabel(step.recipeID, nil, q)
		or RecipeName(S.db.recipes[step.recipeID]))
	if #step.crafters > 0 then
		return ("%s crafts %s"):format(Names(step.crafters, 2), what)
	elseif #step.learnable > 0 then
		return ("%s %s %s"):format(UI.Wrap("nobody knows", "danger"), what,
			UI.Wrap(("(learnable: %s)"):format(Names(step.learnable, 2)), "textMuted"))
	end
	return ("%s %s"):format(UI.Wrap("nobody can make", "danger"), what)
end

function LayoutDetail()
	local d = S.tab.detail
	for _, list in ipairs({ matRows, stepRows, headers }) do
		for _, row in pairs(list) do -- pairs: headers has gaps (H_SYNDICATOR, H_VALUE and H_FOR are conditional)
			row:Hide()
		end
	end
	d.shop:Hide()
	d.forWait = d.forWait or UI.ProgressLine(d.content)
	d.forWait:Stop()
	local recipe = S.db.selected and S.db.recipes[S.db.selected]
	d.empty:SetShown(not recipe)
	d.title:SetShown(recipe ~= nil)
	d.sub:SetShown(recipe ~= nil)
	d.status:SetShown(recipe ~= nil)
	d.crafts:SetShown(recipe ~= nil)
	d.add:SetShown(recipe ~= nil)
	if not recipe then
		d.quality:Hide()
		d.scroll:SetContentHeight(1)
		return
	end
	d.title:SetText(recipe.name or "?")
	SetColor(d.title, QualityColor(recipe.item) or "heading")
	local status, who = ns.Alts_RecipeStatus(S.db.chars, recipe, S.db.selected)
	local prof = ProfName(recipe.base)
	if status == "known" then
		d.sub:SetText(("%s · %s"):format(prof, Names(who, 4)))
	elseif status == "learnable" then
		d.sub:SetText(("%s · nobody knows it yet · learnable: %s"):format(prof, Names(who, 4)))
	else
		d.sub:SetText(("%s · nobody on your account has this profession"):format(prof))
	end

	local ok, plan = xpcall(ns.Alts_Plan, function(err)
		return ns.errorHandler(err)
	end, S.db.selected, S.db.crafts or 1, {
		recipes = S.db.recipes, chars = S.db.chars, producers = S.producers,
		maxDepth = S.db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH, ranks = S.db.ranks,
		count = function(items)
			return (ns.Alts_Have(items))
		end,
	})
	if not ok then
		d.status:SetText("Couldn't work out the materials (the error is in BugSack).")
		SetColor(d.status, "danger")
		d.crafts:SetValue(S.db.crafts or 1)
		d.quality:Hide() -- not the previous recipe's
		d.scroll:SetContentHeight(1)
		return
	end
	ns.AltsCraft_LastPlan = plan -- Send to alt: materials go to the crafter of their step
	if plan.missing > 0 then
		d.status:SetText(ns.Alts_MissingText(plan))
		SetColor(d.status, "danger")
	elseif plan.unknown > 0 then
		d.status:SetText("You have the materials, but a recipe on the way isn't known yet")
		SetColor(d.status, "warning")
	elseif #plan.steps > 1 then
		d.status:SetText(("Everything's there: %d crafts"):format(#plan.steps))
		SetColor(d.status, "success")
	else
		d.status:SetText("Everything's there")
		SetColor(d.status, "success")
	end
	d.crafts:SetValue(S.db.crafts or 1)

	local content = d.content
	local y = 0
	-- Quality: what you mean to make (recipes with more than one).
	local quality = ns.Alts_ClampQuality(recipe, S.db.quality)
	d.quality:SetShown(ns.Alts_Qualities(recipe) > 1)
	if d.quality:IsShown() then
		d.quality:Refresh()
		y = QUALITY_H
	end
	local forChar = ForChar()
	if forChar then
		local fs = headers[H_FOR] or UI.Text(content, 12, "text")
		headers[H_FOR] = fs
		fs:SetWordWrap(true)
		fs:SetJustifyH("LEFT")
		local info = ForInfo(recipe, forChar, CompareQuality(quality))
		fs:SetText(("%s %s"):format(UI.Wrap(("For %s:"):format(ClassName(forChar)), "heading"),
			ForText(info, forChar, recipe)))
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 4, -(y + 6))
		fs:SetPoint("RIGHT", -4, 0)
		fs:Show()
		y = y + fs:GetStringHeight() + 8
		-- A busy line while item levels load (the items' loads redraw this).
		if info and (info.loading or info.target and info.target.loading) then
			d.forWait:Below(fs):Track(UI.ProgressBusy)
		end
	end
	d.shop:ClearAllPoints()
	d.shop:SetPoint("TOPRIGHT", -4, -(y + 8)) -- on the materials heading's line
	y = Header(H_MATERIALS, "Materials (have / need)", y)
	d.shop:Set("Tomte: " .. (recipe.name or "?"), ns.Alts_ShoppingItems(plan, S.db.chain))
	for i, m in ipairs(plan.materials) do
		local row = matRows[i] or CreateMatRow(content)
		matRows[i] = row
		local itemID = m.items[1]
		row.itemID, row.need = itemID, m.need
		row.slot = m.slot and #m.slot > 1 and m.slot or nil
		local rank = ""
		if row.slot then
			rank = #m.items == 1 and ns.Alts_RankMarkup(itemID) or UI.Wrap("any rank", "textMuted")
		end
		row.name:SetText(rank ~= "" and (ItemName(itemID) .. " " .. rank) or ItemName(itemID))
		row.count:SetText(("%d / %d"):format(m.have, m.need))
		local _, where = ns.Alts_Have(m.items)
		row.whereFull = #where > 0 and WhereText(where, 20) or nil
		SetColor(row.name, QualityColor(itemID) or "text")
		if m.missing > 0 then
			SetColor(row.count, "danger")
			row.where:SetText(("%s   %s"):format(UI.Wrap(("missing %d"):format(m.missing), "danger"), WhereText(where, 3)))
		elseif m.crafted then
			SetColor(row.count, "warning")
			row.where:SetText(("craft the rest: %s"):format(RecipeName(S.db.recipes[m.crafted])))
		else
			SetColor(row.count, "success")
			row.where:SetText(WhereText(where, 3))
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + MAT_H
	end
	if #plan.materials == 0 then
		y = y + MAT_H
	end
	-- Gold & value: cost of the materials, what it sells for, the difference.
	local value = ns.Value_Plan and ns.Value_Plan(plan, recipe, S.db.crafts or 1)
	if value then
		local parts = { ("Materials %s%s"):format(value.complete and "" or "at least ", ns.Alts_Gold(value.cost)) }
		if value.sells then
			parts[#parts + 1] = "sells for " .. ns.Alts_Gold(value.sells)
			local profit = value.profit
			parts[#parts + 1] = UI.Wrap(("%s %s"):format(profit >= 0 and "profit" or "loss", ns.Alts_Gold(math.abs(profit))),
				profit >= 0 and "success" or "danger")
		end
		y = Header(H_VALUE, table.concat(parts, "  ·  ") .. "  " .. UI.Wrap(("(%s)"):format(ns.Value_SourceName()), "textMuted"), y + 4)
	end
	y = Header(H_STEPS, "Craft in order", y + 4)
	for i, step in ipairs(plan.steps) do
		local row = stepRows[i] or CreateStepRow(content)
		stepRows[i] = row
		row.num:SetText(i .. ".")
		row.text:SetText(StepText(step, i == #plan.steps and quality or nil))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + STEP_H
	end
	if not ns.Alts_HasSyndicator() then
		y = Header(H_SYNDICATOR, "Syndicator isn't loaded: only this character's bags, bank and the Warband bank are counted.", y + 4)
	end
	d.scroll:SetContentHeight(y + 8)
end

local function CreateDetail(parent)
	local d = CreateFrame("Frame", nil, parent)
	d.title = UI.Text(d, 16, "heading")
	d.title:SetPoint("TOPLEFT", 4, 0)
	d.title:SetPoint("RIGHT", -110, 0)
	d.title:SetWordWrap(false)
	d.sub = UI.Text(d, 12, "textMuted")
	d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -5)
	d.sub:SetPoint("RIGHT", -114, 0)
	d.sub:SetWordWrap(false)
	d.status = UI.Text(d, 12, "success")
	d.status:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -5)
	d.status:SetPoint("RIGHT", -114, 0)

	-- How many times to craft it: - [n] + (type a number, Enter or click away to apply).
	local MAX_CRAFTS = 999
	local crafts = CreateFrame("Frame", nil, d)
	crafts:SetSize(104, 22)
	crafts:SetPoint("TOPRIGHT", -4, 0)
	local minus = UI.Button(crafts, 22, "-")
	minus:SetHeight(22)
	minus:SetPoint("LEFT")
	local plus = UI.Button(crafts, 22, "+")
	plus:SetHeight(22)
	plus:SetPoint("RIGHT")
	local box = CreateFrame("EditBox", nil, crafts)
	box:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	box:SetPoint("RIGHT", plus, "LEFT", -4, 0)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	box:SetJustifyH("CENTER")
	UI.SetFont(box, "number", 13)
	UI.SetTextRole(box, "text")
	UI.Surface(box, 0.35)
	local function Set(n)
		S.db.crafts = math.min(math.max(math.floor(n or 1), 1), MAX_CRAFTS)
		LayoutDetail()
	end
	function crafts:SetValue(n)
		if not box:HasFocus() then
			box:SetText(tostring(n))
		end
	end
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(S.db.crafts or 1))
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, "accent", 0.8)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "frame", 0.35)
		self:HighlightText(0, 0)
		Set(tonumber(self:GetText()))
	end)
	minus:SetScript("OnClick", function()
		box:ClearFocus()
		Set((S.db.crafts or 1) - 1)
	end)
	plus:SetScript("OnClick", function()
		box:ClearFocus()
		Set((S.db.crafts or 1) + 1)
	end)
	d.crafts = crafts

	-- Crafting list: this recipe, this many times.
	local add = UI.Button(d, 104, "Add to list")
	add:SetHeight(20)
	add:SetPoint("TOPRIGHT", crafts, "BOTTOMRIGHT", 0, -4)
	add:SetScript("OnClick", function()
		box:ClearFocus()
		if S.db.selected then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			ns.AltsList_Add(S.db.selected, S.db.crafts or 1, { quality = S.db.quality, ranks = S.db.ranks })
		end
	end)
	add:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Add to the crafting list")
		GameTooltip:AddLine("Track this craft: the Crafting list tab and the tracker on screen say who needs what "
			.. "from where, and the mailbox sends it. The quality and ranks picked here go with it (and replace them "
			.. "when it's listed already).", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	add:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	d.add = add

	d.scroll = UI.Scroll(d)
	d.scroll:SetPoint("TOPLEFT", d.status, "BOTTOMLEFT", -4, -10)
	d.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
	d.content = d.scroll.content
	d.shop = ns.AltsShop_CreateLink(d.content) -- placed by LayoutDetail

	-- Quality: the first line of the detail, for recipes with more than one quality.
	local quality = CreateFrame("Frame", nil, d.content)
	quality:SetHeight(QUALITY_H)
	quality:SetPoint("TOPLEFT", 0, 0)
	quality:SetPoint("RIGHT")
	quality.label = UI.Text(quality, 12, "textMuted")
	quality.label:SetPoint("LEFT", 4, 0)
	quality.label:SetText("Quality")
	local pick = UI.Dropdown(quality, 150)
	pick:SetPoint("LEFT", quality.label, "RIGHT", 10, 0)
	pick.getValue = function()
		return ns.Alts_ClampQuality(S.db.recipes[S.db.selected], S.db.quality) or 0
	end
	pick.setValue = function(value)
		S.db.quality = value ~= 0 and value or nil
		LayoutDetail()
	end
	pick.choices = function()
		local recipe = S.db.recipes[S.db.selected]
		local list = { { value = 0, text = "Any quality" } }
		for q = 1, ns.Alts_Qualities(recipe) do
			list[#list + 1] = { value = q, text = ("%s Quality %d"):format(ns.Alts_QualityMarkup(S.db.selected, q), q) }
		end
		return list
	end
	pick:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Quality")
		GameTooltip:AddLine("The quality you mean to make. Gear and tools are compared at it (Any quality: at \"Compare "
			.. "crafts at\"), and the crafting list and tracker show it. It doesn't pick the reagents: click a material "
			.. "to choose its rank.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	pick:HookScript("OnLeave", GameTooltip_Hide)
	function quality:Refresh()
		pick:Refresh()
	end
	quality:Hide()
	d.quality = quality
	d.empty = UI.Text(d, 12, "textMuted")
	d.empty:SetPoint("TOPLEFT", 4, -4)
	d.empty:SetPoint("RIGHT", -4, 0)
	d.empty:SetWordWrap(true)
	d.empty:SetText("Pick a recipe on the left to see what it takes: the materials, how many you have and where, and who crafts what in which order.")
	return d
end

ns.AltsCraft_LayoutDetail = LayoutDetail
ns.AltsCraft_CreateDetail = CreateDetail
