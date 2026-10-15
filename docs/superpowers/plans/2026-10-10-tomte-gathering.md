# Gathering Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module `gather` that tracks gathering runs (nodes, items with ranks, value, gold and nodes per hour,
rare finds, skill and knowledge, zones) for every gathering profession, with a small tracker, a Gathering page and
links into the play session, recap and Next up.

**Architecture:** Pure logic (classification, learning, the run model, numbers, history) sits in `Data.lua` with no
WoW calls and is unit-tested with plain Lua. `Detect.lua` turns casts and loot windows into plain "gather" tables and
hands them to `Gather.lua`, which owns the run lifecycle. Tracker and page only read the run tables.

**Tech stack:** WoW retail 12.1 Lua (5.1), Tomte's `ns.UI` toolkit and theme roles, `ns.RegisterModule`,
`ns.EditMode_Register`, Gold & value (`ns.Value_ItemPrice`, `ns.Value_LootAdd`, `ns.Value_LootTotals`),
`ns.Content_Get(expansion, "profs")`.

**Spec:** `docs/superpowers/specs/2026-10-10-tomte-gathering-design.md`.

**Execution:** native or subagent-driven, chosen by the user after review. Work stays on branch `gather`, uncommitted,
until the user has checked it in game (CLAUDE.md). Commit steps below happen only after that check.

## Global constraints

- Lua 5.1 syntax (CI runs 5.1): no `goto`, no `//`, no `utf8`.
- No numeric RGB in `SetTextColor`, `SetVertexColor`, `SetColorTexture` or `CreateColor`; colors from theme roles
  (`UI.Color(role)`, `UI.Text(parent, size, role, font)`, `UI.Panel(frame)`). No `|cff` literals, no font paths.
  `tests/test_theme.lua` scans for them.
- One event frame per file, dispatching with `self[event](self, ...)`. No new globals.
- Match game data by IDs (spell IDs, skill lines 182/186/393/356, item class 7 subclasses 6/7/9, map IDs, quest IDs),
  never English text. Item and zone names come from the game.
- Every event payload, GUID, link and name is checked with `issecretvalue` before use. A secret value makes that piece
  unknown; it never raises an error.
- Defaults are safe: the module only reads and counts.
- Optional modules are checked before use: Gold & value (`ns.Value_ItemPrice` returns nil when off), Recap
  (`ns.recapModule.active`), Next up.
- Run the tests from the AddOns folder: `for t in Tomte/tests/test_*.lua; do lua "$t"; done`.

## Review focus

1. **Area loot and rich veins:** one window with three skinned corpses is three gathers and three nodes; a rich vein
   mined three times is three gathers and one node. → Task 2 test "nodes vs gathers".
2. **Bags full / items left in the window:** only slots that got `LOOT_SLOT_CLEARED` are booked. → Task 2 test "book
   only cleared slots".
3. **Treasure chests, disturbed earth and containers** (`GameObject` with the Opening cast, `Item-` sources,
   `isFromItem`) never count and are never learned as gathering spells. → Task 1 tests "Opening is never a gather",
   "never learn from known non-gathering spells".
4. **Secret cast payloads** (gathering with a mob on you): classification falls back to the loot contents; creature
   loot without a readable cast never counts. → Task 1 test "secret cast falls back".
5. **`/reload` or relog mid-run, and switching characters:** the run continues within the idle timeout, ends at its
   last gather when the timeout passed, and is finished (not continued) when another character logs in. → Task 2 test
   "resume rules".

---

### Task 1: Classification and learning (`Modules/Gather/Data.lua`, part 1)

**Files:**
- Create: `Modules/Gather/Data.lua`
- Create: `tests/test_gather.lua`

**Produces** (all pure):
- `ns.GATHER_KINDS = { "mining", "herbalism", "skinning", "fishing" }` and `ns.GATHER_SKILL_LINES = { mining = 186,
  herbalism = 182, skinning = 393, fishing = 356 }`.
- `ns.GATHER_SPELLS = { [2575] = "mining", [195122] = "mining", [423341] = "mining", [471013] = "mining",
  [2366] = "herbalism", [8613] = "skinning", [7620] = "fishing", [131476] = "fishing" }` with a comment crediting
  GatherMate2's collector and Wowhead (IDs only).
- `ns.GATHER_NOT = { [3365] = true, [22810] = true, [1804] = true, [73979] = true, [167895] = true, [1239682] = true }`
  (Opening, Pick Lock, Survey, Logging).
- `ns.Gather_ParseGUID(guid)` → `kind, id`: `"GameObject", 12345` / `"Creature", 223446` / `"Item", nil` / nil for
  nil or junk. The id is the 6th `-` field.
- `ns.Gather_SpellKind(spellID, spellName, names, learned)` → kind or nil. `names` = `{ [localizedName] = kind }` built
  in Detect from `C_Spell.GetSpellName` of each anchor; `learned` = `db.spells`. Order: `GATHER_NOT` → nil, then ID,
  then learned, then name.
- `ns.Gather_ItemKind(classID, subClassID)` → `"mining"` (7/7), `"herbalism"` (7/9), `"skinning"` (7/6) or nil.
- `ns.Gather_Classify(win, cast, opts)` → `kind | nil, reason`.
  - `win = { fromItem, fishing, slots = { { link, itemID, count, quality, classID, subClassID, sources = { guid... } } } }`.
  - `cast = { spellID, kind, at } | nil` (nil when none in the last 3 s or secret); `opts = { now, fishing = bool }`.
  - Rules 1–6 of the spec in order. `cast.kind` is filled by Detect with `Gather_SpellKind`; `Classify` itself checks
    `GATHER_NOT[cast.spellID]` for rule 4. `reason` is a short string for `/tomte gather why` ("cast 2575", "contents: ore",
    "creature loot without a cast", "opening", "container").
- `ns.Gather_Learn(learned, pending, cast, win, kindFromContents)` → `learnedKind | nil`. `pending[spellID] =
  { kind, n }`; at `n == 2` it writes `learned[spellID] = kind` and returns it. Never learns a `GATHER_NOT` spell or a
  spell already in `GATHER_SPELLS`.

- [ ] **Step 1: Write the failing tests** in `tests/test_gather.lua` (same harness as `tests/test_recap.lua`: `loadfile`
  of `Tomte/Modules/Value/Data.lua` and `Tomte/Modules/Gather/Data.lua`, `test(name, fn)`, `eq`, exit code on failure).

```lua
local function Slot(id, sub, src, n)
	return { link = "item:" .. id, itemID = id, count = n or 1, quality = 1, classID = 7, subClassID = sub,
		sources = { src } }
end
local ORE, HERB, HIDE = 7, 9, 6
local NODE, CORPSE = "GameObject-0-1-2-3-410000-0001", "Creature-0-1-2-3-220000-0002"

test("ParseGUID", function()
	local kind, id = ns.Gather_ParseGUID(NODE)
	eq(kind, "GameObject"); eq(id, 410000)
	eq((ns.Gather_ParseGUID("Item-1-0-ABC")), "Item")
	eq((ns.Gather_ParseGUID(nil)), nil)
end)

test("mining cast on a node is mining", function()
	local kind = ns.Gather_Classify({ slots = { Slot(210930, ORE, NODE, 3) } },
		{ spellID = 423341, kind = "mining", at = 99 }, { now = 100 })
	eq(kind, "mining")
end)

test("Opening is never a gather", function()
	local kind = ns.Gather_Classify({ slots = { Slot(210930, ORE, NODE) } }, { spellID = 3365, at = 99 }, { now = 100 })
	eq(kind, nil)
end)

test("secret cast falls back to contents for nodes only", function()
	eq((ns.Gather_Classify({ slots = { Slot(210796, HERB, NODE, 2) } }, nil, { now = 100 })), "herbalism")
	eq((ns.Gather_Classify({ slots = { Slot(212664, HIDE, CORPSE, 2) } }, nil, { now = 100 })), nil)
end)

test("fishing respects the option", function()
	local win = { fishing = true, slots = { Slot(220137, 8, NODE) } }
	eq((ns.Gather_Classify(win, nil, { now = 1, fishing = true })), "fishing")
	eq((ns.Gather_Classify(win, nil, { now = 1, fishing = false })), nil)
end)

test("learn an unknown herb spell after two windows", function()
	local learned, pending = {}, {}
	local cast = { spellID = 999001, at = 1 }
	local win = { slots = { Slot(210796, HERB, NODE) } }
	eq(ns.Gather_Learn(learned, pending, cast, win, "herbalism"), nil)
	eq(ns.Gather_Learn(learned, pending, cast, win, "herbalism"), "herbalism")
	eq(learned[999001], "herbalism")
end)

test("never learn from known non-gathering spells", function()
	local learned, pending = {}, {}
	ns.Gather_Learn(learned, pending, { spellID = 3365 }, {}, "mining")
	ns.Gather_Learn(learned, pending, { spellID = 3365 }, {}, "mining")
	eq(learned[3365], nil)
end)
```

  Also: `isFromItem` and `Item-` sources → nil; a cast older than 3 s is ignored; a skinning cast on a `GameObject`
  window → nil (sources don't fit); `SpellKind` by localized name; mixed contents (2 ore, 1 herb) → mining; empty slots
  → nil.

- [ ] **Step 2: Run** `lua Tomte/tests/test_gather.lua` from AddOns. Expected: FAIL (`Gather_ParseGUID` is nil).
- [ ] **Step 3: Implement** the functions above in `Modules/Gather/Data.lua` (header comment: pure, unit-tested).
  "Mostly" = more than half of the counted units of gather-subclass items.
- [ ] **Step 4: Run** the test file. Expected: all `ok`.

### Task 2: Run model and history (`Modules/Gather/Data.lua`, part 2)

**Files:**
- Modify: `Modules/Gather/Data.lua`
- Modify: `tests/test_gather.lua`

**Interfaces:**
- Consumes: `ns.Value_LootAdd(loot, itemID, link, count, unit, category)`, `ns.Value_LootTotals(loot, priceNow, skip)`
  from `Modules/Value/Data.lua`.
- Produces:
  - `ns.Gather_NewRun(guid, now, baseline)` → run `{ guid, name, class, start, lastAt, manual, gathers = 0, nodes = 0,
    seen = {}, kinds = {}, items = {}, finds = {}, zones = {}, nodeTypes = {}, skill = {}, knowledge = {}, drops = {} }`.
    `baseline = { name, class, manual }`.
  - `ns.Gather_AddGather(run, g)`: `g = { at, kind, sources = { guid... }, mapID, objectID, nodeName }`. Adds one gather
    per source, a node per source GUID not in `run.seen`, per-kind and per-zone node counts, node types by object ID
    (name kept when given). Moves `lastAt`.
  - `ns.Gather_AddItem(run, it)`: `it = { itemID, link, count, unit, rank, quality, kind, mapID, at }`. Uses
    `Value_LootAdd(run.items, ...)` with category `"gathered"`, sets `e.rank`, `e.q`, `e.kind`; adds `unit * count` to
    `run.zones[mapID].v`. Returns the entry.
  - `ns.Gather_AddFind(run, f)`: `f = { kind = "item" | "drop", itemID?, link?, skillLine?, at }`, max 20 kept.
  - `ns.Gather_IsFind(quality)` → `quality >= 3`.
  - `ns.Gather_Skill(run, skillLine, level)` and `ns.Gather_Knowledge(run, skillLine, available)`: first reading sets
    `from` / `last`; later readings move `to`, and knowledge adds only positive steps to `gained`.
  - `run.kinds[kind] = { nodes, gathers }`, `run.zones[mapID] = { nodes, v }`, `run.nodeTypes[objectID] = { n, name }`.
  - `ns.Gather_Duration(run, now, live)` → seconds: finished (`live` false) `max(lastAt - start, 60)`; live
    `max(min(now, lastAt + 120) - start, 60)`.
  - `ns.Gather_Numbers(run, now, live, priceNow)` → `{ duration, nodes, gathers, nodesPerHour, value, valuePerHour, mainKind }`.
    `value` is nil when no item had a price. `mainKind` = kind with most nodes (ties in `GATHER_KINDS` order).
  - `ns.Gather_Idle(run, now, idle)` → true when `now - lastAt >= idle`.
  - `ns.Gather_Resume(run, guid, now, idle)` → `"continue" | "finish" | "none"` (none when no run; finish for another
    GUID or timed out).
  - `ns.Gather_Keep(run, minNodes)` → true when `run.manual` or `run.nodes >= minNodes`.
  - `ns.Gather_Compact(run)` → copy without `seen`, items trimmed to the 15 most valuable, finds as is.
  - `ns.Gather_Archive(runs, copy, keepCount)`: newest first, at most `keepCount` per GUID.
  - `ns.Gather_Filter(runs, scope, guid, since, kind)` and `ns.Gather_Totals(list, now, priceNow)` → `{ count, duration,
    nodes, value, nodesPerHour, valuePerHour }`.
  - `ns.Gather_ItemTotals(list)` → `{ { itemID, link, ranks = { [rank] = n }, n, v } }` sorted by value then count;
    items of different ranks are separate item IDs and stay separate rows grouped by `link` name later in the page.
  - `ns.Gather_ZoneStats(list)` → `{ { mapID, kind, runs, nodes, seconds, value, nodesPerHour, valuePerHour } }`;
    each run's duration is split over its zones by node share.
  - `ns.Gather_SessionSummary(sessionGather, run)` (adds a finished or live run into `session.gather = { runs, nodes,
    value }`) and `ns.Gather_SessionLine(g, money)` → "gathered 42 nodes · 3,860g" (no value part without prices) or nil.

- [ ] **Step 1: Write the failing tests:**

```lua
local function Run()
	return ns.Gather_NewRun("Player-1", 1000, { name = "Aldric", class = "PALADIN" })
end

test("nodes vs gathers", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1010, kind = "skinning", sources = { "Creature-0-1-2-3-1-A", "Creature-0-1-2-3-1-B",
		"Creature-0-1-2-3-1-C" }, mapID = 2248 })
	eq(r.nodes, 3); eq(r.gathers, 3)
	for i = 1, 3 do
		ns.Gather_AddGather(r, { at = 1020 + i, kind = "mining", sources = { NODE }, mapID = 2248 })
	end
	eq(r.nodes, 4); eq(r.gathers, 6); eq(r.kinds.mining.nodes, 1)
end)

test("idle end at the last gather", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1600, kind = "mining", sources = { NODE } })
	eq(ns.Gather_Idle(r, 2199, 600), false)
	eq(ns.Gather_Idle(r, 2200, 600), true)
	eq(ns.Gather_Duration(r), 600)
end)

test("live duration is capped two minutes after the last gather", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1300, kind = "mining", sources = { NODE } })
	eq(ns.Gather_Duration(r, 5000, true), 420)
end)

test("resume rules", function()
	local r = Run()
	r.lastAt = 1000
	eq(ns.Gather_Resume(r, "Player-1", 1500, 600), "continue")
	eq(ns.Gather_Resume(r, "Player-1", 1700, 600), "finish")
	eq(ns.Gather_Resume(r, "Player-2", 1100, 600), "finish")
	eq(ns.Gather_Resume(nil, "Player-1", 1100, 600), "none")
end)

test("knowledge counts gains, not spending", function()
	local r = Run()
	ns.Gather_Knowledge(r, 2881, 4)
	ns.Gather_Knowledge(r, 2881, 6)
	ns.Gather_Knowledge(r, 2881, 1) -- spent 5
	ns.Gather_Knowledge(r, 2881, 2)
	eq(r.knowledge[2881].gained, 3)
end)
```

  Also: `Duration` floor of 60 s; `Numbers` per hour and nil value without prices; `mainKind` with mixed kinds and a tie;
  `Keep` manual vs `minNodes`; `Archive` keeps `keepCount` per GUID and newest first; `Filter` by scope, since and kind;
  `Totals` over two runs; `ItemTotals` keeps ranks apart; `ZoneStats` time split (a 60-minute run with 30 nodes in zone A
  and 10 in zone B gives A 45 minutes); `Skill` from/to; `SessionLine` nil for empty; "book only cleared slots" is
  covered in Task 3's pure helper `ns.Gather_Booked(pendingSlots, slot)` (below) and tested here: a slot booked once,
  a second clear of the same slot ignored, unknown slots ignored.

- [ ] **Step 2: Add `ns.Gather_Booked(pending, slot)`** to the produce list and its tests: `pending[slot] = it` from the
  window read; returns `it` once and removes it.
- [ ] **Step 3: Run** the tests. Expected: FAIL on the new names.
- [ ] **Step 4: Implement.** Keep `run.seen` capped at 500 GUIDs (wipe the oldest half when over).
- [ ] **Step 5: Run** the tests. Expected: all `ok`.

### Task 3: Detection (`Modules/Gather/Detect.lua`)

**Files:**
- Create: `Modules/Gather/Detect.lua`

**Interfaces:**
- Consumes: Task 1 and 2 functions; `ns.Value_ItemPrice(link)`; `ns.Content_Get(ns.ContentExpansion(), "profs")`.
- Produces:
  - `ns.GatherDetect_Start(db, handlers)` / `ns.GatherDetect_Stop()`. `handlers = { gather(g), item(it), find(f),
    skill(skillLine, level), knowledge(skillLine, available) }`, called by Gather.lua.
  - `ns.GatherDetect_Why()` → lines for `/tomte gather why`.
  - `ns.GatherDetect_ReadProgress()`: reads skill and knowledge of every gathering profession now (run start).

Events and what each does:
- `UNIT_SPELLCAST_SENT` (registered with `RegisterUnitEvent(..., "player")`): remember `castGUID → target` when neither
  is secret (node name).
- `UNIT_SPELLCAST_SUCCEEDED` (player): when `spellID` isn't secret, `last = { spellID, kind = Gather_SpellKind(...),
  at = GetTime(), name }`. Secret → `last = nil`.
- `LOOT_READY` and `LOOT_OPENED`: build `win` once per window (guard: `windowOpen` flag reset at `LOOT_CLOSED`).
  - Per slot `1..GetNumLootItems()`: `GetLootSlotType(slot) == Enum.LootSlotType.Item`, `GetLootSlotLink`,
    `GetLootSlotInfo` (quantity, quality), `C_Item.GetItemInfoInstant(link)` (itemID, classID, subClassID), sources
    from `GetLootSourceInfo` (odd returns), each checked with `issecretvalue`.
  - `win.fishing = IsFishingLoot()`, `win.fromItem` = `LOOT_OPENED`'s `isFromItem` (when `LOOT_READY` came first, a
    later `isFromItem = true` cancels the window).
  - `kind, reason = Gather_Classify(win, castIfFresh, { now = GetTime(), fishing = db.fishing })`; when nil and the cast
    is readable, `Gather_Learn(db.spells, pending, ...)` with the contents' kind.
  - On a gather: `handlers.gather({ at = GetServerTime(), kind, sources, mapID = C_Map.GetBestMapForUnit("player"),
    objectID, nodeName })`, then keep each slot as pending `{ itemID, link, count, unit = Value_ItemPrice(link),
    rank = C_TradeSkillUI.GetItemReagentQualityByItemInfo(link), quality, kind, mapID }`.
  - Remember the window for `why` (sources' kinds, cast, kind, reason).
- `LOOT_SLOT_CLEARED(slot)`: `Gather_Booked(pending, slot)` → `handlers.item(it)`; `Gather_IsFind(it.quality)` →
  `handlers.find`. Then re-read skill, knowledge and drop quests (below), throttled to once per window.
- `LOOT_CLOSED`: clear the window and pending slots.
- `SKILL_LINES_CHANGED`, `TRAIT_TREE_CURRENCY_INFO_UPDATED`: re-read progress when a run is on.

Progress reading (only gathering professions the character has, from `GetProfessions()` / `GetProfessionInfo` 7th
return in `GATHER_SKILL_LINES`):
- skill: `child = profs[base] and profs[base].child`; `C_TradeSkillUI.GetProfessionInfoBySkillLineID(child).skillLevel`
  when `child` and the call works (pcall), else `GetProfessionInfo(index)`'s rank;
- knowledge: `C_ProfSpecs.SkillLineHasSpecialization(child)` then `GetCurrencyInfoForSkillLine(child).numAvailable`;
- drops: count of `profs[base].drops` plus `bigDrop` completed (`C_QuestLog.IsQuestFlaggedCompleted`); a count higher
  than the last reading → `handlers.find({ kind = "drop", skillLine = base })` per new drop.

- [ ] **Step 1: Write the file** following the list above; build the localized anchor `names` table at start from
  `C_Spell.GetSpellName(id)` for each `GATHER_SPELLS` id (skip nil).
- [ ] **Step 2: Read it once against the spec's rules** (casts older than 3 s ignored, `GATHER_NOT` before learning,
  every API result checked for secrets).
- [ ] **Step 3: Run all tests** (`for t in Tomte/tests/test_*.lua; do lua "$t"; done`), including the theme scan.

### Task 4: Module and run lifecycle (`Modules/Gather/Gather.lua`), TOC

**Files:**
- Create: `Modules/Gather/Gather.lua`
- Modify: `Tomte.toc` (after `Modules/Pets/Pets.lua`: `Modules/Gather/Data.lua`, `Detect.lua`, `Tracker.lua`,
  `Page.lua`, `Gather.lua`)

**Produces:**
- `ns.Gather_Current()` → the live run or nil (public; the Fishing module keeps no stats of its own).
- `ns.Gather_Start(manual)`, `ns.Gather_End(reason)` (`"idle" | "manual" | "switch"`).
- `ns.Gather_SessionText(session)` → `Gather_SessionLine(session.gather, ns.Alts_Gold)` or nil when the module is off.
- `ns.gatherDB`, `ns.gatherModule`.

Behavior:
- `RegisterModule({ key = "gather", name = "Gathering", category = "General", enabledByDefault = true, defaults = …,
  init, toggle, commands, options, home })` with defaults exactly as in the spec.
- On toggle on: `GatherDetect_Start(db, handlers)`; check `Gather_Resume(db.run, UnitGUID("player"), GetServerTime(),
  db.idle)` at `PLAYER_ENTERING_WORLD` (finish → `Gather_End("switch")` using the stored `lastAt`).
- `handlers.gather`: no run and `db.auto` → `Gather_Start(false)`; no run and not auto → ignore. Then `AddGather`,
  `GatherDetect_ReadProgress()` on the first gather, `ns.GatherTracker_Refresh()`.
- `handlers.item` / `find` / `skill` / `knowledge`: update the run; a find with `db.toastFind` →
  `ns.Toast_Show({ owner = "gather", label = "Rare find", accent = "accent", title = <item name or "Knowledge drop">,
  icon, hold = 6 })`.
- Idle: a `C_Timer.NewTicker(15, …)` while a run is on → `Gather_Idle` → `Gather_End("idle")`.
- `Gather_End`: `Gather_Keep(run, db.minNodes)` → `Gather_Archive(db.runs, Gather_Compact(run), db.keepCount)`, add to
  `ns.Session_Current().gather` with `Gather_SessionSummary`, toast when `db.toastEnd` ("Mining run" title, "32m · 42
  nodes · 3,860g (7,210g/h)", click opens the page); then `db.run = nil`, tracker hidden.
- Commands: `""` opens the page (`ns.Panel_OpenPage("gather")`), `start`, `end`, `why`.
- Options: header; checkboxes auto, fishing, tracker shown, toastEnd, toastFind; sliders idle (3–30 min, stored in
  seconds), minNodes (1–20), keepCount (10–200); button "Clear run history" with confirm.

- [ ] **Step 1: Write the module** and the TOC lines.
- [ ] **Step 2: Run all tests** (module registry test `tests/test_modules.lua` loads every registered module shape).
- [ ] **Step 3: In-game check list item** for Task 9: mine 2 nodes, `/dump TomteDB.gather.run.nodes`.

### Task 5: Tracker (`Modules/Gather/Tracker.lua`)

**Files:**
- Create: `Modules/Gather/Tracker.lua`

**Produces:** `ns.GatherTracker_Refresh()`, `ns.GatherTracker_ResetPosition()`.

- A frame with `UI.Panel(frame)`, movable, position in `db.tracker.point` (same pattern as `Modules/Alts/List.lua`'s
  crafting tracker: `SavePoint`, `Place`).
- `ns.EditMode_Register({ name = "Gathering run", frame, refresh = ns.GatherTracker_Refresh, saved = SavePoint })`;
  in Edit Mode with no run it shows a preview with sample numbers.
- Rows (texts via `UI.Text`, roles: title "heading", numbers font "number", muted "textMuted", finds "accent"):
  title (kind icon from the profession's `GetProfessionInfo` icon, else a fixed icon per kind), time (updates each second
  through a 1 s ticker while shown), nodes and nodes/h, value and gold/h (or "no prices"), top 3 items (value, else
  count) with the rank atlas from `C_TradeSkillUI.GetItemReagentQualityInfo(link)` (`info.iconSmall`, pcall), finds,
  skill and knowledge lines (only when there is something).
- Buttons: minimize (one line) and End (`ns.Gather_End("manual")`).
- Hidden when `db.tracker.shown` is false, no run, in a pet battle (`C_PetBattles.IsInBattle()`), or in an instance
  (`IsInInstance()`); re-checked on `PET_BATTLE_OPENING_START`, `PET_BATTLE_CLOSE`, `PLAYER_ENTERING_WORLD`.

- [ ] **Step 1: Write the tracker.**
- [ ] **Step 2: Run all tests** (theme scan catches stray colors and fonts).

### Task 6: Gathering page (`Modules/Gather/Page.lua`)

**Files:**
- Create: `Modules/Gather/Page.lua`

**Produces:** `ns.GatherPage = { title = "Gathering", Create, Refresh }`, three views behind buttons (as in
`Modules/Pets/Page.lua` / BoardPage):
- **Runs:** filters (this character / all, this week / all time, kind) stored in `db.pageScope`, `db.pageRange`,
  `db.pageKind`; totals line from `Gather_Totals`; rows: when, character (class color), kind, time, nodes, nodes/h, value,
  gold/h, main zone (`C_Map.GetMapInfo(mapID).name`). The live run first, marked "now". Click a row → a detail pane:
  items with ranks and counts, finds, skill, knowledge, zones, node types (`nodeName` or "Node <objectID>").
- **Items:** `Gather_ItemTotals` over the filtered runs; one row per item name with ranks side by side.
- **Zones:** `Gather_ZoneStats` rows: zone, kind, runs, nodes/h, gold/h, sorted by gold/h (nodes/h without prices).
- Week start as in `Modules/Recap/SessionsPage.lua` (`C_DateAndTime.GetSecondsUntilWeeklyReset`).

- [ ] **Step 1: Write the page.**
- [ ] **Step 2: Run all tests.**

### Task 7: Integration (Home, Next up, Recap, Sessions)

**Files:**
- Modify: `Modules/Gather/Gather.lua` (home entries)
- Modify: `Modules/Recap/Recap.lua` (`Summarize`, `Session_OnEnd`)
- Modify: `Modules/Recap/History.lua` (`Recap_Compact` keeps `gather`)
- Modify: `Modules/Recap/Scene.lua` (one more text line when `summary.gatherText`)
- Modify: `Modules/Recap/SessionsPage.lua` (`SessionTooltip` line)
- Modify: `tests/test_history.lua`

Steps:
- [ ] **Step 1: Failing test** in `tests/test_history.lua`: `Recap_Compact(session, extra)` with `session.gather =
  { runs = 1, nodes = 42, value = 38600000 }` keeps `copy.gather` equal to it, and nil when absent.
- [ ] **Step 2: Run** `lua Tomte/tests/test_history.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** `gather = session.gather` in the `Recap_Compact` copy. Run: PASS.
- [ ] **Step 4: Recap card:** in `Summarize`, `gatherText = ns.Gather_SessionText and ns.Gather_SessionText(session)`;
  `Gather_SessionText` includes the live run when `session` is the current one. In `Recap/Scene.lua` (next to
  `summary.lootText`, line ~147) append `"  -  " .. summary.gatherText` to the sources line.
- [ ] **Step 5: Sessions tooltip:** `GameTooltip:AddDoubleLine("Gathering", ns.Gather_SessionLine(h.gather,
  ns.Alts_Gold))` when `h.gather` and `ns.Gather_SessionLine` exist.
- [ ] **Step 6: Home entries** in `Gather.lua`:
  - `{ kind = "page", key = "gather", order = 8, name = "Gathering", icon = <Mining profession icon file ID>, page =
    ns.GatherPage, summary = LastRunLine }`;
  - `{ kind = "next", key = "nextgather", name = "Gathering knowledge drops", score = 35, candidates = NextDrops,
    description = "Weekly knowledge drops your gathering professions can still find." }`. `NextDrops` uses
    `ns.ContentAtMax()` and the drop quest counts from `GatherDetect`; key `gather:drops:<skillLine>`, state = drops
    done (so a dismissal returns when the count changes), click opens the page.
- [ ] **Step 7: Run all tests.**

### Task 8: Docs

**Files:**
- Modify: `README.md` (module table row "Gathering", commands line `/tomte gather start` / `end` / `why`, Credits:
  gathering spell IDs from GatherMate2's collector and Wowhead, IDs only)
- Modify: `CHANGELOG.md` (Unreleased: "Gathering: tracks your mining, herbalism, skinning and fishing runs (nodes,
  items with ranks, gold per hour, rare finds, skill and knowledge, zones) with a small tracker, an end-of-run toast
  and a Gathering page; the recap card and Sessions page show what you gathered.")

- [ ] **Step 1: Write both.**
- [ ] **Step 2: Run all tests.**

### Task 9: Review and in-game check

- [ ] **Step 1:** One reviewer agent reads the branch diff against the spec and this plan (Review focus first). Fix its
  findings and re-run the tests.
- [ ] **Step 2:** Give the user this checklist (`/reload` first, BugSack open):
  1. Mine 3 nodes in Khaz Algar: the tracker appears with nodes, items and their rank icons, value and g/h.
  2. `/tomte gather why` after a node: shows the cast spell ID, `GameObject`, kind mining, reason "cast …".
  3. Open a treasure chest: `why` says "opening"; the node count doesn't change.
  4. Mine with a mob attacking you: no error; the node still counts (reason "contents: ore") or is skipped.
  5. `/reload` mid-run: the tracker comes back with the same numbers.
  6. `/tomte gather end`: end toast, the run on the Gathering page with items, zones and skill.
  7. Edit Mode: move "Gathering run"; it stays after `/reload`.
  8. `/tomte recap`: the card shows "Gathered N nodes · …".
  9. If a skill point was gained: `/dump TomteDB.gather.runs[1].skill` shows from/to.
- [ ] **Step 3:** After the user confirms, commit (`Tomte: Gathering module …`) with the noreply identity.
