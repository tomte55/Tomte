-- Run from the AddOns folder: lua Tomte/tests/test_carddata.lua
local ns = {}
assert(loadfile("Tomte/Modules/Games/CardData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("cards 1-52 map to rank and suit", function()
	eq(ns.Cards_Rank(1), 1)
	eq(ns.Cards_Suit(1), "spade")
	eq(ns.Cards_Rank(13), 13)
	eq(ns.Cards_Rank(14), 1)
	eq(ns.Cards_Suit(14), "heart")
	eq(ns.Cards_Suit(27), "diamond")
	eq(ns.Cards_Suit(52), "club")
	eq(ns.Cards_RankText(52), "K")
	eq(ns.Cards_RankText(10), "10")
end)

test("Make is the inverse of Rank and Suit", function()
	for card = 1, 52 do
		local suit
		for i, name in ipairs(ns.CARDS_SUITS) do
			if name == ns.Cards_Suit(card) then
				suit = i
			end
		end
		eq(ns.Cards_Make(ns.Cards_Rank(card), suit), card)
	end
end)

test("red suits", function()
	eq(ns.Cards_IsRed(ns.Cards_Make(5, 2)), true)
	eq(ns.Cards_IsRed(ns.Cards_Make(5, 3)), true)
	eq(ns.Cards_IsRed(ns.Cards_Make(5, 1)), false)
	eq(ns.Cards_IsRed(ns.Cards_Make(5, 4)), false)
end)

test("a shoe holds every card once per deck", function()
	local shoe = ns.Cards_NewShoe(6, math.random)
	eq(#shoe, 312)
	local count = {}
	for _, card in ipairs(shoe) do
		count[card] = (count[card] or 0) + 1
	end
	for card = 1, 52 do
		eq(count[card], 6, "card " .. card)
	end
end)

test("shuffle uses the random function it's given", function()
	-- random always picks 1: each step swaps position i with the first, a fixed rotation.
	local list = ns.Cards_Shuffle({ 1, 2, 3, 4 }, function()
		return 1
	end)
	eq(table.concat(list, ","), "2,3,4,1")
	local same = ns.Cards_Shuffle({ 1, 2, 3, 4 }, function(n)
		return n
	end)
	eq(table.concat(same, ","), "1,2,3,4")
end)

H.done()
