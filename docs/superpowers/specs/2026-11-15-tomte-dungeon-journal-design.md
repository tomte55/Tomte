# Dungeon Journal (Forever) - design

2026-11-15. Status: draft for the user's approval.

## Intent

On World of Warcraft: Forever there's no Adventure Guide. Players lean on ExehnTV's DungeonJournal addon (about 13M
downloads) to answer three questions before and during a run: which quests belong to this dungeon (and which can I
take), which bosses are in it, and what they drop. The user wants that inside Tomte, so it's one addon fewer (see the
addon absorption roadmap). The main thing is quests, bosses and loot; the reference is DungeonJournal's dungeon page
with its Quests and Bosses views.

## Goals

- A **Dungeons** page in the Tomte window listing every Forever dungeon (and raid), each with its level range and the
  number of quests for your side.
- Opening one shows a header (name, level range) and two tabs:
  - **Quests**: the dungeon's quests, filtered to your side by default (a toggle shows the other side's). Each row:
    title, "Available from level N", state (you have it / done / too low / other side). The detail pane: objective,
    who starts it and where (with a Show on map button), where it's handed in, the quest it follows from, and the
    rewards (choose-one items and always-given items) as item buttons.
  - **Bosses**: the bosses in kill order with a small 3D portrait; the detail pane lists the boss's loot as item rows
    (icon, name in quality color, slot and armor/weapon type), plus the dungeon's trash drops as a last entry.
- Item rows behave like items everywhere: tooltip on hover, shift-click links to chat, ctrl-click tries it on. A green
  tick on items you own and on quests you've done; an upgrade mark when Gear & loot's upgrade check says so.
- Search across dungeon, boss, quest and item names.
- Opens from `/tomte dj`, a key binding, and an optional minimap button (off by default).
- Forever only. Retail has Blizzard's Adventure Guide.

## Non-goals (first version)

- Dungeon maps. Most Forever dungeons have no Blizzard map at all (Hall of Thanes has no UiMap); DungeonJournal's
  parchment maps are its own art. A possible later step, as separate art work.
- Boss abilities and strategies, the in-dungeon tracker, DungeonJournal's "RPG mode", favourites, a Report button,
  a language picker.
- Quest sharing, auto-accept, or anything that acts on quests.

## Anti-goals

- Copying DungeonJournal's code, text or look. It's All Rights Reserved. Tomte's page uses Tomte's theme and widgets.
- Tainting the world map: Show on map must never open Blizzard's map from code or set super-tracking (memories
  "never open map from code", "quest follow taint").
- A slow login or a heavy load on retail: the data only loads on Forever.

## Constraints

- **Data has to be ours to ship.** Blizzard's journal API is empty on Forever (`EJ_GetEncounterInfo(3493)` returned
  nothing in game). QuestieDB's Forever data has none of the new dungeons. AllTheThings (MIT) has a file per Forever
  dungeon and raid under `.contrib/.db/forever/dungeons & raids/` with quests (ID, giver, coords, level, races,
  prerequisite quest, objectives, reward items), bosses (encounter ID, creature ID, drops in order) and trash drops,
  updated daily. Credit it in the generated file and README.
- Names, icons, item slots and quest titles come from the client where it has them (player's language); the data
  carries English names only as a fallback while the client loads them.
- Forever's API: `C_QuestLog.IsQuestFlaggedCompleted`, `C_QuestLog.GetLogIndexForQuestID`, `C_Item.*` (async item
  loading), `C_EncounterJournal.GetDungeonEntrancesForMap` exists. Check each on warcraft.wiki.gg and the
  `forever` branch of Gethe/wow-ui-source before use.
- Another session is changing `Tomte.toc`, `tools/forever_list.lua`, `Modules/QuestList/*`, `Core/MinimapData.lua`,
  `Bindings.xml` and building `Modules/Map/` (a Forever world map). Coordinate before touching the TOC, forever_list
  and Bindings.xml.

## Approaches

1. **A page in the Tomte window** (chosen by the user). Dungeons is a `home` entry of kind `page`; the dungeon view
   uses tabs inside the page. Gets themes, search box, widgets and Forever's side rail for free; can be opened from
   other modules (the Map session's dungeon entrance pins, later).
2. A standalone window like DungeonJournal's. Closer to what players know, but rebuilds a window, tabs, search and
   theming the Tomte window already has. Not chosen.

Data source: AllTheThings, through a generator (the only source that has the new dungeons and is licensed for it).
Hand-kept data and QuestieDB were ruled out.

## Shape

- `tools/journal.py`: reads ATT's Forever dungeon and raid files (pinned commit, like questends.py) and writes
  `Data/Forever/Journal.lua` through `ns.Content_Register(ns.CONTENT_FOREVER, "journal", ...)`: per instance its
  instance ID, area ID, English name, level range, kind (dungeon/raid), quests and bosses as above. Generated, never
  hand-edited.
- `Modules/Journal/`: `Data.lua` (pure: sorting, side filter, quest state rules, search matching; tested in
  `tests/test_journal.lua`), a reader for quest and item state, `Page.lua` (the list and dungeon view), and
  `Journal.lua` (registers the module: `category = "quests"`, Forever only, `minimapButton` with
  `shownByDefault = false`, `/tomte dj`, a binding).
- Show on map goes through what exists: `ns.MapTabs_Opener` / the quest list's map look, or the Map session's
  world map once it lands.

## Calls made after the builder check (the user can overrule)

- **Bosses.** ATT marks bosses as encounters (`e(...)`) only in newer files (Hall of Thanes, Blackrock Spire); older
  ones (Deadmines, Scarlet Monastery) list bosses, rares and trash with loot alike as NPC groups. Rule: encounters
  where ATT has them; otherwise NPC groups whose creature is boss rank (rank 3) in the pfQuest/QuestieDB unit data
  Tomte already generates from. Rares and trash with loot go together in a last "Rares and trash" entry. Order is
  ATT's file order, fixed by a small kill-order override table in `tools/journal.py` where it's wrong (Cookie after
  VanCleef). That table is our own data, kept short.
- **Wings.** One row per instance in the list; Scarlet Monastery, Dire Maul and Blackrock Spire show wing sections
  inside the Quests and Bosses tabs, each with its own level. The list row shows the lowest to highest level.
- **Level range.** ATT gives a minimum only. Show `min-max` taking the max from `Data/Forever/Dungeons.lua` where the
  dungeon matches; otherwise "Level N+".
- **Hand-ins.** ATT has no turn-in data, and QuestieDB has none for the new dungeons. Show "Turn in" from
  `Data/Forever/QuestEnds.lua` where it has the quest and leave the line out otherwise; regenerating from newer
  QuestieDB data fills it in as Questie adds it. No hand-kept hand-ins.
- **Unreleased and non-dungeon content.** Follow ATT: skip blocks it comments out (Molten Core, Naxxramas today) and
  empty stubs; leave out the zone files (City of Dalaran, Ruins of Lordaeron, Excavation Site) and the "dungeon
  sets" / "world bosses" files.
- **Upgrade mark** through `ns.Gear_Verdict` (exists on Forever), asked via `ns.HomeCall` so Journal works with Gear
  & loot off.
- **The other session's files.** Build `tools/journal.py`, `Data/Forever/Journal.lua`, `Modules/Journal/` and the
  test first; add the TOC, forever_list and Bindings.xml lines as the last step, after checking with the Map session
  (their edits there are uncommitted). Show on map targets the Tomte world map if it has landed by then, else the
  quest list's map look.

## Left to the builder

Row and pane layout within the Tomte page style; how the quest state reads cached quest data; portrait framing; how
search ranks; where raids sit in the list (my call: a second group under the dungeons); how missing client data
(an item not yet cached) shows while it loads.
