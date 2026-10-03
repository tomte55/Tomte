# Almost Done Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module that replaces AlmostCompletedAchievements: a list docked to the Achievements window,
reward info and preview, a meta browser, a Top 5 tracker and milestone toasts.

**Architecture:** Pure logic in `Data.lua` (unit-tested with plain Lua). `Scan.lua` owns the records and the
watch set and emits a "changed" callback. `Dock.lua` and `Tracker.lua` only read state through `ns.Ach_*`
functions. `Achievements.lua` registers the module and wires the events.

**Tech Stack:** WoW retail 12.1 Lua, Tomte's `ns.UI` widgets, `ns.Toast_Show`, `MenuUtil`, ModelScene.

**Spec:** `docs/superpowers/specs/2026-10-03-tomte-almost-done-design.md`

## Global Constraints

- TOC `## Interface: 120100`. Files load in TOC order. Data → Rewards → Metas → Scan → Dock → Tracker → module.
- `local addonName, ns = ...` in every file. No globals.
- Module key `ach`, db `TomteDB.ach`, category "Achievements", name "Almost Done".
- Blocked while `C_AddOns.IsAddOnLoaded("AlmostCompletedAchievements")`.
- No commit until the user confirms in game (CLAUDE.md).
- Tests run from the AddOns folder: `lua Tomte/tests/test_achievements.lua`.

## Review Focus

1. Achievements with 0 criteria or `reqQuantity == 0` must not divide by zero. They're skipped, or the criterion counts 0.
2. The first scan after login must not fire milestone toasts (records without a "before" value).
3. An achievement earned while pinned must leave the pins and the tracker without errors.
4. The dock must survive `AchievementFrame` not being loaded yet (load-on-demand) and opening in combat.
5. The search text can contain Lua pattern characters (`%`, `[`): use plain `find`.

Each one is pinned by a test in Task 1 (1, 2, 5) or by an in-game check in the final checklist (3, 4).

---

### Task 1: Data.lua (pure logic) + tests

**Files:** Create `Tomte/Modules/Achievements/Data.lua`, `Tomte/tests/test_achievements.lua`

**Produces:**
- `ns.Ach_Percent(criteria) -> percent, done, total, last` where `criteria` = list of `{ name, completed, quantity, required }`. Returns `nil` when the list is empty.
- `ns.Ach_Milestone(before, after, total, isPinned, fired) -> kind|nil`. `before`/`after` = `{ percent, done, left }`, `fired` = set of kinds already shown for this record. Kinds are `"lastStep"`, `"almost"`, `"pinned"`, and `threshold` is passed via `after.threshold`.
- `ns.Ach_RewardTypeFromText(text) -> "title"|"other"|nil`
- `ns.Ach_ExpansionFromChain(names) -> expansion|nil`. `ns.ACH_EXPANSIONS` is the ordered list.
- `ns.Ach_Passes(record, settings, ctx) -> bool`. `ctx` = `{ pinned = set, ignored = set, rewardType = fn(record) -> type, owned, searchText, professions = list, holidays = list, categoryName = fn }`.
- `ns.Ach_Sort(list, mode)`, `ns.Ach_TopN(records, pins, settings, ctx, n) -> list` (pinned records flagged `.pinned`).
- `ns.Ach_MetaPercent(children) -> percent, done, total`, where a completed child counts 1 and an incomplete one counts its percent / 100.

**Tests (all in test_achievements.lua):**
- [x] Percent: mixed completed/partial. Empty list → nil. required 0 → 0. Last criterion name when exactly one is left.
- [x] Milestone: crossing the threshold → almost. 2 left → 1 left → lastStep (priority over almost). Pinned progress → pinned. The same kind again (fired) → nil. No before → nil.
- [x] RewardTypeFromText: "Title Reward: X" / "Title: X" → title. "Reward: Foo" → other. "" / nil → nil.
- [x] ExpansionFromChain: {"Midnight Dungeon","Dungeons & Raids"} → Midnight. {"Battle for Azeroth"} → BfA (and not "Classic"). No match → nil.
- [x] Passes: ignored (and showIgnored), category off, expansion off ("Other" for nil), professions mine, events running, every reward filter, search with a `%` character, threshold, pins bypassing the threshold.
- [x] Sort modes: percent, points, name, steps.
- [x] TopN: pins first in pin order, completed/missing pins skipped, fill by percent, filters applied to fill.
- [x] MetaPercent.

### Task 2: Rewards.lua

**Produces:** `ns.Ach_RewardInfo(record) -> info|nil`, where info = `{ type, owned, name, displayID, itemID, icon }`. Cached per item. `ns.Ach_RewardsChanged()` clears the cache. `ns.ACH_REWARD_ICONS[type]` = an atlas or file.

### Task 3: Metas.lua

**Produces:** `ns.Ach_MetaChildren(metaID) -> list of ids`, `ns.Ach_MetaRoots()` (built-in), `ns.Ach_ParentsOf(id) -> list`, `ns.Ach_SetMetaLinks(map)`, `ns.Ach_ReadAchievement(id) -> { id, name, icon, completed, percent, done, total, reward }` (live read).

### Task 4: Scan.lua

**Produces:** `ns.Ach_StartScan()`, `ns.Ach_ScanProgress() -> 0..1|nil`, `ns.Ach_Records() -> map id→record`, `ns.Ach_OnCriteriaUpdate()`, `ns.Ach_OnCriteriaEarned(id)`, `ns.Ach_OnAchievementEarned(id)`, `ns.Ach_LoadCache()`, `ns.Ach_SetChangedCallback(fn(changedIDs, milestones))`. Uses `ns.Ach_Percent`, `ns.Ach_Milestone`, Metas.

### Task 5: Achievements.lua (module, events, toasts, commands, options) + TOC

Registers the module and wires the events to Scan. Milestones → `ns.Toast_Show`. Exposes `ns.Ach_List()` (filtered and sorted), `ns.Ach_Top()`, `ns.Ach_Pin/Unpin/IsPinned/Ignore/Unignore/Open(id)`, `ns.Ach_Settings()`.

### Task 6: Tracker.lua

**Produces:** `ns.AchTracker_Refresh(flashIDs)`, `ns.AchTracker_SetLocked(bool)`, `ns.AchTracker_Apply()` (shown/scale/combat).

### Task 7: Dock.lua

**Produces:** `ns.AchDock_Init()` (hooks Blizzard_AchievementUI), `ns.AchDock_Refresh()`, `ns.AchDock_ShowMeta(id)`.

### Task 8: Docs + .gitignore check

The README module table and commands get Almost Done. `.gitignore` already whitelists `/Tomte/` and `/docs/`.

### Final: in-game checklist for the user (the report), then commit after they confirm.
