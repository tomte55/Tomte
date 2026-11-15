# Dungeon Journal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Forever-only "Dungeons" page in the Tomte window: every dungeon's quests, bosses and loot.

**Architecture:** `tools/journal.lua` runs AllTheThings' Forever dungeon files in an empty sandbox (stub constructors,
names taken from the comments by a text pass first) and writes `Data/Forever/Journal.lua`. A pure
`Modules/Journal/Data.lua` holds the rules (states, side filter, search, level text). `Page.lua` draws the list and the
dungeon view; `Journal.lua` registers the module (page, minimap button, command).

**Tech Stack:** Lua (WoW 1.60.1 Forever client API), Lua 5.4 locally for the tool, Lua 5.1 for tests in CI.

**Spec:** `docs/superpowers/specs/2026-11-15-tomte-dungeon-journal-design.md`

**Renamed while building** (Core/Journal.lua already owns `ns.Journal_*`): the module is `Modules/DungeonJournal/`
(main file `DungeonJournal.lua`, key `dj`), functions `ns.DJ_*`, the page `ns.DJPage`, the data
`Data/Forever/DungeonJournal.lua` (content key `dungeonJournal`) from `tools/dungeonjournal.lua`, the test
`tests/test_dungeonjournal.lua`, the binding `TOMTE_DUNGEON_JOURNAL`. Names below are the plan's originals.

## Global Constraints

- Forever only: files go in `tools/forever_list.lua` `extra`, never in `Tomte.toc`.
- AllTheThings is MIT: credit it (commit SHA) in the generated file header and README Credits.
- No WoW API in `Data.lua`; every API checked on warcraft.wiki.gg / the `forever` UI source branch.
- Show on map: `ns.Way_SetPoint` (Tomte's waypoint pin), never Blizzard's map or super-tracking.
- Theme roles only for colors and fonts; Tomte widgets (`ns.HomeKit`, `UI.Segmented`, `UI.Scroll`, `UI.Switch`).
- Coordinate with the Map session before editing `tools/forever_list.lua`, `Bindings.xml`, `Core/Core.lua`.
- No commit of module code before the user checks it in game.

## Review Focus

1. An item the client hasn't cached yet: the row shows a placeholder name and fills in on `ITEM_DATA_LOAD_RESULT`
   without the list jumping or erroring (`GetItemInfo` nil).
2. A quest with no giver NPC (starts from an item drop, `qs`/`qi`) or no coordinates: the detail says where it starts
   as far as known and shows no map button.
3. A dungeon with no quests (or none for your side) or no bosses yet (Shaper's Terrace): the tab says so instead of an
   empty pane.
4. Multi-wing dungeons (Scarlet Monastery, Dire Maul, Blackrock Spire, Maraudon, Stratholme): wing headings, levels
   per wing, no boss counted twice.
5. Class quests and other-side quests: hidden by default, shown dimmed when "Other side's quests" is on; a class quest
   for another class is never offered as yours.

---

### Task 1: Generator and data

**Files:**
- Create: `tools/journal.lua`, `Data/Forever/Journal.lua` (generated)

**Interfaces:**
- Produces: `ns.Content_Register(ns.CONTENT_FOREVER, "journal", list)`; `list` = array of instances sorted by `min`:
  `{ id, name, area, min, max, wings = { { name|nil, min, quests, bosses, rares, trash } } }`
  - quest: `{ id, name, lvl, side = "A"|"H"|nil, classes = { "MAGE", ... }|nil, giver, giverName, map, x, y,
    after = { questIDs }|nil, item (starting item)|nil, goals = { "0/1 Faldrim Anvilmar slain", ... }|nil,
    rewards = { itemIDs }|nil }`
  - boss / rare: `{ name, npc, loot = { itemIDs } }`; trash: `{ itemIDs }`.
- Run: `lua tools/journal.lua <folder with ATT's "dungeons & raids" files> <folder with its .config/constants> <sha>`

- [ ] Step 1: Write the tool. Text pass per line injects names from trailing comments: `X(<id>, {  -- Name` gets
  `_name = [==[Name]==],` after the `{`; `X(<id>),  -- Name` becomes `X(<id>, { _name = ... }),`;
  `key = <number>,  -- Name` gets `key_name = ...` next to it. Names lose `<Title>` and ` [Classic] / ...` suffixes.
  Then `load(text, name, "t", env)` (5.1: `loadstring` + `setfenv`) with an env holding only the stub constructors,
  `setmetatable`, `pairs`, `ipairs`, `type`, `tostring`, `print`, `table`, `string`, `math` and a fallback `__index`
  that returns symbol proxies (indexable, callable, concatenable) for anything else. `maps.lua` loads first so
  `MAP.X` are real uiMapIDs. Constructors return `{ kind, id, ...fields }`; a table argument with an array part is
  its `groups`. `instanceroot` records instances; `root`/`inst` (raids) are ignored.
- [ ] Step 2: Shape rules. Skip instances `760, 78789, 78790` (raids) and any with neither quests nor bosses. A wing is
  `n(<createHeader>, ...)` or `DIREMAUL_SUBMAP(...)` at instance level. Bosses: `e(...)` (name from the comment,
  `creatureID`/first of `creatureIDs`), else instance- or wing-level `n(<number>, ...)` whose description doesn't
  contain "Rare Creature". Rares: children of `n(RARES)` and the "Rare Creature" ones. Trash: items under
  `n(ZONE_DROPS)`. Loot: every `i(...)` below the boss, deduplicated, file order. Quests: `q(...)` under `n(QUESTS)`;
  rewards are its `i(...)` children; goals its `objective(...)` names; side from `races` (`ALLIANCE_ONLY`,
  `HORDE_ONLY`, or a race list); `classes` as class tokens. `max` from the comment "Blizzard lists it for levels
  A-B", else from `Data/Forever/Dungeons.lua` by name (case-insensitive, without a leading "The "). Kill order:
  `ORDER = { [63] = { 644, 642, 643, 1763, 646, 647, 645, 639 } }` (Deadmines: Cookie before VanCleef).
- [ ] Step 3: Generate into `Data/Forever/Journal.lua` (CRLF, header naming ATT, MIT, the SHA, "don't edit").
- [ ] Step 4: Verify: `luac -p Data/Forever/Journal.lua`; Hall of Thanes has 5 quests, 4 bosses in order Faldrim
  Anvilmar, Magmatus, Plunder, Durgen Dirgehammer, Faldrim's loot 271096, 270227, 271097; Scarlet Monastery has 4
  wings; Deadmines ends with Edwin VanCleef; no raid in the list.

### Task 2: Pure rules

**Files:**
- Create: `Modules/Journal/Data.lua`, `tests/test_journal.lua`

**Interfaces:**
- Produces (all pure):
  - `ns.Journal_LevelText(min, max) -> "Level 13-20" | "Level 48+"`
  - `ns.Journal_QuestFits(q, side, class) -> bool` (side nil = both sides; class list nil = any class)
  - `ns.Journal_QuestState(q, ctx) -> "done"|"active"|"low"|"other"|"open"`; `ctx = { level, side, class,
    done(id) -> bool, active(id) -> bool }`; order of checks: done, active, other (not fits), low (`lvl > level`), open.
  - `ns.Journal_Quests(inst, side, class, showOther) -> array of { wing, quest }` (fits first unless showOther adds
    the rest, dimmed by state "other")
  - `ns.Journal_QuestCount(inst, side, class) -> n`
  - `ns.Journal_Matches(inst, text, nameOf) -> bool`; `nameOf(kind, id, fallback)` gives display names ("item",
    "quest"); matches instance, wing, boss, rare, quest and loot names, case-insensitive, plain find; empty text
    matches.
  - `ns.Journal_Bosses(inst) -> array of { wing, boss }` with rares and trash as a last entry
    `{ name = "Rares and trash", loot = ... }` when any exist.
- [ ] Step 1: Tests in `tests/test_journal.lua` (made-up fixture instance with two wings): level text both forms;
  state order (a done quest of the other side is "done"); class quest for another class is "other"; Quests() hides
  other side unless showOther; QuestCount counts only fitting; Matches finds a loot item through nameOf and returns
  true for ""; Bosses appends one "Rares and trash" entry with rare loot then trash, none when both empty.
- [ ] Step 2: Run, see it fail; implement; run all tests green.

### Task 3: Page

**Files:**
- Create: `Modules/Journal/Page.lua`

**Interfaces:**
- Consumes: Task 1 data via `ns.Content_Get("journal")`, Task 2 functions.
- Produces: `ns.JournalPage = { title, Create(frame), Refresh(frame) }`, `ns.JournalPage_Show(instanceID|nil)`.

- [ ] Step 1: List view: search box (`ns.BagsKit_Search`, `UI.SearchBoxClear` behavior comes with it), rows per
  dungeon (`Kit.PoolRow`): name, sub "Level 13-20 · 5 quests", right a tick when every fitting quest is done.
- [ ] Step 2: Dungeon view: heading with name + level text and a "Back" link; `UI.Segmented` Quests | Bosses; a
  switch "Other side's quests" (saved in db). Two scroll panes: left list, right detail.
  Quests detail: title (client title else data name), level, side, state line, goals, "Starts at" giver name + zone
  (button "Show on map" → `ns.Way_SetPoint(map, x/100, y/100, giverName)`), or "Starts from an item: <item>",
  "Follows <quest>", "Turn in" from `ns.Content_Get("questEnds")[id]` (`areaID:x:y` → `ns.MapForArea`) when known,
  rewards as item rows. Bosses detail: 3D portrait (`PlayerModel`, `SetCreature(npc)`, one frame reused), loot rows.
- [ ] Step 3: Item rows: icon `C_Item.GetItemIconByID`, name in quality color (`C_Item.GetItemQualityByID`,
  `ITEM_QUALITY_COLORS`), sub = slot (`_G[equipLoc]`) and subtype from `C_Item.GetItemInfoInstant`; right: "Owned"
  (`C_Item.GetItemCount(id, true) > 0`) or the upgrade headline from `ns.Gear_Verdict(link)` when it says upgrade.
  Hover: item tooltip; click: `HandleModifiedItemClick(link)` (shift links, ctrl tries on). Uncached items:
  `C_Item.RequestLoadItemDataByID`, relayout debounced on `ITEM_DATA_LOAD_RESULT` while the page is shown.

### Task 4: Module, wiring, docs

**Files:**
- Create: `Modules/Journal/Journal.lua`
- Modify: `tools/forever_list.lua` (extra: `Data/Forever/Journal.lua` after Core/Content.lua's group; module files
  after Leveling's), regenerate `Tomte_Forever.toc` and `Core/BugFiles.lua`; `README.md`; key binding in
  `Bindings.xml` + `BINDING_NAME_TOMTE_JOURNAL` (after checking with the Map session).

- [ ] Step 1: `ns.RegisterModule{ key = "journal", name = "Dungeon journal", category = "quests", icon = <file ID>,
  enabledByDefault = true, defaults = { otherSide = false }, home = { page entry key "journal" },
  minimapButton = { name, icon, onClick, tooltip, shownByDefault = false }, commands = { { "", hidden, open } },
  options = { header, checkbox otherSide } }`; events (`ITEM_DATA_LOAD_RESULT`, `QUEST_TURNED_IN`, `QUEST_ACCEPTED`,
  `QUEST_REMOVED`) only while active and the page shown.
- [ ] Step 2: Wiring, then `lua Tomte/tools/forevertoc.lua`, `lua Tomte/tools/bugfiles.lua`, all tests, `luac -l`
  global check on the new files.
- [ ] Step 3: Hand to the user for the in-game check; commit after.
