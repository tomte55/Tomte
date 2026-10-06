-- Run from the AddOns folder: lua Tomte/tests/test_recap.lua
local ns = {}
assert(loadfile("Tomte/Core/SessionData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Moments/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Recap/Data.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local BASE = { money = 1000, level = 80, xpFraction = 0.5 }

---------------------------------------------------------------------------------------------------------------
-- Session

test("WarbandMoved keeps the net through a deposit and a withdrawal", function()
	local s = ns.Session_New("Player-1", 100, BASE)
	s.moneyNow = 1500 -- earned 500
	s.moneyNow = s.moneyNow - 1200 -- deposit 1200
	ns.Session_WarbandMoved(s, 1200)
	eq(s.moneyNow - s.money, 500, "after deposit")
	s.moneyNow = s.moneyNow + 300 -- withdraw 300
	ns.Session_WarbandMoved(s, -300)
	eq(s.moneyNow - s.money, 500, "after withdrawal")
end)

test("Begin starts a session on a fresh db", function()
	local db = {}
	local s, new = ns.Session_Begin(db, "Player-1", true, 100, BASE)
	eq(new, true)
	eq(db.session, s)
	eq(s.guid, "Player-1")
	eq(s.start, 100)
	eq(s.money, 1000)
	eq(s.moneyNow, 1000)
	eq(s.levelNow, 80)
	eq(type(s.gold["in"]), "table")
	eq(#s.log, 0)
end)

test("Begin keeps the session across a reload", function()
	local db = {}
	local s = ns.Session_Begin(db, "Player-1", true, 100, BASE)
	s.log[1] = { kind = "rare" }
	local again, new = ns.Session_Begin(db, "Player-1", false, 500, { money = 5, level = 81, xpFraction = 0 })
	eq(new, false)
	eq(again, s)
	eq(again.start, 100)
	eq(again.money, 1000)
	eq(#again.log, 1)
end)

test("Begin on a new login moves the old session to sessionLast", function()
	local db = {}
	local s = ns.Session_Begin(db, "Player-1", true, 100, BASE)
	s.seen = 200
	local fresh = ns.Session_Begin(db, "Player-1", true, 900, BASE)
	eq(db.sessionLast["Player-1"], s)
	eq(fresh.start, 900)
	eq(db.session, fresh)
end)

test("Begin for another character rolls the old one over under its own GUID", function()
	local db = {}
	local alice = ns.Session_Begin(db, "Player-A", true, 100, BASE)
	local bob = ns.Session_Begin(db, "Player-B", false, 300, BASE)
	eq(db.sessionLast["Player-A"], alice)
	eq(db.sessionLast["Player-B"], nil)
	eq(bob.guid, "Player-B")
end)

test("Begin fills tables missing from an old (AFK) session", function()
	local db = { session = { guid = "Player-1", start = 50, money = 10, level = 70, xpFraction = 0.1 } }
	local s, new = ns.Session_Begin(db, "Player-1", false, 100, BASE)
	eq(new, false)
	eq(s.start, 50)
	eq(type(s.log), "table")
	eq(type(s.gold.out), "table")
	eq(type(s.rares), "table")
	eq(s.moneyNow, 10)
end)

test("Migrate moves afk.session to session", function()
	local old = { guid = "Player-1", start = 1 }
	local db = { afk = { session = old, orbit = true } }
	ns.Session_Migrate(db)
	eq(db.session, old)
	eq(db.afk.session, nil)
	eq(db.afk.orbit, true)
end)

test("Migrate keeps an existing session and drops the AFK copy", function()
	local cur = { guid = "Player-1" }
	local db = { session = cur, afk = { session = { guid = "Player-1" } } }
	ns.Session_Migrate(db)
	eq(db.session, cur)
	eq(db.afk.session, nil)
	ns.Session_Migrate({}) -- nothing to do, no error
end)

---------------------------------------------------------------------------------------------------------------
-- Notes

test("AddNote appends entries", function()
	local log = {}
	eq(ns.Recap_AddNote(log, { kind = "achievement", title = "A" }, 40), true)
	eq(#log, 1)
end)

test("AddNote collapses renown per faction", function()
	local log = {}
	ns.Recap_AddNote(log, { kind = "renown", factionID = 7, from = 11, to = 12, at = 1 }, 40)
	ns.Recap_AddNote(log, { kind = "renown", factionID = 7, from = 12, to = 13, at = 2 }, 40)
	ns.Recap_AddNote(log, { kind = "renown", factionID = 8, from = 1, to = 2, at = 3 }, 40)
	eq(#log, 2)
	eq(log[1].from, 11)
	eq(log[1].to, 13)
	eq(log[1].at, 2)
end)

test("AddNote counts a rare once per GUID", function()
	local log = {}
	eq(ns.Recap_AddNote(log, { kind = "rare", guid = "Creature-1", title = "X" }, 40), true)
	eq(ns.Recap_AddNote(log, { kind = "rare", guid = "Creature-1", title = "X" }, 40), false)
	eq(ns.Recap_AddNote(log, { kind = "rare", guid = "Creature-2", title = "Y" }, 40), true)
	eq(#log, 2)
end)

test("AddNote: loot after its upgrade note is ignored", function()
	local log = {}
	ns.Recap_AddNote(log, { kind = "upgrade", itemID = 5, at = 100 }, 40)
	eq(ns.Recap_AddNote(log, { kind = "loot", itemID = 5, at = 101 }, 40), false)
	eq(#log, 1)
end)

test("AddNote: an upgrade replaces the loot note of the same item", function()
	local log = {}
	ns.Recap_AddNote(log, { kind = "loot", itemID = 5, at = 100, title = "Helm" }, 40)
	eq(ns.Recap_AddNote(log, { kind = "upgrade", itemID = 5, at = 102, title = "Helm" }, 40), true)
	eq(#log, 1)
	eq(log[1].kind, "upgrade")
end)

test("AddNote: the same item much later is a new note", function()
	local log = {}
	ns.Recap_AddNote(log, { kind = "upgrade", itemID = 5, at = 100 }, 40)
	ns.Recap_AddNote(log, { kind = "loot", itemID = 5, at = 1000 }, 40)
	eq(#log, 2)
end)

test("AddNote drops the oldest past the cap", function()
	local log = {}
	for i = 1, 5 do
		ns.Recap_AddNote(log, { kind = "achievement", title = tostring(i) }, 3)
	end
	eq(#log, 3)
	eq(log[1].title, "3")
	eq(log.dropped, 2)
end)

---------------------------------------------------------------------------------------------------------------
-- Gold

test("MoneySource follows loot > auction > mail > vendor", function()
	eq(ns.Recap_MoneySource({}), nil)
	eq(ns.Recap_MoneySource({ vendor = true }), "vendor")
	eq(ns.Recap_MoneySource({ vendor = true, mail = true }), "mail")
	eq(ns.Recap_MoneySource({ mail = true, auction = true }), "auction")
	eq(ns.Recap_MoneySource({ auction = true, loot = true }), "loot")
end)

test("GoldAttribute books in and out per source", function()
	local gold = { ["in"] = {}, out = {} }
	ns.Recap_GoldAttribute(gold, 500, "vendor")
	ns.Recap_GoldAttribute(gold, -200, "vendor")
	ns.Recap_GoldAttribute(gold, 300, "loot")
	ns.Recap_GoldAttribute(gold, 999, nil) -- unknown: left to "other"
	ns.Recap_GoldAttribute(gold, 0, "loot")
	eq(gold["in"].vendor, 500)
	eq(gold.out.vendor, 200)
	eq(gold["in"].loot, 300)
end)

test("GoldSources gives net per source with other as the remainder", function()
	local gold = { ["in"] = { vendor = 500, loot = 300 }, out = { vendor = 200, auction = 1000 } }
	local list = ns.Recap_GoldSources(gold, 0)
	-- vendor +300, loot +300, auction -1000, other = 0 - (-400) = +400
	eq(#list, 4)
	eq(list[1].source, "auction")
	eq(list[1].amount, -1000)
	eq(list[2].source, "other")
	eq(list[2].amount, 400)
	eq(list[3].source, "loot") -- ties keep the source order
	eq(list[4].source, "vendor")
end)

test("GoldSources drops zero entries", function()
	local list = ns.Recap_GoldSources({ ["in"] = { loot = 100 }, out = {} }, 100)
	eq(#list, 1)
	eq(list[1].source, "loot")
	eq(#ns.Recap_GoldSources({ ["in"] = {}, out = {} }, 0), 0)
end)

---------------------------------------------------------------------------------------------------------------
-- Summary

test("Duration", function()
	eq(ns.Recap_Duration(30), "<1m")
	eq(ns.Recap_Duration(14 * 60 + 5), "14m")
	eq(ns.Recap_Duration(2 * 3600 + 14 * 60), "2h 14m")
	eq(ns.Recap_Duration(3600), "1h 0m")
end)

test("Counts per kind, items and renown levels", function()
	local c = ns.Recap_Counts({
		{ kind = "loot" }, { kind = "upgrade" }, { kind = "rare" }, { kind = "rare" },
		{ kind = "renown", from = 3, to = 5 }, { kind = "renown", from = 1, to = 2 },
	})
	eq(c.loot, 1)
	eq(c.rare, 2)
	eq(c.items, 2)
	eq(c.renownLevels, 3)
	eq(c.mount or 0, 0)
end)

test("CountsLine in order with plurals", function()
	local c = ns.Recap_Counts({ { kind = "achievement" }, { kind = "achievement" }, { kind = "rare" },
		{ kind = "tame" }, { kind = "mount" }, { kind = "loot" }, { kind = "renown", from = 1, to = 3 } })
	eq(ns.Recap_CountsLine(c), "2 achievements · 1 rare · 1 tame · 1 mount · 1 item · +2 renown")
	eq(ns.Recap_CountsLine(ns.Recap_Counts({})), "")
end)

local function Money(copper)
	return math.floor(copper / 10000) .. "g"
end

test("SummaryLine with and without gold", function()
	local c = ns.Recap_Counts({ { kind = "rare" } })
	eq(ns.Recap_SummaryLine({ duration = 8040, net = 34200000, counts = c }, Money), "2h 14m · +3420g · 1 rare")
	eq(ns.Recap_SummaryLine({ duration = 600, net = -20000, counts = ns.Recap_Counts({}) }, Money), "10m · -2g")
	eq(ns.Recap_SummaryLine({ duration = 600, net = 0, counts = ns.Recap_Counts({}) }, Money), "10m")
end)

test("Worth needs 10 minutes and something to show", function()
	eq(ns.Recap_Worth({ duration = 300, net = 1000000, entries = 3 }), false)
	eq(ns.Recap_Worth({ duration = 900, net = 0, entries = 0 }), false)
	eq(ns.Recap_Worth({ duration = 900, net = 9999, entries = 0 }), false)
	eq(ns.Recap_Worth({ duration = 900, net = -10000, entries = 0 }), true)
	eq(ns.Recap_Worth({ duration = 900, net = 0, entries = 1 }), true)
	eq(ns.Recap_Worth({ duration = 900, net = 0, entries = 0, xp = true }), true)
end)

test("Highlights rank legendary, mount, epic, achievement, rare, ...", function()
	local log = {
		{ kind = "loot", quality = 3, title = "blue", at = 1 },
		{ kind = "rare", title = "rare", at = 2 },
		{ kind = "achievement", title = "ach", at = 3 },
		{ kind = "loot", quality = 4, title = "epic", at = 4 },
		{ kind = "mount", title = "mount", at = 5 },
		{ kind = "loot", quality = 5, title = "legendary", at = 6 },
		{ kind = "renown", title = "renown", at = 7 },
		{ kind = "tame", title = "tame", at = 8 },
	}
	local shown, more = ns.Recap_Highlights(log, 6)
	eq(#shown, 6)
	eq(more, 2)
	eq(shown[1].title, "legendary")
	eq(shown[2].title, "mount")
	eq(shown[3].title, "epic")
	eq(shown[4].title, "ach")
	eq(shown[5].title, "rare")
	eq(shown[6].title, "tame")
end)

test("Highlights: newer first within a rank, upgrades rank with epics", function()
	local shown = ns.Recap_Highlights({
		{ kind = "achievement", title = "old", at = 1 },
		{ kind = "achievement", title = "new", at = 5 },
		{ kind = "upgrade", quality = 3, title = "upg", at = 2 },
	}, 6)
	eq(shown[1].title, "upg")
	eq(shown[2].title, "new")
	eq(shown[3].title, "old")
end)

test("Highlights counts dropped entries as more", function()
	local log = { { kind = "rare", at = 1 } }
	log.dropped = 4
	local shown, more = ns.Recap_Highlights(log, 6)
	eq(#shown, 1)
	eq(more, 4)
end)

test("RowLabel", function()
	eq(ns.Recap_RowLabel({ kind = "loot", quality = 5 }), "Legendary")
	eq(ns.Recap_RowLabel({ kind = "loot", quality = 4 }), "Epic")
	eq(ns.Recap_RowLabel({ kind = "upgrade" }), "Upgrade")
	eq(ns.Recap_RowLabel({ kind = "rare" }), "Rare killed")
	eq(ns.Recap_RowLabel({ kind = "renown", from = 3, to = 5 }), "Renown 5 (+2)")
end)

---------------------------------------------------------------------------------------------------------------
-- Detection helpers

test("IsRareVignette", function()
	eq(ns.Recap_IsRareVignette("VignetteKill", "Creature-0-1-2-3-4-5"), true)
	eq(ns.Recap_IsRareVignette("VignetteKillElite", "Vehicle-0-1-2-3-4-5"), true)
	eq(ns.Recap_IsRareVignette("VignetteEvent", "Creature-0-1-2-3-4-5"), false)
	eq(ns.Recap_IsRareVignette("VignetteKill", "GameObject-0-1"), false)
	eq(ns.Recap_IsRareVignette(nil, "Creature-1"), false)
	eq(ns.Recap_IsRareVignette("VignetteKill", nil), false)
end)

test("LootLink matches self loot messages only", function()
	local patterns = ns.Recap_LootPatterns({ "You receive loot: %s.", "You receive loot: %sx%d.", "You receive item: %s." })
	local link = "|cnIQ4:|Hitem:19019::::::::80:::::|h[Thunderfury]|h|r"
	eq(ns.Recap_LootLink("You receive loot: " .. link .. ".", patterns), link)
	eq(ns.Recap_LootLink("You receive loot: " .. link .. "x2.", patterns), link)
	eq(select(2, ns.Recap_LootLink("You receive loot: " .. link .. "x2.", patterns)), 2, "count")
	eq(select(2, ns.Recap_LootLink("You receive loot: " .. link .. ".", patterns)), 1, "count 1")
	eq(ns.Recap_LootLink("You receive item: " .. link .. ".", patterns), link)
	eq(ns.Recap_LootLink("Thrall receives loot: " .. link .. ".", patterns), nil)
	eq(ns.Recap_LootLink(nil, patterns), nil)
	local old = "|cffa335ee|Hitem:19019::::::::80:::::|h[Thunderfury]|h|r"
	eq(ns.Recap_LootLink("You receive loot: " .. old .. ".", patterns), old)
end)

test("ItemID from a link", function()
	eq(ns.Recap_ItemID("|cnIQ4:|Hitem:19019::::|h[x]|h|r"), 19019)
	eq(ns.Recap_ItemID("nope"), nil)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
