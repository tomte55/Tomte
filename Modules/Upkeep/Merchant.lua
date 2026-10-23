local addonName, ns = ...

-- Vendor Helper at the merchant window: price colors and the non-refundable purchase lock. Registered in Vendor.lua,
-- the rule in Data.lua (ns.Upkeep_PriceShort).
--
-- Prices: when you can't afford an item, Blizzard greys every cost on its row (AltCurrencyFrame_Update with
-- canAfford false), so you can't tell which currency you're missing. After each MerchantFrame_UpdateMerchantInfo
-- this paints only the costs you lack red and the others white again. Blizzard already lists every cost (gold plus up
-- to MAX_ITEM_COST currencies or items) on the row; nothing is added or moved.
--
-- Lock: Blizzard asks before a purchase that can't be refunded (StaticPopup "CONFIRM_PURCHASE_NONREFUNDABLE_ITEM").
-- Its Yes button stays disabled for LOCK_SECONDS so a double click or a held Enter can't buy by accident. Only widget
-- methods are called on the dialog (Disable/Enable), never a field written, so the popup stays untainted.
-- Both hooks are hooksecurefunc (can't be undone): they do nothing while the module or the setting is off.

local LOCK_SECONDS = 1
local NONREFUNDABLE = "CONFIRM_PURCHASE_NONREFUNDABLE_ITEM"

local UI = ns.UI
local db
local active = false
local hookedPrices, hookedLock = false, false
local lockCount = 0 -- counts locks, so only the latest one's timer enables the Yes button

-- Prices -------------------------------------------------------------------------------------------------------------

-- How many of one cost you hold: currencies from the currency API, items like Blizzard's own stack-split check
-- (bags and reagent bag, not the bank).
local function Have(link, currencyName)
	if type(link) ~= "string" then
		return nil
	end
	if currencyName then
		local id = C_CurrencyInfo.GetCurrencyIDFromLink(link)
		local info = id and C_CurrencyInfo.GetCurrencyInfo(id)
		return info and info.quantity
	end
	return C_Item.GetItemCount(link, false, false, true)
end

local function PaintRow(slot, index, money)
	local frameName = "MerchantItem" .. slot .. "AltCurrencyFrame"
	local altFrame = _G[frameName]
	local costs, buttons = {}, {}
	if altFrame and altFrame:IsShown() then
		for i = 1, MAX_ITEM_COST do
			local button = _G[frameName .. "Item" .. i]
			-- button.item is the cost's index on the merchant item (Blizzard skips costs without a texture).
			if button and button:IsShown() and button.item and button.Text then
				local _, need, link, currencyName = GetMerchantItemCostItem(index, button.item)
				costs[#costs + 1] = { need = need, have = Have(link, currencyName) }
				buttons[#buttons + 1] = button
			end
		end
	end
	local info = C_MerchantFrame.GetItemInfo(index)
	local price = info and info.price or 0
	local short = ns.Upkeep_PriceShort(price, money, costs)
	for i, button in ipairs(buttons) do
		if short[i] then
			button.Text:SetTextColor(UI.RGB("danger"))
		else
			button.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
		end
	end
	local moneyFrame = _G["MerchantItem" .. slot .. "MoneyFrame"]
	if price > 0 and moneyFrame and moneyFrame:IsShown() then
		-- Blizzard's own money font colors ("red", or nil for the normal one).
		SetMoneyFrameColor(moneyFrame:GetName(), short.money and "red" or nil)
	end
end

local function OnMerchantInfo()
	if not (active and db.prices) or MerchantFrame.selectedTab ~= 1 then
		return
	end
	local count, money = GetMerchantNumItems(), GetMoney()
	for slot = 1, MERCHANT_ITEMS_PER_PAGE do
		local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + slot
		-- Blizzard only greys a row when it says you can't afford it; the other rows are already right.
		if index <= count and CanAffordMerchantItem(index) == false then
			PaintRow(slot, index, money)
		end
	end
end

-- Lock ---------------------------------------------------------------------------------------------------------------

local function OnPopupShow(which)
	if which ~= NONREFUNDABLE or not (active and db.lockNonRefundable) then
		return
	end
	local dialog = StaticPopup_FindVisible(which)
	local button = dialog and dialog.GetButton1 and dialog:GetButton1()
	if not button then
		return
	end
	button:Disable()
	lockCount = lockCount + 1
	local lock = lockCount
	C_Timer.After(LOCK_SECONDS, function()
		-- The same popup may have been closed or reused for another question meanwhile, or shown again for another
		-- purchase (whose own timer enables it).
		if lock == lockCount and dialog:IsShown() and dialog.which == which then
			button:Enable()
		end
	end)
end

-- Start / stop -------------------------------------------------------------------------------------------------------

function ns.UpkeepMerchant_Init(moduleDB)
	db = moduleDB
end

local function HookPrices()
	if not hookedPrices and MerchantFrame_UpdateMerchantInfo then
		hookedPrices = true
		hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnMerchantInfo)
	end
end

local function HookLock()
	if not hookedLock and StaticPopup_Show then
		hookedLock = true
		hooksecurefunc("StaticPopup_Show", OnPopupShow)
	end
end

-- The merchant window and the popups live in Blizzard addons that may load after Tomte: hook each once it has
-- (EventUtil runs the hook now when it already has). Called on every turn-on; the waiting flag keeps calls from
-- stacking callbacks.
local waiting = false

function ns.UpkeepMerchant_Toggle(on)
	active = on
	if on and not waiting then
		waiting = true
		EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", HookPrices)
		EventUtil.ContinueOnAddOnLoaded("Blizzard_StaticPopup", HookLock)
	end
	ns.UpkeepMerchant_Refresh()
end

-- Paints the open merchant window again (a setting changed, or the module turned on). Never calls Blizzard's
-- MerchantFrame_Update from here: that would write MerchantFrame's fields from addon code. Turned off, the colors stay
-- until Blizzard's next update of the window (a page turn, a bag or currency change).
function ns.UpkeepMerchant_Refresh()
	if MerchantFrame and MerchantFrame:IsShown() then
		OnMerchantInfo()
	end
end
