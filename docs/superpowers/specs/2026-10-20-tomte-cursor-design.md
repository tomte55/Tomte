# Cursor highlight: design

2026-10-20. Module 4 of the addon round (see `2026-10-20-tomte-addon-round-overview.md`). Inspired by CursorGlow
and CursorTrail. Key `cursor`, folder `Modules/Cursor/`, settings group `ambience`. The user handed every decision
to Claude; everything below not in the overview is **Claude's call**.

## Intent

Lose the cursor on a busy screen (raid effects, a big monitor), shake the mouse, and a ring pops up around it, the
way macOS does "shake to find". Optionally the ring stays on in combat or all the time, with a short trail.

## Goals

- Ring in the theme's accent color around the cursor, read from the theme each time it appears.
- Modes: when you shake the mouse (default on), always in combat (off), always (off). Optional trail (off).
- Hide while turning the camera with the mouse (default on): the cursor is hidden then anyway.
- Never takes the mouse, never blocks clicks. Off by default.
- No work beyond a cheap position read while the ring is hidden; nothing at all while the module is off or the
  UI is hidden.

## Non-goals

- Replacing or resizing the game's cursor (no API for it).
- Custom ring art: no new `.tga` (would need a full client restart). Claude's call.
- Particle effects, rainbow trails, per-mode colors.

## API findings (checked on warcraft.wiki.gg and Gethe/wow-ui-source, live)

- `GetCursorPosition()`: x, y in screen pixels, unaffected by UI scale, origin bottom left. Divide by
  `UIParent:GetEffectiveScale()` for UIParent offsets. No restrictions listed; not a secret value.
- `IsMouselooking()`: true while the right mouse button turns the camera.
- `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`: no payload; entering and leaving combat.
- `Texture:SetDesaturated(true)`: grayscale; then `SetVertexColor` tints it (common Blizzard and addon pattern, but
  the wiki page doesn't say so outright: check in game).
- Ring texture: `interface/minimap/ui-minimap-ping-expand.blp`, file ID 237609 (community listfile), used live by
  `Blizzard_SharedMapDataProviders/GroupMembersDataProvider.lua` and `SharedMapPoiTemplates.xml` for the map's
  player ping ring. Halo and trail dots: Tomte's own `Media/Theme/Glow.tga` (white radial spot, `ns.Theme.MEDIA`).
- Icon: 135934 `spell_holy_mindvision` (community listfile).

## Look (Claude's call)

- Ring: the ping ring texture, desaturated, `ADD` blend, accent tint, `size` units across (default 64), at
  `opacity` (default 80%). Behind it a soft accent glow 1.6x the size at 35% of the ring's opacity.
- Shake: the ring fades in within 0.08 s while growing to 2.4x over 0.15 s, stays big while you keep shaking,
  shrinks back over 0.35 s when you stop, holds 0.6 s and fades over 0.4 s. Shake detection lags up to its 0.5 s
  window behind the hand, so the ring is gone about a second after the mouse is still.
- Steady modes (combat, always, the test) show the ring at full opacity; a shake still pops it bigger.
- Trail: up to 8 accent dots, one per 12 units moved, each lasting 0.35 s, shrinking to 40% and fading.
- Frame: a full-screen holder on UIParent, strata `TOOLTIP`, `EnableMouse(false)`.

## Shake detection (Claude's call)

Samples at 30 Hz, kept for 0.5 s. A shake: total path at least 250 units and at least 3 direction reversals along
x or y, where both legs around a reversal are at least 25 units; steps under 2 units are ignored as jitter. Tuned
for the 768-unit-tall UI at scale 1: a wrist flick covers 60 to 200 units per leg, aiming at a button rarely turns
three times in half a second. Thresholds are constants in `Data.lua`; no sensitivity setting until the user asks.

## Performance (Claude's call)

One driver frame, a child of UIParent, with an `OnUpdate`: the game stops calling it whenever UIParent is hidden
(cinematics, movies, Alt+Z), so those cost nothing without extra events. While the ring is hidden the script
returns immediately except 30 times a second, when it reads the cursor once and runs the shake check over at most
~15 samples. While the ring is shown it draws every frame. The driver's script is removed when the module turns off.
A `C_Timer` ticker would keep running under cinematics and would need a second mechanism for drawing.

## Settings

Card "When to show it": When you shake the mouse, Always in combat, Always, Hide while turning the camera,
Preview (Show). Card "Look": Size (32 to 160 px, step 8), Opacity (20% to 100%), Trail.

Defaults: `shake = true, combat = false, always = false, hideMouselook = true, size = 64, opacity = 0.8,
trail = false`. Module `enabledByDefault = false`.

## Commands

`/tomte cursor test`: shows the ring around the cursor for 4 seconds (says the module is off when it is).

## Files

- `Modules/Cursor/Data.lua`: pure (shake detection, ring envelope, trail aging). `tests/test_cursor.lua`.
- `Modules/Cursor/Cursor.lua`: driver, drawing, events, registration.

## Test plan (in game)

1. Tomte window > Ambience > Cursor highlight: turn it on, `/reload`.
2. Shake the mouse quickly left-right a few times: a ring in the theme's accent color pops up big around the
   cursor, shrinks to normal size when you stop, and fades about a second later. Ordinary mouse use (clicking
   buttons, dragging the camera) should not trigger it.
3. Same shake up-down: same result.
4. `/tomte cursor test`: ring at normal size for 4 seconds, following the cursor. Click through it on a button:
   the click must reach the button.
5. Turn on Trail, shake: a few small fading dots follow the cursor.
6. Size and Opacity sliders: the next ring follows them.
7. Turn on Always in combat, attack a training dummy: the ring stays while in combat, goes when combat ends.
8. Turn on Always, hold the right mouse button to turn the camera: the ring hides and returns on release
   (turn off Hide while turning the camera: it stays).
9. Switch theme (Tomte settings): the next ring uses the new accent color.
10. Turn the module off: the ring disappears at once, even with Always on.
11. Alt+Z with Always on: the ring hides with the UI.
12. Look for: the ring is a clean colored ring (not muddy gold); if it looks wrong, `/fstack` over it and report.
