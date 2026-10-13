# Tomte: Gathering routes, follow mode and minimap nodes

Date: 2026-10-13. The user asked for "the best variant" of a route helper on top of the node spots Gathering
remembers (`2026-10-13-tomte-sharing-update-nodes-design.md`), built end to end with Claude making the decisions.
Picks up the "Later" items of that spec: minimap pins, "last gathered" per spot and a route through a zone's nodes.

## Goal

A gatherer opens the map in a zone and sees a loop through the node spots Tomte knows. One click (map button,
`/tomte gather follow` or a key binding) starts **follow mode**: Tomte puts a map pin on the next spot of the loop,
Waypoints (or Blizzard's arrow) shows the way, and the pin moves on as the player reaches each spot or gathers it.
On the minimap the spots show as small icons, and while following the loop is drawn there too.

## Decisions

### The loop (pure, `Modules/Gather/Route.lua`)

- One loop per map through the spots the map shows (the "Show nodes" choice: your professions or all), so a Miner
  and Herbalist gets one mixed loop. Distances in yards (`C_Map.GetMapWorldSize`); straight lines, because gatherers
  fly.
- Built with nearest neighbour (from k-nearest lists, K = 8), then 2-opt on the neighbour lists until nothing
  improves. Deterministic: the same spots give the same loop. Maps with more than 1,000 spots get no loop (about 0.15 s
  to build in one frame; no zone comes close).
- **Leave out far-off spots** (setting, on): a spot whose detour (`d(prev, s) + d(s, next) - d(prev, next)`) is more
  than 3 times the loop's median leg and more than 300 yards is dropped, worst first, at most a quarter of the
  spots. A lone spot across the zone costs more flying than it brings.
- Built lazily and cached per map and kinds; any change to the spots (a new one, an import, Forget) drops the cache.
- Follow rules are pure too: the start is the nearest spot not gathered in the last 5 minutes, and the direction is
  the one whose next leg is closest to where the player faces (`GetPlayerFacing`). Moving on skips spots gathered in
  the last 5 minutes, unless every spot was.

### Follow mode (`Modules/Gather/Follow.lua`)

- Start: the map is the player's zone (`GetBestMapForUnit`, or its parent when the player stands in a cave map
  without enough spots). Needs at least 2 spots in the loop and a player position (none in instances).
- The pin is placed with `ns.TrackPin` (combat-safe). Every 0.2 s Tomte checks the player's distance on that map;
  within 30 yards the pin moves to the next spot (whether the node is there or not: you see it on the minimap).
  No separate "gathered it" trigger: the loot window opens next to the node, well inside 30 yards, so the distance
  check has already moved on, and a gather near the next spot would skip it. A key binding and
  `/tomte gather skip` skip a spot by hand (somebody took it).
- The Waypoints card names the node ("Bismuth") with "Gathering route, spot 3 of 42, lap 1" below it.
- Stops: the same button, command or binding (the earlier map pin and super-tracked quest come back); tracking
  something else (a quest, your own map pin), which is respected and not undone; Gathering switched off; 60 seconds
  away from the route's map; a logout or `/reload` (the last pin stays as a plain map pin).
- The loop is copied when following starts, so spots learned on the way don't reshuffle it mid-lap.

### "Last gathered" (session only)

- Gather.lua remembers, per spot, when you last gathered it this session (`GatherNodes_Add` now returns the spot a
  gather merged into). No saved data and no migration: node respawn is minutes, not days.
- World map and minimap dim spots gathered in the last 5 minutes; the world map tooltip says "Gathered 3m ago".

### Drawing

- World map (`MapPins.lua`): the loop as thin accent-colored lines under the pins (setting "Show the route on the
  world map", on), the pin being followed bigger with an accent ring, and the map button's tooltip and menu give
  the loop's spots and length ("42 spots, 6,300 yards a lap") plus Follow / Stop following.
- Minimap (`MinimapPins.lua`, setting "Show nodes on the minimap", on): small icons for the spots of the player's map
  within the minimap's view (`C_Minimap.GetViewRadius`, `Minimap:GetWidth()`), turning with a rotating minimap
  (`rotateMinimap` CVar), round or square (`GetMinimapShape`, the LibDBIcon convention). Icons at 75% alpha so
  Blizzard's own tracking blips still show. While following: the loop as lines, clipped to the minimap's edge, and
  the followed spot clamped to the edge when it's out of view.
- The minimap's update runs only while there are spots on the player's map (OnUpdate on a frame hidden otherwise);
  the spots near the player are picked once a second, and only those are placed every frame. The geometry
  (offsets, rotation, round/square bounds, edge clamp, line clipping) is pure: `Modules/Gather/MinimapData.lua`.

### Settings, commands, bindings

- Nodes section: "Show nodes on the minimap", "Show the route on the world map", "Leave out far-off spots" and a
  "Route in this zone: Follow" button. New keys get defaults; nothing reshaped, so no migration.
- `/tomte gather follow` (start or stop), `/tomte gather skip`, `/tomte gather route` (the loop on this map and why).
- Key bindings: "Gathering route: follow or stop" and "Gathering route: skip a spot".

## Out of scope / later

- Routes across continent maps or between zones; a loop drawn on the continent map.
- Saved per-spot statistics (times gathered, last seen across sessions).
- "Where to farm X" (zones ranked by spots of an item) and zone suggestions from run history.
- Resuming follow mode after `/reload`.
