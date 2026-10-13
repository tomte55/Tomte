# Settings redesign: group rail and card pages

2026-10-13. Brainstormed with mockups (visual companion); the user picked every direction below and then
delegated the build ("write the spec, then plan and then build it the best way you see fit").

## Why

The settings sidebar lists 37 modules under 13 categories in one long scrolling list. Five categories hold one or
two modules, "General" holds ten unrelated ones. The module page is one flat column of identical rows: a wall of
description text, loose "Uses" lines, controls far right, thin section rules, dependent settings shown at full
strength while their switch is off, and the right half of a wide window empty.

## What the player sees

### Sidebar: icon rail + group list

- The 37 modules move into 9 groups (agreed with the user):

  | Group | Modules |
  | --- | --- |
  | Tomte (pinned, divider under it) | Tomte window, Minimap Buttons, Recent, Next up |
  | Your week | Weekly board, Alts, Delves, World quests, Gold world quests |
  | Gear | Gear Check, Showcase, Dressing room, Durability, Vendor Helper |
  | Professions & gold | Gathering, Fishing, Material uses, Gold & value |
  | Collections | Collect here, Holidays & events, Pet Battles, Almost Done |
  | Travel | Flight Timer, Waypoints, Smart Mount, Teleports |
  | Social & chat | Whispers, Mentions, Friends Online, Group Alerts, Friend sharing, Chat Tabs, Trade Filter, Channel Tags, Chat Copy |
  | Ambience | AFK Screen, Moments, Session recap |
  | Class & combat | Hunter Pets, Rogue Poisons, Pet Health |

- Far left, a 44 px rail with one game icon per group. Hovering the rail slides it out to about 190 px **over** the
  list (shadowed, nothing underneath moves) showing each group's name and module count; it slides back when the
  mouse leaves. The selected group has the accent bar.
- Beside the rail, the list column: search box, the group's name and one-line description, then its modules, each
  with the on/off checkbox kept (quick toggling without opening the page). Blocked modules are dimmed as today.
- Clicking a group opens the module you last looked at in that group (this session), else its first module. The
  page always shows a module, so the window reopens on the saved module and therefore its group: no separate saved
  group key.
- Typing in search replaces the list with matches from every group (name, summary, description, group name), each
  row with its group's small icon. Picking a match selects it; clearing search shows that module's group.
- A group where no module applies to this character (all blocked) has a dimmed icon; it still opens.

### Module page: header + cards

- Header: the module's icon (40 px), name, a one-line `summary` with a "More" link that expands the full
  `description` in place ("Less" folds it). Under it, `uses`/`conflicts` as chips: green = loaded, faint = not
  installed, red = conflict. Right side: an On/Off switch (hidden for always-on modules), and under it the
  "Open <page> ›" buttons. A blocked module shows its reason in a warning strip under the header and nothing below,
  as today.
- Options become cards. Each `header` row starts a card titled with its label (small caps, accent); rows before the
  first header go into an untitled card.
- Two columns when each column can be at least 360 px wide, else one. Cards are dealt in order into the shorter
  column (ties go left). A module with a single card uses the full width. Resizing the window re-lays the cards.
- Checkboxes in options become switches (`UI.Switch`). A dropdown with at most 3 choices whose labels fit in 170 px
  becomes segmented buttons (`UI.Segmented`); anything else stays a dropdown.
- New schema field `parent = "<key>"`: the row is indented and dimmed while that option is off (it stays usable, so
  you can set it up before turning the parent on). `shown()` still hides rows.
- Rows with a `tooltip` get a faint "?" after the label. Help stays in tooltips (two columns leave no room for hint
  lines). A label cut off by the control shows its full text in the tooltip.
- The auto "Reset" section becomes quiet links at the bottom right of the page ("Reset <module> to defaults", and
  "Reset all Tomte settings" on the Tomte window page), same confirmation popups. Other `button` rows stay rows.
- Default window size grows from 960×640 to 1040×680 (saved sizes are kept); minimum stays 820×560.

## Code

- `Panel/Panel.lua` (791 lines) is split first, as a pure move in its own commit: `Panel/Sidebar.lua` (list and
  search), `Panel/ModulePage.lua` (module page header and options host), `Panel/Panel.lua` (window, title bar,
  views, public `ns.Panel_*`). Shared state between them goes through a small `ns.PanelState` table
  (selected module, refresh callbacks), set up in `Panel.lua`'s file order.
- New pure file `Panel/Layout.lua` (no WoW API, `tests/test_panel_layout.lua`):
  - `ns.PANEL_GROUPS`: ordered `{ key, name, description, icon }` (icon: file ID; `nil` for Tomte = `ns.ICON`).
  - `ns.PanelLayout_Group(key)`, `ns.PanelLayout_Columns(width, gap, minColumn)` → 1 or 2,
    `ns.PanelLayout_Deal(heights, columns)` → per card `{ column, y }` and the total height,
    `ns.PanelLayout_UseSegments(widths, max, maxChoices)`,
    `ns.PanelLayout_Matches(module, groupName, text)`.
- `Panel/Controls.lua` (new, after Widgets.lua; Widgets.lua is at 806 lines): `UI.Switch` (same API as
  `UI.Checkbox`: `SetChecked`, `checked`, `onChange`, enable/disable) and `UI.Segmented` (`getValue`, `setValue`,
  `choices` like `UI.Dropdown`, `Refresh`). Theme roles only.
- `Panel/Options.lua`: builds cards (pooled card frames), switches, segmented rows, `parent`, the "?" marker,
  column layout on width change, and the footer links. Changing an option that some row names as `parent` rebuilds
  the options (keeps the scroll).
- Modules: `category` becomes a group key (`tomte`, `week`, `gear`, `professions`, `collections`, `travel`,
  `social`, `ambience`, `class`); every module gets `icon` (file ID, checked against the community listfile) and
  `summary`; rows that only matter when a checkbox is on get `parent`.
- `ns.ModuleCategories` goes (only the old sidebar used it); `ns.ModuleMatches` also looks at `summary`.
- Saved variables: migration 9 drops `panel.collapsed`; the core default `panel = { collapsed = {} }` becomes
  `panel = {}`. Case in `tests/test_migrations.lua`.

## Tests

- `test_panel_layout.lua`: column count thresholds, dealing cards (order, ties, single card), segment rule, search
  matching.
- A scan test (`test_panel_layout.lua`) reads every file in the TOC that calls `ns.RegisterModule` and checks each
  module's `category` is a known group key and that it has `icon` and `summary`.
- Existing tests updated for the new categories and the removed `ns.ModuleCategories`; full suite green;
  `luac -l` globals check on the new and split files; `lua Tomte/tools/bugfiles.lua` after the TOC change.

## Unchanged

Home, content pages, the Home rail (`Panel/Rail.lua`), `ns.Panel_OpenModule(key)` (selects the module and so its
group), every module's db, and the existing options schema fields.

## Docs

CLAUDE.md: `parent`, `icon`, `summary` and the group keys in the options/new-module sections. README's layout stays.
CHANGELOG line after the in-game check.
