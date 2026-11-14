# Quest route: plan the follow ahead, with hand-ins (design)

Date: 2026-11-14. World of Warcraft: Forever only (Quest list, Leveling's Next quests).

## Why

The Quest list's follow (and Next quests' when the list is off) points at the top quest of the nearest stop, or at a
quest whose area you stand in (ns.Leveling_FollowPick). It doesn't know where a quest is handed in until the quest is
finished, so it zigzags. Seen in Tirisfal: five quests ready to hand in at Brill, you near Agamand Mills, and the arrow
sends you to a quest to the west first. If that west quest also hands in at Brill, doing it first and then handing in
all six is the sensible trip; if it doesn't, Brill first may be. The user wants the follow to plan ahead "like a
travelling salesman, with the info on where a quest will be turned in", so routes get far more effective.

## Goals

- Every quest in the plan contributes up to two places: **where you do it** (its area or pin, as today) and **where you
  hand it in** (the quest's finisher, known ahead from data, before the quest is finished).
- A quest's hand-in comes after its objective in the plan. Hand-ins at the same place are one stop ("Brill: hand in 6").
- The planner orders all stops to walk the least, and the **follow / Waypoints' arrow** takes the plan's first stop.
- The list keeps its look (user's choice A): stops by area, nearest first. Only what's followed changes.

## Non-goals

- The list becomes the route (option B, rejected: it would reshuffle as you move).
- Quest pick-ups (new quests from givers) in the plan. A later step, if wanted.
- Weighing how long an objective takes ("kill 10" vs "talk to"): distance is the only cost for now.
- Retail.

## Anti-goals

- The arrow flips back and forth as you walk (a plan that changes by a few yards must not move the follow).
- The follow taints the game's tracker or map (it stays Tomte's own follow, ns.ActiveQuest_Follow; never the game's
  super-track).
- Data that's wrong for your side: a hand-in NPC of the other faction, or one for another race/class's quest, is never
  routed to.

## How it works

### Data

A generated table (from QuestieDB's Forever data, as `tools/questitems.py` already does for quest items; GPLv3, credited)
gives each quest its finisher's spot: `[questID] = areaID, x, y` (zone percent). Finishers are NPCs or objects (QuestieDB
questKeys `finishedBy`); an NPC with several spawns uses its main spot. Quests the data doesn't know, or whose finisher
has no spot, simply have no hand-in in the plan (they behave as today).

At run time a spot is turned into world yards like Leveling's quest points (`LevelingRead_QuestPoints`: map position →
`C_Map.GetWorldPosFromMapPos`), the area ID to a uiMapID as Sources does (Modules/Sources/Sources.lua `MapFor`).

For a quest that's **finished**, the game's own turn-in point (C_QuestLog.GetQuestsOnMap's point for it, which is where
the `?` is) wins over the data.

### Planner (pure, unit-tested)

Input: where you stand, the quests in the plan (those Next stops would list: same filters as Leveling_NextStops), each
with an objective point (unless finished) and a hand-in point (if known). Output: stops in order.

- Objective points: Leveling_NextStops' grouping (close quests are one stop), as today.
- Hand-in points: quests handed in within the same small radius are one stop.
- Order: nearest feasible stop next, then untangled (2-opt), as `Modules/WorldQuests/RouteOrder.lua` does, with the rule
  that a quest's hand-in stop can't come before the stop holding its objective. A move that breaks the rule is skipped.
- 10 to 25 stops: instant in Lua; recomputed on the existing 2-second tick only when the inputs changed.
- The rule from the area follow stays on top: while you stand in a quest's area, that quest is followed
  (Leveling_FollowPick), and the plan starts from it.

### Following the plan

- The follow takes the first stop's top quest (for a hand-in stop: one of the quests handed in there).
- **No flipping:** the followed stop stays until you reach it, or until a new plan is clearly shorter in total (by
  20% or more). A quest you pick yourself still wins until the plan's first stop changes (as today).
- Waypoints' arrow and the world map mark (QuestList/Map.lua) follow it as today.

### Seeing why

- `/tomte questlist why` (debug) lists the plan: each stop in order with its quests and kind (do / hand in) and the
  total yards, so a bad route can be reported.

## Decided after the builder check (Claude's calls, for the user to check)

- **Which quests are planned.** The Quest list plans the quests it would list: its "Show" setting (all or tracked
  only) and the Hidden line apply, so the arrow never leads to a quest you hid. Next quests plans its own set (what it
  lists today). The planner takes the quest list as input; each module passes its own.
- **Every grouping.** The plan runs whatever "Group by" is set to (stop, zone, nothing): it's about what's followed, not
  how the list is drawn. The move-based re-update moves out of stop mode accordingly; nothing runs while the list is
  hidden.
- **Next quests keeps its look**, like the list (choice A): its header names the nearest stop as now. The followed
  quest is marked as active in it (as it already is), so the arrow's target shows even when it isn't the nearest stop.
- **It replaces the current follow**, no new setting: "Follow the nearest quest" becomes "Follow quests along a
  route" (same saved key, no migration), with its tooltip rewritten. Quests without hand-in data fall back to today's
  behaviour inside the plan (an objective stop with no hand-in), so nothing needs the old path kept separately.

## Constraints

- Forever only; quest data from QuestieDB's Forever DB (Forever may differ from Classic: the game's own turn-in point
  wins for finished quests).
- Pure planner in a `*Data.lua` with tests; game reads in a Read file; generated data never edited by hand.
- Leveling/Data.lua is at 896 lines: the planner goes in its own pure file (e.g. `Modules/Leveling/RouteData.lua`),
  and Leveling/Data.lua gets split first if anything else must go there.
- Cost: no work while the list and Next quests are hidden; the plan is cached between ticks.

## Approaches

1. **Whole route (chosen by the user).** Plan every stop with objective-before-hand-in, follow the first stop.
   Handles chains (west quest → Brill → a quest east of Brill that also hands in at Brill).
2. **One step ahead.** Score each candidate next stop by its distance plus the trip to its hand-in. Simpler, misses
   chains and gets five hand-ins at one place wrong.

## Left to the builder

- The generated file's name and format, and whether finisher spots come from QuestieDB's NPC/object data or pfQuest's
  (already used by tools/itemsources.py).
- The hand-in merge radius and the exact "clearly shorter" threshold (start at 20%).
- Where the planner's 2-opt is shared with RouteOrder.lua (a common pure helper) or kept apart.
