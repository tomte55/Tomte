# Loot window looks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto loot always goes to the feed; manual loot opens a window in one of three looks (Strips, Panel, Tiles);
nothing greys or shows twice.

**Architecture:** `Window.lua` keeps the window shell (frame, placement, keys, Escape, paging, Edit Mode, API for
`Loot.lua`) and hands drawing to a look. Each look is its own file that registers `ns.LootLooks[key]` and draws into a
host frame from a context table, so later settings previews can draw it with sample loot. Shared pieces (the feed's
strip, icon frames, keycap, text helpers) move into a new `Parts.lua` used by the feed and every look.

**Tech Stack:** WoW retail 12.1.5 Lua, Tomte's `ns.UI` widgets and theme roles, plain-Lua tests (Lua 5.1).

**Spec:** `docs/superpowers/specs/2026-10-25-tomte-loot-window-looks-design.md`

## Global Constraints

- CRLF files; edit with Edit/Write only. Tabs, ~120 columns, double quotes, `local function` for private code.
- Colors and fonts by theme role only (`tests/test_theme.lua` scans); item quality colors via `ITEM_QUALITY_COLORS`.
- No numeric colors, no `|cff` literals, no theme reads at file load.
- Every saved key has a default; `style` → `look` only through migration 14 in `Core/Migrations.lua`.
- Midnight: `Readable` on event payloads; the keyboard handling stays as is (`ns.LootWindow_UpdateKeys`).
- No commit before the user's in-game check (memory: autonomous-when-delegated). CHANGELOG after confirmation.

## Review Focus

1. Area loot (several corpses, one window) taken by hand row by row: rows leave, pages shrink, window never empty but
   open. Expected: "Nothing left" never shows while the game still holds the loot; the window closes with the loot.
2. A currency looted by hand with "Reputation and currency lines" on: exactly one feed line (or none with
   `feedManual` off). The keys live in Toasts.lua (game events), so this one is checked in game.
3. Stuck loot after auto loot (full bags): the window opens in the chosen look, and what you take goes to the feed.
4. Theme switch while the window is open, and Blizzard theme (`panel = "blizzard"`) for Panel and Tiles.
5. Font size 18 and 10: the looks scale and nothing overlaps (Tiles' grid, Panel's two-line rows).

---

### Task 1: Pure rules (Data.lua) and migration

**Files:** Modify `Modules/Loot/Data.lua`, `Core/Migrations.lua`, `tests/test_loot.lua`, `tests/test_migrations.lua`

**Produces:**
- `ns.Loot_FeaturedIndex(entries) -> index|nil`: like `Loot_BestIndex`, but only items with `verdict.upgrade` or that
  `ns.Loot_IsValuable({ classID, subclassID, quality, toy = e.toy })` accepts; never taken ones.
- `ns.Loot_Lines(entries, opts)` gains `opts.hideTaken` (taken entries make no line; a junk fold of only taken items
  makes none) and `opts.skipMoney` (coin makes no line: Panel shows it in its footer).
- `ns.Loot_FeedsTaken(auto, feedManual) -> bool`: `auto or feedManual`.
- `ns.Loot_WorthText(e) -> string|nil`: the stack's price text as `Loot_Details` writes it.
- Migration 14: `loot.style` "card" → `look = "panel"`, "list"/"feed" → "strips"; `style` removed; no loot table: nothing.

- [ ] Tests first in `tests/test_loot.lua`: featured (upgrade beats valuable beats nothing; plain reagents → nil;
  taken upgrade → nil), lines hideTaken/skipMoney, FeedsTaken truth table, WorthText (nil without worth).
- [ ] Test in `tests/test_migrations.lua`: card → panel, list → strips, feed → strips, missing loot table untouched.
- [ ] Implement; run `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`: no FAIL.

### Task 2: Read.lua extras

**Files:** Modify `Modules/Loot/Read.lua`

- [ ] In `ItemExtras`: `e.subType` (GetItemInfo's 7th return, the localized subtype), `e.toy = C_ToyBox.GetToyInfo(itemID) ~= nil`.
- Money: a loot slot gives no copper amount (quantity 0, only the game's "12 Gold 40 Silver" text), so Panel's
  footer shows the money entries' names, not a sum.

### Task 3: Parts.lua (shared drawing) and Feed.lua on it

**Files:** Create `Modules/Loot/Parts.lua` (TOC after `Read.lua`); modify `Modules/Loot/Feed.lua`, `Modules/Loot/Window.lua`

**Produces (all `ns.LootParts_*`, plus the moved text helpers keeping their names):**
- moved from Window.lua: `ns.Loot_NameText`, `ns.Loot_PartsText`, `ns.Loot_MoneyText`, `ns.Loot_DetailOpts`, `ns.LOOT_MONEY_ICON`.
- `ns.LootParts_Init(db)`.
- `ns.LootParts_Strip(f)`: adds the feed line pieces to frame `f` (`bg`, `bar`, `icon`, `text`, `detail`).
- `ns.LootParts_FillStrip(f, spec, size, bgAlpha, maxW) -> width`: Feed.lua's Fill drawing (spec as Feed's).
- `ns.LootParts_IconFrame(tex, quality, isMoney)`: quality-colored frame color.
- `ns.LootParts_FlatButton(parent, text, size, idle)`, `ns.LootParts_Keycap(parent)` → cap with `cap:SetKey(text|nil, size)`.
- `ns.LootParts_TakeKeyText(db) -> string|nil`: the loot key, else the binding's text.

- [ ] Move verbatim, adapt Feed's `CreateLine`/`Fill` to call the strip helpers; behavior of the feed unchanged.

### Task 4: Window shell and the three looks

**Files:** Rewrite `Modules/Loot/Window.lua`; create `Modules/Loot/LookStrips.lua`, `LookPanel.lua`, `LookTiles.lua`
(TOC after `Feed.lua`).

**Look interface:** `ns.LootLooks[key] = { Build(host) -> view, Draw(view, ctx) -> width, height }`, `view.root` is a
frame on `host` the shell shows/hides. `ctx = { entries, title, size, bgAlpha, extras, perPage, page, open, preview,
keyText, onLoot(entries), onTakeAll(), onClose(), onTurn(delta) }`; Draw returns `page, pages` too via `ctx.page`/`ctx.pages`
written back.

- Strips: no box; header title (size+5) with the close x; strips from Parts, clickable, accent hover; footer keycap +
  "Take all", pages.
- Panel: `UI.Panel(root, { alpha })`; header band (accent gradient), spaced LOOT label, title, x; featured block when
  `Loot_FeaturedIndex`; two-line rows (subType · details; worth right); footer: money names (click loots them) left,
  filled accent Take all with keycap right.
- Tiles: `UI.Panel`; 5 tiles per row, quality border, counts, upgrade marker; caption strip naming the hovered (else
  first) item; footer: "N items · worth", Take all with keycap.
- All: taken entries hidden (`hideTaken`), "Nothing left" when empty, sizes scale with `size / 12`.
- Shell: removes linger/fade (`LootWindow_Closed()` hides), keeps keys/Escape/placement/Edit Mode, preview uses the
  look from `db.look`.

### Task 5: Loot.lua, Toasts.lua and settings

**Files:** Modify `Modules/Loot/Loot.lua`, `Modules/Loot/Toasts.lua`, `README.md`

- [ ] Display: `session.auto` → stuck check (always), else ShowWindow. `Taken`: feed when
  `Loot_FeedsTaken(session.auto, db.feedManual)`; PLAYER_MONEY likewise.
- [ ] Currency: `ns.LootToasts_LootCurrency(e, show)` notes `lc:<id>` and the event key; the event path skips a
  currency noted `lc:<id>` within `SAME_GAIN`; the loot path skips when the event already showed it.
- [ ] Defaults `look = "strips"`, `feedManual = true`; options: Look (Strips/Panel/Tiles), the feedManual checkbox,
  fadeDelay tooltip; summary/description/Why; Edit Mode options `look`; README row.
- [ ] Tests green, `lua Tomte/tools/bugfiles.lua`, luac global check on every new/changed file.
