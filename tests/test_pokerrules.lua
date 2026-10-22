-- Run from the AddOns folder: lua Tomte/tests/test_pokerrules.lua
local ns = {}
assert(loadfile("Tomte/Modules/Games/CardData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/BlackjackRules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/PokerRules.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local A, J, Q, K = 1, 11, 12, 13
local S, HE, D, C = 1, 2, 3, 4 -- suit indexes: spades, hearts, diamonds, clubs

-- Cards from { rank, suit } pairs.
local function hand(...)
	local out = {}
	for i, rs in ipairs({ ... }) do
		out[i] = ns.Cards_Make(rs[1], rs[2])
	end
	return out
end

local function thousands(n)
	return tostring(n)
end

-- No shuffle: the deck stays 1..52 in order (spades A-K, hearts A-K ...), so the deal is A-5 of spades.
local function noShuffle(n)
	return n
end

local function newGame()
	local game = ns.Blackjack_NewGame()
	ns.Poker_Repair(game)
	return game
end

test("every hand is recognized", function()
	eq(ns.Poker_Evaluate(hand({ 10, S }, { J, S }, { Q, S }, { K, S }, { A, S })), "royal")
	eq(ns.Poker_Evaluate(hand({ 9, HE }, { 10, HE }, { J, HE }, { Q, HE }, { K, HE })), "straightFlush")
	eq(ns.Poker_Evaluate(hand({ A, D }, { 2, D }, { 3, D }, { 4, D }, { 5, D })), "straightFlush", "wheel flush")
	eq(ns.Poker_Evaluate(hand({ 7, S }, { 7, HE }, { 7, D }, { 7, C }, { 2, S })), "quads")
	eq(ns.Poker_Evaluate(hand({ 3, S }, { 3, HE }, { 3, D }, { 9, C }, { 9, S })), "fullHouse")
	eq(ns.Poker_Evaluate(hand({ 2, C }, { 6, C }, { 9, C }, { J, C }, { K, C })), "flush")
	eq(ns.Poker_Evaluate(hand({ 10, S }, { J, HE }, { Q, D }, { K, C }, { A, S })), "straight", "ace high")
	eq(ns.Poker_Evaluate(hand({ A, S }, { 2, HE }, { 3, D }, { 4, C }, { 5, S })), "straight", "ace low")
	eq(ns.Poker_Evaluate(hand({ 5, S }, { 5, HE }, { 5, D }, { J, C }, { 2, S })), "trips")
	eq(ns.Poker_Evaluate(hand({ 4, S }, { 4, HE }, { 8, D }, { 8, C }, { K, S })), "twoPair")
	eq(ns.Poker_Evaluate(hand({ J, S }, { J, HE }, { 3, D }, { 5, C }, { 9, S })), "jacks")
	eq(ns.Poker_Evaluate(hand({ A, S }, { A, HE }, { 3, D }, { 5, C }, { 9, S })), "jacks", "aces")
end)

test("losing hands pay nothing", function()
	eq(ns.Poker_Evaluate(hand({ 10, S }, { 10, HE }, { 3, D }, { 5, C }, { 9, S })), nil, "pair of tens")
	eq(ns.Poker_Evaluate(hand({ J, S }, { Q, S }, { K, S }, { A, S }, { 2, HE })), nil, "no wrap-around straight")
	eq(ns.Poker_Evaluate(hand({ 2, S }, { 4, HE }, { 6, D }, { 8, C }, { 10, S })), nil)
end)

test("the pay table, with the royal's bonus at five coins", function()
	eq(ns.Poker_Pay("royal", 1), 250)
	eq(ns.Poker_Pay("royal", 4), 1000)
	eq(ns.Poker_Pay("royal", 5), 4000)
	eq(ns.Poker_Pay("fullHouse", 5), 45)
	eq(ns.Poker_Pay("flush", 1), 6)
	eq(ns.Poker_Pay("jacks", 3), 3)
	eq(ns.Poker_Pay(nil, 5), 0)
end)

test("deal takes the bet, hold and draw pay the hand", function()
	local game = newGame()
	game.poker.coin, game.poker.coins = 10, 5
	eq(ns.Poker_Deal(game, noShuffle), true)
	eq(game.chips, 950)
	eq(ns.Poker_InPlay(game), true)
	local round = game.poker.round
	eq(#round.cards, 5)
	eq(ns.Poker_HoldText(round.cards), "You have a straight flush.")
	-- Hold the ace to four, draw for the five: the sixth card of the unshuffled deck is the six of spades.
	for i = 1, 4 do
		eq(ns.Poker_Hold(game, i), true)
	end
	eq(ns.Poker_Draw(game), true)
	eq(ns.Cards_Rank(round.cards[5]), 6)
	eq(round.result, "flush")
	eq(round.payout, 300) -- 6 per coin, 5 coins of 10
	eq(round.net, 250)
	eq(game.chips, 1250)
	eq(ns.Poker_InPlay(game), false)
	eq(game.poker.stats.hands, 1)
	eq(game.poker.stats.flush, 1)
	eq(game.poker.stats.wins, 1)
	eq(game.poker.stats.biggestWin, 250)
	eq(game.poker.stats.net, 250)
	eq(game.stats.peak, 1250)
end)

test("held cards stay, the rest come from the deck in order", function()
	local game = newGame()
	ns.Poker_Deal(game, noShuffle)
	eq(ns.Poker_Hold(game, 2), true)
	eq(ns.Poker_Hold(game, 2), false, "a second click lets it go")
	ns.Poker_Hold(game, 2)
	ns.Poker_Draw(game)
	local cards = game.poker.round.cards
	eq(cards[1], 6)
	eq(cards[2], 2)
	eq(cards[3], 7)
	eq(cards[4], 8)
	eq(cards[5], 9)
end)

test("jacks or better gives the bet back and isn't a win", function()
	local game = newGame()
	game.poker.coin, game.poker.coins = 50, 2
	ns.Poker_Deal(game, noShuffle)
	local round = game.poker.round
	round.cards = hand({ J, S }, { J, HE }, { 3, D }, { 5, C }, { 9, S })
	for i = 1, 5 do
		ns.Poker_Hold(game, i)
	end
	ns.Poker_Draw(game)
	eq(round.result, "jacks")
	eq(round.payout, 100)
	eq(round.net, 0)
	eq(game.chips, 1000)
	eq(game.poker.stats.wins, 0)
	eq(game.poker.stats.jacks, 1)
	eq(ns.Poker_RoundText(round, thousands), "Jacks or better: your bet back.")
end)

test("a losing hand", function()
	local game = newGame()
	ns.Poker_Deal(game, noShuffle)
	local round = game.poker.round
	round.cards = hand({ 2, S }, { 4, HE }, { 6, D }, { 8, C }, { 10, S })
	for i = 1, 5 do
		ns.Poker_Hold(game, i)
	end
	ns.Poker_Draw(game)
	eq(round.result, nil)
	eq(round.payout, 0)
	eq(game.chips, 950)
	eq(ns.Poker_RoundText(round, thousands), "No win. Deal again?")
end)

test("the bet can't change during a hand, and needs the chips", function()
	local game = newGame()
	eq(ns.Poker_SetCoin(game, 50), true)
	eq(ns.Poker_SetCoin(game, 7), false, "not a coin value")
	eq(ns.Poker_SetCoins(game, 1), true)
	eq(ns.Poker_BetOne(game), true)
	eq(game.poker.coins, 2)
	ns.Poker_SetCoins(game, 5)
	ns.Poker_BetOne(game)
	eq(game.poker.coins, 1, "after five comes one")
	eq(ns.Poker_Bet(game), 50)
	ns.Poker_Deal(game, noShuffle)
	eq(ns.Poker_SetCoin(game, 100), false)
	eq(ns.Poker_BetOne(game), false)
	eq(select(2, ns.Poker_Deal(game, noShuffle)), "playing")
	ns.Poker_Draw(game)
	game.chips = 40
	eq(select(2, ns.Poker_Deal(game, noShuffle)), "chips")
	eq(game.chips, 40)
end)

test("round text names the hand and the win", function()
	eq(ns.Poker_RoundText({ result = "fullHouse", payout = 450, net = 400 }, thousands), "Full house! You win 450.")
	eq(ns.Poker_HoldText(hand({ 2, S }, { 4, HE }, { 6, D }, { 8, C }, { 10, S })), nil)
	eq(ns.Poker_HoldText(hand({ 4, S }, { 4, HE }, { 8, D }, { 8, C }, { K, S })), "You have two pair.")
end)

test("repair fills in a missing or damaged game", function()
	local game = ns.Blackjack_NewGame()
	local poker = ns.Poker_Repair(game)
	eq(game.poker, poker)
	eq(poker.coin, 10)
	eq(poker.coins, 5)
	eq(poker.stats.royal, 0)
	poker.coin, poker.coins, poker.stats.quads = 33, 9, nil
	poker.round = { phase = "hold", cards = { 1, 2 } }
	ns.Poker_Repair(game)
	eq(poker.coin, 10)
	eq(poker.coins, 5)
	eq(poker.stats.quads, 0)
	eq(poker.round, nil)
	ns.Poker_Deal(game, noShuffle)
	local round = poker.round
	ns.Poker_Repair(game)
	eq(poker.round, round, "a hand in play survives")
end)

H.done()
