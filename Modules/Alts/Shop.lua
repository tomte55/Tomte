local addonName, ns = ...

-- Shopping for missing materials: the "Shopping list" (Auctionator) and "TSM search" links on the Crafting tab
-- (CraftDetail.lua) and the Crafting list tab (ListTab.lua), as ns.AltsShop_CreateLink.

local UI = ns.UI

-- c: a theme role.
local function SetColor(fs, c)
	fs:SetTextColor(UI.RGBA(c))
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

-- TSM search ------------------------------------------------------------------------------------------------

-- TSM has no API that makes a shopping list (TSM_API only reads), so Tomte hands over a search to paste into its
-- Shopping tab (Alts_TsmSearch in PlanData.lua).
local function TsmLoaded()
	return C_AddOns.IsAddOnLoaded("TradeSkillMaster")
end

local function ShowTsmSearch(items)
	ns.Dialog_Show({
		title = "TSM search",
		hint = "Copy it (Ctrl+C) and paste it into the search box of TSM's Shopping tab at the Auction House.",
		text = ns.Alts_TsmSearch(items),
		readOnly = true,
	})
end

-- Links ------------------------------------------------------------------------------------------------------

-- asButton: drawn as a small button (the Crafting list tab) instead of a text link.
local function TextLink(parent, label, tooltip, onClick, asButton)
	local b = CreateFrame("Button", nil, parent)
	b.text = UI.Text(b, 12, "accent")
	b.text:SetText(label)
	if asButton then
		b:SetSize(math.max(124, b.text:GetStringWidth() + 20), 22)
		UI.Surface(b, 0.45)
		b.text:SetPoint("CENTER")
	else
		b:SetSize(b.text:GetStringWidth(), 16)
		b.text:SetPoint("RIGHT")
	end
	b:SetScript("OnEnter", function(self)
		SetColor(self.text, "text")
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		tooltip(parent)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		SetColor(self.text, "accent")
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function()
		UI.Sound("confirm")
		onClick(parent)
	end)
	return b
end

local function Missing(link)
	return ("the %d missing material%s"):format(#link.items, #link.items == 1 and "" or "s")
end

-- The shopping links (Crafting tab and Crafting list tab headings): "Shopping list" for Auctionator and "TSM search"
-- for TSM, right-aligned in that order. link:Set(listName, items) shows the ones whose addon is loaded while
-- something is missing. asButtons: small buttons instead of text links.
function ns.AltsShop_CreateLink(parent, asButtons)
	local link = CreateFrame("Frame", nil, parent)
	link:SetHeight(asButtons and 22 or 16)
	link.auctionator = TextLink(link, "Shopping list", function(self)
		GameTooltip:SetText("Auctionator shopping list")
		GameTooltip:AddLine(("Makes the list \"%s\" with %s and how many, replacing an older one of that name.")
			:format(self.listName, Missing(self)), 1, 1, 1, true)
	end, function(self)
		MakeShoppingList(self.listName, self.items)
	end, asButtons)
	link.tsm = TextLink(link, "TSM search", function(self)
		GameTooltip:SetText("TSM search")
		GameTooltip:AddLine(("A search for %s and how many, to paste into TSM's Shopping tab."):format(Missing(self)),
			1, 1, 1, true)
	end, function(self)
		ShowTsmSearch(self.items)
	end, asButtons)
	function link:Set(listName, items)
		self.listName, self.items = listName, items
		local width = 0
		for _, b in ipairs({ { self.auctionator, ShoppingAPI() ~= nil }, { self.tsm, TsmLoaded() } }) do
			local button, on = b[1], b[2]
			button:SetShown(on)
			if on then
				button:ClearAllPoints()
				button:SetPoint("RIGHT", -(width > 0 and width + 12 or 0), 0)
				width = width + (width > 0 and 12 or 0) + button:GetWidth()
			end
		end
		self:SetWidth(math.max(width, 1))
		self:SetShown(#items > 0 and width > 0)
	end
	link:Hide()
	return link
end
