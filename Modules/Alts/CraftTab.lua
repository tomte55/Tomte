local addonName, ns = ...

-- Alts page, Crafting tab: search recipes on the left (who knows each one), the selected recipe on the right as a
-- shopping list (materials: needed / have / where) and the crafts in order, crafted materials worked out through
-- other known recipes (Data.lua's plan). Item counts come from Syndicator when it's loaded (Collect.lua).

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN, RED, YELLOW = { 0.45, 0.85, 0.45 }, { 1, 0.45, 0.35 }, { 1, 0.75, 0.3 }
local LIST_W = 0.38 -- of the tab's width
local RESULT_H, MAT_H, STEP_H, HEADER_H = 22, 20, 20, 26

local tab, db
local results, resultRows, groupRows = {}, {}, {}
local matRows, stepRows, headers = {}, {}, {}
local searchText = ""
local producers -- [itemID] = recipeIDs, rebuilt when recipes change
local loading = {} -- [itemID] = true while its name loads

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function ClassName(c)
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	return color and color:WrapTextInColorCode(c.name or "?") or (c.name or "?")
end

local function Names(chars, limit)
	local parts = {}
	for i, c in ipairs(chars) do
		if i > (limit or 3) then
			parts[#parts + 1] = ("+%d"):format(#chars - i + 1)
			break
		end
		parts[#parts + 1] = ClassName(c)
	end
	return table.concat(parts, ", ")
end

-- Item names load on demand; the tab redraws once a missing one arrives.
local function ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if name then
		return name
	end
	if not loading[itemID] then
		loading[itemID] = true
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
			loading[itemID] = nil
			ns.AltsCraft_Refresh()
		end)
	end
	return ("item %d"):format(itemID)
end

-- The item's rarity color, nil until its data is loaded (ItemName starts the load and redraws).
local function QualityColor(itemID)
	if not itemID then
		return nil
	end
	local quality = C_Item.GetItemQualityByID(itemID)
	if not quality then
		ItemName(itemID)
		return nil
	end
	local r, g, b = C_Item.GetItemQualityColor(quality)
	return { r, g, b }
end

local function Hex(c)
	return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- A recipe's name in its item's rarity color (white for recipes that make no item, like enchants).
local function RecipeName(recipe)
	local name = recipe and recipe.name or "?"
	local color = recipe and QualityColor(recipe.item)
	return color and ("|c%s%s|r"):format(Hex(color), name) or name
end

local function ProfName(base)
	for _, c in pairs(db.chars) do
		local prof = c.profs and c.profs[base]
		if prof and prof.name then
			return prof.name
		end
	end
	return "?"
end

-- Results list ---------------------------------------------------------------------------------------------

-- The continent you're on, for putting its expansion's recipes first.
local function ContinentName()
	local mapID = C_Map.GetBestMapForUnit("player")
	local depth = 0
	while mapID and mapID > 0 and depth < 10 do
		local info = C_Map.GetMapInfo(mapID)
		if not info then
			return nil
		end
		if info.mapType == Enum.UIMapType.Continent then
			return info.name
		end
		mapID, depth = info.parentMapID, depth + 1
	end
	return nil
end

local function CreateResultRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(RESULT_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.06)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 28, 0)
	row.who = UI.Text(row, 11, GREY)
	row.who:SetPoint("RIGHT", -4, 0)
	row.who:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.who, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetShown(self.id == db.selected)
	end)
	row:SetScript("OnClick", function(self)
		db.selected = self.id
		db.crafts = 1
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.AltsCraft_Refresh()
	end)
	return row
end

-- Group header: profession (gold), expansion (white), category (grey); click folds it.
local HEADER_STYLE = {
	prof = { size = 13, color = GOLD, x = 2, h = 24 },
	exp = { size = 12, color = WHITE, x = 10, h = 22 },
	cat = { size = 11, color = GREY, x = 18, h = 20 },
}

local function CreateGroupRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row.toggle = UI.Text(row, 12, GREY)
	row.toggle:SetWidth(10)
	row.text = UI.Text(row, 12, WHITE)
	row.text:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)
	row.text:SetWordWrap(false)
	row.count = UI.Text(row, 11, DIM)
	row.count:SetPoint("RIGHT", -4, 0)
	row.text:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 1, 1)
	end)
	row:SetScript("OnLeave", function(self)
		local c = self.color
		self.text:SetTextColor(c[1], c[2], c[3])
	end)
	row:SetScript("OnClick", function(self)
		db.collapsed[self.key] = not self.collapsed
		PlaySound(self.collapsed and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		ns.AltsCraft_Refresh()
	end)
	return row
end

local function SetResultRow(row, r)
	row.id = r.id
	row.icon:SetTexture(r.recipe.icon or 134400)
	row.name:SetText(r.recipe.name or ("recipe " .. r.id))
	-- Rarity color; recipes nobody knows yet are dimmed.
	local quality = QualityColor(r.recipe.item) or WHITE
	if r.status == "known" then
		row.who:SetText(Names(r.who, 1))
		SetColor(row.who, GREY)
		row.name:SetTextColor(quality[1], quality[2], quality[3], 1)
	elseif r.status == "learnable" then
		row.who:SetText("learnable")
		SetColor(row.who, GREY)
		row.name:SetTextColor(quality[1], quality[2], quality[3], 0.5)
	else
		row.who:SetText("no one")
		SetColor(row.who, RED)
		row.name:SetTextColor(quality[1], quality[2], quality[3], 0.3)
	end
	row.bg:SetShown(r.id == db.selected)
end

-- "Only what we have materials for": recipes whose whole plan is covered and known. Counts are shared between
-- recipes during one pass (the same reagent is looked up once).
local function HaveMaterials(list)
	local counts = {}
	local ctx = {
		recipes = db.recipes, chars = db.chars, producers = producers,
		maxDepth = db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
		count = function(items)
			local key = table.concat(items, ",")
			if not counts[key] then
				counts[key] = (ns.Alts_Have(items))
			end
			return counts[key]
		end,
	}
	local kept = {}
	for _, r in ipairs(list) do
		local ok, plan = pcall(ns.Alts_Plan, r.id, 1, ctx)
		if ok and plan.missing == 0 and plan.unknown == 0 then
			kept[#kept + 1] = r
		end
	end
	return kept
end

-- /tomte alts why <recipe>: why "Materials on hand" keeps or drops a recipe (each material: need, have and where).
function ns.AltsCraft_Why(text)
	text = strtrim(text or ""):lower()
	if text == "" then
		ns.Print("usage: /tomte alts why <part of a recipe name>")
		return
	end
	db = db or ns.altsDB -- set when the tab is first built; the command can come before that
	producers = producers or ns.Alts_Producers(db.recipes)
	local found = ns.Alts_Search(db.recipes, db.chars, { text = text, learnable = true }, 3)
	if #found == 0 then
		ns.Print("no recipe matches \"" .. text .. "\".")
		return
	end
	ns.Print(("Syndicator %s."):format(ns.Alts_HasSyndicator() and "is counting" or "isn't loaded or ready: only this character and the Warband bank"))
	for _, r in ipairs(found) do
		local ok, plan = pcall(ns.Alts_Plan, r.id, 1, {
			recipes = db.recipes, chars = db.chars, producers = producers,
			maxDepth = db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
			count = function(items)
				return (ns.Alts_Have(items))
			end,
		})
		if not ok then
			ns.Print(("%s: plan error %s"):format(r.recipe.name or r.id, tostring(plan)))
		else
			local kept = plan.missing == 0 and plan.unknown == 0
			ns.Print(("%s: %s (missing %d, steps nobody knows %d)"):format(r.recipe.name or r.id,
				kept and "|cff73d973kept|r" or "|cffff7359dropped|r", plan.missing, plan.unknown))
			for _, m in ipairs(plan.materials) do
				local _, where = ns.Alts_Have(m.items)
				local parts = {}
				for _, w in ipairs(where) do
					parts[#parts + 1] = ("%s %d"):format(w.name, w.n)
				end
				ns.Print(("   %s: need %d, have %d%s%s"):format(C_Item.GetItemNameByID(m.items[1]) or ("item " .. m.items[1]),
					m.need, m.have, m.missing > 0 and (", |cffff7359missing %d|r"):format(m.missing) or "",
					#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
			end
			for _, step in ipairs(plan.steps) do
				if #step.crafters == 0 then
					ns.Print(("   nobody knows %s"):format(db.recipes[step.recipeID] and db.recipes[step.recipeID].name or step.recipeID))
				end
			end
		end
	end
end

-- An expansion skill line's name ("Dragon Isles Blacksmithing"), for recipes read before names were stored.
local lineNames = {}
local function LineName(recipe)
	local line = recipe.line
	if not line then
		return nil
	end
	if lineNames[line] == nil then
		local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(line)
		lineNames[line] = info and info.professionName and info.professionName ~= "" and info.professionName or false
	end
	return lineNames[line] or nil
end

-- Every group key in the current list, for collapse all / expand all.
local function SetAllCollapsed(collapsed)
	local rows = ns.Alts_Group(results, {
		profName = ProfName, current = function()
			return false
		end, lineName = LineName, collapsed = {}, expand = true,
	})
	for _, row in ipairs(rows) do
		if row.kind ~= "recipe" then
			db.collapsed[row.key] = collapsed
		end
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	ns.AltsCraft_Refresh()
end

local function LayoutResults()
	local content = tab.list.content
	results = ns.Alts_Search(db.recipes, db.chars, {
		text = searchText,
		char = db.filterChar ~= "all" and db.filterChar or nil,
		base = db.filterProf ~= "all" and db.filterProf or nil,
		learnable = db.filterShow ~= "known",
	})
	if db.haveMats then
		results = HaveMaterials(results)
	end
	local continent = ContinentName()
	local rows = ns.Alts_Group(results, {
		profName = ProfName,
		current = function(recipe)
			return ns.Alts_LineInContinent(recipe.lineName, continent)
		end,
		lineName = LineName,
		collapsed = db.collapsed,
		expand = searchText ~= "",
	})
	local y, nResult, nGroup = 0, 0, 0
	for _, item in ipairs(rows) do
		local row
		if item.kind == "recipe" then
			nResult = nResult + 1
			row = resultRows[nResult] or CreateResultRow(content)
			resultRows[nResult] = row
			SetResultRow(row, item.result)
		else
			nGroup = nGroup + 1
			row = groupRows[nGroup] or CreateGroupRow(content)
			groupRows[nGroup] = row
			local style = HEADER_STYLE[item.kind]
			row.key, row.collapsed, row.color = item.key, item.collapsed, style.color
			row:SetHeight(style.h)
			row.toggle:ClearAllPoints()
			row.toggle:SetPoint("LEFT", style.x, 0)
			row.toggle:SetText(searchText ~= "" and "" or (item.collapsed and "+" or "-"))
			row.text:SetFont(STANDARD_TEXT_FONT, style.size, "")
			row.text:SetText(item.text)
			SetColor(row.text, style.color)
			row.count:SetText(item.count)
			row:SetEnabled(searchText == "")
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + row:GetHeight()
	end
	for i = nResult + 1, #resultRows do
		resultRows[i]:Hide()
	end
	for i = nGroup + 1, #groupRows do
		groupRows[i]:Hide()
	end
	tab.list:SetContentHeight(y)
	if next(db.recipes) == nil then
		tab.hint:SetText("No recipes yet. Log in on each crafter and open their profession window once; Tomte reads the recipes from there.")
	elseif #results == 0 then
		tab.hint:SetText(db.haveMats and "Nothing here can be made with what the account has." or "No recipe matches.")
	else
		tab.hint:SetText("")
	end
	tab.hint:SetShown(tab.hint:GetText() ~= "")
end

-- Filters --------------------------------------------------------------------------------------------------

local function CharChoices()
	local list = { { value = "all", text = "All characters" } }
	for _, c in ipairs(ns.Alts_Roster(db.chars, "name", nil)) do
		if next(c.profs or {}) then
			list[#list + 1] = { value = c.guid, text = c.name or "?" }
		end
	end
	return list
end

local function ProfChoices()
	local list = { { value = "all", text = "All professions" } }
	local seen = {}
	for _, r in pairs(db.recipes) do
		if r.base and not seen[r.base] then
			seen[r.base] = true
			list[#list + 1] = { value = r.base, text = ProfName(r.base) }
		end
	end
	table.sort(list, function(a, b)
		if a.value == "all" or b.value == "all" then
			return a.value == "all"
		end
		return a.text < b.text
	end)
	return list
end

local function Filter(parent, key, choices)
	local d = UI.Dropdown(parent, 120)
	d.getValue = function()
		return db[key]
	end
	d.setValue = function(value)
		db[key] = value
		LayoutResults()
	end
	d.choices = choices
	return d
end

local function CreateFilters(frame)
	frame.filters = {
		Filter(frame, "filterChar", CharChoices),
		Filter(frame, "filterProf", ProfChoices),
		Filter(frame, "filterShow", function()
			return { { value = "learnable", text = "Known + learnable" }, { value = "known", text = "Known only" } }
		end),
	}
	frame.filters[1]:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", 0, -8)
	frame.filters[2]:SetPoint("LEFT", frame.filters[1], "RIGHT", 6, 0)
	frame.filters[3]:SetPoint("LEFT", frame.filters[2], "RIGHT", 6, 0)
	local have = CreateFrame("Button", nil, frame)
	have:SetSize(260, 20)
	have:SetPoint("TOPLEFT", frame.filters[1], "BOTTOMLEFT", 0, -8)
	have.check = UI.Checkbox(have)
	have.check:SetPoint("LEFT", 2, 0)
	have.label = UI.Text(have, 12, WHITE)
	have.label:SetPoint("LEFT", have.check, "RIGHT", 8, 0)
	have.label:SetText("Materials on hand")
	have:SetWidth(have.label:GetStringWidth() + 30)
	local function Tip()
		GameTooltip:SetOwner(have, "ANCHOR_RIGHT")
		GameTooltip:SetText("Materials on hand", 1, 1, 1)
		GameTooltip:AddLine("Only recipes the account can make right now: every material is on one of your characters "
			.. "or in the Warband bank (or can be crafted from what is), and somebody knows each recipe on the way.",
			nil, nil, nil, true)
		GameTooltip:Show()
	end
	have:SetScript("OnEnter", Tip)
	have:SetScript("OnLeave", GameTooltip_Hide)
	have.check:HookScript("OnEnter", Tip)
	have.check:HookScript("OnLeave", GameTooltip_Hide)
	have.check.onChange = function(checked)
		db.haveMats = checked
		LayoutResults()
	end
	have:SetScript("OnClick", function()
		have.check:Click()
	end)
	frame.haveMats = have
	frame.expandAll = UI.Button(frame, 78, "Expand all")
	frame.collapseAll = UI.Button(frame, 78, "Collapse all")
	frame.expandAll:SetScript("OnClick", function()
		SetAllCollapsed(false)
	end)
	frame.collapseAll:SetScript("OnClick", function()
		SetAllCollapsed(true)
	end)
end

local function RefreshFilters()
	for _, d in ipairs(tab.filters) do
		-- A saved character or profession that's gone falls back to all.
		local found = false
		for _, choice in ipairs(d.choices()) do
			if choice.value == d.getValue() then
				found = true
			end
		end
		if not found then
			d.setValue("all")
		end
		d:Refresh()
	end
	tab.haveMats.check:SetChecked(db.haveMats)
end

-- Auctionator shopping list ----------------------------------------------------------------------------------

-- Auctionator.API.v1 (Auctionator 340, Source/API/v1/ShoppingLists.lua): CreateShoppingList(callerID, name,
-- searchStrings) replaces a list of the same name; ConvertToSearchString(callerID, { searchString, isExact,
-- quantity }) makes each entry.
local CALLER = "Tomte"

local function ShoppingAPI()
	local a = _G.Auctionator
	local api = a and type(a.API) == "table" and a.API.v1
	if type(api) == "table" and type(api.CreateShoppingList) == "function" and type(api.ConvertToSearchString) == "function" then
		return api
	end
	return nil
end

-- Makes (or replaces) the Auctionator shopping list `name` with one exact search per item ({ itemID, qty }).
local function MakeShoppingList(name, items)
	local api = ShoppingAPI()
	if not api then
		ns.Print("Auctionator isn't loaded.")
		return
	end
	local strings, loadingNames = {}, 0
	for _, it in ipairs(items) do
		local itemName = C_Item.GetItemNameByID(it.itemID)
		if itemName then
			strings[#strings + 1] = { searchString = itemName, isExact = true, quantity = it.qty }
		else
			loadingNames = loadingNames + 1
			C_Item.RequestLoadItemDataByID(it.itemID)
		end
	end
	if loadingNames > 0 then
		ns.Print(("%d item name%s still loading: click Shopping list again in a moment."):format(loadingNames,
			loadingNames == 1 and " is" or "s are"))
		return
	end
	local ok, err = pcall(function()
		for i, term in ipairs(strings) do
			strings[i] = api.ConvertToSearchString(CALLER, term)
		end
		api.CreateShoppingList(CALLER, name, strings)
	end)
	if not ok then
		ns.Print("Auctionator couldn't make the list: " .. tostring(err))
		return
	end
	ns.Print(("Auctionator list '%s' (%d item%s). It's in the Shopping tab at the Auction House."):format(name, #strings,
		#strings == 1 and "" or "s"))
end

-- A "Shopping list" link (Crafting tab and Crafting list tab headings). link:Set(listName, items) shows it when
-- Auctionator is loaded and something is missing.
function ns.AltsShop_CreateLink(parent)
	local link = CreateFrame("Button", nil, parent)
	link:SetHeight(16)
	link.text = UI.Text(link, 12, GOLD)
	link.text:SetPoint("RIGHT")
	link.text:SetText("Shopping list")
	link:SetWidth(link.text:GetStringWidth())
	link:SetScript("OnEnter", function(self)
		SetColor(self.text, WHITE)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Auctionator shopping list")
		GameTooltip:AddLine(("Makes the list \"%s\" with the %d missing material%s and how many, replacing an older one "
			.. "of that name."):format(self.listName, #self.items, #self.items == 1 and "" or "s"), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	link:SetScript("OnLeave", function(self)
		SetColor(self.text, GOLD)
		GameTooltip:Hide()
	end)
	link:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		MakeShoppingList(self.listName, self.items)
	end)
	function link:Set(listName, items)
		self.listName, self.items = listName, items
		self:SetShown(#items > 0 and ShoppingAPI() ~= nil)
	end
	link:Hide()
	return link
end

-- Detail ---------------------------------------------------------------------------------------------------

local function Header(i, text, y)
	local fs = headers[i]
	if not fs then
		fs = UI.Text(tab.detail.content, 11, GREY)
		headers[i] = fs
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 4, -(y + 10))
	fs:Show()
	return y + HEADER_H
end

local function CreateMatRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(MAT_H)
	row:EnableMouse(true)
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWidth(170)
	row.name:SetWordWrap(false)
	row.count = UI.Text(row, 12, WHITE)
	row.count:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.count:SetWidth(70)
	row.count:SetJustifyH("RIGHT")
	row.where = UI.Text(row, 11, GREY)
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
			GameTooltip:AddLine(("Worth %s each, %s for %d"):format(ns.Value_Text(unit, stale), ns.Value_Text(unit * self.need, stale),
				self.need), 1, 0.82, 0.45)
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
	row.num = UI.Text(row, 12, GOLD)
	row.num:SetPoint("LEFT", 4, 0)
	row.num:SetWidth(18)
	row.text = UI.Text(row, 12, WHITE)
	row.text:SetPoint("LEFT", row.num, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetWordWrap(false)
	return row
end

-- "Tommorah 5, Warband bank 1": names in class color (the Warband bank in blue-grey), counts in white.
local function WhereText(list, limit)
	local parts = {}
	for i, w in ipairs(list) do
		if i > limit then
			parts[#parts + 1] = "|cff9e9e9e...|r"
			break
		end
		local color = w.class and C_ClassColor.GetClassColor(w.class)
		local name = color and color:WrapTextInColorCode(w.name) or ("|cff8fa8c0%s|r"):format(w.name)
		parts[#parts + 1] = ("%s |cffffffff%d|r"):format(name, w.n)
	end
	return table.concat(parts, "  ")
end

local function StepText(step)
	local recipe = db.recipes[step.recipeID]
	local what = ("%dx %s"):format(step.crafts, RecipeName(recipe))
	if #step.crafters > 0 then
		return ("%s crafts %s"):format(Names(step.crafters, 2), what)
	elseif #step.learnable > 0 then
		return ("|cffff7359nobody knows|r %s |cff9e9e9e(learnable: %s)|r"):format(what, Names(step.learnable, 2))
	end
	return ("|cffff7359nobody can make|r %s"):format(what)
end

local function LayoutDetail()
	local d = tab.detail
	for _, list in ipairs({ matRows, stepRows, headers }) do
		for _, row in ipairs(list) do
			row:Hide()
		end
	end
	d.shop:Hide()
	local recipe = db.selected and db.recipes[db.selected]
	d.empty:SetShown(not recipe)
	d.title:SetShown(recipe ~= nil)
	d.sub:SetShown(recipe ~= nil)
	d.status:SetShown(recipe ~= nil)
	d.crafts:SetShown(recipe ~= nil)
	d.add:SetShown(recipe ~= nil)
	if not recipe then
		d.scroll:SetContentHeight(1)
		return
	end
	d.title:SetText(recipe.name or "?")
	SetColor(d.title, QualityColor(recipe.item) or GOLD)
	local status, who = ns.Alts_RecipeStatus(db.chars, recipe, db.selected)
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
	end, db.selected, db.crafts or 1, {
		recipes = db.recipes, chars = db.chars, producers = producers,
		maxDepth = db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
		count = function(items)
			return (ns.Alts_Have(items))
		end,
	})
	if not ok then
		d.status:SetText("Couldn't work out the materials (the error is in BugSack).")
		SetColor(d.status, RED)
		d.crafts:SetValue(db.crafts or 1)
		d.scroll:SetContentHeight(1)
		return
	end
	ns.AltsCraft_LastPlan = plan -- Send to alt: materials go to the crafter of their step
	if plan.missing > 0 then
		d.status:SetText(("Missing %d material%s"):format(plan.missing, plan.missing == 1 and "" or "s"))
		SetColor(d.status, RED)
	elseif plan.unknown > 0 then
		d.status:SetText("You have the materials, but a recipe on the way isn't known yet")
		SetColor(d.status, YELLOW)
	elseif #plan.steps > 1 then
		d.status:SetText(("Everything's there: %d crafts"):format(#plan.steps))
		SetColor(d.status, GREEN)
	else
		d.status:SetText("Everything's there")
		SetColor(d.status, GREEN)
	end
	d.crafts:SetValue(db.crafts or 1)

	local content = d.content
	local y = Header(1, "Materials (have / need)", 0)
	d.shop:Set("Tomte: " .. (recipe.name or "?"), ns.Alts_ShoppingItems(plan, db.chain))
	for i, m in ipairs(plan.materials) do
		local row = matRows[i] or CreateMatRow(content)
		matRows[i] = row
		local itemID = m.items[1]
		row.itemID, row.need = itemID, m.need
		row.name:SetText(ItemName(itemID))
		row.count:SetText(("%d / %d"):format(m.have, m.need))
		local _, where = ns.Alts_Have(m.items)
		row.whereFull = #where > 0 and WhereText(where, 20) or nil
		SetColor(row.name, QualityColor(itemID) or WHITE)
		if m.missing > 0 then
			SetColor(row.count, RED)
			row.where:SetText(("|cffff7359missing %d|r   %s"):format(m.missing, WhereText(where, 3)))
		elseif m.crafted then
			SetColor(row.count, YELLOW)
			row.where:SetText(("craft the rest: %s"):format(RecipeName(db.recipes[m.crafted])))
		else
			SetColor(row.count, GREEN)
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
	local value = ns.Value_Plan and ns.Value_Plan(plan, recipe, db.crafts or 1)
	if value then
		local parts = { ("Materials %s%s"):format(value.complete and "" or "at least ", ns.Alts_Gold(value.cost)) }
		if value.sells then
			parts[#parts + 1] = "sells for " .. ns.Alts_Gold(value.sells)
			local profit = value.profit
			parts[#parts + 1] = ("|cff%s%s %s|r"):format(profit >= 0 and "73d973" or "ff7359", profit >= 0 and "profit" or "loss",
				ns.Alts_Gold(math.abs(profit)))
		end
		y = Header(4, table.concat(parts, "  ·  ") .. ("  |cff9e9e9e(%s)|r"):format(ns.Value_SourceName()), y + 4)
	end
	y = Header(2, "Craft in order", y + 4)
	for i, step in ipairs(plan.steps) do
		local row = stepRows[i] or CreateStepRow(content)
		stepRows[i] = row
		row.num:SetText(i .. ".")
		row.text:SetText(StepText(step))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + STEP_H
	end
	if not ns.Alts_HasSyndicator() then
		y = Header(3, "Syndicator isn't loaded: only this character's bags, bank and the Warband bank are counted.", y + 4)
	end
	d.scroll:SetContentHeight(y + 8)
end

-- Build ----------------------------------------------------------------------------------------------------

local function CreateSearch(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	box:SetFont(STANDARD_TEXT_FONT, 12, "")
	box:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	box:SetTextInsets(8, 8, 0, 0)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, GOLD[1], GOLD[2], GOLD[3], 0.35)
	local placeholder = UI.Text(box, 12, DIM)
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search recipes")
	local refresh = UI.Debounce(UI.SEARCH_DELAY, function()
		LayoutResults()
	end)
	box:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		searchText = strtrim(self:GetText()):lower()
		refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function CreateDetail(parent)
	local d = CreateFrame("Frame", nil, parent)
	d.title = UI.Text(d, 16, GOLD)
	d.title:SetPoint("TOPLEFT", 4, 0)
	d.title:SetPoint("RIGHT", -110, 0)
	d.title:SetWordWrap(false)
	d.sub = UI.Text(d, 12, GREY)
	d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -5)
	d.sub:SetPoint("RIGHT", -114, 0)
	d.sub:SetWordWrap(false)
	d.status = UI.Text(d, 12, GREEN)
	d.status:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -5)
	d.status:SetPoint("RIGHT", -114, 0)

	-- How many times to craft it: - x1 +
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
	box:SetFont(STANDARD_TEXT_FONT, 13, "")
	box:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	local boxBg = box:CreateTexture(nil, "BACKGROUND")
	boxBg:SetAllPoints()
	boxBg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, GOLD[1], GOLD[2], GOLD[3], 0.35)
	local function Set(n)
		db.crafts = math.min(math.max(math.floor(n or 1), 1), MAX_CRAFTS)
		LayoutDetail()
	end
	function crafts:SetValue(n)
		if not box:HasFocus() then
			box:SetText(tostring(n))
		end
	end
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(db.crafts or 1))
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.8)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.35)
		self:HighlightText(0, 0)
		Set(tonumber(self:GetText()))
	end)
	minus:SetScript("OnClick", function()
		box:ClearFocus()
		Set((db.crafts or 1) - 1)
	end)
	plus:SetScript("OnClick", function()
		box:ClearFocus()
		Set((db.crafts or 1) + 1)
	end)
	d.crafts = crafts

	-- Crafting list: this recipe, this many times.
	local add = UI.Button(d, 104, "Add to list")
	add:SetHeight(20)
	add:SetPoint("TOPRIGHT", crafts, "BOTTOMRIGHT", 0, -4)
	add:SetScript("OnClick", function()
		box:ClearFocus()
		if db.selected then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			ns.AltsList_Add(db.selected, db.crafts or 1)
		end
	end)
	add:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Add to the crafting list")
		GameTooltip:AddLine("Track this craft: the Crafting list tab and the tracker on screen say who needs what "
			.. "from where, and the mailbox sends it.", 1, 1, 1, true)
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
	d.shop = ns.AltsShop_CreateLink(d.content) -- on the materials heading's line
	d.shop:SetPoint("TOPRIGHT", -4, -8)
	d.empty = UI.Text(d, 12, GREY)
	d.empty:SetPoint("TOPLEFT", 4, -4)
	d.empty:SetPoint("RIGHT", -4, 0)
	d.empty:SetWordWrap(true)
	d.empty:SetText("Pick a recipe on the left to see what it takes: the materials, how many you have and where, and who crafts what in which order.")
	return d
end

function ns.AltsCraft_Create(frame, altsDB)
	tab, db = frame, altsDB
	tab.search = CreateSearch(tab)
	tab.search:SetPoint("TOPLEFT", 4, -4)
	CreateFilters(tab)
	tab.list = UI.Scroll(tab)
	tab.list:SetPoint("TOPLEFT", tab.haveMats, "BOTTOMLEFT", -4, -8)
	tab.list:SetPoint("BOTTOMLEFT", 0, 0)
	tab.hint = UI.Text(tab, 12, GREY)
	tab.hint:SetPoint("TOPLEFT", tab.haveMats, "BOTTOMLEFT", 0, -12)
	tab.hint:SetPoint("RIGHT", tab.search, "RIGHT")
	tab.hint:SetWordWrap(true)
	local divider = UI.VLine(tab)
	tab.detail = CreateDetail(tab)
	tab:SetScript("OnSizeChanged", function(self, width)
		local listW = math.floor(width * LIST_W)
		self.search:SetWidth(listW - 8)
		local third = math.floor((listW - 8 - 12) / 3)
		for _, d in ipairs(self.filters) do
			d:SetWidth(third)
		end
		-- Collapse all / Expand all at the right end of the materials row.
		self.collapseAll:ClearAllPoints()
		self.collapseAll:SetPoint("RIGHT", self, "LEFT", listW - 8, 0)
		self.collapseAll:SetPoint("TOP", self.haveMats, "TOP", 0, 0)
		self.expandAll:ClearAllPoints()
		self.expandAll:SetPoint("RIGHT", self.collapseAll, "LEFT", -6, 0)
		self.list:SetPoint("RIGHT", self, "LEFT", listW - 8, 0)
		divider:ClearAllPoints()
		divider:SetPoint("TOP", self, "TOPLEFT", listW + 4, -4)
		divider:SetPoint("BOTTOM", self, "BOTTOMLEFT", listW + 4, 4)
		self.detail:ClearAllPoints()
		self.detail:SetPoint("TOPLEFT", listW + 16, -4)
		self.detail:SetPoint("BOTTOMRIGHT")
	end)
end

-- The recipe index changed (a scan finished, a recipe was learned).
function ns.AltsCraft_RecipesChanged()
	producers = nil
end

function ns.AltsCraft_Refresh()
	if not (tab and tab:IsVisible()) then
		return
	end
	producers = producers or ns.Alts_Producers(db.recipes)
	RefreshFilters()
	LayoutResults()
	LayoutDetail()
end
