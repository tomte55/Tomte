# Tomte health-pass proposals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry out every open proposal from the 2026-10-11 codebase health pass: legacy API removal, one money/number
formatter, migrations in Core, one event frame per module, the remaining shared helpers, theme-color conversions, the
big-file splits, the two file renames, a shared test harness and shared Python tool helpers.

**Architecture:** Mostly behavior-neutral restructuring of a WoW retail addon (Lua 5.1, no build step). New pure files
(`Core/Format.lua`, `Core/Migrations.lua`, `Core/Events.lua`) carry the shared logic and are unit-tested with plain
Lua; UI and event code is checked in game by the user. Each phase ends with the full unit-test loop, an in-game check
list for the user, and a commit only after the user confirms (CLAUDE.md rule).

**Tech Stack:** Lua 5.1 (WoW 12.1 client, CI runs `lua5.1`), plain-Lua unit tests in `tests/`, Python 3 dev tools in
`tools/` (Pillow, fontTools).

**Spec:** the "Open proposals" list in the health-pass final report (conversation of 2026-10-11) plus the five research
reports summarized in each task below. Fact sources: warcraft.wiki.gg and https://github.com/Gethe/wow-ui-source (live).

## Global Constraints

- Repo root = live addon folder `D:\World of Warcraft\_retail_\Interface\AddOns\Tomte`. Run tests from the AddOns
  folder: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done` (bash). All green.
- Edit Lua only with the Edit/Write tools, never sed/awk/heredocs (they break CRLF and backslashes here).
- `TomteDB` keys are never renamed or restructured, except by an ordered migration in `Core/Migrations.lua`.
- No new globals except frame names that bindings or `UISpecialFrames` need. `local addonName, ns = ...` at the top of
  every Lua file.
- Colors and fonts only through theme roles (`ns.UI`, `ns.Theme`); `tests/test_theme.lua` must stay green.
- After any TOC change: `lua Tomte/tools/bugfiles.lua` from the AddOns folder (or `test_bugreport` fails).
- Don't "simplify" secure buttons, `InCombatLockdown()` guards, taint workarounds, secret-value checks or `C_Timer`
  deferrals that have a written reason.
- No commit before the user has checked the phase in game. Then commit with the GitHub noreply identity already in the
  repo config, and add a CHANGELOG **Unreleased** line only for changes a player notices.
- Line numbers below are from 2026-10-11 and shift as phases land: always find code by the quoted name/content.

## Review Focus

1. **12.1.5 client (deprecation fallbacks gone):** with `/console loadDeprecationFallbacks 0` nothing in Tomte errors.
   Pinned by Task 1's in-game step and its grep step.
2. **A module turned off mid-session, then on again (event merges):** handlers of an "off" owner must not run, and
   an owner's unregister must not silence another owner's events. Pinned by Task 4's bus tests (`Unwatch` keeps other
   owners, `UnwatchAll` per owner, handler of unwatched owner not called).
3. **Saved variables from an old version (migrations):** a TomteDB missing whole module tables, or with the old keys,
   migrates without error and only once. Pinned by Task 3's tests (nil module tables, flag set/unset, re-run no-op).
4. **Money and counts at the edges:** 0, nil, values under 1 gold, millions, negative (only the minus sign case).
   Pinned by Task 2's `test_format.lua`.
5. **File splits loading in the right order:** a helper captured at file load from a file that now loads later is
   nil. Pinned in Tasks 9-13 by the load-order step and a `luac -l` global-read check for each new file.

---

## Phase 0: commit the cleanup pass

### Task 0: Commit the health pass after the in-game check

**Files:** none changed.

- [ ] **Step 1:** User runs the in-game check list from the conversation (36 items) and reports BugSack output.
- [ ] **Step 2:** Fix anything reported (systematic-debugging skill), re-run tests.
- [ ] **Step 3:** Commit:

```bash
git -C "D:/World of Warcraft/_retail_/Interface/AddOns/Tomte" add -A
git -C "D:/World of Warcraft/_retail_/Interface/AddOns/Tomte" commit -m "Codebase health pass: headers, comments, dead code, shared helpers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Phase 1: legacy APIs (urgent: 12.1.5 removes `GetCoinTextureString`)

### Task 1: Replace every deprecated global with its C_ API

**Files:**
- Modify: `Modules/Alts/Send.lua` (GetCoinTextureString ~645, GetAutoCompleteRealms ~77, comment ~66, `C_AddOns` guard ~811)
- Modify: `Panel/Home.lua` (~583 `ns.Alts_Gold and ... or GetCoinTextureString(...)`)
- Modify: `Modules/Fishing/Key.lua` (~126 IsPlayerSpell, ~137 C_PetBattles guard)
- Modify: `Modules/Travel/Router.lua` (~113-118 IsPlayerSpell fallback)
- Modify: `Modules/Rogue/Rogue.lua` (~44-47 IsPlayerSpell twice, ~15-16/78-79 GetSpecialization*)
- Modify: `Modules/Social/Whispers.lua` (~199 BNSendWhisper, ~206 SendChatMessage)
- Modify: `Modules/AFK/AFK.lua` (~137 SendChatMessage, ~50 C_PetBattles guard)
- Modify: `Modules/Chat/Filter.lua` (~147-160 ChatFrame_Add/RemoveMessageEventFilter)
- Modify: `Modules/Chat/Tabs.lua` (~46 NUM_CHAT_WINDOWS)
- Modify: `Panel/Widgets.lua` (~66-69 UI.InsertLink's ChatEdit_InsertLink fallback)
- Modify: `Modules/Achievements/Achievements.lua` (~198-210 OpenAchievementFrameToAchievement branch)
- Modify: `Modules/Combat/PetHealth.lua` (~25-26), `Modules/Gear/Gear.lua` (~12-13, 43, 51, 772), `Modules/Hunter/Checks.lua` (~11-19, 61-62): GetSpecialization*
- Modify: `Modules/Moments/Moments.lua` (~76 C_PetBattles guard), `Modules/Delves/Scan.lua` (~111 GetDelvesForMap guard)

**Interfaces:** Produces nothing new. Replacements (all exist in 12.1.0 build 69933, verified against wow-ui-source live):

| Legacy | Replacement |
|---|---|
| `GetCoinTextureString(c)` | `C_CurrencyInfo.GetCoinTextureString(c)` |
| `IsPlayerSpell(id)` | `C_SpellBook.IsSpellKnown(id)` |
| `SendChatMessage(msg, type, lang, target)` | `C_ChatInfo.SendChatMessage(msg, type, lang, target)` |
| `BNSendWhisper(id, text)` | `C_BattleNet.SendWhisper(id, text)` (returns bool) |
| `ChatFrame_AddMessageEventFilter` / `Remove...` | `ChatFrameUtil.AddMessageEventFilter` / `RemoveMessageEventFilter` |
| `ChatEdit_InsertLink(link)` | `ChatFrameUtil.InsertLink(link)` |
| `NUM_CHAT_WINDOWS` | `Constants.ChatFrameConstants.MaxChatWindows` |
| `GetAutoCompleteRealms()` | `C_AutoComplete.GetAutoCompleteRealms()` |
| `OpenAchievementFrameToAchievement(id)` | `ShowAchievementFrameForAchievement(id)` |
| `GetSpecialization()` / `GetSpecializationInfo(i)` | `C_SpecializationInfo.GetSpecialization()` / `.GetSpecializationInfo(i)` |

- [ ] **Step 1: Verify each replacement once more** on `https://warcraft.wiki.gg/wiki/API_<Name>` (WebFetch) and note
  any argument/return difference in the commit message. Known: `C_BattleNet.SendWhisper` returns a bool; Whispers'
  existing `sent == false` check only works with it.
- [ ] **Step 2: Replace each site.** Pattern for a fallback (`Whispers.lua`):

```lua
-- before
local send = C_BattleNet.SendWhisper or BNSendWhisper
local sent = send(accountID, text)
-- after
local sent = C_BattleNet.SendWhisper(accountID, text)
```

  Pattern for a straight rename (`Rogue.lua`, upvalues at file top):

```lua
-- before
local GetSpecialization, GetSpecializationInfo = GetSpecialization, GetSpecializationInfo
-- after
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
```

  For Gear.lua, Checks.lua and PetHealth.lua, which already upvalue from `C_SpecializationInfo`, only fix the remaining
  bare calls. Delete the comments that explain the deprecation fallback (Rogue.lua, Checks.lua) and replace them with
  nothing: the C_ name speaks for itself. In `Panel/Home.lua` make the money line `ns.Alts_Gold(GetMoney())` (Alts/Data.lua
  always loads; Task 2 renames it). In `Achievements.lua` call `ShowAchievementFrameForAchievement(id)` directly and
  drop the comment about the older name. Remove the existence guards for APIs that always exist in 12.1
  (`C_PetBattles`, `C_AreaPoiInfo.GetDelvesForMap`, `C_AddOns`) only where the guard is a bare `X and X.Y` check.
- [ ] **Step 3: Grep for leftovers** (must print nothing):

```bash
cd "/d/World of Warcraft/_retail_/Interface/AddOns/Tomte" && grep -rnwE 'GetCoinTextureString|IsPlayerSpell|BNSendWhisper|ChatFrame_AddMessageEventFilter|ChatFrame_RemoveMessageEventFilter|ChatEdit_InsertLink|NUM_CHAT_WINDOWS|GetAutoCompleteRealms|OpenAchievementFrameToAchievement' --include=*.lua . | grep -v 'C_CurrencyInfo.GetCoinTextureString\|C_AutoComplete.GetAutoCompleteRealms'; grep -rnE '(^|[^._A-Za-z])(SendChatMessage|GetSpecialization|GetSpecializationInfo)\(' --include=*.lua Modules Panel Core
```

- [ ] **Step 4: Run all unit tests** (loop in Global Constraints). Expected: no FAIL lines.
- [ ] **Step 5: In-game check (user).** `/console loadDeprecationFallbacks 0`, `/reload`. Then: send dock at a mailbox
  (postage line), Home hero gold, Fishing key, a Rogue poison check, `/way` to another continent with portals on,
  whisper a friend and a BattleTag friend, AFK auto-reply, Trade Filter on, Chat Tabs restore, shift-click link,
  open an achievement from Almost Done, Gear tooltip, Hunter pet check, Pet Health bar. BugSack must stay empty.
  Afterwards `/console loadDeprecationFallbacks 1`.
- [ ] **Step 6: Commit after confirmation.** CHANGELOG line: `- Ready for patch 12.1.5: Tomte no longer uses game functions Blizzard is removing (the mailbox's postage line would have broken).`

---

## Phase 2: one formatter for money, counts and "ago"

### Task 2: `Core/Format.lua` (pure) and its callers

**Files:**
- Create: `Core/Format.lua`, `tests/test_format.lua`
- Modify: `Tomte.toc` (insert `Core/Format.lua` right before `Core/Core.lua`), then `lua Tomte/tools/bugfiles.lua`
- Modify (callers): `Modules/AFK/Data.lua`, `Modules/Travel/Data.lua`, `Modules/Weekly/FactionData.lua`,
  `Modules/WorldQuests/Data.lua`, `Modules/Alts/Data.lua`, `Modules/Recap/Scene.lua`, `Modules/Recap/SessionsPage.lua`,
  `Modules/Recap/Recap.lua`, `Panel/Home.lua`, `Modules/Gather/Gather.lua`, `Modules/Social/Data.lua`,
  `Modules/Recent/Data.lua`, `Modules/Teleports/Data.lua`
- Modify (tests that load those files, add `Core/Format.lua` first): `tests/test_afk.lua`, `test_alts.lua`,
  `test_list.lua`, `test_travel.lua`, `test_wq.lua`, `test_factions.lua`, `test_social.lua`, `test_recent.lua`,
  `test_teleports.lua`

**Interfaces:**
- Produces: `ns.Thousands(n) -> string`, `ns.Gold(copper) -> string`, `ns.Price(copper) -> string`,
  `ns.SignedGold(copper) -> string`, `ns.Coins(copper, detailed, icons) -> string`, `ns.Ago(seconds) -> string`,
  `ns.Clock(seconds) -> string`. Kept as aliases so the ~50 call sites need no edit: `ns.Alts_Gold = ns.Gold`,
  `ns.Alts_Price = ns.Price`, `ns.AFK_MoneyText = ns.Coins`, `ns.Social_Ago = ns.Ago`, `ns.Recent_Ago = ns.Ago`.
- Consumes: nothing (pure Lua, `math` and `string` only).

- [ ] **Step 1: Write the failing test** `tests/test_format.lua` (expected strings are the ones today's tests assert):

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_format.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)

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

test("Thousands groups digits and floors", function()
	eq(ns.Thousands(0), "0")
	eq(ns.Thousands(nil), "0")
	eq(ns.Thousands(999), "999")
	eq(ns.Thousands(1000), "1,000")
	eq(ns.Thousands(1234567), "1,234,567")
	eq(ns.Thousands(1234.9), "1,234")
end)
test("Thousands keeps the minus sign outside the groups", function()
	eq(ns.Thousands(-123), "-123")
	eq(ns.Thousands(-1234), "-1,234")
end)
test("Gold is whole gold with a g", function()
	eq(ns.Gold(1230000000), "123,000g")
	eq(ns.Gold(1230050000), "123,005g")
	eq(ns.Gold(nil), "0g")
	eq(ns.Gold(9999), "0g")
end)
test("Price falls back to silver and copper", function()
	eq(ns.Price(120000), "12g")
	eq(ns.Price(4500), "45s")
	eq(ns.Price(80), "80c")
	eq(ns.Price(nil), "0c")
end)
test("SignedGold", function()
	eq(ns.SignedGold(nil), "")
	eq(ns.SignedGold(0), "+0g")
	eq(ns.SignedGold(-25000000), "-2,500g")
	eq(ns.SignedGold(25000000), "+2,500g")
end)
test("Coins matches the AFK money text", function()
	eq(ns.Coins(500000000), "50,000g")
	eq(ns.Coins(12345678), "1,234g")
	eq(ns.Coins(5612), "56s 12c")
	eq(ns.Coins(7), "7c")
	eq(ns.Coins(0), "0c")
	eq(ns.Coins(12345678, true), "1,234g 56s")
end)
test("Ago", function()
	eq(ns.Ago(0), "now")
	eq(ns.Ago(nil), "now")
	eq(ns.Ago(-5), "now")
	eq(ns.Ago(300), "5m")
	eq(ns.Ago(7200), "2h")
	eq(ns.Ago(172800), "2d")
end)
test("Clock", function()
	eq(ns.Clock(0), "0s")
	eq(ns.Clock(59), "59s")
	eq(ns.Clock(61), "1:01")
	eq(ns.Clock(3601), "1:00:01")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
```

  Before writing it, open `tests/test_afk.lua:83-97`, `test_alts.lua:164-171`, `test_social.lua:195-198`,
  `test_recent.lua:92-95`, `test_teleports.lua:110-113`, `test_travel.lua:48-52` and copy the exact input/expected
  pairs they use into the tests above if any differ from these (they are the ground truth).
- [ ] **Step 2: Run it:** `lua Tomte/tests/test_format.lua`. Expected: error "cannot open Tomte/Core/Format.lua".
- [ ] **Step 3: Write `Core/Format.lua`:**

```lua
local addonName, ns = ...

-- Number, money and time text shared by every module. Pure Lua (unit-tested in tests/test_format.lua); loads before
-- Core.lua so data files can use it at file load. Outputs match what each module printed before it moved here.

local floor, abs, max = math.floor, math.abs, math.max

-- 1234567 -> "1,234,567". nil -> "0". Floors, and keeps a minus sign outside the groups ("-1,234").
function ns.Thousands(n)
	local sign, digits = tostring(floor(n or 0)):match("^(-?)(%d+)$")
	local head = (#digits - 1) % 3 + 1
	return sign .. digits:sub(1, head) .. digits:sub(head + 1):gsub("%d%d%d", ",%0")
end

-- Whole gold: 1234567890 copper -> "123,456g".
function ns.Gold(copper)
	return ns.Thousands(floor((copper or 0) / 10000)) .. "g"
end
```

  Then move these bodies verbatim and rename only the function name:
  - `ns.Alts_Price` (Modules/Alts/Data.lua, "Alts_Price") -> `function ns.Price(copper)`; inside, `ns.Alts_Gold` -> `ns.Gold`.
  - `ns.AFK_MoneyText` (Modules/AFK/Data.lua) -> `function ns.Coins(copper, detailed, icons)`; inside, its local
    `Thousands` -> `ns.Thousands`.
  - `ns.Recent_Ago` (Modules/Recent/Data.lua, the nil/negative-safe one) -> `function ns.Ago(seconds)`.
  - The "Ns" / "m:ss" / "h:mm:ss" body shared by `Tp_FormatCooldown` and `Way_FormatArrival`, without their rounding
    -> `function ns.Clock(seconds)` (takes whole seconds).

  And add:

```lua
-- "+2,500g" / "-2,500g"; "" for nil. For gold differences (session recap, Home).
function ns.SignedGold(copper)
	if not copper then
		return ""
	end
	return (copper < 0 and "-" or "+") .. ns.Gold(abs(copper))
end
```

- [ ] **Step 4: Run** `lua Tomte/tests/test_format.lua`. Expected: "all passed".
- [ ] **Step 5: Switch callers.**
  - Delete the local `Thousands` in AFK/Data.lua, Travel/Data.lua, Weekly/FactionData.lua, WorldQuests/Data.lua and
    the inline loop in Alts/Data.lua; call `ns.Thousands(...)` at runtime (not captured at load).
  - Alts/Data.lua: delete `ns.Alts_Gold` / `ns.Alts_Price` bodies; add `ns.Alts_Gold = ns.Gold` and
    `ns.Alts_Price = ns.Price` with a one-line comment. AFK/Data.lua: `ns.AFK_MoneyText = ns.Coins`.
    Social/Data.lua and Recent/Data.lua: `ns.Social_Ago = ns.Ago`, `ns.Recent_Ago = ns.Ago`.
  - `ns.WQ_FormatGold(copper)`: body becomes `return floor((copper or 0) / 10000) < 1 and "<1g" or ns.Gold(copper)`
    (check the original `<1g` threshold and keep it exactly).
  - `Signed` in Recap/SessionsPage.lua and Panel/Home.lua, and the inline sign in Recap/Recap.lua (~380): use
    `ns.SignedGold`. Leave Recap/Scene.lua's `Signed` (coin icons, unsigned zero) as is.
  - Teleports/Data.lua `Tp_FormatCooldown` and Travel/Data.lua `Way_FormatArrival`: keep their own rounding (ceil /
    round, nil for negative) and return `ns.Clock(rounded)`.
  - Gather/Gather.lua: `ns.Gather_Money = ns.Gold` (it was an alias of Alts_Gold).
  - Add `assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)` as the FIRST loadfile in each test listed under Files.
- [ ] **Step 6: Run all unit tests.** Expected: no FAIL lines. `grep -rn 'gsub("%%d%%d%%d"\|reverse():gsub' --include=*.lua Modules` prints nothing.
- [ ] **Step 7: In-game check (user):** Home hero gold and session change, Alts roster gold and warband line, Crafting
  value lines, List shopping prices, Recap card and Sessions page (+/- gold), World quests gold rewards, Gathering run
  values, AFK screen money, Teleports cooldowns, waypoint arrival time, Faction paragon numbers, Whispers inbox "5m".
  All text identical.
- [ ] **Step 8: Commit after confirmation** (no CHANGELOG line: not visible).

---

## Phase 3: migrations in Core

### Task 3: `Core/Migrations.lua` with the in-module one-offs moved in

**Files:**
- Create: `Core/Migrations.lua`, `tests/test_migrations.lua`
- Modify: `Core/Core.lua` (delete the local `MIGRATIONS` list and its comment; `ns.RunMigrations(db, ns.MIGRATIONS)`)
- Modify: `Tomte.toc` (insert `Core/Migrations.lua` right before `Core/Core.lua`, after `Core/Format.lua`), bugfiles
- Modify: `Core/Session.lua` (remove the `ns.Session_Migrate(db)` call in `ns.Session_Init`)
- Modify: `Modules/NextUp/NextUp.lua` (remove the `placedUnderChars` block in `init`)
- Modify: `Modules/Travel/Waypoint.lua` (remove the `cardDistance == 325` block in `init`)
- Modify: `Modules/Achievements/Scan.lua` (remove the "Caches saved by older versions may lack topID" patch in `ns.Ach_LoadCache`)
- Modify: `Modules/Flight/Data.lua` (remove the `if not flights then` legacy branch in `ns.RecordPace`)

**Interfaces:**
- Produces: `ns.MIGRATIONS` (array of `function(db)`), run by the existing `ns.RunMigrations(db, migrations)`.
- Consumes at runtime: `ns.Setup_Migrate` (Core/Setup.lua), `ns.Moments_MigrateAtMax` (Modules/Moments/Data.lua),
  `ns.Session_Migrate` (Core/SessionData.lua). All loaded by the time ADDON_LOADED runs the list.

Stay where they are (need live game data, can't run before defaults): `Gear_MigrateHinted` (class spec IDs, per
character) and Session.lua's name/class re-fill (`UnitName`). Write one comment line in `Core/Migrations.lua` naming
them so the next reader knows.

- [ ] **Step 1: Pin today's Flight legacy branch first** (so the migration's difference is known). Add to
  `tests/test_flight_data.lua` a test that records one flight on a pace saved as `{ seconds = 1000, distance = 10 }`
  (no `flights`) and asserts `flights == 10` afterwards and the resulting `seconds/distance` ratio. Run it: PASS on the
  current code. Record the numbers in the commit message.
- [ ] **Step 2: Write the failing test** `tests/test_migrations.lua`:

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_migrations.lua
local ns = { errorHandler = function(err) print("migration error: " .. tostring(err)) end }
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Setup.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/SessionData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Moments/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Migrations.lua"))("Tomte", ns)

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
test("migrations don't run twice", function()
	local db = { schema = #ns.MIGRATIONS, way = { cardDistance = 325 } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.way.cardDistance, 325)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
```

  Before running: confirm the saved shapes against the code (`db.next.placement` in NextUp.lua, `db.way.cardDistance`
  in Waypoint.lua, `db.ach.cache[guid].records[i].topID/category` in Scan.lua, `db.flight.paces[mapID]` and
  `PACE_WINDOW` in Flight/Data.lua) and fix the test's keys if any differ.
- [ ] **Step 3: Run it.** Expected: error "cannot open Tomte/Core/Migrations.lua".
- [ ] **Step 4: Write `Core/Migrations.lua`:** copy migrations 1-3 verbatim from Core.lua's `MIGRATIONS` (with their
  comments), then append:

```lua
	-- 4: the AFK module kept the play session until the Session recap took it over.
	function(db)
		ns.Session_Migrate(db)
	end,
	-- 5: NextUp's old default placement "column" became "characters". placedUnderChars marked users the old in-module
	-- fix had already handled (their "column" is a choice).
	function(db)
		local nextDB = db.next
		if type(nextDB) ~= "table" then
			return
		end
		if not nextDB.placedUnderChars and nextDB.placement == "column" then
			nextDB.placement = "characters"
		end
		nextDB.placedUnderChars = nil
	end,
	-- 6: Waypoints: 325 yards was an old default that put the card too far out.
	function(db)
		if type(db.way) == "table" and db.way.cardDistance == 325 then
			db.way.cardDistance = 110
		end
	end,
	-- 7: Almost Done caches saved before records kept topID: dropped, the login scan rebuilds them.
	function(db)
		local cache = type(db.ach) == "table" and db.ach.cache
		if type(cache) ~= "table" then
			return
		end
		for guid, entry in pairs(cache) do
			local records = type(entry) == "table" and entry.records
			if type(records) == "table" then
				for _, record in pairs(records) do
					if type(record) == "table" and record.category and record.topID == nil then
						cache[guid] = nil
						break
					end
				end
			end
		end
	end,
	-- 8: Flight paces saved as lifetime totals (before the PACE_WINDOW of 10 flights) count as 9 flights, so the next
	-- flight starts pulling the average right away. Flight/Data.lua's PACE_WINDOW - 1.
	function(db)
		local paces = type(db.flight) == "table" and db.flight.paces
		if type(paces) ~= "table" then
			return
		end
		for _, pace in pairs(paces) do
			if type(pace) == "table" and pace.flights == nil then
				pace.flights = 9
			end
		end
	end,
```

  File header: `-- Settings migrations, in order, each run once per SavedVariables (TomteDB.schema, ns.RunMigrations in
  Modules.lua) before defaults are merged. Only add to the end. A migration must cope with missing tables. Pure
  (tests/test_migrations.lua). Two fix-ups need live game data and stay in their modules: Gear_MigrateHinted (Gear) and
  Session.lua's name/class re-fill.` Open with `ns.MIGRATIONS = {` and close with `}`.
- [ ] **Step 5: Remove the moved code** from Core.lua (local list; call `ns.RunMigrations(db, ns.MIGRATIONS)`),
  Session.lua (`Session_Migrate` call), NextUp.lua, Waypoint.lua, Scan.lua and Flight/Data.lua (the `if not flights`
  branch: `flights` is now always set; keep a plain `flights = pace.flights or 0` only if the code needs a number for a
  brand-new pace: read the function and keep new-pace behavior identical).
- [ ] **Step 6: Run** `lua Tomte/tests/test_migrations.lua` then all tests. Expected: all pass. Update the Flight test from
  Step 1 to the migrated shape (pace with `flights = 9` recorded once) and note the ratio difference in the commit.
- [ ] **Step 7: In-game check (user):** `/reload` on an existing install: Next up stays where it was, Waypoint card
  distance slider unchanged (try setting 325, reload, it stays 325 now), Almost Done list shows within seconds, a flight
  timer still estimates. BugSack empty.
- [ ] **Step 8: Commit after confirmation.** CHANGELOG: `- Waypoints: a card distance of 325 yards no longer resets to 110 at every login.`

---

## Phase 4: one event frame per module

### Task 4: `Core/Events.lua`, an owner-aware event bus

**Files:**
- Create: `Core/Events.lua`, `tests/test_eventbus.lua`
- Modify: `Tomte.toc` (insert `Core/Events.lua` after `Core/Migrations.lua`, before `Core/Core.lua`), bugfiles

**Interfaces (produces, used by Tasks 5-8):**
- `ns.NewEvents() -> bus`. `bus.frame` is the WoW frame.
- `bus:On(owner, event, fn)`: attach `fn(bus, ...)` for `event`. Call at file load; handlers run in attach order.
- `bus:Watch(owner, event, unit1, unit2)`: the owner wants the event; first watcher registers it on the frame
  (`RegisterUnitEvent` when a unit is given).
- `bus:Unwatch(owner, event)`, `bus:UnwatchAll(owner)`: the frame unregisters an event only when no owner watches it.
- `bus:Watching(owner, event) -> bool`.
- `bus:TryWatch(owner, event) -> bool`: like Watch, but `pcall`s the register (for events missing in this client).

- [ ] **Step 1: Write the failing test** `tests/test_eventbus.lua`:

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_eventbus.lua
local registered = {}
local frames = {}
_G.CreateFrame = function()
	local f = { scripts = {} }
	function f:SetScript(name, fn) self.scripts[name] = fn end
	function f:RegisterEvent(e) registered[e] = "all" end
	function f:RegisterUnitEvent(e, u1, u2) registered[e] = u1 .. (u2 and ("," .. u2) or "") end
	function f:UnregisterEvent(e) registered[e] = nil end
	frames[#frames + 1] = f
	return f
end
local ns = {}
assert(loadfile("Tomte/Core/Events.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	for k in pairs(registered) do registered[k] = nil end
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
local function Fire(bus, event, ...)
	bus.frame.scripts.OnEvent(bus.frame, event, ...)
end

test("handlers run in attach order, only for watching owners", function()
	local bus, calls = ns.NewEvents(), {}
	bus:On("a", "E", function(self, x) calls[#calls + 1] = "a" .. x end)
	bus:On("b", "E", function(self, x) calls[#calls + 1] = "b" .. x end)
	bus:Watch("a", "E")
	Fire(bus, "E", 1)
	eq(table.concat(calls, " "), "a1")
	bus:Watch("b", "E")
	Fire(bus, "E", 2)
	eq(table.concat(calls, " "), "a1 a2 b2")
end)
test("one owner's unwatch keeps the event for another", function()
	local bus = ns.NewEvents()
	bus:On("a", "E", function() end)
	bus:On("b", "E", function() end)
	bus:Watch("a", "E")
	bus:Watch("b", "E")
	bus:Unwatch("a", "E")
	eq(registered.E, "all")
	bus:Unwatch("b", "E")
	eq(registered.E, nil)
end)
test("UnwatchAll only drops that owner", function()
	local bus = ns.NewEvents()
	bus:Watch("a", "E")
	bus:Watch("a", "F")
	bus:Watch("b", "F")
	bus:UnwatchAll("a")
	eq(registered.E, nil)
	eq(registered.F, "all")
	eq(bus:Watching("a", "F"), false)
	eq(bus:Watching("b", "F"), true)
end)
test("unit events", function()
	local bus = ns.NewEvents()
	bus:Watch("a", "UNIT_AURA", "player")
	eq(registered.UNIT_AURA, "player")
end)
test("handlers get the bus as self", function()
	local bus, seen = ns.NewEvents(), nil
	bus:On("a", "E", function(self) seen = self end)
	bus:Watch("a", "E")
	Fire(bus, "E")
	eq(seen, bus)
end)
test("an owner unwatching itself inside its handler is fine", function()
	local bus, n = ns.NewEvents(), 0
	bus:On("a", "E", function(self) n = n + 1; self:Unwatch("a", "E") end)
	bus:Watch("a", "E")
	Fire(bus, "E")
	Fire(bus, "E")
	eq(n, 1)
end)
test("TryWatch survives an unknown event", function()
	local bus = ns.NewEvents()
	bus.frame.RegisterEvent = function() error("unknown event") end
	eq(bus:TryWatch("a", "NOPE"), false)
	eq(bus:Watching("a", "NOPE"), false)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
```

- [ ] **Step 2: Run it.** Expected: "cannot open Tomte/Core/Events.lua".
- [ ] **Step 3: Write `Core/Events.lua`:**

```lua
local addonName, ns = ...

-- One event frame per module, shared by its files. Each file is an owner: it attaches handlers once (On, at file
-- load) and says when it wants an event (Watch / Unwatch, from its Start/Stop). The frame registers an event while
-- any owner watches it and calls only the watching owners' handlers, in attach order (TOC order across files).
-- Unit-tested with a CreateFrame stub (tests/test_eventbus.lua).

function ns.NewEvents()
	local frame = CreateFrame("Frame")
	local handlers = {} -- [event] = { { owner = owner, fn = fn }, ... }
	local watchers = {} -- [event] = { [owner] = true }
	local bus = { frame = frame }

	frame:SetScript("OnEvent", function(_, event, ...)
		local list, watching = handlers[event], watchers[event]
		if not list or not watching then
			return
		end
		for i = 1, #list do
			local h = list[i]
			if watching[h.owner] then
				h.fn(bus, ...)
			end
		end
	end)

	function bus:On(owner, event, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], { owner = owner, fn = fn })
	end

	local function Count(event)
		local n = 0
		for _ in pairs(watchers[event] or {}) do
			n = n + 1
		end
		return n
	end

	function bus:Watch(owner, event, unit1, unit2)
		if Count(event) == 0 then
			if unit1 then
				frame:RegisterUnitEvent(event, unit1, unit2)
			else
				frame:RegisterEvent(event)
			end
		end
		watchers[event] = watchers[event] or {}
		watchers[event][owner] = true
	end

	-- For events this client may not have: false when the frame refused it.
	function bus:TryWatch(owner, event)
		local ok = pcall(bus.Watch, bus, owner, event)
		if not ok and watchers[event] then
			watchers[event][owner] = nil
		end
		return ok
	end

	function bus:Unwatch(owner, event)
		local watching = watchers[event]
		if not watching or not watching[owner] then
			return
		end
		watching[owner] = nil
		if Count(event) == 0 then
			frame:UnregisterEvent(event)
		end
	end

	function bus:UnwatchAll(owner)
		for event in pairs(watchers) do
			bus:Unwatch(owner, event)
		end
	end

	function bus:Watching(owner, event)
		return watchers[event] ~= nil and watchers[event][owner] == true
	end

	return bus
end
```

- [ ] **Step 4: Run** the bus test, then all tests. Expected: all pass.
- [ ] **Step 5: Commit together with Task 5** (the bus alone changes nothing in game).

### Task 5: Core, Gear, Recap, Delves, Gather, Chat Tabs onto the bus

Rules for every merge (apply in Tasks 5-7):
- The file loading first in the TOC creates the bus and exports it: `ns.<Prefix>_Events = ns.NewEvents()`. Later files
  capture it at file load: `local events = ns.<Prefix>_Events`.
- Each file picks one owner string (its file name, e.g. `"reveal"`). Every `function events:EVENT(...)` becomes
  `events:On(OWNER, "EVENT", function(self, ...) ... end)` with the same body, or keep the named function and attach it:
  `events:On(OWNER, "EVENT", Handler)`.
- `events:RegisterEvent(e)` -> `events:Watch(OWNER, e)`; `RegisterUnitEvent(e, u)` -> `Watch(OWNER, e, u)`;
  `pcall(events.RegisterEvent, events, e)` -> `events:TryWatch(OWNER, e)`;
  `UnregisterEvent(e)` -> `Unwatch(OWNER, e)`; `UnregisterAllEvents()` -> `UnwatchAll(OWNER)`.
- `self:EVENT()` calls between handlers become calls of the local function.
- Order inside a module = attach order = TOC order. Where the inventory lists an order dependency, check the TOC gives
  it, and keep any existing `C_Timer.After(0)` that documents the dependency.
- OnUpdate-only ticker frames and override-binding owner frames are not touched.

**Files and owners (from the 2026-10-11 inventory):**

| Module | Bus created in | Export | Owners (TOC order) | Must keep |
|---|---|---|---|---|
| Core | `Core/Core.lua` (replace `f`) | `ns.Core_Events` | `"core"`, `"session"` (Core/Session.lua) | Core's PEW runs before Session's, both before any module (Core.lua and Session.lua load before Modules). Core's one-shot PEW: `Unwatch("core", ...)` not the frame. Session.lua's `self:PLAYER_XP_UPDATE("player")` -> local call. SafeTrack's temporary REGEN watch uses owner `"safetrack"`. |
| Gear | `Modules/Gear/Gear.lua` | `ns.Gear_Events` | `"gear"`, `"reveal"` (Reveal.lua loads after Gear.lua) | PEW, BAG_UPDATE_DELAYED, PLAYER_EQUIPMENT_CHANGED: gear before reveal. Keep Reveal's `C_Timer.After(0)`. UNIT_INVENTORY_CHANGED stays a player unit event. |
| Recap | `Modules/Recap/Track.lua` (TOC 157, before Recap.lua) | `ns.Recap_Events` | `"track"`, `"recap"` | `ticker` (OnUpdate) untouched. |
| Delves | `Modules/Delves/Scan.lua` | `ns.Delves_Events` | `"read"`, `"entrance"`, `"delves"` | Delves.lua's alias handlers (`events.X = refreshScan`) attach as `On("delves", "X", refreshScan)`; refreshScan receives the bus as self, which it ignores (check). PLAYER_SPECIALIZATION_CHANGED stays a player unit event. |
| Gather | `Modules/Gather/Detect.lua` | `ns.Gather_Events` | `"detect"`, `"tracker"`, `"gather"` | Tracker's always-on PET_BATTLE_* and PEW stay watched while the module is off (they are watched in `GatherTracker_Init`). |
| Chat Tabs | `Modules/Chat/Tabs.lua` (own bus, local) | none | `"login"`, `"tabs"` | `loginWatch` becomes owner `"login"` watching PEW at file load and unwatching itself; `Deactivate` does `UnwatchAll("tabs")` only. |

- [ ] **Step 1:** Convert Core (Core.lua, Session.lua). Run all tests (test_bugreport reads Core.lua as text: still green).
- [ ] **Step 2:** Convert Gear (Gear.lua, Reveal.lua). Run all tests.
- [ ] **Step 3:** Convert Recap, Delves, Gather, Chat Tabs. Run all tests.
- [ ] **Step 4: Check no stray frame API calls remain** on converted buses:

```bash
cd "/d/World of Warcraft/_retail_/Interface/AddOns/Tomte" && grep -nE 'events:(Register|Unregister)|self:(Register|Unregister)(All)?Events?' Core/Core.lua Core/Session.lua Modules/Gear/Gear.lua Modules/Gear/Reveal.lua Modules/Recap/*.lua Modules/Delves/*.lua Modules/Gather/*.lua Modules/Chat/Tabs.lua
```

  Expected: nothing (Raids.lua's calls on Blizzard's EncounterJournal are not in this list).
- [ ] **Step 5: In-game check (user):** login and `/reload` (Session recap counts the session, Home week loads);
  Gear tooltip after equipping and after looting gear (upgrade toast/Reveal); `/camp` then cancel (Recap logout card);
  loot a rare (Recap log); Delves page and the entrance card; gather a node and enter a pet battle (tracker hides);
  Chat Tabs after login. Turn Gear, Recap, Delves, Gather off and on again in settings: no errors, features stop and
  resume. BugSack empty.
- [ ] **Step 6: Commit Tasks 4+5 after confirmation** (no CHANGELOG line).

### Task 6: Travel and Fishing onto the bus

**Files:** `Modules/Travel/Guard.lua` (creates `ns.Way_Events`, TOC before Router and Waypoint), `Router.lua`,
`Waypoint.lua`; `Modules/Fishing/Helpers.lua` (creates `ns.Fishing_Events`), `Key.lua`, `Fishing.lua`.

| Module | Owners (TOC order) | Must keep |
|---|---|---|
| Travel | `"guard"`, `"router"`, `"way"` | Router now runs before Waypoint for shared events (USER_WAYPOINT_UPDATED, SUPER_TRACKING_CHANGED, ZONE_CHANGED_NEW_AREA, PEW). Safe only because every Router handler defers (`CheckSoon` C_Timer.After(0), first-PEW After(0)): verify each Router handler still defers before converting; if one doesn't, attach Router's handlers after Waypoint's by creating the bus in Waypoint.lua instead and moving Waypoint before Router in the TOC. Router's own on/off (`WayRouter_Toggle`, portals option) = `Watch/UnwatchAll("router")`. The throwaway PLAYER_LOGIN frame in `ClaimWay` becomes owner `"login"` (watch PLAYER_LOGIN, unwatch itself in the handler); toggle-off must not unwatch `"login"`. `ticker` frames untouched. |
| Fishing | `"helpers"`, `"key"`, `"notice"` | Helpers' PEW expects Key's PEW first (comment and `C_Timer.After(0)` in Helpers.lua): keep the After(0). Key's toggle-off `UnregisterAllEvents()` then re-register REGEN becomes `UnwatchAll("key")` then `Watch("key", "PLAYER_REGEN_ENABLED")`. Helpers' temporary REGEN watch/unwatch is per owner now, so Key's permanent REGEN survives. `keyEvents` stays the override-binding owner frame: keep a separate plain frame for `SetOverrideBinding` (`local bindingOwner = CreateFrame("Frame")`) and move only event code to the bus. The OnUpdate `waiter` frame is untouched. |

- [ ] **Step 1:** Convert Travel. Run all tests.
- [ ] **Step 2:** Convert Fishing. Run all tests. Grep step as in Task 5 Step 4 for these files.
- [ ] **Step 3: In-game check (user):** `/way 50 50`, a portal route (portals on), turn portals off and on, guard
  pins at a city guard's gossip; Fishing key cast/reel/loot, `/reload` while the bobber is out, combat while fishing
  (bindings come back after), the Angleur notice if Angleur is installed; turn both modules off/on. BugSack empty.
- [ ] **Step 4: Commit after confirmation.**

### Task 7: Alts onto the bus

**Files:** `Modules/Alts/Collect.lua` (creates `ns.Alts_Events`; first Alts file with a frame), `CraftTab.lua`,
`Send.lua`, `List.lua`.

Owners (TOC order): `"collect"`, `"mats"` (CraftTab), `"send"`, `"list"`. Must keep:
- `pcall(RegisterEvent)` sites (CraftTab `WatchMaterials`, List `AltsList_Start`) -> `TryWatch`.
- Collect's temporary PLAYER_REGEN_ENABLED (Refresh in combat) -> `Watch/Unwatch("collect", ...)`; List's permanent
  REGEN survives.
- Syndicator callbacks: CraftTab and List each register `BagCacheUpdate`, `MailCacheUpdate`, `WarbandBankCacheUpdate`
  with the frame as owner. Syndicator's CallbackRegistry stores per owner, so give each its own owner table
  (`local matsOwner, listOwner = {}, {}`) and pass those instead of the frame. Unregister with the same table.
- List.lua's `events.baganator` / `events.syndicator` flags become file locals.
- `matsEvents` today stays registered after the module turns off: keep that (watch in `WatchMaterials`, never
  unwatch) so behavior is unchanged; add a comment that it's deliberate (clearing a cache is harmless).

- [ ] **Step 1:** Convert, run all tests, grep step for `Modules/Alts/*.lua`.
- [ ] **Step 2: In-game check (user):** open a profession (recipes scanned), learn a recipe, Crafting tab material
  counts after a bank visit and after mailing items, the List tab tracker while crafting, combat during a list update,
  the mailbox send dock, Syndicator counts if installed. Turn Alts off/on. BugSack empty.
- [ ] **Step 3: Commit after confirmation.**

### Task 8: The one-shot waiter frames

**Files:** `Modules/Mount/Journal.lua` (~125), `Modules/Achievements/Dock.lua` (~849), `Modules/Teleports/MapTab.lua` (~225).

- [ ] **Step 1: Verify** `EventUtil.ContinueOnAddOnLoaded(addonName, callback)` on warcraft.wiki.gg (Gear.lua and
  Sheet.lua already use it).
- [ ] **Step 2:** Journal.lua and Dock.lua: replace the waiter frame with
  `EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", Hook)` / `("Blizzard_AchievementUI", Hook)`. Dock runs on
  every toggle-on: guard with a file-local `local waiting` so it is called once.
- [ ] **Step 3:** MapTab.lua `waitForCombat`: register through Teleports.lua's existing events frame instead (export
  `ns.Tp_Events` there if needed) with a dedicated handler that creates the secure button, then `TpTab_Refresh`; keep
  the order "button first, then refresh".
- [ ] **Step 4:** Run all tests. In-game: open the Mount Journal (zone star), the Achievements window (dock), open the
  world map's Teleports tab in combat then leave combat (button works). Commit after confirmation.
- [ ] **Step 5:** Update CLAUDE.md's convention line: "Use one event frame per module (`ns.NewEvents()`, Core/Events.lua)
  shared by its files". (This replaces the per-file wording written on 2026-10-11.)

---

## Phase 5: the remaining shared helpers

### Task 9: Small helper unifications (no visible change)

**Files:** `Modules/Weekly/BoardPage.lua`, `Modules/Weekly/Factions.lua`, `Modules/Chat/Filter.lua`,
`Core/Core.lua`, `Modules/Hunter/Stable.lua`, `Modules/Hunter/Tooltips.lua`, `Modules/Moments/Moments.lua`,
`Modules/Teleports/Owned.lua`, `Modules/Recap/Track.lua`, `Modules/Gear/Reveal.lua`, `Modules/Travel/Guard.lua`,
`Modules/Delves/Scan.lua`, `Cinematic/SceneKit.lua`, `Modules/AFK/Scene.lua`, `Modules/Moments/Scene.lua`,
`Panel/Widgets.lua`, `Panel/Dialog.lua`, `Panel/Setup.lua`, `Panel/Share.lua`, `Modules/Pets/Guides.lua`,
`Panel/Options.lua`, `Panel/Panel.lua`, `Modules/Gather/Page.lua`, `Modules/Pets/Page.lua`, plus every file with an
inline `issecretvalue and issecretvalue(x)` that isn't test-loaded.

**Interfaces (produces):**
- `ns.IsSecret(...)` becomes varargs: true when any argument is a secret value (single-argument behavior unchanged).
- `ns.SceneTitleBand(card) -> title, label, line, subtitle` (SceneKit).
- `UI.Dialog(name, width, height, opts) -> frame` with `opts = { parent = UIParent|WorldFrame, y = 0, escape = true }`.
- `UI.FitButton(button, minWidth, pad, unbounded)`.

- [ ] **Step 1: Weekly TipLine and Filter class color.** BoardPage.lua and Factions.lua: `local TipLine = UI.TipLine`
  (every caller passes a role; no wrap). Filter.lua: `UI.ClassColored(short, SenderClass(guid))`.
- [ ] **Step 2: Varargs secret.** In Core.lua replace `ns.IsSecret` with:

```lua
-- True when any argument is a secret value (12.x). Without the API (older clients, tests) nothing is secret.
function ns.IsSecret(...)
	if issecretvalue == nil then
		return false
	end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end
```

  Then: the four varargs `Secret(...)` copies (Hunter/Stable, Hunter/Tooltips, Moments/Moments, Teleports/Owned) ->
  `local Secret = ns.IsSecret`; Recap/Track.lua `Readable(...)` -> `local function Readable(...) return not
  ns.IsSecret(...) end`; Gear/Reveal.lua `Secret` -> `ns.IsSecret`; inline `issecretvalue and issecretvalue(x)` ->
  `ns.IsSecret(x)` in AFK.lua, Alts.lua, Alts/Collect.lua, ProfGear.lua, Delves/Scan.lua, Gear.lua, Toast.lua,
  Owned.lua, Panel/Bug.lua. Not Core/Content.lua and Core/BugReport.lua (test-loaded alone).
- [ ] **Step 3: Waypoints.** Guard.lua: `ns.TrackPin(mapID, info.position.x, info.position.y)`. Delves/Scan.lua:

```lua
local now
if mode == "poi" then
	now = ns.SafeTrack(function()
		C_SuperTrack.SetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI, e.poi)
	end)
else
	now = ns.TrackPin(e.map, e.x, e.y)
end
```

  (Copy the exact POI call from the current closure; never `and/or` here: SafeTrack returns false in combat.)
- [ ] **Step 4: Scene title band.** Move the 8 identical lines from AFK/Scene.lua (~195-202) into SceneKit.lua as
  `ns.SceneTitleBand(card)` returning the four objects; call it from AFK/Scene.lua and Moments/Scene.lua and assign the
  returns to the same fields they set today.
- [ ] **Step 5: UI.Dialog.** Move Setup.lua's 14-line block (CreateFrame, CENTER, DIALOG strata, SetToplevel, mouse,
  movable, clamped, drag scripts, Hide, `UI.Panel`, `tinsert(UISpecialFrames, name)`) into Widgets.lua as `UI.Dialog`
  with the opts above (WorldFrame parent and the scale compensation stay in the callers that have them: Dialog.lua,
  Guides.lua). Use it in Dialog.lua, Setup.lua, Share.lua, Guides.lua. Gear's import dialog keeps its own code
  (different on purpose: not clamped, no Esc).
- [ ] **Step 6: UI.FitButton.**

```lua
-- Sizes a button to its label: at least minWidth, label width + pad. unbounded uses GetUnboundedStringWidth.
function UI.FitButton(button, minWidth, pad, unbounded)
	local fs = button:GetFontString()
	local w = unbounded and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	button:SetWidth(math.max(minWidth or 0, math.ceil(w) + (pad or 24)))
end
```

  Replace each site keeping its own numbers: Dialog.lua and Options.lua `(80, 24)`; Panel.lua two sites `(0, 24)`
  (they didn't `ceil`: check width difference is < 1px, else keep them); Gather/Page.lua, Pets/Page.lua (~752),
  Weekly/BoardPage.lua `(56, 22, true)`; Pets/Page.lua (~166) `(40, 18, true)`.
- [ ] **Step 7:** Run all tests. In-game: Hunter Call Pet tooltip, Teleports tab, Moments banner, Recap loot of a
  rare, Gear upgrade reveal, guard gossip pin, Delves track (POI and pin), AFK screen and a Moments cinematic title,
  first-run picker (`/tomte setup` if it exists, else Share's import dialog), copy dialog, Pet Guides window, all
  buttons labelled as before. Commit after confirmation.

### Task 10: Bigger shared pieces (no visible change)

**Files:** Create `Core/Journal.lua`; modify `Modules/Collect/Catalog.lua`, `Modules/Holidays/Catalog.lua`,
`Cinematic/SceneKit.lua`, `Panel/ModelPreview.lua`, `Cinematic/Showcase.lua`, `Modules/Moments/Scene.lua`,
`Modules/Hunter/Checks.lua`, `Modules/Rogue/Rogue.lua`, create `Core/Check.lua`; `Tomte.toc` + bugfiles.

**Interfaces:**
- `ns.Journal_Scan(owner, { mount = fn(mountID, info), pet = fn(speciesID, info), done = fn(), progress = fn(fraction) })`:
  one budgeted reader (BUDGET_MS = 4, MAX_SPECIES = 6000, own hidden frame per scan), calling back per uncollected entry.
  `ns.Journal_StillMissing(kind, id) -> bool`.
- `ns.ModelLight(scene)`, `ns.ModelLookDown(actor, pitch)`: the identical light lines and pitch-sign check from the
  three camera fits. Each caller keeps its own GUESS_BOX, FIT_PASSES, fit fraction and Project.
- `ns.Check_Report(spec)` with `spec = { name, verbose, problems = { text, ... }, banner = { accent, icon, label },
  bannerOnVerbose = bool, offMessage = string|nil }`: prints and shows the banner exactly as today's two callers do.

- [ ] **Step 1: Journal reader.** Move Collect/Catalog.lua's budgeted OnUpdate loop and its mount/pet read (skip
  collected / hidden; pcall'd pet info) into `Core/Journal.lua` (TOC: after Core/Content.lua). Collect keeps its
  3-phase progress by mapping the reader's mount/pet phases plus its own achievement phase; Holidays keeps its 2-half
  progress and restart-on-target-change. Both keep their own per-entry logic (Collect: parsed source zones; Holidays:
  `Events_MatchEntry`, `line`, pet `displayID` = 13th return of `C_PetJournal.GetPetInfoBySpeciesID`).
- [ ] **Step 2: Camera pieces.** Extract only `ns.ModelLight` and `ns.ModelLookDown` into SceneKit.lua; call them from
  the three files. Do not unify constants (framing would change).
- [ ] **Step 3: Check report.** `Core/Check.lua` with `ns.Check_Report` and `ns.Check_OnEnterWorld(delay, fn)` (the
  identical enter-world + ready-check trigger). Hunter passes `bannerOnVerbose = true`, accent "warning", fixed icon,
  no offMessage; Rogue passes `bannerOnVerbose = false`, accent "danger", the spell icon, `offMessage = "is off"`, and
  keeps its extra verbose poison listing before calling `Check_Report`.
- [ ] **Step 4:** Run all tests. In-game: Collect here tab after login (list fills, progress bar), Events page missing
  collectibles during a holiday, model previews (Collect tab, Holidays page, Almost Done), a flight showcase, a Moments
  creature reveal, Hunter `/tomte hunter check` and a pet-less dungeon entry, Rogue check with a missing poison.
  Identical. Commit after confirmation.

### Task 11: Row actions shared by Collect and Holidays (needs one decision)

**Decision for the user before starting:** Collect's tab blocks opening an achievement in combat ("the journal opens
after combat"); Holidays' page opens it in combat. Recommended: Collect's rule for both (opening the load-on-demand
Achievements UI in combat may be blocked).

**Files:** Create `Panel/Entries.lua` (after Panel/ModelPreview.lua in the TOC); modify `Modules/Collect/Tab.lua`,
`Modules/Holidays/Page.lua`.

**Interfaces:** `ns.Entry_Link(e) -> link|nil` (mount, pet, toy, achievement), `ns.Entry_Open(e)` (journal or
achievement, with the chosen combat rule), `ns.Entry_Model(e) -> spec|nil` (pets: `e.displayID` when present, else
the live 12th return).

- [ ] **Step 1:** Move Holidays/Page.lua's `Link`, `OpenEntry`, `ModelFor` (the superset: they handle toys) into
  `Panel/Entries.lua` as the three functions; apply the chosen combat rule; Collect/Tab.lua and Holidays/Page.lua call
  them. Tab keeps its own `db.preview` gate and its hint wording.
- [ ] **Step 2:** Run all tests. In-game: shift-click and click rows in both places, in and out of combat; hover
  previews. Commit after confirmation; CHANGELOG line if the combat rule changed for Holidays.

---

## Phase 6: theme colors

### Task 12: Theme-color conversions and a stricter theme test

**Decision for the user before starting:** Mount's two `UIErrorsFrame` messages are Blizzard yellow today. Recommended
`"heading"` (identical on the Blizzard theme, follows other themes). And the Gear sheet's row hover becomes the theme's
"hover" color like every other row list (slightly stronger on Blizzard, tinted on other themes).

**Files:** `Core/Theme.lua`, `Modules/Recent/Recent.lua`, `Modules/Alts/CraftTab.lua`, `Modules/Alts/List.lua`,
`Modules/Alts/RosterTab.lua`, `Modules/Alts/Send.lua`, `Modules/Mount/Mount.lua`, `Modules/Gear/Sheet.lua`,
`tests/test_theme.lua`.

- [ ] **Step 1: Write the failing theme-test checks.** In `tests/test_theme.lua`'s per-line scan (the loop that flags
  `|c[fF][fF]%x...` literals), add:

```lua
-- Hand-built color codes: use UI.Wrap / Theme.Hex (roles or color tables) instead.
if code:find("%%02x%%02x%%02x") then
	Flag(file, n, "hand-built hex color")
end
```

  and add `"AddMessage"` to the function list checked for three trailing numeric color arguments, matching the whole
  line (`:AddMessage%(.*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*%)`) and carrying a pending flag to the next
  line when the call doesn't close on its own line. Use the file's existing reporting function name instead of `Flag`
  (read the test first). Run `lua Tomte/tests/test_theme.lua`. Expected: FAIL listing Recent.lua, CraftTab.lua,
  List.lua, RosterTab.lua, Send.lua and Mount.lua.
- [ ] **Step 2: `Theme.Hex` accepts color tables.** In Core/Theme.lua make `Theme.Hex(roleOrColor)` take either a role
  name or a `{ r, g, b }` / `{ r = , g = , b = }` table (the shapes `UI.RGBA` already accepts), rounding as today.
  `Theme.Wrap` and `UI.Wrap` follow.
- [ ] **Step 3: Convert the sites.**
  - Recent.lua `AccentWrap(e, text)` -> `UI.Wrap(text, Accent(e))`.
  - CraftTab.lua `Hex(c)` and `RecipeName`, List.lua `InQuality` -> the 4th return of
    `C_Item.GetItemQualityColor(quality)` (the ready hex string): `"|c" .. hex .. text .. "|r"` is still a hand-built
    code but not `%02x`; or `ITEM_QUALITY_COLORS[q].color:WrapTextInColorCode(text)` (verify on the wiki).
  - RosterTab.lua and Send.lua class names -> `UI.ClassColored(c.name or "?", c.class)`.
  - Mount.lua `AddMessage(msg, 1, 0.82, 0)` -> `AddMessage(msg, UI.RGB("heading"))` (or the role the user chose).
  - Sheet.lua `row.hover:SetColorTexture(1, 1, 1, 0.05)` -> `row.hover:SetColorTexture(UI.Color("hover"))`.
- [ ] **Step 4:** Run all tests (theme test now green). In-game: Recent entries' accent titles, Crafting recipe names in
  quality colors, List tracker items, roster and send-dock class names, Smart Mount "no mount" message, Gear sheet row
  hover, on two themes. Commit after confirmation. CHANGELOG: `- Gear Check: the character sheet panel's row highlight
  now follows your theme.` (and the Mount line if the color changes on non-Blizzard themes).

---

## Phase 7: splits and renames (pure moves)

General rules for Tasks 13-17:
- Move blocks verbatim. The only allowed edits: the renames listed, `local` captures at the top of the new file, and
  new `ns.*` exports for names another new file needs.
- Every new file starts with `local addonName, ns = ...`, a header (what it holds, where the rest lives), and
  `local UI = ns.UI` if used.
- Then: TOC lines, `lua Tomte/tools/bugfiles.lua`, all tests, and a global-read check for each new file
  (`luac -l <file> | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` must list only WoW API / Lua globals, never a name that was
  a file local before the split).
- Fix the comments that point at moved code (headers listed per task).

### Task 13: Split Panel/Home.lua

**Files:** Create `Panel/HomeKit.lua`, `Panel/HomeHero.lua`, `Panel/HomeAround.lua`, `Panel/Rail.lua`; modify
`Panel/Home.lua`, `Tomte.toc` (line `Panel/Home.lua` -> `Panel/HomeKit.lua`, `Panel/HomeHero.lua`,
`Panel/HomeAround.lua`, `Panel/Home.lua`, `Panel/Rail.lua`), `Core/Modules.lua` comment (~116).

| Block (find by name) | Goes to |
|---|---|
| `DISPLAY_FONT/NARROW_FONT`, `PAD`, `ROW_H/ROW2_H`, `SetColor`, `TipLine`, `Snap`, `Kit = {}`/`ns.HomeKit`, `Kit.Heading`, `Kit.Row`, `Kit.PoolRow`, `Kit.HideFrom`, `HLine`, `VLine` | HomeKit.lua; export `Kit.PAD`, `Kit.SetColor`, `Kit.TipLine`, `Kit.Snap`, `Kit.HLine`, `Kit.VLine` |
| `HERO_W`, `Durability`, `ModuleOn`, `Signed`, `TipPair`, `Secret`, `Capitalized`, `FACTS`, `FactClickable`, `FactEnter`, `CreateHero` | HomeHero.lua; export `ns.PanelHome_CreateHero`, `ns.PanelHome_HERO_W` |
| `CreateAround` | HomeAround.lua; export `ns.PanelHome_CreateAround` |
| `HERO_MIN_CONTENT`, `WEEK_H`, `NEXT_UNDER_MIN` (as `40 + 2 * Kit.ROW2_H`), `RESIZE_DELAY`, `ns.PanelHome_Create` | Home.lua |
| `RAIL_ROW_H`, `RAIL_HEADER_H`, `RAIL_W`, `SetIcon`, `CreateRailRow`, `ns.PanelRail_Create` | Rail.lua |

New files capture at top: `local Kit = ns.HomeKit` and `local SetColor, TipLine, Snap, PAD = Kit.SetColor, Kit.TipLine,
Kit.Snap, Kit.PAD`. HomeKit must stay before `Modules/Delves/Page.lua` (captures `ns.HomeKit` at load): it does.

- [ ] **Step 1:** Create HomeKit.lua and move its blocks; run tests.
- [ ] **Step 2:** Create HomeHero.lua, HomeAround.lua, Rail.lua; reduce Home.lua; TOC; bugfiles; run tests; global check.
- [ ] **Step 3:** In-game: Home at several window sizes, hero facts and their tooltips/clicks, Around you, the rail
  with pills, Delves page (uses HomeKit). Commit after confirmation.

### Task 14: Split Modules/Alts/CraftTab.lua

**Files:** Create `Modules/Alts/CraftGear.lua`, `CraftMats.lua`, `CraftResults.lua`, `Shop.lua`, `CraftDetail.lua`;
modify `CraftTab.lua`, `Tomte.toc` (CraftTab line -> CraftTab, CraftGear, CraftMats, CraftResults, Shop, CraftDetail),
headers of Alts.lua, ListTab.lua, ProfGear.lua, ProfTab.lua.

Shared mutable state becomes one table in CraftTab.lua: `local S = {}; ns.AltsCraft_State = S` with fields `tab`,
`db`, `producers`. In all moved code rename `tab` -> `S.tab`, `db` -> `S.db`, `producers` -> `S.producers` (the only
non-move edit). New files: `local S = ns.AltsCraft_State`.

| Blocks | Goes to | Exports |
|---|---|---|
| `LIST_W`, `loading`, `SetColor`, `ClassName`, `Names`, `redrawSoon`, `ItemName`, `QualityColor`, `Hex`, `RecipeName`, `ProfName`, `ns.AltsCraft_Create/Open/RecipesChanged/Refresh` | CraftTab.lua | `ns.AltsCraft_SetColor/ClassName/Names/ItemName/QualityColor/RecipeName/ProfName` |
| `Loaded/Ilvl`, `ForChar`, `itemInfo/ItemInfo`, `wornCache/Worn`, `CompareQuality`, `ForInfo`, `IlvlRange`, `MarkText`, `ForText` | CraftGear.lua | `ns.AltsCraft_ForChar/CompareQuality/ForInfo/MarkText/ForText` |
| `matsKept/matsChain`, `ClearMaterials`, `matsEvents` (bus owner after Task 7), `WatchMaterials`, `HaveMaterials`, `ns.AltsCraft_Why` | CraftMats.lua | `ns.AltsCraft_ClearMaterials/WatchMaterials/HaveMaterials` |
| `RESULT_H`, `SEARCH_ROWS`, `results/resultRows/groupRows`, `searchText`, `ContinentName`, `CreateResultRow`, `HEADER_STYLE`, `CreateGroupRow`, `SetResultRow`, `lineNames/LineName`, `SetAllCollapsed`, `LayoutResults`, `CharChoices/ProfChoices/ForChoices`, `Filter`, `CreateFilters`, `RefreshFilters`, `CreateSearch` | CraftResults.lua | `ns.AltsCraft_LayoutResults/CreateFilters/RefreshFilters/CreateSearch` |
| `CALLER`, `ShoppingAPI`, `MakeShoppingList`, `ns.AltsShop_CreateLink` (+ its own 3-line `SetColor`) | Shop.lua | — |
| `MAT_H/STEP_H/HEADER_H/QUALITY_H`, `matRows/stepRows/headers`, `H_*`, `Header`, `SetRank`, `RankMenu`, `CreateMatRow`, `CreateStepRow`, `WhereText`, `StepText`, `LayoutDetail` (drop the forward declaration; define it before use), `CreateDetail` | CraftDetail.lua | `ns.AltsCraft_LayoutDetail/CreateDetail` |

CraftTab.lua's entry points call the later files' functions through `ns.` at runtime (not captured at load).

- [ ] **Step 1:** Create the state table and CraftGear.lua; run tests. **Step 2:** CraftMats.lua, CraftResults.lua,
  Shop.lua, CraftDetail.lua; TOC; bugfiles; run tests; global check.
- [ ] **Step 3:** In-game: Crafting tab search, filters, grouping/collapse, a recipe's detail (materials, steps,
  Syndicator counts, value, gear for), rank menu, Auctionator shopping list button, `/tomte alts why`. Commit after confirmation.

### Task 15: Split Modules/Alts/Data.lua

**Files:** Create `Modules/Alts/PlanData.lua`, `RosterData.lua`, `GearData.lua`, `Forget.lua`; delete `Data.lua`;
`Tomte.toc` (`Modules/Alts/Data.lua` -> the four); `tests/test_alts.lua:3` -> four loadfiles (PlanData, RosterData,
GearData, Forget); `tests/test_list.lua:3` -> PlanData only; headers of Alts.lua, ListTab.lua, HomeSection.lua.

| Blocks | Goes to |
|---|---|
| saved-data layout comment, `ALTS_FULL_DEPTH`, `Alts_Producers`, `Alts_Crafters`, `Alts_RecipeStatus`, `Alts_Search`, `Alts_Group`, `LINE_ALIASES`, `Alts_LineInContinent`, `Alts_Yield`, `SlotKey`, `PickProducer`, `PickedRank`, `Alts_Plan`, `Alts_ShoppingItems`, `Alts_RecipeItemName`, `Alts_RecipesByName`, `Alts_RecipeItemStatus` | PlanData.lua (`local max, min, ceil = math.max, math.min, math.ceil`) |
| `Alts_Gold/Alts_Price` aliases (Task 2), `Alts_Ago`, `ALTS_SORTS`, `Alts_Roster`, `Alts_TotalGold`, `Alts_WarbandText`, `ALTS_PROFESSIONS`, `Alts_Uncovered`, `Alts_FreeSlots`, `Alts_GapText`, `Until`, `Alts_WeeklyStatus`, `Alts_WeeklyLine`, `Alts_Profs`, `Alts_SecondaryText`, `Alts_ProfText` | RosterData.lua (`floor, max`) |
| gear-for comment and tables (`ARMOR`…`KIND_NAMES`, incl. the `PROF_BY_SUBCLASS` load-time loop after `PROF_SUBCLASS`), `Alts_GearFor`, `ITEM_SLOTS/SLOT_NAMES`, `Alts_WornFor`, `Alts_Upgrade`, `Alts_Qualities`, `Alts_ClampQuality`, `Alts_QualityLinks`, `Alts_ProfItem` … `Alts_ProfBagUpgrade` | GearData.lua (`floor, max, min`) |
| `SquashRealm`, `Alts_ForgetMatches`, `FORGET_STORES`, `Alts_ForgetEverywhere` | Forget.lua |

- [ ] **Step 1:** Create the four files by moving blocks; delete Data.lua; TOC; bugfiles; update the three tests'
  loadfile lines (test_alts and test_list also need `Core/Format.lua` first, from Task 2).
- [ ] **Step 2:** Run all tests (test_alts, test_list, test_send green); global check.
- [ ] **Step 3:** In-game: Characters tab, Crafting tab, List tab, Profession gear tab, `/tomte alts forget <name>`
  on a test character. Commit after confirmation.

### Task 16: Split Modules/Gear/Gear.lua

**Files:** Create `Modules/Gear/Context.lua`, `Tooltip.lua`, `Hints.lua`, `Baganator.lua`, `Weights.lua`; modify
`Gear.lua`; `Tomte.toc` (Gear.lua line -> Context, Tooltip, Hints, Baganator, Weights, Gear: Gear.lua last, because
its registration table captures functions from the others at load).

New files read state at call time: `local function DB() return ns.gearDB end` and `ns.gearModule.active` (set in
Gear.lua's init/toggle before any handler runs). Rename in moved code: `db.x` -> `DB().x`, `module.active` ->
`ns.gearModule.active`.

| Blocks | Goes to | Exports |
|---|---|---|
| `GetSpecialization*` upvalues (C_ after Task 1), `PRIMARY_KEYS`, `UnitClass` line, `SpecAt`, `Spec`, `CurrentSeason`, `ContextFor`, `ownCtx/Context`, `specCtx/SpecContext`, `OtherSpecs`, `IsGearLink`, `Evaluate`, `InvalidateVerdicts`, `ns.Gear_ContextForChar` | Context.lua | `ns.Gear_SpecAt`, `ns.Gear_CurrentSeason`, `ns.Gear_OwnContext`, `ns.Gear_SpecContext`, `ns.Gear_OtherSpecs`, `ns.Gear_IsGearLink`, `ns.Gear_EvaluateLink` (existing), `ns.Gear_InvalidateVerdicts`, `ns.GEAR_PRIMARY_KEYS` |
| `COLOR_ROLES`, `Label`, `Reason`, `MAX_REASONS`, `MAX_ALT_LINES`, `OwnLines`, `AltLines`, `OnItem` | Tooltip.lua | `ns.GearTooltip_OnItem` |
| `noWeightsSaid`, `CharHinted`, `MaxLevel`, `WeightsHint`, `lastAudit`, `AuditHint` | Hints.lua | `ns.GearHints_Weights`, `ns.GearHints_Audit`, `ns.GearHints_MaxLevel` |
| `BAGANATOR_*_ID`, `ALT_ROLE`, `MAYBE_ROLE`, `RegisterBaganator` (with `Arrow`) | Baganator.lua | `ns.GearBaganator_Register` |
| `CharWeights`, `SIM_STEPS`, `WEIGHT_STEPS`, `PrintSteps`, `PrintSimSteps`, `PrintWeights`, `SourceLabel`, `ClearWeights`, `dialog`, `Import`, `BuildDialog`, `OpenImport`, `NextSim`, `PrintSpecs` | Weights.lua | existing `ns.Gear_PrintSimSteps/ClearWeights/OpenImport`, new `ns.GearWeights_Print/SourceLabel/NextSim/PrintSpecs/HideDialog` |
| `ns.Gear_Context`, `ns.Gear_Verdict`, the events (bus after Task 5), `RereadWorn`, `WornChanged`, `ns.GearItems_OnReady`, `Command`, `Start`, `Stop`, the registration, `ns.gearModule` | Gear.lua | — |

- [ ] **Step 1:** Create Context.lua; run tests. **Step 2:** the other four; reduce Gear.lua; TOC; bugfiles; run tests;
  global check (`test_bugreport` mentions `Modules/Gear/Gear.lua` as a string: still exists).
- [ ] **Step 3:** In-game: Gear tooltips (own, alt, maybe), chat hints, Baganator arrows, `/tomte gear import`,
  `/tomte gear weights`, `/tomte gear specs`, `/tomte gear sim`, character sheet panel, option toggles. Commit after confirmation.

### Task 17: Network.lua as three generated files

**Files:** Modify `tools/waynet.py`; create `Modules/Travel/NetworkNodes.lua`, `NetworkEdges.lua`, `NetworkConds.lua`
(generated); delete `Network.lua`; `Tomte.toc` (Network line -> the three, still before Route.lua and Router.lua);
`tests/test_route.lua:3` -> three loadfiles; README.md Layout/tools line.

- [ ] **Step 1: Change `build()`** to return `{ filename: text }`: NetworkNodes.lua gets the header, generated comment,
  `ns.WAY_NET_BUILD`, `ns.WAY_NET_NODES`; NetworkEdges.lua gets `WAY_NET_EDGES` and `WAY_NET_VOLUMES` (with the volume
  comment); NetworkConds.lua gets `WAY_NET_CONDS`. Each starts with `local addonName, ns = ...` and
  `-- Generated by tools/waynet.py (build %s). Don't edit: regenerate.` `main()` writes all three and deletes a leftover
  `Network.lua`. Wrap long CONDS rows:

```python
def lua_wrapped(value, indent=1, width=120):
    flat = lua(value)
    if not isinstance(value, list) or len(flat) + indent * 4 <= width:
        return flat
    pad = "\t" * (indent + 1)
    return "{\n" + ",\n".join(pad + lua_wrapped(v, indent + 1, width) for v in value) + ",\n" + "\t" * indent + "}"
```

  Use it for the CONDS row value. Keep `lua()` unchanged for everything else.
- [ ] **Step 2: Regenerate** with the build in the current header (`python -I tools/waynet.py 12.1.0.69933`), then
  verify the tables are identical to the old file:

```bash
cd "/d/World of Warcraft/_retail_/Interface/AddOns" && git -C Tomte show HEAD:Modules/Travel/Network.lua > "$TEMP/net_old.lua" && lua -e '
local function load(paths) local ns = {} for _, p in ipairs(paths) do assert(loadfile(p))("Tomte", ns) end return ns end
local function same(a, b) if type(a) ~= type(b) then return false end if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end for k in pairs(b) do if a[k] == nil then return false end end return true end
local old = load({ os.getenv("TEMP") .. "/net_old.lua" })
local new = load({ "Tomte/Modules/Travel/NetworkNodes.lua", "Tomte/Modules/Travel/NetworkEdges.lua", "Tomte/Modules/Travel/NetworkConds.lua" })
for _, k in ipairs({ "WAY_NET_NODES", "WAY_NET_EDGES", "WAY_NET_VOLUMES", "WAY_NET_CONDS", "WAY_NET_BUILD" }) do print(k, same(old[k], new[k])) end'
```

  Expected: five `true` lines. If wago.tools serves different data for that build, regenerate the OLD single file from
  the same CSVs first and compare against that instead.
- [ ] **Step 3:** TOC, bugfiles, test_route.lua, run all tests. In-game: a portal route. Commit after confirmation.

### Task 18: Rename the pure-logic files of Weekly and Gear

**Files:** `git mv` (rename, history kept):
- `Modules/Weekly/Data.lua` -> `Modules/Weekly/Model.lua`
- `Modules/Weekly/FactionData.lua` -> `FactionModel.lua`, `ActivityData.lua` -> `ActivityModel.lua`, `RaidData.lua` -> `RaidModel.lua`
- `Modules/Gear/Data.lua` -> `Modules/Gear/Rules.lua`

Then update: `Tomte.toc` (lines naming them), bugfiles, `tests/test_weekly.lua:7`, `test_factions.lua:6`,
`test_activities.lua:6`, `test_raids.lua:6`, `test_gear.lua:6` and `:203`, `test_wq.lua:3`; comments in
`Weekly/Activities.lua:5`, `Weekly/Factions.lua:5,8`, `Weekly/BoardPage.lua:6`, `Weekly/Weekly.lua:5`,
`Weekly/WeekView.lua:5`, `Gear/Gear.lua` header (and the split files from Task 16), `Gear/Items.lua:3`,
`Gear/Reveal.lua:7`. Leave docs/superpowers history files alone.

- [ ] **Step 1:** `git mv` each file. **Step 2:** update all references listed; `grep -rn 'Weekly/Data.lua\|FactionData\|ActivityData\|RaidData\|Gear/Data.lua' --include=*.lua --include=*.toc --include=*.md . | grep -v docs/` prints nothing.
- [ ] **Step 3:** bugfiles, run all tests. In-game: `/reload`, Weekly board and Gear tooltip work. Commit after confirmation.

---

## Phase 8: tests and tools

### Task 19: `tests/harness.lua`

**Files:** Create `tests/harness.lua`; modify all `tests/test_*.lua`; README "Tests" section (one sentence).

**Interfaces:** `local H = dofile("Tomte/tests/harness.lua")` returns `H.test(name, fn)`, `H.eq(actual, expected,
label)`, `H.near(actual, expected, label)` (tolerance 0.001), `H.done()`.

- [ ] **Step 1: Write `tests/harness.lua`:**

```lua
-- Shared helpers for the plain-Lua unit tests. Load from the AddOns folder:
--   local H = dofile("Tomte/tests/harness.lua")
--   local test, eq = H.test, H.eq
--   ... tests ...
--   H.done()
local H = { failures = 0 }

function H.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		H.failures = H.failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

function H.eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

function H.near(actual, expected, label)
	if math.abs(actual - expected) > 0.001 then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

-- Ends the run: exit code 1 when anything failed (CI runs each file under bash -e).
function H.done()
	if H.failures > 0 then
		print(H.failures .. " failed")
		os.exit(1)
	end
	print("all passed")
end

return H
```

- [ ] **Step 2: Prove it fails a run:** create a scratch copy of `tests/test_home.lua` in the scratchpad that uses the
  harness and has `H.eq(1, 2)` inside one test; run it from the AddOns folder; expected exit code 1 and "1 failed".
  Delete the scratch file.
- [ ] **Step 3: Convert every test file:** replace its `local failures`, `test`, `eq` (and the 0.001 `near` in
  test_minimap.lua and test_travel.lua) with `local H = dofile("Tomte/tests/harness.lua")` and
  `local test, eq, near = H.test, H.eq, H.near` (only the names it uses), and its ending block (all four variants) with
  `H.done()`. Keep file-specific helpers (`has`, test_flight_data's own `near`, factories) as they are. Convert in
  batches of ~10 files, running the loop after each batch.
- [ ] **Step 4:** Count check: `grep -l 'local function test(' tests/test_*.lua` prints nothing;
  `grep -L 'H.done()' tests/test_*.lua` prints nothing. Run all tests. Commit (no in-game check needed: dev only).

### Task 20: Shared Python helpers for the tools

**Files:** Create `tools/artlib.py`, `tools/wago.py`; modify `tools/theme_art.py`, `tools/themes/emerald.py`,
`forge.py`, `frost.py`, `void.py`, `tools/events.py`, `tools/waynet.py`.

**Interfaces:**
- `artlib.seamless_noise(size, rnd, sigma, blur)` (moved verbatim from emerald.py `_seamless_noise`),
  `artlib.wrap_blur(img, blur)` (the 3x3 tile/blur/crop step), `artlib.signed_rgba(grey_img, k)` (grey around 128 ->
  white/black RGBA, alpha `abs(d) * k`), `artlib.white(alpha_img)` (moved from frost.py),
  `artlib.glow(size, rgb=(255, 255, 255))` (theme_art's `glow` with the colour as a parameter),
  `artlib.hairline(img, cx, cy, start, ss, power)` and `artlib.finish(img, w, h)` (the shared flourish skeleton),
  `artlib.static_font(src_file, dst_path, wght=None)` and `artlib.copy_license(src_dir, dst_name)`,
  `artlib.tint(img, rgb, alpha=1.0)` (forge's `tinted`).
- `wago.load(folder, tables, build, user_agent=True) -> dict[name] = rows` and `wago.folder_from_argv(prefix)`.

Import setup at the top of each script (the `-I` flag removes the script folder from `sys.path`, so insert it
explicitly; theme scripts run without `-I` because Pillow lives in the user site-packages):

```python
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # tools/ (themes/*.py use parents[1] too)
import artlib
```

(`theme_art.py`, `events.py` and `waynet.py` are in `tools/` themselves: use `parents[0]`.)

- [ ] **Step 1: Add an `--art-only` flag** to theme_art.py and emerald.py (the two with a required `--fonts-src`): skip
  the font step when given. Run every generator with `--art-only` (or without `--fonts-src` where optional) on the
  current code and confirm `git -C Tomte status --short Media/` prints nothing (the art is deterministic).
- [ ] **Step 2: Write `tools/artlib.py`** by moving the helpers listed above verbatim from their source files (one
  source per helper, as named), and switch each script to import them. Copies that differ keep their difference as a
  parameter (glow colour, flourish power 1.3 vs 1.4, alpha factor 1.5 vs 1.6).
- [ ] **Step 3: Re-run every generator** with `--art-only`; `git -C Tomte status --short Media/` must print nothing
  (byte-identical .tga files). If the user has the font sources, also run once with `--fonts-src` and check the .ttf
  files are unchanged.
- [ ] **Step 4: Write `tools/wago.py`** from events.py's `load` (the one with the Chrome User-Agent, which wago.tools
  needs) and the shared `main()` argv handling; switch events.py and waynet.py to it. Re-run both for their current
  builds and confirm `Modules/Holidays/Generated.lua` and the three Network files are unchanged (`git status`).
- [ ] **Step 5:** Commit (dev only, no in-game check). README tools line if names changed.

---

## Order and checkpoints

Phases run in order: 0 (commit) -> 1 (urgent, 12.1.5) -> 2 -> 3 -> 4 (Tasks 4-8) -> 5 (Tasks 9-11) -> 6 -> 7 (Tasks
13-18; 16 after Task 5 because Gear's events move first; 14/15 after Task 7) -> 8. Each task that touches game code
ends with the user's in-game check and a commit; Tasks 19-20 need no game. Two decisions are needed before their tasks
start: the achievement-in-combat rule (Task 11) and the Mount message color (Task 12).
