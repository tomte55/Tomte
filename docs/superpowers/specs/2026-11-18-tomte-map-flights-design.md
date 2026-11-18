# Tomte map as the flight map (Forever): design, 2026-11-18

## Why

Blizzard's flight map on Forever is a bare continent picture with flight masters and no quests. The user looks at a
map first to see where their quests are, then opens the flight master and has to remember. Picking a flight on the
Tomte map, with the quests, zones and the followed quest right there, removes that back and forth.

## Goals

- Talking to a flight master opens the Tomte map in a flight mode instead of Blizzard's flight map.
- The places you can fly to from here show as flight pins; hovering one shows the route (each hop as a line), the
  flight time (Flight module's data) and the cost; a click flies there.
- Everything the Tomte map already shows stays: your quests (the followed one with its area), zones up close, you.
- The flight master nearest the followed quest is marked, so the answer to "where do I fly" is on the map.

## Non-goals

- No change to flying itself, the Flight timer bar or the flight cinematic (Flight module).
- Not on retail (the Tomte map is Forever only).
- No taxi pathfinding of our own: the game's routes (`GetNumRoutes`, `TaxiGetNodeSlot`) are the truth.

## Anti-goals

- Never hide, move or show Blizzard's flight map from code (UI panels shown or hidden from addon code taint; see the
  project's map notes). It's muted instead, and stays the thing the game opens and closes.
- Never a flight without a click (`TakeTaxiNode` only from a pin's OnClick).
- Never stuck: leaving the flight master, Esc or closing our window always ends both windows, and the game's flight
  map comes back whenever the Tomte map module or this setting is off.

## Constraints (checked in Forever's UI source, branch "forever")

- `FlightMapFrame` is a centre UI panel (`UIPanelWindows`, `showFailedFunc = CloseTaxiMap`); it unregisters nothing
  we need and hides on `TAXIMAP_CLOSED`.
- Blizzard's own flight pin calls `TakeTaxiNode(slotIndex)` from plain Lua in OnClick: not protected.
- `C_TaxiMap.GetAllTaxiNodes(mapID)` gives each node's `slotIndex`, `state` (Current, Reachable, Unreachable),
  `position` and `name`; `TaxiNodeCost(slot)`, `GetNumRoutes(slot)`, `TaxiGetNodeSlot(slot, hop, source)`.
- Events: `TAXIMAP_OPENED`, `TAXIMAP_CLOSED`.

## Approaches

1. **Instead of Blizzard's (picked by the user).** On `TAXIMAP_OPENED` the Tomte map opens in flight mode; Blizzard's
   flight map, which the game still opens, is muted (alpha 0, no mouse). Everything is chosen on the Tomte map.
2. **Beside Blizzard's.** Both windows open; choosing still happens in Blizzard's. Safer, but takes the screen and
   keeps the bare map as the place you click. Not picked.
3. **Quests drawn onto Blizzard's flight map.** Adding pins to `FlightMapFrame` (its canvas data providers) touches
   Blizzard's map code, which the project avoids on Forever (taint), and keeps its lack of detail. Dropped.

## Design

- **Setting** in the Tomte map's settings: "Use the Tomte map at flight masters" (default on; the Tomte map module
  itself is off by default). Off, or the module off: Blizzard's flight map as before, unmuted.
- **Opening**: on `TAXIMAP_OPENED` (taxi, not other systems) the Tomte map window opens (or switches, if already
  open) in flight mode, framed on your continent's flight pins with you in view. Blizzard's `FlightMapFrame` is
  muted once it's loaded and shown: alpha 0 and mouse off on the frame and its canvas. How exactly it's made
  invisible and unclickable is measured in game; if its pins still catch the mouse, the next step is a tiny scale.
  Never `Hide()`.
- **Flight pins** (flight mode only, over the normal taxi pins, which hide meanwhile): Reachable nodes as the game's
  flight master icon, Current as you are here, Unreachable faded and not clickable. Hover: the route as lines from
  here through each hop, and a tooltip with the name, the flight time (Flight module's known times, or "not flown
  yet") and the cost (`ns.Price`). Click: `TakeTaxiNode(slotIndex)`.
- **Nearest to your quest**: the reachable node closest to the followed quest's spot gets a ring in the accent colour
  and a tooltip line ("Nearest to <quest>").
- **Closing**: our window closing (button, Esc, map key) calls `CloseTaxiMap()`; `TAXIMAP_CLOSED` (walked away, flew,
  Esc on the muted frame) ends flight mode and closes our window if flight mode opened it. Blizzard's frame is
  unmuted on `TAXIMAP_CLOSED` and whenever the setting or module turns off.
- **Files**: flight mode in a new `Modules/Map/Flights.lua` (reading nodes and routes, the mute, the pins and lines),
  pure parts (nearest node, route hops to line segments, framing box) in `Modules/Map/Data.lua` with tests; the
  window learns a flight mode (title "Flight Map", framing) in Window.lua; Map.lua registers the events and setting.
  The Flight module is asked for times through an `ns.Flight_*` function, never its db.

## Left to the builder

- The framing zoom (all reachable nodes of the continent in view, margin as Find me uses).
- Line look (thickness, accent colour, alpha) and the Unreachable alpha.
- Whether the Flight module's MapCoverage strip and tooltip extras have a place on our map (later, not in v1).
