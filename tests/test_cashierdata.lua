-- Run from the AddOns folder: lua Tomte/tests/test_cashierdata.lua
local ns = {}
assert(loadfile("Tomte/Modules/Games/CardData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/BlackjackRules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/PokerRules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/SlotsRules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Games/CashierData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function thousands(n)
	return tostring(n)
end

test("every item has a unique key, a name and either a price or a feat", function()
	local seen = {}
	for _, list in ipairs({ ns.CASHIER_BACKS, ns.CASHIER_FELTS }) do
		eq(list[1].cost, 0, "the first item is free")
		for _, item in ipairs(list) do
			eq(seen[item.key], nil, item.key)
			seen[item.key] = true
			eq(type(item.name), "string")
			eq((item.cost ~= nil) ~= (item.feat ~= nil), true, item.key)
		end
	end
end)

test("buying takes chips and owns the item", function()
	local game, owned = ns.Blackjack_NewGame(), {}
	game.chips = 3000
	local lattice = ns.Cashier_Item("back", "lattice")
	eq(ns.Cashier_Has(lattice, owned, game), false)
	eq(ns.Cashier_Buy(game, owned, lattice), true)
	eq(game.chips, 500)
	eq(ns.Cashier_Has(lattice, owned, game), true)
	eq(select(2, ns.Cashier_Buy(game, owned, lattice)), "owned")
	eq(select(2, ns.Cashier_Buy(game, owned, ns.Cashier_Item("felt", "blue"))), "chips")
	eq(game.chips, 500)
end)

test("feat items can't be bought, and unlock from stats", function()
	local game, owned, seen = ns.Blackjack_NewGame(), {}, {}
	game.chips = 1000000
	local natural = ns.Cashier_Item("back", "natural")
	eq(select(2, ns.Cashier_Buy(game, owned, natural)), "feat")
	eq(ns.Cashier_Status(natural, owned, game, thousands), "0 / 50")
	eq(ns.Cashier_FeatText(natural, game, thousands), "Unlocks with 50 blackjacks (0 so far).")
	eq(#ns.Cashier_NewFeats(game, seen), 0)
	game.stats.blackjacks = 50
	local new = ns.Cashier_NewFeats(game, seen)
	eq(#new, 1)
	eq(new[1].key, "natural")
	eq(#ns.Cashier_NewFeats(game, seen), 0)
	eq(ns.Cashier_Status(natural, owned, game, thousands), "Owned")
end)

test("feats from video poker and slots count their own game's stats", function()
	local game, owned, seen = ns.Blackjack_NewGame(), {}, {}
	ns.Poker_Repair(game)
	ns.Slots_Repair(game)
	local quads, jackpot = ns.Cashier_Item("back", "quads"), ns.Cashier_Item("back", "jackpot")
	eq(ns.Cashier_Has(quads, owned, game), false)
	game.stats.quads = 10 -- the casino's stats don't count for a poker feat
	eq(ns.Cashier_Has(quads, owned, game), false)
	game.poker.stats.quads = 3
	eq(ns.Cashier_Has(quads, owned, game), true)
	eq(ns.Cashier_Status(jackpot, owned, game, thousands), "0 / 1")
	game.slots.stats.jackpots = 1
	local new = ns.Cashier_NewFeats(game, seen)
	eq(#new, 2)
end)

test("can't buy during a hand", function()
	local game, owned = ns.Blackjack_NewGame(), {}
	game.round = { phase = "player", hands = {} }
	eq(select(2, ns.Cashier_Buy(game, owned, ns.Cashier_Item("back", "lattice"))), "playing")
end)

test("the look in use falls back to the free item", function()
	local game = ns.Blackjack_NewGame()
	local look, owned = { back = "royal", felt = "nope" }, {}
	eq(ns.Cashier_Using(look, "back", owned, game).key, "classic")
	eq(ns.Cashier_Using(look, "felt", owned, game).key, "green")
	owned.royal = true
	eq(ns.Cashier_Using(look, "back", owned, game).key, "royal")
end)

test("status shows the price", function()
	eq(ns.Cashier_Status(ns.Cashier_Item("felt", "noir"), {}, { stats = {} }, thousands), "25000 chips")
end)

H.done()
