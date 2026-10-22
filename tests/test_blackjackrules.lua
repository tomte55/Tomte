-- Run from the AddOns folder: lua Tomte/tests/test_blackjackrules.lua
local ns = {}
assert(loadfile("Tomte/Modules/Games/CardData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/BlackjackRules.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local A, J, Q, K = 1, 11, 12, 13

-- Spades of these ranks.
local function cards(...)
	local out = {}
	for i, rank in ipairs({ ... }) do
		out[i] = ns.Cards_Make(rank, 1)
	end
	return out
end

local function noRandom()
	error("the shoe was reshuffled")
end

-- A game whose shoe deals these ranks first (you, dealer, you, dealer, then hits and the dealer's draws), padded
-- with twos so no reshuffle happens.
local function game(bet, ...)
	local g = ns.Blackjack_NewGame()
	g.shoe = cards(...)
	for _ = #g.shoe + 1, 312 do
		g.shoe[#g.shoe + 1] = ns.Cards_Make(2, 4)
	end
	g.bet = bet
	return g
end

local function thousands(n)
	return tostring(n)
end

test("hand values count aces as 1 or 11", function()
	eq(ns.Blackjack_Value(cards(A, K)), 21)
	eq(select(2, ns.Blackjack_Value(cards(A, 6))), true)
	eq(ns.Blackjack_Value(cards(A, 6, 9)), 16)
	eq(select(2, ns.Blackjack_Value(cards(A, 6, 9))), false)
	eq(ns.Blackjack_Value(cards(A, A, 9)), 21)
	eq(ns.Blackjack_Value(cards(K, Q, 5)), 25)
	eq(ns.Blackjack_ValueText(cards(A, 6)), "soft 17")
	eq(ns.Blackjack_ValueText(cards(K, Q, 5)), "Bust")
end)

test("deal takes the bet and plays your hand", function()
	local g = game(100, 10, 9, 7, 8)
	eq(ns.Blackjack_Deal(g, noRandom), true)
	eq(g.chips, 900)
	eq(ns.Blackjack_InPlay(g), true)
	eq(ns.Blackjack_Value(g.round.hands[1].cards), 17)
	local can = ns.Blackjack_Actions(g)
	eq(can.hit and can.stand and can.double, true)
	eq(can.split, false)
end)

test("no deal without a bet or chips", function()
	local g = game(0, 10, 9, 7, 8)
	eq(select(2, ns.Blackjack_Deal(g, noRandom)), "bet")
	g.bet, g.chips = 100, 50
	eq(select(2, ns.Blackjack_Deal(g, noRandom)), "chips")
end)

test("stand: dealer draws to 17 and you win", function()
	-- You 10+8 = 18; dealer 9+5, draws 3 = 17, stands.
	local g = game(100, 10, 9, 8, 5, 3)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Stand(g, noRandom)
	eq(g.round.phase, "done")
	eq(#g.round.dealer, 3)
	eq(g.round.hands[1].result, "win")
	eq(g.chips, 1100)
	eq(g.round.net, 100)
	eq(ns.Blackjack_RoundText(g.round, thousands), "Dealer has 17. You win 100.")
end)

test("dealer stands on soft 17", function()
	local g = game(100, 10, A, 7, 6)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Stand(g, noRandom)
	eq(#g.round.dealer, 2)
	eq(g.round.hands[1].result, "push")
	eq(g.chips, 1000)
end)

test("bust: the dealer doesn't draw, you lose the bet", function()
	local g = game(100, 10, 9, 6, 5, K)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Hit(g, noRandom)
	eq(g.round.phase, "done")
	eq(#g.round.dealer, 2)
	eq(g.round.hands[1].result, "bust")
	eq(g.chips, 900)
	eq(ns.Blackjack_RoundText(g.round, thousands), "Bust. You lose 100.")
end)

test("hitting to 21 stands on its own", function()
	local g = game(100, 5, 10, 6, 7, K)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Hit(g, noRandom)
	eq(g.round.phase, "done")
	eq(g.round.hands[1].result, "win")
end)

test("blackjack pays 3:2 at once", function()
	local g = game(100, A, 9, K, 7)
	ns.Blackjack_Deal(g, noRandom)
	eq(g.round.phase, "done")
	eq(g.round.hands[1].result, "blackjack")
	eq(g.chips, 1150)
	eq(g.stats.blackjacks, 1)
	eq(ns.Blackjack_RoundText(g.round, thousands), "Blackjack! You win 150.")
end)

test("dealer peeks: a dealer blackjack ends the round", function()
	local g = game(100, 10, A, 9, K)
	ns.Blackjack_Deal(g, noRandom)
	eq(g.round.phase, "done")
	eq(g.round.hands[1].result, "lose")
	eq(g.chips, 900)
	eq(ns.Blackjack_RoundText(g.round, thousands), "Dealer has blackjack. You lose 100.")
end)

test("both blackjack is a push", function()
	local g = game(100, A, K, Q, A)
	ns.Blackjack_Deal(g, noRandom)
	eq(g.round.hands[1].result, "push")
	eq(g.chips, 1000)
end)

test("double: twice the bet, one card", function()
	-- You 6+5, double, draw 10 = 21; dealer 10+7.
	local g = game(100, 6, 10, 5, 7, 10)
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_Double(g, noRandom), true)
	local hand = g.round.hands[1]
	eq(#hand.cards, 3)
	eq(hand.bet, 200)
	eq(hand.result, "win")
	eq(g.chips, 1200)
end)

test("no double without the chips for it", function()
	local g = game(600, 6, 10, 5, 7)
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_Actions(g).double, false)
	eq(ns.Blackjack_Double(g, noRandom), false)
end)

test("split: two hands, played in turn", function()
	-- You 8+8 vs dealer 10+6. Split: hand 1 gets 3 (11), hand 2 gets 10 (18). Hand 1 hits 9 (20) and stands,
	-- hand 2 stands; dealer draws 5 = 21.
	local g = game(100, 8, 10, 8, 6, 3, 10, 9, 5)
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_Actions(g).split, true)
	eq(ns.Blackjack_Split(g, noRandom), true)
	eq(#g.round.hands, 2)
	eq(g.chips, 800)
	eq(g.round.active, 1)
	eq(ns.Blackjack_Actions(g).split, false, "only one split")
	ns.Blackjack_Hit(g, noRandom)
	ns.Blackjack_Stand(g, noRandom)
	eq(g.round.active, 2)
	ns.Blackjack_Stand(g, noRandom)
	eq(g.round.phase, "done")
	eq(g.round.hands[1].result, "lose")
	eq(g.round.hands[2].result, "lose")
	eq(g.chips, 800)
	eq(g.stats.hands, 2)
end)

test("ten-value cards split, and 21 after a split isn't blackjack", function()
	-- You K+Q vs dealer 9+8. Hand 1 gets A (21, done), hand 2 gets 9 (19), stands. Dealer 17.
	local g = game(100, K, 9, Q, 8, A, 9)
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_Split(g, noRandom), true)
	eq(g.round.active, 2)
	ns.Blackjack_Stand(g, noRandom)
	eq(g.round.hands[1].result, "win")
	eq(g.round.hands[2].result, "win")
	eq(g.chips, 1200)
end)

test("split aces get one card each", function()
	local g = game(100, A, 10, A, 7, 5, 9)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Split(g, noRandom)
	eq(g.round.phase, "done")
	eq(#g.round.hands[1].cards, 2)
	eq(#g.round.hands[2].cards, 2)
	eq(g.round.hands[1].result, "lose") -- 16 vs 17
	eq(g.round.hands[2].result, "win") -- 20 vs 17
end)

test("double after a split", function()
	local g = game(100, 8, 10, 8, 7, 3, 2, 10)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Split(g, noRandom)
	eq(ns.Blackjack_Double(g, noRandom), true)
	eq(g.round.hands[1].bet, 200)
	eq(g.round.active, 2)
end)

test("the bet stays up for the next round, as far as the chips go", function()
	local g = game(500, 10, 9, 8, K)
	g.chips = 700
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Stand(g, noRandom) -- 18 vs 19: lose
	eq(g.chips, 200)
	eq(g.bet, 200)
end)

test("bets are whole tens up to your chips, and fixed while playing", function()
	local g = game(0, 10, 9, 8, K)
	g.chips = 125
	ns.Blackjack_AddBet(g, 100)
	ns.Blackjack_AddBet(g, 50)
	eq(g.bet, 120)
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_AddBet(g, 10), false)
	ns.Blackjack_ClearBet(g)
	eq(g.bet, 120)
end)

test("streaks, biggest win and peak", function()
	local g = game(100, 10, 9, 10, 8, 10, 9, 10, 8, 10, 9, 8, 10)
	for _ = 1, 2 do
		ns.Blackjack_Deal(g, noRandom)
		ns.Blackjack_Stand(g, noRandom)
	end
	eq(g.stats.streak, 2)
	eq(g.stats.bestStreak, 2)
	eq(g.stats.peak, 1200)
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Stand(g, noRandom) -- 18 vs 20
	eq(g.stats.streak, 0)
	eq(g.stats.bestStreak, 2)
	eq(g.stats.biggestWin, 100)
	eq(g.stats.wins, 2)
	eq(g.stats.losses, 1)
end)

test("house chips only when broke", function()
	local g = ns.Blackjack_NewGame()
	eq(ns.Blackjack_Refill(g, 500), false)
	g.chips = 5
	eq(ns.Blackjack_Refill(g, 500), 495)
	eq(g.chips, 500)
	eq(g.stats.refills, 1)
end)

test("earned chips count toward stats and the peak", function()
	local g = ns.Blackjack_NewGame()
	ns.Blackjack_AddChips(g, 250)
	eq(g.chips, 1250)
	eq(g.stats.earned, 250)
	eq(g.stats.peak, 1250)
end)

test("spending needs the chips and no hand in play, and trims the bet", function()
	local g = game(500)
	eq(ns.Blackjack_Spend(g, 2000), false)
	eq(ns.Blackjack_Spend(g, 600), true)
	eq(g.chips, 400)
	eq(g.bet, 400)
	g.bet = 100
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_Spend(g, 10), false)
end)

test("an old saved game gets the earned stat", function()
	local g = ns.Blackjack_NewGame()
	g.stats.earned = nil
	ns.Blackjack_Repair(g)
	eq(g.stats.earned, 0)
end)

test("reshuffles when a quarter of the shoe is left", function()
	local g = game(100)
	g.next = 312 - 70
	local calls = 0
	ns.Blackjack_Deal(g, function(n)
		calls = calls + 1
		return n
	end)
	eq(g.round.shuffled, true)
	eq(calls, 311)
	eq(g.next, 5)
end)

test("stack pair puts a pair in your next hand", function()
	local g = game(100, 7, 9, 3, 4, 5, 6, 7)
	eq(ns.Blackjack_StackPair(g), true)
	ns.Blackjack_Deal(g, noRandom)
	eq(ns.Blackjack_Actions(g).split, true)
end)

test("repair fills in a damaged save", function()
	local g = ns.Blackjack_Repair({ chips = "x", round = 5, stats = { hands = 3 } })
	eq(g.chips, 1000)
	eq(g.round, nil)
	eq(g.stats.hands, 3)
	eq(g.stats.peak, 1000)
	eq(g.next, 1)
end)

test("net chips: all time in the stats, per game for the play session", function()
	local g = game(100, 10, 9, 13, 7) -- you 10+K = 20, dealer 9+7 = 16, stand: dealer draws a two to 18
	ns.Blackjack_SessionCheck(g, "s1")
	ns.Blackjack_Deal(g, noRandom)
	ns.Blackjack_Stand(g, noRandom)
	eq(g.round.net, 100)
	eq(g.stats.net, 100)
	eq(g.session.blackjack, 100)
	ns.Blackjack_RecordNet(g, "slots", -10)
	eq(g.session.slots, -10)
	ns.Blackjack_SessionCheck(g, "s1")
	eq(g.session.blackjack, 100, "the same session keeps its counts")
	ns.Blackjack_SessionCheck(g, "s2")
	eq(g.session.blackjack, 0, "a new session starts over")
	eq(g.stats.net, 100)
end)

H.done()
