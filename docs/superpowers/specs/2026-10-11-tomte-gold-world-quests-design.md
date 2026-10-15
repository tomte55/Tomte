# Gold world quests (module `wgq`)

A friend uses GoldWQ (one window: gold world quests across the expansion's zones with totals, special assignments,
weekly caches, a TomTom route, weekly gold per character and an alt view). The user asked for the same window and
functionality in Tomte, Tomte-flavoured. Decisions below were made by Claude (delegated); the user tests in game.

GoldWQ is public domain (its CurseForge license; corrected 2026-10-15: this spec first said it had none). Its window,
special assignment and route logic were the reference. Its game IDs are facts: the cache item IDs come from it. Special
assignment quest/unlock pairs and weekly cache quests come from WeeklyRewards (MIT), the 11.0 Khaz Algar special
assignment quest IDs from Plumber (GPLv3, IDs only).

## Follows the player's expansion

GoldWQ hardcodes six Midnight zones. Tomte reads `goldZones`, `assignments` and `caches` from
`Data/<Expansion>/Gold.lua` for `ns.ContentExpansion()` (The War Within: Khaz Algar zones incl. Undermine, Siren Isle,
K'aresh; Midnight: Quel'Thalas zones as in GoldWQ). Map IDs checked against UiMap on wago.tools (build 69933).

## Window

A themed standalone window (`UI.Panel`), movable by its title, resizable (grip), foldable to its title bar, scale and
opacity settings, position and size saved. Not closed by Esc (it's a tracker window, like GoldWQ). Opens with
`/tomte wgq`, a key binding, the Home quick action, or at login (setting, off by default).

Title bar: "Gold world quests", the total ("14 quests · 3,250g"), buttons Route / Characters / settings / fold / close.

Gold view, three folding sections:

1. **Gold world quests**: every world quest that gives gold in the expansion's zones (reusing World quests' scan and
   reward cache, `ns.WQ_ForZones`), grouped by zone (richest zone first) with a zone line "Hallowfall · 4 · 1,820g",
   rows richest first: gold, title, time left. Click tracks it (Waypoints shows it), right-click opens the map on its
   zone, shift-click links it. Route stop numbers in front while a route runs.
2. **Special assignments**: per zone the best state: Done / Up (with time left, click tracks) / Locked (with the
   unlock quest's progress, e.g. 2/3 world quests). From the data pairs (quest + unlock quest); generic fallback:
   any scanned world quest tagged Capstone (Enum.QuestTagType.Capstone) is Up, and a locked capstone area POI
   (atlas containing "Capstone") on a zone map is Locked.
3. **Weekly caches**: each weekly source (quest or quest pool) Done / Not done for this character, labeled by the
   cache item's name (or the quest's). Done = flagged complete or turned in this week (own log, as GoldWQ: some
   flags never clear). Right-click hides a row; a setting brings hidden ones back.

Characters view: each character seen with this module: level, gold from world quests this week and in total, caches
done this week (x/y), click to unfold the cache list. Weekly numbers roll over at the weekly reset without logging in
(stored next reset time).

## Route

Route button: orders the gold quests with positions (world coordinates via `C_Map.GetWorldPosFromMapPos`): the
player's continent first, nearest-neighbour from where you stand then 2-opt; other continents after, each from its
richest quest. Tomte's own tracking (`ns.WQ_Track`, Waypoints marker), no TomTom. Turning in the tracked stop tracks
the next one still up and says so in chat; Stop route clears it.

## Gold tally and login line

QUEST_TURNED_IN with money for a world quest adds to this character's week and lifetime totals and prints "+250g"
(setting). Login: once the scan has loaded (or after a minute), one chat line "Gold world quests: 14 up, 3,250g"
(setting, on).

## Home

A quick action "Gold world quests" with the count of gold quests up (from the last scan) that opens the window.

## Pure logic (tests/test_gold.lua)

Grouping and totals, route order, special assignment state and best-per-zone, cache done-ness, weekly rollover of a
character record, chat summary.

## As built (after the user's in-game feedback, 2026-10-11)

- The window uses the subtle widget panel (no border, 55% background) and the small spaced title, like the Crafting
  list and Almost Done. It reopens after a reload if it was open (no separate open-on-login setting).
- Command `/tomte wgq` (module key `wgq`): "gold" was too general.
- An expansion menu (session only) shows Legion to Dragonflight gold quests too (`Data/Older/Gold.lua`, zones only).
- The route moved to Modules/WorldQuests/Route.lua (order: RouteOrder.lua) and is shared with a Route button in the
  World quests map tab; one route at a time.
