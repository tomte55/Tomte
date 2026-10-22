-- Run from the AddOns folder: lua Tomte/tests/test_slotsrules.lua
local ns = {}
assert(loadfile("Tomte/Modules/Games/CardData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/BlackjackRules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/SlotsRules.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

local function thousands(n)
	return tostring(n)
end

local function newGame()
	local game = ns.Blackjack_NewGame()
	ns.Slots_Repair(game)
	return game
end

-- A random(n) that stops the reels at these stops, in order.
local function stopsAt(...)
	local stops, i = { ... }, 0
	return function()
		i = i + 1
		return stops[i]
	end
end

-- The stop on reel i where `key` is in the middle row.
local function find(i, key)
	for n, k in ipairs(ns.SLOTS_REELS[i]) do
		if k == key then
			return n
		end
	end
end

test("each reel has 26 stops with the planned counts, no symbol next to itself", function()
	local want = { murloc = 10, copper = 5, silver = 4, gold = 3, ruby = 3, hearth = 1 }
	for i, reel in ipairs(ns.SLOTS_REELS) do
		eq(#reel, 26, "reel " .. i)
		local counts = {}
		for n, key in ipairs(reel) do
			counts[key] = (counts[key] or 0) + 1
			eq(key ~= ns.Slots_At(i, n + 1), true, "reel " .. i .. " stop " .. n)
		end
		for key, n in pairs(want) do
			eq(counts[key], n, "reel " .. i .. " " .. key)
		end
	end
end)

test("the machine pays back 94.9% over time", function()
	near(ns.Slots_ReturnRate(), 0.94902, "return rate")
end)

test("line pays: three of a kind, any three bars, else nothing", function()
	eq(ns.Slots_LinePay("murloc", "murloc", "murloc"), 4)
	eq(ns.Slots_LinePay("hearth", "hearth", "hearth"), 1000)
	eq(select(2, ns.Slots_LinePay("gold", "gold", "gold")), "three")
	eq(ns.Slots_LinePay("copper", "gold", "silver"), 2)
	eq(select(2, ns.Slots_LinePay("copper", "copper", "silver")), "bars")
	eq(ns.Slots_LinePay("murloc", "murloc", "copper"), 0)
	eq(ns.Slots_LinePay("ruby", "gold", "gold"), 0)
end)

test("cells wrap around the strip", function()
	eq(ns.Slots_Cell(1, 1, 1), ns.SLOTS_REELS[1][26])
	eq(ns.Slots_Cell(1, 26, 3), ns.SLOTS_REELS[1][1])
	eq(ns.Slots_Cell(2, 5, 2), ns.SLOTS_REELS[2][5])
end)

test("a jackpot on the middle line", function()
	local game = newGame()
	game.slots.bet = 50
	local h1, h2, h3 = find(1, "hearth"), find(2, "hearth"), find(3, "hearth")
	eq(ns.Slots_Spin(game, stopsAt(h1, h2, h3)), true)
	local last = game.slots.last
	eq(last.jackpot, true)
	eq(last.wins[1].line, 1)
	eq(last.wins[1].pay, 10000) -- 1,000 times the line bet of 10
	eq(last.payout >= 10000, true)
	eq(game.chips, 1000 - 50 + last.payout)
	eq(game.slots.stats.jackpots, 1)
	eq(game.slots.stats.net, last.payout - 50)
	eq(game.slots.stats.spins, 1)
	eq(game.slots.stats.wins, 1)
	eq(game.stats.peak, game.chips)
	eq(game.slots.stops[1], h1)
	eq(ns.Slots_ResultText(last, thousands):sub(1, 8), "Jackpot!")
end)

test("wins are found on every line, diagonals too", function()
	-- Pick stops that put murlocs top-left, middle-middle and bottom-right: the falling diagonal (line 4).
	local function stopWith(i, key, row)
		for n = 1, 26 do
			if ns.Slots_Cell(i, n, row) == key then
				return n
			end
		end
	end
	local stops = { stopWith(1, "murloc", 1), stopWith(2, "murloc", 2), stopWith(3, "murloc", 3) }
	local wins = ns.Slots_Wins(stops, 10)
	local found = false
	for _, win in ipairs(wins) do
		if win.line == 4 then
			found = true
			eq(win.pay, 8) -- 4 times the line bet of 2
			eq(win.symbol, "murloc")
		end
	end
	eq(found, true)
end)

test("a spin needs the chips; bets are the chip values", function()
	local game = newGame()
	eq(ns.Slots_SetBet(game, 100), true)
	eq(ns.Slots_SetBet(game, 30), false)
	game.chips = 90
	eq(select(2, ns.Slots_Spin(game, stopsAt(1, 1, 1))), "chips")
	eq(game.chips, 90)
	eq(game.slots.stats.spins, 0)
end)

test("result text", function()
	eq(ns.Slots_ResultText({ jackpot = false, payout = 0, wins = {} }, thousands), "No win. Spin again?")
	eq(ns.Slots_ResultText({ jackpot = false, payout = 8, wins = { {} } }, thousands), "One line pays 8.")
	eq(ns.Slots_ResultText({ jackpot = false, payout = 20, wins = { {}, {} } }, thousands), "2 lines pay 20.")
end)

test("repair fills in a missing or damaged game", function()
	local game = ns.Blackjack_NewGame()
	local slots = ns.Slots_Repair(game)
	eq(slots.bet, 10)
	eq(#slots.stops, 3)
	eq(slots.stats.jackpots, 0)
	slots.bet, slots.stops, slots.last = 7, { 1 }, { payout = 3 }
	ns.Slots_Repair(game)
	eq(slots.bet, 10)
	eq(slots.stops[3], 1)
	eq(slots.last, nil)
	slots.last = { payout = 4, wins = { { line = 1, pay = 4, symbol = "diamond", kind = "three" } } }
	ns.Slots_Repair(game)
	eq(slots.last, nil, "a result naming a symbol that's gone")
	local kept = { payout = 4, wins = { { line = 1, pay = 4, symbol = "ruby", kind = "three" } } }
	slots.last = kept
	ns.Slots_Repair(game)
	eq(slots.last, kept)
end)

H.done()
