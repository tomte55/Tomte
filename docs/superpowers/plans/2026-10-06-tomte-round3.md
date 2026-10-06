# Tomte Round 3 Implementation Plan (Home polish, Alts round 2, weights for every spec, alt upgrades)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** planned, not started. The user builds it later. Start only after this branch's earlier features (Next up,
Recent, Sessions, Gold & value, Send to alt, Crafting list) have been tried in game, so new work isn't stacked on
untested code.

**Specs:**
- `docs/superpowers/specs/2026-10-06-tomte-home-polish-design.md`
- `docs/superpowers/specs/2026-10-06-tomte-alts-round2-design.md`
- `docs/superpowers/specs/2026-10-06-tomte-spec-weights-alt-upgrades-design.md`

**Tech Stack:** WoW retail 12.1 Lua addon (Tomte), plain Lua for tests (`for t in Tomte/tests/test_*.lua; do lua "$t"; done`
from the AddOns folder).

## Global Constraints

- TOC `## Interface: 120100`. No new globals. `local addonName, ns = ...`.
- Check every API on warcraft.wiki.gg and Blizzard's UI source before use; each spec's "To verify" list comes first
  in its phase.
- Nothing new is always on screen (the user's "keep it nice and structured" rule): tooltips and clicks before rows.
- No combat logic. Protected calls (character pane, summoning) skipped in combat with a short message.
- No commit of a phase until the user confirms it in game (CLAUDE.md).

## Order

Phases are independent except phase 4, which needs phase 3. Smallest first so each in-game test is short.

1. Home polish (small, UI only)
2. Alts round 2 (small pieces, no new data model)
3. Weights for every spec (data + hint changes)
4. Upgrades for alts (new per-character gear data, evaluator context, Baganator widget, mailbox group)

---

## Phase 1: Home polish

### Task 1.1: Toggle key
**Files:** `Tomte/Bindings.xml`, the `Tomte_Binding` dispatcher in Core.
- [ ] Add `TOMTE_TOGGLE` ("Toggle Tomte") calling `Tomte_Binding("TOGGLE")` → `ns.Panel_Toggle()`; `BINDING_NAME_TOMTE_TOGGLE`.

### Task 1.2: Clickable hero facts
**Files:** `Tomte/Panel/Home.lua` (hero facts become buttons), `Modules/Gear/Sheet.lua` (`ns.GearSheet_Open`),
`Modules/Upkeep/Durability.lua` (export the `list` command as `ns.Durability_List`).
- [ ] Facts as `Button`s with hover bg; tooltip builders per fact; click handlers per the spec table.
- [ ] No "Click:" line and no click when the owning module is off; Item level click refused in combat.

### Task 1.3: Rail pills
**Files:** `Tomte/Panel/Home.lua` (`CreateRailRow`: pill texture + text), `Core/Modules.lua` (document `pill`),
`Modules/Alts/Alts.lua` and `Modules/Weekly/Weekly.lua` (`pill` on their page entries), Panel options
("Counts on the rail").
- [ ] Pure `ns.Home_PillText(n)` ("" at 0, "99+") with a test in `tests/test_home.lua`.

### Task 1.4: More "Around you" blocks
**Files:** `Modules/Flight/Flight.lua` (+ a pure filter in `Coverage.lua`), `Modules/Mount/Mount.lua`,
`Core/Modules.lua` / Home options ("Around you shows").
- [ ] Flight masters block (untimed only, `maxRows = 2`, waypoint via `C_Map.SetUserWaypoint`).
- [ ] Mount favorites block (`Mount_ZoneList`, `maxRows = 2`, summon out of combat).
- [ ] Per-block checkboxes filtered in `ns.HomeEntries("around")`; tests for the filter.

## Phase 2: Alts round 2

### Task 2.1: Warband gold
**Files:** `Modules/Alts/Collect.lua` (read + event), `Data.lua` (`Alts_TotalGold(chars, warband)`),
`HomeSection.lua`, `RosterTab.lua`; `tests/test_alts.lua`.

### Task 2.2: Profession gap hints
**Files:** `Modules/Alts/Data.lua` (`ns.Alts_FreeSlots`), `HomeSection.lua` (unlit icon tooltip), `RosterTab.lua`
(footer tooltip); tests.

### Task 2.3: Roster Concentration and vault
**Files:** `Modules/Alts/RosterTab.lua` (detailed third line, row tooltip), reading Weekly through
`ns.Weekly_View` / `ns.Weekly_ConcNow`; guarded when Weekly is off.

### Task 2.4: "Learnable by" on recipe items
**Files:** `Modules/Alts/Alts.lua` (`OnItem`: recipe item branch), `Data.lua` (pure name/"+n" builder); tests.
- [ ] Settle To verify 2 (item → recipe) first.

### Task 2.5: Auctionator shopping list
**Files:** `Modules/Alts/CraftTab.lua`, `ListTab.lua` (heading link), `ListData.lua` or `Data.lua` (pure
`ns.Alts_ShoppingItems(plan, mode)`), Alts `uses`; tests.
- [ ] Settle To verify 1 (Auctionator API) in Auctionator's source first.

## Phase 3: Weights for every spec

### Task 3.1: Spec list
- [ ] A temporary debug command prints every class's spec IDs, names, roles and main stats; copy into Scales.

### Task 3.2: Fill `Gear/Scales.lua`
- [ ] DPS and tanks from the sims site, healers from the guide ladder (spec table: source and label per role).
- [ ] Sanity test per entry in `tests/test_gear.lua`.

### Task 3.3: Hints
**Files:** `Modules/Gear/Gear.lua`, `Advice.lua` (`Gear_WeightsHint` gets level/max level), `db.hinted` per
character with migration; Next up source "Sim on Raidbots" (`Modules/NextUp`); tests for the hint rules.

## Phase 4: Upgrades for alts

### Task 4.1: Store worn gear per character
**Files:** `Modules/Alts/Collect.lua` (`gear`, `specID`, `primary`, `classToken`, `gearAt`), Data.lua header comment.

### Task 4.2: Context for another character
**Files:** `Modules/Gear/Gear.lua` / `Advice.lua` (`ns.Gear_ContextForChar(char)`, pure where possible), level
check against the alt's level; tests for plate/cloth/leather alts and weight sources.

### Task 4.3: Transfer rule and cache
**Files:** `Modules/Gear/Items.lua` (bind state), new `Modules/Gear/Alts.lua` (verdict cache per link and alt,
invalidation on gear/spec/weights change); tests for the transfer rule.
- [ ] Settle To verify 1 (bind state APIs) first.

### Task 4.4: Tooltip line
**Files:** `Modules/Gear/Gear.lua` tooltip post-call ("Upgrade for Mira (Holy): +8.2%", up to 2 + "+n more").

### Task 4.5: Baganator widget
**Files:** `Modules/Gear/Gear.lua` (second `RegisterCornerWidget`, map-blue arrow, hidden when the gold arrow shows).

### Task 4.6: Mailbox group
**Files:** `Modules/Alts/SendData.lua` / `Send.lua` ("Gear for <name>", BoE only).

### Task 4.7: Settings and README
- [ ] Gear Check options from the spec; README rows for Gear Check and Alts updated.
