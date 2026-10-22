local addonName, ns = ...

-- Video poker: pure logic (no WoW API calls; unit-tested in tests/test_pokerrules.lua). Jacks or Better on the
-- full-pay 9/6 table: five cards from a fresh deck, hold any, draw once, paid by the hand made. The game is
-- game.poker in the casino's saved game (BlackjackRules.lua holds the chips and the shared stats). Cards from
-- CardData.lua; drawn in PokerMachine.lua.

local MAX_COINS = 5
local ROYAL_MAX = 800 -- a royal flush pays this per coin at five coins (250 below): the machine's max-bet bonus
local HAND_SIZE = 5
local DECK = 52

ns.POKER_MAX_COINS = MAX_COINS
ns.POKER_COIN_VALUES = { 10, 50, 100, 500 } -- the chip buttons; a bet is one coin value times 1 to 5 coins

-- Best first. pay: coins paid per coin bet (1 is the bet back). have: the hand in "You have ...".
ns.POKER_HANDS = {
	{ key = "royal", name = "Royal flush", pay = 250, have = "a royal flush" },
	{ key = "straightFlush", name = "Straight flush", pay = 50, have = "a straight flush" },
	{ key = "quads", name = "Four of a kind", pay = 25, have = "four of a kind" },
	{ key = "fullHouse", name = "Full house", pay = 9, have = "a full house" },
	{ key = "flush", name = "Flush", pay = 6, have = "a flush" },
	{ key = "straight", name = "Straight", pay = 4, have = "a straight" },
	{ key = "trips", name = "Three of a kind", pay = 3, have = "three of a kind" },
	{ key = "twoPair", name = "Two pair", pay = 2, have = "two pair" },
	{ key = "jacks", name = "Jacks or better", pay = 1, have = "jacks or better" },
}

local HANDS = {}
for _, hand in ipairs(ns.POKER_HANDS) do
	HANDS[hand.key] = hand
end

local Rank, Suit = ns.Cards_Rank, ns.Cards_Suit

-- Hands --------------------------------------------------------------------------------------------------------

-- Five ranks, all different, in a run; the ace plays high (10-J-Q-K-A) or low (A-2-3-4-5).
local function IsStraight(ranks)
	local seen, low, high = {}, 14, 0
	for _, r in ipairs(ranks) do
		if seen[r] then
			return false
		end
		seen[r] = true
		low, high = math.min(low, r), math.max(high, r)
	end
	return high - low == 4 or (seen[1] and seen[10] and seen[11] and seen[12] and seen[13]) or false
end

-- The paying hand five cards make (a key of ns.POKER_HANDS), or nil.
function ns.Poker_Evaluate(cards)
	local ranks, counts, suits = {}, {}, {}
	for i, card in ipairs(cards) do
		local r = Rank(card)
		ranks[i] = r
		counts[r] = (counts[r] or 0) + 1
		suits[Suit(card)] = true
	end
	local suitCount = 0
	for _ in pairs(suits) do
		suitCount = suitCount + 1
	end
	local flush, straight = suitCount == 1, IsStraight(ranks)
	if flush and straight then
		local broadway = counts[1] and counts[13]
		return broadway and "royal" or "straightFlush"
	end
	-- Group sizes, biggest first: { 4, 1 }, { 3, 2 }, { 2, 2, 1 } ...
	local groups, pairRank = {}, nil
	for r, n in pairs(counts) do
		groups[#groups + 1] = n
		if n == 2 then
			pairRank = r
		end
	end
	table.sort(groups, function(a, b)
		return a > b
	end)
	if groups[1] == 4 then
		return "quads"
	elseif groups[1] == 3 and groups[2] == 2 then
		return "fullHouse"
	elseif flush then
		return "flush"
	elseif straight then
		return "straight"
	elseif groups[1] == 3 then
		return "trips"
	elseif groups[1] == 2 and groups[2] == 2 then
		return "twoPair"
	elseif groups[1] == 2 and (pairRank == 1 or pairRank >= 11) then
		return "jacks"
	end
	return nil
end

-- Coins a hand pays for `coins` coins bet (the royal's bonus at five).
function ns.Poker_Pay(key, coins)
	local hand = HANDS[key]
	if not hand then
		return 0
	end
	if key == "royal" and coins == MAX_COINS then
		return ROYAL_MAX * coins
	end
	return hand.pay * coins
end

function ns.Poker_Hand(key)
	return HANDS[key]
end

-- The game -----------------------------------------------------------------------------------------------------

local function Stats()
	local stats = { hands = 0, wins = 0, biggestWin = 0 }
	for _, hand in ipairs(ns.POKER_HANDS) do
		stats[hand.key] = 0
	end
	return stats
end

local function ValidCoin(value)
	for _, v in ipairs(ns.POKER_COIN_VALUES) do
		if v == value then
			return true
		end
	end
	return false
end

local function ValidRound(round)
	return type(round) == "table" and (round.phase == "hold" or round.phase == "done")
		and type(round.cards) == "table" and #round.cards == HAND_SIZE and type(round.held) == "table"
		and type(round.deck) == "table" and #round.deck == DECK and type(round.next) == "number"
		and type(round.coin) == "number" and type(round.coins) == "number" and type(round.bet) == "number"
end

-- game.poker, made or filled in where an older or damaged save lacks it. Returns it.
function ns.Poker_Repair(game)
	local poker = type(game.poker) == "table" and game.poker or {}
	game.poker = poker
	if not ValidCoin(poker.coin) then
		poker.coin = ns.POKER_COIN_VALUES[1]
	end
	if type(poker.coins) ~= "number" or poker.coins < 1 or poker.coins > MAX_COINS then
		poker.coins = MAX_COINS
	end
	poker.stats = type(poker.stats) == "table" and poker.stats or Stats()
	for k, v in pairs(Stats()) do
		if type(poker.stats[k]) ~= "number" then
			poker.stats[k] = v
		end
	end
	if poker.round ~= nil and not ValidRound(poker.round) then
		poker.round = nil
	end
	return poker
end

-- Cards are dealt and waiting to be held and drawn (the bet is already off the chips).
function ns.Poker_InPlay(game)
	local round = game.poker.round
	return round ~= nil and round.phase == "hold"
end

-- The bet in chips: coin value times coins.
function ns.Poker_Bet(game)
	return game.poker.coin * game.poker.coins
end

-- Between hands only. Returns true when it changed.
function ns.Poker_SetCoin(game, value)
	if ns.Poker_InPlay(game) or not ValidCoin(value) then
		return false
	end
	game.poker.coin = value
	return true
end

-- One coin more, back to one after five. Between hands only.
function ns.Poker_BetOne(game)
	if ns.Poker_InPlay(game) then
		return false
	end
	game.poker.coins = game.poker.coins % MAX_COINS + 1
	return true
end

function ns.Poker_SetCoins(game, coins)
	if ns.Poker_InPlay(game) or coins < 1 or coins > MAX_COINS then
		return false
	end
	game.poker.coins = coins
	return true
end

-- Deals five from a freshly shuffled deck at the current bet. random(n) -> 1..n. Returns true, or false and why
-- ("playing" or "chips").
function ns.Poker_Deal(game, random)
	local poker = game.poker
	if ns.Poker_InPlay(game) then
		return false, "playing"
	end
	local bet = ns.Poker_Bet(game)
	if game.chips < bet then
		return false, "chips"
	end
	game.chips = game.chips - bet
	local deck = {}
	for card = 1, DECK do
		deck[card] = card
	end
	ns.Cards_Shuffle(deck, random)
	local round = { phase = "hold", cards = {}, held = {}, deck = deck, next = HAND_SIZE + 1, coin = poker.coin,
		coins = poker.coins, bet = bet }
	for i = 1, HAND_SIZE do
		round.cards[i] = deck[i]
		round.held[i] = false
	end
	poker.round = round
	return true
end

-- Holds card i or lets it go. Returns whether it's held now (nil between hands).
function ns.Poker_Hold(game, i)
	if not ns.Poker_InPlay(game) or i < 1 or i > HAND_SIZE then
		return nil
	end
	local held = game.poker.round.held
	held[i] = not held[i]
	return held[i]
end

-- Replaces the cards not held from the same deck and pays the hand.
function ns.Poker_Draw(game)
	if not ns.Poker_InPlay(game) then
		return false
	end
	local poker = game.poker
	local round = poker.round
	for i = 1, HAND_SIZE do
		if not round.held[i] then
			round.cards[i] = round.deck[round.next]
			round.next = round.next + 1
		end
	end
	local key = ns.Poker_Evaluate(round.cards)
	local payout = ns.Poker_Pay(key, round.coins) * round.coin
	round.result, round.payout, round.net = key, payout, payout - round.bet
	round.phase = "done"
	game.chips = game.chips + payout
	local stats = poker.stats
	stats.hands = stats.hands + 1
	if key then
		stats[key] = stats[key] + 1
	end
	if round.net > 0 then
		stats.wins = stats.wins + 1
		stats.biggestWin = math.max(stats.biggestWin, round.net)
	end
	game.stats.peak = math.max(game.stats.peak, game.chips)
	return true
end

-- Text ---------------------------------------------------------------------------------------------------------

-- While holding: "You have two pair." for the paying hand already in the cards, else nil.
function ns.Poker_HoldText(cards)
	local key = ns.Poker_Evaluate(cards)
	return key and ("You have %s."):format(HANDS[key].have) or nil
end

-- The line once a hand is drawn. thousands(n): the number formatter (ns.Thousands in the game).
function ns.Poker_RoundText(round, thousands)
	if not round.result then
		return "No win. Deal again?"
	end
	local name = HANDS[round.result].name
	if round.net == 0 then
		return name .. ": your bet back."
	end
	return ("%s! You win %s."):format(name, thousands(round.payout))
end
