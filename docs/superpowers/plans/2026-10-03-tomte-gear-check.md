# Tomte Gear Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module that puts a trustworthy upgrade verdict on item tooltips and Baganator bag arrows.

**Architecture:** `Data.lua` is pure Lua and holds every rule: Pawn string parsing, stat normalisation, scoring,
comparison target, set and unique checks, verdict and text. It is unit-tested with plain Lua. `Items.lua` turns item
links into descriptors with WoW APIs and keeps the equipped snapshot. `Gear.lua` is the module: tooltip post-call,
Baganator plugin, import dialog, options and commands.

**Tech Stack:** Lua 5.1 (WoW 12.1.0), Tomte module registry, `TooltipDataProcessor`, Baganator API.

**Spec:** `docs/superpowers/specs/2026-10-03-tomte-gear-check-design.md`

## Global Constraints

- `## Interface: 120100`. Prefer `C_*` APIs; verified list in the spec.
- No globals. Third-party addons are never modified. Baganator is optional (`OptionalDeps`).
- Never a false green: only a clean Upgrade returns `true` to Baganator.
- Any tooltip string can be secret: check `issecretvalue` before string ops.
- Module key `gear`, category "Gear", on by default.

## Review Focus

1. An item that isn't cached yet: no verdict and no error. Baganator gets false; it refreshes once the data arrives.
2. Hovering an item you're wearing: no verdict (it would only say "Sidegrade 0%").
3. A malformed or other-class Pawn string: a clear message and nothing saved.
4. A two-hander while dual-wielding, a one-hander while wearing a two-hander, Titan's Grip: each gets a sensible
   target. Tests: `Compare: 2H vs MH+OH`, `Compare: 1H with 2H worn`, `Compare: Titan's Grip`.
5. A unique ring you already wear: compared against that ring, and never over its limit. Tests: `Unique: same
   ring`, `Unique: embellishment limit`.

---

### Task 1: Data.lua: weights, stats and scoring

**Files:** create `Tomte/Modules/Gear/Data.lua`, `Tomte/tests/test_gear.lua`.

**Produces:**
- `ns.Gear_ParsePawn(text) -> { name, class, spec, weights = { AGI=..., CRIT=... } } | nil, err`.
  `class` is an upper-case class token such as `DEATHKNIGHT`; `spec` is the 1-based spec index.
- `ns.Gear_NormalizeStats(raw) -> stats`: raw keys come from `GetItemStats`. Result keys are STR, AGI, INT, STA,
  CRIT, HASTE, MASTERY, VERS, DPS, ARMOR. Hybrid primaries are kept in `stats.PRIMARY = { AGI = n, INT = n }`.
- `ns.Gear_ParseStatText(text) -> stats`: parses "+13 Haste" or "+12 Haste and +5 Mastery" (gem lines).
- `ns.Gear_DefaultWeights(primary) -> weights`: primary 1, secondaries 0.5.
- `ns.Gear_Score(desc, weights, primary, gemValue) -> number`: base stats + gem stats + empty sockets × gemValue.
- `ns.Gear_StripLink(link) -> link`: clears the enchant and gem fields of the item string.

Tests:
- Parsing a Raidbots string.
- Rejecting garbage.
- A hybrid primary counts only for the spec's primary stat.
- Score maths.
- Stripping the link keeps the bonus IDs.

### Task 2: Data.lua: comparison target, sets, uniques, verdict

**Produces:**
- `ns.Gear_Target(cand, equipped) -> { slots = {16} | {16,17}, mode = "single"|"sum"|"pair"|"empty" }`.
  `equipped` is a table of slot → descriptor.
- `ns.Gear_Evaluate(cand, equipped, ctx) -> verdict`.
  - `ctx = { primary, weights, noWeights, armorSubclass, specOK }`.
  - `verdict = { kind, pct, statsPct, reasons = {...}, noWeights }`.
  - `kind` is one of upgrade, upgradeBut, sidegrade, downgrade, notForYou, simIt, pair, empty.
- `ns.Gear_Headline(verdict) -> text, colorKey`.
- `ns.Gear_ParseUnique(text) -> { category, max } | nil`.

Tests:
- Every verdict kind.
- Rings: compared against the weaker ring.
- Unique: same ring.
- Unique: embellishment limit.
- 2H vs MH+OH.
- 1H with a 2H worn.
- Titan's Grip.
- Breaks 4-set.
- Completes 4-set: lifts a small downgrade.
- Catalyst note.
- Trinket gives Sim it.
- Losing an effect gives upgradeBut.
- Wrong armor type, with a cloak exception.
- Wrong primary stat.
- A red tooltip line gives Not for you.
- Empty slot.
- Upgrade track reason.

### Task 3: Items.lua: descriptors and equipped snapshot (WoW API, tested in game)

**Produces:**
- `ns.GearItems_Describe(link) -> desc | nil`. Returns nil when the item isn't cached, and requests the load.
- `ns.GearItems_Equipped() -> equipped | nil`. Returns nil while the snapshot is incomplete.
- `ns.GearItems_Invalidate()`.
- Callback `ns.GearItems_OnReady`, called when data that was missing arrives.

### Task 4: Gear.lua: module, tooltip, Baganator, import dialog, options; TOC, README, .gitignore check

- Tooltip post-call for items. It skips ShoppingTooltip1/2 unless the option is on, and skips items that are
  equipped.
- Baganator: register once, return `verdict.kind == "upgrade"`, and call `RequestItemButtonsRefresh` on equipment
  or spec changes and when data arrives.
- Import dialog: our own frame with a multi-line edit box.
- Commands: `import`, `weights`, `clear`.
- TOC: add the 3 files and `OptionalDeps: FlightTimer, Baganator`.
- README: add a module row.

### Task 5: Verify

Run all `Tomte/tests/*.lua`, check syntax with `luac -p` if available, and re-read against the spec. Commit after
the user confirms in game.
