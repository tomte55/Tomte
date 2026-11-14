# Quest Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Quest list's and Next quests' follow takes the first stop of a planned route over every quest's objective
and hand-in, instead of the nearest stop.

**Architecture:** A generator writes each Forever quest's hand-in spot (Data/Forever/QuestEnds.lua, from QuestieDB). A
pure planner (Modules/Leveling/RouteData.lua) orders "do" and "hand in" stops with objective-before-hand-in and
anti-flip. A game-side file (Modules/Leveling/Route.lua) turns quests, points and hand-ins into planner input and
answers "which quest to follow"; QuestList.lua and NextQuests.lua call it.

**Tech Stack:** Python 3 generator (tools/), WoW Lua 5.1, plain-Lua tests.

**Spec:** `docs/superpowers/specs/2026-11-14-tomte-quest-route-design.md`

## Global Constraints

- Forever only. Generated files are never hand-edited; CRLF; Edit/Write tools for Lua.
- Only quests in your log are planned (so no race/class/faction filtering of finishers is needed).
- Distance is the only cost. Quests on another continent than yours are left out of the plan.
- Anti-flip: keep the stop holding the followed quest first unless a free plan is at least 20% shorter.
- Standing in a quest's area still wins (Leveling_FollowPick), with the route's pick as its fallback.
- No work while the list / widget is hidden; nothing changes the game's super-tracked quest.

## Review Focus

- A finished quest (hand-in only) and an unfinished one handing in at the same NPC: one hand-in stop, after the
  unfinished one's objective (test in Task 2).
- A quest without hand-in data: an objective stop only, never blocks a hand-in stop (test in Task 2).
- Hand-in on another continent / map unknown: dropped, the quest still has its objective stop (Task 3).
- 2-opt never moves a hand-in before its objective (test in Task 2).
- Followed quest no longer in the plan (turned in): the free plan is used (test in Task 2).

---

### Task 1: Hand-in data

**Files:** Create `tools/questends.py`, generated `Data/Forever/QuestEnds.lua`; modify `tools/forever_list.lua`
(after QuestItems.lua), README Credits line (QuestieDB already credited: extend its text).

- Reads foreverQuestDB.lua (finishedBy = field 3: `{{npcIDs},{objectIDs}}`), foreverNpcDB.lua (spawns = 7, zoneID = 9),
  foreverObjectDB.lua (spawns = 4, zoneID = 5) with the Parser from questitems.py (import it).
- Spot of a finisher: its zoneID's first spawn, else the first zone's first spawn. First NPC finisher, else first
  object. Quests without a spot are left out.
- Output: `ns.Content_Register(ns.CONTENT_FOREVER, "questEnds", { [questID] = "areaID:x:y", ... })`, x/y in percent
  as %g.
- [ ] Run it, check 9267 = "17:61.21:37.85" (Mupsi Shacklefridd, The Barrens), forevertoc + bugfiles.

### Task 2: Planner (pure)

**Files:** Create `Modules/Leveling/RouteData.lua` (after Leveling/Data.lua), test `tests/test_questroute.lua`.

**Interfaces — Produces:**
- `ns.Route_Plan(you, quests, followedID, mergeYards) -> stops`
  - you: `{ x, y }` (world yards, your continent); quests: `{ { questID, complete, point = {x,y} | nil, hand = {x,y} | nil } }`
    (caller already filtered to your continent).
  - Stops: `{ { kind = "do" | "hand", x, y, quests = { questID, ... } } }` in route order. A complete quest has only
    a hand stop (its point is the game's turn-in spot; `hand` falls back to `point`). An unfinished quest has a do stop
    at `point` and, with `hand`, a hand stop. Hand stops within mergeYards of each other merge (first one's spot).
  - Order: nearest feasible next from `you`; then 2-opt keeping only reversals that leave every quest's do before its
    hand. Anti-flip: if followedID is in a stop, also plan with that stop forced first; use the forced plan unless the
    free plan's length (from you) is under 80% of it.
- `ns.Route_Length(you, stops) -> yards`.
- Tests: precedence (Agamand example: you north, west quest hands in at Brill, five complete at Brill → first stop is
  the west quest's do stop); complete-only quests merge into one hand stop; no-hand quest → do stop only; 2-opt keeps
  precedence on a crossing layout; anti-flip keeps the followed stop first unless 20% shorter; followed quest absent
  → free plan; empty input → {}.

### Task 3: Game side

**Files:** Create `Modules/Leveling/Route.lua` (after Read.lua); modify `Core/Core.lua` (shared `ns.MapForArea`),
`Modules/Sources/Sources.lua` (use it), `Modules/Leveling/Data.lua` (export `ns.Leveling_OnStop(q, grouped)`).

**Interfaces — Produces:**
- `ns.MapForArea(areaID, englishName) -> uiMapID | nil` (Core; Sources' zone-map lookup moved here verbatim).
- `ns.LevelingRoute_Pick(quests, points, you, grouped, followedID) -> questRow | nil, stops` — filters quests with
  Leveling_OnStop, builds planner input from `points` (Read's QuestPoints, same continent as you) and hand-ins
  (questEnds → MapForArea → world point, cached per quest), returns the first stop's top quest (do: its quest; hand:
  the first of its quests in your log order) and the plan.
- [ ] QuestList.lua: follow fallback becomes `LevelingRoute_Pick(listed quests (sections, not "hidden"), points, you,
  IsInGroup(), followed)` in every grouping (points read in every mode), still through Leveling_FollowPick; option
  label "Follow quests along a route" + tooltip; `/tomte questlist why` prints the plan (stop, kind, quests, yards).
- [ ] NextQuests.lua: same for its follow (its own quest set); option label alike.
- [ ] TOC/forever_list, forevertoc, bugfiles, luac global check, all tests.

### Task 4: Docs

- [ ] README Quest list / Leveling rows; CHANGELOG once confirmed in game.
