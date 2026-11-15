# Tomte map (Forever): our own seamless world map and minimap quest markers

Date: 2026-11-15. Forever only (client 1.60.1, Interface 16001).

## Why

Blizzard's world map and quest tracker taint as soon as addon code calls into them (memories: never open the map
from code, quest-follow taint, Esc vs Alt+Z). Every map feature Tomte builds on `WorldMapFrame` has to tiptoe around
that. A map window that is Tomte's own, with Tomte's own markers, can't taint anything of Blizzard's and works in
combat. Making it one seamless, zoomable world (as OpenMap does) is the other half of the wish. The minimap gets our
own quest markers and quest areas, which the game only draws for its super-tracked quest (and super-tracking from
addon code taints).

## Goals

- Minimap: the followed quest's pin (on the edge when out of view) and its area; the other quests' spots on the
  player's map as small markers. Turns with a rotating minimap (pins; the area hides while rotating), round or square.
- A Tomte window holding one stitched world: both continents (Azeroth map 947's layout), every zone's art on top of
  its continent, explored overlays as the game reveals them. Wheel zooms toward the cursor, drag pans, double-click or
  a button finds you. Player arrow with facing, party and raid members, the zone name under the cursor.
- On it: quest pins of every visible zone, the followed quest's ring and area, flight masters (known ones lit),
  dungeon entrances, Waypoints' target. Clicking a quest pin follows it; Ctrl-click places a Waypoints pin.
- Its own key binding (bind M to it) and `/tomte map`. Esc closes it. Movable, resizable, remembers its size.

## Non-goals (this pass)

- Blended zone borders, colour matching, minimap terrain at the closest zoom, sea art: OpenMap does these with an
  offline-baked art pipeline (364 MB of textures). Decide after seeing the raw stitch in game.
- The quest log inside the map, moving the Collect/Teleports/World quests tabs, boat routes, caves, drawing, search.
- Replacing Blizzard's map: it stays as it is; M is the player's choice in Key Bindings.

## Anti-goals

- Anything that calls into `WorldMapFrame`, the quest tracker or `C_SuperTrack` setters from the map's own code
  (Ctrl-click goes through Waypoints, which already owns that choice).
- A map that hitches: no loading of hundreds of textures in one frame, no OnUpdate while hidden.

## Approaches considered

1. **Embed in WorldMapFrame (OpenMap's way).** Blizzard's and other addons' pins keep working; but it writes
   Blizzard's scroll container and taints (OpenMap documents gamepad and combat pin breakage). Rejected: the whole
   point is to stop touching Blizzard's map.
2. **Own window, art from the live API (chosen).** `C_Map.GetMapRectOnMap(zone, 947)` places each zone,
   `C_Map.GetMapArtLayers/GetMapArtLayerTextures` give its tiles, `C_MapExplorationInfo.GetExploredMapTextures` the
   revealed parts. No shipped art, no generated data. Seams between zones show where zone rectangles overlap.
3. **Own window with baked art (OpenMap's polish).** Smooth borders, but needs an offline pipeline (wago.tools DB2,
   CASC downloads, mask baking) and hundreds of MB in the zip. Kept as a later step on top of 2 if the seams bother.

## How it's built

New Forever-only module **Tomte map** (`key = "map"`, category `travel`), folder `Modules/Map/`:

| File | Role |
| --- | --- |
| `Data.lua` | Pure: world units (art pixels of map 947), zone rect -> world box, zoom/pan maths (zoom toward a point, clamp), visibility of a box in the view, zoom levels. Tested in `tests/test_map.lua`. |
| `Art.lua` | Zone and continent tiles and explored overlays: built per region once, textures set lazily (at most 48 files a frame), culled against the view, anchors cleared while culled. |
| `Pins.lua` | Player arrow, party, quest pins, followed quest ring and area (one `QuestPOIFrame` per zone, sized to the zone's box), flight masters, dungeon entrances, Waypoints' target. Pins live on an unscaled layer. |
| `Window.lua` | The frame (`TomteMapFrame`, in UISpecialFrames), title bar, find-me button, zone label, resize grip, the view and canvas, mouse handling. |
| `Map.lua` | Main file: module registration, db, events, binding, commands. |

Coordinates: one canvas frame, size W x H (map 947's art size), scaled by `fit * zoom` and anchored to the view's
centre at -u*W, v*H (u, v = view centre in 0..1). Zones placed once in canvas units. Map positions of a zone convert
through its rect; party/player through `C_Map.GetPlayerMapPosition(continent, unit)` and the continent's rect.

Minimap markers: `Modules/QuestList/Minimap.lua` (the Quest list owns "the followed quest"), setting under
"Show it on the world map" (`minimapMark`). Geometry shared with Gather: Gather's `MinimapData.lua` moves to
`Core/MinimapData.lua` as `ns.Mini_*` (pure move, own commit). The area: a `QuestPOIFrame` sized to the zone in
minimap pixels, placed from the player's offset; clipped by frames with `SetClipsChildren`: one for a square minimap,
horizontal strips approximating the circle for a round one (each strip its own blob frame). Hidden while the minimap
rotates (frames can't turn).

## Settings

Tomte map: open with Esc closes it (fixed), "Show flight masters", "Show dungeon entrances", "Show party members",
"Map scale of pins" slider; size and position saved. Quest list: "Show it on the minimap" (`minimapMark`, default on).

## Measured in game before the next step (test list)

- 947 exists on Forever and zone rects line up with the continent art; how bad the seams look.
- `GetPlayerMapPosition(1414/1415, "party1")` works; `QuestPOIFrame` draws at small sizes and in clipped strips.
- Frame time while panning and zooming (Performance module).

## Art, after the first in-game round (2026-11-15)

Zone rectangles overlapped with frames and neighbours, and a grid cut by `GetMapInfoAtPosition` was blocky (the game
only knows rough zone shapes), so the user chose OpenMap-style prepared art (option 1), as an optional separate addon.

- **Minimap tiles** (`tools/minimaptiles.py` -> `Data/Forever/MinimapTiles.lua`, 1724 tiles, ~27 KB): the game's own
  minimap files per terrain tile, read from each continent's WDT (MAIN/MAID). Drawn over the art from zoom 10 to 22
  (`Modules/Map/Mini.lua`), desaturated, at most 120 at a time. No art shipped.
- **All explored pieces** (`tools/mapreveal.py` -> `Data/Forever/MapReveal.lua`, 572 pieces, ~25 KB): without the art
  addon a zone is drawn from all its pieces (they cover only its own land).
- **Zone masks** (`tools/mapart.py` -> the `Tomte_MapArt` addon, 44 masks, 12 MB, not in git; index in
  `Data/Forever/MapArtIndex.lua`): each zone's own land (union of its pieces' alpha, closed, holes filled, grown and
  blurred), so its full picture is drawn through a soft mask. Used only when the addon's `## Version` matches the index.
- Second round (mask version 2): own land alone left holes between a zone's named areas, where the continent's
  picture showed blown up, and land running to a zone picture's edge brought its burnt frame along as a hard line.
  Each mask is now the zone's territory on its continent: own land grown over the continent's land (read from the
  continent picture's colours) until it meets a neighbour's, never onto the zone picture's outer 3% (its frame).
  Capitals have no pieces, and the game doesn't flag them as cities on this client: MapReveal.lua lists them with no
  pieces and the map leaves them out (they covered their zone with their whole rectangle).
- Mask version 3: each continent picture gets a mask too (its land, a wide band of sea, fading out well before its
  burnt frame) and the world picture always lies under the continents, so the continent's edge no longer shows as a
  hard line over the world's sea.
- Fourth round: a masked zone's picture holds little of its detail (the game draws most of it in the explored-area
  pieces), so the pieces are drawn over it through the same mask: all of them by default ("Show the whole map"), or
  only the explored ones. Continents and zones fade in across their start zoom (x/1.3 to x*1.3, in log space) instead
  of popping in. Quest pins take the game's own quest-button art (Blizzard_POIButton) and one frame level each, south
  on top, so overlapping pins no longer flicker. A strip of land between Dun Morogh and Elwynn lies in no zone's
  picture: only the continent's, with its title lettering, covers it.
- Still open: colour matching between zones (Eastern Plaguelands, Burning Steppes, Shen'dralas stand out); a few
  coastal strips no zone's picture covers show the continent picture; releasing `Tomte_MapArt` (its own zip on the
  GitHub release, maybe its own CurseForge project).

## Left to the builder

Pin icons (atlases the Forever client has), exact zoom range (whole world to about 6x a zone), strip count.
