local addonName, ns = ...

-- Blackjack: pure logic (no WoW API calls; unit-tested in tests/test_blackjackrules.lua). The game is one plain
-- table (saved as TomteDB.casino.game): chips, the bet on the table, the shoe, the round in play and the stats.
-- Rules: 6 decks, dealer stands on soft 17 and peeks with an ace or ten showing, blackjack pays 3:2, double on any
-- first two cards (also after a split), one split, split aces get one card each. Cards come from CardData.lua.
-- Drawn in Table.lua, registered in Casino.lua.

local START_CHIPS = 1000
local MIN_BET = 10
local DECKS = 6
local RESHUFFLE_AT = 0.25 -- share of the shoe left when it's reshuffled before the next deal
local DEALER_STANDS = 17

ns.BLACKJACK_START_CHIPS = START_CHIPS
ns.BLACKJACK_MIN_BET = MIN_BET
-- The chip buttons. Bets are whole tens, so a 3:2 blackjack payout is always whole.
ns.BLACKJACK_CHIPS = { 10, 50, 100, 500 }

local Rank = ns.Cards_Rank

local function CardValue(card)
	local rank = Rank(card)
	if rank == 1 then
		return 1
	end
	return math.min(rank, 10)
end

-- Total of a list of cards, and whether it's soft (an ace counted as 11).
function ns.Blackjack_Value(cards)
	local total, aces = 0, 0
	for _, card in ipairs(cards) do
		local v = CardValue(card)
		total = total + v
		if v == 1 then
			aces = aces + 1
		end
	end
	if aces > 0 and total + 10 <= 21 then
		return total + 10, true
	end
	return total, false
end

-- Two cards making 21, not on a split hand.
local function Natural(hand)
	return #hand.cards == 2 and not hand.split and ns.Blackjack_Value(hand.cards) == 21
end
ns.Blackjack_IsNatural = Natural

local function Stats()
	return { hands = 0, wins = 0, losses = 0, pushes = 0, blackjacks = 0, biggestWin = 0, streak = 0,
		bestStreak = 0, peak = START_CHIPS, refills = 0, earned = 0 }
end

function ns.Blackjack_NewGame()
	return { chips = START_CHIPS, bet = 0, shoe = {}, next = 1, stats = Stats() }
end

-- Fills in what an older or damaged saved game lacks.
function ns.Blackjack_Repair(game)
	if type(game.chips) ~= "number" then
		game.chips = START_CHIPS
	end
	game.bet = type(game.bet) == "number" and game.bet or 0
	game.shoe = type(game.shoe) == "table" and game.shoe or {}
	game.next = type(game.next) == "number" and game.next or 1
	game.stats = type(game.stats) == "table" and game.stats or Stats()
	for k, v in pairs(Stats()) do
		if type(game.stats[k]) ~= "number" then
			game.stats[k] = v
		end
	end
	if game.round ~= nil and type(game.round) ~= "table" then
		game.round = nil
	end
	return game
end

local function NewShoe(game, random)
	game.shoe = ns.Cards_NewShoe(DECKS, random)
	game.next = 1
end

local function Draw(game, random)
	if game.next > #game.shoe then
		NewShoe(game, random)
	end
	local card = game.shoe[game.next]
	game.next = game.next + 1
	return card
end

-- Cards left in the shoe.
function ns.Blackjack_Left(game)
	return math.max(#game.shoe - game.next + 1, 0)
end

-- A hand is being played (the buttons are Hit, Stand ...).
function ns.Blackjack_InPlay(game)
	return game.round ~= nil and game.round.phase == "player"
end

function ns.Casino_ActiveHand(game)
	local round = game.round
	return round and round.phase == "player" and round.hands[round.active] or nil
end

-- Betting ------------------------------------------------------------------------------------------------------

-- Bets are whole tens, at most what you have.
local function MaxBet(game)
	return math.floor(game.chips / MIN_BET) * MIN_BET
end

-- Adds a chip to the bet. False while a hand is in play.
function ns.Blackjack_AddBet(game, amount)
	if ns.Blackjack_InPlay(game) then
		return false
	end
	game.bet = math.min(game.bet + amount, MaxBet(game))
	return true
end

function ns.Blackjack_ClearBet(game)
	if not ns.Blackjack_InPlay(game) then
		game.bet = 0
	end
end

-- Out of chips: the house tops you up to `to`. Returns the chips given, or false while you can still bet.
-- How often it may happen is ChipRules.lua's call.
function ns.Blackjack_Refill(game, to)
	if game.chips >= MIN_BET or ns.Blackjack_InPlay(game) then
		return false
	end
	local given = to - game.chips
	game.chips = to
	game.stats.refills = game.stats.refills + 1
	game.stats.peak = math.max(game.stats.peak, game.chips)
	return given
end

-- Chips from outside the table (earned by playing the game).
function ns.Blackjack_AddChips(game, amount)
	game.chips = game.chips + amount
	game.stats.earned = game.stats.earned + amount
	game.stats.peak = math.max(game.stats.peak, game.chips)
end

-- Chips spent at the Cashier. False when you don't have them or a hand is in play (its bet isn't in your chips).
function ns.Blackjack_Spend(game, amount)
	if ns.Blackjack_InPlay(game) or game.chips < amount then
		return false
	end
	game.chips = game.chips - amount
	game.bet = math.min(game.bet, MaxBet(game))
	return true
end

-- The round -----------------------------------------------------------------------------------------------------

local function Settle(game)
	local round = game.round
	local dealerTotal = ns.Blackjack_Value(round.dealer)
	local dealerNatural = Natural({ cards = round.dealer })
	local stats = game.stats
	local staked, paid = 0, 0
	for _, hand in ipairs(round.hands) do
		local total = ns.Blackjack_Value(hand.cards)
		local natural = Natural(hand)
		local result, payout
		if total > 21 then
			result, payout = "bust", 0
		elseif natural and not dealerNatural then
			result, payout = "blackjack", math.floor(hand.bet * 5 / 2) -- whole already: floor keeps it an integer
		elseif dealerNatural then
			result, payout = natural and "push" or "lose", natural and hand.bet or 0
		elseif dealerTotal > 21 or total > dealerTotal then
			result, payout = "win", hand.bet * 2
		elseif total == dealerTotal then
			result, payout = "push", hand.bet
		else
			result, payout = "lose", 0
		end
		hand.result, hand.payout = result, payout
		staked, paid = staked + hand.bet, paid + payout
		stats.hands = stats.hands + 1
		if result == "blackjack" or result == "win" then
			stats.wins = stats.wins + 1
		elseif result == "push" then
			stats.pushes = stats.pushes + 1
		else
			stats.losses = stats.losses + 1
		end
		if result == "blackjack" then
			stats.blackjacks = stats.blackjacks + 1
		end
	end
	game.chips = game.chips + paid
	round.net = paid - staked
	round.phase = "done"
	round.dealerNatural = dealerNatural
	if round.net > 0 then
		stats.streak = stats.streak + 1
		stats.bestStreak = math.max(stats.bestStreak, stats.streak)
		stats.biggestWin = math.max(stats.biggestWin, round.net)
	elseif round.net < 0 then
		stats.streak = 0
	end
	stats.peak = math.max(stats.peak, game.chips)
	-- The same bet stays up for the next deal, as far as the chips go.
	game.bet = math.min(game.bet, MaxBet(game))
end

-- The dealer draws to 17 (standing on soft 17), unless every hand is already decided: all bust, or a blackjack.
local function DealerPlay(game, random)
	local round = game.round
	local live = false
	for _, hand in ipairs(round.hands) do
		if ns.Blackjack_Value(hand.cards) <= 21 and not Natural(hand) then
			live = true
		end
	end
	if live then
		while ns.Blackjack_Value(round.dealer) < DEALER_STANDS do
			round.dealer[#round.dealer + 1] = Draw(game, random)
		end
	end
	Settle(game)
end

-- On to the next hand that isn't done; with none left, the dealer plays and the round is settled.
local function Advance(game, random)
	local round = game.round
	for i, hand in ipairs(round.hands) do
		if not hand.done then
			round.active = i
			return
		end
	end
	round.active = nil
	DealerPlay(game, random)
end

-- A hand at 21 or over plays no further.
local function AddCard(game, hand, random)
	hand.cards[#hand.cards + 1] = Draw(game, random)
	if ns.Blackjack_Value(hand.cards) >= 21 then
		hand.done = true
	end
end

-- Deals a round at the bet on the table. random(n) -> 1..n (math.random). Returns true, or false and why.
function ns.Blackjack_Deal(game, random)
	if ns.Blackjack_InPlay(game) then
		return false, "playing"
	end
	if game.bet < MIN_BET then
		return false, "bet"
	end
	if game.bet > game.chips then
		return false, "chips"
	end
	local shuffled = false
	if ns.Blackjack_Left(game) < DECKS * 52 * RESHUFFLE_AT then
		NewShoe(game, random)
		shuffled = true
	end
	game.chips = game.chips - game.bet
	local hand = { cards = {}, bet = game.bet }
	local round = { phase = "player", hands = { hand }, active = 1, dealer = {}, shuffled = shuffled }
	game.round = round
	hand.cards[1] = Draw(game, random)
	round.dealer[1] = Draw(game, random)
	hand.cards[2] = Draw(game, random)
	round.dealer[2] = Draw(game, random)
	local up = CardValue(round.dealer[1])
	-- The dealer peeks under an ace or a ten: a dealer blackjack ends the round before you act.
	if ((up == 1 or up == 10) and Natural({ cards = round.dealer })) or Natural(hand) then
		hand.done = true
		round.active = nil
		Settle(game)
	end
	return true
end

-- What the active hand may do: { hit, stand, double, split } as booleans (all false between rounds).
function ns.Blackjack_Actions(game)
	local hand = ns.Casino_ActiveHand(game)
	if not hand then
		return { hit = false, stand = false, double = false, split = false }
	end
	local two = #hand.cards == 2
	local affords = game.chips >= hand.bet
	return {
		hit = true,
		stand = true,
		double = two and affords,
		split = two and affords and #game.round.hands == 1 and CardValue(hand.cards[1]) == CardValue(hand.cards[2]),
	}
end

function ns.Blackjack_Hit(game, random)
	local hand = ns.Casino_ActiveHand(game)
	if not hand then
		return false
	end
	AddCard(game, hand, random)
	if hand.done then
		Advance(game, random)
	end
	return true
end

function ns.Blackjack_Stand(game, random)
	local hand = ns.Casino_ActiveHand(game)
	if not hand then
		return false
	end
	hand.done = true
	Advance(game, random)
	return true
end

-- Doubles the bet for exactly one more card.
function ns.Blackjack_Double(game, random)
	if not ns.Blackjack_Actions(game).double then
		return false
	end
	local hand = ns.Casino_ActiveHand(game)
	game.chips = game.chips - hand.bet
	hand.bet = hand.bet * 2
	hand.doubled = true
	AddCard(game, hand, random)
	hand.done = true
	Advance(game, random)
	return true
end

-- Two hands from a pair, each with a second card; split aces get that one card and stand.
function ns.Blackjack_Split(game, random)
	if not ns.Blackjack_Actions(game).split then
		return false
	end
	local round = game.round
	local first = round.hands[1]
	game.chips = game.chips - first.bet
	local second = { cards = { first.cards[2] }, bet = first.bet, split = true }
	first.cards[2] = nil
	first.split = true
	round.hands[2] = second
	local aces = Rank(first.cards[1]) == 1
	for _, hand in ipairs(round.hands) do
		AddCard(game, hand, random)
		if aces then
			hand.done = true
		end
	end
	Advance(game, random)
	return true
end

-- For testing splits in game: swaps cards in the shoe so the next deal gives you a pair (your cards are the 1st and
-- 3rd dealt). Returns false when the shoe is too short.
function ns.Blackjack_StackPair(game)
	local shoe, first = game.shoe, game.next
	if ns.Blackjack_Left(game) < DECKS * 52 * RESHUFFLE_AT + 3 then
		return false
	end
	local want = CardValue(shoe[first])
	for i = first + 3, #shoe do
		if CardValue(shoe[i]) == want then
			shoe[first + 2], shoe[i] = shoe[i], shoe[first + 2]
			return true
		end
	end
	return false
end

-- Text ----------------------------------------------------------------------------------------------------------

local RESULT_TEXT = { blackjack = "Blackjack", win = "Win", push = "Push", lose = "Lose", bust = "Bust" }

-- "Blackjack", "Win", "Push", "Lose" or "Bust".
function ns.Blackjack_ResultText(result)
	return RESULT_TEXT[result]
end

-- "17", "soft 17" or "Bust" for a list of cards.
function ns.Blackjack_ValueText(cards)
	local total, soft = ns.Blackjack_Value(cards)
	if total > 21 then
		return "Bust"
	end
	return soft and ("soft " .. total) or tostring(total)
end

-- The line under the table once a round is settled: what happened, and the chips won or lost.
-- thousands(n): the number formatter (ns.Thousands in the game).
function ns.Blackjack_RoundText(round, thousands)
	local dealerTotal = ns.Blackjack_Value(round.dealer)
	local what
	local hands = round.hands
	if round.dealerNatural then
		what = "Dealer has blackjack."
	elseif #hands == 1 and hands[1].result == "blackjack" then
		what = "Blackjack!"
	elseif #hands == 1 and hands[1].result == "bust" then
		what = "Bust."
	elseif dealerTotal > 21 then
		what = "Dealer busts."
	else
		what = "Dealer has " .. dealerTotal .. "."
	end
	local net = round.net or 0
	if net > 0 then
		return what .. " You win " .. thousands(net) .. "."
	elseif net < 0 then
		return what .. " You lose " .. thousands(-net) .. "."
	end
	return what .. " Push."
end
