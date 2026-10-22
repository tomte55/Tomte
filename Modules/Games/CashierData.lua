local addonName, ns = ...

-- Blackjack Cashier: pure logic (no WoW API calls; unit-tested in tests/test_cashierdata.lua). The card backs and
-- felts you can buy with chips or unlock with a feat, what you own and which one is in use. Colors are theme roles:
-- base fills the back (dimmed by `dim`), ink draws its pattern (Media/Games/<pattern>.tga) and rule; a felt's role
-- tints the felt (dimmed by `dim`, else Felt.lua's default). A feat counts a stat of the casino's stats (game.stats)
-- or, with `game`, of that game's (game.poker.stats, game.slots.stats). Drawn in Cashier.lua, Card.lua and Felt.lua.

ns.CASHIER_BACKS = {
	{ key = "classic", name = "Classic", base = "accentDeep", ink = "accent", cost = 0 },
	{ key = "lattice", name = "Lattice", base = "accentDeep", ink = "accent", pattern = "BackLattice", cost = 2500 },
	{ key = "sunburst", name = "Sunburst", base = "frameDark", ink = "warning", pattern = "BackSunburst", cost = 5000 },
	{ key = "royal", name = "Royal", base = "danger", dim = 0.45, ink = "text", pattern = "BackDamask", cost = 10000 },
	{ key = "midnight", name = "Midnight", base = "info", dim = 0.35, ink = "text", pattern = "BackStars",
		cost = 25000 },
	{ key = "natural", name = "Natural", base = "success", dim = 0.35, ink = "text", pattern = "BackSpades",
		feat = { stat = "blackjacks", at = 50, text = "50 blackjacks" } },
	{ key = "streak", name = "Hot streak", base = "warning", dim = 0.45, ink = "text", pattern = "BackChevron",
		feat = { stat = "bestStreak", at = 10, text = "a 10-hand win streak" } },
	{ key = "whale", name = "Whale", base = "info", dim = 0.25, ink = "accent", pattern = "BackWaves",
		feat = { stat = "peak", at = 100000, text = "100,000 chips at once" } },
	{ key = "quads", name = "Four of a kind", base = "danger", dim = 0.35, ink = "warning", pattern = "BackLattice",
		feat = { game = "poker", stat = "quads", at = 3, text = "3 fours of a kind in video poker" } },
	{ key = "jackpot", name = "Jackpot", base = "success", dim = 0.3, ink = "warning", pattern = "BackStars",
		feat = { game = "slots", stat = "jackpots", at = 1, text = "a slots jackpot" } },
}

ns.CASHIER_FELTS = {
	{ key = "green", name = "Green", role = "success", cost = 0 },
	{ key = "blue", name = "Blue", role = "info", cost = 5000 },
	{ key = "crimson", name = "Crimson", role = "danger", cost = 10000 },
	{ key = "noir", name = "Black and gold", role = "frameDark", dim = 1, cost = 25000 },
}

local LISTS = { back = ns.CASHIER_BACKS, felt = ns.CASHIER_FELTS }

-- kind: "back" or "felt".
function ns.Cashier_Item(kind, key)
	for _, item in ipairs(LISTS[kind]) do
		if item.key == key then
			return item
		end
	end
end

-- How far along a feat is. game: the casino's saved game.
local function FeatCount(item, game)
	local from = item.feat.game and game[item.feat.game]
	local stats = from and from.stats or game.stats
	return stats and stats[item.feat.stat] or 0
end

local function FeatMet(item, game)
	return item.feat ~= nil and FeatCount(item, game) >= item.feat.at
end

-- owned: [item key] = true (bought). game: the casino's saved game (for feats).
function ns.Cashier_Has(item, owned, game)
	return item.cost == 0 or owned[item.key] == true or FeatMet(item, game)
end

-- Buys item with chips. Returns true, or false and why: "owned", "feat" (not for sale), "playing" or "chips".
function ns.Cashier_Buy(game, owned, item)
	if ns.Cashier_Has(item, owned, game) then
		return false, "owned"
	end
	if item.feat then
		return false, "feat"
	end
	if ns.Blackjack_InPlay(game) then
		return false, "playing"
	end
	if not ns.Blackjack_Spend(game, item.cost) then
		return false, "chips"
	end
	owned[item.key] = true
	return true
end

-- The item in use for kind: the chosen one while you have it, else the free one.
function ns.Cashier_Using(look, kind, owned, game)
	local item = ns.Cashier_Item(kind, look[kind])
	if item and ns.Cashier_Has(item, owned, game) then
		return item
	end
	return LISTS[kind][1]
end

-- Under a swatch: "Owned", "2,500 chips" or a feat's progress, "12 / 50". thousands: the number formatter.
function ns.Cashier_Status(item, owned, game, thousands)
	if ns.Cashier_Has(item, owned, game) then
		return "Owned"
	end
	if item.feat then
		return ("%s / %s"):format(thousands(FeatCount(item, game)), thousands(item.feat.at))
	end
	return thousands(item.cost) .. " chips"
end

-- A feat item's hover line: "Unlocks with 50 blackjacks (12 so far)." Nil for items with a price.
function ns.Cashier_FeatText(item, game, thousands)
	if not item.feat then
		return nil
	end
	return ("Unlocks with %s (%s so far)."):format(item.feat.text, thousands(FeatCount(item, game)))
end

-- Feat items unlocked since last asked: marks them in seen ([item key] = true) and returns them.
function ns.Cashier_NewFeats(game, seen)
	local out = {}
	for _, list in pairs(LISTS) do
		for _, item in ipairs(list) do
			if FeatMet(item, game) and not seen[item.key] then
				seen[item.key] = true
				out[#out + 1] = item
			end
		end
	end
	return out
end
