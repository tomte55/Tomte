local addonName, ns = ...

-- Trading Post module: Trader's Tender waiting in the Collector's Cache (with a waypoint to it), the month's time
-- left before the shop and the Traveler's Log turn over, the Traveler's Log itself (points, milestones, activities
-- with a click to track) and the shop from your last visit. A page in the Tomte window, reminders as toasts, two
-- Next up sources and an "Around you" block in the Trading Post cities. Pure logic: Data.lua; reads: Read.lua;
-- the page: Page.lua; the buy button in Blizzard's Trading Post window: Buy.lua. See docs/superpowers/specs/2026-10-21-tomte-trading-post-design.md.

local OWNER = "tradingpost"
local ICON = "Interface\\Icons\\INV_Misc_Treasurechest02b"
local LOGIN_FALLBACK = 20 -- seconds to wait for the cache's answer before the login reminders go without it
local CITY_DELAY = 2 -- seconds after a zone change before checking for a Trading Post city
-- Made-up state for the sample toast and the settings previews: the monthly 500 Tender, a log milestone still open,
-- two days and a bit left.
local SAMPLE_STATE = { waiting = 500, earned = 850, nextOne = { required = 1000, tender = 100 },
	secondsLeft = 2 * 86400 + 5 * 3600 }
local SAMPLE_CITY = { name = "Dornogal" }

local UI = ns.UI
local module, db
local loginPending, loginTimer
local cityToasted = {} -- [city key] = true once this session
local lastCity

local events = ns.TradingPost_Events

local function OpenPage()
	ns.Panel_OpenPage("tradingpost")
end

local function TenderIcon()
	return ns.TradingPost_State().tenderIcon or ICON
end

-- Toasts ---------------------------------------------------------------------------------------------------------

-- The parts every reminder shares. sample: a settings preview or the sample button (kept out of Recent).
local function Spec(spec, sample)
	spec.owner, spec.label = OWNER, spec.label or "Trading Post"
	spec.accent = spec.accent or "accent"
	spec.holdInCombat, spec.hold = true, spec.hold or 10
	spec.test = sample or nil
	return spec
end

-- Each reminder's spec takes the state it reads (ns.TradingPost_State() plus secondsLeft), so a preview can hand it
-- SAMPLE_STATE instead.
local function WaitingSpec(s, sample)
	return Spec({
		title = ("%s Tender waiting"):format(ns.Thousands(s.waiting)),
		text = "Trader's Tender in the Collector's Cache at a Trading Post." .. (sample and "" or "\nClick for a waypoint."),
		icon = TenderIcon(), accent = "success", mergeKey = "tradingpost:waiting",
		onClick = not sample and ns.TradingPost_Waypoint or nil,
	}, sample)
end

local function NewMonthSpec(s, sample)
	local text = "New stock and a fresh Traveler's Log."
	if s.waiting > 0 then
		text = text .. ("\n%s Tender waiting in the Collector's Cache. Click for a waypoint."):format(
			ns.Thousands(s.waiting))
	else
		text = text .. "\nClick for the Trading Post page."
	end
	return Spec({
		title = "A new month", text = text, icon = ICON, mergeKey = "tradingpost:month",
		hold = 12, onClick = s.waiting > 0 and ns.TradingPost_Waypoint or OpenPage,
	}, sample)
end

local function EndingSpec(s, sample)
	return Spec({
		title = ("Month ends in %s"):format(ns.TradingPost_TimeLeft(s.secondsLeft)),
		text = ("Traveler's Log: %s.\nClick for the activities."):format(ns.TradingPost_NextText(s.earned, s.nextOne)
			or "every milestone reached"),
		icon = TenderIcon(), accent = "warning", mergeKey = "tradingpost:ending", onClick = OpenPage,
	}, sample)
end

local function CitySpec(s, city, sample)
	return Spec({
		title = ("%s Tender waiting"):format(ns.Thousands(s.waiting)),
		text = ("The Collector's Cache is here in %s. Click for a waypoint."):format(city.name),
		icon = TenderIcon(), accent = "success", mergeKey = "tradingpost:waiting", onClick = ns.TradingPost_Waypoint,
	}, sample)
end

local function WaitingToast(sample)
	ns.Toast_Show(WaitingSpec(sample and SAMPLE_STATE or ns.TradingPost_State(), sample))
end

local function NewMonthToast()
	ns.Toast_Show(NewMonthSpec(ns.TradingPost_State()))
end

local function EndingToast()
	local s = ns.TradingPost_State()
	ns.Toast_Show(EndingSpec({ earned = s.earned, nextOne = s.nextOne, secondsLeft = ns.TradingPost_SecondsLeft() }))
end

local function CityToast(city)
	ns.Toast_Show(CitySpec(ns.TradingPost_State(), city))
end

-- Settings previews (Panel/Preview.lua): each reminder from SAMPLE_STATE, built by the real reminders' spec code.
local function WaitingPreview(host)
	return ns.Toast_DrawSample(host, WaitingSpec(SAMPLE_STATE, true), 1)
end

local function CityPreview(host)
	return ns.Toast_DrawSample(host, CitySpec(SAMPLE_STATE, SAMPLE_CITY, true), 1)
end

local function NewMonthPreview(host)
	return ns.Toast_DrawSample(host, NewMonthSpec(SAMPLE_STATE, true), 1)
end

local function EndingPreview(host)
	return ns.Toast_DrawSample(host, EndingSpec(SAMPLE_STATE, true), 1)
end

local LOGIN_TOASTS = { newMonth = NewMonthToast, waiting = WaitingToast, ending = EndingToast }

-- Once per login, when the cache's answer and the month's time left are in (or LOGIN_FALLBACK passed without them).
local function LoginToasts()
	if not (loginPending and module.active) then
		return
	end
	loginPending = false
	if loginTimer then
		loginTimer:Cancel()
		loginTimer = nil
	end
	local s = ns.TradingPost_State()
	local kinds = ns.TradingPost_LoginToasts({
		month = s.available and s.month or nil, waiting = s.waiting, secondsLeft = ns.TradingPost_SecondsLeft(),
		open = s.nextOne ~= nil,
	}, db.seen, date("%Y-%m-%d"), db.toasts)
	for _, kind in ipairs(kinds) do
		LOGIN_TOASTS[kind]()
	end
	-- Logging in at a Trading Post: the login reminder already said it.
	local city = ns.TradingPost_City()
	if city then
		cityToasted[city.key] = true
	end
end

local function CheckCity()
	local city = ns.TradingPost_City()
	local key = city and city.key
	if key == lastCity then
		return
	end
	lastCity = key
	if city and db.toasts.city and not cityToasted[key] and not loginPending
		and ns.TradingPost_State().waiting > 0 then
		cityToasted[key] = true
		CityToast(city)
	end
end

local checkCitySoon = UI.Debounce(CITY_DELAY, function()
	if module.active then
		CheckCity()
	end
end)

-- After every read (Read.lua): redraw, and the login reminders once the cache has answered.
function ns.TradingPost_OnChanged()
	if not module.active then
		return
	end
	ns.TradingPostPage_Refresh()
	ns.TradingPostBuy_Refresh()
	if ns.Panel_IsShown() then
		ns.Panel_Refresh()
	end
	local s = ns.TradingPost_State()
	if loginPending and s.chestKnown and (not s.available or ns.TradingPost_SecondsLeft()) then
		LoginToasts()
	end
	if not loginPending then
		CheckCity()
	end
end

local function StartLogin()
	loginPending = true
	if loginTimer then
		loginTimer:Cancel()
	end
	loginTimer = C_Timer.NewTimer(LOGIN_FALLBACK, function()
		loginTimer = nil
		LoginToasts()
	end)
end

events:On("main", "PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if isLogin or isReload then
		StartLogin()
	end
	checkCitySoon()
end)
events:On("main", "ZONE_CHANGED_NEW_AREA", checkCitySoon)

-- Home -----------------------------------------------------------------------------------------------------------

local function Summary()
	local s = ns.TradingPost_State()
	local parts = { ("%s Tender"):format(ns.Thousands(s.tender)) }
	if s.waiting > 0 then
		parts[#parts + 1] = ("%s waiting"):format(ns.Thousands(s.waiting))
	end
	if s.available then
		parts[#parts + 1] = ("%s/%s points"):format(ns.Thousands(s.earned), ns.Thousands(s.max))
	end
	return table.concat(parts, " · ")
end

local function MonthLeftText()
	local left = ns.TradingPost_SecondsLeft()
	return left and ("Shop and Traveler's Log refresh in %s"):format(ns.TradingPost_TimeLeft(left)) or nil
end

local PAGE = { kind = "page", key = "tradingpost", order = 43, name = "Trading Post", icon = ICON,
	page = ns.TradingPostPage, summary = Summary,
	pill = function()
		return ns.TradingPost_State().waiting > 0 and 1 or 0
	end,
	pillTip = "Trader's Tender waiting in the Collector's Cache" }

local function WaypointTip(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText("Collector's Cache", UI.Color("heading"))
	GameTooltip:AddLine("Open it to collect your Tender.", UI.RGB("textMuted"))
	GameTooltip:AddLine("Click: waypoint", UI.RGB("accent"))
	GameTooltip:Show()
end

local AROUND = { kind = "around", key = "tradingpostaround", order = 7, name = "Trading Post", maxRows = 3,
	icon = ICON, open = OpenPage, openText = "Opens the Trading Post page",
	shown = function()
		return ns.TradingPost_City() ~= nil
	end,
	title = function()
		local s = ns.TradingPost_State()
		if s.waiting > 0 then
			return ("Trading Post: %s Tender waiting"):format(ns.Thousands(s.waiting))
		end
		return ("Trading Post: %s Tender"):format(ns.Thousands(s.tender))
	end,
	items = function(limit)
		local s = ns.TradingPost_State()
		local rows = {}
		if s.waiting > 0 then
			rows[#rows + 1] = { icon = TenderIcon(), text = "Collector's Cache", color = "success",
				right = ns.Thousands(s.waiting), onClick = ns.TradingPost_Waypoint, onEnter = WaypointTip }
		end
		local shop = ns.TradingPost_Shop()
		local shopText = shop and ns.TradingPost_ShopText(ns.TradingPost_ShopSummary(shop.items, s.tender))
		rows[#rows + 1] = { icon = ICON, text = shopText or "Shop: not seen this month", onClick = OpenPage }
		local left = MonthLeftText()
		if left then
			rows[#rows + 1] = { icon = ICON, text = left, color = "textMuted", onClick = OpenPage }
		end
		while #rows > limit do
			table.remove(rows)
		end
		return rows
	end }

local NEXT_TENDER = { kind = "next", key = "nexttender", name = "Trader's Tender waiting", score = 85,
	description = "Tender is waiting in the Collector's Cache at a Trading Post (click for a waypoint).",
	candidates = function()
		local s = ns.TradingPost_State()
		if s.waiting <= 0 then
			return {}
		end
		return { {
			key = "tradingpost:waiting", state = s.waiting,
			text = ("%s Trader's Tender waiting"):format(ns.Thousands(s.waiting)),
			why = "In the Collector's Cache at a Trading Post.", icon = TenderIcon(),
			onClick = ns.TradingPost_Waypoint, hint = "Click for a waypoint",
		} }
	end }

local NEXT_LOG = { kind = "next", key = "nexttravelerslog", name = "Traveler's Log milestone", score = 45,
	description = "In the month's last week, the points still needed for the next Traveler's Log milestone.",
	candidates = function()
		local s = ns.TradingPost_State()
		local left = ns.TradingPost_SecondsLeft()
		if not (s.available and s.nextOne and left and left <= ns.TRADINGPOST_NEXT_DAYS * 86400) then
			return {}
		end
		local closest = ns.TradingPost_Closest(s.sorted)
		return { {
			key = "tradingpost:log", state = ("%s:%d"):format(tostring(s.month), s.earned),
			text = "Traveler's Log: " .. ns.TradingPost_NextText(s.earned, s.nextOne),
			why = ("%s left%s"):format(ns.TradingPost_TimeLeft(left), closest and (" · closest: " .. closest.name) or ""),
			icon = TenderIcon(), onClick = OpenPage, hint = "Click for the activities",
		} }
	end }

-- Commands -------------------------------------------------------------------------------------------------------

local function Status()
	local s = ns.TradingPost_State()
	ns.Print(("%s Trader's Tender%s."):format(ns.Thousands(s.tender),
		not s.chestKnown and " (the cache hasn't answered yet)"
			or s.waiting > 0 and (", %s waiting in the Collector's Cache"):format(ns.Thousands(s.waiting))
			or ", nothing waiting in the Collector's Cache"))
	if not s.available then
		print("  The Traveler's Log isn't open to this character.")
		return
	end
	print(("  %s: %s/%s points, %s."):format(s.monthName or "This month", ns.Thousands(s.earned),
		ns.Thousands(s.max), ns.TradingPost_NextText(s.earned, s.nextOne) or "every milestone reached"))
	local left = MonthLeftText()
	if left then
		print("  " .. left .. ".")
	end
	local closest = ns.TradingPost_Closest(s.sorted)
	if closest then
		local cur, max = ns.TradingPost_Progress(closest)
		print(("  Closest: %s%s, %d points."):format(closest.name, cur and (" (%d/%d)"):format(cur, max) or "",
			closest.points))
	end
end

local function Shop()
	local shop = ns.TradingPost_Shop()
	if not shop then
		ns.Print("no shop seen this month. Visit a Trading Post (Stormwind, Orgrimmar or Dornogal) once.")
		return
	end
	local s = ns.TradingPost_State()
	ns.Print(("the shop, seen %s ago: %s."):format(ns.Ago(GetServerTime() - shop.at),
		ns.TradingPost_ShopText(ns.TradingPost_ShopSummary(shop.items, s.tender)) or "empty"))
	for _, it in ipairs(shop.items) do
		local mark = it.state == "bought" and " (bought)" or it.state == "owned" and " (owned)" or ""
		print(("  %s, %s: %s Tender%s"):format(it.name, ns.TradingPost_CategoryWord(it.category):lower(),
			ns.Thousands(it.price), mark))
	end
end

local function Sample()
	if ns.Module_RequireOn(module) then
		WaitingToast(true)
	end
end

-- Module ---------------------------------------------------------------------------------------------------------

module = ns.RegisterModule({
	key = "tradingpost",
	name = "Trading Post",
	category = "week",
	icon = ICON,
	summary = "Tender waiting in the cache, the Traveler's Log and the month's shop.",
	description = "Reminds you when Trader's Tender is waiting in the Collector's Cache (with a waypoint to it) and "
		.. "when a new month brings new stock. A page with the Traveler's Log (points, milestones and the activities "
		.. "closest to done, click to track one) and the shop from your last visit, marked with what you already own.",
	enabledByDefault = true,
	toasts = "Trading Post reminders",
	defaults = {
		toasts = { waiting = true, city = true, newMonth = true, ending = true },
		seen = { month = 0, waitingDay = "", endingDay = "" }, -- last Trading Post month seen, last day a toast showed
		spots = {}, -- [city key] = { map = uiMapID, x, y } (0..1), where the vendor stands, learned on a visit
		shop = {}, -- { month = activePerksMonth, at = server time, items = { { id, name, icon, price, category,
		-- itemID, mountID, speciesID, setID, appearanceID, bought, pending } } }, from the last visit
	},
	noShare = { "seen", "spots", "shop" }, -- reminder memory and collected data: not in settings strings
	init = function(saved)
		db = saved
		ns.TradingPost_ReadInit(db)
	end,
	toggle = function(active)
		if active then
			events:Watch("main", "PLAYER_ENTERING_WORLD")
			events:Watch("main", "ZONE_CHANGED_NEW_AREA")
			ns.TradingPost_ReadStart(ns.inWorld)
			if ns.inWorld then
				StartLogin()
			end
		else
			events:UnwatchAll("main")
			ns.TradingPost_ReadStop()
			ns.TradingPostBuy_Stop()
			loginPending, lastCity = false, nil
			if loginTimer then
				loginTimer:Cancel()
				loginTimer = nil
			end
			ns.Toast_Clear(OWNER)
		end
	end,
	home = { PAGE, AROUND, NEXT_TENDER, NEXT_LOG },
	commands = {
		{ "", "open the Trading Post page", OpenPage, hidden = true },
		{ "open", "open the Trading Post page", OpenPage },
		{ "status", "your Tender, the cache, the Traveler's Log and the time left, in chat", Status },
		{ "shop", "the shop from your last visit this month, in chat", Shop },
		{ "way", "a waypoint to the nearest Collector's Cache", function()
			ns.TradingPost_Waypoint()
		end },
		{ "test", "show a sample toast", Sample },
	},
	options = {
		{ type = "header", label = "Reminders" },
		{ type = "checkbox", key = "toasts.waiting", label = "Tender waiting",
			preview = ns.Preview_When("toasts.waiting", WaitingPreview),
			tooltip = "At login, once a day, when Trader's Tender is waiting in the Collector's Cache. Every account "
				.. "with game time gets 500 there each month." },
		{ type = "checkbox", key = "toasts.city", label = "In a Trading Post city",
			preview = ns.Preview_When("toasts.city", CityPreview),
			tooltip = "Entering Stormwind, Orgrimmar or Dornogal while Tender is waiting in the cache." },
		{ type = "checkbox", key = "toasts.newMonth", label = "New month",
			preview = ns.Preview_When("toasts.newMonth", NewMonthPreview),
			tooltip = "The first login of a new month: new stock in the shop and a fresh Traveler's Log." },
		{ type = "checkbox", key = "toasts.ending", label = "Month ending",
			preview = ns.Preview_When("toasts.ending", EndingPreview),
			tooltip = "In the month's last three days, once a day, while a Traveler's Log milestone is still open." },
		{ type = "button", label = "Sample toast", text = "Show", onClick = Sample },
		{ type = "header", label = "Trading Post" },
		{ type = "button", label = "Page", text = "Open", onClick = OpenPage },
		{ type = "button", label = "Collector's Cache", text = "Waypoint", onClick = function()
			ns.TradingPost_Waypoint()
		end, tooltip = "A waypoint to the nearest Collector's Cache: the Trading Post on your continent, else your "
			.. "faction's capital." },
	},
})
