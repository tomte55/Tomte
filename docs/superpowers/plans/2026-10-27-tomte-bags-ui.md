# Bags UI overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The bag window, bank window, side panels and Bag categories page in one structure (header band, tray,
footer band), hairline item slots, and drag reordering of categories.

**Architecture:** A small frame kit in `Modules/Bags/Kit.lua` (band, tray, joined button cluster, sunk search box,
meter, attached tab) used by every Bags window; the item buttons restyled in `Buttons.lua`; the windows rebuilt on
the kit; one new pure move operation in `EditData.lua` for dragging.

**Tech Stack:** Lua 5.1 (WoW 12.1.5), plain-Lua tests (`tests/harness.lua`).

**Spec:** `docs/superpowers/specs/2026-10-27-tomte-bags-ui-design.md`

## Global Constraints

- Colors only by theme role or `{r, g, b}` from the game (quality colors); black / white shading allowed
  (`tests/test_theme.lua`). Fonts by role. Theme switching reloads the UI, so no runtime repaint is needed.
- No new art or fonts. Motion through `Panel/Motion.lua` (`UI.Appear`, `UI.Disappear`, `UI.Tween`, `UI.BorderTo`);
  never scale text.
- Item buttons stay `ContainerFrameItemButtonTemplate`; restyle through their regions and Tomte textures only.
- Files under ~900 lines; splits are pure moves in their own commit first.
- The user delegated the whole build: one combined in-game test list at the end, no commits before it except pure
  moves and docs.

## Review Focus

1. Every theme: bands, tray and frames read on light-ish themes (Classic, Blizzard) too, not only on dark ones.
2. Item clicks, drag and drop and the bank's right-click deposit still work after the restyle (no new fields read by
   Blizzard's click code).
3. "Buttons only on hover", "Lock the window", other characters' bags and the one-bag view still work.
4. Dragging a category onto itself, a section into a section, or Empty / Other anywhere never loses a node.
5. Narrow windows (8 columns): the header band's clusters and search box don't overlap.

Test for 4 in Task 2; the rest go on the in-game list (Task 9).

---

### Task 1: Split EditPage.lua (pure move)

**Files:** Create `Modules/Bags/EditList.lua` (the list: rows, drawing); Modify `Modules/Bags/EditPage.lua`,
`Tomte.toc` (EditList.lua before EditPage.lua), `Core/BugFiles.lua` (tools/bugfiles.lua).

**Interfaces:** Produces `ns.BagsEditList_Create(page, onPick) -> list`, `ns.BagsEditList_Draw(list, layout, byKey,
selected)`.

- [ ] Move the list code verbatim; tests, GETGLOBAL check; commit `Split the Bag categories list out of
  EditPage.lua (pure move)`.

### Task 2: Moving a node anywhere (pure)

**Files:** Modify `Modules/Bags/EditData.lua`; Test `tests/test_bagsedit.lua`.

**Interfaces:** Produces `ns.BagsEdit_MoveTo(layout, key, targetKey, where) -> bool`; where = "before" | "after" |
"into" (a section's end). Sections and dividers stay at the top level: dropped before/after a node inside a section,
they land before/after that section. Returns false (nothing changes) for a missing key, the node itself as target,
or "into" a non-section.

- [ ] Tests: move a category before another in the same list; after a category inside a section (it joins the
  section); "into" a section (its end); a section dropped after a child lands after its section; a divider likewise;
  onto itself -> false and unchanged; unknown keys -> false; node count unchanged in every case.
- [ ] Implement; tests pass.

### Task 3: Frame kit

**Files:** Create `Modules/Bags/Kit.lua` (after Buttons.lua in the TOC).

**Interfaces (all take a parent, return the frame):**
- `ns.BagsKit_Band(parent)`: darker band (two "surface" layers over the parent's fill) with a "rule" line on its
  bottom edge (`band:SetRuleTop(true)` moves the line to the top, for footers).
- `ns.BagsKit_Tray(parent)`: recessed tray: black fill at 0.35 over the window, a 1-px black edge, a black 0.6
  line along its inner top edge (the shadow), a faint white 0.04 line along its outer bottom edge.
- `ns.BagsKit_Cluster(parent, specs)`: one frame with a "frame" border; inside, buttons side by side divided by
  "rule" lines. spec = `{ icon = file/atlas/ID, text = string, tip = string, onClick = fn }`; returns the cluster
  with `.buttons[i]`; buttons 22 px tall, icons 14 px; hover washes the button ("hover" role); `cluster:SetLit(i,
  on)` lights a button (accent wash + "text" color), for switches.
- `ns.BagsKit_Search(parent, placeholder, onChange)`: sunk box (black 0.45 fill, "rule" edge, inner top shadow),
  placeholder in "textFaint", a "?" at its right end inside (`search.help`), `search:SetError(text|nil)` (danger
  edge + tooltip with the reason), right-click clears (`UI.SearchBoxClear`), debounced onChange.
- `ns.BagsKit_Meter(parent, width)`: 4 px bar, black fill, "rule" edge, accentDeep fill; `meter:SetValue(0..1)`.
- `ns.BagsKit_Tab(parent, size)`: a tab attached to a window edge (same fill as the window, "frame" border on
  three sides, `tab:SetSide("top"|"right")` picks the open side), `tab.icon`, `tab:SetSelected(on)` (accent edge,
  joins the window: open side drawn in the window's fill).

- [ ] Implement; GETGLOBAL check; theme test passes.

### Task 4: Hairline slots

**Files:** Modify `Modules/Bags/Buttons.lua`.

- [ ] Hide Blizzard's slot art and quality border on Tomte's buttons (NormalTexture alpha 0, IconBorder hidden
  after every SetItemButtonQuality), add a BACKGROUND fill (black 0.35) and a 1-screen-pixel border (`UI.Border`,
  PixelUtil-based so the size/37 scale doesn't thicken it) in "rule", or the item's quality color for uncommon and
  better; empty slots: fill white 0.03 and border at 0.6; hover: `UI.BorderTo(button, "accent")`, back on leave
  (HookScript, not SetScript). Display-only buttons the same.
- [ ] Icon inset 2 px inside the border so frame and icon don't touch.

### Task 5: The bag window on the kit

**Files:** Modify `Modules/Bags/Window.lua` (split first if it would pass 900 lines: the footer and bag-slot tabs
into `WindowParts.lua` as a pure move).

- [ ] Header band: cluster [bag slots, characters], title, kit search (stretching between the title and the right
  cluster), cluster [saved searches, sort, settings, close]; bad search -> `search:SetError`; "?" help in the box.
- [ ] Body inside a kit tray; footer band (rule on top): currencies button, "N free slots", kit meter (used/total of
  bags 0-5), tracked currencies, gold right.
- [ ] Bag slots: kit tabs on the window's top edge, each with its free count; shown by the bags button.
- [ ] "Buttons only on hover" fades the two clusters only. Fade in/out with `UI.Appear` / `UI.Disappear`.

### Task 6: The bank window on the kit

**Files:** Modify `Modules/Bags/Bank.lua`.

- [ ] Header band: cluster switch [Character, Warband] (lit = shown bank; a part hidden when that bank can't be
  viewed), title, cluster [sort, close]. Tray around the body. Footer band: Deposit button + Include reagents left,
  gold text + cluster [Deposit, Withdraw] right.
- [ ] Bank tabs as kit tabs on the right edge (`SetSide("right")`), selected = tab filter; "+" as the last tab.
- [ ] The gold panel as a drawer under the footer, flush with the window's right edge, sliding down
  (`UI.SlideTo`/Tween, whole pixels) and up when closed.

### Task 7: Side panels

**Files:** Modify `Modules/Bags/Currencies.lua`, `Modules/Bags/Find.lua`.

- [ ] Docked flush to the bag window's left edge (TOPRIGHT to its TOPLEFT, no gap), same height, band with title +
  close cluster, list in a tray. Opening one closes the other (`ns.BagsCurrencies_Hide`, `ns.BagsFind_Hide`).

### Task 8: The Bag categories page

**Files:** Modify `Modules/Bags/EditList.lua`, `Modules/Bags/EditPage.lua`.

- [ ] Band with two clusters [+ Category, + Section, + Divider] and [Share, Import, Defaults] (the Tomte window's
  title bar is the title). The list in a tray: grip "⋮⋮"-style handle (two short "textFaint" bars), count pills,
  section rows in the title font with a hairline after, automatic categories in "textMuted", picked row with accent
  edge + wash.
- [ ] Drag: press on a row and move > 4 px starts a drag; a ghost of the row follows the cursor; a 2 px accent drop
  line shows "before" / "after" (upper / lower half of a row) or "into" (on a section row's right two thirds);
  release calls `ns.BagsEdit_MoveTo`; the list scrolls while the cursor is within 16 px of its top or bottom.
- [ ] Editor: name as a large title (click to edit inline), three groups (What goes in / When two categories want
  an item / Where it shows) as framed boxes, Always in it as an icon drop area (right-click an icon to remove; a
  "paste IDs" link opens the old box), bottom row Section / Move up / Move down / Delete (danger).

### Task 9: Docs, checks, in-game list

- [ ] CHANGELOG `### Improved` "- **Bags:** ..." and `### New` drag line; README row wording if needed; all tests,
  bugfiles, GETGLOBAL checks; a fresh reviewer over the whole diff; one combined test list for the user.
