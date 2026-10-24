local addonName, ns = ...

-- Trading Post: reads the game into plain tables for the page, Home and the reminders. The Traveler's Log
-- (C_PerksActivities, readable anywhere), Trader's Tender, the Collector's Cache (an async server request) and,
-- while the Trading Post is open, the shop (saved for the rest of the month) and where the vendor stands.
-- Pure rules in Data.lua; registered in TradingPost.lua.

local CHEST_DELAY = 3 -- seconds after entering the world before asking the server what's in the cache
local READ_DELAY = 0.5 -- seconds to gather a burst of log or currency events into one read
local SHOP_DELAY = 0.5 -- seconds after the vendor opens before its list is read (it fills on PERKS_PROGRAM_DATA_REFRESH)
local MONTH_END_SLACK = 5 -- seconds after the month's end before the log is read again

local db
local state = { available = false, activities = {}, sorted = {}, milestones = {}, tender = 0, waiting = 0,
	waitingItems = 0 }
local readAt -- GetTime() of the last log read (secondsLeft counts down from it)
local vendorOpen = false
local monthTimer, chestTimer

local events = ns.NewEvents()
ns.TradingPost_Events = events

local function Changed()
	if ns.TradingPost_OnChanged then
		ns.TradingPost_OnChanged()
	end
end

-- The log --------------------------------------------------------------------------------------------------------

local function PlainActivity(a, now)
	local reqs = {}
	for i, r in ipairs(a.requirementsList or {}) do
		reqs[i] = { completed = r.completed, text = r.requirementText }
	end
	return {
		id = a.ID, name = a.activityName, description = a.description, points = a.thresholdContributionAmount or 0,
		completed = a.completed, inProgress = a.inProgress, tracked = a.tracked, requirements = reqs,
		expired = not a.completed and a.eventEndTime and a.eventEndTime > 0 and a.eventEndTime < now or nil,
		eventName = a.eventName,
	}
end

local function ScheduleMonthEnd(seconds)
	if monthTimer then
		monthTimer:Cancel()
		monthTimer = nil
	end
	if seconds and seconds > 0 and seconds < 86400 then
		monthTimer = C_Timer.NewTimer(seconds + MONTH_END_SLACK, function()
			monthTimer = nil
			ns.TradingPost_ReadAll()
		end)
	end
end

local function ReadLog()
	state.available = C_PlayerInfo.IsTravelersLogAvailable() and true or false
	if not state.available then
		state.month, state.activities, state.sorted, state.milestones = nil, {}, {}, {}
		state.nextOne, state.tenderLeft, state.earned, state.max = nil, 0, 0, 0
		return
	end
	local info = C_PerksActivities.GetPerksActivitiesInfo()
	if not info then
		return
	end
	local now = GetServerTime()
	local activities = {}
	for _, a in ipairs(info.activities or {}) do
		local plain = PlainActivity(a, now)
		if not plain.expired then
			activities[#activities + 1] = plain
		end
	end
	local thresholds = {}
	for i, t in ipairs(info.thresholds or {}) do
		thresholds[i] = { index = t.thresholdOrderIndex, required = t.requiredContributionAmount,
			tender = t.currencyAwardAmount, item = t.itemReward }
	end
	state.month, state.monthName = info.activePerksMonth, info.displayMonthName
	-- 0 right after login, before the server has sent the month: unknown, not "the month ends now".
	local seconds = info.secondsRemaining
	state.secondsRemaining, readAt = seconds and seconds > 0 and seconds or nil, GetTime()
	state.activities = activities
	state.earned, state.max = ns.TradingPost_Points(activities, thresholds)
	state.milestones, state.nextOne, state.tenderLeft = ns.TradingPost_Milestones(thresholds, state.earned)
	state.sorted = ns.TradingPost_SortActivities(activities)
	ScheduleMonthEnd(info.secondsRemaining)
end

local function ReadTender()
	local info = C_CurrencyInfo.GetCurrencyInfo(ns.TRADINGPOST_CURRENCY)
	state.tender = info and info.quantity or 0
	state.tenderIcon = info and info.iconFileID or nil
	state.tenderName = info and info.name or "Trader's Tender"
end

-- Seconds left in the Trading Post month, counted down from the last read; nil without the log.
function ns.TradingPost_SecondsLeft()
	if not (state.available and state.secondsRemaining and readAt) then
		return nil
	end
	return math.max(state.secondsRemaining - (GetTime() - readAt), 0)
end

function ns.TradingPost_State()
	return state
end

-- The cache --------------------------------------------------------------------------------------------------

-- Asks the server what waits in the Collector's Cache; the answer comes as CHEST_REWARDS_UPDATED_FROM_SERVER.
local function RequestChest(delay)
	if chestTimer then
		chestTimer:Cancel()
	end
	chestTimer = C_Timer.NewTimer(delay or READ_DELAY, function()
		chestTimer = nil
		C_PerksProgram.RequestPendingChestRewards()
	end)
end

events:On("read", "CHEST_REWARDS_UPDATED_FROM_SERVER", function()
	state.waiting, state.waitingItems = ns.TradingPost_Waiting(C_PerksProgram.GetPendingChestRewards())
	state.chestKnown = true
	Changed()
end)

-- The shop ----------------------------------------------------------------------------------------------------

-- "bought", "owned" (collected some other way) or nil. The collection calls can fail on odd IDs: that's "not owned".
local function OwnedState(it)
	if it.bought then
		return "bought"
	end
	local ok, owned = pcall(function()
		if it.mountID and it.mountID > 0 then
			return (select(11, C_MountJournal.GetMountInfoByID(it.mountID)))
		elseif it.speciesID and it.speciesID > 0 then
			return (C_PetJournal.GetNumCollectedInfo(it.speciesID) or 0) > 0
		elseif it.setID and it.setID > 0 then
			local set = C_TransmogSets.GetSetInfo(it.setID)
			return set and set.collected
		elseif it.appearanceID and it.appearanceID > 0 then
			return C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(it.appearanceID)
		elseif it.category == 5 and it.itemID then -- Enum.PerksVendorCategoryType.Toy
			return PlayerHasToy(it.itemID)
		end
		return false
	end)
	return ok and owned and "owned" or nil
end

-- The shop seen this month, with each item's state worked out now (a purchase or a new mount since counts), or nil.
function ns.TradingPost_Shop()
	local shop = db and db.shop
	if not (shop and shop.items and shop.month and shop.month == state.month) then
		return nil
	end
	for _, it in ipairs(shop.items) do
		it.state = OwnedState(it)
	end
	return shop
end

local function ReadShop()
	if not vendorOpen then
		return
	end
	local ids = C_PerksProgram.GetAvailableVendorItemIDs()
	if not (ids and #ids > 0) then
		return
	end
	local items = {}
	for _, id in ipairs(ids) do
		local info = C_PerksProgram.GetVendorItemInfo(id)
		if info and info.name and info.name ~= "" then
			items[#items + 1] = {
				id = id, name = info.name, icon = info.iconTexture, price = info.price or 0,
				category = info.perksVendorCategoryID, itemID = info.itemID, mountID = info.mountID,
				speciesID = info.speciesID, setID = info.transmogSetID, appearanceID = info.itemModifiedAppearanceID,
				bought = info.purchased or nil, pending = info.isPurchasePending or nil,
			}
		end
	end
	db.shop = { month = state.month, at = GetServerTime(), items = ns.TradingPost_SortShop(items) }
	Changed()
end

local readShopSoon = ns.UI.Debounce(SHOP_DELAY, ReadShop)

-- True while the Trading Post vendor's window is open.
function ns.TradingPost_AtVendor()
	return vendorOpen
end

-- Where the player is ----------------------------------------------------------------------------------------

-- The player's map and its parents, innermost first.
local function MapChain()
	local chain = {}
	local mapID = C_Map.GetBestMapForUnit("player")
	while mapID and mapID > 0 and #chain < 10 do
		chain[#chain + 1] = mapID
		local info = C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
	end
	return chain
end

local function Continent()
	for _, mapID in ipairs(MapChain()) do
		local info = C_Map.GetMapInfo(mapID)
		if info and info.mapType == Enum.UIMapType.Continent then
			return mapID
		end
	end
	return nil
end

-- The Trading Post city the player is in, or nil.
function ns.TradingPost_City()
	return ns.TradingPost_CityFor(MapChain())
end

-- At the vendor: remember where it stands (Dornogal's cache has no published spot).
local function LearnSpot()
	local city = ns.TradingPost_City()
	if not city then
		return
	end
	local pos = C_Map.GetPlayerMapPosition(city.map, "player")
	if pos and not ns.IsSecret(pos.x) and pos.x > 0 then
		db.spots[city.key] = { map = city.map, x = pos.x, y = pos.y }
	end
end

-- A waypoint to the nearest Collector's Cache (prints what it did).
function ns.TradingPost_Waypoint()
	local city, spot = ns.TradingPost_PickSpot(db.spots, Continent(), UnitFactionGroup("player"))
	if not city then
		ns.Print("no Trading Post known near you yet. Visit one (Stormwind, Orgrimmar or Dornogal) once.")
		return
	end
	if not C_Map.CanSetUserWaypointOnMap(spot.map) then
		ns.Print("can't place a map pin there.")
		return
	end
	local now = ns.TrackPin(spot.map, spot.x, spot.y)
	ns.Print(("%s the Trading Post in %s."):format(now and "tracking" or "after combat: tracking", city.name))
end

-- Tracking ---------------------------------------------------------------------------------------------------

-- Adds the activity to the objective tracker, or takes it off (what a shift-click in the Traveler's Log does).
function ns.TradingPost_ToggleTrack(a)
	if a.tracked then
		C_PerksActivities.RemoveTrackedPerksActivity(a.id)
	elseif not a.completed then
		C_PerksActivities.AddTrackedPerksActivity(a.id)
	end
end

-- Reads ------------------------------------------------------------------------------------------------------

function ns.TradingPost_ReadAll()
	ReadLog()
	ReadTender()
	RequestChest()
	Changed()
end

local readSoon = ns.UI.Debounce(READ_DELAY, function()
	ReadLog()
	ReadTender()
	Changed()
end)

events:On("read", "PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if isLogin or isReload then
		ReadLog()
		ReadTender()
		RequestChest(CHEST_DELAY)
		Changed()
	end
end)

-- A finished activity can cross a milestone, which adds Tender to the cache.
local function LogChanged()
	readSoon()
	RequestChest()
end
events:On("read", "PERKS_ACTIVITIES_UPDATED", LogChanged)
events:On("read", "PERKS_ACTIVITY_COMPLETED", LogChanged)
events:On("read", "PERKS_ACTIVITIES_TRACKED_UPDATED", readSoon)

-- Opening the cache pays out Tender: ask again what's left in it.
local function TenderChanged()
	readSoon()
	RequestChest()
end
events:On("read", "PERKS_PROGRAM_CURRENCY_REFRESH", TenderChanged)
events:On("read", "PERKS_PROGRAM_CURRENCY_AWARDED", TenderChanged)
events:On("read", "CURRENCY_DISPLAY_UPDATE", function(_, currencyType)
	if currencyType == ns.TRADINGPOST_CURRENCY then
		TenderChanged()
	end
end)

events:On("read", "PERKS_PROGRAM_OPEN", function()
	vendorOpen = true
	LearnSpot()
	readShopSoon()
end)
events:On("read", "PERKS_PROGRAM_DATA_REFRESH", readShopSoon)
events:On("read", "PERKS_PROGRAM_PURCHASE_SUCCESS", readShopSoon)
events:On("read", "PERKS_PROGRAM_PURCHASE_CART_SUCCESS", readShopSoon)
events:On("read", "PERKS_PROGRAM_REFUND_SUCCESS", readShopSoon)
events:On("read", "PERKS_PROGRAM_CLOSE", function()
	ReadShop() -- the last look, before the list goes away
	vendorOpen = false
	Changed()
end)

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "CHEST_REWARDS_UPDATED_FROM_SERVER", "PERKS_ACTIVITIES_UPDATED",
	"PERKS_ACTIVITY_COMPLETED", "PERKS_ACTIVITIES_TRACKED_UPDATED", "PERKS_PROGRAM_CURRENCY_REFRESH",
	"PERKS_PROGRAM_CURRENCY_AWARDED", "CURRENCY_DISPLAY_UPDATE", "PERKS_PROGRAM_OPEN", "PERKS_PROGRAM_DATA_REFRESH",
	"PERKS_PROGRAM_PURCHASE_SUCCESS", "PERKS_PROGRAM_PURCHASE_CART_SUCCESS", "PERKS_PROGRAM_REFUND_SUCCESS",
	"PERKS_PROGRAM_CLOSE",
}

function ns.TradingPost_ReadInit(saved)
	db = saved
end

-- inWorld: the module was turned on mid-session (no PLAYER_ENTERING_WORLD is coming), so read now.
function ns.TradingPost_ReadStart(inWorld)
	for _, event in ipairs(EVENTS) do
		events:Watch("read", event)
	end
	if inWorld then
		ns.TradingPost_ReadAll()
	end
end

function ns.TradingPost_ReadStop()
	events:UnwatchAll("read")
	vendorOpen = false
	if monthTimer then
		monthTimer:Cancel()
		monthTimer = nil
	end
	if chestTimer then
		chestTimer:Cancel()
		chestTimer = nil
	end
end
