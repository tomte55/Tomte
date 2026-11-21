# Forever routes: design, 2026-11-21

## Problem

On World of Warcraft: Forever, a map pin gets a straight-line arrow and nothing else. A pin on another continent (a
guide's `/tway #1434 27.4 77.0 Old Man Heming` read in Thunder Bluff) leaves the player to work out the flights and the
zeppelin. Retail's portal router (`Router.lua`, `Route.lua`, `Network*.lua`) is built on retail's own route tables and
retail's world, so it doesn't load on Forever.

## What the player gets

- Tracking a map pin that is quicker to reach by flight path, zeppelin or boat starts a route. The map pin moves to the
  next place to act: the flight master to fly from, the zeppelin tower or dock to board at. Once walking is the
  quickest way left, the player's own pin comes back, with its name.
- Waypoints' arrow and text show the step: "Fly to Orgrimmar", then "Then: Take the zeppelin to Grom'gol", and
  "On the way to Old Man Heming".
- `/tomte way route` lists the whole route; the current step is marked.
- The setting "Route to other continents" shows on Forever too, as "Route by flights, zeppelins and boats".

## How

- **Transports**, hand-kept in `Data/Forever/Transports.lua`: each one's two ends (zone map and percent coordinates),
  its kind (zeppelin, boat) and which side uses it. Zeppelins and the Ratchet boat stand where their zeppelin masters
  and shipmasters are (QuestieDB's Forever NPC data); the Alliance boats come from the classic maps and are marked as
  not checked on Forever. No tram: Stormwind and Ironforge are a flight apart.
- **Flight paths** come from the game: `C_TaxiMap.GetTaxiNodesForMap` on each continent, only the ones you know and your
  side may use (as the Tomte map's pins). Any two known flight masters on one continent count as linked: the game's own
  network on each continent is connected, and the exact hops don't change which flight master to walk to.
- **Planner** (`Modules/Travel/ForeverRouteData.lua`, pure, tested): all places in world yards per continent. Walking
  between any two places on one continent costs distance over a riding speed; a flight costs a fixed wait plus a longer
  than straight distance at taxi speed; a zeppelin or boat a fixed wait and crossing. One Dijkstra from the goal, then
  the best first place to walk to from where you stand. A route is only taken when it beats walking by a clear margin,
  and the step being followed is kept unless another way is clearly quicker (no flip-flopping on a boat).
- **Router** (`Modules/Travel/ForeverRouter.lua`): plans again every second from where you stand (not while on a flight,
  not inside an instance), so landing, a zeppelin crossing or a hearthstone just leads to the next step. Saves the real
  pin per character as the retail router does (`db.routes`, same shape) so a `/reload` mid-route keeps it. It provides
  the same `ns.WayRouter_*` functions as `Router.lua`, so Waypoints and its target text need no Forever branch.
- The pin for a world point (down to the most detailed map that takes a pin) moves from `Router.lua` into Core
  (`ns.MapPinSpot`) for both routers.

- **On the Tomte map** (added after the first test): the route as a line (`Modules/Map/RouteLine.lua`, laid out with
  the flight pins), and in flight mode the ring goes on the flight master the route flies to next, its tooltip
  "On your route to <pin>".
- Pin names survive a `/reload`: Waypoints saves the last named pin per character (`db.named`).
- **Known flight paths** (after the second test): `isUndiscovered` didn't mark an unknown Grom'gol, so routes use only
  the flight paths the flight master's window lists as current or reachable (distant ones include flight paths never
  visited, measured at Undercity), learned per character at every
  flight master (`db.flights`). Until a character has opened one, routes use no flights and say so.
- **The followed quest** (Quest list's auto follow, or any tracked target that isn't a map pin): no pin is placed (an
  addon's super-tracking taints Forever's tracker and map); the arrow itself leads to the route's next step
  (`ns.WayRouter_Aim`, called from `Target.lua`), planned again every second. A quest on another continent is found on
  that continent's map.

## Not now

- Hearthstone and mage teleports as steps (there is no API for the hearthstone's spot).
- Mountains and water between two places on one continent: walking is a straight line.
