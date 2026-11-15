# Dungeon journal (Forever): status, 2026-11-15

Where the Dungeon journal stands, so the work can be picked up again. Design and the second pass (look and eight
additions): `docs/superpowers/specs/2026-11-15-tomte-dungeon-journal-design.md`; first build plan:
`docs/superpowers/plans/2026-11-15-tomte-dungeon-journal.md`.

## Commits

| Commit | What |
| --- | --- |
| 22afe2d | Design |
| 32c3441 | The module, its data and generator, test, README row, CHANGELOG line, key binding |

Not pushed by this session; the beta release (tomte-be session) pushes everything. The user was asked whether the
journal ships in that beta, since the last round wasn't tried in game (revert 32c3441 to hold it back).

## Checked in game by the user (earlier rounds)

- The page opens from Home, `/tomte dj` and the minimap button; dungeons listed by level group with level bars.
- A dungeon's Quests and Bosses tabs, quest details and boss loot. The user reported problems the round after:
  - the tile star vanished as the pointer reached it;
  - the key was missing from Key Bindings;
  - Show on map errored in the map's Pins.lua.
  All three are fixed in 32c3441, but those fixes are untested.

## Built but not yet confirmed in game

- The redesign the user picked (mockup "D": B's layout with C's depth):
  - the lit band (`Stage.lua`) with the boss or quest giver's model, frozen and turned by dragging;
  - loot as raised tiles with a quality glow and badges;
  - the list in a well;
  - the "All dungeons" back button.
- Show on map / Show entrance open the Tomte map on the spot with a pulsing mark (`ns.MapWindow_ShowSpot`, Map's code).
  They also set a waypoint.
- The key: `CLICK TomteDungeonJournalButton:LeftButton`. It has to be in `Bindings_Forever.xml`, which is the file
  Forever reads; `Bindings.xml` has it too.
- The tile star is a non-mouse frame, so hovering it keeps the tile's hover. Click the star or right-click to toggle.
  A redraw under the pointer keeps the hover look.
- Stars on bosses and dungeon rows that hold wanted items; "N upgrades" on dungeon rows in the "now" group.
- "Usable by you" switch on the band (`db.usableOnly`, also a setting); "Before you go" (open quests by start zone).
- Search lands on the hit (boss, quest or extra drops), with the matched item marked and scrolled to.
- Inside a dungeon, `/tomte dj` and the key open on that dungeon (`ns.DJ_Here`).
- Open question to the user: in a Wailing Caverns screenshot, Lord Pythas' row looked highlighted next to the picked row.
  Was the pointer over it?
- `MODEL_ZOOM` 0.45 in `Stage.lua` is a guess, to tune in game.

## Open work, in order

1. The user's in-game test of everything above; fix what it finds.
2. The run tracker: its own design doc first, then a module. What the user asked for:
   - a timer and XP (XP per hour, runs to the next level);
   - bosses killed, detected by NPC ID on death (needs an in-game check of what Forever allows);
   - the dungeon's quests with live objectives;
   - a summary card on leaving;
   - run history saved, shown on the journal's dungeon page (best time).

   Reuse Leveling's XP reads, the Quest list's state, Recap, Edit Mode and `ns.DJ_Here`. The user wants it like
   ExehnTV's DungeonJournal's tracker but in Tomte's style (no code taken).
3. Maybe: ATT's `lore` text for a dungeon's about line (in the data source, not generated yet).

## Facts measured

- The data's `id` is the Encounter Journal's journalInstanceID (63 = Deadmines); `area` is ATT's zoneTextAreaID
  (nil for Dire Maul and Atal'hakkar).
- Doors: 18 of 28 dungeons have one (`door = { map = uiMapID, x, y }`, percent), from ATT's `coord` or the first
  of `coords`; the 50,50 placeholder is dropped. None for Hall of Thanes, Ruins of Lordaeron, The Drowned City,
  Krol'dok Stronghold, Dire Maul, Alcaz Prison, Stratholme, Blackrock Spire, Blackmaw Hold, The Shaper's Terrace.
  BRD's door is on map 35.
- Forever's zone maps list no EJ dungeon entrances (Map measured), so `J.Entrance`'s EJ fallback finds nothing.
- The Tomte map reads this module's `door` field for its dungeon entrance pins: keep that shape.
- Upgrade checks need item data cached: `J.Upgrades` preloads 20 items every 0.25 s (`C_Item.IsItemDataCachedByID`).

## Rebuilding the data

`tools/dungeonjournal.lua` turns AllTheThings' Forever database (MIT) into `Data/Forever/DungeonJournal.lua`.
Clone or download ATT, then from the Tomte folder run:

```
lua tools/dungeonjournal.lua <ATT folder> <ATT folder>/config <ATT commit SHA>
```

The SHA goes into the file's header. Never edit the generated file by hand.

## Files

| File | Role |
| --- | --- |
| `Modules/DungeonJournal/Data.lua` | Pure: level groups, quest fit and state, quest and boss lists, search hits, Before you go, loot (`tests/test_dungeonjournal.lua`) |
| `Read.lua` | `ns.DJKit` (J): page state, names, your context, Gear Check verdicts and upgrades, wanted items, `ns.DJ_Here`, entrances |
| `Parts.lua` | Pooled text, labels, list and detail rows, row stars |
| `Stage.lua` | The lit band and its model; the list's well |
| `Tiles.lua` | Loot tiles and the star |
| `Detail.lua` | Right side: boss, quest, Before you go; map pins |
| `Lists.lua` | Left list and the dungeons page |
| `Page.lua` | The page: header, tabs, switches, events while shown, `ns.DJPage_Show` |
| `DungeonJournal.lua` | Registers the module, settings, minimap button, the key's hidden button |
| `Data/Forever/DungeonJournal.lua` | Generated data |
| `tools/dungeonjournal.lua` | The generator |
| `Bindings_Forever.xml`, `Bindings.xml`, `Core/Core.lua` | The key binding and its name |
