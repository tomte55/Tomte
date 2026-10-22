-- Run from the AddOns folder: lua Tomte/tests/test_migrations.lua
local ns = { errorHandler = function(err) print("migration error: " .. tostring(err)) end }
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Setup.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/SessionData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Moments/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Migrations.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("an empty db runs every migration without error", function()
	local db = {}
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.schema, #ns.MIGRATIONS)
end)
test("the AFK module's old session moves to db.session", function()
	local db = { schema = 3, afk = { session = { start = 5 } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.session.start, 5)
	eq(db.afk.session, nil)
end)
test("NextUp: old default column becomes characters, the flag goes", function()
	local db = { schema = 3, next = { placement = "column" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.next.placement, "characters")
	eq(db.next.placedUnderChars, nil)
end)
test("NextUp: a column picked after the old fix stays", function()
	local db = { schema = 3, next = { placement = "column", placedUnderChars = true } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.next.placement, "column")
	eq(db.next.placedUnderChars, nil)
end)
test("Waypoints: the old 325 card distance becomes 110, others stay", function()
	local db = { schema = 3, way = { cardDistance = 325 } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.way.cardDistance, 110)
	local db2 = { schema = 3, way = { cardDistance = 200 } }
	ns.RunMigrations(db2, ns.MIGRATIONS)
	eq(db2.way.cardDistance, 200)
end)
test("Almost Done: a cache with records lacking topID is dropped, a current one kept", function()
	local db = { schema = 3, ach = { cache = {
		old = { records = { { id = 1, category = 92 } } },
		new = { records = { { id = 2, category = 92, topID = 92 } } },
	} } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.ach.cache.old, nil)
	eq(db.ach.cache.new.records[1].topID, 92)
end)
test("Flight: paces without a flight count get one", function()
	local db = { schema = 3, flight = { paces = { [12] = { seconds = 1000, distance = 10 } } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.flight.paces[12].flights, 9)
	eq(db.flight.paces[12].seconds, 1000)
end)
test("Settings: the sidebar's collapsed categories are dropped, the rest of the panel kept", function()
	local db = { schema = 8, panel = { collapsed = { General = true }, selected = "alts" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.panel.collapsed, nil)
	eq(db.panel.selected, "alts")
	local bare = { schema = 8 }
	ns.RunMigrations(bare, ns.MIGRATIONS)
	eq(bare.panel, nil, "no panel table is fine")
end)
test("Delves: an unticked Delves in Around you moves to the window's Around you shows", function()
	local db = { schema = 9, delves = { around = false, entrance = true }, window = { around = { wqaround = false } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.delves.around, nil)
	eq(db.delves.entrance, true, "other Delves settings kept")
	eq(db.window.around.delvesaround, false)
	eq(db.window.around.wqaround, false, "other blocks kept")
	local on = { schema = 9, delves = { around = true } }
	ns.RunMigrations(on, ns.MIGRATIONS)
	eq(on.delves.around, nil)
	eq(on.window, nil, "ticked: nothing to move")
	local noWindow = { schema = 9, delves = { around = false } }
	ns.RunMigrations(noWindow, ns.MIGRATIONS)
	eq(noWindow.window.around.delvesaround, false, "window tables made")
	local bare = { schema = 9 }
	ns.RunMigrations(bare, ns.MIGRATIONS)
	eq(bare.delves, nil, "no delves table is fine")
end)
local NEW_DEFAULTS = 11 -- index of "new defaults are for new installs" in ns.MIGRATIONS

test("New defaults: an existing install keeps Friend sharing on and Group Alerts on Master", function()
	local db = { schema = NEW_DEFAULTS - 1, enabled = {}, alerts = { sound = "bell", repeats = 3 },
		mentions = { flash = true, sound = "chime" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled.share, true, "share pinned on")
	eq(db.alerts.channel, "Master", "alerts stay on Master")
	eq(db.alerts.repeats, 3, "saved repeats untouched")
	eq(db.mentions.flash, true, "saved flash untouched")
end)
test("New defaults: the player's own choices stay", function()
	local db = { schema = NEW_DEFAULTS - 1, enabled = { share = false }, alerts = { channel = "SFX" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled.share, false, "share off stays off")
	eq(db.alerts.channel, "SFX", "chosen channel stays")
end)
test("New defaults: a fresh install gets them, nothing pinned", function()
	local db = {}
	ns.Setup_MarkFresh(db)
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled, nil, "no enabled table before Core merges its defaults")
	eq(db.alerts, nil, "no alerts table made")
	local old = { schema = NEW_DEFAULTS - 1, enabled = {} }
	ns.RunMigrations(old, ns.MIGRATIONS)
	eq(old.alerts, nil, "an install from before Group Alerts gets the new defaults")
end)
test("migrations don't run twice", function()
	local db = { schema = #ns.MIGRATIONS, way = { cardDistance = 325 } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.way.cardDistance, 325)
end)

test("Minimap Buttons: the old single angle moves to Tomte's button, shown", function()
	local db = { schema = 11, minimap = { angle = 200 } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.minimap.buttons.minimap.angle, 200)
	eq(db.minimap.buttons.minimap.shown, true)
	eq(db.minimap.angle, nil)
end)
test("Minimap Buttons: a button already placed keeps its spot", function()
	local db = { schema = 11, minimap = { angle = 200, buttons = { minimap = { shown = false, angle = 90 } } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.minimap.buttons.minimap.angle, 90)
	eq(db.minimap.buttons.minimap.shown, false)
	eq(db.minimap.angle, nil)
end)

test("Casino: Blackjack's saved data, on/off and Recent checkbox move to the casino key", function()
	local game = { chips = 4321 }
	local db = { schema = 12, blackjack = { game = game, taxi = true }, enabled = { blackjack = false },
		recent = { include = { blackjack = false } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.blackjack, nil)
	eq(db.casino.game, game)
	eq(db.casino.taxi, true)
	eq(db.enabled.casino, false)
	eq(db.enabled.blackjack, nil)
	eq(db.recent.include.casino, false)
end)
test("Casino: nothing to move on an install without Blackjack", function()
	local db = { schema = 12 }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.casino, nil)
	eq(db.enabled, nil)
end)

H.done()
