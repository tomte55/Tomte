# EnhanceQoL + Plumber takeover, step 0 and phases 1-3: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** settings regrouped into 12 groups with a scrolling rail, plus three new modules: Quests, Loot, Instances.

**Architecture:** each module is its own folder in Tomte's module shape (pure `Data.lua` with tests, readers, UI
files, main file last). The three modules touch disjoint files and are built in parallel; shared files (TOC,
`Bindings.xml`, README, CHANGELOG, `Panel/Layout.lua`, Gear's export) are owned by the coordinator.

**Tech Stack:** WoW retail 12.1.5 Lua, Tomte's `ns.*` services, plain-Lua 5.1 unit tests.

**Spec:** `docs/superpowers/specs/2026-10-22-tomte-enhanceqol-plumber-absorption-design.md`

## Global Constraints

- All of `CLAUDE.md` applies (module shape, file headers, theme roles, events only while active, hooks inert while
  off, `UI.ContextMenu`, `ns.Confirm_Show`, `ns.EditMode_Register`, `ns.Content_Register`, no deprecated globals).
- No copied code from EnhanceQoL or Plumber (no license). Reading them for which API/event does the job is fine;
  game IDs may be taken and are credited in README.
- Verify every API on warcraft.wiki.gg / Gethe/wow-ui-source live before use. Anything needing a hardware event
  becomes one key or click per action.
- Guard GUIDs, names, gossip fields and unit info with `ns.IsSecret`.
- Midnight-only content goes through `ns.Content_Register` and follows the character's expansion.
- Clashes only warn (`conflicts` entries), never switch Tomte's feature off.
- Builders never edit the TOC, `Bindings.xml`, README, CHANGELOG, Core or another module's folder; they report
  the TOC lines, binding entries and README text they need.

## Review Focus

1. Quest automation while DialogueUI is installed: DialogueUI handles the same QUEST_*/GOSSIP_SHOW events; Tomte
   must act once and not fight its window (accept is idempotent, but gossip selection twice can pick wrong).
2. Skip key held when the window opens, and reopening the same NPC after a skip: automation must stay skipped for
   that window only.
3. Fast loot with full bags or a locked/roll item: nothing may loop, and the window (or Blizzard's) must show what
   is left.
4. Toggling Loot off mid-session: Blizzard's loot frame and loot toasts must work again without `/reload`.
5. Minimap badge with Blizzard's indicator: on Stop the original indicator returns and updates as before.

---

### Task 0: Settings regroup (coordinator)

**Files:** Modify `Panel/Layout.lua` (`ns.PANEL_GROUPS`), `Panel/Sidebar.lua` (rail becomes a ScrollFrame),
every module's `category`, `tests/test_panel_layout.lua`, `CLAUDE.md` category list.

- [ ] Groups (key, short): `tomte` Tomte, `week` Week, `quests` Quests, `gear` Gear, `professions` Profs,
  `collections` Collect, `travel` Travel, `social` Groups ("Groups & friends"), `chat` Chat, `interface`
  Interface, `class` Class, `ambience` Ambience. Assignments per the spec's table; modules not in the table keep
  their nearest group (Graphics presets and Cursor highlight move to `interface`, World quests and Gold world
  quests to `quests`, Showcase to `ambience`, Chat files to `chat`).
- [ ] Test: 12 groups, unique keys, every TOC module in a known group (existing test covers the last part).
- [ ] Rail: buttons on a scroll child; mouse wheel scrolls by one row; `RefreshRail` scrolls the selected button
  into view; no scrollbar.

### Task 1: Gear export for the reward pick (coordinator)

**Files:** Modify `Modules/Gear/RewardCard.lua`.

- **Produces:** `ns.GearRewards_BestChoice() -> index|nil`: the quest reward choice Gear Check calls a clean
  upgrade (`Pick` returns `sure == true`), nil when Gear Check is off, has no spec context, or isn't sure.

### Task 2: Quests module (builder A)

**Files:** `Modules/Quests/Data.lua` (pure), `Modules/Quests/Read.lua` (quest/gossip readers),
`Modules/Quests/Cinematics.lua`, `Modules/Quests/TalkingHead.lua`, `Modules/Quests/Items.lua`,
`Modules/Quests/Quests.lua` (main), `Data/WarWithin/Quests.lua`, `Data/Midnight/Quests.lua` (event gossip IDs via
`ns.Content_Register(exp, "questGossip", {...})`), `tests/test_quests.lua`.

- Key `quests`, name "Quests", category `quests`, `enabledByDefault = false`, per the spec's Phase 1 list.
- **Consumes:** `ns.GearRewards_BestChoice()` (look up at call time; may be nil).
- Pure decisions to test: `ns.Quests_ShouldAccept(info, rules)`, `ns.Quests_ShouldTurnIn(info, rules)`,
  `ns.Quests_RewardChoice(numChoices, bestChoice, pickForMe)` -> index|0|nil (nil = stop),
  `ns.Quests_GossipPick(options, eventIDs, already)` -> option index|nil, `ns.Quests_SkipCinematic(policy, kind,
  movieID, seen, alsoInEngine)` -> bool, `ns.Quests_SkipKeyDown(setting, shift, ctrl, alt)` -> bool.

### Task 3: Loot module (builder B)

**Files:** `Modules/Loot/Data.lua` (pure: line building, junk folding, paging), `Modules/Loot/Read.lua`
(`GetLootSlotInfo` etc. into plain tables), `Modules/Loot/Window.lua` (List and Card styles), `Modules/Loot/Feed.lua`,
`Modules/Loot/Toasts.lua` (Blizzard loot toast suppression + boss banner), `Modules/Loot/Loot.lua` (main),
`tests/test_loot.lua`.

- Key `loot`, name "Loot", category `gear`, `enabledByDefault = true`, per the spec's Phase 2 list.
- Take all: `ns.Binding_Add("LOOT_TAKE_ALL", "loot", fn)`; coordinator adds `TOMTE_LOOT_TAKE_ALL` to
  `Bindings.xml`. While the window is shown, the window's own "Take all" button does the same.
- **Consumes:** Gear Check verdict and Gold & value price only through existing `ns.Gear_*` / `ns.Value_*` exports,
  looked up at call time.

### Task 4: Instances module (builder C)

**Files:** `Modules/Instances/Data.lua` (pure: badge text, queue progress weighting, lockout summary),
`Modules/Instances/Read.lua`, `Modules/Instances/Badge.lua`, `Modules/Instances/Entrance.lua`,
`Modules/Instances/Queue.lua`, `Modules/Instances/Instances.lua` (main), `tests/test_instances.lua`.

- Key `instances`, name "Instances", category `social`, `enabledByDefault = true`, every piece its own switch,
  per the spec's Phase 3 list.
- Pure functions to test: `ns.Instances_BadgeText(info)` (examples from the spec: "5 · H", "M+12", "D8", "LFR",
  "TW", "25 · M"), `ns.Instances_QueueProgress(needs, totals)` (tanks and healers weigh more),
  `ns.Instances_LockoutSummary(saved)`.

### Task 5: Integration (coordinator)

- [ ] TOC lines in load order; `lua Tomte/tools/bugfiles.lua`; `Bindings.xml` entry.
- [ ] README: module rows, commands, layout folders, credits for IDs. CHANGELOG Unreleased `### New` lines.
- [ ] All tests green; `luac -l` global scan on every new file.
- [ ] One review per module by a fresh reviewer; fix findings.
- [ ] Hand the user one combined in-game test list; commit per task after confirmation.
