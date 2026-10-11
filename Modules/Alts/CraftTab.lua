local addonName, ns = ...

-- Alts page, Crafting tab: search recipes on the left (who knows each one), the selected recipe on the right as a
-- shopping list (materials: needed / have / where) and the crafts in order, crafted materials worked out through
-- other known recipes (Data.lua's plan). Item counts come from Syndicator when it's loaded (Collect.lua).
-- This file holds the state and helpers the tab's files share and the entry points the page calls; the rest is in
-- CraftGear.lua (gear for a character), CraftMats.lua (materials on hand, /tomte alts why), CraftResults.lua (search,
-- filters, list), Shop.lua (the Auctionator shopping list link) and CraftDetail.lua (the selected recipe).

local UI = ns.UI
local LIST_W = 0.38 -- of the tab's width

-- The tab's mutable state, shared with the other Craft files: tab (the frame), db (Alts' saved data) and producers
-- ([itemID] = recipeIDs, rebuilt when recipes change).
local S = {}
ns.AltsCraft_State = S

local loading = {} -- [itemID] = true while its name loads

-- c: a theme role, or an { r, g, b } table for item quality colors.
local function SetColor(fs, c)
	fs:SetTextColor(UI.RGBA(c))
end

local function ClassName(c)
	return UI.ClassColored(c.name or "?", c.class)
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

-- Item names load on demand; the tab redraws once a batch of missing ones has arrived.
local redrawSoon = ns.UI.Debounce(0.2, function()
	ns.AltsCraft_Refresh()
end)

local function ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if name then
		return name
	end
	if not loading[itemID] then
		loading[itemID] = true
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
			loading[itemID] = nil
			redrawSoon()
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

-- A recipe's name in its item's rarity color (white for recipes that make no item, like enchants).
local function RecipeName(recipe)
	local name = recipe and recipe.name or "?"
	local color = recipe and QualityColor(recipe.item)
	return color and UI.Wrap(name, color) or name
end

local function ProfName(base)
	for _, c in pairs(S.db.chars) do
		local prof = c.profs and c.profs[base]
		if prof and prof.name then
			return prof.name
		end
	end
	return "?"
end

ns.AltsCraft_SetColor = SetColor
ns.AltsCraft_ClassName = ClassName
ns.AltsCraft_Names = Names
ns.AltsCraft_ItemName = ItemName
ns.AltsCraft_QualityColor = QualityColor
ns.AltsCraft_RecipeName = RecipeName
ns.AltsCraft_ProfName = ProfName

function ns.AltsCraft_Create(frame, altsDB)
	S.tab, S.db = frame, altsDB
	ns.AltsCraft_WatchMaterials()
	S.tab.search = ns.AltsCraft_CreateSearch(S.tab)
	S.tab.search:SetPoint("TOPLEFT", 4, -4)
	ns.AltsCraft_CreateFilters(S.tab)
	S.tab.list = UI.Scroll(S.tab)
	S.tab.list:SetPoint("TOPLEFT", S.tab.haveMats, "BOTTOMLEFT", -4, -8)
	S.tab.list:SetPoint("BOTTOMLEFT", 0, 0)
	S.tab.hint = UI.Text(S.tab, 12, "textMuted")
	S.tab.hint:SetPoint("TOPLEFT", S.tab.haveMats, "BOTTOMLEFT", 0, -12)
	S.tab.hint:SetPoint("RIGHT", S.tab.search, "RIGHT")
	S.tab.hint:SetWordWrap(true)
	local divider = UI.VLine(S.tab)
	S.tab.detail = ns.AltsCraft_CreateDetail(S.tab)
	S.tab:SetScript("OnSizeChanged", function(self, width)
		local listW = math.floor(width * LIST_W)
		self.search:SetWidth(listW - 8)
		local third = math.floor((listW - 8 - 12) / 3)
		for _, d in ipairs(self.filters) do
			d:SetWidth(third)
		end
		self.forFilter:SetWidth(listW - 8)
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

-- Opens the Crafting tab on a recipe, "Gear for" set to forValue ("me", a guid or nil to keep it). From Next up, the
-- Profession gear tab and the Crafting list (entry: a listed craft, whose quality and ranks it takes; the amount
-- starts at 1, as Add to list adds to the listed one).
function ns.AltsCraft_Open(recipeID, forValue, entry)
	local adb = S.db or ns.altsDB
	adb.selected, adb.crafts, adb.quality, adb.ranks = recipeID, 1, nil, nil
	if entry then
		adb.quality = entry.quality
		for key, itemID in pairs(entry.ranks or {}) do
			adb.ranks = adb.ranks or {}
			adb.ranks[key] = itemID
		end
	end
	if forValue then
		adb.filterFor = forValue
	end
	if S.tab then
		S.tab.search:SetText("") -- a search could hide it
	end
	adb.view = "craft"
	ns.Panel_OpenPage("alts")
	ns.Alts_ShowTab("craft")
end

-- The recipe index changed (a scan finished, a recipe was learned).
function ns.AltsCraft_RecipesChanged()
	S.producers = nil
	ns.AltsCraft_ClearMaterials()
end

function ns.AltsCraft_Refresh()
	if not (S.tab and S.tab:IsVisible()) then
		return
	end
	S.producers = S.producers or ns.Alts_Producers(S.db.recipes)
	ns.AltsCraft_RefreshFilters()
	ns.AltsCraft_LayoutResults()
	ns.AltsCraft_LayoutDetail()
end
