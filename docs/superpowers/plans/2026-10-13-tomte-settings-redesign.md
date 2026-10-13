# Settings redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the settings sidebar with a group icon rail + group list, and the module page with a header and
two-column option cards.

**Architecture:** Pure rules (groups, column dealing, segment rule, search) in `Panel/Layout.lua`, unit-tested.
Panel.lua is split into Sidebar/ModulePage/Panel first (pure move). New controls in `Panel/Controls.lua`. Options.lua
renders cards from the existing schema plus `parent`. Modules get `category` = group key, `icon`, `summary`.

**Tech Stack:** WoW 12.1 retail Lua, plain-Lua tests (Lua 5.1 in CI).

**Spec:** `docs/superpowers/specs/2026-10-13-tomte-settings-redesign-design.md`

## Global Constraints

- Colors and fonts only through theme roles (`UI.Color`, `UI.Text`, `UI.SetTextRole`); never read colors at file load.
- No new globals; cross-file names `ns.Panel*`/`ns.PANEL_*`; CRLF files edited with Edit/Write only.
- Group keys: `tomte`, `week`, `gear`, `professions`, `collections`, `travel`, `social`, `ambience`, `class`.
- Two columns only when each column ≥ 360 px; segmented only for ≤ 3 choices fitting 170 px.
- Default window 1040×680, minimum 820×560.
- No commit before the user checks it in game (user's standing rule); commits listed per task are made after that.

## Review Focus

- Search typed, then a group icon clicked: search must clear (else the list shows matches, not the group).
- A module whose page is open gets disabled from its list checkbox: page switch and list must agree.
- Window resized across the 2-column threshold while a page is open: cards re-lay without stale positions.
- A dropdown whose choices are dynamic (characters) grows past 3: must turn back into a dropdown on rebuild.
- `Panel_OpenModule(key)` for a module in another group while the rail is expanded: list shows the new group.

---

### Task 1: Split Panel.lua (pure move)

**Files:** Create `Panel/Sidebar.lua`, `Panel/ModulePage.lua`; modify `Panel/Panel.lua`, `Tomte.toc`.

**Interfaces — Produces:** `ns.PanelState` = `{ Selected(), Refresh(), RefreshList(), RefreshPage() , panel }`
filled by Panel.lua; `ns.PanelSidebar_Create(parent)`, `ns.PanelSidebar_Refresh()`, `ns.PanelModulePage_Create(parent)`,
`ns.PanelModulePage_Refresh()`.

- [ ] Move the "Sidebar" section verbatim into Sidebar.lua, the "Module settings page" section into ModulePage.lua,
      with local captures at top; replace forward-declared locals with `ns.PanelState` lookups at call time.
- [ ] TOC: `Panel\Sidebar.lua`, `Panel\ModulePage.lua` before `Panel\Panel.lua`; `lua Tomte/tools/bugfiles.lua`.
- [ ] `luac -l` globals check on the three files; full test suite.
- [ ] Commit `Split Panel.lua into Sidebar, ModulePage and Panel (pure moves)`.

### Task 2: Pure layout rules

**Files:** Create `Panel/Layout.lua`, `tests/test_panel_layout.lua`; TOC (before Widgets.lua).

**Interfaces — Produces:**
- `ns.PANEL_GROUPS` — array of `{ key, name, description, icon }`.
- `ns.PanelLayout_Group(key)` → group table or nil.
- `ns.PanelLayout_Columns(width, gap, minColumn)` → `1|2`.
- `ns.PanelLayout_Deal(heights, columns, gap)` → `places, totalHeight`; `places[i] = { column, y }`.
- `ns.PanelLayout_UseSegments(widths, max, maxChoices)` → boolean.
- `ns.PanelLayout_Matches(module, groupName, text)` → boolean (text lower case, "" matches).

- [ ] Tests first (thresholds 719/720 with gap 0... per `2*min+gap`; dealing order, ties left, single card;
      segments by count and width; matches on name/summary/description/group).
- [ ] Implement; tests green.
- [ ] Scan test: every TOC file calling `ns.RegisterModule` has `category = "<known key>"`, `icon =`, `summary =`
      (fails until Task 6).

### Task 3: Controls

**Files:** Create `Panel/Controls.lua` (after Widgets.lua in TOC).

**Interfaces — Produces:** `UI.Switch(parent)` (`SetChecked`, `checked`, `onChange`, Enable/Disable dims);
`UI.Segmented(parent)` (`getValue`, `setValue`, `choices`, `Refresh()`, `:Fit(maxWidth)` returns width).

- [ ] Write both; theme roles only; `test_theme` green.

### Task 4: Sidebar rail and group list

**Files:** Modify `Panel/Sidebar.lua`, `Panel/Panel.lua` (sizes, layout), `Core/Modules.lua` (drop
`ModuleCategories`, `ModuleMatches` adds summary), `Core/Core.lua` (`panel = {}`), `Core/Migrations.lua` (9: drop
`panel.collapsed`), tests `test_modules.lua`, `test_migrations.lua`.

- [ ] Migration test then migration.
- [ ] Rail: 44 px, icon buttons, slide-out to 190 px over the list (OnUpdate only while animating or expanded),
      clip children, labels/counts fade in; group click selects remembered/first module and clears search.
- [ ] List: search, group heading + description, module rows with checkbox; search mode lists all matches with
      group icon.

### Task 5: Module page header and cards

**Files:** Modify `Panel/ModulePage.lua`, `Panel/Options.lua`.

- [ ] Header: icon, title, summary + More/Less, chips, switch, Open buttons, blocked strip.
- [ ] Options: sections → pooled cards; columns via `PanelLayout_Columns/Deal`; switches; segmented via
      `PanelLayout_UseSegments`; `parent` indent + dim + rebuild on change; "?" marker; truncated-label tooltip;
      footer reset links.

### Task 6: Content pass

**Files:** every module main file + `Panel/Window.lua`.

- [ ] `category` → group key; `icon` (listfile-checked file ID); `summary` (one sentence, player wording);
      `parent` on dependent rows; scan test green.
- [ ] CLAUDE.md: schema fields and groups. Full suite, globals check, bugfiles.
