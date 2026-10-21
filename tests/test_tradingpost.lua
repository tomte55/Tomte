-- Run from the AddOns folder: lua Tomte/tests/test_tradingpost.lua
local ns = {}
assert(loadfile("Tomte/Modules/TradingPost/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local THRESHOLDS = {
	{ index = 2, required = 400, tender = 100 },
	{ index = 1, required = 200, tender = 100 },
	{ index = 3, required = 1000, tender = 300 },
}

local function names(list)
	local out = {}
	for i, a in ipairs(list) do
		out[i] = a.name
	end
	return table.concat(out, " ")
end

test("Points: completed activities only, capped at the top milestone", function()
	local acts = { { completed = true, points = 300 }, { completed = false, points = 500 },
		{ completed = true, points = 100 } }
	local earned, max = ns.TradingPost_Points(acts, THRESHOLDS)
	eq(earned, 400)
	eq(max, 1000)
	earned = ns.TradingPost_Points({ { completed = true, points = 1500 } }, THRESHOLDS)
	eq(earned, 1000, "capped")
end)

test("Points: no thresholds falls back to 1000", function()
	local _, max = ns.TradingPost_Points({}, {})
	eq(max, 1000)
end)

test("Milestones: sorted, reached, next and Tender left", function()
	local list, nextOne, left = ns.TradingPost_Milestones(THRESHOLDS, 250)
	eq(list[1].required, 200)
	eq(list[1].reached, true)
	eq(list[2].reached, false)
	eq(nextOne.required, 400)
	eq(left, 400)
	eq(ns.TradingPost_NextText(250, nextOne), "150 points to the next 100 Tender")
	local _, none, zero = ns.TradingPost_Milestones(THRESHOLDS, 1000)
	eq(none, nil)
	eq(zero, 0)
	eq(ns.TradingPost_NextText(1000, none), nil)
end)

test("ParseProgress reads localized counts", function()
	local a, b = ns.TradingPost_ParseProgress("3 / 5")
	eq(a, 3)
	eq(b, 5)
	a, b = ns.TradingPost_ParseProgress("Kill rares: 1,000/2,500")
	eq(a, 1000)
	eq(b, 2500)
	a, b = ns.TradingPost_ParseProgress("1.000 / 2.500")
	eq(a, 1000)
	eq(b, 2500)
	a = ns.TradingPost_ParseProgress("Complete a dungeon")
	eq(a, nil)
	a = ns.TradingPost_ParseProgress(nil)
	eq(a, nil)
	a, b = ns.TradingPost_ParseProgress("7 / 5")
	eq(a, 5, "capped at the goal")
end)

test("Progress: first unfinished requirement with a count", function()
	local cur, max, f = ns.TradingPost_Progress({ requirements = {
		{ completed = true, text = "5 / 5" }, { completed = false, text = "1 / 4" } } })
	eq(cur, 1)
	eq(max, 4)
	eq(f, 0.25)
	local _, _, done = ns.TradingPost_Progress({ completed = true })
	eq(done, 1)
	eq(ns.TradingPost_Progress({ requirements = { { text = "Do it" } } }), nil)
end)

test("SortActivities: under way by progress, then not started by points, done last", function()
	local list = ns.TradingPost_SortActivities({
		{ name = "Done", completed = true, points = 50 },
		{ name = "Fresh50", points = 50, requirements = { { text = "0 / 5" } } },
		{ name = "Half", points = 25, requirements = { { text = "5 / 10" } } },
		{ name = "Fresh100", points = 100 },
		{ name = "Nearly", points = 10, requirements = { { text = "9 / 10" } } },
		{ name = "Started", points = 30, inProgress = true },
	})
	eq(names(list), "Nearly Half Started Fresh100 Fresh50 Done")
	eq(ns.TradingPost_Closest(list).name, "Nearly")
	eq(ns.TradingPost_Closest({ { name = "x", completed = true } }), nil)
end)

test("Waiting sums Tender and counts item rewards", function()
	local tender, items = ns.TradingPost_Waiting({ { rewardAmount = 500 }, { rewardAmount = 100 },
		{ rewardAmount = 0, perksVendorItemID = 7 } })
	eq(tender, 600)
	eq(items, 1)
	eq((ns.TradingPost_Waiting(nil)), 0)
end)

test("TimeLeft wording", function()
	eq(ns.TradingPost_TimeLeft(9 * 86400 + 3600), "9 days")
	eq(ns.TradingPost_TimeLeft(86400 + 5 * 3600), "1 day 5 h")
	eq(ns.TradingPost_TimeLeft(86400), "1 day")
	eq(ns.TradingPost_TimeLeft(5 * 3600 + 59), "5 h")
	eq(ns.TradingPost_TimeLeft(40 * 60), "40 min")
	eq(ns.TradingPost_TimeLeft(5), "1 min")
end)

local ON = { newMonth = true, waiting = true, ending = true }

test("LoginToasts: the first month ever is only remembered", function()
	local seen = { month = 0, waitingDay = "", endingDay = "" }
	local out = ns.TradingPost_LoginToasts({ month = 40, waiting = 0, secondsLeft = 9 * 86400 }, seen, "d1", ON)
	eq(#out, 0)
	eq(seen.month, 40)
end)

test("LoginToasts: a new month carries the waiting Tender", function()
	local seen = { month = 39, waitingDay = "", endingDay = "" }
	local out = ns.TradingPost_LoginToasts({ month = 40, waiting = 500, secondsLeft = 30 * 86400 }, seen, "d1", ON)
	eq(table.concat(out, " "), "newMonth")
	eq(seen.waitingDay, "d1")
	out = ns.TradingPost_LoginToasts({ month = 40, waiting = 500, secondsLeft = 30 * 86400 }, seen, "d1", ON)
	eq(#out, 0, "same day again")
	out = ns.TradingPost_LoginToasts({ month = 40, waiting = 500, secondsLeft = 29 * 86400 }, seen, "d2", ON)
	eq(table.concat(out, " "), "waiting", "next day")
end)

test("LoginToasts: waiting alone when the new-month switch is off", function()
	local seen = { month = 39, waitingDay = "", endingDay = "" }
	local out = ns.TradingPost_LoginToasts({ month = 40, waiting = 500 }, seen, "d1",
		{ newMonth = false, waiting = true, ending = true })
	eq(table.concat(out, " "), "waiting")
	eq(seen.month, 40)
end)

test("LoginToasts: month ending only with a milestone open, once a day", function()
	local seen = { month = 40, waitingDay = "", endingDay = "" }
	local s = { month = 40, waiting = 0, secondsLeft = 2 * 86400, open = true }
	eq(table.concat(ns.TradingPost_LoginToasts(s, seen, "d1", ON), " "), "ending")
	eq(#ns.TradingPost_LoginToasts(s, seen, "d1", ON), 0)
	s.open = false
	eq(#ns.TradingPost_LoginToasts(s, seen, "d2", ON), 0, "all reached")
	s.open, s.secondsLeft = true, 5 * 86400
	eq(#ns.TradingPost_LoginToasts(s, seen, "d3", ON), 0, "not the last days yet")
	eq(#ns.TradingPost_LoginToasts({ waiting = 0, open = true, secondsLeft = 3600 }, seen, "d4", ON), 0,
		"no log: no ending reminder")
end)

test("CityFor finds the city among the parent maps", function()
	eq(ns.TradingPost_CityFor({ 1519, 84, 13 }).key, "stormwind")
	eq(ns.TradingPost_CityFor({ 2339, 2248 }).key, "dornogal")
	eq(ns.TradingPost_CityFor({ 2248, 2274 }), nil)
end)

test("PickSpot: own continent, else faction capital; learned spots win", function()
	local city, spot = ns.TradingPost_PickSpot({}, 12, "Alliance")
	eq(city.key, "orgrimmar", "Kalimdor has Orgrimmar")
	eq(spot.map, 85)
	city = ns.TradingPost_PickSpot({}, 2274, "Alliance")
	eq(city.key, "stormwind", "Dornogal not learned yet")
	city, spot = ns.TradingPost_PickSpot({ dornogal = { map = 2339, x = 0.5, y = 0.4 } }, 2274, "Alliance")
	eq(city.key, "dornogal")
	eq(spot.y, 0.4)
	eq(ns.TradingPost_PickSpot({}, 2274, "Neutral"), nil)
end)

test("ShopSummary and ShopText", function()
	local items = { { price = 700 }, { price = 300 }, { price = 100, state = "bought" }, { price = 50, state = "owned" } }
	local s = ns.TradingPost_ShopSummary(items, 500)
	eq(s.total, 4)
	eq(s.missing, 2)
	eq(s.affordable, 1)
	eq(ns.TradingPost_ShopText(s), "2 you don't have, 1 you can afford")
	eq(ns.TradingPost_ShopText(ns.TradingPost_ShopSummary({ { state = "owned" } }, 0)),
		"You have everything in the shop")
	eq(ns.TradingPost_ShopText(ns.TradingPost_ShopSummary({}, 0)), nil)
end)

test("SortShop: mounts first, dearest first", function()
	local list = ns.TradingPost_SortShop({
		{ name = "Hat", category = 1, price = 100 }, { name = "Horse", category = 2, price = 700 },
		{ name = "Cat", category = 3, price = 400 }, { name = "Robe", category = 1, price = 300 },
		{ name = "Odd", category = 42, price = 1 },
	})
	eq(names(list), "Horse Cat Robe Hat Odd")
	eq(ns.TradingPost_CategoryWord(2), "Mount")
	eq(ns.TradingPost_CategoryWord(42), "Other")
end)

H.done()
