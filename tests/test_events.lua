-- Run from the AddOns folder: lua Tomte/tests/test_events.lua
local ns = {}
assert(loadfile("Tomte/Modules/Collect/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Holidays/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Holidays/Table.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Holidays/Generated.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- Facts ------------------------------------------------------------------------------------------------------------

test("holiday table: unique keys, numeric ids, lower-case icons", function()
	local keys = {}
	for _, def in ipairs(ns.EVENTS_DEFS) do
		assert(type(def.key) == "string" and not keys[def.key], "key " .. tostring(def.key))
		keys[def.key] = true
		assert(#def.ids > 0, def.key .. " has no ids")
		for _, id in ipairs(def.ids) do
			assert(type(id) == "number", def.key)
		end
		for _, icon in ipairs(def.icons or {}) do
			eq(icon, icon:lower(), def.key .. " icon")
			assert(not icon:find("%.blp$"), def.key .. " icon has .blp")
		end
	end
	assert(not keys.timewalking, "timewalking is its own entry")
end)

test("generated toys belong to known holidays", function()
	local keys = { timewalking = true }
	for _, def in ipairs(ns.EVENTS_DEFS) do
		keys[def.key] = true
	end
	local n = 0
	for key, ids in pairs(ns.EVENTS_TOYS) do
		assert(keys[key], "unknown key " .. key)
		for _, id in ipairs(ids) do
			assert(type(id) == "number")
			n = n + 1
		end
	end
	assert(n >= 50, "expected the holiday toys, got " .. n)
	assert(#ns.EVENTS_TW_TEXTURES >= 10)
end)

test("darkmoon quests cover 14 professions", function()
	local n = 0
	for skillLine, quest in pairs(ns.EVENTS_DARKMOON_QUESTS) do
		assert(type(skillLine) == "number" and quest >= 29506 and quest <= 29520)
		n = n + 1
	end
	eq(n, 14)
end)

-- Data.lua -----------------------------------------------------------------------------------------------------------

local function T(y, mo, d, h, mi)
	return { year = y, month = mo, monthDay = d, hour = h or 0, minute = mi or 0 }
end

test("minutes: epoch, a day, leap day, year end", function()
	eq(ns.Events_Minutes(T(1970, 1, 1)), 0, "epoch")
	eq(ns.Events_Minutes(T(2026, 10, 11)) - ns.Events_Minutes(T(2026, 10, 10)), 1440, "a day")
	eq(ns.Events_Minutes(T(2028, 3, 1)) - ns.Events_Minutes(T(2028, 2, 28)), 2 * 1440, "leap year")
	eq(ns.Events_Minutes(T(2027, 3, 1)) - ns.Events_Minutes(T(2027, 2, 28)), 1440, "no leap")
	eq(ns.Events_Minutes(T(2027, 1, 1, 0, 15)) - ns.Events_Minutes(T(2026, 12, 31, 23, 30)), 45, "year end")
end)

test("month offset from the calendar's selected month", function()
	eq(ns.Events_MonthOffset({ month = 11, year = 2004 }, { month = 10, year = 2026 }), 263)
	eq(ns.Events_MonthOffset({ month = 12, year = 2026 }, { month = 1, year = 2027 }), 1)
	eq(ns.Events_MonthOffset({ month = 10, year = 2026 }, { month = 10, year = 2026 }), 0)
end)

test("month days and the day walk over a month and a year end", function()
	eq(ns.Events_MonthDays(2028, 2), 29, "leap")
	eq(ns.Events_MonthDays(2100, 2), 28, "century")
	eq(ns.Events_MonthDays(2000, 2), 29, "400")
	eq(ns.Events_MonthDays(2026, 12), 31)
	local days = ns.Events_DayList(T(2026, 12, 29), 5)
	eq(#days, 5)
	eq(days[1].offset, 0)
	eq(days[3].monthDay, 31)
	eq(days[4].offset, 1, "next month")
	eq(days[4].monthDay, 1)
	eq(days[4].year, 2027)
	eq(days[4].month, 1)
	eq(days[5].monthDay, 2)
	for _, d in ipairs(ns.Events_DayList(T(2026, 2, 27), 14)) do
		assert(d.monthDay <= 31 and d.offset <= 1, "never past day 31 or offset 1")
	end
end)

test("lookup: ID wins, then texture; shared textures are ignored", function()
	local a = { key = "a", ids = { 1 }, textures = { 10, 11 } }
	local b = { key = "b", ids = { 2 }, textures = { 11, 12 }, lfg = { 285 } }
	local index = ns.Events_Index({ a, b })
	eq(ns.Events_Lookup(index, nil, 10), a, "texture 10")
	eq(ns.Events_Lookup(index, nil, 11), nil, "shared texture")
	eq(ns.Events_Lookup(index, nil, 12), b, "texture 12")
	eq(ns.Events_Lookup(index, 2, 10), b, "id first")
	eq(ns.Events_Lookup(index, 99, nil), nil, "unknown")
	eq(index.byLFG[285], b, "lfg")
end)

test("lookup with the real table: Hallow's End by id and by texture", function()
	local index = ns.Events_Index(ns.EVENTS_DEFS)
	eq(ns.Events_Lookup(index, 324, nil).key, "hallows")
	eq(ns.Events_Lookup(index, 12345, 235461).key, "hallows")
	eq(ns.Events_Lookup(index, nil, 1304688), nil, "Timewalking texture isn't a holiday")
	eq(index.byLFG[285].key, "hallows")
end)

test("every holiday in the real table has its own square icon", function()
	for _, def in ipairs(ns.EVENTS_DEFS) do
		eq(type(def.icon), "number", def.key)
		for _, tex in ipairs(def.textures) do
			eq(def.icon ~= tex, true, def.key .. " icon isn't a calendar texture")
		end
	end
end)

local hallows = { key = "hallows", ids = { 324 }, textures = {}, icon = 236546 }
local INDEX = ns.Events_Index({ hallows })
local NOW = T(2026, 10, 20, 12, 0)

test("collect: dedupe, active vs soon, window and ended", function()
	local function H(day)
		return { eventID = 324, name = "Hallow's End", startTime = T(2026, 10, 18, 10, 0), endTime = T(2026, 11, 1, 11, 0),
			day = day }
	end
	local rows = {
		H(T(2026, 10, 20)), H(T(2026, 10, 21)), H(T(2026, 10, 22)),
		{ name = "Soon Fest", startTime = T(2026, 10, 25, 10, 0), endTime = T(2026, 10, 27, 10, 0), day = T(2026, 10, 25) },
		{ name = "Far Fest", startTime = T(2026, 11, 5, 10, 0), endTime = T(2026, 11, 6, 10, 0), day = T(2026, 11, 5) },
		{ name = "Gone Fest", startTime = T(2026, 10, 19, 10, 0), endTime = T(2026, 10, 20, 11, 0), day = T(2026, 10, 20) },
	}
	local list = ns.Events_Collect(rows, NOW, 7 * 1440, INDEX)
	eq(#list, 2, "count")
	eq(list[1].def, hallows, "first is the active holiday")
	eq(list[1].icon, 236546, "the table's icon, not the calendar texture")
	eq(list[1].active, true)
	eq(list[1].endsIn, 11 * 1440 + 23 * 60, "ends in")
	eq(list[2].name, "Soon Fest")
	eq(list[2].icon, nil, "unknown event: no icon")
	eq(list[2].active, false)
	eq(list[2].startsIn, 4 * 1440 + 22 * 60, "starts in")
end)

test("collect: an event without an entry gets its icon group's icon by texture", function()
	local index = ns.Events_Index({ hallows }, { { icon = 6025441, textures = { 6033780, 6033781 } } })
	local rows = {
		{ name = "Delves Bonus Event", texture = 6033781, startTime = T(2026, 10, 20, 8, 0),
			endTime = T(2026, 10, 21, 8, 0), day = T(2026, 10, 20) },
		{ eventID = 324, name = "Hallow's End", texture = 6033781, startTime = T(2026, 10, 18, 10, 0),
			endTime = T(2026, 11, 1, 11, 0), day = T(2026, 10, 20) },
	}
	local list = ns.Events_Collect(rows, NOW, 7 * 1440, index)
	eq(#list, 2)
	eq(list[1].icon, 6025441, "group icon")
	eq(list[2].icon, 236546, "the entry's icon wins")
end)

test("weekly icon groups: real icons, no texture shared with a holiday", function()
	local index = ns.Events_Index(ns.EVENTS_DEFS)
	for _, group in ipairs(ns.EVENTS_WEEKLY_ICONS) do
		eq(type(group.icon), "number")
		for _, tex in ipairs(group.textures) do
			eq(index.byTexture[tex], nil, tex .. " is no holiday's")
		end
	end
	eq(type(ns.EVENTS_TIMEWALKING.icon), "number")
	eq(ns.Events_Timewalking({ id = 1, name = "TW" }, 60, ns.EVENTS_TIMEWALKING).icon, ns.EVENTS_TIMEWALKING.icon)
end)

test("collect: two occurrences of one holiday stay apart; a row without times covers its day", function()
	local rows = {
		{ eventID = 324, name = "Hallow's End", startTime = T(2026, 10, 18), endTime = T(2026, 10, 21), day = T(2026, 10, 20) },
		{ eventID = 324, name = "Hallow's End", startTime = T(2026, 10, 25), endTime = T(2026, 10, 26), day = T(2026, 10, 25) },
		{ name = "Day Thing", day = T(2026, 10, 20) },
	}
	local list = ns.Events_Collect(rows, NOW, 7 * 1440, INDEX)
	eq(#list, 3)
	local day
	for _, ev in ipairs(list) do
		if ev.name == "Day Thing" then
			day = ev
		end
	end
	eq(day.active, true, "day row active")
	eq(day.endsIn, 12 * 60, "until midnight")
end)

test("collect: a holiday over New Year read from both months is one row", function()
	local function W(day)
		return { eventID = 141, name = "Feast of Winter Veil", startTime = T(2026, 12, 16, 10, 0),
			endTime = T(2027, 1, 2, 6, 0), day = day }
	end
	local winter = { key = "winterveil", ids = { 141 } }
	local list = ns.Events_Collect({ W(T(2026, 12, 30)), W(T(2026, 12, 31)), W(T(2027, 1, 1)) }, T(2026, 12, 30, 8, 0),
		7 * 1440, ns.Events_Index({ winter }))
	eq(#list, 1)
	eq(list[1].endsIn, 2 * 1440 + 22 * 60)
end)

test("timewalking folds the calendar row into the finder's event", function()
	local list = {
		{ key = "x:1", name = "Timewalking Dungeon Event", texture = 1304688, active = true, startsIn = -100, endsIn = 500 },
		{ key = "hallows:2", def = hallows, name = "Hallow's End", active = true, startsIn = -10, endsIn = 9000 },
	}
	local tw = ns.Events_Timewalking({ id = 1146, name = "Random Timewalking Dungeon (Cataclysm)" }, 3600 * 30,
		{ key = "timewalking" })
	eq(tw.key, "timewalking:1146")
	eq(tw.endsIn, 30 * 60)
	local out = ns.Events_FoldTimewalking(list, tw, { 1304686, 1304687, 1304688 })
	eq(#out, 2, "calendar row dropped")
	eq(out[1], tw, "sorted by time left")
	eq(#ns.Events_FoldTimewalking(list, nil, { 1304688 }), 2, "no finder event: calendar row kept")
end)

test("duration and when", function()
	eq(ns.Events_Duration(2 * 1440), "2 days")
	eq(ns.Events_Duration(1440 + 5), "1 day")
	eq(ns.Events_Duration(61), "1 h")
	eq(ns.Events_Duration(59), "59 min")
	eq(ns.Events_Duration(0), "1 min")
	eq(ns.Events_When({ active = true, endsIn = 11 * 1440 + 23 * 60 }), "11 days left")
	eq(ns.Events_When({ active = false, startsIn = 4 * 1440 + 22 * 60 }), "starts in 4 days")
end)

local DMF = { key = "darkmoon", currencies = { 515 }, icons = { "interface\\icons\\inv_misc_ticket_darkmoon_01" },
	extra = { pet = { 1061 } } }
local DMF_S = ns.Events_Signals(DMF, { "Darkmoon Faire", "Darkmoon Faire", "Darkmoon Island" })

test("match: zone name, currency link, cost icon, extra id", function()
	eq(ns.Events_MatchSource("|cFFFFD200Vendor: |rLhara|n|cFFFFD200Zone: |rDarkmoon Island|n|cFFFFD200Cost: |r180", DMF_S),
		true, "zone")
	eq(ns.Events_MatchSource("|cFFFFD200Cost: |r90|Hcurrency:515|h|h", DMF_S), true, "currency")
	eq(ns.Events_MatchSource("Cost: 90|TINTERFACE\\ICONS\\INV_MISC_TICKET_DARKMOON_01.BLP:0|t", DMF_S), true, "icon")
	eq(ns.Events_MatchSource("Cost: 90|Hcurrency:1166|h|h", DMF_S), false, "other currency")
	eq(ns.Events_MatchEntry("pet", 1061, "", DMF_S), true, "extra pet")
	eq(ns.Events_MatchEntry("mount", 1061, "", DMF_S), false, "extra is per kind")
	eq(ns.Events_MatchSource(nil, DMF_S), false, "nil")
end)

test("match: holiday name as whole words, also after |n; not Hallowfall", function()
	local s = ns.Events_Signals({ key = "hallows" }, { "Hallow's End" })
	eq(ns.Events_MatchSource("|cFFFFD200Drop: |rLoot-Filled Pumpkin|n|cFFFFD200Holiday: |rHallow's End|n", s), true)
	eq(ns.Events_MatchSource("|cFFFFD200Drop: |rBeledar's Spawn|n|cFFFFD200Zone: |rHallowfall", s), false)
	local b = ns.Events_Signals({ key = "brewfest" }, { "Brewfest" })
	eq(ns.Events_MatchSource("|cFFFFD200Vendor: |rBarleybrew|nBrewfest Vendors", b), true, "after |n")
end)

test("match: real client source rows", function()
	local index = ns.Events_Index(ns.EVENTS_DEFS)
	local hal = ns.Events_Signals(ns.Events_Lookup(index, 324), { "Hallow's End" })
	-- Toy 70722: name and cost icon.
	eq(ns.Events_MatchSource("|cFFFFD200World Event:|r Hallow's End|n|cFFFFD200Vendor: |rChub / Dorothy|n|cFFFFD200Cost: "
		.. "|r150|TINTERFACE\\ICONS\\ACHIEVEMENT_HALLOWEEN_CANDY_01.BLP:0|t|n|n", hal), true)
	-- Lick King: only the extra ID.
	eq(ns.Events_MatchEntry("pet", 3491, "|cFFFFD200Drop:|r Headless Horseman|n|cFFFFD200Zone:|r Scarlet Monastery", hal), true)
	-- Timewalking vendor items: currency link.
	local tw = ns.Events_Signals(ns.EVENTS_TIMEWALKING, { "Timewalking" })
	eq(ns.Events_MatchSource("|cFFFFD200Vendor: |rCupri|n|cFFFFD200Cost: |r5000|Hcurrency:1166|h|TInterface\\ICONS\\"
		.. "PVECurrency-Justice.blp:0|t|h", tw), true)
	-- Lunar Festival: the Dornogal vendor's coin icon is not a festival signal.
	local lunar = ns.Events_Signals(ns.Events_Lookup(index, 327), { "Lunar Festival" })
	eq(ns.Events_MatchSource("|cFFFFD200Vendor: |rSir Finley Mrrgglton|n|cFFFFD200Cost: |r500"
		.. "|TInterface\\ICONS\\INV_Misc_ElvenCoins.blp:0|t", lunar), false)
end)

test("counts text", function()
	eq(ns.Events_CountsText({ mounts = 2, pets = 5, toys = 3, achievements = 12 }),
		"2 mounts, 5 pets, 3 toys and 12 achievements left")
	eq(ns.Events_CountsText({ pets = 1 }), "1 pet left")
	eq(ns.Events_CountsText({ mounts = 1, toys = 2 }), "1 mount and 2 toys left")
	eq(ns.Events_CountsText({}), nil)
	eq(ns.Events_Total({ mounts = 1, toys = 2 }), 3)
end)

test("darkmoon rows: open first, professions without a quest skipped, none for no professions", function()
	local rows = ns.Events_DarkmoonRows({ 186, 999, 171 }, ns.EVENTS_DARKMOON_QUESTS, function(q)
		return q == 29518
	end)
	eq(#rows, 2)
	eq(rows[1].questID, 29506, "open first")
	eq(rows[1].done, false)
	eq(rows[2].questID, 29518)
	eq(rows[2].done, true)
	eq(#ns.Events_DarkmoonRows({}, ns.EVENTS_DARKMOON_QUESTS, function()
		return false
	end), 0)
end)

test("dungeon split: holiday bosses, timewalking, not joinable", function()
	local bosses, tw = ns.Events_SplitDungeons({
		{ id = 285, name = "The Headless Horseman", isHoliday = true, forAll = true, forPlayer = false, doneToday = false },
		{ id = 1146, name = "Random Timewalking Dungeon (Cataclysm)", isHoliday = true, isTimeWalker = true, forAll = true },
		{ id = 286, name = "The Frost Lord Ahune", isHoliday = true, forAll = false },
		{ id = 2, name = "Random Dungeon", forAll = true },
	}, { [285] = hallows })
	eq(#bosses, 1)
	eq(bosses[1].owner, hallows)
	eq(bosses[1].eligible, false, "too low")
	eq(tw.id, 1146)
end)

test("toast once per occurrence, only with something left", function()
	local ev = { key = "hallows:1", def = hallows, active = true }
	eq(ns.Events_ShouldToast(ev, 3, {}), true)
	eq(ns.Events_ShouldToast(ev, 3, { ["hallows:1"] = 5 }), false, "toasted")
	eq(ns.Events_ShouldToast(ev, 0, {}), false, "nothing left")
	eq(ns.Events_ShouldToast({ key = "x", active = true }, 3, {}), false, "no table entry")
	eq(ns.Events_ShouldToast({ key = "y", def = hallows, active = false }, 3, {}), false, "not started")
	local toasted = { a = 100, b = 1000 }
	ns.Events_PruneToasted(toasted, 1000 + 500, 1000)
	eq(toasted.a, nil, "old pruned")
	eq(toasted.b, 1000, "recent kept")
end)

test("heads-up the day before: once, only within a day of the start, with something left", function()
	local ev = { key = "hallows:9", def = hallows, active = false, startsIn = 20 * 60 }
	eq(ns.Events_ShouldHeadsUp(ev, 2, {}), true)
	eq(ns.Events_HeadsUpKey(ev), "pre:hallows:9")
	eq(ns.Events_ShouldHeadsUp(ev, 2, { ["pre:hallows:9"] = 1 }), false, "once")
	eq(ns.Events_ShouldHeadsUp({ key = "k", def = hallows, active = false, startsIn = 2 * 1440 }, 2, {}), false, "too early")
	eq(ns.Events_ShouldHeadsUp({ key = "k", def = hallows, active = true, startsIn = -5 }, 2, {}), false, "started")
	eq(ns.Events_ShouldHeadsUp(ev, 0, {}), false, "nothing left")
end)

test("merge todo rows: open extras after open rows, done at the end", function()
	local rows = { { text = "q1" }, { text = "q2" }, { text = "d1", done = true } }
	ns.Events_MergeTodo(rows, { { text = "x-done", done = true }, { text = "x-open" } })
	eq(rows[3].text, "x-open")
	eq(rows[4].text, "d1")
	eq(rows[5].text, "x-done")
end)

H.done()
