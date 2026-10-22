-- Run from the AddOns folder: lua Tomte/tests/test_chiprules.lua
local ns = {}
assert(loadfile("Tomte/Modules/Games/CardData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/BlackjackRules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/ChipRules.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local DAY, NEXT_DAY, WEEK = 1000 * 600, 1144 * 600, 2000 * 600

local function thousands(n)
	return tostring(n)
end

test("reset keys ignore a few seconds of jitter", function()
	eq(ns.Chips_ResetKey(100000, 500 * 600 - 100000 + 3), 500 * 600)
	eq(ns.Chips_ResetKey(100002, 500 * 600 - 100000 - 4), 500 * 600)
end)

test("flights pay per whole minute, up to a cap", function()
	local earned = {}
	eq(ns.Chips_FlightPay(earned, DAY, 59), 0)
	eq(ns.Chips_FlightPay(earned, DAY, 185), 30)
	eq(ns.Chips_FlightPay(earned, DAY, 5 * 3600), 200)
	eq(earned.today.flight, 230)
end)

test("quests pay by frequency", function()
	local earned = {}
	eq(ns.Chips_QuestPay(earned, DAY, nil), 25)
	eq(ns.Chips_QuestPay(earned, DAY, "daily"), 50)
	eq(ns.Chips_QuestPay(earned, DAY, "weekly"), 250)
	eq(earned.today.quest, 325)
end)

test("the vault pays once a week", function()
	local earned = {}
	eq(ns.Chips_VaultPay(earned, DAY, WEEK), 1000)
	eq(ns.Chips_VaultPay(earned, NEXT_DAY, WEEK), 0)
	eq(ns.Chips_VaultPay(earned, NEXT_DAY, WEEK + 7 * 86400), 1000)
end)

test("looted gold pays per whole gold, carries copper over and stops at the day's cap", function()
	local earned = {}
	eq(ns.Chips_LootPay(earned, DAY, 25000), 2)
	eq(ns.Chips_LootPay(earned, DAY, 5000), 1) -- 0.5 gold left over plus 0.5 now
	eq(ns.Chips_LootPay(earned, DAY, 10000000), 497)
	eq(ns.Chips_LootPay(earned, DAY, 10000000), 0)
	eq(ns.Chips_LootPay(earned, NEXT_DAY, 30000), 3)
end)

test("a new day starts the tally over", function()
	local earned = {}
	ns.Chips_QuestPay(earned, DAY, nil)
	eq(#ns.Chips_Today(earned, DAY), 1)
	eq(#ns.Chips_Today(earned, NEXT_DAY), 0)
	ns.Chips_FlightPay(earned, NEXT_DAY, 120)
	local today = ns.Chips_Today(earned, NEXT_DAY)
	eq(#today, 1)
	eq(today[1][1], "Flight paths")
	eq(today[1][2], 20)
end)

test("the house refills once a day, to 500", function()
	local game, earned = ns.Blackjack_NewGame(), {}
	eq(ns.Chips_Refill(game, earned, DAY), false) -- still has chips
	game.chips = 0
	eq(ns.Chips_Refill(game, earned, DAY), 500)
	eq(game.chips, 500)
	game.chips = 0
	eq(ns.Chips_RefillReady(earned, DAY), false)
	eq(ns.Chips_Refill(game, earned, DAY), false)
	eq(ns.Chips_Refill(game, earned, NEXT_DAY), 500)
end)

test("wait text", function()
	eq(ns.Chips_WaitText(6 * 3600 + 100), "in 6h")
	eq(ns.Chips_WaitText(25 * 60), "in 25m")
	eq(ns.Chips_WaitText(5), "in 1m")
end)

test("ranks by the most chips held", function()
	local name, nextName, nextAt = ns.Chips_Rank(1000)
	eq(name, "Regular")
	eq(nextName, "High roller")
	eq(nextAt, 25000)
	eq(ns.Chips_Rank(25000), "High roller")
	name, nextName = ns.Chips_Rank(250000)
	eq(name, "Whale")
	eq(nextName, nil)
end)

test("a bet's chip stack: fewest chips, biggest at the bottom, capped", function()
	local values = { 10, 50, 100, 500 }
	local s = ns.Chips_Stack(160, values, 6)
	eq(table.concat(s, ","), "100,50,10")
	eq(table.concat(ns.Chips_Stack(3000, values, 4), ","), "500,500,500,500")
	eq(#ns.Chips_Stack(0, values, 6), 0)
end)

test("float text", function()
	eq(ns.Chips_FloatText("vault", 1000, thousands), "+1000 Great Vault")
end)

H.done()
