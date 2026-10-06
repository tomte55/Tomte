local addonName, ns = ...

-- Gold & value: what things are worth, from Auctionator or TSM (a setting picks; vendor price without either).
--   Session recap  every looted item is priced (Recap/Track.lua calls ns.Value_NoteLoot) so the recap card and the
--                  Sessions page show what a session's loot was worth, not just the gold.
--   Alts           each character's bags (and bank, read when it's open) and the Warband bank, priced; a column in
--                  the roster and "worth" next to the total gold.
--   Crafting tab   what the materials cost, what the result sells for and the difference.
-- Choices are in Data.lua (unit-tested).

local DEBOUNCE = 2
local CALLER = "Tomte" -- Auctionator wants the calling addon's name
local BAGS = { 0, 1, 2, 3, 4, 5 } -- Backpack .. ReagentBag (Enum.BagIndex)
local BANK = { 6, 7, 8, 9, 10, 11 } -- CharacterBankTab_1..6
local WARBAND = { 12, 13, 14, 15, 16 } -- AccountBankTab_1..5

local module, db
local bankOpen = false
local worthTimer

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

-- Price sources ---------------------------------------------------------------------------------------------------

local function HasAuctionator()
	return Auctionator ~= nil and type(Auctionator.API) == "table" and type(Auctionator.API.v1) == "table"
end

local function HasTSM()
	return type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function"
end

local function Has()
	return { auctionator = HasAuctionator(), tsm = HasTSM() }
end

function ns.Value_SourceName()
	local source = ns.Value_Source(db.source, Has())
	return source == "tsm" and "TSM" or (source == "auctionator" and "Auctionator" or "vendor prices")
end

-- Auction price in copper and age in days (nil when unknown).
local function AuctionatorPrice(itemID, link)
	local api = Auctionator.API.v1
	local ok, price = pcall(function()
		if link then
			return api.GetAuctionPriceByItemLink(CALLER, link)
		end
		return api.GetAuctionPriceByItemID(CALLER, itemID)
	end)
	if not ok or type(price) ~= "number" then
		return nil
	end
	local okAge, age = pcall(function()
		if link then
			return api.GetAuctionAgeByItemLink(CALLER, link)
		end
		return api.GetAuctionAgeByItemID(CALLER, itemID)
	end)
	return price, okAge and type(age) == "number" and age or nil
end

local function TSMPrice(itemID, link)
	local ok, price = pcall(function()
		local itemString = link and TSM_API.ToItemString(link) or ("i:" .. itemID)
		return itemString and TSM_API.GetCustomPriceValue(db.tsmSource, itemString)
	end)
	if ok and type(price) == "number" then
		return price
	end
	return nil
end

-- The auction price from the chosen source, or nil. Also says whether it's stale.
local function AuctionPrice(itemID, link)
	local source = ns.Value_Source(db.source, Has())
	if source == "auctionator" then
		local price, age = AuctionatorPrice(itemID, link)
		return price, ns.Value_Stale(age, db.stale)
	elseif source == "tsm" then
		return TSMPrice(itemID, link), false
	end
	return nil, false
end

-- What one of this item is worth: copper (or nil: left out or unknown), "auction" | "vendor", stale.
-- item: link or itemID. bound: the item is soulbound (only its vendor price counts).
function ns.Value_ItemPrice(item, bound)
	if not (module and module.active) or item == nil then
		return nil
	end
	local link = type(item) == "string" and item or nil
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
	if not itemID then
		return nil
	end
	local _, _, _, _, _, _, _, _, _, _, sell, _, _, bindType = C_Item.GetItemInfo(item)
	local auction, stale
	if db.source ~= "vendor" then
		auction, stale = AuctionPrice(itemID, link)
	end
	local price, kind = ns.Value_Pick({
		category = ns.Value_Category(classID),
		bound = bound or bindType == 1, -- Enum.ItemBind.OnAcquire
		auction = auction,
		vendor = sell,
	}, db.gear)
	return price, kind, kind == "auction" and stale or false
end

-- "1,240g" with a grey "?" when the price is stale.
function ns.Value_Text(copper, stale)
	if not copper then
		return "?"
	end
	return ns.Alts_Gold(copper) .. (stale and "|cff9e9e9e?|r" or "")
end

-- Session loot ---------------------------------------------------------------------------------------------------

-- Every looted item (Recap/Track.lua). Priced now, so the session remembers what it was worth that day.
function ns.Value_NoteLoot(link, count)
	if not (module and module.active and db.sessions) then
		return
	end
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
	if not itemID then
		return
	end
	local session = ns.Session_Current()
	session.loot = session.loot or {}
	local unit = ns.Value_ItemPrice(link)
	ns.Value_LootAdd(session.loot, itemID, link, count or 1, unit or 0, ns.Value_Category(classID))
end

-- A session's loot value: total and by category, or nil when nothing was priced (or the module is off).
function ns.Value_SessionLoot(session)
	if not (module and module.active and db.sessions) or not session or not session.loot or not next(session.loot) then
		return nil
	end
	local priceNow
	if db.priceAt == "now" then
		priceNow = function(itemID, e)
			return (ns.Value_ItemPrice(e.link or itemID))
		end
	end
	return ns.Value_LootTotals(session.loot, priceNow, db.gear == "none" and { gear = true } or nil)
end

-- "loot worth 3,860g (gathered 3,200g)"
function ns.Value_SessionLootText(session)
	local total, by = ns.Value_SessionLoot(session)
	if not total or total <= 0 then
		return nil
	end
	local text = "loot worth " .. ns.Alts_Gold(total)
	if by.gathered > 0 and by.gathered < total then
		text = text .. (" (gathered %s)"):format(ns.Alts_Gold(by.gathered))
	end
	return text
end

-- Carried value --------------------------------------------------------------------------------------------------

local function BagsValue(bags)
	local stacks = {}
	for _, bag in ipairs(bags) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.hyperlink and not info.hasNoValue then
				stacks[#stacks + 1] = { price = ns.Value_ItemPrice(info.hyperlink, info.isBound), count = info.stackCount }
			end
		end
	end
	return ns.Value_Sum(stacks)
end

local function ReadWorth()
	worthTimer = nil
	if not (module.active and db.alts and ns.altsDB) then
		return
	end
	if InCombatLockdown() then
		worthTimer = C_Timer.NewTimer(DEBOUNCE * 3, ReadWorth)
		return
	end
	local c = ns.altsDB.chars[UnitGUID("player")]
	if not c then
		return
	end
	c.worth = c.worth or {}
	c.worth.bags = BagsValue(BAGS)
	if bankOpen then
		c.worth.bank = BagsValue(BANK)
		ns.altsDB.warbandWorth = { v = BagsValue(WARBAND), at = GetServerTime() }
	end
	c.worth.at = GetServerTime()
	if ns.Alts_Changed then
		ns.Alts_Changed()
	end
end

local function ReadWorthSoon()
	if worthTimer then
		worthTimer:Cancel()
	end
	worthTimer = C_Timer.NewTimer(DEBOUNCE, ReadWorth)
end

-- A character's carried value (bags + last seen bank), or nil.
function ns.Value_CharWorth(c)
	if not (module and module.active and db.alts) or not c.worth then
		return nil
	end
	return (c.worth.bags or 0) + (c.worth.bank or 0)
end

-- Every character's carried value plus the Warband bank, or nil.
function ns.Value_AccountWorth(chars)
	if not (module and module.active and db.alts) then
		return nil
	end
	local total, any = 0, false
	for _, c in pairs(chars) do
		local v = ns.Value_CharWorth(c)
		if v then
			total, any = total + v, true
		end
	end
	local warband = ns.altsDB and ns.altsDB.warbandWorth
	if warband then
		total, any = total + (warband.v or 0), true
	end
	return any and total or nil
end

function events:PLAYER_ENTERING_WORLD()
	ReadWorthSoon()
end

function events:BAG_UPDATE_DELAYED()
	ReadWorthSoon()
end

function events:BANKFRAME_OPENED()
	bankOpen = true
	ReadWorthSoon()
end

function events:BANKFRAME_CLOSED()
	ReadWorth() -- the bank's contents are still readable now
	bankOpen = false
end

-- Crafting tab ---------------------------------------------------------------------------------------------------

-- Plan value for the Crafting tab: { cost, complete, sells, profit } or nil. plan from ns.Alts_Plan, recipe from
-- the Alts recipes, crafts = how many.
function ns.Value_Plan(plan, recipe, crafts)
	if not (module and module.active) then
		return nil
	end
	local materials = {}
	for _, m in ipairs(plan.materials) do
		-- A shortfall that's crafted is made from other materials (also listed): only what you have counts here.
		materials[#materials + 1] = {
			need = m.crafted and m.have or m.need, have = m.have, unit = (ns.Value_ItemPrice(m.items[1])),
		}
	end
	local cost, complete = ns.Value_CraftCost(materials, db.owned)
	local sells
	if recipe and recipe.item then
		local unit = ns.Value_ItemPrice(recipe.item)
		if unit then
			local per = ((recipe.qMin or 1) + (recipe.qMax or recipe.qMin or 1)) / 2
			sells = math.floor(unit * per * (crafts or 1))
		end
	end
	return { cost = cost, complete = complete, sells = sells, profit = sells and (sells - cost) or nil }
end

-- Module --------------------------------------------------------------------------------------------------------

local EVENTS = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }

local function PrintPrice(text)
	text = strtrim(text or "")
	if text == "" then
		ns.Print(("prices from %s. Usage: /tomte value price <item link or ID>"):format(ns.Value_SourceName()))
		return
	end
	-- /tomte lower-cases its arguments, so a link only gives its item ID here.
	local item = tonumber(text) or tonumber(text:match("item:(%d+)") or "")
	if not item then
		ns.Print("give an item link (shift-click it) or an item ID.")
		return
	end
	local price, kind, stale = ns.Value_ItemPrice(item)
	ns.Print(("%s: %s (%s%s, from %s)"):format(text, ns.Value_Text(price, stale), kind or "no price",
		stale and ", stale" or "", ns.Value_SourceName()))
end

module = ns.RegisterModule({
	key = "value",
	name = "Gold & value",
	category = "General",
	description = "What things are worth, from Auctionator or TSM: the value of a session's loot on the recap card and "
		.. "the Sessions page, each character's bags and bank in Alts, and what a craft costs and sells for in the "
		.. "Crafting tab.",
	enabledByDefault = true,
	uses = {
		{ addon = "Auctionator", why = "auction prices", without = "uses TSM or vendor prices" },
		{ addon = "TradeSkillMaster", why = "auction prices (if you pick TSM)", without = "uses Auctionator or vendor prices" },
	},
	defaults = {
		source = "auto", -- auto | auctionator | tsm | vendor
		tsmSource = "DBMarket",
		sessions = true,
		priceAt = "loot", -- loot | now
		gear = "vendor", -- auction | vendor | none
		alts = true,
		owned = "market", -- market | free
		stale = 7,
	},
	init = function(saved)
		db = saved
		ns.valueDB = saved
	end,
	toggle = function(active)
		for _, event in ipairs(EVENTS) do
			if active then
				events:RegisterEvent(event)
			else
				events:UnregisterEvent(event)
			end
		end
		if active then
			ReadWorthSoon()
		end
	end,
	options = {
		{ type = "dropdown", key = "source", label = "Prices from", choices = function()
			return {
				{ value = "auto", text = "Auto (TSM, else Auctionator)" },
				{ value = "auctionator", text = "Auctionator" },
				{ value = "tsm", text = "TSM" },
				{ value = "vendor", text = "Vendor prices only" },
			}
		end, tooltip = "Where auction prices come from. A missing addon falls back to the other, then to vendor prices." },
		{ type = "dropdown", key = "tsmSource", label = "TSM price", choices = function()
			return {
				{ value = "DBMarket", text = "Market value (realm)" },
				{ value = "DBMinBuyout", text = "Min buyout (realm)" },
				{ value = "DBRecent", text = "Recent value (realm)" },
				{ value = "DBRegionMarketAvg", text = "Market value (region)" },
				{ value = "DBRegionSaleAvg", text = "Sale average (region)" },
			}
		end, tooltip = "Which TSM price source counts, when prices come from TSM." },
		{ type = "slider", key = "stale", label = "Auctionator price stale after (days)", min = 1, max = 21, step = 1,
			tooltip = "Older prices are marked with a grey ?. Scan the auction house to refresh them." },
		{ type = "dropdown", key = "gear", label = "Gear and BoEs", choices = function()
			return {
				{ value = "vendor", text = "Vendor price" },
				{ value = "auction", text = "Auction price" },
				{ value = "none", text = "Leave out" },
			}
		end, tooltip = "Auction prices for gear are often misleading (few sales, item level variants)." },
		{ type = "header", label = "Sessions" },
		{ type = "checkbox", key = "sessions", label = "Count loot value in sessions",
			tooltip = "Every looted item is priced for the recap card and the Sessions page. Needs Session recap on." },
		{ type = "dropdown", key = "priceAt", label = "Price loot", choices = function()
			return { { value = "loot", text = "When looted" }, { value = "now", text = "At today's price" } }
		end },
		{ type = "header", label = "Alts and crafting" },
		{ type = "checkbox", key = "alts", label = "Carried value in Alts",
			tooltip = "What each character's bags and bank are worth (the bank is read when you open it), and the Warband bank." },
		{ type = "dropdown", key = "owned", label = "Materials you have", choices = function()
			return { { value = "market", text = "Count at market price" }, { value = "free", text = "Count as free" } }
		end, tooltip = "In the Crafting tab's cost: what the materials you already have are worth." },
	},
	commands = {
		{ "price", "what an item is worth: /tomte value price <item link or ID>", PrintPrice },
	},
})
