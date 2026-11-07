local addonName, ns = ...

-- Gear Check at vendors: its upgrade arrow (Arrow.lua) on the merchant's items, retail and Forever, from the same
-- verdict as your bags (ns.Gear_BagArrow: Gear.lua or Baganator.lua on retail, Forever.lua on Forever). Blizzard's
-- MerchantFrame_UpdateMerchantInfo redraws the page on opening, turning a page and MERCHANT_UPDATE, so it's hooked
-- once; the buyback tab hides the arrows. The hooks can't be removed: with Gear Check off, Gear_BagArrow answers nil
-- and every arrow hides.

local ARROW_SCALE = 0.85 -- as on Tomte's bag buttons
local ARROW_X, ARROW_Y = -3, 3 -- the item button's top left corner, a little outside it

local arrows = {} -- [Blizzard's item button] = { [kind] = arrow }: kept here, nothing is written on their buttons

local function HideAll()
	for _, kinds in pairs(arrows) do
		for _, widget in pairs(kinds) do
			widget:Hide()
		end
	end
end

local function Arrow(button, kind)
	local kinds = arrows[button]
	if not kinds then
		kinds = {}
		arrows[button] = kinds
	end
	local widget = kinds[kind]
	if not widget then
		widget = ns.Gear_Arrow(button, ns.GEAR_ARROW_ROLES[kind])
		widget:SetScale(ARROW_SCALE)
		widget:SetPoint("TOPLEFT", ARROW_X, ARROW_Y)
		kinds[kind] = widget
	end
	return widget
end

local function Update()
	HideAll()
	if not (ns.Gear_BagArrow and MerchantFrame and MerchantFrame:IsShown()) then
		return
	end
	local perPage = MERCHANT_ITEMS_PER_PAGE or 10
	for i = 1, perPage do
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		local index = ((MerchantFrame.page or 1) - 1) * perPage + i
		local link = button and button:IsShown() and GetMerchantItemLink(index)
		local kind = link and ns.Gear_BagArrow(link)
		if kind then
			Arrow(button, kind):Show()
		end
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", Update)
	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", HideAll)
end)
