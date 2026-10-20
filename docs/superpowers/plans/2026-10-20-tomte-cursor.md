# Cursor highlight: plan

Spec: `docs/superpowers/specs/2026-10-20-tomte-cursor-design.md`.

1. Verify APIs (GetCursorPosition, IsMouselooking, PLAYER_REGEN_*, SetDesaturated) and the ring texture's file ID.
2. `Modules/Cursor/Data.lua` (pure): `ns.Cursor_AddSample`, `ns.Cursor_IsShake`, `ns.Cursor_ShakeLook`,
   `ns.Cursor_Look`, `ns.Cursor_TrailAdd`, `ns.Cursor_TrailFade`, `ns.CURSOR_SHAKE_WINDOW`.
3. `tests/test_cursor.lua`: shakes (horizontal, vertical) yes; straight moves, two turns, small wiggles, jitter,
   slow zigzags no; ring envelope; steady and hidden; trail spacing, cap and fade.
4. `Modules/Cursor/Cursor.lua`: driver frame (OnUpdate, 30 Hz sampling while hidden, per-frame drawing while
   shown), lazy full-screen holder (TOOLTIP, no mouse), theme colors on show, combat flag events, Start/Stop,
   registration with options and the `test` command.
5. Run all unit tests and the `luac -l` globals check; CRLF line endings.
6. Overseer: TOC lines, `lua Tomte/tools/bugfiles.lua`, README row and command, CHANGELOG after the in-game check.
