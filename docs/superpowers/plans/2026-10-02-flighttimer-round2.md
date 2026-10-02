# FlightTimer Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Cinematic flight mode (camera zoom and orbit, UI fade-out, letterbox) and account-wide flight stats.

**Architecture:**
- Pure decisions in `Data.lua`: `CinematicWanted` and `RecordStats`, both unit-tested.
- New `Cinematic.lua` owns the camera, letterbox, UIParent fade and combat-deferred restore.
- `Core.lua` drives it from the flight tick and adds the slash commands.
- `Bar.lua` gains `Bar_SetCinematic(on)`.

**Spec:** `docs/superpowers/specs/2026-10-02-flighttimer-round2-design.md`

## Global Constraints

- Base rules still apply: namespace, one event frame, no new globals, Lua 5.1, and a WoW-free `Data.lua`.
- The UI must always come back. Exit is idempotent and defers to `PLAYER_REGEN_ENABLED` in combat.
- Don't use `SaveView`/`SetView`.

## Review Focus

1. **Combat starts while the UI is hidden** → the UI comes back on `PLAYER_REGEN_ENABLED` (or via Alt-Z).
2. **`/reload` mid-cinematic, then not on a taxi** → orbit stopped and zoom restored.
3. **`/ft cinematic` off mid-flight** → immediate exit, never re-entered that flight.
4. **Landing on an unknown route while cinematic** → exit happens on landing and the UI comes back.
5. **Another addon or the user shows UIParent mid-cinematic (Alt-Z)** → no error; exit still restores alpha 1.

### Task 1: Pure logic + tests
- `ns.CINEMATIC_DELAY = 2`, `ns.CINEMATIC_END_LEAD = 3`, `ns.CINEMATIC_MIN = 20`.
- `ns.CinematicWanted(expected, elapsed) -> bool`.
- Defaults: `cinematic = true`, `stats = { flights = 0, seconds = 0, copper = 0, longest = 0, longestRoute = "" }`.
- `ns.RecordStats(db, duration, routeName)`.
- Tests:
  - wanted: before the delay, after the delay with an unknown time, inside the end lead, overrun, short known flight.
  - stats: count, sum, longest replaced only when longer.

### Task 2: Cinematic.lua, bar hand-off, Core wiring, `/ft cinematic|stats|resetstats`
- `ns.Cinematic_Init()`, `ns.Cinematic_Enter(flight)`, `ns.Cinematic_Exit(flight)` (idempotent, works on a saved
  flight table for cleanup), `ns.Cinematic_IsActive()`, `ns.Cinematic_OnCombatEnded()`.
- Core:
  - The tick evaluates `db.cinematic and not flight.cinematicDone and CinematicWanted(...)`. It enters or
    exits on a change; exiting sets `flight.cinematicDone`.
  - `EndFlight` always calls Exit.
  - The resume failure path calls Exit on the saved flight.
  - Cost: `route.cost = TaxiNodeCost(slot)` is added to the stats when the flight starts from pending.
    Origin name is stored for the route name.
  - Register `PLAYER_REGEN_ENABLED`.
- Verify: `luac -p`, unit tests, and the global-write scan.
