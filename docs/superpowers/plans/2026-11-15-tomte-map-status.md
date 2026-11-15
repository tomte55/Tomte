# Tomte map (Forever): status, 2026-11-15

Where the Tomte map, its art pipeline, the Quest list's minimap markers and Square minimap stand, so the work can be
picked up again. Design and every round's reasoning: `docs/superpowers/specs/2026-11-15-tomte-world-map-design.md`.

## Commits

| Commit | What |
| --- | --- |
| b2ef67d | Gather's minimap geometry moved to `Core/MinimapData.lua` (pure move) |
| 83403d3 | Quest list's minimap markers; Tomte map, first version |
| 761b496 | Minimap pictures close up, territory and continent masks (Tomte_MapArt v3), level fades, game-style quest pins |
| 6bb6f94 | Quest log beside the map, detail settings, keys, flights, pin fan-out, place names (v6), Square minimap, Quest list minimap look and garbage fix, pin button |

Not pushed by this session; the beta release (tomte-be session) pushes everything.

## What works (checked in game by the user)

- One seamless world in its own window (`TomteMapFrame`): wheel zoom toward the cursor, drag, right-click out, levels
  fading in (world, continents, zones, then the game's minimap pictures), "Show the whole map" (all pieces drawn).
- Pins: you (larger arrow, a ping on open), party, quests in the game's quest-button look, fanned out where they
  overlap (`Map_Clusters`, eased), the active quest's area (stronger over parchment, light over the ground pictures),
  flight masters, dungeon entrances (from the Dungeon journal's data), your map pin. Pins grow a little close up.
- Ctrl-click places a map pin (the map pin cursor shows while Ctrl is held); Ctrl-click on the pin removes it with its
  tracking (`ns.ClearOwnPin`), so the Quest list's follow picks up again.
- Side panel (book button or the quest log key): your quests by zone heading; hover shows a find button that flies
  there (`Map_Flight`, one fluid move, same end zoom every time); right-click the Quest list's menu. Teleports tab when
  that module is on (the world map's panel, lent via `ns.MapTabs_Borrow`). Slides open; the map keeps its scale and
  its left edge.
- Keys: `CLICK TomteMapButton:LeftButton` (map, like M) and `:RightButton` (map with quest log, like L), in Key
  Bindings > Tomte and as the map's "Map key" / "Quest log key" settings (override bindings, M and L replace the
  game's).
- Detail settings: continent maps from (default 1.2x), zone maps from (5x), ground pictures on/from (10x).
- `ns.MapWindow_ShowSpot(mapID, x, y, label)` (0..1 coordinates): the Dungeon journal's Show on map / Show entrance.
- Square minimap module: square mask, thin frame, Forever's day/night icon moved to the corner, other addons' buttons
  follow (`GetMinimapShape` while on and no other addon defines it; LibDBIcon refreshed).
- Quest list minimap: the game's quest buttons, the area drawn lighter; spots read only when the log, the active quest
  or your map changes (105 MB in 3 min down to about 25 MB in 4 min).

## Built but not yet confirmed in game

The last round went into 6bb6f94 untested:

- Place names v6: names are copied only where two zones name the same spot ("clash" rule), otherwise kept; preview
  showed Camp Taurajo, Razorfen Kraul/Downs and Northwatch Hold whole.
- Zone pictures fading out before their frame (`FRAME_FADE`): the straight line at Feralas over Desolace.
- Title bar buttons moved inside the bar.
- The bigger player arrow and the ping on open.

## Open work, in the order planned

1. **Performance.**
   - Map window: `Window · OnUpdate` about 0.5 ms a frame while open, 26 MB made in a session.
   - Opening the map: frames over 100 ms (Build plus the first layout loading art).
   - Quest list minimap markers: about 6 KB of garbage and 0.1 ms per frame left (one
     `GetPlayerMapPosition` vector per frame; `LevelingRead_You` only when there's no zone map).
2. **Shipping Tomte_MapArt.** It's built locally into `_forever_\Interface\AddOns\Tomte_MapArt` (version 6) and is in
   neither git nor the release zip, so friends get the map without soft borders and with cut names. Proposal: its own
   zip on the GitHub release, maybe its own CurseForge project. Its masks are made from Blizzard's art (see Sharing in
   CLAUDE.md and OpenMap's NOTICE).
3. **Known gaps nobody's art covers.** Land no zone picture covers shows the continent picture blown up: north of
   Elwynn (the continent's "M" of its title) and north of Durotar (Orgrimmar). Filling it with the capital's own city
   map was tried and looked worse (a bright city fragment); left as is.
4. **Not done.** Colour matching between zones (tried: tints can only darken, the colours are Blizzard's design;
   dropped). Moving Collect here / World quests tabs (they don't load on Forever, so only Teleports moved).

## Rebuilding the art

From the Tomte folder (Pillow and numpy in user site-packages, so `python -P`, not `-I`):

```
python -P tools/minimaptiles.py ...   # Data/Forever/MinimapTiles.lua (see its docstring)
python -P tools/mapreveal.py ...      # Data/Forever/MapReveal.lua
python -P tools/mapart.py 1.60.1.70938 <cache folder> "D:/World of Warcraft/_forever_/Interface/AddOns/Tomte_MapArt"
```

`mapart.py` writes the addon (`## Version`, `Masks/Zone*.tga`, `Continent*.tga`, `Labels*.tga`) and
`Data/Forever/MapArtIndex.lua` together; bump `VERSION` whenever masks change, since Tomte only uses an addon whose
version matches its index. Stale `Labels*.tga` for zones without names can be deleted by hand. Offline preview scripts
(compose, coverage, names) lived in the session scratchpad and are gone with it; `mapart.py`'s functions
(`pieces_picture`, `label_boxes`, `territory_mask`) are what they used.

## Measured on Forever (keep)

- Forever reads `Bindings_Forever.xml`, not `Bindings.xml`: keep both in step.
- `C_EncounterJournal.GetDungeonEntrancesForMap` lists nothing for Forever's zone maps.
- Some API positions (`C_Map.GetUserWaypoint().position`, some places) come without `GetXY`: read `.x`/`.y` too
  (`Pos` in Pins.lua).
- Removing a map pin needs `C_SuperTrack.SetSuperTrackedUserWaypoint(false)` too, as the game's map does; else
  `ns.OwnTargetTracked` stays true.
- A zone's place names are in its explored-area pieces, not its base picture; a zone's map also names neighbouring
  places near its edges.
- The day/night icon is `MinimapCluster.DielFrame` (Camelot/Diel.lua), placed again by `SetEditModeScale`.
- Some dungeon doors are given on a continent's map (Wailing Caverns on Kalimdor): zoom to the zone at the spot.

## Files

`Modules/Map/`: Data.lua (pure, `tests/test_map.lua`), Art.lua, Mini.lua, Pins.lua, QuestTab.lua, Side.lua, Window.lua,
Map.lua. `Core/QuestPin.lua` (quest button look, shared with `Modules/QuestList/Minimap.lua`), `Core/Core.lua`
(`ns.ClearOwnPin`), `Panel/MapTabs.lua` (lending a tab), `Modules/SquareMinimap/SquareMinimap.lua`,
`Data/Forever/{MinimapTiles,MapReveal,MapArtIndex}.lua`, `tools/{minimaptiles,mapreveal,mapart}.py`. Forever-only
files are listed in `tools/forever_list.lua`.
