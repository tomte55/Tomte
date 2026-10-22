local addonName, ns = ...

-- Slots: pure logic (no WoW API calls; unit-tested in tests/test_slotsrules.lua). Three reels, three rows, five
-- paylines (the rows and both diagonals, always on). A spin is settled at once: the stops are picked, the lines paid,
-- and the saved game only keeps where the reels stopped and what they paid. The game is game.slots in the casino's
-- saved game (BlackjackRules.lua holds the chips). Drawn in SlotMachine.lua.

local LINE_SHARE = 5 -- a fifth of the bet rides on each line
local ANY_BARS = 2 -- three bars of mixed metals on a line pay this, times the line bet

ns.SLOTS_BETS = { 10, 50, 100, 500 } -- the chip buttons; all multiples of LINE_SHARE, so line pays stay whole
ns.SLOTS_ANY_BARS = ANY_BARS

-- Lowest first. pay: three on a line pay this times the line bet. icon: a file ID.
ns.SLOTS_SYMBOLS = {
	{ key = "murloc", letter = "M", name = "Murloc", pay = 4, icon = 134169 }, -- inv_misc_head_murloc_01
	{ key = "copper", letter = "C", name = "Copper bar", pay = 15, icon = 133216, bar = true }, -- inv_ingot_02
	{ key = "silver", letter = "S", name = "Silver bar", pay = 30, icon = 133215, bar = true }, -- inv_ingot_01
	{ key = "gold", letter = "G", name = "Gold bar", pay = 60, icon = 133217, bar = true }, -- inv_ingot_03
	{ key = "ruby", letter = "R", name = "Ruby", pay = 120, icon = 134129 }, -- inv_misc_gem_ruby_02
	{ key = "hearth", letter = "H", name = "Hearthstone", pay = 1000, icon = 134414, jackpot = true }, -- inv_misc_rune_01
}

-- Each reel's strip, by symbol letter: 10 murlocs, 5 copper, 4 silver, 3 gold, 3 rubies and 1 Hearthstone in 26
-- stops, no symbol next to itself. With the pays above that returns 94.9% of what's bet (Slots_ReturnRate).
local STRIPS = {
	"MHMSMGCMRMSGMGMSMCSCRMCMRC",
	"CRCSMGSHMCGMCMSMRMRMSMGMCM",
	"SMCMCHMGCMSMGRMCMRGMSMCRSM",
}

-- Rows 1-3 (top to bottom) per reel; the middle row first.
ns.SLOTS_LINES = { { 2, 2, 2 }, { 1, 1, 1 }, { 3, 3, 3 }, { 1, 2, 3 }, { 3, 2, 1 } }

local SYMBOLS, BY_LETTER = {}, {}
for _, symbol in ipairs(ns.SLOTS_SYMBOLS) do
	SYMBOLS[symbol.key] = symbol
	BY_LETTER[symbol.letter] = symbol.key
end

-- Reels as lists of symbol keys.
ns.SLOTS_REELS = {}
for i, strip in ipairs(STRIPS) do
	local reel = {}
	for n = 1, #strip do
		reel[n] = BY_LETTER[strip:sub(n, n)]
	end
	ns.SLOTS_REELS[i] = reel
end

function ns.Slots_Symbol(key)
	return SYMBOLS[key]
end

-- The symbol on reel i at stop n (any whole number: it wraps around the strip).
function ns.Slots_At(i, n)
	local reel = ns.SLOTS_REELS[i]
	return reel[(n - 1) % #reel + 1]
end

-- The symbol on reel i, row 1-3, with the reel stopped at `stop` (its middle row).
function ns.Slots_Cell(i, stop, row)
	return ns.Slots_At(i, stop + row - 2)
end

-- What three symbols on a line pay, times the line bet: the multiplier and "three" or "bars" (0 and nil: nothing).
function ns.Slots_LinePay(a, b, c)
	if a == b and b == c then
		return SYMBOLS[a].pay, "three"
	end
	if SYMBOLS[a].bar and SYMBOLS[b].bar and SYMBOLS[c].bar then
		return ANY_BARS, "bars"
	end
	return 0, nil
end

-- The share of bets paid back over time: every stop combination of the three reels on one line (each line sees the
-- same odds).
function ns.Slots_ReturnRate()
	local reels, total = ns.SLOTS_REELS, 0
	for _, a in ipairs(reels[1]) do
		for _, b in ipairs(reels[2]) do
			for _, c in ipairs(reels[3]) do
				total = total + ns.Slots_LinePay(a, b, c)
			end
		end
	end
	return total / (#reels[1] * #reels[2] * #reels[3])
end

-- The game -----------------------------------------------------------------------------------------------------

local function Stats()
	return { spins = 0, wins = 0, biggestWin = 0, jackpots = 0, net = 0 }
end

local function ValidBet(bet)
	for _, v in ipairs(ns.SLOTS_BETS) do
		if v == bet then
			return true
		end
	end
	return false
end

-- A saved result whose wins all name a symbol this machine has (symbols were renamed once: coins became bars).
local function ValidLast(last)
	if type(last) ~= "table" or type(last.wins) ~= "table" then
		return false
	end
	for _, win in ipairs(last.wins) do
		if type(win) ~= "table" or not SYMBOLS[win.symbol] then
			return false
		end
	end
	return true
end

-- game.slots, made or filled in where an older or damaged save lacks it. Returns it.
function ns.Slots_Repair(game)
	local slots = type(game.slots) == "table" and game.slots or {}
	game.slots = slots
	if not ValidBet(slots.bet) then
		slots.bet = ns.SLOTS_BETS[1]
	end
	local stops = slots.stops
	if type(stops) ~= "table" or type(stops[1]) ~= "number" or type(stops[2]) ~= "number"
		or type(stops[3]) ~= "number" then
		slots.stops = { 1, 1, 1 }
	end
	slots.stats = type(slots.stats) == "table" and slots.stats or Stats()
	for k, v in pairs(Stats()) do
		if type(slots.stats[k]) ~= "number" then
			slots.stats[k] = v
		end
	end
	if slots.last ~= nil and not ValidLast(slots.last) then
		slots.last = nil
	end
	return slots
end

function ns.Slots_SetBet(game, bet)
	if not ValidBet(bet) then
		return false
	end
	game.slots.bet = bet
	return true
end

-- The lines `stops` win: { { line = n, pay = chips, symbol = key, kind = "three" or "bars" } ... }, and the total.
function ns.Slots_Wins(stops, bet)
	local wins, total = {}, 0
	local lineBet = bet / LINE_SHARE
	for n, rows in ipairs(ns.SLOTS_LINES) do
		local a = ns.Slots_Cell(1, stops[1], rows[1])
		local b = ns.Slots_Cell(2, stops[2], rows[2])
		local c = ns.Slots_Cell(3, stops[3], rows[3])
		local mult, kind = ns.Slots_LinePay(a, b, c)
		if mult > 0 then
			local pay = mult * lineBet
			wins[#wins + 1] = { line = n, pay = pay, symbol = a, kind = kind }
			total = total + pay
		end
	end
	return wins, total
end

-- One spin at the current bet. random(n) -> 1..n. Returns true, or false and "chips". The result is game.slots.last:
-- { bet, payout, net, wins, jackpot }, and game.slots.stops where each reel stopped.
function ns.Slots_Spin(game, random)
	local slots = game.slots
	local bet = slots.bet
	if game.chips < bet then
		return false, "chips"
	end
	game.chips = game.chips - bet
	local stops = {}
	for i, reel in ipairs(ns.SLOTS_REELS) do
		stops[i] = random(#reel)
	end
	local wins, payout = ns.Slots_Wins(stops, bet)
	local jackpot = false
	for _, win in ipairs(wins) do
		jackpot = jackpot or (win.kind == "three" and SYMBOLS[win.symbol].jackpot == true)
	end
	slots.stops = stops
	slots.last = { bet = bet, payout = payout, net = payout - bet, wins = wins, jackpot = jackpot }
	game.chips = game.chips + payout
	local stats = slots.stats
	stats.spins = stats.spins + 1
	stats.net = stats.net + payout - bet
	ns.Blackjack_RecordNet(game, "slots", payout - bet)
	if payout > bet then
		stats.wins = stats.wins + 1
		stats.biggestWin = math.max(stats.biggestWin, payout - bet)
	end
	if jackpot then
		stats.jackpots = stats.jackpots + 1
	end
	game.stats.peak = math.max(game.stats.peak, game.chips)
	return true
end

-- Text ---------------------------------------------------------------------------------------------------------

-- The line under the reels once they stop. thousands(n): the number formatter (ns.Thousands in the game).
function ns.Slots_ResultText(last, thousands)
	if last.jackpot then
		return ("Jackpot! You win %s."):format(thousands(last.payout))
	elseif last.payout == 0 then
		return "No win. Spin again?"
	elseif #last.wins == 1 then
		return ("One line pays %s."):format(thousands(last.payout))
	end
	return ("%d lines pay %s."):format(#last.wins, thousands(last.payout))
end
