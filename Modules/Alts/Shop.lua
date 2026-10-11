local addonName, ns = ...

-- Auctionator shopping list: the "Shopping list" link on the Crafting tab (CraftDetail.lua) and the Crafting list tab
-- (ListTab.lua), as ns.AltsShop_CreateLink.

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

-- A "Shopping list" link (Crafting tab and Crafting list tab headings). link:Set(listName, items) shows it when
-- Auctionator is loaded and something is missing.
function ns.AltsShop_CreateLink(parent)
	local link = CreateFrame("Button", nil, parent)
	link:SetHeight(16)
	link.text = UI.Text(link, 12, "accent")
	link.text:SetPoint("RIGHT")
	link.text:SetText("Shopping list")
	link:SetWidth(link.text:GetStringWidth())
	link:SetScript("OnEnter", function(self)
		SetColor(self.text, "text")
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Auctionator shopping list")
		GameTooltip:AddLine(("Makes the list \"%s\" with the %d missing material%s and how many, replacing an older one "
			.. "of that name."):format(self.listName, #self.items, #self.items == 1 and "" or "s"), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	link:SetScript("OnLeave", function(self)
		SetColor(self.text, "accent")
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
