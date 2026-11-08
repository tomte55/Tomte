local addonName, ns = ...

-- Gold & value: sell on the auction house or at a vendor. A line on item tooltips, the verdict the bags' AH mark and
-- Vendor Helper's grey selling ask for. The auction price comes from Value.lua's source; the sale rate and sales a day
-- from TSM, when it's there. Rule in Data.lua (Value_SellVerdict); registered in Value.lua.

local TSM_SCALE = 1000 -- TSM_API rounds to whole numbers: the rate is asked times this, as TSM's own tooltip does
local BIND_ON_PICKUP, BIND_QUEST = 1, 4 -- Enum.ItemBind
local CONSUMABLE = 0 -- Enum.ItemClass.Consumable: potions, food, scrolls

local UI = ns.UI

local module, db
local hooked = false

local function TSMNumber(source, itemString)
	if type(TSM_API) ~= "table" or type(TSM_API.GetCustomPriceValue) ~= "function" then
		return nil
	end
	local ok, value = pcall(TSM_API.GetCustomPriceValue, ("%s * %d"):format(source, TSM_SCALE), itemString)
	if ok and type(value) == "number" then
		return value / TSM_SCALE
	end
	return nil
end

-- The verdict for count of item (a link or an item ID), or nil: bound, no auction price, or Value off.
function ns.Value_SellAdvice(item, count, bound)
	if not (module and module.active) or item == nil or bound then
		return nil
	end
	local itemID = C_Item.GetItemInfoInstant(item)
	if not itemID then
		return nil
	end
	local _, _, _, _, _, _, _, _, _, _, vendor, _, _, bindType = C_Item.GetItemInfo(item)
	if bindType == BIND_ON_PICKUP or bindType == BIND_QUEST then
		return nil
	end
	local market = ns.Value_AuctionPrice(itemID, type(item) == "string" and item or nil)
	if not market then
		return nil
	end
	local itemString = "i:" .. itemID
	return ns.Value_SellVerdict({
		market = market,
		vendor = vendor,
		saleRate = TSMNumber("DBRegionSaleRate", itemString),
		soldPerDay = TSMNumber("DBRegionSoldPerDay", itemString),
		count = count or 1,
		minGain = db.sell.minGain,
	})
end

-- What one of item really fetches and where you'd sell it (Value_SellPick): copper, "auction" | "vendor". Nil while
-- Gold & value is off or the item is worth nothing. Bound items: the vendor price.
function ns.Value_SellPrice(item, bound)
	if not (module and module.active) or item == nil then
		return nil
	end
	local _, _, _, _, _, _, _, _, _, _, vendor = C_Item.GetItemInfo(item)
	return ns.Value_SellPick(ns.Value_SellAdvice(item, 1, bound), vendor)
end

-- The bags' AH mark: this item should go to the auction house. Judged on everything of it you carry, as the tooltip,
-- so every stack of it is marked alike (you'd list them together).
function ns.Value_SellMark(item, count, bound)
	if not (db and db.sell.mark) or item == nil then
		return false
	end
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
	if classID == CONSUMABLE and not db.sell.markConsumables then
		return false
	end
	count = math.max(itemID and C_Item.GetItemCount(itemID) or 0, count or 1)
	local v = ns.Value_SellAdvice(item, count, bound)
	return v ~= nil and v.kind == "ah"
end

-- Tooltip --------------------------------------------------------------------------------------------------------------

local function Percent(rate)
	return ("%d%%"):format(math.floor(rate * 100 + 0.5))
end

local function SoldText(v)
	if not v.soldPerDay then
		return ""
	end
	return (" %s sold a day."):format(ns.Thousands(math.floor(v.soldPerDay + 0.5)))
end

local function VendorText(v)
	return v.vendor > 0 and ("Vendor %s."):format(ns.Price(v.vendor)) or "No vendor price."
end

-- An item in your bags that's soulbound (a link alone can't say: a worn BoE is bound).
local function IsBound(data)
	if not (data.guid and C_Item.GetItemLocation) then
		return false
	end
	local ok, location = pcall(C_Item.GetItemLocation, data.guid)
	if not (ok and location and location:IsValid()) then
		return false
	end
	local okBound, bound = pcall(C_Item.IsBound, location)
	return okBound and bound == true
end

local function OnItem(tooltip, data)
	if not (module and module.active and db.sell.tooltip and tooltip.AddLine and data) then
		return
	end
	local itemID = data.id
	if not itemID or ns.IsSecret(itemID) or type(itemID) ~= "number" or IsBound(data) then
		return
	end
	local link = data.hyperlink
	if ns.IsSecret(link) then
		link = nil
	end
	local count = math.max(C_Item.GetItemCount(itemID), 1)
	local v = ns.Value_SellAdvice(link or itemID, count)
	if not v then
		return
	end
	local each = ns.Price(math.floor(v.market + 0.5))
	local rate = v.saleRate and (" (%s sell)"):format(Percent(v.saleRate)) or ""
	if v.kind == "ah" then
		UI.TipLine(("Auction House: sells%s, about %s each"):format(rate, each), "success")
		UI.TipLine(VendorText(v) .. SoldText(v), "textMuted")
	elseif v.kind == "small" then
		UI.TipLine(("Auction House: about %s each%s, a small gain for %d"):format(each, rate, count), "textMuted")
	elseif v.kind == "slow" then
		UI.TipLine(("Auction House: about %s, but slow%s"):format(each, rate), "warning")
		UI.TipLine("Most don't sell. " .. VendorText(v) .. SoldText(v), "textMuted")
	else
		UI.TipLine(("Vendor it: %s, the Auction House about %s after its cut"):format(ns.Price(v.vendor),
			ns.Price(math.floor(v.net + 0.5))), "textMuted")
	end
end

function ns.ValueSell_Init(mod, saved)
	module, db = mod, saved
end

-- On toggle and when the setting changes. Post-calls can't be removed; OnItem checks the setting.
function ns.ValueSell_Update()
	if module.active and db.sell.tooltip and not hooked and TooltipDataProcessor
		and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItem, "tooltip"))
	end
end
