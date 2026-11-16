# Tomte map: town markers, dungeon clicks, title bar (2026-11-16)

Small change to the Tomte map (Forever). Approved by the user in conversation.

## Why

The user wants the Tomte map to do what the minimap's tracking menu does (mailbox, auctioneer, banker, ...), on the
whole map, and to open a dungeon in the Dungeon journal straight from its entrance marker. The map's title bar should
look like every other window's on the Forever theme.

## What

1. **Dungeon click.** A dungeon entrance pin opens that dungeon in the Dungeon journal (`ns.DJ_Open`). Its tooltip says
   so. Does nothing but print when the journal is off (`ns.Module_RequireOn`).
2. **Town markers.** A magnifying glass button at the map's top-right corner (inside the map's well), as the minimap's
   tracking button. Click: a checkbox menu (`UI.ContextMenu`), the minimap's tracking icons inline: Auctioneer, Banker,
   Battlemaster, Innkeeper, Mailbox, Class Trainer, Profession Trainers, Repair, Stable Master, Flight Master,
   Dungeon entrances. The last two drive the existing `taxis` / `dungeons` settings.
   - Pins: the game's tracking icons (`Interface\Minimap\Tracking\<kind>`), shown only at zone level and closer.
     Tooltip: name and title. Only NPCs friendly to your faction (or both); class trainers only for your class.
   - Saved in `db.town = { [kind] = true }`, all off by default (a friend's map stays clean). Also in the options as
     checkboxes under "On the map".
3. **Title bar.** On the Forever theme the map uses the frame other windows use: the metal strip with the round badge
   (`PortraitFrameTemplate`, as the Tomte window), the place and coordinates centered on the strip, the red close
   button in the corner. The find and quest log buttons move to a row under the strip. Other themes keep today's bar.

## Data

`tools/townsfolk.lua` builds `Data/Forever/Townsfolk.lua` from QuestieDB's Forever data (GPL-3.0, facts only: IDs,
names, titles, service flags, factions, positions), applying its corrections in its own order (legacy classic fixes,
generated Forever delta, authored Forever fixes). Zone area IDs go to uiMapIDs through QuestieDB's
`areaIdToUiMapId`. Trainers are sorted by their title ("Warrior Trainer", "Journeyman Blacksmith"). Flight masters
stay the game's own (`C_TaxiMap`). Credited in README.

## Approaches

- Learn as you play (save where a mailbox, bank ... was opened): always right, but empty at first.
- **Questie's data (picked by the user):** the whole map filled from day one; Forever-specific gaps follow QuestieDB.
- Both: more work; not needed while QuestieDB tracks Forever.

## Builder's calls

- Town pins are smaller than dungeon pins (14 px) and sit under dungeons and flight masters.
- The glass is an action-icon button like the map's other buttons, its icon `Interface\Minimap\Tracking\None`
  (the minimap's tracking button art), falling back to the spyglass.

## Round 2 (user's in-game feedback, 2026-11-16)

- Badge: the game map's book (`Interface\QuestFrame\UI-QuestLog-BookIcon`, WorldMapFrame's portrait), drawn under the
  frame's metal so the frame's own ring goes round it (`UI.Forever_Badge(..., under)`).
- Menus on the Forever theme look like the game's (Blizzard_Menu: Classic MenuStyle2 background, Cata checkboxes,
  the tooltip divider, the quest title highlight); rows can carry an icon on the right (`desc:SetIcon`). The town menu
  opens to the left of its button, over the map (`UI.ContextMenu(by, gen, "LEFT")`).
- Town markers of one kind close together on the view share one pin (`ns.Map_Group`, about one pin width); its
  tooltip lists each NPC with its title.
- Find me is a round button beside the glass; the quest log button is the game map's side panel toggle
  (`QuestCollapse-Show/Hide`) on the map's bottom-right corner. The row under the strip keeps only the coordinates.
- A search box over the quest list: every word typed must be in the quest's title, zone or objectives
  (`ns.Map_QuestMatches`).
