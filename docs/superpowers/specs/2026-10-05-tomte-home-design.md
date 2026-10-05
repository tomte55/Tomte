# Tomte: Home screen

Date: 2026-10-05. Designed with the user (mockups in the brainstorm companion: A "tile grid" for Home combined with
C "navigation rail" for content pages). Built autonomously after the design was agreed ("build it and come back when
it is all done"). Spec 1 of 2; spec 2 is Alts (`2026-10-05-tomte-alts-design.md`), which lives in this home screen.

## Goal

The Tomte window becomes an overview of content and actions instead of a settings list. `/tomte`, the minimap
button and the addon compartment open **Home**: tiles for every content page and world-map tab, a Quick row of
actions, and a Settings button. Content pages get the full window with a navigation rail. Settings keeps today's
sidebar + options view, without content tabs.

## Views (one window, same size/position/resizing as today, 960×640 default)

1. **Home** (default on every open). Title bar: icon, "Tomte", **Settings** button, close.
   - Tile grid of **pages** (open inside the window), then the label "On the world map" and tiles for **map tabs**
     (open the world map on that tab and hide the Tomte window). Each tile: icon, name (gold), one summary line
     (grey). Columns: as many 220+ px columns as fit (3 at the default width).
   - **Quick** row at the bottom: small buttons for actions (Whisper inbox, Last session recap, Reveal upgrades),
     each optionally with a count in its label.
   - A tile/button is hidden when its module is off or blocked, or its `shown()` returns false (e.g. Stable on a
     non-hunter). An empty section (no map tabs) hides its label.
2. **Page**. Title bar: as Home, plus the page's name after "Tomte ·". Left **rail** (170 px): "Home", every
   visible page, then "WORLD MAP" and the map entries (clicking opens the map like the tile). The selected page is
   gold with a gold bar. Right: the page's frame, with a header line: page title and, when the owning module has
   `uses`, a "Uses Syndicator: ..." line (right-aligned, green; red "not loaded, ..." when missing).
3. **Settings**. Today's view unchanged (search, categories, module rows with checkboxes, module page with header,
   options). Title bar shows **< Home** instead of Settings. Changes:
   - Module pages no longer have Options/Page tabs: a module with a page shows its options, plus a button row
     "Open <page title> →" at the top that switches to the Page view.
   - Module header gets dependency lines under the description: "Uses X: why" (green) / "Uses X: not loaded, ..." (red) and
     "Conflicts with X: why" (red while X is loaded) from the module's `uses` / `conflicts` fields.

The window remembers the current view for the session (re-opening Tomte goes to Home, as agreed: "/tomte always
opens Home"). The selected settings module is still saved (`TomteDB.panel.selected`).

## Module API additions (Core/Modules.lua stays pure logic)

```lua
home = {                                  -- optional, list of entries
  { kind = "page",  key = "weekly", name = "Weekly board", icon = <texture|atlas>, page = <page object>,
    summary = function() return "Vault 4/9 · 2 prof quests left" end,   -- optional, nil/"" = no line
    shown = function() return true end },                               -- optional
  { kind = "map",   key = "collect", name = "Collect here", icon = ..., open = ns.CollectTab_Open, summary = ... },
  { kind = "quick", key = "inbox", name = "Whisper inbox", open = fn, count = function() return 3 end },
},
uses      = { { addon = "Syndicator", why = "item counts across characters" } },
conflicts = { { addon = "WaypointUI", why = "Waypoints stays off while it's enabled" } },
```

- `page` objects keep today's shape `{ title, Create(frame), Refresh(frame) }`; `module.page` is removed from modules
  that move to `home` (Weekly, Hunter, Flight, Mount) and set as the home entry's `page`.
- Pure helpers (unit-tested): `ns.HomeEntries(kind)` → visible entries of that kind (by `order`, then registration (module
  active, `shown()` true); `ns.ModuleDependencies(module, isLoaded)` → lines `{ text, ok }` for uses/conflicts.
- `summary`/`count` are called in `pcall` when Home is shown (errors go to the error handler, the tile shows no line).
  They must be cheap and read existing state only; no scans.

## Entries

| Module | Kind | Name (order) | Summary / count |
|---|---|---|---|
| Alts (spec 2) | page | Alts (1) | "N characters · total gold" |
| Weekly | page | Weekly board (2) | "Vault x/9 · n knowledge left" (`Weekly_HomeSummary`); below max level "Max-level characters only" |
| Hunter | page | Stable (3) | "N pets" from the stable snapshot; module is blocked (so hidden) on non-hunters |
| Flight | page | Flight coverage (4) | "N flight masters timed" (`Coverage_Timed`, cheap) |
| Mount | page | Mount zones (5) | "N zone favorites here" (`Mount_ZoneList` on where you stand) |
| Collect | map | Collect here (1) | "2 mounts, 18 achievements left" (cached catalog), "Reading your collections..." until built |
| Teleports | map | Teleports (2) | "N ready" (known entries off cooldown) |
| World quests | map | World quests (3) | "N world quests around here" (`C_TaskQuest.GetQuestsOnMap`, no reward reads) |
| Whispers | quick | Whisper inbox (1) | unread count |
| Recap | quick | Last session recap (2) | shown when a last session exists |
| Gear | quick | Reveal upgrades (3) | none |

Entries sort by `order`, then registration. Quick actions hide the Tomte window before they run (they open their own
window or card).

Summaries that need data a module doesn't already keep are left out (no line) rather than computed on the spot.
Exact sources are listed in the implementation plan.

## Shortcuts

- `/tomte`, minimap left-click, compartment: open/toggle Home. Help text and the minimap tooltip say "open Tomte".
- `ns.Panel_OpenModule(key)` (Gear sheet button, Achievements dock, Waypoints): Settings view on that module.
- `ns.Panel_OpenPage(key)` (new): Page view; `/tomte weekly board` uses it. `/tomte alts` opens the Alts page.
- Map entries: call the module's existing `open` (they already open the map + select the tab), then hide Tomte.

## Removed

- The FlightTimer hand-over (`Core/Migration.lua`, Flight's blocked check, TOC OptionalDeps): FlightTimer no longer
  exists. The WaypointUI collision check stays (it's a conflict, not a dependency).

## Testing

- Plain Lua: `HomeEntries` visibility rules (inactive module, `shown` false, registration order), dependency lines.
- In game: Home layout at default and minimum size, each tile/rail entry/quick button, Settings ↔ Home, Esc closes,
  Gear sheet + Achievements dock buttons land on settings, `/tomte weekly board`, map tiles in and out of combat.

The default WoW font has no arrows, check marks or house glyphs, so the UI uses plain text ("< Home", "Open X >").

## Revision 2026-10-05: Home as a journal

After the first in-game look the user found the tile grid mostly empty space on a big window (and tile borders cut
off on the right). Redesigned with the frontend-design pass and approved from a mockup ("much better and
professional"):

- **The rail is on Home too.** Home is the page view without a page: rail on the left (pages, then "On the world
  map" entries in map blue #8FC7FF with an "Opens the world map" tooltip; every rail row's tooltip shows the entry's
  summary). Tiles are gone.
- **Hero column** (290 px, hidden when the content would get narrower than 620 px): the current character as a
  `PlayerModel` (drag to turn) on a warm gradient, the name in Morpheus 40 in class color, "Level 80 Blood Elf, Beast
  Mastery", item level / gold / lowest durability / location (narrow font, right-aligned), and the quick actions as
  full-width buttons with their counts.
- **Sections** (module.home entries `kind = "section"`, `slot = "week" | "characters"`, `Create(frame, Kit)` /
  `Refresh(frame)`): Weekly's "This week" across the top (Great Vault 3×3: earned slots gold with item level, the next
  one "p/t"; reset countdown; "Still open for <name>" in two columns from `Weekly_HomeTodo`, open first, done dimmed;
  "Open Weekly board" link), Alts' "Your characters" on the left (rows: class-colored name, level, profession icons
  with unspent knowledge, gold; total gold; the eleven professions as icons, lit when someone has it, tooltips list
  who, "n of 11").
- **Around you** on the right: entries `kind = "around"` with `title()` and `items(limit)` → `{ icon, text, color,
  right, onEnter }`, drawn as a blue clickable heading (opens the map tab) and rows: Collect here (mounts and pets,
  then the achievements closest to done), World quests (the tab's own order and filters, reward text + time left),
  Teleports (ready ones).
- **Kit** (`ns.HomeKit`): `Heading` (Morpheus title, grey meta, link on the right), `Row` (icon, text, narrow right
  text), `PoolRow` / `HideFrom`. Sizes are snapped to whole pixels.
- Section headings are sentence case (no all-caps labels). Fonts: Morpheus for headings and the name, Friz Quadrata
  for text, Arial Narrow for numbers.
