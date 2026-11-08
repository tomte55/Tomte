# Leveling: Next quests widget (World of Warcraft: Forever)

2026-11-08. Part of the Leveling module (Forever only).

## Goal

A small on-screen widget that says which quests to do next: the quests close to each other grouped into one stop,
the nearest stop first, and inside it the turn-ins and then the lowest level.

## What the client gives (measured in game, 2026-11-08)

- `C_QuestLog.GetQuestsOnMap(mapID)` returns a point per quest in your log: `questID`, `mapID`, `x`, `y` (0..1 on that
  map), `numObjectives`, `inProgress`. On the Barrens it also listed Stonetalon quests (their own `mapID`).
- `C_QuestLog.GetDistanceSqToQuest(questID)` returns squared yards and whether it's on your continent.
- `C_Map.GetWorldPosFromMapPos` exists, so points on different maps share one world coordinate system.
- `C_SuperTrack.SetSuperTrackedQuestID` makes a quest active (used by the page already).

## Design

**Points.** Read.lua reads each quest's point from `GetQuestsOnMap` for your map and the maps around it (the quest's
own `mapID`), turned into world coordinates. A quest with no point is left out of the widget.

**Clusters (pure, Data.lua, tested).** Single-linkage: quests whose points lie within `CLUSTER_YARDS` (300) of any quest
already in a cluster join it. A cluster's distance is that of its nearest quest to you. Its name is the zone of most
of its quests.

**What's in.** Quests in the page's "done", "timed", "now" and "easy" groups. Dungeon quests (`q.dungeon`) only while
you're in a group. Hard, elite and grey quests stay out. Turn-ins are part of the cluster where you hand them in.

**Order.** Clusters nearest first. Inside one: turn-ins, timed quests, then the lowest level, then the most XP.

**Widget.** Always on screen while Leveling is on and the widget setting is on (default on). Movable through
`ns.EditMode_Register`. Shows the first cluster: a heading with the zone and the yards to it, up to 5 quests (level,
title, "turn in" or XP), then one line for the next cluster ("Then: Stonetalon, 3 quests, 900 yd"). Click a quest:
active quest (the page's click); Shift-click: track. Hover: objectives. No arrow of our own: the active quest's map
marker is enough.

**Updates.** On `QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED`, `ZONE_CHANGED_NEW_AREA` and group changes (debounced),
and a ticker (every 2 s, only while the widget shows) that re-sorts after you've moved about 100 yards. No OnUpdate.

**Settings.** Leveling options: "Next quests on screen" (checkbox), "Quests to show" (slider 3 to 8).

## Files

- `Modules/Leveling/Data.lua`: `ns.Leveling_NextQuests(quests, points, you, grouped)` returns clusters; tests in
  `tests/test_leveling.lua`. If Data.lua passes 900 lines, the quest rules move to `QuestsData.lua` first (pure move).
- `Modules/Leveling/Read.lua`: `ns.LevelingRead_QuestPoints()`.
- `Modules/Leveling/NextQuests.lua`: the widget (after Page.lua in the TOC).
- `Modules/Leveling/Leveling.lua`: defaults, options, events.

## Open

- `GetQuestsOnMap` for the player's map may already return the neighbouring zones' quests; if not, also ask the
  parent (continent) map. To check while building.
- Cluster names: the zone only, unless a landmark name is easy to get later.
