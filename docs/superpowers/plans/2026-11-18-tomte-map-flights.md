# Tomte map as the flight map: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At a flight master on Forever, the Tomte map opens in flight mode instead of Blizzard's flight map: flight
pins you click to fly, routes on hover, your quests on the same map.

**Architecture:** A new `Modules/Map/Flights.lua` owns flight mode: it reads the taxi nodes when the flight master
opens, mutes Blizzard's `FlightMapFrame`, draws its own pins and route lines on the Tomte map's pin layer, and ends
everything on `TAXIMAP_CLOSED`. Pure geometry goes in `Modules/Map/Data.lua`. Map.lua registers the two taxi events
while the module is on; Window.lua lays flight pins out with the rest and closes the flight master when it hides.

**Tech Stack:** WoW Forever 1.60.1 Lua, plain-Lua tests (`tests/harness.lua`, Lua 5.1 in CI).

**Spec:** `docs/superpowers/specs/2026-11-18-tomte-map-flights-design.md`

## Global Constraints

- Never `Hide()`, `Show()` or move `FlightMapFrame` from our code: mute it (alpha 0, scale 0.001) and put both back.
- `TakeTaxiNode` only from a pin's OnClick.
- Nothing taints: no calls into Blizzard's map canvas, no hooks that act while the module or setting is off.
- Setting key `flights` (default `true`), label "Use the Tomte map at flight masters".
- Theme colors by role only (`UI.Color("accent")`), money through `ns.Price`.

## Review Focus

- The flight master closes while our window is open (walking away, Esc on the muted frame): our window must close if
  flight mode opened it, and Blizzard's frame must be unmuted.
- Our window closed by the player: `CloseTaxiMap()` so the game ends the flight master conversation.
- The setting or the module turned off while at a flight master: Blizzard's frame unmuted and shown as normal.
- A node with no route (`GetNumRoutes` 0) or on another map layer: no line, no error.
- The first visit: `Blizzard_FlightMap` not loaded yet when `TAXIMAP_OPENED` fires.

---

### Task 1: Pure geometry

**Files:** Modify `Modules/Map/Data.lua`; Test `tests/test_map.lua`

**Interfaces — Produces:**
- `ns.Map_BoxAround(points, pad) -> box | nil`: points `{ { cx, cy } ... }` in canvas units; box `{ l, t, w, h }`
  grown by `pad` (a share of its size each way, at least 1 unit); nil for no points.
- `ns.Map_Nearest(points, x, y) -> index | nil`: the point nearest x, y (canvas units).

- [ ] Tests "box around flight pins" (two points (10,20),(30,60), pad 0.5: l = 0, t = 0, w = 40, h = 80; one point
  gives a box of at least 2 by 2 around it; `{}` gives nil) and "nearest point" ((0,0),(10,0),(3,4) from (2,3) is 3;
  `{}` gives nil).
- [ ] Implement, run `lua Tomte/tests/test_map.lua`: all passed.

### Task 2: Flight time for a destination

**Files:** Modify `Modules/Flight/Tooltip.lua`

**Interfaces — Produces:** `ns.Flight_TimeText(slot) -> string | nil`: "~4m 10s" style (`ns.FormatTime`, "~" for an
estimate) while the Flight module is on and the taxi map open; nil when unknown or off. `AddTimeLine` uses it.

### Task 3: Flight mode

**Files:** Create `Modules/Map/Flights.lua` (after `Pins.lua` in `tools/forever_list.lua`); Modify
`Modules/Map/Map.lua` (default, option, events), `Modules/Map/Window.lua` (layout call, OnHide, open in flight mode),
`Modules/Map/Pins.lua` (taxi pins hidden in flight mode); regenerate `Tomte_Forever.toc`, `Core/BugFiles.lua`.

**Interfaces:**
- Consumes: Task 1, Task 2, `ns.MapArt_ToCanvas`, `ns.ActiveQuest_ID`, `ns.MapPins_QuestSpot`.
- Produces: `ns.MapFlights_Init(layer, db)`, `ns.MapFlights_Opened()`, `ns.MapFlights_Closed()`,
  `ns.MapFlights_Active() -> bool`, `ns.MapFlights_Layout(toView, toViewAll)`, `ns.MapFlights_WindowHidden()`,
  `ns.MapFlights_Stop()`; Window: `ns.MapWindow_OpenFlights(box) -> bool` (opens if needed, aims at box; returns
  whether it opened the window).

- [ ] `Opened` (TAXIMAP_OPENED while module and setting on): read `GetTaxiMapID()` and
  `C_TaxiMap.GetAllTaxiNodes(mapID)` into nodes `{ slot, name, state, mapID, x, y, cx, cy }`, mute Blizzard's frame
  (hook its OnShow once it exists; the hook mutes only while flight mode is on), open the window framed on the
  reachable and current nodes (`Map_BoxAround`, pad 0.15), mark the nearest reachable node to the followed quest.
- [ ] Pins: Current `Taxi_Frame_Green`, Reachable `Taxi_Frame_Gray` (`Taxi_Frame_Yellow` while hovered), Unreachable
  gray at alpha 0.35, no click. Tooltip: name, "You are here" (`TAXINODEYOUAREHERE`) / cost (`ns.Price`) and time
  (`ns.Flight_TimeText`) / `TAXI_PATH_UNREACHABLE`; nearest: "Nearest to <quest title>" in accent. Click: `TakeTaxiNode`.
- [ ] Hover: route lines through each hop (`GetNumRoutes`, `TaxiGetNodeSlot(slot, hop, true/false)`), accent, 3 px.
- [ ] `Closed` / `Stop` / window hidden: unmute, hide pins and lines, close the window if flight mode opened it;
  `WindowHidden` calls `CloseTaxiMap()` while the taxi map is open.
- [ ] Tests, `luac -l` global check, forevertoc and bugfiles regenerated; in game by the user.
