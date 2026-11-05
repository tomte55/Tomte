local addonName, ns = ...

-- Alts page, Crafting tab: the search box, the filters and the grouped recipe list on the left. CraftTab.lua has the
-- shared helpers and entry points; CraftGear.lua and CraftMats.lua feed the "Gear for" and "Materials on hand"
-- filters; CraftDetail.lua draws the selected recipe.

local S = ns.AltsCraft_State
local UI = ns.UI
local RESULT_H = 22
local SEARCH_ROWS = 200 -- rows drawn at most while searching (every group is open then)

local results, resultRows, groupRows = {}, {}, {}
local searchText = ""

local SetColor, ClassName, Names = ns.AltsCraft_SetColor, ns.AltsCraft_ClassName, ns.AltsCraft_Names -- CraftTab.lua
local QualityColor, RecipeName, ProfName = ns.AltsCraft_QualityColor, ns.AltsCraft_RecipeName, ns.AltsCraft_ProfName
local ForChar, CompareQuality, ForInfo = ns.AltsCraft_ForChar, ns.AltsCraft_CompareQuality, ns.AltsCraft_ForInfo -- CraftGear.lua
local MarkText, ForText = ns.AltsCraft_MarkText, ns.AltsCraft_ForText
local HaveMaterials = ns.AltsCraft_HaveMaterials -- CraftMats.lua

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
	row.bg:SetColorTexture(UI.Color("hover"))
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 28, 0)
	row.who = UI.Text(row, 11, "textMuted")
	row.who:SetPoint("RIGHT", -4, 0)
	row.who:SetJustifyH("RIGHT")
	row.mark = UI.Text(row, 11, "text", "number")
	row.mark:SetPoint("RIGHT", row.who, "LEFT", -6, 0)
	row.mark:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.mark, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		local c = ForChar()
		local recipe = S.db.recipes[self.id]
		if c and recipe and self.forInfo then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(RecipeName(recipe))
			local hr, hg, hb = UI.Color("heading")
			GameTooltip:AddLine(("For %s"):format(ClassName(c)), hr, hg, hb)
			GameTooltip:AddLine(ForText(self.forInfo, c, recipe), 1, 1, 1, true)
			if self.forInfo.mark then
				local r, g, b = UI.Color("textMuted")
				GameTooltip:AddLine("Item level only, without optional reagents (they can raise it). Stats, effects and set "
					.. "bonuses aren't compared.", r, g, b, true)
			end
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetShown(self.id == S.db.selected)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		S.db.selected = self.id
		S.db.crafts, S.db.quality, S.db.ranks = 1, nil, nil
		UI.Sound("pick")
		ns.AltsCraft_Refresh()
	end)
	return row
end

-- Group header: profession (heading), expansion (text), category (muted); click folds it.
local HEADER_STYLE = {
	prof = { size = 13, color = "heading", x = 2, h = 24 },
	exp = { size = 12, color = "text", x = 10, h = 22 },
	cat = { size = 11, color = "textMuted", x = 18, h = 20 },
}

local function CreateGroupRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row.toggle = UI.Text(row, 12, "textMuted")
	row.toggle:SetWidth(10)
	row.text = UI.Text(row, 12, "text")
	row.text:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)
	row.text:SetWordWrap(false)
	row.count = UI.Text(row, 11, "textFaint", "number")
	row.count:SetPoint("RIGHT", -4, 0)
	row.text:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.text, "text")
	end)
	row:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.text, self.color)
	end)
	row:SetScript("OnClick", function(self)
		S.db.collapsed[self.key] = not self.collapsed
		UI.Sound(self.collapsed and "on" or "off")
		ns.AltsCraft_Refresh()
	end)
	return row
end

local function SetResultRow(row, r)
	row.id, row.forInfo = r.id, r.forInfo
	row.mark:SetText(MarkText(r.forInfo))
	row.icon:SetTexture(r.recipe.icon or 134400)
	row.name:SetText(r.recipe.name or ("recipe " .. r.id))
	-- Rarity color; recipes nobody knows yet are dimmed.
	local quality = QualityColor(r.recipe.item) or "text"
	if r.status == "known" then
		row.who:SetText(Names(r.who, 1))
		SetColor(row.who, "textMuted")
		row.name:SetTextColor(UI.RGBA(quality, 1))
	elseif r.status == "learnable" then
		row.who:SetText("learnable")
		SetColor(row.who, "textMuted")
		row.name:SetTextColor(UI.RGBA(quality, 0.5))
	else
		row.who:SetText("no one")
		SetColor(row.who, "danger")
		row.name:SetTextColor(UI.RGBA(quality, 0.3))
	end
	row.bg:SetShown(r.id == S.db.selected)
	-- Redrawn under the mouse (item levels that were loading arrived): the open tooltip follows.
	if GameTooltip:IsOwned(row) then
		row:GetScript("OnEnter")(row)
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
			S.db.collapsed[row.key] = collapsed
		end
	end
	UI.Sound(collapsed and "off" or "on")
	ns.AltsCraft_Refresh()
end

local function LayoutResults()
	local content = S.tab.list.content
	results = ns.Alts_Search(S.db.recipes, S.db.chars, {
		text = searchText,
		char = S.db.filterChar ~= "all" and S.db.filterChar or nil,
		base = S.db.filterProf ~= "all" and S.db.filterProf or nil,
		learnable = S.db.filterShow ~= "known",
	})
	local forChar = ForChar()
	if forChar then
		local kept = {}
		for _, r in ipairs(results) do
			r.forInfo = ForInfo(r.recipe, forChar, CompareQuality())
			if r.forInfo then
				kept[#kept + 1] = r
			end
		end
		results = kept
	end
	if S.db.haveMats then
		results = HaveMaterials(results)
	end
	local continent = ContinentName()
	local rows = ns.Alts_Group(results, {
		profName = ProfName,
		current = function(recipe)
			return ns.Alts_LineInContinent(recipe.lineName, continent)
		end,
		lineName = LineName,
		collapsed = S.db.collapsed,
		expand = searchText ~= "",
	})
	local y, nResult, nGroup, more = 0, 0, 0, 0
	for i, item in ipairs(rows) do
		local row
		local drawn = nResult + nGroup
		if searchText ~= "" and (drawn >= SEARCH_ROWS or item.kind ~= "recipe" and drawn >= SEARCH_ROWS - 3) then
			-- A short search opens every group: thousands of rows. Draw the first ones and say how many are left
			-- (no group heading right at the end with nothing under it).
			for j = i, #rows do
				more = more + (rows[j].kind == "recipe" and 1 or 0)
			end
			break
		elseif item.kind == "recipe" then
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
			UI.SetFont(row.text, "body", style.size)
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
	if more > 0 then
		S.tab.more = S.tab.more or UI.Text(content, 12, "textMuted")
		S.tab.more:ClearAllPoints()
		S.tab.more:SetPoint("TOPLEFT", 6, -(y + 6))
		S.tab.more:SetText(("%d more: type more to narrow the search."):format(more))
		y = y + 26
	end
	if S.tab.more then
		S.tab.more:SetShown(more > 0)
	end
	S.tab.list:SetContentHeight(y)
	if next(S.db.recipes) == nil then
		S.tab.hint:SetText("No recipes yet. Log in on each crafter and open their profession window once; Tomte reads the recipes from there.")
	elseif #results == 0 then
		S.tab.hint:SetText(S.db.haveMats and "Nothing here can be made with what the account has."
			or forChar and ("No recipe makes gear %s can use. Characters' recipes are read when they open their profession window."):format(forChar.name or "?")
			or "No recipe matches.")
	else
		S.tab.hint:SetText("")
	end
	S.tab.hint:SetShown(S.tab.hint:GetText() ~= "")
end

-- Filters --------------------------------------------------------------------------------------------------

local function CharChoices()
	local list = { { value = "all", text = "All characters" } }
	for _, c in ipairs(ns.Alts_Roster(S.db.chars, "name", nil)) do
		if next(c.profs or {}) then
			list[#list + 1] = { value = c.guid, text = c.name or "?" }
		end
	end
	return list
end

local function ProfChoices()
	local list = { { value = "all", text = "All professions" } }
	local seen = {}
	for _, r in pairs(S.db.recipes) do
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

-- "Gear for": anyone, the character you're on (follows whoever is logged in), or one character.
local function ForChoices()
	local me = UnitGUID("player")
	local mine = S.db.chars[me]
	local list = {
		{ value = "all", text = "Gear for: anyone" },
		{ value = "me", text = ("Gear for: you (%s)"):format(mine and mine.name or "this character") },
	}
	for _, c in ipairs(ns.Alts_Roster(S.db.chars, "name", nil)) do
		if c.guid ~= me and c.class then
			list[#list + 1] = { value = c.guid, text = "Gear for: " .. (c.name or "?") }
		end
	end
	return list
end

local function Filter(parent, key, choices)
	local d = UI.Dropdown(parent, 120)
	d.getValue = function()
		return S.db[key]
	end
	d.setValue = function(value)
		S.db[key] = value
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
	frame.forFilter = Filter(frame, "filterFor", ForChoices)
	frame.forFilter.setValue = function(value)
		S.db.filterFor = value
		ns.AltsCraft_Refresh() -- the detail says what the craft means for them too
	end
	frame.forFilter:SetPoint("TOPLEFT", frame.filters[1], "BOTTOMLEFT", 0, -6)
	frame.forFilter:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Gear for")
		GameTooltip:AddLine("Only what that character can use: armor of their type, weapons their class equips and cloaks, "
			.. "rings, necks and trinkets with their main stat, plus tools and accessories for their professions. Each row "
			.. "says how its item level compares with what they wear: green +n is an upgrade at every quality, yellow +n "
			.. "only at the higher qualities, new fills an empty slot, - isn't an upgrade. With a quality picked under "
			.. "\"Compare crafts at\" (Profession gear tab or Settings), at that quality.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame.forFilter:HookScript("OnLeave", GameTooltip_Hide)
	local have = CreateFrame("Button", nil, frame)
	have:SetSize(260, 20)
	have:SetPoint("TOPLEFT", frame.forFilter, "BOTTOMLEFT", 0, -8)
	have.check = UI.Checkbox(have)
	have.check:SetPoint("LEFT", 2, 0)
	have.label = UI.Text(have, 12, "text")
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
		S.db.haveMats = checked
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
	for _, d in ipairs(S.tab.filters) do
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
	local forOK = false
	for _, choice in ipairs(ForChoices()) do
		forOK = forOK or choice.value == S.db.filterFor
	end
	if not forOK then
		S.db.filterFor = "all"
	end
	S.tab.forFilter:Refresh()
	S.tab.haveMats.check:SetChecked(S.db.haveMats)
end

-- Search ---------------------------------------------------------------------------------------------------

local function CreateSearch(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	UI.SearchBoxClear(box)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.35)
	local placeholder = UI.Text(box, 12, "textFaint")
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

ns.AltsCraft_LayoutResults = LayoutResults
ns.AltsCraft_CreateFilters = CreateFilters
ns.AltsCraft_RefreshFilters = RefreshFilters
ns.AltsCraft_CreateSearch = CreateSearch
