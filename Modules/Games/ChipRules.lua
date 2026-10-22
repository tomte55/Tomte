local addonName, ns = ...

-- Blackjack: pure logic (no WoW API calls; unit-tested in tests/test_chiprules.lua). Chips earned by playing the game
-- (flight paths, quests, the Great Vault, looted gold), the house's once-a-day refill and the rank from the most chips
-- ever held. The day's tally is TomteDB.blackjack.earned; days and weeks are keyed by the time of their next reset.
-- Read from the game in Earn.lua, drawn in Table.lua.

local PER_FLIGHT_MINUTE = 10
local FLIGHT_MAX_MINUTES = 20 -- a "flight" longer than this (a logout on a taxi, a clock jump) pays for 20
local QUEST_PAY = { normal = 25, daily = 50, weekly = 250 }
local VAULT_PAY = 1000
local COPPER_PER_CHIP = 10000 -- one chip per whole gold looted
local LOOT_DAY_CAP = 500
local REFILL_TO = 500
local RESET_ROUND = 600 -- seconds: reset times are on the hour, so a key rounded to 10 minutes ignores clock jitter

ns.CHIPS_REFILL_TO = REFILL_TO
ns.CHIPS_SOURCES = { "flight", "quest", "vault", "loot" } -- display order
ns.CHIPS_SOURCE_NAMES = { flight = "Flight paths", quest = "Quests", vault = "Great Vault", loot = "Gold looted" }
local FLOAT_LABEL = { flight = "flight", quest = "quest", vault = "Great Vault", loot = "loot" }

-- By the most chips ever held, so spending at the Cashier never lowers it.
local RANKS = { { at = 0, name = "Regular" }, { at = 25000, name = "High roller" }, { at = 100000, name = "Whale" } }

-- A day or week key: the time of its next reset. now and secondsLeft: the server time and the seconds until reset.
function ns.Chips_ResetKey(now, secondsLeft)
	return math.floor((now + secondsLeft) / RESET_ROUND + 0.5) * RESET_ROUND
end

-- The tally (TomteDB.blackjack.earned), started over when the day moved on.
local function Tally(earned, day)
	if earned.day ~= day or type(earned.today) ~= "table" then
		earned.day = day
		earned.today = {}
		earned.lootCopper = 0
	end
	return earned.today
end

local function Record(earned, day, source, amount)
	local today = Tally(earned, day)
	if amount > 0 then
		today[source] = (today[source] or 0) + amount
	end
	return amount
end

-- Chips for `seconds` in the air: whole minutes only.
function ns.Chips_FlightPay(earned, day, seconds)
	local minutes = math.min(math.floor(seconds / 60), FLIGHT_MAX_MINUTES)
	return Record(earned, day, "flight", math.max(minutes, 0) * PER_FLIGHT_MINUTE)
end

-- frequency: "daily", "weekly" or nil (any other quest).
function ns.Chips_QuestPay(earned, day, frequency)
	return Record(earned, day, "quest", QUEST_PAY[frequency] or QUEST_PAY.normal)
end

-- The first Great Vault claim of the week pays; week: the week's key.
function ns.Chips_VaultPay(earned, day, week)
	if earned.vaultWeek == week then
		return 0
	end
	earned.vaultWeek = week
	return Record(earned, day, "vault", VAULT_PAY)
end

-- Gold picked up from loot: a chip per whole gold, carrying the rest over, at most LOOT_DAY_CAP chips a day.
function ns.Chips_LootPay(earned, day, copper)
	local today = Tally(earned, day)
	local total = (earned.lootCopper or 0) + math.max(copper, 0)
	local chips = math.floor(total / COPPER_PER_CHIP)
	earned.lootCopper = total - chips * COPPER_PER_CHIP
	chips = math.min(chips, math.max(LOOT_DAY_CAP - (today.loot or 0), 0))
	return Record(earned, day, "loot", chips)
end

-- "+25 quest" over the chip count.
function ns.Chips_FloatText(source, amount, thousands)
	return "+" .. thousands(amount) .. " " .. FLOAT_LABEL[source]
end

-- The chips a bet shows as in its betting circle, bottom to top: the fewest chips of the values in `values`, the
-- biggest at the bottom, at most `max` (the small ones on top are left off a tall stack).
function ns.Chips_Stack(amount, values, max)
	local sorted = {}
	for i, v in ipairs(values) do
		sorted[i] = v
	end
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local out = {}
	for _, v in ipairs(sorted) do
		while amount >= v and #out < max do
			out[#out + 1] = v
			amount = amount - v
		end
	end
	return out
end

-- What was earned today, in display order: { { name, amount } ... }, sources with nothing left out.
function ns.Chips_Today(earned, day)
	local out = {}
	if earned.day ~= day or type(earned.today) ~= "table" then
		return out
	end
	for _, source in ipairs(ns.CHIPS_SOURCES) do
		local amount = earned.today[source]
		if amount and amount > 0 then
			out[#out + 1] = { ns.CHIPS_SOURCE_NAMES[source], amount }
		end
	end
	return out
end

-- The house -------------------------------------------------------------------------------------------------------

function ns.Chips_RefillReady(earned, day)
	return earned.refillDay ~= day
end

-- Tops the game up to REFILL_TO once a day. Returns the chips given, or false.
function ns.Chips_Refill(game, earned, day)
	if not ns.Chips_RefillReady(earned, day) then
		return false
	end
	local given = ns.Blackjack_Refill(game, REFILL_TO)
	if given then
		earned.refillDay = day
	end
	return given
end

-- "in 6h", "in 25m" for the seconds until the house refills.
function ns.Chips_WaitText(seconds)
	if seconds >= 3600 then
		return ("in %dh"):format(math.floor(seconds / 3600))
	end
	return ("in %dm"):format(math.max(math.ceil(seconds / 60), 1))
end

-- Rank ------------------------------------------------------------------------------------------------------------

-- The rank's name for the most chips held, then the next rank's name and threshold (nil at the top).
function ns.Chips_Rank(peak)
	local i = 1
	for j, rank in ipairs(RANKS) do
		if peak >= rank.at then
			i = j
		end
	end
	local nextRank = RANKS[i + 1]
	return RANKS[i].name, nextRank and nextRank.name, nextRank and nextRank.at
end
