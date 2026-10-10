# Holidays & Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module `events` ("Holidays & events") that lists the world events active now and starting soon,
what the player still misses from each holiday (mounts, pets, toys, achievements), the daily holiday boss and the
Darkmoon Faire profession quests. It feeds Home, Next up, Recent (toast) and the Weekly board's "Still open" list.

**Architecture:** Pure logic (calendar time math, dedupe and classification, holiday lookup, source matching, rows,
toast decision) sits in `Data.lua` with no WoW calls and is unit-tested with plain Lua. Facts sit in `Table.lua`, and
generated IDs in `Generated.lua` (from `tools/events.py`). `Calendar.lua` and `Catalog.lua` read the game into plain
tables for the pure functions. `Page.lua` and `Holidays.lua` draw and wire it up.

**Tech stack:** WoW retail 12.1 Lua (5.1), Tomte's `ns.UI` toolkit and theme roles, `ns.RegisterModule`, Home entries
(`section`, `page`, `next`), `ns.Toast_Show`, Collect here's source parser. Python 3 for the dev script.

**Spec:** `docs/superpowers/specs/2026-10-10-tomte-holidays-design.md`.

**Execution:** the user reviews the spec's open questions first. Then Claude implements natively, and one reviewer
agent checks the branch. Work stays on branch `events`, uncommitted, until the user has checked it in game
(CLAUDE.md).

## Global constraints

- Lua 5.1 syntax (CI runs 5.1): no `goto`, no `//`, no integer division operator, no `utf8`.
- No numeric RGB in `SetTextColor`, `SetVertexColor`, `SetColorTexture` or `CreateColor`; colors come from theme roles
  (`UI.Color(role)`). No `|cff` literals, no font paths. `tests/test_theme.lua` enforces this.
- One event frame per file, dispatching with `self[event](self, ...)`.
- No new globals. Everything lives on `ns` (`ns.Events_*`, `ns.EventsCatalog_*`, `ns.EventsPage`).
- Any client language: match by IDs, textures, currency links and names the game gives (calendar name, achievement
  category title, map name). No English game text in runtime matching.
- Defaults are safe: nothing spends, queues or changes a setting. The finder click only opens and selects, never
  queues. Calendar filter CVars are never changed.
- No calendar read while `C_ChatInfo.InChatMessagingLockdown()` is true; secret fields skip the row.
- No list taken from another addon. IDs come from the game's tables (wago.tools) or warcraft.wiki.gg.

## Review focus

1. **Month edges:** the soon window crosses into next month or next year, a holiday runs over New Year (Winter
   Veil). The read must use offset 1 for the next month's days and never pass day 32. → Data test "minutes across
   year end" and the reader walks real dates.
2. **Blizzard's calendar open on another month** while Tomte reads: Tomte must not move it, and must still read
   today's events. → Data test "month offset"; Calendar.lua reads `GetMonthInfo(0)` when `CalendarFrame` is shown.
3. **Source text where the holiday name follows a `|n`** ("...|nBrewfest Vendors") or sits beside a lookalike
   ("Hallowfall"): it must match the first and not the second. → Data tests "name after |n" and "no Hallowfall".
4. **A holiday seen on every day of the window** (the same occurrence 8 times), and two occurrences of one holiday
   (Darkmoon Faire this month and next): one row each. → Data test "dedupe".
5. **A character with no professions, or below the holiday boss's level:** no Darkmoon rows (a note instead) and
   "not available on this character", no Next up nagging. → Data tests "Darkmoon rows" and "dungeon split".

---

### Task 1: Facts, generator and generated data

**Files:**
- Create: `Modules/Holidays/Table.lua`, `tools/events.py`, `Modules/Holidays/Generated.lua` (script output).
- Test: `tests/test_events.lua` (started here, extended in Task 2).

**Produces:**
- `ns.EVENTS_DEFS`: a list of `{ key, ids, textures, category?, currencies?, icons?, maps?, lfg?, extra? }`.
- `ns.EVENTS_TIMEWALKING`: the Timewalking entry `{ key = "timewalking", category = 15454, currencies = { 1166 },
  icons = {...} }`.
- `ns.EVENTS_DARKMOON_QUESTS`: `[skillLine] = questID`.
- `ns.EVENTS_TOYS`: `[key] = { itemID... }`.
- `ns.EVENTS_TW_TEXTURES`: `{ fileID... }`.

- [ ] **Step 1: Write `Modules/Holidays/Table.lua`**

```lua
local addonName, ns = ...

-- Holidays & events: facts. Holiday IDs and texture fileIDs (start, ongoing, end) from the client's Holidays table,
-- achievement categories from Achievement_Category (World Events, 155), LFG dungeons from LFGDungeons (wago.tools).
-- icons: cost-icon paths (lower case, no .blp) that holiday vendors' source text carries, language-free.
-- maps: uiMapIDs whose localized name counts as the holiday's name in source text.
-- extra: mounts and pets whose source text doesn't name the holiday (from tools/events.py's report).
-- Pilgrim's Bounty shares its textures with the old Harvest Festival, so it's matched by ID only.

ns.EVENTS_DEFS = {
	{ key = "darkmoon", ids = { 479 }, textures = { 235446, 235447, 235448 }, category = 15101, currencies = { 515 },
		icons = { "interface\\icons\\inv_misc_ticket_darkmoon_01" }, maps = { 407 } },
	{ key = "lunar", ids = { 327 }, textures = { 235469, 235470, 235471 }, category = 160,
		icons = { "interface\\icons\\inv_misc_elvencoins" } },
	{ key = "love", ids = { 423 }, textures = { 235466, 235467, 235468 }, category = 187,
		icons = { "interface\\icons\\inv_valentinescard01" }, lfg = { 288 } },
	{ key = "noblegarden", ids = { 181 }, textures = { 235475, 235476, 235477 }, category = 159,
		icons = { "interface\\icons\\achievement_noblegarden_chocolate_egg" } },
	{ key = "childrens", ids = { 201 }, textures = { 235443, 235444, 235445 }, category = 163 },
	{ key = "midsummer", ids = { 341 }, textures = { 235472, 235473, 235474 }, category = 161,
		icons = { "interface\\icons\\inv_summerfest_fireflower" }, lfg = { 286 } },
	{ key = "pirates", ids = { 398 }, textures = { 235481 } },
	{ key = "brewfest", ids = { 372 }, textures = { 235440, 235441, 235442 }, category = 162, lfg = { 287 } },
	{ key = "hallows", ids = { 324 }, textures = { 235460, 235461, 235462 }, category = 158,
		icons = { "interface\\icons\\achievement_halloween_candy_01" }, lfg = { 285 } },
	{ key = "dead", ids = { 409 }, textures = { 307364, 307365, 840589 } },
	{ key = "pilgrims", ids = { 404 }, textures = {}, category = 14981 },
	{ key = "winterveil", ids = { 141 }, textures = { 235482, 235484, 235485 }, category = 156 },
}

-- Timewalking gets new holiday IDs every season: it's found through the Dungeon Finder instead.
ns.EVENTS_TIMEWALKING = { key = "timewalking", category = 15454, currencies = { 1166 },
	icons = { "interface\\icons\\pvecurrency-justice" } }

-- Darkmoon Faire profession quests, [TradeSkillLineID] = questID. 29509, 29510, 29511, 29513 and 29516 are checked in
-- game with /tomte events ids; the rest against warcraft.wiki.gg.
ns.EVENTS_DARKMOON_QUESTS = {
	[171] = 29506, [794] = 29507, [164] = 29508, [185] = 29509, [333] = 29510, [202] = 29511, [356] = 29513,
	[182] = 29514, [773] = 29515, [755] = 29516, [165] = 29517, [186] = 29518, [393] = 29519, [197] = 29520,
}
```

- [ ] **Step 2: Write `tools/events.py`.** Standard library only. It downloads to its own scratch directory, which
  it creates empty, and runs with `python -I`.
  - Fetch `https://wago.tools/db2/<T>/csv` for Toy, Mount, BattlePetSpecies, Holidays and HolidayNames (Chrome
    User-Agent, as `waynet.py` does).
  - Holiday names (English, dev time only):

    ```python
    NAMES = {"darkmoon": ["Darkmoon Faire", "Darkmoon Island"], "lunar": ["Lunar Festival"],
             "love": ["Love is in the Air"], "noblegarden": ["Noblegarden"], "childrens": ["Children's Week"],
             "midsummer": ["Midsummer Fire Festival", "Midsummer"], "pirates": ["Pirates' Day"],
             "brewfest": ["Brewfest"], "hallows": ["Hallow's End"], "dead": ["Day of the Dead"],
             "pilgrims": ["Pilgrim's Bounty"], "winterveil": ["Feast of Winter Veil", "Winter Veil"],
             "timewalking": ["Timewalking"]}
    ```

    Currencies and icons are copied from `Table.lua` (parse it with a regex).
  - `match(text)` mirrors `ns.Events_MatchSource`:
    - turn `|n` into a newline;
    - check currency links and `|T` paths;
    - strip colors and `|T..|t`;
    - look for the names as whole words, ignoring case.

    It returns the first holiday key or None.
  - Toys: keep every toy whose source matches → `EVENTS_TOYS[key]`, sorted IDs.
  - Timewalking textures: every Holidays row whose name is "Timewalking Dungeon Event" → its non-zero
    `TextureFileDataID_0..2`, sorted and unique.
  - Write `Modules/Holidays/Generated.lua`:

    ```lua
    local addonName, ns = ...

    -- Generated by tools/events.py from the client's Toy and Holidays tables (wago.tools, build <build>). Do not edit.
    ns.EVENTS_TOYS = {
    	brewfest = { 33927, 71137 },
    	...
    }
    ns.EVENTS_TW_TEXTURES = { 1129672, 1129673, ... }
    ```

  - Report to stdout, under three headings:
    - "Toys with source type World Event (SourceTypeEnum 6) that didn't match";
    - "Mounts/pets that mention a holiday word only in their name or description";
    - "Mounts/pets with SourceTypeEnum 6 that didn't match".

    Each line has the ID, the name and the cleaned source.
  - Write the file with `\n` line endings, tabs for indentation (Lua style of the repo).

- [ ] **Step 3: Run it.** `python -I tools/events.py` from the repo root. Read the report and add the true holiday
  items it lists to `extra = { mount = {...}, pet = {...} }` in `Table.lua`. Toys that belong to a holiday but didn't
  match (vendor-only text such as "Midsummer Merchant", which the English name rules do catch; anything else) go into
  the script's `TOY_EXTRA = { key: [itemID] }` dict and the script is run again. Note each manual addition in a
  comment with the item name.

- [ ] **Step 4: Start `tests/test_events.lua` with the data checks**

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_events.lua
local ns = {}
assert(loadfile("Tomte/Modules/Collect/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Holidays/Table.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Holidays/Generated.lua"))("Tomte", ns)

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

-- (Task 2 adds the Data.lua tests here.)

if failures > 0 then
	error(failures .. " test(s) failed")
end
print("all passed")
```

- [ ] **Step 5: Run** `lua Tomte/tests/test_events.lua` from the AddOns folder. Expected: three `ok` lines, "all
  passed".

### Task 2: Pure logic (`Modules/Holidays/Data.lua`)

**Files:** create `Modules/Holidays/Data.lua`; extend `tests/test_events.lua`.

**Consumes:** `ns.Collect_Clean`, `ns.Collect_LowerMentions` (Collect/Data.lua).

**Produces** (all pure):
- `ns.Events_Minutes(t)`: minutes since 1970-01-01 for a `CalendarTime` (`year, month, monthDay, hour, minute`).
- `ns.Events_MonthOffset(selected, target)`: months from `selected` to `target` (`{ month, year }`).
- `ns.Events_Index(defs)`: returns `{ byID, byTexture, byLFG }`. A texture used by two entries is left out.
- `ns.Events_Lookup(index, eventID, texture)`: returns the def, or nil. ID first.
- `ns.Events_Collect(rows, now, soonMinutes, index)`: returns events sorted by `ns.Events_Sort`.
  - `rows = { { eventID, texture, name, description, startTime?, endTime?, day } }`, where `day` is the
    CalendarTime of the day the row came from.
  - An event is `{ key, def, name, description, texture, active, startsIn, endsIn }`, times in minutes from `now`.
- `ns.Events_Sort(list)`: active first by `endsIn`, then soon by `startsIn`, then name.
- `ns.Events_Timewalking(dungeon, secondsToReset, def)`: the finder's Timewalking event.
- `ns.Events_FoldTimewalking(list, twEvent, twTextures)`: drops unmatched calendar rows with a Timewalking texture,
  adds `twEvent`, sorts.
- `ns.Events_Duration(minutes)`: "3 days", "1 day", "5 h", "40 min".
- `ns.Events_When(ev)`: "6 days left" or "starts in 2 days".
- `ns.Events_Signals(def, names)`: `{ names = {lower}, currencies = set, icons = set, extra = { kind = set } }`.
- `ns.Events_MatchSource(raw, signals)` → bool; `ns.Events_MatchEntry(kind, id, raw, signals)` → bool.
- `ns.Events_CountsText(counts)`: "2 mounts, 5 pets, 3 toys and 12 achievements left", or nil.
- `ns.Events_Total(counts)`: the number.
- `ns.Events_DarkmoonRows(skillLines, quests, isDone)`: `{ { skillLine, questID, done } }`, open first.
- `ns.Events_SplitDungeons(dungeons, byLFG)`: returns `bosses, timewalking`.
  - `dungeons = { { id, name, isHoliday, isTimeWalker, forAll, forPlayer, doneToday } }`.
  - `bosses = { { id, name, owner, eligible, doneToday } }`; `timewalking` is the first joinable `isTimeWalker`
    dungeon.
- `ns.Events_ShouldToast(ev, total, toasted)`, and `ns.Events_PruneToasted(toasted, now, maxAge)` (in seconds).
- `ns.Events_MergeTodo(rows, extra)`: puts open extra rows after the last open row and done ones at the end (rows
  have `done`).

- [ ] **Step 1: Add the failing tests** to `tests/test_events.lua`, above the final `if failures` block, and load
  `Data.lua` at the top (`assert(loadfile("Tomte/Modules/Holidays/Data.lua"))("Tomte", ns)` after the Collect line).

```lua
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

local hallows = { key = "hallows", ids = { 324 }, textures = {} }
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
	eq(list[1].active, true)
	eq(list[1].endsIn, 11 * 1440 + 23 * 60, "ends in")
	eq(list[2].name, "Soon Fest")
	eq(list[2].active, false)
	eq(list[2].startsIn, 4 * 1440 + 22 * 60, "starts in")
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

test("merge todo rows: open extras after open rows, done at the end", function()
	local rows = { { text = "q1" }, { text = "q2" }, { text = "d1", done = true } }
	ns.Events_MergeTodo(rows, { { text = "x-done", done = true }, { text = "x-open" } })
	eq(rows[3].text, "x-open")
	eq(rows[4].text, "d1")
	eq(rows[5].text, "x-done")
end)
```

- [ ] **Step 2: Run** `lua Tomte/tests/test_events.lua`. Expected: FAIL (`loadfile` of Data.lua fails or
  `Events_Minutes` is nil).

- [ ] **Step 3: Write `Modules/Holidays/Data.lua`**

```lua
local addonName, ns = ...

-- Holidays & events: pure logic (unit-tested with plain Lua). Calendar times are realm-time CalendarTime tables;
-- they're compared as minutes on a proleptic Gregorian count, so no os/time call is needed.

local function DaysFromCivil(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function ns.Events_Minutes(t)
	return DaysFromCivil(t.year, t.month, t.monthDay) * 1440 + (t.hour or 0) * 60 + (t.minute or 0)
end

function ns.Events_MonthOffset(selected, target)
	return (target.year - selected.year) * 12 + (target.month - selected.month)
end

function ns.Events_Index(defs)
	local byID, byTexture, byLFG = {}, {}, {}
	for _, def in ipairs(defs) do
		for _, id in ipairs(def.ids or {}) do
			byID[id] = def
		end
		for _, tex in ipairs(def.textures or {}) do
			byTexture[tex] = byTexture[tex] == nil and def or false -- false: shared, ignored
		end
		for _, id in ipairs(def.lfg or {}) do
			byLFG[id] = def
		end
	end
	return { byID = byID, byTexture = byTexture, byLFG = byLFG }
end

function ns.Events_Lookup(index, eventID, texture)
	local def = eventID and index.byID[eventID]
	if def then
		return def
	end
	return texture and index.byTexture[texture] or nil
end

function ns.Events_Sort(list)
	table.sort(list, function(a, b)
		if a.active ~= b.active then
			return a.active
		end
		local ka, kb = a.active and a.endsIn or a.startsIn, b.active and b.endsIn or b.startsIn
		if ka ~= kb then
			return ka < kb
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

function ns.Events_Collect(rows, now, soonMinutes, index)
	local nowM = ns.Events_Minutes(now)
	local out, seen = {}, {}
	for _, r in ipairs(rows) do
		local def = ns.Events_Lookup(index, r.eventID, r.texture)
		local dayStart = ns.Events_Minutes({ year = r.day.year, month = r.day.month, monthDay = r.day.monthDay })
		local startM = r.startTime and ns.Events_Minutes(r.startTime) or dayStart
		local endM = r.endTime and ns.Events_Minutes(r.endTime) or (r.startTime and startM or dayStart) + 1440
		local key = (def and def.key or r.name or "?") .. ":" .. startM
		if not seen[key] and endM > nowM and startM - nowM <= soonMinutes then
			seen[key] = true
			out[#out + 1] = { key = key, def = def, name = r.name, description = r.description, texture = r.texture,
				active = startM <= nowM, startsIn = startM - nowM, endsIn = endM - nowM }
		end
	end
	return ns.Events_Sort(out)
end

function ns.Events_Timewalking(dungeon, secondsToReset, def)
	return { key = "timewalking:" .. dungeon.id, def = def, name = dungeon.name, active = true, startsIn = 0,
		endsIn = math.floor((secondsToReset or 0) / 60), dungeonID = dungeon.id }
end

function ns.Events_FoldTimewalking(list, twEvent, twTextures)
	if not twEvent then
		return list
	end
	local tw = {}
	for _, t in ipairs(twTextures or {}) do
		tw[t] = true
	end
	local out = {}
	for _, ev in ipairs(list) do
		if ev.def or not (ev.texture and tw[ev.texture]) then
			out[#out + 1] = ev
		end
	end
	out[#out + 1] = twEvent
	return ns.Events_Sort(out)
end

function ns.Events_Duration(minutes)
	minutes = math.max(math.floor(minutes or 0), 1)
	if minutes >= 2 * 1440 then
		return math.floor(minutes / 1440) .. " days"
	elseif minutes >= 1440 then
		return "1 day"
	elseif minutes >= 60 then
		return math.floor(minutes / 60) .. " h"
	end
	return minutes .. " min"
end

function ns.Events_When(ev)
	if ev.active then
		return ns.Events_Duration(ev.endsIn) .. " left"
	end
	return "starts in " .. ns.Events_Duration(ev.startsIn)
end

function ns.Events_Signals(def, names)
	local s = { names = {}, currencies = {}, icons = {}, extra = {} }
	for _, n in ipairs(names or {}) do
		if type(n) == "string" and n ~= "" then
			s.names[#s.names + 1] = n:lower()
		end
	end
	for _, c in ipairs(def.currencies or {}) do
		s.currencies[c] = true
	end
	for _, i in ipairs(def.icons or {}) do
		s.icons[i:lower()] = true
	end
	for kind, ids in pairs(def.extra or {}) do
		s.extra[kind] = {}
		for _, id in ipairs(ids) do
			s.extra[kind][id] = true
		end
	end
	return s
end

function ns.Events_MatchSource(raw, signals)
	if not raw or raw == "" then
		return false
	end
	for id in raw:gmatch("|Hcurrency:(%d+)") do
		if signals.currencies[tonumber(id)] then
			return true
		end
	end
	for path in raw:gmatch("|T([^:|]+)") do
		local p = path:lower():gsub("%.blp$", "")
		if signals.icons[p] then
			return true
		end
	end
	local text = ns.Collect_Clean(raw):gsub("|n", "\n"):lower()
	return ns.Collect_LowerMentions(text, signals.names)
end

function ns.Events_MatchEntry(kind, id, raw, signals)
	if signals.extra[kind] and signals.extra[kind][id] then
		return true
	end
	return ns.Events_MatchSource(raw, signals)
end

local KINDS = {
	{ "mounts", "mount", "mounts" }, { "pets", "pet", "pets" }, { "toys", "toy", "toys" },
	{ "achievements", "achievement", "achievements" },
}

function ns.Events_Total(counts)
	local n = 0
	for _, k in ipairs(KINDS) do
		n = n + (counts[k[1]] or 0)
	end
	return n
end

function ns.Events_CountsText(counts)
	local parts = {}
	for _, k in ipairs(KINDS) do
		local n = counts[k[1]] or 0
		if n > 0 then
			parts[#parts + 1] = ("%d %s"):format(n, n == 1 and k[2] or k[3])
		end
	end
	if #parts == 0 then
		return nil
	elseif #parts == 1 then
		return parts[1] .. " left"
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts] .. " left"
end

function ns.Events_DarkmoonRows(skillLines, quests, isDone)
	local open, done = {}, {}
	for _, line in ipairs(skillLines) do
		local q = quests[line]
		if q then
			local row = { skillLine = line, questID = q, done = isDone(q) and true or false }
			table.insert(row.done and done or open, row)
		end
	end
	for _, row in ipairs(done) do
		open[#open + 1] = row
	end
	return open
end

function ns.Events_SplitDungeons(dungeons, byLFG)
	local bosses, timewalking = {}, nil
	for _, d in ipairs(dungeons) do
		if d.forAll then
			if d.isTimeWalker then
				timewalking = timewalking or d
			elseif d.isHoliday then
				bosses[#bosses + 1] = { id = d.id, name = d.name, owner = byLFG[d.id], eligible = d.forPlayer and true or false,
					doneToday = d.doneToday and true or false }
			end
		end
	end
	return bosses, timewalking
end

function ns.Events_ShouldToast(ev, total, toasted)
	return ev.active and ev.def ~= nil and (total or 0) > 0 and not toasted[ev.key] or false
end

function ns.Events_PruneToasted(toasted, now, maxAge)
	for key, at in pairs(toasted) do
		if now - at > maxAge then
			toasted[key] = nil
		end
	end
end

function ns.Events_MergeTodo(rows, extra)
	local lastOpen = 0
	for i, r in ipairs(rows) do
		if not r.done then
			lastOpen = i
		end
	end
	for _, r in ipairs(extra) do
		if r.done then
			rows[#rows + 1] = r
		else
			lastOpen = lastOpen + 1
			table.insert(rows, lastOpen, r)
		end
	end
	return rows
end
```

- [ ] **Step 4: Run** `lua Tomte/tests/test_events.lua`. Expected: every test `ok`, "all passed". Then the full suite
  (`for t in Tomte/tests/test_*.lua; do lua "$t"; done`) to confirm the theme scan passes.

### Task 3: Calendar and finder reader (`Modules/Holidays/Calendar.lua`)

**Files:** create `Modules/Holidays/Calendar.lua`.

**Consumes:** Task 1 tables, Task 2 functions.

**Produces:**
- `ns.Events_Init(db)` keeps the db (for `soonDays`).
- `ns.Events_Request()`:
  - when `not (CalendarFrame and CalendarFrame:IsShown())`, calls `C_Calendar.SetAbsMonth(now.month, now.year)`;
  - then calls `C_Calendar.OpenCalendar()`.
- `ns.Events_ReadRows(days)`: returns rows for today .. today + days - 1, or nil while
  `C_ChatInfo.InChatMessagingLockdown()`.
  - The base offset is `ns.Events_MonthOffset(C_Calendar.GetMonthInfo(0), now)`.
  - Walk real dates: `monthDay` from `now.monthDay`; when it passes `GetMonthInfo(base).numDays`, go to day 1 of offset
    `base + 1`.
  - For each day, per index 1..`GetNumDayEvents(off, day)` (pcall):
    - `ev = C_Calendar.GetDayEvent(off, day, i)`; skip unless `ev.calendarType == "HOLIDAY"`, or when
      `issecretvalue(ev.eventID)`;
    - `info = C_Calendar.GetHolidayInfo(off, day, i)` (offsets 0 and 1 only; else nil);
    - the row is `{ eventID = ev.eventID, texture = ev.iconTexture or info.texture, name = info.name or ev.title,
      description = info.description, startTime = info.startTime, endTime = info.endTime, day = {year, month,
      monthDay = day} }`. Year and month come from `GetMonthInfo(off)`.
- `ns.Events_ReadDungeons()`: for `i = 1, GetNumRandomDungeons()`:
  - `id, name, ..., isHoliday (16), ..., isTimeWalker (19)` = `GetLFGRandomDungeonInfo(i)`;
  - `forAll, forPlayer = IsLFGDungeonJoinable(id)`;
  - `doneToday = GetLFGDungeonRewards(id)`.
- `ns.Events_Current(force)` returns `state = { list, bosses, timewalking, filters, at }`. It is cached for 60 s;
  `force` or `ns.Events_Invalidate()` rebuilds it.
  - `list = Events_FoldTimewalking(Events_Collect(rows, now, soonDays*1440, INDEX), twEvent, EVENTS_TW_TEXTURES)`.
  - `twEvent` uses `C_DateAndTime.GetSecondsUntilWeeklyReset()`.
  - `filters` holds the CVar booleans `calendarShowHolidays`, `calendarShowDarkmoon` and `calendarShowWeeklyHolidays`
    (`C_CVar.GetCVarBool`).
- `ns.Events_Names(ev)`: the calendar name, `GetCategoryInfo(def.category)` (its title) and
  `C_Map.GetMapInfo(m).name` for `def.maps`.
- `ns.Events_DarkmoonNow()`: returns nil when the faire isn't active. Otherwise `rows` from `Events_DarkmoonRows`,
  with:
  - skill lines from `GetProfessions()` (all five returns; `GetProfessionInfo(i)` 7th return);
  - `isDone = C_QuestLog.IsQuestFlaggedCompleted`;
  - `title = C_QuestLog.GetTitleForQuestID(q)`, or "Loading..." after `C_QuestLog.RequestLoadQuestByID(q)`;
  - `profession` = the first return of `GetProfessionInfo`.
- `ns.Events_OpenFinder(dungeonID)`:
  - in combat, prints "after combat: open the Dungeon Finder." and returns;
  - else `PVEFrame_ShowFrame("GroupFinderFrame", LFDParentFrame)` (when it exists, else `ToggleLFDParentFrame()`),
    then `LFDQueueFrame_SetType(dungeonID)` when it exists and `db.selectInFinder ~= false` (a hidden fallback flag
    for the taint case).
- `ns.EVENTS_INDEX = ns.Events_Index(ns.EVENTS_DEFS)` is built at file load.

- [ ] Write the file with these functions. Every API call is guarded for nil (`C_Calendar.GetHolidayInfo` may return
  nothing).
- [ ] The full test suite still passes (the theme scan covers the new file).

### Task 4: What's missing (`Modules/Holidays/Catalog.lua`)

**Files:** create `Modules/Holidays/Catalog.lua`.

**Consumes:** Task 2 matching, Task 3 `Events_Names`, `ns.Ach_ReadCriteria`, `ns.Ach_Percent`, `ns.Collect_ParseSource`.

**Produces:**
- `ns.EventsCatalog_Start(targets)`:
  - `targets = { [defKey] = signals }`;
  - restarts only when the set of keys changed;
  - a `{}` targets stops the reader.
- `ns.EventsCatalog_State()`: returns `{ ready, progress }`.
- `ns.EventsCatalog_Missing(def)`: returns `{ mounts, pets, toys, achievements, counts }` or nil while not ready.
  - Entry shapes: mount `{ kind, id, spellID, name, icon, source, line }`, pet `{ kind, id, name, icon, source, line,
    displayID }`, toy `{ kind, id, name, icon }` and achievement `{ kind = "ach", id, name, icon, percent, done,
    total }`.
  - Achievements are read live each call: `GetCategoryNumAchievements(def.category)`, `GetAchievementInfo(cat, i)`,
    skip completed, progress via `Ach_Percent(Ach_ReadCriteria(id))`.
  - Toys are filtered live with `PlayerHasToy`.
- `ns.EventsCatalog_Earned(kind, id)`: drops a mount or pet.
- `ns.EventsCatalog_SetChanged(fn)`.

How it reads:
- A hidden `OnUpdate` frame works 4 ms per frame, the same shape as Collect's `Catalog.lua`:
  - Mounts: `C_MountJournal.GetMountIDs()`, `GetMountInfoByID` (skip collected and `shouldHideOnChar`) and
    `GetMountInfoExtraByID` (source, 3rd return).
  - Then pets 1..6000: `pcall(C_PetJournal.GetPetInfoBySpeciesID, id)` (name 1, icon 2, source 5, obtainable 11),
    skip `GetNumCollectedInfo(id) > 0`.
  - Each entry is tested against every target (`Events_MatchEntry`) and stored in that holiday's list, with `line`
    from `Collect_ParseSource(source).line`.
- Toys: `ns.EVENTS_TOYS[key]` items, with names from `C_ToyBox.GetToyInfo`; missing names load via
  `Item:CreateFromItemID(id):ContinueOnItemLoad(changed)`.

- [ ] Write the file.
- [ ] The full test suite passes.

### Task 5: Module, toast, Next up, Recent owner (`Modules/Holidays/Holidays.lua`)

**Files:** create `Modules/Holidays/Holidays.lua`; modify `Modules/Recent/Recent.lua` (the `OWNERS` list).

**Consumes:** Tasks 3–4, `ns.Toast_Show`, `ns.Panel_OpenPage`, `ns.EventsPage` (Task 7; the page entry is added in
Task 7).

**Produces:**
- `RegisterModule`: key `events`, name "Holidays & events", category "Collections", `enabledByDefault = true`.
  - defaults as in the spec, plus `selectInFinder = true`; `keep = {}`.
- Events (in `toggle(active)`):
  - `PLAYER_ENTERING_WORLD`: first time only, `Events_Request` after 5 s.
  - `CALENDAR_UPDATE_EVENT_LIST`, `LFG_UPDATE_RANDOM_INFO`, `LFG_COMPLETION_REWARD`, `QUEST_TURNED_IN`,
    `NEW_MOUNT_ADDED`, `NEW_PET_ADDED`, `NEW_TOY_ADDED`, `ACHIEVEMENT_EARNED`.
  - All debounced 1 s → `Events_Invalidate`, `Refresh()`.
- `Refresh()`:
  - reads `Events_Current()`;
  - builds targets (signals for each listed event with a def; Timewalking uses `ns.EVENTS_TIMEWALKING`);
  - `EventsCatalog_Start(targets)`;
  - `MaybeToast()`;
  - `ns.Panel_Refresh()` when the panel is shown.
- `MaybeToast()`:
  - out of combat, catalog ready, `db.toasts.start`;
  - for each active event with `Events_ShouldToast(ev, total, db.toasted)`: `ns.Toast_Show({ owner = "events", label
    = "Holiday", accent = "accent", title = ev.name .. " has started", text = Events_CountsText(counts) .. " · ends "
    .. date, icon = ev.texture, mergeKey = "events:" .. ev.key, holdInCombat = true, hold = 12, onClick =
    OpenPage(ev.key) })`;
  - then `db.toasted[ev.key] = GetServerTime()`;
  - the end date uses `FormatShortDate(endTime.monthDay, endTime.month)` (Blizzard's localized date helper).
  - `Events_PruneToasted(db.toasted, GetServerTime(), 60 * 86400)` at init.
- `ns.Events_WeeklyRows()`: returns `{}` unless the module is active and `db.weekly`. Otherwise:
  - Darkmoon rows as `{ text = profession .. ": " .. title, right = done and "done" or "open", done }`;
  - holiday bosses as `{ text = name, right = doneToday and "done today" or "today", done = doneToday }`, only when
    eligible.
- Next up sources (`home` entries of kind `"next"`), as in the spec:
  - `nextholidayboss` (score 70): one candidate per eligible boss not done today. Key `"events:boss:" .. id`, state =
    today's date `("%d-%d-%d")`. `onClick = Events_OpenFinder(id)`, hint "Click to open the Dungeon Finder".
  - `nextevent` (score 60): an active event with a def, `endsIn <= 2880` and total > 0. Key `"events:end:" ..
    ev.key`.
  - `nextdarkmoon` (score 50): the faire is active and any row is open. Key `"events:dmf"`, state = the open count.
- Commands:
  - `open`;
  - `list` (prints each event, its `Events_When`, counts text and boss/Darkmoon state);
  - `calendar` (prints the raw rows of today: eventID, texture, name, start/end, plus the three CVars);
  - `ids` (each Darkmoon quest ID, its skill line and `GetTitleForQuestID`);
  - `test` (sample toast with `test = true`).
- Options:
  - show on Home, rows, starting within (days), other events;
  - the four kinds;
  - start toast and "Sample toast" button;
  - Weekly board rows;
  - "Open calendar" button (`ToggleCalendar()`).
- Recent.lua: add `{ "events", "Holidays & events" }` to `OWNERS` after `{ "wq", "World quests" }`.

- [ ] Write the module and the Recent line.
- [ ] Run the full test suite (`test_recent.lua` and `test_theme.lua` must pass).

### Task 6: Home block and Weekly rows

**Files:**
- Modify: `Panel/Home.lua`. In the layout code: `hasRight` gains `or byslot.events ~= nil`; after the
  `byslot.recent` push add `if byslot.events then stack[#stack + 1] = byslot.events end`; the empty check
  includes `byslot.events`.
- Modify: `Modules/Weekly/HomeSection.lua`. After `local rows = ns.Weekly_HomeTodo(...)`, add
  `if ns.Events_WeeklyRows then ns.Events_MergeTodo(rows, ns.Events_WeeklyRows()) end`.
- Modify: `Modules/Holidays/Holidays.lua` (adds the section entry).

**Produces:** the section entry `{ kind = "section", slot = "events", key = "eventssection", Create, Refresh, shown =
function() return db.home end }`:
- `Create(frame, Kit)`: a `Kit.Heading` and a row pool.
- `Refresh(frame)`:
  - `Events_Current()`; returns 0 when the list is empty.
  - The heading is "Events" with "n on now" on the right; up to `db.homeRows` rows from the list.
  - Each row is `Kit.PoolRow`:
    - icon `ev.texture`, text `ev.name`;
    - color `"text"` when active, `"textMuted"` when soon;
    - right `Events_When(ev)` for soon ones; for active ones the missing total ("14 left", "reading..." while the
      catalog isn't ready, or `Events_When`).
  - `onEnter`: tooltip with the description, `Events_When` and the counts text.
  - `onClick`: `ns.EventsPage_Open(ev.key)`.
  - Returns `40 + n * Kit.ROW_H`.

- [ ] Make the three edits.
- [ ] Run the full test suite (`test_home.lua` must pass).

### Task 7: Events page (`Modules/Holidays/Page.lua`)

**Files:** create `Modules/Holidays/Page.lua`; modify `Modules/Holidays/Holidays.lua` (page entry).

**Produces:**
- `ns.EventsPage = { title = "Events", Create, Refresh }`, the same shape as `ns.PetsPage`.
- `ns.EventsPage_Init(db)` and `ns.EventsPage_Open(key)`. `Open` calls `ns.Panel_OpenPage("events")` and scrolls to
  the event.
- Page entry: `{ kind = "page", key = "events", order = 41, name = "Events", icon =
  "Interface\\Icons\\INV_Misc_Toy_10", page = ns.EventsPage, summary = function() ... "Hallow's End · 6 days" or
  "Nothing on" end }`.
- Layout, in a `UI.Scroll`, with headings "On now" and "Soon". For each event:
  - a header row: icon, name, `Events_When`, the description in its tooltip;
  - boss rows (eligible / done / not available) with a click to open the finder;
  - Darkmoon rows (profession, quest, done) or the note "No profession quests for this character";
  - four collapsible lists (`UI.CollapseButton`, state in `db.collapsed[ev.key .. kind]`), each list's rows being
    icon, name and `line` (or percent).
    - Hover: `GameTooltip` with name and source (the cleaned source lines), plus `ns.ModelPreview_Show` for mounts
      (`C_MountJournal.GetMountInfoExtraByID` displayID and sceneID) and pets (`displayID` from
      `GetPetInfoBySpeciesID` 12th return).
    - Click: an achievement opens `OpenAchievementFrameToAchievement(id)` (after `C_AddOns.LoadAddOn
      ("Blizzard_AchievementUI")` when needed); a Shift-click on any row puts its link in chat
      (`ChatEdit_InsertLink`, with links from `C_MountJournal.GetMountLink`, `C_PetJournal.GetBattlePetLink` (needs a
      petID: skip for pets), `C_ToyBox.GetToyLink` and `GetAchievementLink`).
  - Soon events show only the header and "Starts <date>".
- Footer:
  - "Hidden by your calendar filter: Darkmoon Faire" when a filter CVar is off;
  - an "Open calendar" button.

- [ ] Write the page and its entry.
- [ ] Run the full test suite.

### Task 8: TOC, README, CHANGELOG

**Files:** modify `Tomte.toc`, `README.md`, `CHANGELOG.md`.

- [ ] TOC: after `Modules/Collect/Collect.lua`, in this order:
  - `Modules/Holidays/Table.lua`, `Modules/Holidays/Generated.lua`, `Modules/Holidays/Data.lua`;
  - `Modules/Holidays/Calendar.lua`, `Modules/Holidays/Catalog.lua`, `Modules/Holidays/Page.lua`;
  - `Modules/Holidays/Holidays.lua`.
- [ ] README:
  - a module-table row "Holidays & events | Collections | ..." in player-facing words;
  - `/tomte events` commands under Commands;
  - `Holidays` in the Layout's module folder list;
  - Credits: "Holiday, LFG dungeon, achievement category and toy source data from the client's tables on
    wago.tools; Darkmoon quest IDs from warcraft.wiki.gg."
- [ ] CHANGELOG under Unreleased, for example: "Holidays & events: what's on now and soon, what you're still missing
  from each holiday (mounts, pets, toys, achievements), the daily holiday boss and the Darkmoon Faire profession
  quests, on Home, in Next up and as a toast when a holiday starts." Added only after the user's in-game check.
- [ ] Run `for t in Tomte/tests/test_*.lua; do lua "$t"; done` from AddOns. Expected: every file "all passed".

### Task 9: Almost Done's holiday filter on the shared reader (only if the user says yes, spec question 5)

**Files:** modify `Modules/Achievements/Achievements.lua` (`Holidays()` and `StartUp()`).

- [ ] `Holidays()` returns the lower-case names of `ns.Events_Current().list` entries that are active or start within
  1 day, when `ns.Events_Current` exists. Otherwise it keeps its own loop, but computes the offset with
  `ns.Events_MonthOffset(C_Calendar.GetMonthInfo(0), now)` instead of 0.
- [ ] `StartUp()` calls `ns.Events_Request()` instead of `C_Calendar.OpenCalendar()` when it exists.
- [ ] Run `lua Tomte/tests/test_achievements.lua` and the full suite.

### Task 10: Review and in-game checklist

- [ ] One reviewer agent reads the whole branch diff against the spec and this plan. It checks the Review focus
  items, taint around the finder, `issecretvalue` guards, Lua 5.1, the theme rules and no globals. Fix its findings
  and re-run the tests.
- [ ] Write the in-game checklist for the user:
  1. `/reload`, BugSack clean. `/tomte events calendar`: are the eventIDs the holiday IDs (324 for Hallow's End)?
     What do the filter CVars say?
  2. `/tomte events ids`: do 29509, 29510, 29511, 29513 and 29516 show Cooking, Enchanting, Engineering, Fishing and
     Jewelcrafting quest names?
  3. Home: the Events block shows the active holiday with a count. The rail's Events page lists mounts, pets, toys
     and achievements; hover shows source and model.
  4. Clear the toast memory (`/run TomteDB.events.toasted = {}`), `/reload`: the start toast appears within 30 s and
     is in Recent.
  5. During a holiday with a boss: the Next up row → click → the Dungeon Finder opens with the boss selected. Queue
     and leave the queue: no "AddOn tried to call a protected function" in BugSack.
  6. At the next Darkmoon Faire: the profession quests on the page and in the Weekly board's "Still open".
