# Collect Here Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module that lists missing mounts, pets and achievements for the viewed world map zone, in a world map side tab, with zone-arrival and rare-up toasts.

**Architecture:** Pure parsing and matching live in `Collect/Data.lua` (plain Lua tests). `Collect/Catalog.lua` builds the mount and pet catalogs in per-frame chunks and an achievement index through a new shared achievement walker (`Achievements/Walk.lua`), which Almost Done's scan also moves onto. A new shared `Panel/MapTabs.lua` owns the world map side tabs, so the Teleports tab and the Collect tab switch each other off cleanly.

**Tech Stack:** WoW retail 12.1 Lua (Interface 120100), plain Lua 5.x for tests (`lua Tomte/tests/test_x.lua` from the AddOns folder).

**Spec:** `docs/superpowers/specs/2026-10-04-tomte-collect-here-design.md`

## Global Constraints

- `## Interface: 120100`. Use the addon namespace `local addonName, ns = ...`. No new globals.
- No combat logic. Journals open only out of combat (`InCombatLockdown()`).
- Never touch the user's journal or Toy Box filters.
- The tab never calls `QuestMapFrame:SetDisplayMode` (it would taint the quest log).
- enUS source text. Matching is lowercase and exact for zone values, whole-word for achievements.
- No commit until the user has confirmed it in game (CLAUDE.md).

## Review Focus

1. **Instance names containing a comma** ("Amirdrassil, the Dream's Hope (Mythic)") must still match the entrance
   name. Tested in Task 1.
2. **Short or generic map names** like "Dalaran" inside longer words must not match achievements, and only whole words
   count. Tested in Task 1 (`Collect_TextMentions`).
3. **A source with no zone line** (promotion, shop) must never appear. Tested in Task 1 (`Collect_ParseSource` zones
   empty).
4. **The walker joined mid-pass** must still visit every category exactly once for the late subscriber. Tested in
   Task 2.
5. **Both tabs enabled:** switching between Teleports, Collect and Blizzard's tabs must leave exactly one content
   frame shown. This is in-game only; it goes on the test checklist (Task 6).

---

### Task 1: Collect/Data.lua (pure logic)

**Files:**
- Create: `Tomte/Modules/Collect/Data.lua`
- Test: `Tomte/tests/test_collect.lua`

**Interfaces (Produces):**
- `ns.Collect_Clean(text) -> string`: strips `|cXXXXXXXX`, `|r` and `|T...|t`, and trims.
- `ns.Collect_ParseSource(raw) -> { lines = { {label, value, raw} }, zones = { candidate,... }, drop = name|nil, line = display string|nil }`
  - `label` is lowercased and has no colon. `value` is cleaned; `raw` keeps the texture codes.
  - `zones` holds lowercased candidates from the `zone`, `location` and `pet battle` lines, with aliases expanded and
    qualifiers dropped.
  - `line` is the display line, made from the first of drop, vendor, quest, achievement, treasure, world event, pet
    battle ("Wild pet battle"), profession or discovery, plus " · " and the raw cost when there is one.
- `ns.Collect_Candidates(value) -> list`: the whole value, the pieces split on ", ", and neighbouring pairs joined
  back with ", ". Each is lowercased with a trailing "(...)" removed.
- `ns.Collect_MatchZones(zones, nameSet) -> matchedName|nil`, where `nameSet` is `[lowercased name] = display name`.
- `ns.Collect_TextMentions(text, names) -> bool`: whole-word, case-insensitive, names of 4+ characters.
- `ns.Collect_Sections(entries, opts) -> { {key, title, entries} }`
  - Entries are `{ kind = "mount"|"pet"|"ach", name, upNow, percent }`. `opts.show[kind]` and `opts.collapsed[kind]`
    are honoured; a collapsed section is still returned with `collapsed = true`.
  - Mounts and pets sort with up-now first, then by name. Achievements sort by percent descending, then name.
- `ns.Collect_ZoneToastText(zoneName, counts) -> string`, e.g. "2 mounts, 3 pets, 18 achievements left".

- [ ] **Step 1: Write the failing tests** in `Tomte/tests/test_collect.lua` (same harness as test_teleports.lua):
  - Doomwalker: `|cFFFFD200Drop: |rDoomwalker|n|cFFFFD200Zone: |rTanaris` gives zones `{tanaris}`, drop
    `Doomwalker`, line `Drop: Doomwalker`.
  - Vendor with cost: the line contains "Vendor: Ando the Gat" and " · 777", and zones include
    "liberation of undermine".
  - Fyrakk: `Zone: |rAmirdrassil, the Dream's Hope (Mythic)` matches the nameSet entry "amirdrassil, the dream's hope".
  - Pet battle list `Azshara, Eversong Woods (Burning Crusade), Nagrand` gives candidates that include
    "eversong woods" and "nagrand".
  - Promotion source `|cFFFFD200Promotion:|r Blizzard Store` gives empty zones and line "Promotion: Blizzard Store".
  - Alias: `Zone: |rCapital Cities` matches a nameSet that only has "orgrimmar".
  - `Drop: World Drop` gives a nil drop.
  - TextMentions: "Explore Hallowfall" with {"Hallowfall"} is true; "Hallowfallen" is false; "Org" (short) is false.
  - Sections: order, up-now first, achievement percent sort, hidden and collapsed kinds.
  - Toast text: plurals and zero kinds left out.
- [ ] **Step 2:** `lua Tomte/tests/test_collect.lua` fails (the file doesn't exist yet).
- [ ] **Step 3:** Implement Data.lua.
- [ ] **Step 4:** The tests pass.

### Task 2: Achievements/Walk.lua, and Scan.lua onto it

**Files:**
- Create: `Tomte/Modules/Achievements/Walk.lua` (TOC: before Scan.lua)
- Modify: `Tomte/Modules/Achievements/Scan.lua` (the Step/scanner loop is replaced by a subscription)
- Test: `Tomte/tests/test_achwalk.lua`

**Interfaces (Produces):**
- `ns.AchWalk_Join(key, handlers)`, with `handlers = { visit = fn(id, categoryID), category = fn() | nil, finish = fn() | nil }`.
  Joining again with the same key restarts that subscriber.
- `ns.AchWalk_Leave(key)`
- `ns.AchWalk_Progress(key) -> 0..1 | nil`
- `ns.AchWalk_SetSkipped(fn(categoryID) -> bool)`: Scan.lua passes the Feats and Legacy test (it needs
  `ns.Ach_CategoryInfo`).
- A subscriber that joins while a category is in progress starts at the next category boundary and finishes after
  `#categories` category ends. When the list ends with subscribers left, the walk wraps to 1. With no subscribers,
  the frame hides.
- Budget: 4 ms per frame (`debugprofilestop`).

- [ ] **Step 1: Failing test.** Stub `CreateFrame` (a frame with SetScript/Show/Hide/IsShown), `GetCategoryList`,
  `GetCategoryNumAchievements`, `GetAchievementInfo(cat, i)` and `debugprofilestop` (a counter). Drive it by calling
  the stored OnUpdate. Check:
  - Two subscribers that join together visit every achievement once and finish on the same frame.
  - Subscriber B joins after A has done a category: B still visits every achievement exactly once and finishes later.
  - A skipped category gets no visits.
  - Leave stops the visits.
- [ ] **Step 2:** It fails.
- [ ] **Step 3:** Implement Walk.lua.
  - Scan.lua: `Ach_StartScan` builds `scan = { records = {}, metaLinks = {}, pins = ns.Ach_PinSet() }`, then
    `ns.AchWalk_Join("ach", { visit = Visit, category = function() scan.pins = ns.Ach_PinSet(); ns.AchDock_ScanStatus() end, finish = Finish })`.
  - `Ach_StopScan` calls `ns.AchWalk_Leave("ach")`. `Ach_ScanProgress` returns `scan and ns.AchWalk_Progress("ach")`.
  - The SKIPPED_TOP check moves into the skip callback.
- [ ] **Step 4:** test_achwalk and test_achievements pass.

### Task 3: Panel/MapTabs.lua, and Teleports onto it

**Files:**
- Create: `Tomte/Panel/MapTabs.lua` (TOC: after Panel/Panel.lua)
- Modify: `Tomte/Modules/Teleports/MapTab.lua` (CreateTab/CreatePanel/ShowOurs/HideOurs/OnDisplayMode replaced)

**Interfaces (Produces):**
- `ns.MapTabs_Add({ key, icon, tooltip, title, onShow = fn(panel), onHide = fn(panel), onMapChanged = fn(panel) }) -> tab, panel`
  - The panel is created with the dark background and a `panel.title` font string. Tabs stack in the order they
    were added, under `QuestMapFrame.MapLegendTab`, counting only the shown ones.
  - Returns nil when `QuestMapFrame.MapLegendTab` is missing.
- `ns.MapTabs_SetShown(key, shown)`: hiding the active tab gives Blizzard's frames back.
- `ns.MapTabs_Select(key)`, `ns.MapTabs_IsActive(key) -> bool`
- One `hooksecurefunc(QuestMapFrame, "SetDisplayMode")` and one `hooksecurefunc(WorldMapFrame, "OnMapChanged")`
  for all tabs.

- [ ] **Step 1:** Implement MapTabs.lua by lifting the existing logic from Teleports/MapTab.lua (ShowOurs, HideOurs,
  OnDisplayMode, CreateTab, panel background), made generic over a list of tabs.
- [ ] **Step 2:** Teleports/MapTab.lua `Build()` calls `ns.MapTabs_Add` with `onShow = Refresh`,
  `onHide = function() Detach(); HidePin() end` and `onMapChanged = Refresh`.
  - `active` becomes `ns.MapTabs_IsActive("tp")`. `TpTab_SetEnabled` calls `ns.MapTabs_SetShown`. `TpTab_Open`
    calls `ns.MapTabs_Select("tp")`.
- [ ] **Step 3:** `luac -p` on both files, and test_teleports passes.

### Task 4: Collect/Catalog.lua

**Files:** Create `Tomte/Modules/Collect/Catalog.lua`

**Interfaces:**
- Consumes: `ns.Collect_ParseSource`, `ns.Collect_MatchZones`, `ns.Collect_TextMentions`, `ns.AchWalk_*`,
  `ns.Tp_MapNames(mapID) -> { names = {...} }`, `ns.Ach_ReadCriteria`, `ns.Ach_Percent`.
- Produces:
  - `ns.Collect_Start()` builds the catalogs (chunked, 4 ms per frame), then joins the walker.
  - `ns.Collect_Stop()`
  - `ns.Collect_State() -> { mounts = bool, pets = bool, achievements = bool, progress = 0..1 }` (each true when ready).
  - `ns.Collect_ResolveMap(mapID) -> mapID, info, kind`: kind is "zone", "continent" or nil; micro and orphan maps
    walk up to a zone.
  - `ns.Collect_ForMap(mapID) -> entries, zoneName | nil` (the "nothing here" case for world and cosmic). Entries:
    - mount: `{ kind="mount", id=mountID, spellID, name, icon, source=raw, line, zone, drop }`
    - pet: `{ kind="pet", id=speciesID, name, icon, source=raw, line, zone, drop }`
    - ach: `{ kind="ach", id, name, icon, points, percent, done, total }`
  - `ns.Collect_Unmatched(mapID) -> { value, ... }` for `/tomte collect here`.
  - `ns.Collect_Earned(kind, id)` drops an entry.
  - `ns.Collect_ApplyVignettes(entries, mapID)` sets `e.upNow = { x, y, mapID }` when a vignette's name equals
    `e.drop` (lowercased).
  - `ns.Collect_SetChanged(fn)`
- [ ] **Step 1:** Implement. The continent view uses `C_Map.GetMapChildrenInfo(continent, Enum.UIMapType.Zone)`;
  each zone gets its own nameSet through `Tp_MapNames`, so each entry carries its zone.
  - Achievement names: the map name for a zone or dungeon map; the continent's name plus each child zone name for a
    continent.
  - Per-map results are cached until the catalogs change.
- [ ] **Step 2:** `luac -p`.

### Task 5: Collect/Tab.lua + Collect/Collect.lua + TOC + .gitignore check

**Files:** Create `Tomte/Modules/Collect/Tab.lua` and `Tomte/Modules/Collect/Collect.lua`. Modify `Tomte/Tomte.toc`.

- [ ] **Step 1: Tab.lua.** `ns.MapTabs_Add{ key = "collect", ... }`, with rows modelled on the Teleports rows.
  - Header rows toggle `db.collapsed[kind]`.
  - Tooltip: the raw source with `|n` turned into newlines, or the achievement hyperlink.
  - OnMouseUp: shift + left gives a link; left opens the journal; right on an up-now row sets the waypoint.
  - API: `ns.CollectTab_Init(db)`, `ns.CollectTab_SetEnabled(bool)`, `ns.CollectTab_Refresh()`,
    `ns.CollectTab_Open()`.
- [ ] **Step 2: Collect.lua.** The module (key `collect`, name "Collect here", category "Collections",
  enabledByDefault true) with the defaults from the spec, the events, the zone and rare toasts, the commands `open`,
  `here` and `test`, and options (show kinds, toasts).
- [ ] **Step 3: TOC.** Add `Panel/MapTabs.lua` and `Modules/Achievements/Walk.lua`, and after Recap add:
  ```
  Modules/Collect/Data.lua
  Modules/Collect/Catalog.lua
  Modules/Collect/Tab.lua
  Modules/Collect/Collect.lua
  ```
  `.gitignore` already whitelists Tomte (same addon), so there's nothing to add.
- [ ] **Step 4:** `luac -p` on all changed files, and every `tests/test_*.lua` passes.

### Task 6: Review + in-game checklist

- [ ] One fresh reviewer goes over the whole diff.
- [ ] Fix the findings.
- [ ] Report to the user with the /reload test list. No commit until confirmed.
