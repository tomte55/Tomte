-- Run from the AddOns folder: lua Tomte/tests/test_weekly.lua
date = os.date
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/WarWithin/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Weekly/Data.lua"))("Tomte", ns)

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

local WEEK = 7 * 86400
local NOW = 1800000000
local MINING, ALCHEMY = 2916, 2906

local function Snap(over)
	local s = {
		guid = "Player-1", name = "Main", class = "HUNTER", at = NOW - 3600, nextReset = NOW + 86400,
		vault = {
			raid = { { progress = 3, threshold = 2, ilvl = 680 }, { progress = 3, threshold = 4, ilvl = 690 }, { progress = 3, threshold = 6 } },
			dungeons = { { progress = 0, threshold = 1 }, { progress = 0, threshold = 4 }, { progress = 0, threshold = 8 } },
			world = {},
		},
		vaultReady = false,
		currencies = { [3445] = { name = "Hero Mistcrest", qty = 300, earnedWeek = 90, weeklyCap = 0, total = 340, seasonCap = 400, useTotal = true } },
		quests = { [100] = "done", [101] = "log" },
		renown = { [2600] = { name = "Silvermoon Court", level = 12, max = 20, earned = 1250, threshold = 2500 } },
		lockouts = {
			{ name = "Voidspire", difficulty = "Heroic", killed = 4, total = 8, expires = NOW + 86400 },
			{ name = "Old Raid", difficulty = "Normal", killed = 8, total = 8, expires = NOW - 1 },
		},
		profs = {
			[MINING] = { name = "Mining", base = 186, knowledge = { [93705] = true, [95135] = true, [88673] = true } },
			[ALCHEMY] = { name = "Alchemy", base = 171, knowledge = {},
				conc = { qty = 500, max = 1000, cycleMS = 360000, perCycle = 1, at = NOW - 3600 } },
		},
	}
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end

local LEARNED = { [100] = { title = "Delve weekly" }, [101] = { title = "World boss" }, [102] = { title = "Unseen" } }

test("view: fresh snapshot keeps weekly progress", function()
	local v = ns.Weekly_View(Snap(), NOW)
	eq(v.stale, false, "stale")
	eq(v.vault.raid[1].progress, 3, "progress")
	eq(v.vault.raid[2].ilvl, 690, "ilvl")
	eq(v.quests[100], "done", "quest")
	eq(v.currencies[3445].earnedWeek, 90, "earned")
	eq(v.vaultReady, false, "vault ready")
end)

test("view: after the reset weekly progress is reset and the vault waits", function()
	local v = ns.Weekly_View(Snap(), NOW + 86400)
	eq(v.stale, true, "stale")
	eq(v.vault.raid[1].progress, 0, "progress")
	eq(v.vault.raid[1].ilvl, nil, "ilvl")
	eq(v.quests[100], nil, "done quest gone")
	eq(v.quests[101], "log", "quest in log stays")
	eq(v.currencies[3445].earnedWeek, 0, "earned")
	eq(v.currencies[3445].total, 340, "season total stays")
	eq(v.vaultReady, true, "vault ready")
	eq(v.renown[2600].level, 12, "renown stays")
	eq(v.profs[MINING].knowledge[93705], nil, "knowledge reset")
end)

test("view: several weeks stale is still just reset", function()
	local v = ns.Weekly_View(Snap(), NOW + 3 * WEEK)
	eq(v.stale, true)
	eq(v.vaultReady, true)
	eq(#v.lockouts, 0, "all lockouts expired")
end)

test("view: unknown reset time is not stale", function()
	local s = Snap()
	s.nextReset = nil
	eq(ns.Weekly_View(s, NOW + 3 * WEEK).stale, false)
end)

test("view: no vault waiting after a reset when nothing was unlocked", function()
	local s = Snap()
	s.vault.raid = { { progress = 1, threshold = 2 } }
	eq(ns.Weekly_View(s, NOW + 86400).vaultReady, false)
	s.vaultReady = true
	eq(ns.Weekly_View(s, NOW).vaultReady, true, "reported ready")
end)

test("view: lockouts drop at their own expiry (extended ones live on)", function()
	local s = Snap()
	s.lockouts[3] = { name = "Extended", killed = 2, total = 8, expires = NOW + 2 * WEEK }
	local v = ns.Weekly_View(s, NOW + 2 * 86400)
	eq(#v.lockouts, 1, "count")
	eq(v.lockouts[1].name, "Extended")
	eq(#ns.Weekly_View(s, NOW).lockouts, 2, "expired one is gone now")
end)

test("conc: prediction, cap and full time", function()
	local conc = { qty = 500, max = 1000, cycleMS = 360000, perCycle = 1, at = NOW }
	local qty, fullAt = ns.Weekly_ConcNow(conc, NOW)
	eq(qty, 500)
	eq(fullAt, NOW + 500 * 360)
	eq(ns.Weekly_ConcNow(conc, NOW + 3600), 510, "10 per hour")
	eq(ns.Weekly_ConcNow(conc, NOW + 359), 500, "not a full cycle yet")
	eq(ns.Weekly_ConcNow(conc, NOW + 10 * 86400), 1000, "capped")
	local full = { qty = 1000, max = 1000, cycleMS = 360000, perCycle = 1, at = NOW - 50 }
	local q2, f2 = ns.Weekly_ConcNow(full, NOW)
	eq(q2, 1000)
	eq(f2, NOW - 50, "full since the reading")
	local noRate = { qty = 700, max = 1000, at = NOW }
	local q3, f3 = ns.Weekly_ConcNow(noRate, NOW + 86400)
	eq(q3, 700, "no rate, no prediction")
	eq(f3, nil)
	eq(ns.Weekly_ConcNow(nil, NOW), nil)
end)

test("conc: toast once per fill", function()
	local chars = { ["Player-1"] = Snap() }
	local conc = chars["Player-1"].profs[ALCHEMY].conc
	local fullAt = conc.at + 500 * 360
	eq(#ns.Weekly_DueConc(chars, fullAt - 1), 0, "not yet")
	eq(ns.Weekly_NextConcFull(chars, NOW), fullAt, "timer target")
	local due = ns.Weekly_DueConc(chars, fullAt)
	eq(#due, 1, "due")
	eq(due[1].skillLine, ALCHEMY)
	conc.notified = true
	eq(#ns.Weekly_DueConc(chars, fullAt + 100), 0, "toasted")
	eq(ns.Weekly_NextConcFull(chars, NOW), nil, "no timer")
	-- A new full reading keeps the mark; one below max clears it.
	local again = ns.Weekly_MergeConc(conc, { qty = 1000, max = 1000, at = fullAt + 200 })
	eq(again.notified, true, "still full")
	local spent = ns.Weekly_MergeConc(again, { qty = 400, max = 1000, at = fullAt + 300 })
	eq(spent.notified, nil, "spent")
end)

test("vault: next goal at every threshold", function()
	local function Slots(p)
		return { { progress = p, threshold = 2 }, { progress = p, threshold = 4 }, { progress = p, threshold = 6 } }
	end
	eq((ns.Weekly_VaultText(Slots(0))), "0/2 to slot 1")
	eq((ns.Weekly_VaultText(Slots(2))), "2/4 to slot 2")
	eq((ns.Weekly_VaultText(Slots(5))), "5/6 to slot 3")
	local text, unlocked, n = ns.Weekly_VaultText(Slots(6))
	eq(text, "all slots open")
	eq(unlocked, 3)
	eq(n, 3)
	local s = Slots(4)
	s[1].ilvl, s[2].ilvl = 680, 690
	eq((ns.Weekly_VaultText(s)), "4/6 to slot 3 · ilvl 690", "best ilvl")
end)

test("currency: season, weekly and plain caps", function()
	local a, b = ns.Weekly_CurrencyProgress({ qty = 10, total = 340, seasonCap = 400, useTotal = true })
	eq(a, 340)
	eq(b, 400)
	a, b = ns.Weekly_CurrencyProgress({ qty = 10, earnedWeek = 50, weeklyCap = 90 })
	eq(a, 50)
	eq(b, 90)
	a, b = ns.Weekly_CurrencyProgress({ qty = 10 })
	eq(a, 10)
	eq(b, nil)
end)

test("knowledge: gathering and crafting sources", function()
	local mining = ns.Weekly_Knowledge(ns.Content_Get(11, "profs")[186], { [93707] = true, [88673] = true, [88674] = true })
	eq(#mining, 4, "trainer, treatise, drops, big drop")
	eq(mining[1].n, 1, "any trainer quest counts")
	eq(mining[3].n, 2, "drops")
	eq(mining[3].of, 5)
	local alch = ns.Weekly_Knowledge(ns.Content_Get(11, "profs")[171], { [93528] = true })
	eq(alch[3].label, "Treasures")
	eq(alch[3].n, 1)
	eq(ns.Weekly_IsProfQuest(95135), true)
	eq(ns.Weekly_IsProfQuest(100), false)
end)

test("knowledge: every quest ID is checked, also without treasures", function()
	local ids = ns.Weekly_ProfQuestIDs(ns.Content_Get(11, "profs")[182])
	eq(#ids, 5 + 5 + 2, "trainer, drops, treatise, big drop")
	local seen = {}
	for _, id in ipairs(ids) do
		seen[id] = true
	end
	eq(seen[81425] and seen[81429] and seen[81430] and seen[95130] and seen[93704], true)
	eq(#ns.Weekly_ProfQuestIDs(ns.Content_Get(11, "profs")[171]), 1 + 2 + 1, "alchemy: trainer, treasures, treatise")
	eq(#ns.Weekly_ProfQuestIDs(ns.Content_Get(11, "profs")[333]), 3 + 2 + 5 + 2, "enchanting has both")
	eq(ns.Weekly_IsProfQuest(81427), true, "drops are not learned as weekly quests")
end)

test("snapshot expansion: stored, else the level's content expansion, else The War Within", function()
	eq(ns.Weekly_SnapExpansion({ expansion = 11, level = 80 }), 11, "stored wins")
	eq(ns.Weekly_SnapExpansion({}), 10, "nothing known: War Within")
	local saved = ns.ContentExpansion
	ns.ContentExpansion = function(level)
		return level >= 81 and 11 or 10
	end
	eq(ns.Weekly_SnapExpansion({ level = 90 }), 11, "old Midnight snapshot")
	eq(ns.Weekly_SnapExpansion({ level = 80 }), 10, "old War Within snapshot")
	ns.ContentExpansion = saved
	eq(ns.Weekly_View(Snap({ expansion = 11 }), NOW).expansion, 11, "view carries it")
	eq(ns.Weekly_View(Snap(), NOW).expansion, 10, "view of an old snapshot")
end)

test("crest sets: the first one the character has, else the newest", function()
	local sets = ns.Content_Get(11, "crests")
	local function Has(list)
		return function(id)
			return list[id] == true
		end
	end
	eq(ns.Weekly_PickCrestSet(sets, Has({})).label, "Mistcrests", "none: newest")
	eq(ns.Weekly_PickCrestSet(sets, Has({ [3345] = true })).label, "Dawncrests", "only last season's")
	eq(ns.Weekly_PickCrestSet(sets, Has({ [3345] = true, [3442] = true })).label, "Mistcrests", "both: newest")
	eq(ns.Weekly_PickCrestSet(nil, Has({})), nil, "no sets")
	eq(ns.Content_Get(10, "crests")[1].ids[4], 3290, "War Within: Gilded Ethereal")
end)

test("crest IDs of a view: stored set, else the expansion's set it has, else what it stored", function()
	local v = ns.Weekly_View(Snap({ crests = { 3442, 3443 } }), NOW)
	eq(table.concat(ns.Weekly_CrestIDs(v), ","), "3442,3443", "stored")
	v = ns.Weekly_View(Snap({ expansion = 11 }), NOW) -- old snapshot holding a Hero Mistcrest
	eq(table.concat(ns.Weekly_CrestIDs(v), ","), "3442,3443,3444,3445,3446", "Midnight set it has")
	v = ns.Weekly_View(Snap(), NOW) -- War Within, holding a Mistcrest (old data): what it stored
	eq(table.concat(ns.Weekly_CrestIDs(v), ","), "3445", "stored currencies")
	v = ns.Weekly_View(Snap({ crests = {}, currencies = {} }), NOW)
	eq(ns.Weekly_BoardModel(v, {}, NOW, false).progress[1].text, "Lockouts", "no crests, no section")
end)

test("grid: crests of every character", function()
	local a = Snap({ crests = { 3284 }, currencies = { [3284] = { name = "Weathered Ethereal Crest", qty = 5 } } })
	local b = Snap({ guid = "Player-2", crests = { 3442 }, currencies = { [3442] = { name = "Adventurer Mistcrest", qty = 7 } } })
	local labels = {}
	for _, row in ipairs(ns.Weekly_GridModel({ ns.Weekly_View(a, NOW), ns.Weekly_View(b, NOW) }, {}, NOW).rows) do
		labels[#labels + 1] = row.label or ("#" .. row.header)
	end
	local text = table.concat(labels, "|")
	eq(text:find("Weathered Ethereal Crest", 1, true) ~= nil and text:find("Adventurer Mistcrest", 1, true) ~= nil, true,
		text)
end)

test("no data text", function()
	eq(ns.Weekly_NoDataText("raids", 11), "No raids data for Midnight yet.")
	eq(ns.Weekly_NoDataText("activities", 12), "No activities data for expansion 12 yet.")
end)

test("profession data per expansion", function()
	eq(ns.Weekly_ProfDef(10, 186).child, 2881, "Khaz Algar Mining")
	eq(ns.Weekly_ProfDef(nil, 186).child, 2916, "old snapshots are Midnight")
	eq(ns.Weekly_IsProfQuest(83733), true, "War Within treatise")
end)

test("view: War Within professions use their own sources", function()
	local s = Snap()
	s.profs = { [2881] = { name = "Mining", base = 186, expansion = 10, knowledge = { [83102] = true, [83050] = true } } }
	local items = ns.Weekly_ProfModel({ ns.Weekly_View(s, NOW) }, NOW)
	local trainer, drops
	for _, item in ipairs(items) do
		if item.left == "Trainer quest" then trainer = item end
		if item.left == "Weekly drops" then drops = item end
	end
	eq(trainer.right, "done")
	eq(drops.right, "1/5 · 1 pt each")
	eq(trainer.loc.map, 2339, "Dornogal")
	eq(trainer.loc.x, 52.6)
	eq(items[2].right, "8 pts of knowledge left this week", "treatise 1 + 4 drops + big drop 3")
end)

test("quests: only learned ones in the log or done, by title", function()
	local list = ns.Weekly_Quests(ns.Weekly_View(Snap(), NOW), LEARNED)
	eq(#list, 2)
	eq(list[1].title, "Delve weekly")
	eq(list[1].done, true)
	eq(list[2].done, false)
end)

local function Find(items, left)
	for _, item in ipairs(items) do
		if item.left == left then
			return item
		end
	end
end

test("popup: lists only open items", function()
	local items = ns.Weekly_OpenModel(ns.Weekly_View(Snap(), NOW), LEARNED, NOW, true)
	eq(Find(items, "Vault: Raid").right, "3/4 to slot 2 · ilvl 680")
	eq(Find(items, "Vault: Dungeons").right, "0/1 to slot 1")
	eq(Find(items, "Hero Mistcrest").right, "340 / 400")
	eq(Find(items, "World boss").state, "open")
	eq(Find(items, "Delve weekly"), nil, "done quest left out")
	eq(Find(items, "Mining: Trainer quest"), nil, "done source left out")
	eq(Find(items, "Mining: Weekly drops").right, "1/5 · 1 pt each")
	eq(Find(items, "Alchemy: Treatise").right, "open · 1 pt")
	eq(Find(items, "Alchemy: Treatise").tip:find("Thalassian Treatise on Alchemy", 1, true) ~= nil, true, "hint")
	eq(Find(items, "Alchemy: Trainer quest").loc.text, "the Artisan's Consortium")
	eq(Find(items, "Alchemy: Concentration"), nil, "not full")
	eq(Find(items, "World boss") ~= nil, true)
	eq(#ns.Weekly_OpenModel(ns.Weekly_View(Snap(), NOW), LEARNED, NOW, false) < #items, true, "learned hidden")
end)

test("popup: all done is empty, full concentration shows", function()
	local s = Snap()
	s.vault = { raid = { { progress = 2, threshold = 2 } } }
	s.currencies = { [3445] = { name = "Hero Mistcrest", total = 400, seasonCap = 400, useTotal = true } }
	s.quests = { [100] = "done" }
	s.profs = {}
	eq(#ns.Weekly_OpenModel(ns.Weekly_View(s, NOW), LEARNED, NOW, true), 0, "all done")
	s.profs = { [ALCHEMY] = { name = "Alchemy", base = 171,
		knowledge = { [93690] = true, [95127] = true, [93528] = true, [93529] = true },
		conc = { qty = 1000, max = 1000, at = NOW } } }
	local items = ns.Weekly_OpenModel(ns.Weekly_View(s, NOW), LEARNED, NOW, true)
	eq(#items, 1)
	eq(items[1].left, "Alchemy: Concentration")
	eq(items[1].state, "warn")
end)

local function Headers(items)
	local headers = {}
	for _, item in ipairs(items) do
		if item.kind == "header" then
			headers[#headers + 1] = item.text
		end
	end
	return table.concat(headers, ",")
end

test("board model: vault notes, to do and progress", function()
	local m = ns.Weekly_BoardModel(ns.Weekly_View(Snap(), NOW), LEARNED, NOW, true)
	eq(m.vaultReady, false)
	eq(#m.vault, 2, "world has no slots")
	eq(m.vault[1].note, "1 more boss for slot 2")
	eq(m.vault[1].nextSlot, 2)
	eq(m.vault[2].note, "1 more dungeon for slot 1")
	eq(Headers(m.todo), "Weekly quests,Alchemy,Mining")
	eq(m.todo[2].left, "World boss", "open quests first")
	eq(m.todo[3].left, "Delve weekly")
	eq(m.todo[3].dimLeft, true, "done quest")
	eq(Find(m.todo, "Treatise") ~= nil, true, "Alchemy's treatise is open")
	eq(Find(m.todo, "Trainer quest").indent, true)
	eq(Headers(m.progress), "Crests,Lockouts", "renown is on the Factions tab")
	eq(Find(m.progress, "Silvermoon Court"), nil)
	eq(Find(m.progress, "Voidspire Heroic").right, "4/8 · resets in 1d 0h")
end)

test("board model: after the reset the vault waits and lockouts are gone", function()
	local m = ns.Weekly_BoardModel(ns.Weekly_View(Snap(), NOW + 86400), LEARNED, NOW + 86400, true)
	eq(m.vaultReady, true)
	eq(m.vault[1].note, "2 more bosses for slot 1")
	eq(Headers(m.progress), "Crests", "lockouts expired")
end)

test("board model: a profession with all knowledge", function()
	local s = Snap()
	local def = ns.Weekly_ProfDef(nil, 186)
	local all = {}
	for _, id in ipairs(ns.Weekly_ProfQuestIDs(def)) do
		all[id] = true
	end
	s.profs[MINING].knowledge = all
	local m = ns.Weekly_BoardModel(ns.Weekly_View(s, NOW), LEARNED, NOW, false)
	eq(Headers(m.todo), "Alchemy", "no quests, Mining collapsed")
	eq(Find(m.todo, "Mining").right, "knowledge done")
	eq(Find(m.todo, "Mining").state, "done")
end)

test("reset text", function()
	eq(ns.Weekly_ResetText(nil, NOW), nil)
	eq(ns.Weekly_ResetText(11 * 3600 + 23 * 60, NOW), "Resets in 11h 23m · " .. os.date("%a %H:%M", NOW + 11 * 3600 + 23 * 60))
end)

test("prof model: concentration text and knowledge rows", function()
	local items = ns.Weekly_ProfModel({ ns.Weekly_View(Snap(), NOW) }, NOW)
	eq(items[1].kind, "header")
	eq(items[1].text, "Main")
	eq(items[2].left, "Alchemy", "sorted by name")
	eq(items[2].right, "4 pts of knowledge left this week", "trainer 1, treatise 1, treasures 2 x 1")
	eq(items[3].left, "Concentration")
	eq(items[3].right:find("^510 / 1000 · full ") ~= nil, true, items[3].right)
	eq(items[3].frac, 0.51)
	local mining = Find(items, "Mining")
	eq(mining.right, "7 pts of knowledge left this week", "Midnight mining: 4 drops + big drop 3")
end)

test("grid: rows, union of characters, stale cells dimmed", function()
	local alt = Snap({ guid = "Player-2", name = "Alt", nextReset = NOW - 10, profs = {}, quests = {},
		renown = { [2601] = { name = "Amani", level = 3, max = 20 } } })
	local views = { ns.Weekly_View(Snap(), NOW), ns.Weekly_View(alt, NOW) }
	local grid = ns.Weekly_GridModel(views, LEARNED, NOW)
	local byLabel = {}
	for _, row in ipairs(grid.rows) do
		if row.label then
			byLabel[row.label] = row
		end
	end
	eq(byLabel.Raid.cells[1].text, "1/3")
	eq(byLabel.Raid.cells[2].state, "dim", "alt is stale")
	eq(byLabel.World, nil, "no world slots anywhere")
	eq(byLabel["Weekly quests"].cells[1].text, "1/2")
	eq(byLabel["Weekly quests"].cells[2].text, "", "alt has none")
	eq(byLabel.Amani.cells[1].text, "", "main lacks that faction")
	eq(byLabel.Amani.cells[2].text, "3")
	eq(byLabel["Voidspire Heroic"].cells[1].text, "4/8")
	eq(byLabel.Concentration.cells[1].text, "510", "an hour of recharge")
	for i, row in ipairs(grid.rows) do
		if row.header then
			eq(grid.rows[i + 1] ~= nil and grid.rows[i + 1].header == nil, true, "header " .. row.header .. " has rows")
		end
	end
end)

test("char order: current first, then last seen, hidden left out", function()
	local chars = {
		a = { name = "A", seen = 100 }, b = { name = "B", seen = 300 }, c = { name = "C", seen = 200 }, d = { name = "D", seen = 400 },
	}
	eq(table.concat(ns.Weekly_CharOrder(chars, "a", { d = true }), ","), "a,b,c")
	eq(table.concat(ns.Weekly_CharOrder(chars, "a", { a = true }), ","), "d,b,c")
	eq(table.concat(ns.Weekly_CharOrder(chars, "a", { a = true }, true), ","), "a,d,b,c")
	eq(table.concat(ns.Weekly_CharOrder(chars, "x", {}), ","), "d,b,c,a", "current not tracked")
end)

test("duration", function()
	eq(ns.Weekly_Duration(90061), "1d 1h")
	eq(ns.Weekly_Duration(3720), "1h 2m")
	eq(ns.Weekly_Duration(59), "0m")
	eq(ns.Weekly_Duration(-5), "0m")
end)

test("home summary: vault slots and open knowledge sources", function()
	local v = ns.Weekly_View(Snap(), NOW)
	local text = ns.Weekly_HomeSummary(v)
	assert(text:find("^Vault 1/6"), text)
	assert(text:find("knowledge left"), text)
	v.vaultReady = true
	assert(ns.Weekly_HomeSummary(v):find("^Vault rewards waiting"), "ready")
	eq(ns.Weekly_HomeSummary({ vault = {}, profs = {} }), "", "nothing")
end)

test("home todo: open first, then done; knowledge, quests and capped crests", function()
	local v = ns.Weekly_View(Snap(), NOW)
	local rows = ns.Weekly_HomeTodo(v, LEARNED)
	assert(#rows > 3, "rows")
	local seenDone = false
	for _, r in ipairs(rows) do
		if r.done then
			seenDone = true
		else
			assert(not seenDone, "open after done: " .. r.text)
		end
	end
	local found
	for _, r in ipairs(rows) do
		if r.text == "Delve weekly" then
			found = r
		end
	end
	eq(found.done, true, "quest done")
	eq(ns.Weekly_HomeTodo({ profs = {}, quests = {}, currencies = {} }, {})[1], nil, "empty")
end)

if failures > 0 then
	os.exit(1)
end
