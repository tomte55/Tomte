# Tomte Waypoints (replaces WaypointUI)

Date: 2026-10-03. Status: approved in chat (approach A, structure section); the rest was delegated ("implement it all,
come back when done"), so the decisions below were made without a per-section check-in.

## Why

Third step of moving third-party addons into Tomte (after Gear Check and Almost Done). WaypointUI 1.7.3 is ~12k
lines with its own settings UI, locales, libs and bridges to TomTom/Dugi/APR/SilverDragon. The user runs it at
defaults except **meters instead of yards**, and uses five things:

1. The in-world marker (beam + icon) for quests and map pins
2. Distance and arrival time under it
3. The close-up label (name + objective) near the target
4. The edge arrow when the target is off-screen
5. Click the map to place a pin and it gets tracked right away

Not wanted: pathfinding (Mapzeroth), custom `/way` pins, sounds, custom colors, addon bridges, chat-link pins,
guard guide pins.

## What it does

A **Waypoints** module (key `way`, category Travel) in `Tomte/Modules/Travel/`.

- **Marker** for whatever is super-tracked (quest, user pin, area POI / taxi / dig site / housing plot pin,
  vignette, corpse): a gold diamond with the target's icon, an optional beam rising from behind it, and a footer
  (name on the first line, then distance and arrival time). Its size shrinks gently with distance.
- **Close-up card**: inside the card distance (default 110 yd, about 100 m) the diamond and footer give way to a dark/gold
  card: icon, name, objective text (quest objectives, "Ready for turn-in" text, POI description) and distance.
  Classic style shows the full card; Minimal shows a compact one (name + distance).
  Targets with nothing to describe (map pins you place, taxi nodes without a description) keep the far marker
  all the way in; the card would only repeat the name.
- **Hidden** when closer than the hide distance (default 25 yd) and while inside the tracked quest's area
  (the quest blob), like WaypointUI; the quest objective tracker and blob take over there.
- **Edge arrow**: when the target is off-screen, a gold arrow (with the icon) on an ellipse around the screen
  center, pointing toward it. Turns smoothly.
- **Redirect**: when Blizzard routes through a step (`C_SuperTrack.GetNextWaypointForMap` returns a description,
  e.g. "Take the portal to Dornogal"), that text replaces the name.
- **Auto-track placed pins**: on `USER_WAYPOINT_UPDATED` with a pin present, super-track it next frame.
- **Blizzard's marker** (`SuperTrackedFrame`) is hidden while the module is active and shown again when it's
  turned off.

### Style presets

A Style dropdown sets these keys; each stays editable afterwards.

| Key | Classic | Minimal |
| --- | --- | --- |
| beam | on | off |
| footer | distance, arrival and name | distance |
| card | on (full) | on (compact) |
| arrow | on | on |
| scale | 1.0 | 0.85 |

### Settings (panel)

- Look: Style, Marker size, Opacity, Beam, Beam opacity, Footer
- Close-up: Close-up card, Card distance, Hide when closer than
- Edge arrow: Edge arrow, Arrow size
- General: Use meters (default **on**, matching the user's WaypointUI setting), Auto-track placed map pins,
  Show when the UI is hidden (Alt+Z)

Distances are stored in yards; sliders show them in the chosen unit.

### Commands

`/tomte way test` drops a user pin a bit ahead of the player and tracks it; `/tomte way clear` stops
tracking (and removes the user pin).

## How it works

- **Anchor**: Blizzard's navigation frame from `C_Navigation.GetFrame()` (recreated on `NAVIGATION_FRAME_CREATED`,
  gone on `NAVIGATION_FRAME_DESTROYED`) moves on screen with the target. The far marker and the card are anchored
  to it with `SetPoint` (copying `GetCenter` each update lagged a frame behind camera turns); only the edge arrow
  computes a position from its center. We never parent to or modify it. Distance from `C_Navigation.GetDistance()`.
  Off-screen: `C_Navigation.WasClampedToScreen()`.
- **Parent**: UIParent, or WorldFrame when "show when the UI is hidden" is on (scaled to match UIParent). The
  cinematic engine already hides foreign WorldFrame children, so the marker disappears during Tomte cinematics.
- **Update loop**: an OnUpdate frame that only runs while something is tracked and the navigation frame exists.
  Position every frame (it has to follow the camera); distance, state and text throttled to 0.1 s; target info
  (name, icon, objective) refreshed on `SUPER_TRACKING_CHANGED`, `SUPER_TRACKING_PATH_UPDATED`,
  `QUEST_LOG_UPDATE`, `USER_WAYPOINT_UPDATED`, `ZONE_CHANGED*` and `PLAYER_ENTERING_WORLD`.
- **Arrival time**: exponential moving average of the closing speed (pure, in `Data.lua`); no time when standing
  still or moving away. Reset when the target changes. Flight Timer's data isn't used: it times taxi routes,
  not free movement.
- **Combat / restrictions**: the navigation and super-track APIs are not combat-secret; nothing here is
  protected. The marker keeps working in combat; there is no combat-only behavior.
- **Coexistence**: `blocked` while WaypointUI is loaded ("disable it and /reload to switch over"). Both drawing
  markers and hiding Blizzard's would fight.

## Files

| File | Job |
| --- | --- |
| `Modules/Travel/Data.lua` | Pure logic (tested in `tests/test_travel.lua`): distance/arrival text, state, scale, edge arrow math, style presets |
| `Modules/Travel/Target.lua` | What is tracked: type, name, icon (atlas or texture), objective lines, quest area, redirect text |
| `Modules/Travel/Marker.lua` | Frames: diamond, beam, footer, card, edge arrow; `ns.WayMarker_*` |
| `Modules/Travel/Waypoint.lua` | Module registration, events, update loop, Blizzard marker hiding, auto-track, options, commands |

## Out of scope

Pathfinding, `/way` and custom pin lists, sounds, colors per quest type, TomTom and other bridges, chat-link and
guide pins, "is a taxi faster" (possible later idea using Flight Timer's data).
