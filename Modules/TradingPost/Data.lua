local addonName, ns = ...

-- Trading Post: pure logic (no WoW API calls; unit-tested in tests/test_tradingpost.lua). Traveler's Log points and
-- milestones, activity progress and order, Tender waiting in the Collector's Cache, which reminder to show, where
-- the nearest cache is and the remembered shop. Read.lua fills the tables, TradingPost.lua registers the module.

ns.TRADINGPOST_CURRENCY = 2032 -- Trader's Tender (Constants.CurrencyConsts.CURRENCY_ID_PERKS_PROGRAM_DISPLAY_INFO)
ns.TRADINGPOST_ENDING_DAYS = 3 -- the "month ending" reminder shows in the month's last days
ns.TRADINGPOST_NEXT_DAYS = 7 -- Next up suggests an open milestone in the month's last days
local DEFAULT_MAX = 1000 -- Blizzard's own fallback when a month has no thresholds

-- The Trading Posts. x, y: the Collector's Cache (warcraft.wiki.gg, Collector's Cache); Dornogal has none published,
-- so its spot is learned at the vendor (Read.lua). continent: the uiMap of the continent the city is on.
ns.TRADINGPOST_CITIES = {
	{ key = "stormwind", name = "Stormwind", map = 84, continent = 13, faction = "Alliance", x = 0.513, y = 0.724 },
	{ key = "orgrimmar", name = "Orgrimmar", map = 85, continent = 12, faction = "Horde", x = 0.484, y = 0.757 },
	{ key = "dornogal", name = "Dornogal", map = 2339, continent = 2274 },
}

-- Enum.PerksVendorCategoryType -> the word on a shop row, in the order the shop list shows them.
ns.TRADINGPOST_CATEGORIES = {
	{ id = 2, word = "Mount" },
	{ id = 3, word = "Pet" },
	{ id = 8, word = "Set" },
	{ id = 1, word = "Appearance" },
	{ id = 5, word = "Toy" },
	{ id = 7, word = "Illusion" },
	{ id = 9, word = "Warband scene" },
}
local CATEGORY_ORDER, CATEGORY_WORD = {}, {}
for i, c in ipairs(ns.TRADINGPOST_CATEGORIES) do
	CATEGORY_ORDER[c.id], CATEGORY_WORD[c.id] = i, c.word
end

function ns.TradingPost_CategoryWord(id)
	return CATEGORY_WORD[id] or "Other"
end

-- Traveler's Log -------------------------------------------------------------------------------------------------

-- Points earned and the top milestone, as Blizzard_MonthlyActivities counts them: the points of the completed
-- activities, capped at the largest threshold.
function ns.TradingPost_Points(activities, thresholds)
	local max = 0
	for _, t in ipairs(thresholds or {}) do
		max = math.max(max, t.required or 0)
	end
	if max == 0 then
		max = DEFAULT_MAX
	end
	local earned = 0
	for _, a in ipairs(activities or {}) do
		if a.completed then
			earned = earned + (a.points or 0)
		end
	end
	return math.min(earned, max), max
end

-- thresholds { required, tender, item, index } -> milestones sorted by points, each with reached; next: the first
-- one not reached (nil when all are); tenderLeft: the Tender still to earn this month.
function ns.TradingPost_Milestones(thresholds, earned)
	local list = {}
	for i, t in ipairs(thresholds or {}) do
		list[i] = { required = t.required or 0, tender = t.tender or 0, item = t.item, index = t.index }
	end
	table.sort(list, function(a, b)
		return a.required < b.required
	end)
	local nextOne, left = nil, 0
	for _, m in ipairs(list) do
		m.reached = earned >= m.required
		if not m.reached then
			nextOne = nextOne or m
			left = left + m.tender
		end
	end
	return list, nextOne, left
end

local function Digits(s)
	return tonumber((s:gsub("%D", "")))
end

-- "3 / 5", "3/5", "1,000 / 2,500" or "1.000/2.500" (localized digit groups) -> 3, 5. nil when there's no count.
function ns.TradingPost_ParseProgress(text)
	if type(text) ~= "string" then
		return nil
	end
	local a, b = text:match("(%d[%d,%.\194\160]*)%s*/%s*(%d[%d,%.\194\160]*)")
	if not a then
		return nil
	end
	local cur, max = Digits(a), Digits(b)
	if not (cur and max and max > 0) then
		return nil
	end
	return math.min(cur, max), max
end

-- An activity's progress from its requirements { completed, text }: the first unfinished one with a count, as
-- cur, max, fraction. A completed activity is 1; none with a count: nil.
function ns.TradingPost_Progress(activity)
	if activity.completed then
		return nil, nil, 1
	end
	for _, r in ipairs(activity.requirements or {}) do
		if not r.completed then
			local cur, max = ns.TradingPost_ParseProgress(r.text)
			if cur then
				return cur, max, cur / max
			end
		end
	end
	return nil
end

-- Open activities first: the ones under way (closest to done first, then more points), then the ones not started
-- (more points first); completed ones last. Ties by name. Returns a new list; activity.fraction is set.
function ns.TradingPost_SortActivities(activities)
	local list = {}
	for i, a in ipairs(activities or {}) do
		local _, _, fraction = ns.TradingPost_Progress(a)
		a.fraction = fraction
		list[i] = a
	end
	local function group(a)
		if a.completed then
			return 3
		end
		return ((a.fraction or 0) > 0 or a.inProgress) and 1 or 2
	end
	table.sort(list, function(a, b)
		local ga, gb = group(a), group(b)
		if ga ~= gb then
			return ga < gb
		end
		if ga == 1 and (a.fraction or 0) ~= (b.fraction or 0) then
			return (a.fraction or 0) > (b.fraction or 0)
		end
		if ga ~= 3 and (a.points or 0) ~= (b.points or 0) then
			return (a.points or 0) > (b.points or 0)
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- The closest open activity (the first of the sorted list that isn't done), or nil.
function ns.TradingPost_Closest(sorted)
	local a = sorted and sorted[1]
	if a and not a.completed then
		return a
	end
	return nil
end

-- Collector's Cache ----------------------------------------------------------------------------------------------

-- GetPendingChestRewards' list -> the Tender waiting and how many other rewards (items) wait with it.
function ns.TradingPost_Waiting(pending)
	local tender, items = 0, 0
	for _, r in ipairs(pending or {}) do
		if (r.rewardAmount or 0) > 0 then
			tender = tender + r.rewardAmount
		elseif r.perksVendorItemID then
			items = items + 1
		end
	end
	return tender, items
end

-- "9 days", "1 day 5 h", "5 h", "40 min".
function ns.TradingPost_TimeLeft(seconds)
	seconds = math.max(seconds or 0, 0)
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	if days >= 2 then
		return days .. " days"
	elseif days == 1 then
		return hours > 0 and ("1 day %d h"):format(hours) or "1 day"
	elseif hours >= 1 then
		return hours .. " h"
	end
	return math.max(math.floor(seconds / 60), 1) .. " min"
end

-- "150 points to the next 100 Tender", nil when every milestone is reached (or there are none).
function ns.TradingPost_NextText(earned, nextOne)
	if not nextOne then
		return nil
	end
	return ("%d points to the next %d Tender"):format(nextOne.required - earned, nextOne.tender)
end

-- Reminders ------------------------------------------------------------------------------------------------------

-- Which login reminders to show, at most one of each, in order. s: { month (nil without the log), waiting,
-- secondsLeft, open (a milestone is still open) }; seen: { month, waitingDay, endingDay } (updated here: it is the
-- module's saved memory); today: "YYYY-MM-DD"; on: the toast switches { newMonth, waiting, ending }.
-- The first month ever seen is only remembered. A new-month reminder carries the waiting Tender, so the separate
-- waiting one is skipped that day.
function ns.TradingPost_LoginToasts(s, seen, today, on)
	local out = {}
	if s.month and s.month ~= seen.month then
		if on.newMonth and (seen.month or 0) ~= 0 then
			out[#out + 1] = "newMonth"
			if (s.waiting or 0) > 0 then
				seen.waitingDay = today
			end
		end
		seen.month = s.month
	end
	if on.waiting and (s.waiting or 0) > 0 and seen.waitingDay ~= today then
		out[#out + 1] = "waiting"
		seen.waitingDay = today
	end
	if on.ending and s.month and s.open and (s.secondsLeft or math.huge) <= ns.TRADINGPOST_ENDING_DAYS * 86400
		and seen.endingDay ~= today then
		out[#out + 1] = "ending"
		seen.endingDay = today
	end
	return out
end

-- Where to go --------------------------------------------------------------------------------------------------

-- The city whose map is in maps (the player's map and its parents), or nil.
function ns.TradingPost_CityFor(maps)
	for _, mapID in ipairs(maps or {}) do
		for _, c in ipairs(ns.TRADINGPOST_CITIES) do
			if c.map == mapID then
				return c
			end
		end
	end
	return nil
end

-- The cache to send the player to: the Trading Post on their continent, else their faction's capital. spots: the
-- learned ones { [city key] = { map, x, y } } (they win over the built-in spot). Returns city, { map, x, y } or nil.
function ns.TradingPost_PickSpot(spots, continent, faction)
	local function spotOf(c)
		local learned = spots and spots[c.key]
		if learned and learned.map and learned.x then
			return learned
		end
		if c.x then
			return { map = c.map, x = c.x, y = c.y }
		end
		return nil
	end
	for _, c in ipairs(ns.TRADINGPOST_CITIES) do
		if continent and c.continent == continent and spotOf(c) then
			return c, spotOf(c)
		end
	end
	for _, c in ipairs(ns.TRADINGPOST_CITIES) do
		if faction and c.faction == faction and spotOf(c) then
			return c, spotOf(c)
		end
	end
	return nil
end

-- The shop -------------------------------------------------------------------------------------------------------

-- items { price, state = "bought" | "owned" | nil } and the player's Tender -> { total, missing (not bought and not
-- owned), affordable (missing ones the Tender covers) }.
function ns.TradingPost_ShopSummary(items, tender)
	local s = { total = 0, missing = 0, affordable = 0 }
	for _, it in ipairs(items or {}) do
		s.total = s.total + 1
		if not it.state then
			s.missing = s.missing + 1
			if (it.price or 0) <= (tender or 0) then
				s.affordable = s.affordable + 1
			end
		end
	end
	return s
end

-- By category (mounts first, see TRADINGPOST_CATEGORIES), then the dearest first, then name. A new list.
function ns.TradingPost_SortShop(items)
	local list = {}
	for i, it in ipairs(items or {}) do
		list[i] = it
	end
	table.sort(list, function(a, b)
		local ca, cb = CATEGORY_ORDER[a.category] or 99, CATEGORY_ORDER[b.category] or 99
		if ca ~= cb then
			return ca < cb
		end
		if (a.price or 0) ~= (b.price or 0) then
			return (a.price or 0) > (b.price or 0)
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- "Shop: 3 you don't have, 2 you can afford", from ShopSummary.
function ns.TradingPost_ShopText(summary)
	if summary.total == 0 then
		return nil
	end
	if summary.missing == 0 then
		return "You have everything in the shop"
	end
	return ("%d you don't have, %d you can afford"):format(summary.missing, summary.affordable)
end
