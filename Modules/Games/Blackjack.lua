local addonName, ns = ...

-- Blackjack: a blackjack table for play chips, opened by command, key binding or (settings) on its own when you take
-- a flight path or queue for a group. Hides in combat and comes back after. Chips are earned by playing the game
-- (Earn.lua, paid by ChipRules.lua) and spent at the Cashier (Cashier.lua, CashierData.lua). While the table is open
-- the Flight module skips its cinematic (Modules/Flight/Flight.lua asks ns.Blackjack_IsOpen). Rules in
-- BlackjackRules.lua, the window in Table.lua.

local TAXI_CHECK = 1 -- seconds between UnitOnTaxi checks after losing control (it can lag the event)
local TAKEOFF_CHECKS = 5 -- that many checks before losing control is taken as not a flight
local FLIGHT_POLL = 1 -- seconds between checks while flying
local LANDED_CHECKS = 3 -- checks off the taxi in a row that count as landed
local LOADING_GRACE = 3 -- seconds after a loading screen before UnitOnTaxi is trusted (as in Modules/Flight)
local FEAT_CHECK = 5 -- seconds after the module starts before feats already earned are announced
local MODULE_KEY = "blackjack"
local ICON = 134493 -- inv_misc_ticket_tarot_stack_01
-- Group queues the table waits through: dungeon finder, raid finder, scenarios (battlegrounds are read separately).
local LFG_CATEGORIES = { LE_LFG_CATEGORY_LFD, LE_LFG_CATEGORY_RF, LE_LFG_CATEGORY_SCENARIO }

ns.BLACKJACK_ICON = ICON

local module, db
local forFlight = false -- the table opened on its own for this flight
local forQueue = false -- the table opened on its own for this queue
local wasQueued = false -- in a queue at the last check: the table opens when a queue starts, not on every update
local afterCombat = false -- combat hid the table: show it again when combat ends
local flightTicker -- runs while you're on a flight path
local offTaxi = 0 -- checks in a row the flight ticker found you off the taxi

local function Show()
	if ns.Module_RequireOn(module) then
		ns.BlackjackTable_Show()
	end
end

local function Toggle()
	if ns.Module_RequireOn(module) then
		forFlight, forQueue = false, false
		ns.BlackjackTable_Toggle()
	end
end

function ns.Blackjack_Active()
	return module.active
end

-- Feats -----------------------------------------------------------------------------------------------------------

-- Card backs unlocked by a feat (CashierData.lua) since the last check get a toast.
function ns.Blackjack_CheckFeats()
	if not module.active then
		return
	end
	for _, item in ipairs(ns.Cashier_NewFeats(db.game.stats, db.feats)) do
		ns.Toast_Show({
			owner = MODULE_KEY, label = "Blackjack", accent = "accent", icon = ICON, mergeKey = "blackjack:" .. item.key,
			title = item.name .. " card back",
			text = ("Unlocked for %s. Pick it at the table's Cashier."):format(item.feat.text),
		})
		ns.Session_Note("blackjack", { title = "Blackjack: the " .. item.name .. " card back", icon = ICON,
			detail = "unlocked for " .. item.feat.text })
	end
	ns.BlackjackCashier_Refresh()
end

-- Earning ---------------------------------------------------------------------------------------------------------

local function Paid(source, amount)
	ns.BlackjackTable_Earned(source, amount)
	ns.Blackjack_CheckFeats()
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
	ns.BlackjackEarn_FlightEnd()
	if forFlight then
		forFlight = false
		if db.closeOnLand then
			ns.BlackjackTable_Hide()
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
	ns.BlackjackEarn_FlightStart()
	offTaxi = 0
	flightTicker = C_Timer.NewTicker(FLIGHT_POLL, FlightTick)
	if db.taxi and not InCombatLockdown() and not ns.BlackjackTable_IsShown() then
		forFlight = true
		ns.BlackjackTable_Show()
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
		ns.BlackjackTable_Hide()
	elseif forQueue and not queued then
		forQueue = false
		ns.BlackjackTable_Hide()
	elseif started and db.queue and not IsInInstance() and not InCombatLockdown()
		and not ns.BlackjackTable_IsShown() then
		forQueue = true
		ns.BlackjackTable_Show()
	end
end

-- Events ----------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	if self[event] then
		self[event](self, ...)
	end
	ns.BlackjackEarn_OnEvent(event, ...)
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
	if ns.BlackjackTable_IsShown() then
		afterCombat = true
		ns.BlackjackTable_Hide()
	end
end

function events:PLAYER_REGEN_ENABLED()
	if afterCombat then
		afterCombat = false
		ns.BlackjackTable_Show()
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
	for _, event in ipairs(ns.BLACKJACK_EARN_EVENTS) do
		events:RegisterEvent(event)
	end
	wasQueued = QueueState()
	if ns.inWorld then
		CheckTaxi()
	end
	C_Timer.After(FEAT_CHECK, ns.Blackjack_CheckFeats)
end

local function Stop()
	events:UnregisterAllEvents()
	StopWatchingFlight()
	ns.BlackjackEarn_Stop()
	forFlight, forQueue, wasQueued, afterCombat = false, false, false, false
	ns.BlackjackTable_Hide()
end

-- For the Flight module: the table is up, so no cinematic over it.
function ns.Blackjack_IsOpen()
	return module.active and ns.BlackjackTable_IsShown() or false
end

-- Commands ------------------------------------------------------------------------------------------------------

local function Stats()
	local game, s = db.game, db.game.stats
	ns.Print(("blackjack: %s chips (%s). %s hands: %s won, %s lost, %s pushed, %s blackjacks. Biggest win %s, best "
		.. "streak %s, most chips %s, chips earned %s, house refills %s."):format(ns.Thousands(game.chips),
		ns.Chips_Rank(s.peak), ns.Thousands(s.hands), ns.Thousands(s.wins), ns.Thousands(s.losses),
		ns.Thousands(s.pushes), ns.Thousands(s.blackjacks), ns.Thousands(s.biggestWin), ns.Thousands(s.bestStreak),
		ns.Thousands(s.peak), ns.Thousands(s.earned), ns.Thousands(s.refills)))
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
local function StartOver()
	db.game = ns.Blackjack_NewGame()
	ns.BlackjackTable_ApplyLook()
	ns.BlackjackTable_Refresh()
	ns.Print(("blackjack: a fresh %s chips, stats cleared."):format(ns.Thousands(ns.BLACKJACK_START_CHIPS)))
end

local function Today()
	local today = ns.Chips_Today(db.earned, (ns.BlackjackEarn_Day()))
	if #today == 0 then
		ns.Print("blackjack: no chips earned today yet.")
		return
	end
	local parts = {}
	for _, row in ipairs(today) do
		parts[#parts + 1] = row[1] .. " " .. ns.Thousands(row[2])
	end
	ns.Print("blackjack, earned today: " .. table.concat(parts, ", ") .. ".")
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("BLACKJACK", MODULE_KEY, function()
	forFlight, forQueue = false, false
	ns.BlackjackTable_Toggle()
end)
BINDING_NAME_TOMTE_BLACKJACK = "Blackjack table"

module = ns.RegisterModule({
	key = MODULE_KEY,
	name = "Blackjack",
	category = "ambience",
	icon = ICON,
	summary = "A blackjack table for play chips you earn out in the world.",
	description = "You against the dealer at a classic casino table, for play chips only. Six decks, the dealer "
		.. "stands on all 17s, blackjack pays 3:2, double and split. Earn chips on flight paths, from quests, the "
		.. "Great Vault and gold you loot; spend them on card backs and felts at the Cashier. Run dry and the house "
		.. "tops you up once a day. Open it with /tomte blackjack or a key binding, or have it open on its own on "
		.. "flight paths or while you wait in a queue.",
	enabledByDefault = true,
	toasts = true,
	defaults = {
		taxi = false,
		closeOnLand = true,
		queue = false,
		sounds = true,
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = 60 }, -- ns.BlackjackTable_ResetPlace repeats it
		game = ns.Blackjack_NewGame(), -- chips, bet, shoe, round in play, stats (BlackjackRules.lua)
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
		ns.BlackjackEarn_Init(db, Paid)
		ns.BlackjackTable_Init(db)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "", "open or close the table", Toggle, hidden = true },
		{ "open", "open the blackjack table", Show },
		{ "stats", "your chips and stats, in chat", Stats },
		{ "today", "chips earned today, in chat", Today },
		{ "split", "make your next hand a pair (to try a split)", StackPair },
		{ "reset", "put the table back in the middle of the screen", ns.BlackjackTable_ResetPlace, whileOff = true },
	},
	options = {
		{ type = "header", label = "Table" },
		{ type = "button", label = "Blackjack table", text = "Open", onClick = Show,
			tooltip = "Key Bindings > Tomte > Blackjack table opens and closes it with a key." },
		{ type = "checkbox", key = "sounds", label = "Sounds",
			tooltip = "Cards, chips and a sound for each win or loss, on the game's sound effects volume." },
		{ type = "button", label = "Table position", text = "Reset", onClick = ns.BlackjackTable_ResetPlace },
		{ type = "button", label = "Chips and stats", text = "Start over", onClick = StartOver,
			confirm = "Start over with a fresh 1,000 chips and clear your blackjack stats? Card backs and felts you "
				.. "bought stay yours." },
		{ type = "header", label = "Opens on its own" },
		{ type = "checkbox", key = "taxi", label = "On flight paths",
			tooltip = "The table opens when you take a flight path. While it's open, Flight Timer's cinematic doesn't play." },
		{ type = "checkbox", key = "closeOnLand", label = "Close when you land", parent = "taxi",
			tooltip = "Only when it opened for that flight." },
		{ type = "checkbox", key = "queue", label = "While you wait in a queue",
			tooltip = "The table opens when you queue for a dungeon, raid or battleground (not from inside an "
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
