local addonName, ns = ...

-- Casino: blackjack, video poker and slots for play chips in one window, opened by command, key binding or
-- (settings) on its own when you take a flight path or queue for a group. Hides in combat and comes back after. Was
-- the Blackjack module (key "blackjack") until 1.20: migration 13 moved its saved data. Chips are earned by playing the game (Earn.lua, paid by ChipRules.lua) and spent at
-- the Cashier (Cashier.lua, CashierData.lua). While the window is open the Flight module skips its cinematic
-- (Modules/Flight/Flight.lua asks ns.Casino_IsOpen). Rules in BlackjackRules.lua, PokerRules.lua and
-- SlotsRules.lua; the window in Window.lua, its games in Table.lua, PokerMachine.lua and SlotMachine.lua.

local TAXI_CHECK = 1 -- seconds between UnitOnTaxi checks after losing control (it can lag the event)
local TAKEOFF_CHECKS = 5 -- that many checks before losing control is taken as not a flight
local FLIGHT_POLL = 1 -- seconds between checks while flying
local LANDED_CHECKS = 3 -- checks off the taxi in a row that count as landed
local LOADING_GRACE = 3 -- seconds after a loading screen before UnitOnTaxi is trusted (as in Modules/Flight)
local FEAT_CHECK = 5 -- seconds after the module starts before feats already earned are announced
local MODULE_KEY = "casino"
local ICON = 134493 -- inv_misc_ticket_tarot_stack_01
-- Group queues the table waits through: dungeon finder, raid finder, scenarios (battlegrounds are read separately).
local LFG_CATEGORIES = { LE_LFG_CATEGORY_LFD, LE_LFG_CATEGORY_RF, LE_LFG_CATEGORY_SCENARIO }

ns.CASINO_ICON = ICON

local module, db
local forFlight = false -- the table opened on its own for this flight
local forQueue = false -- the table opened on its own for this queue
local wasQueued = false -- in a queue at the last check: the table opens when a queue starts, not on every update
local afterCombat = false -- combat hid the table: show it again when combat ends
local flightTicker -- runs while you're on a flight path
local offTaxi = 0 -- checks in a row the flight ticker found you off the taxi

-- game: "blackjack", "poker" or "slots"; nil opens the last one played.
local function Show(game)
	if ns.Module_RequireOn(module) then
		ns.GamesWindow_Show(game)
	end
end

local function Toggle()
	if ns.Module_RequireOn(module) then
		forFlight, forQueue = false, false
		ns.GamesWindow_Toggle()
	end
end

function ns.Casino_Active()
	return module.active
end

-- Feats -----------------------------------------------------------------------------------------------------------

-- Card backs unlocked by a feat (CashierData.lua) since the last check get a toast.
function ns.Casino_CheckFeats()
	if not module.active then
		return
	end
	for _, item in ipairs(ns.Cashier_NewFeats(db.game, db.feats)) do
		ns.Toast_Show({
			owner = MODULE_KEY, label = "Casino", accent = "accent", icon = ICON, mergeKey = "casino:" .. item.key,
			title = item.name .. " card back",
			text = ("Unlocked for %s. Pick it at the Cashier."):format(item.feat.text),
		})
		ns.Session_Note("casino", { title = "Casino: the " .. item.name .. " card back", icon = ICON,
			detail = "unlocked for " .. item.feat.text })
	end
	ns.CasinoCashier_Refresh()
end

-- Earning ---------------------------------------------------------------------------------------------------------

local function Paid(source, amount)
	ns.GamesWindow_Earned(source, amount)
	ns.Casino_CheckFeats()
end

-- Flight paths ----------------------------------------------------------------------------------------------------

-- UnitOnTaxi flickers around takeoff and landing (Modules/Flight polls it for the same reason), so a flight is
-- watched by a ticker that runs only while you're in the air, and lands after several checks off the taxi in a row.
local function StopWatchingFlight()
	if flightTicker then
		flightTicker:Cancel()
		flightTicker = nil
	end
end

local function Landed()
	StopWatchingFlight()
	ns.CasinoEarn_FlightEnd()
	if forFlight then
		forFlight = false
		if db.closeOnLand then
			ns.GamesWindow_Hide()
		end
	end
end

local function FlightTick()
	if UnitOnTaxi("player") then
		offTaxi = 0
		return
	end
	offTaxi = offTaxi + 1
	if offTaxi >= LANDED_CHECKS then
		Landed()
	end
end

local function CheckTaxi()
	if not module.active or flightTicker or not UnitOnTaxi("player") then
		return
	end
	ns.CasinoEarn_FlightStart()
	offTaxi = 0
	flightTicker = C_Timer.NewTicker(FLIGHT_POLL, FlightTick)
	if db.taxi and not InCombatLockdown() and not ns.GamesWindow_IsShown() then
		forFlight = true
		ns.GamesWindow_Show()
	end
end

-- Queues ----------------------------------------------------------------------------------------------------------

-- queued: waiting in a dungeon, raid, scenario or battleground queue; popped: one of them is ready to enter.
local function QueueState()
	local queued, popped = false, false
	for _, category in ipairs(LFG_CATEGORIES) do
		local mode = GetLFGMode(category)
		queued = queued or mode == "queued"
		popped = popped or mode == "proposal"
	end
	for i = 1, GetMaxBattlefieldID() do
		local status = GetBattlefieldStatus(i)
		queued = queued or status == "queued"
		popped = popped or status == "confirm"
	end
	return queued, popped
end

-- A queue that pops closes the table however it was opened (and keeps combat from bringing it back), so it never
-- covers the accept button. With the setting on, the table opens when a queue starts (not inside an instance) and a
-- table opened that way closes when the queue ends.
local function CheckQueue()
	if not module.active then
		return
	end
	local queued, popped = QueueState()
	local started = queued and not wasQueued
	wasQueued = queued
	if popped then
		forQueue, afterCombat = false, false
		ns.GamesWindow_Hide()
	elseif forQueue and not queued then
		forQueue = false
		ns.GamesWindow_Hide()
	elseif started and db.queue and not IsInInstance() and not InCombatLockdown()
		and not ns.GamesWindow_IsShown() then
		forQueue = true
		ns.GamesWindow_Show()
	end
end

-- Events ----------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	if self[event] then
		self[event](self, ...)
	end
	ns.CasinoEarn_OnEvent(event, ...)
end)

-- Losing control may be a takeoff: UnitOnTaxi can take a moment to say so.
function events:PLAYER_CONTROL_LOST()
	C_Timer.NewTicker(TAXI_CHECK, CheckTaxi, TAKEOFF_CHECKS)
end

-- A /reload or a loading screen: still in the air (watch on), or landed while away (pay the saved flight).
function events:PLAYER_ENTERING_WORLD()
	C_Timer.After(LOADING_GRACE, function()
		if not module.active then
			return
		end
		CheckTaxi()
		if not flightTicker and db.earned.flightStart then
			Landed()
		end
	end)
end

function events:PLAYER_REGEN_DISABLED()
	if ns.GamesWindow_IsShown() then
		afterCombat = true
		ns.GamesWindow_Hide()
	end
end

function events:PLAYER_REGEN_ENABLED()
	if afterCombat then
		afterCombat = false
		ns.GamesWindow_Show()
	end
end

events.LFG_UPDATE = CheckQueue
events.LFG_QUEUE_STATUS_UPDATE = CheckQueue
events.LFG_PROPOSAL_SHOW = CheckQueue
events.UPDATE_BATTLEFIELD_STATUS = CheckQueue

local EVENTS = {
	"PLAYER_CONTROL_LOST", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS",
}

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs(ns.CASINO_EARN_EVENTS) do
		events:RegisterEvent(event)
	end
	wasQueued = QueueState()
	if ns.inWorld then
		CheckTaxi()
	end
	C_Timer.After(FEAT_CHECK, ns.Casino_CheckFeats)
end

local function Stop()
	events:UnregisterAllEvents()
	StopWatchingFlight()
	ns.CasinoEarn_Stop()
	forFlight, forQueue, wasQueued, afterCombat = false, false, false, false
	ns.GamesWindow_Hide()
end

-- For the Flight module: the table is up, so no cinematic over it.
function ns.Casino_IsOpen()
	return module.active and ns.GamesWindow_IsShown() or false
end

-- Commands ------------------------------------------------------------------------------------------------------

local function Stats()
	local game, s = db.game, db.game.stats
	local T = ns.Thousands
	ns.Print(("casino: %s chips (%s). Most chips %s, chips earned %s, house refills %s."):format(T(game.chips),
		ns.Chips_Rank(s.peak), T(s.peak), T(s.earned), T(s.refills)))
	ns.Print(("blackjack: %s hands: %s won, %s lost, %s pushed, %s blackjacks. Biggest win %s, best streak %s.")
		:format(T(s.hands), T(s.wins), T(s.losses), T(s.pushes), T(s.blackjacks), T(s.biggestWin), T(s.bestStreak)))
	local p = game.poker.stats
	ns.Print(("video poker: %s hands, %s won, biggest win %s. Royal flushes %s, straight flushes %s, fours of a kind "
		.. "%s."):format(T(p.hands), T(p.wins), T(p.biggestWin), T(p.royal), T(p.straightFlush), T(p.quads)))
	local sl = game.slots.stats
	ns.Print(("slots: %s spins, %s won, biggest win %s, jackpots %s."):format(T(sl.spins), T(sl.wins),
		T(sl.biggestWin), T(sl.jackpots)))
end

local function StackPair()
	if ns.Blackjack_InPlay(db.game) then
		ns.Print("finish this hand first.")
	elseif ns.Blackjack_StackPair(db.game) then
		ns.Print("your next hand is a pair.")
	else
		ns.Print("the shoe is about to be shuffled: deal once, then try again.")
	end
end

-- Cashier purchases are kept: they were bought, they aren't stats.
local function NewGame()
	local game = ns.Blackjack_NewGame()
	ns.Poker_Repair(game)
	ns.Slots_Repair(game)
	return game
end

local function StartOver()
	db.game = NewGame()
	ns.GamesWindow_ApplyLook()
	ns.GamesWindow_Refresh()
	ns.Print(("casino: a fresh %s chips, stats cleared."):format(ns.Thousands(ns.BLACKJACK_START_CHIPS)))
end

local function Today()
	local today = ns.Chips_Today(db.earned, (ns.CasinoEarn_Day()))
	if #today == 0 then
		ns.Print("casino: no chips earned today yet.")
		return
	end
	local parts = {}
	for _, row in ipairs(today) do
		parts[#parts + 1] = row[1] .. " " .. ns.Thousands(row[2])
	end
	ns.Print("casino, earned today: " .. table.concat(parts, ", ") .. ".")
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("CASINO", MODULE_KEY, function()
	forFlight, forQueue = false, false
	ns.GamesWindow_Toggle()
end)
BINDING_NAME_TOMTE_CASINO = "Casino"

module = ns.RegisterModule({
	key = MODULE_KEY,
	name = "Casino",
	category = "ambience",
	icon = ICON,
	summary = "Blackjack, video poker and slots for play chips you earn out in the world.",
	description = "Three games in one window, for play chips only. Blackjack: you against the dealer, six decks, the "
		.. "dealer stands on all 17s, blackjack pays 3:2, double and split. Video poker: Jacks or Better on the "
		.. "full-pay table. Slots: three reels, five lines, a Hearthstone jackpot. Earn chips on flight paths, from "
		.. "quests, the Great Vault and gold you loot; spend them on card backs and felts at the Cashier. Run dry and "
		.. "the house tops you up once a day. Open it with /tomte casino or a key binding, or have it open on its "
		.. "own on flight paths or while you wait in a queue.",
	enabledByDefault = true,
	toasts = true,
	defaults = {
		taxi = false,
		closeOnLand = true,
		queue = false,
		sounds = true,
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = 60 }, -- ns.GamesWindow_ResetPlace repeats it
		lastGame = "blackjack", -- the game the window opens on: "blackjack", "poker" or "slots"
		-- Chips, bet, shoe, round in play and stats (BlackjackRules.lua); game.poker and game.slots hold the other
		-- games (PokerRules.lua, SlotsRules.lua), filled in by their Repair.
		game = NewGame(),
		earn = { flight = true, quest = true, vault = true, loot = true }, -- which ways of earning chips are on
		-- Today's tally (ChipRules.lua): day, today = { [source] = chips }, lootCopper, vaultWeek, refillDay (reset
		-- times as keys), flightStart (server time, while on a taxi).
		earned = {},
		look = { back = "classic", felt = "green" }, -- the Cashier items in use
		owned = {}, -- [item key] = true: bought at the Cashier
		feats = {}, -- [item key] = true: feat items already announced
	},
	keep = { "game" }, -- your chips and stats: a settings reset keeps them, profiles don't carry them
	init = function(saved)
		db = saved
		ns.Blackjack_Repair(db.game)
		ns.Poker_Repair(db.game)
		ns.Slots_Repair(db.game)
		ns.CasinoEarn_Init(db, Paid)
		ns.GamesWindow_Init(db)
		ns.BlackjackTable_Init(db)
		ns.PokerMachine_Init(db)
		ns.SlotMachine_Init(db)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "", "open or close the casino", Toggle, hidden = true },
		{ "open", "open the casino on the last game played", function()
			Show()
		end },
		{ "blackjack", "open the blackjack table", function()
			Show("blackjack")
		end },
		{ "poker", "open video poker", function()
			Show("poker")
		end },
		{ "slots", "open the slots", function()
			Show("slots")
		end },
		{ "stats", "your chips and stats for all three games, in chat", Stats },
		{ "today", "chips earned today, in chat", Today },
		{ "split", "make your next hand a pair (to try a split)", StackPair },
		{ "reset", "put the window back in the middle of the screen", ns.GamesWindow_ResetPlace, whileOff = true },
	},
	options = {
		{ type = "header", label = "Casino" },
		{ type = "button", label = "Casino", text = "Open", onClick = function()
			Show()
		end, tooltip = "Opens on the last game you played. Key Bindings > Tomte > Casino opens and closes it with a "
			.. "key." },
		{ type = "checkbox", key = "sounds", label = "Sounds",
			tooltip = "Cards, chips, reels and a sound for each win, on the game's sound effects volume." },
		{ type = "button", label = "Window position", text = "Reset", onClick = ns.GamesWindow_ResetPlace },
		{ type = "button", label = "Chips and stats", text = "Start over", onClick = StartOver,
			confirm = "Start over with a fresh 1,000 chips and clear your stats in all three games? Card backs and "
				.. "felts you bought stay yours." },
		{ type = "header", label = "Opens on its own" },
		{ type = "checkbox", key = "taxi", label = "On flight paths",
			tooltip = "The casino opens when you take a flight path. While it's open, Flight Timer's cinematic doesn't "
				.. "play." },
		{ type = "checkbox", key = "closeOnLand", label = "Close when you land", parent = "taxi",
			tooltip = "Only when it opened for that flight." },
		{ type = "checkbox", key = "queue", label = "While you wait in a queue",
			tooltip = "The casino opens when you queue for a dungeon, raid or battleground (not from inside an "
				.. "instance), and closes when the queue pops so the accept button is free." },
		{ type = "header", label = "Earning chips" },
		{ type = "checkbox", key = "earn.flight", label = "Flight paths",
			tooltip = "10 chips for each minute in the air." },
		{ type = "checkbox", key = "earn.quest", label = "Quests",
			tooltip = "25 chips for each quest you turn in, 50 for a daily, 250 for a weekly." },
		{ type = "checkbox", key = "earn.vault", label = "Great Vault",
			tooltip = "1,000 chips the first time you claim your Great Vault reward each week." },
		{ type = "checkbox", key = "earn.loot", label = "Gold you loot",
			tooltip = "A chip for each gold you loot, up to 500 chips a day. Your gold isn't touched." },
	},
})
