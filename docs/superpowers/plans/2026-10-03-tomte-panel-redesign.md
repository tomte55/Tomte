# Tomte Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A resizable standalone settings panel with a grouped module sidebar and full-height module pages, a
minimap button module, and 3D models for tame-log beasts on the Stable page.

**Architecture:** Panel.lua keeps the window, sidebar and module page. The option row factories move to
Options.lua. A shared `UI.Scroll` widget replaces copy-pasted scroll code in the panel and Stable page. The minimap
button is a regular Tomte module (`Modules/Minimap`) with its positioning maths in a pure Data.lua.

**Tech Stack:** Lua 5.1 (WoW 12.1.0, `## Interface: 120100`), Tomte module registry, plain-Lua tests.

**Spec:** `docs/superpowers/specs/2026-10-03-tomte-panel-redesign-design.md`

## Global Constraints

- No globals except `TomteDB`, `Tomte_OnAddonCompartmentClick` and the existing `TomtePanel`/`TomtePanelEscape`
  frame names.
- No libraries. Never modify third-party addons.
- Panel: default 960×640, min 820×560, max UIParent size. Sidebar 220 px. Options column max 560 px.
- Saved: `TomteDB.panel.layout = { point, x, y, w, h }`, `TomteDB.panel.selected = key`. `panel.category` cleared.
- Minimap module: key `minimap`, category `General`, on by default, `defaults = { angle = 225 }`.
- Tests run from the AddOns folder: `lua Tomte/tests/<file>.lua`. Every test file must print no `FAIL`.
- No commit until the user confirms in game (CLAUDE.md).

## Review Focus

1. A saved layout bigger than the current screen (resolution or UI scale changed): the panel is clamped to the
   resize bounds and stays on screen.
2. The saved selected module no longer exists (module removed or renamed): the first module is selected, no error.
3. Search hides the selected module: the page on the right keeps showing it.
4. A tame-log entry keyed by name (no npcID): the row still shows and isn't hoverable for a model; no error.
5. Dragging the minimap button on a square minimap (an addon defines `GetMinimapShape`): the button follows the
   square edge. Test: `Offset: square corner`.

---

### Task 1: Minimap maths (pure)

**Files:** create `Tomte/Modules/Minimap/Data.lua`, `Tomte/tests/test_minimap.lua`.

**Produces:**
- `ns.Minimap_Offset(angle, halfW, halfH, shape) -> x, y`: angle in degrees (0 = right, counter-clockwise),
  half sizes include the button radius, shape is a `GetMinimapShape()` value or nil (= "ROUND"). Same rules as
  LibDBIcon: a round quadrant puts the point on the ellipse; a square quadrant on the clamped diagonal
  (`sqrt(2*w^2) - 10`).
- `ns.Minimap_Angle(dx, dy) -> degrees in [0, 360)`.

- [ ] Step 1: tests

```lua
test("Offset: round right", function()
	local x, y = ns.Minimap_Offset(0, 75, 75, nil)
	near(x, 75) near(y, 0)
end)
test("Offset: round 225", function()
	local x, y = ns.Minimap_Offset(225, 75, 75, "ROUND")
	near(x, -75 * math.sqrt(0.5)) near(y, -75 * math.sqrt(0.5))
end)
test("Offset: square corner", function()
	local x, y = ns.Minimap_Offset(45, 75, 75, "SQUARE")
	near(x, 75) near(y, 75)
end)
test("Offset: square edge middle", function()
	local x, y = ns.Minimap_Offset(90, 75, 75, "SQUARE")
	near(x, 0) near(y, 75)
end)
test("Offset: unknown shape counts as round", function()
	local x = ns.Minimap_Offset(0, 75, 75, "BLOB")
	near(x, 75)
end)
test("Angle wraps to 0-360", function()
	near(ns.Minimap_Angle(1, 0), 0)
	near(ns.Minimap_Angle(0, 1), 90)
	near(ns.Minimap_Angle(-1, -1), 225)
end)
```

- [ ] Step 2: run, expect failure (file missing). Step 3: implement. Step 4: run, all `ok`.

### Task 2: Stable summary carries npcID and family

**Files:** modify `Tomte/Modules/Hunter/Data.lua` (`Hunter_StableSummary`), `Tomte/tests/test_hunter.lua`.

- [ ] Step 1: extend the existing summary test:

```lua
eq(s.seenOnly[1].creatures[1].npcID, 2)
eq(s.seenOnly[1].creatures[1].family, "Bat")
```

and add:

```lua
test("StableSummary: name-keyed creature has no npcID", function()
	local seen = {}
	ns.Hunter_RecordSeen(seen, "Bat", nil, "Old Bat", "Duskwood", 1)
	local s = ns.Hunter_StableSummary(nil, seen)
	eq(s.seenOnly[1].creatures[1].npcID, nil)
	eq(s.seenOnly[1].creatures[1].name, "Old Bat")
end)
```

- [ ] Step 2: run, fails. Step 3: in the seen loop, copy each creature into a new table
  `{ name, zone, at, family = family, npcID = type(key) == "number" and key or nil }` (don't mutate saved data).
  Step 4: run, passes.

### Task 3: `UI.Scroll` widget

**Files:** modify `Tomte/Panel/Widgets.lua`.

**Produces:** `UI.Scroll(parent) -> scroll` (a ScrollFrame). Fields: `scroll.content` (scroll child, width follows
the scroll frame), `scroll.thumb` (2 px gold texture right of the frame). Methods: `scroll:SetScroll(value)`
(clamped), `scroll:SetContentHeight(h)` (keeps the offset, clamps it), `scroll:UpdateThumb()`. Mouse wheel scrolls
40 px. Optional `scroll.onWidthChanged(width)` called from OnSizeChanged.

### Task 4: Options.lua split

**Files:** create `Tomte/Panel/Options.lua`; modify `Tomte/Panel/Panel.lua`, `Tomte/Tomte.toc` (Options.lua after
Widgets.lua, before Panel.lua).

**Produces:**
- `ns.PanelOptions_Build(scroll, module, keepScroll)`: releases previous rows, builds rows for `module.options`
  into `scroll.content`, sets content height, restores the offset when `keepScroll`.
- `ns.PanelOptions_Release()`.
- `StaticPopupDialogs.TOMTE_CONFIRM` moves here.

Factories and Setup functions are moved unchanged, except rows are created on the content frame passed in.

### Task 5: Panel rewrite

**Files:** modify `Tomte/Panel/Panel.lua`, `Tomte/Core/Core.lua` (`ns.ICON`, defaults `panel = {}`, clear
`panel.category`).

- Build(): frame `TomtePanel`, BG + border, `SetResizable(true)`, `SetResizeBounds(820, 560, UIParent:GetWidth(),
  UIParent:GetHeight())`, title bar (icon 20×20 + "Tomte" + close), resize grip (16×16, SizeGrabber Up/Down/
  Highlight), body = sidebar + page.
- Layout restore: `ApplyLayout()` reads `ns.db.panel.layout`, clamps w/h to the bounds, `SetPoint(point, UIParent,
  point, x, y)`; default CENTER 960×640. `SaveLayout()` on drag stop and resize stop uses `panel:GetPoint(1)` after
  `StopMovingOrSizing`.
- Sidebar: search box (top), `UI.Scroll` below it; headers + module rows pooled; rows: checkbox, name, gold bar,
  bg; OnEnter tooltip with description; OnClick selects and saves `panel.selected`.
- Page: header (title, Enabled checkbox + label, desc, reason), tabs (existing tab code), options `UI.Scroll`
  limited to 560 px width, page frames per module (created lazily, anchored under the header/tabs, filling the
  rest), "No options." text.
- `ns.Panel_Toggle()`, `ns.Panel_Open()`; Options → AddOns canvas holder with an "Open Tomte" button.
- Esc dummy frame stays. `panelClosed` hooks stay.

### Task 6: Minimap module

**Files:** create `Tomte/Modules/Minimap/Minimap.lua`; modify `Tomte/Tomte.toc` (Minimap Data + module first
under Modules).

- Button as in the spec. `module.toggle(active)` creates the button on first activation and shows/hides it.
  `Place()` uses `ns.Minimap_Offset(angle, Minimap:GetWidth()/2 + 5, Minimap:GetHeight()/2 + 5, GetMinimapShape
  and GetMinimapShape())`. Drag: OnUpdate computes cursor offset from `Minimap:GetCenter()` scaled by
  `Minimap:GetEffectiveScale()`, `ns.Minimap_Angle`, saves `db.angle`, places.
- Option: button "Reset position".

### Task 7: Stable page two-column + seen models

**Files:** modify `Tomte/Modules/Hunter/StablePage.lua`.

- Summary + hairline at top; `UI.Scroll` list left; preview column 260 px right with a VLine divider.
- `hovered`/`clicked` hold either a pet or a seen creature. Creature rows (with npcID) set `row.entry`.
- `ShowPreview()`: creature → `model:SetCreature(npcID)`, name, family, "Seen in <zone>", `date("%d %b %Y", at)`;
  pet → as before. Model key (`"c"..npcID` / `"d"..displayID`) avoids reloading the same model. If
  `model:GetModelFileID()` is nil after setting, retry once after 0.5 s while the key is unchanged.

### Task 8: Verify

- [ ] All test files print no FAIL. `luac -p` (or `lua -e "loadfile(...)"`) parses every changed file.
- [ ] Hand over with the in-game checklist; no commit.
