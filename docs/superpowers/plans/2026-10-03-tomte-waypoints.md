# Waypoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module that replaces WaypointUI: in-world marker, close-up card, edge arrow and auto-tracked map
pins, in Tomte's dark/gold style with Classic/Minimal presets.

**Architecture:** Pure logic in `Data.lua` (unit-tested). `Target.lua` turns the super-track state into
`{ kind, name, icon, lines, questID, redirect }`. `Marker.lua` owns the frames and takes screen-pixel positions.
`Waypoint.lua` registers the module, follows `C_Navigation.GetFrame()` and drives the marker.

**Tech Stack:** WoW retail 12.1 Lua, `C_Navigation`, `C_SuperTrack`, `C_Map` user waypoints, `QuestUtil` icon
helpers, Tomte's `ns.UI` and options schema.

**Spec:** `docs/superpowers/specs/2026-10-03-tomte-waypoints-design.md`

## Global Constraints

- TOC `## Interface: 120100`. Load order: Data → Target → Marker → Waypoint, after Flight.
- `local addonName, ns = ...` in every file. No globals.
- Module key `way`, db `TomteDB.way`, category "Travel", name "Waypoints". Default on.
- Blocked while `C_AddOns.IsAddOnLoaded("WaypointUI")`; WaypointUI in `OptionalDeps` so the check sees it.
- `C_Navigation.GetNextWaypointForMap` (12.1.0), not the deprecated `C_SuperTrack` alias.
- Distances stored in yards; `metric` defaults to true.
- No commit until the user confirms in game (CLAUDE.md).
- Tests: `lua Tomte/tests/test_travel.lua` from the AddOns folder.

## Review Focus

1. Navigation frame destroyed and recreated (zoning, tracking cleared): the ticker stops and restarts, no nil
   `GetCenter` errors. In-game check.
2. Off-screen and behind the camera: the arrow points the right way and turns the short way round across ±π.
   `TurnToward` test in Task 1.
3. Standing still or moving away: no arrival time instead of a huge or negative one. `UpdateArrival` tests.
4. Turning the module off gives Blizzard's marker back; turning it on hides it again without `/reload`. In-game check.
5. Distance thousands and km formatting (1,240 yd / 1.4 km). `FormatDistance` tests.

---

### Task 1: Data.lua + tests

**Files:** Create `Tomte/Modules/Travel/Data.lua`, `Tomte/tests/test_travel.lua`

**Produces:** `ns.Way_FormatDistance(yards, metric)`, `ns.Way_FormatSetting(yards, metric)`,
`ns.Way_FormatArrival(seconds)`, `ns.Way_NewArrival()`, `ns.Way_UpdateArrival(state, distance, now) -> seconds|nil`,
`ns.Way_FooterText(mode, distanceText, arrivalText, name)`, `ns.Way_State(info, opts) -> "none"|"hidden"|"offscreen"|"card"|"far"`,
`ns.Way_DistanceScale(distance)`, `ns.Way_EdgePoint(dx, dy, rx, ry) -> x, y, rotation`,
`ns.Way_TurnToward(current, target, rate)`, `ns.Way_ApplyStyle(db, style)`, `ns.WAY_STYLES`, `ns.WAY_FOOTERS`.

- [x] Write the tests (formatting, arrival smoothing, footer modes, state priority, scale clamp, edge point, styles)
- [x] Run: fails (no file)
- [x] Implement Data.lua
- [x] Run: `lua Tomte/tests/test_travel.lua` → all passed

### Task 2: Target.lua

**Files:** Create `Tomte/Modules/Travel/Target.lua`

**Produces:** `ns.WayTarget_Get() -> target|nil`, `ns.WayTarget_InQuestArea(target) -> bool`.

- [x] Quest: title, `QuestUtil.GetQuestIconActiveForQuestID` (world quests: `GetWorldQuestAtlasInfo`), unfinished
      objectives or the turn-in text
- [x] User waypoint (map name + coords), corpse, map pins (AreaPOI info, quest offer, taxi, dig site, housing plot),
      vignette; fallback `C_SuperTrack.GetSuperTrackedItemName`
- [x] Redirect step from `C_Navigation.GetNextWaypointForMap` leads the card lines
- [x] `luac -p` clean, no global writes

### Task 3: Marker.lua

**Files:** Create `Tomte/Modules/Travel/Marker.lua`

**Produces:** `ns.WayMarker_Apply(db)`, `ns.WayMarker_SetTarget(target)`, `ns.WayMarker_SetAlpha(a)`,
`ns.WayMarker_Hide()`, `ns.WayMarker_NavPoint(navFrame) -> sx, sy|nil`,
`ns.WayMarker_Show(state, sx, sy, footer, distanceText, scale)`.

- [x] Holder on UIParent or WorldFrame (scaled to UIParent), BACKGROUND strata
- [x] Far view (diamond, icon, beam, footer), card (full/compact), edge arrow (diamond + orbiting chevron)
- [x] Positions converted from screen pixels by each view's effective scale

### Task 4: Waypoint.lua, TOC, README

**Files:** Create `Tomte/Modules/Travel/Waypoint.lua`; modify `Tomte/Tomte.toc`, `README.md`

- [x] Events → dirty target; ticker only while a navigation frame exists; info every 0.1 s, position every frame
- [x] Hide `SuperTrackedFrame` via `Show`/`SetShown` hooks while active; `Show()` it again on disable
- [x] Auto-track on `USER_WAYPOINT_UPDATED` (next frame; ignored for 3 s after a loading screen)
- [x] Options (Look / Close up / Edge arrow / General), style dropdown applies preset and rebuilds the page
- [x] Commands `test`, `clear`
- [x] All test files pass

### Task 5: In-game check (user)

See the checklist in the hand-off message. Commit after confirmation.
