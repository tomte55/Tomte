# Waypoints: portal routes and guard directions

## Problem

The game routes a tracked **quest** through portals ("Take the portal to Orgrimmar"), but a **map pin** on another
continent gets no navigation at all: no navigation frame, so Tomte's marker shows nothing. Separately, a guard's
directions only put a marker on the map, not a waypoint.

## Guard directions

`DYNAMIC_GOSSIP_POI_UPDATED` within 5 s of a gossip window: read the POI the way Blizzard's GossipDataProvider does
(`C_GossipInfo.GetPoiForUiMapID` / `GetPoiInfo` on the player's map, then parents up to zone level). Setting
"Waypoint for guard directions": Never / Ask (default, `TOMTE_CONFIRM` popup) / Always. A repeat event for the same POI
doesn't ask again. `Modules/Travel/Guard.lua`.

## Portal routes

**Data.** Blizzard's own network: WaypointNode (name, SafeLoc, condition, type 1 leave by / 2 arrive at / 0 path,
volume), WaypointEdge (from, to, cost, condition), WaypointSafeLocs (instance + world x, y), WaypointMapVolume. 574
nodes, 371 edges in 12.1.0.69933. `tools/waynet.py <build>` downloads them from wago.tools and writes
`Modules/Travel/Network.lua`. Nodes without a place (mage "Create a portal", usable anywhere) and `[DNT` nodes are
left out.

**Conditions.** PlayerCondition (+ ModifierTree) compiled into expression trees, TrinityCore's PlayerConditionLogic for
the logic fields (a 0 logic field isn't checked). Checked in game: faction (race masks of conditions 923/924, tree type
116), class, level, quests (completed / on / ready / either / between), known spells, achievements. Everything else
(areas, auras, world states, content tuning, reputation...) is unknown. Three-valued evaluation; only a known false
blocks a node or edge.

**Search.** Dijkstra from the player's world point to the pin's world point. Explicit edges at their cost; walking
between nodes on the same instance at distance / 10. Nodes in an interior volume (bounds all zero, e.g. the Wizard's
Sanctum) are reached only through edges or from the same interior. Nodes within 25 yd of the start cost 0. Volume
bounds are otherwise not used: once you're on the pin's instance the game's own navigation takes over.

**Walking it.** `Router.lua`. When the tracked user waypoint is on another instance, the map pin moves to the current
step (the most detailed map that takes a pin there) and is tracked; the real pin is kept in `db.routes[guid]` so a
/reload mid-route resumes. A step you reach moves on when the next step is on the same map; a portal step stays until
the instance changes, then the route is searched again from where you are. On the pin's instance the real pin comes
back. Removing the pin ends the route; placing another pin starts over. Turning the option or the module off puts the
real pin back. The card shows the step, "Then: <next way off a map>" and the destination. `/tomte way route` lists the
steps.

**Not covered.** Hearthstones and teleports (the Teleports module knows them) aren't part of a route; mage portals
aren't either. Node texts are Blizzard's English names.
