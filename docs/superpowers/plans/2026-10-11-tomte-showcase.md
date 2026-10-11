# Showcase implementation plan

Spec: `docs/superpowers/specs/2026-10-11-tomte-showcase-design.md`. Built inline (no subagents), unit tests with plain
Lua, then one in-game test round.

1. **Engine options** (`Cinematic/Engine.lua`): `zoom` (signed `state.zoomedOut`), `pitch`, `interactive`,
   `bands`. Existing callers keep today's behavior (no options = zoom out to 20, pitch 22, input captured, bands).
2. **Data.lua + tests**: stat rows (role filter, hide at 0), formats, `CharShow_Zoom`, `CharShow_Shoulder`,
   `CharShow_TurnBack`, `CharShow_TrackTag`, `CharShow_SlotHints`, slot column lists. `tests/test_showcase.lua`.
3. **Camera.lua**: CVar backup/restore (persisted, restored at login and logout), shoulder offset follower, swing +
   slow turn with yaw tracking, turn back, popup hiding, model height measuring.
4. **Scene.lua**: scene contract (Create/Begin/Update/End), slots, stats panel, own tooltip, refresh.
5. **Showcase.lua**: module (key `showcase`), open/close/toggle, binding `TOMTE_SHOWCASE` (Bindings.xml), command,
   minimap button, events (gear, stats, moving, logout), options, `cinematicState`.
6. TOC entries, README module list, run every test, report with the in-game checklist. Commit only after the user
   confirms in game.
