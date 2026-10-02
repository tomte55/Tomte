# FlightTimer — Design

Account-wide flight path (taxi) timer. Records how long flights take, shows the expected time on the
flight map tooltip, and shows an in-flight bar that either records (unknown route) or counts down
(known/estimated route).

## Goals

- Show expected flight time when hovering a destination on the flight map.
- While flying: count down if the time is known/estimated, otherwise record (count up).
- Clearly distinct visuals for "recording" vs "countdown".
- Learn per hop, so one flight A→B→C teaches A→B, B→C (and their reverses as estimates).
- Data shared across all characters on the account.

Out of scope: per-character data, statistics, sharing with friends, settings panel.

## APIs (verified)

| API | Use |
|---|---|
| `TakeTaxiNode(slot)` | `hooksecurefunc` — capture destination slot at takeoff |
| `GetTaxiMapID()` | uiMapID of the open taxi map (only valid while the map is open) |
| `C_TaxiMap.GetAllTaxiNodes(uiMapID)` | `TaxiNodeInfo[]`: `nodeID`, `slotIndex`, `position`, `name`, `state` |
| `GetNumRoutes(slot)`, `TaxiGetNodeSlot(slot, hop, isSource)` | Hop list of the route (same as Blizzard's `FM_FlightPathDataProvider.lua`) |
| `UnitOnTaxi("player")` | Flight start/end detection |
| `C_Map.GetPlayerMapPosition(uiMapID, "player")` | Position polling for hop timing (nil in instances — fine) |
| `FlightMap_FlightPointPinMixin:OnMouseEnter` | Hook for modern flight map tooltip (hook on `ADDON_LOADED` of `Blizzard_FlightMap`, before pins exist) |
| `TaxiNodeOnButtonEnter(button)` | Global hook for the legacy taxi frame tooltip |

## Data model

SavedVariables `FlightTimerDB` (account-wide):

```lua
FlightTimerDB = {
  routes = { ["<srcNodeID>><dstNodeID>"] = seconds },  -- full measured routes
  hops   = { ["<aNodeID>><bNodeID>"]     = seconds },  -- per-hop (measured from routes)
  frame  = { point, x, y, locked = true },
}
```

- A route with a single hop also writes `hops` with the same value.
- New measurements overwrite old ones (routes can change between patches).

## Lookup: `ns.GetTime(srcNodeID, path) -> seconds, isEstimate`

`path` is the list of nodeIDs from source to destination.

1. `routes[src>dst]` exists → measured, not an estimate.
2. Else sum each hop: `hops[a>b]`, falling back to `hops[b>a]`. Any summed result → estimate.
3. Any hop missing → `nil` (unknown).

## Recording a flight

1. `TakeTaxiNode` hook (map still open): resolve `GetTaxiMapID()`, all nodes, current node
   (`state == Current`), destination, and hop path → pending flight `{mapID, path, positions}`.
2. Start the timer when `UnitOnTaxi("player")` turns true (checked via `PLAYER_CONTROL_LOST` and an
   OnUpdate fallback for the first few seconds). Discard pending flight if it doesn't start within ~10s.
3. While on taxi, poll player position every 0.2s on `mapID`. For the next pending intermediate node,
   track minimum distance and the time at that minimum; when the minimum is within a threshold and
   distance has grown again past it, commit that timestamp and move to the next node. If position is
   nil, hop timing is skipped for that flight (route total still recorded).
4. Landing (`UnitOnTaxi` turns false, via `PLAYER_CONTROL_GAINED`): if the player is close to the
   destination node position (or position unknown but duration is plausible: ≥ 5s), save the route
   total and every hop that was committed (first hop from takeoff, last hop to landing). Otherwise
   (early landing) discard.

## UI

### Flight map tooltip

After Blizzard builds the tooltip for a reachable node, append one line: `01:23`, or `~01:23` for an
estimate. No line when unknown. Re-`Show()` the tooltip.

Format: `mm:ss` (with leading zero), `h:mm:ss` if ≥ 1 hour.

### In-flight bar

One movable status bar frame, hidden unless on a taxi.

- **Recording** (unknown): red/orange bar with a slow sweeping fill, pulsing red dot, `REC` label, elapsed time counting up.
- **Countdown** (known/estimate): green bar draining from full, remaining time; `~` prefix if estimated. If the flight overruns, show `+0:05` overtime with the bar empty.
- Shows destination name.
- Draggable when unlocked; position saved in `FlightTimerDB.frame`.

### Slash `/ft`

- `help` — list commands
- `lock` / `unlock` — toggle bar movement (unlock shows a dummy bar to drag)
- `reset` — wipe all recorded times

## Files

- `FlightTimer/FlightTimer.toc`
- `FlightTimer/Core.lua` — event frame, DB init, data/lookup, flight recording
- `FlightTimer/Bar.lua` — in-flight bar UI
- `FlightTimer/Tooltip.lua` — flight map tooltip hooks, slash commands

## Testing (in game)

1. Fly a new direct route → REC bar, counts up; after landing hovering that destination shows `mm:ss`.
2. Fly it again → green countdown, ends close to 0.
3. Fly a multi-hop route A→B→C → afterward, B→A / A→B tooltips show `~` estimates.
4. `/ft unlock`, drag, `/ft lock`, `/reload` → position kept.
5. Log in on another character → times are present.
