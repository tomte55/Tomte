local addonName, ns = ...

-- Games: pure logic (no WoW API calls; unit-tested in tests/test_carddata.lua). Playing cards as numbers, so a shoe
-- saves as a plain list: 1-13 are spades ace to king, 14-26 hearts, 27-39 diamonds, 40-52 clubs. Used by
-- BlackjackRules.lua and any later card game.

local RANKS = 13
local SUITS = { "spade", "heart", "diamond", "club" }
local RANK_TEXT = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

ns.CARDS_SUITS = SUITS

-- 1 (ace) to 13 (king).
function ns.Cards_Rank(card)
	return (card - 1) % RANKS + 1
end

-- "spade", "heart", "diamond" or "club".
function ns.Cards_Suit(card)
	return SUITS[math.floor((card - 1) / RANKS) + 1]
end

function ns.Cards_IsRed(card)
	local suit = ns.Cards_Suit(card)
	return suit == "heart" or suit == "diamond"
end

-- "A", "2" ... "10", "J", "Q", "K".
function ns.Cards_RankText(card)
	return RANK_TEXT[ns.Cards_Rank(card)]
end

-- The card of `rank` (1-13) in suit index `suit` (1-4).
function ns.Cards_Make(rank, suit)
	return (suit - 1) * RANKS + rank
end

-- Shuffles list in place (Fisher-Yates). random(n) -> 1..n, math.random in the game.
function ns.Cards_Shuffle(list, random)
	for i = #list, 2, -1 do
		local j = random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- `decks` full decks, shuffled.
function ns.Cards_NewShoe(decks, random)
	local shoe = {}
	for _ = 1, decks do
		for card = 1, RANKS * #SUITS do
			shoe[#shoe + 1] = card
		end
	end
	return ns.Cards_Shuffle(shoe, random)
end
