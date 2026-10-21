local addonName, ns = ...

-- Blackjack: a blackjack table for play chips, opened by command, key binding or (a setting) on its own when you
-- take a flight path. Hides in combat and comes back after. While it's open the Flight module skips its cinematic
-- (Modules/Flight/Flight.lua asks ns.Blackjack_IsOpen). Rules in BlackjackRules.lua, the window in Table.lua.

local TAXI_CHECK = 1 -- seconds after losing control before UnitOnTaxi is asked (it can lag the event)
local LOADING_GRACE = 3 -- seconds after a loading screen before UnitOnTaxi is trusted (as in Modules/Flight)
local MODULE_KEY = "blackjack"

local module, db
local forFlight = false -- the table opened on its own for this flight
local afterCombat = false -- combat hid the table: show it again when combat ends

local function Show()
	if ns.Module_RequireOn(module) then
		ns.BlackjackTable_Show()
	end
end

local function Toggle()
	if ns.Module_RequireOn(module) then
		forFlight = false
		ns.BlackjackTable_Toggle()
	end
end

-- Flight paths ----------------------------------------------------------------------------------------------------

local function CheckTaxi()
	if not (module.active and db.taxi) or InCombatLockdown() then
		return
	end
	if UnitOnTaxi("player") and not ns.BlackjackTable_IsShown() then
		forFlight = true
		ns.BlackjackTable_Show()
	end
end

local function Landed()
	if forFlight and not UnitOnTaxi("player") then
		forFlight = false
		if db.closeOnLand then
			ns.BlackjackTable_Hide()
		end
	end
end

-- Events ------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:PLAYER_CONTROL_LOST()
	C_Timer.After(TAXI_CHECK, CheckTaxi)
end

function events:PLAYER_CONTROL_GAINED()
	Landed()
end

-- A /reload or a loading screen in mid-flight.
function events:PLAYER_ENTERING_WORLD()
	C_Timer.After(LOADING_GRACE, function()
		if module.active then
			CheckTaxi()
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

local EVENTS = {
	"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
}

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	if ns.inWorld then
		CheckTaxi()
	end
end

local function Stop()
	events:UnregisterAllEvents()
	forFlight, afterCombat = false, false
	ns.BlackjackTable_Hide()
end

-- For the Flight module: the table is up, so no cinematic over it.
function ns.Blackjack_IsOpen()
	return module.active and ns.BlackjackTable_IsShown() or false
end

-- Commands ------------------------------------------------------------------------------------------------------

local function Stats()
	local game, s = db.game, db.game.stats
	ns.Print(("blackjack: %s chips. %s hands: %s won, %s lost, %s pushed, %s blackjacks. Biggest win %s, best "
		.. "streak %s, most chips %s, house chips taken %s."):format(ns.Thousands(game.chips), ns.Thousands(s.hands),
		ns.Thousands(s.wins), ns.Thousands(s.losses), ns.Thousands(s.pushes), ns.Thousands(s.blackjacks),
		ns.Thousands(s.biggestWin), ns.Thousands(s.bestStreak), ns.Thousands(s.peak), ns.Thousands(s.refills)))
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

local function StartOver()
	db.game = ns.Blackjack_NewGame()
	ns.BlackjackTable_Refresh()
	ns.Print(("blackjack: a fresh %s chips, stats cleared."):format(ns.Thousands(ns.BLACKJACK_START_CHIPS)))
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("BLACKJACK", MODULE_KEY, function()
	forFlight = false
	ns.BlackjackTable_Toggle()
end)
BINDING_NAME_TOMTE_BLACKJACK = "Blackjack table"

module = ns.RegisterModule({
	key = MODULE_KEY,
	name = "Blackjack",
	category = "ambience",
	icon = 134493, -- inv_misc_ticket_tarot_stack_01
	summary = "A blackjack table for play chips, for flights or any time.",
	description = "You against the dealer, for play chips only: 1,000 to start, and the house gives you more if you "
		.. "run out. Six decks, the dealer stands on soft 17, blackjack pays 3:2, double and split. Your chips and "
		.. "stats stay between sessions. Open it with /tomte blackjack or a key binding, or have it open on its own "
		.. "when you take a flight path.",
	enabledByDefault = true,
	defaults = {
		taxi = false,
		closeOnLand = true,
		sounds = true,
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = 60 }, -- ns.BlackjackTable_ResetPlace repeats it
		game = ns.Blackjack_NewGame(), -- chips, bet, shoe, round in play, stats (BlackjackRules.lua)
	},
	keep = { "game" }, -- your chips and stats: a settings reset keeps them, profiles don't carry them
	init = function(saved)
		db = saved
		ns.Blackjack_Repair(db.game)
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
			confirm = "Start over with a fresh 1,000 chips and clear your blackjack stats?" },
		{ type = "header", label = "Flight paths" },
		{ type = "checkbox", key = "taxi", label = "Open on flight paths",
			tooltip = "The table opens when you take a flight path. While it's open, Flight Timer's cinematic doesn't play." },
		{ type = "checkbox", key = "closeOnLand", label = "Close when you land", parent = "taxi",
			tooltip = "Only when it opened for that flight." },
	},
})
