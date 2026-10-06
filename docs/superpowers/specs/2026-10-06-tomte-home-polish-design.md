# Tomte: Home polish (hero facts, rail pills, more "Around you", toggle key)

Date: 2026-10-06. Picked by the user from the post-Home ideas. **Spec only, not built.** Builds on the Home screen
(`2026-10-05-tomte-home-design.md`) as it is on this branch, with Next up and Recent stacked above "Around you".

Rule for everything here (agreed with the user): Home must not get cluttered. Anything new shows only when it has
something to say, and prefers a tooltip or a click over a new row.

## 1. Clickable hero facts

The four facts under the character model (Item level, Gold, Durability, Location) become buttons. Nothing changes
visually until hover: the row gets the faint row highlight (`Kit.Row`'s `bg`) and a tooltip whose last line says
what a click does.

| Fact | Tooltip | Click |
|---|---|---|
| Item level | Equipped and overall item level (`GetAverageItemLevel()`), and "n missing enchants, n empty sockets" from Gear Check's audit (`ns.Gear_Audit` / `Gear_AuditText`) when there are any | Opens the character pane with Gear Check's sheet panel (new small export `ns.GearSheet_Open` next to `GearSheet_Refresh`) |
| Gold | This session's gold change and where it came from (Recap's session money split, `Value_SessionLootText` for loot worth), the account total (Alts) and, with Gold & value, carried value | Opens the Sessions page (`ns.Panel_OpenPage("sessions")`) |
| Durability | Worst three slots with percent (`Durability_Summary`'s slots) | Prints what `/tomte dura list` prints (that command's function, exported as `ns.Durability_List`) |
| Location | Zone, subzone, map coordinates | Opens the world map on the player's map (`OpenWorldMap(C_Map.GetBestMapForUnit("player"))`) |

- A fact whose module is off has no click (tooltip only, no "Click:" line).
- In combat: the character pane can't open from an addon button (`ToggleCharacter` is protected in combat),
  so the Item level click is skipped with "Not in combat".

## 2. Rail pills

A small count pill at the right end of a rail row: gold text on a dark rounded backing, the way Blizzard's
quest log shows counts. **Only when the count is above 0**; most of the time the rail looks as it does today.

- Page entries get an optional `pill = function() return n end` (same contract as quick actions' `count`:
  cheap, existing state only, called through `ns.HomeCall`).
- Map entries never get pills (Around you already shows their counts).
- Max two digits ("99+" above that). The row text truncates to make room.

| Page | Pill | Why it's actionable |
|---|---|---|
| Alts | Crafting list to-do lines for the character you're on, excluding grey "other character has it" lines (`ListData` to-do cache) | Something to grab, mail or craft here |
| Weekly board | Great Vault rewards waiting (1) + characters with Concentration full | Something to claim/spend |
| Stable | none | |
| Flight coverage | none | |
| Mount zones | none | |
| Sessions | none | |

Option (Tomte window, existing "Tomte window" settings): "Counts on the rail" (on).

## 3. More "Around you" blocks

Two new `kind = "around"` entries. The right column already holds Next up and Recent, so both blocks are small
and conditional:

- **Flight masters** (Flight module): flight masters on the player's zone that you haven't timed a route from
  (`Coverage_Summarize` for the zone, nodes with state "untimed"). Title "Flight masters: 3 not timed here".
  Rows: node name, distance on the right when known. Click: a waypoint to the node through `C_Map.SetUserWaypoint` (Waypoints tracks map pins as soon as
  they're placed, the same way `Weekly_SetWaypoint` works). **Shown only when the zone has untimed nodes.** `maxRows = 2`.
- **Mount favorites** (Mount module): your zone favorites for where you stand (`Mount_ZoneList`). Title
  "Mount favorites: 4 here". Rows: icon and mount name. Click: summons it (`C_MountJournal.SummonByID`, out of
  combat). **Shown only when there's at least one.** `maxRows = 2`.

Both go after Teleports in `order`, so Collect / World quests / Teleports keep their rows first when space is
short (Around you already gives every block two rows, then the rest in order).

A Home setting "Around you shows" with a checkbox per block (Collect here, World quests, Teleports, Flight masters,
Mount favorites), all on. Lets the user trim the column without turning modules off.

## 4. Toggle key

`Bindings.xml`: `TOMTE_TOGGLE` in category Tomte, "Toggle Tomte", calling `Tomte_Binding("TOGGLE")` →
`ns.Panel_Toggle()` (already exists). Unbound by default.

## Testing

- Plain Lua: pill text ("" at 0, "99+"), the flight master filter (untimed only, sorted by distance), the
  "Around you shows" filter in `HomeEntries`.
- In game: hover/click each fact (also in combat), pills appear and vanish as the crafting list and vault change,
  a zone with and without untimed flight masters, a zone with mount favorites, the key binding.

## To verify

1. `C_MountJournal.SummonByID` from a Home row's OnClick (not protected per the 12.1 API docs; check in game).
2. The flight master nodes' map positions in `Flight/Atlas.lua` are on the zone map (for the waypoint and distance).
3. Gear Check's sheet panel can be opened by code (today it's opened from the character pane button).
