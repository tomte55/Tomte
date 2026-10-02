# FlightTimer round 2: cinematic mode + flight stats

Builds on the base and round 1 specs.

## Spike result: camera APIs in 12.x

Settled by reading DialogueUI 1.0.5 (`## Interface: 120100`), which ships these patterns on Midnight:

- `GetCameraZoom`, `CameraZoomIn(n)` and `CameraZoomOut(n)` work for addons. Zoom is restored by applying the
  difference.
- `SaveView`/`SetView` are **avoided**, because DialogueUI notes they break Camera Following Style.
  We don't restore yaw. Camera follow brings the camera behind the character after landing.
- The UI is hidden by fading `UIParent:SetAlpha` to 0 and then `UIParent:SetShown(false)`, and only when
  `not InCombatLockdown()`.
- `MoveViewLeftStart(speed)` / `MoveViewLeftStop()`: the wiki lists them as unprotected and present in 12.1.5. `speed` multiplies
  the `cameraYawMoveSpeed` CVar.

## Cinematic mode

`/ft cinematic` toggles it (`FlightTimerDB.cinematic`, default **on**).

**When it's on** (pure `ns.CinematicWanted(expected, elapsed)`):
- From 2s after takeoff.
- Until 3s before the expected landing, so the UI is back as you land. With no known time, it lasts until
  the landing.
- Never on known flights shorter than 20s.
- Never re-entered after it ends during a flight.

**Entering:**
1. Save `oldZoom = GetCameraZoom()` on the flight (persisted via `db.current`), unless one is already saved.
2. Zoom out to 20 yards (`CameraZoomOut(20 - current)` if positive). Start a slow orbit with
   `MoveViewLeftStart(0.04)`.
3. Move the timer bar to `WorldFrame` at strata `FULLSCREEN_DIALOG` with matching effective scale, so it
   stays visible.
4. Letterbox: black bands at the top and bottom of the screen on `WorldFrame` (strata `FULLSCREEN`).
   Each is 9% of the screen height, with a soft 24px gradient edge, and slides in over 1.2s.
5. Fade `UIParent` alpha 1→0 over 1s, then hide it. Skipped if in combat.

**Exiting** (end lead, landing, `/ft cinematic` off, or cleanup after `/reload`):
1. `MoveViewLeftStop()`, then restore the zoom to `oldZoom`.
2. Slide the letterbox out.
3. Show `UIParent` and fade it 0→1 over 0.6s. In combat, wait for `PLAYER_REGEN_ENABLED`.
4. Move the bar back to `UIParent` once the UI is shown.

**Safety:** the UI must always come back.
- Exit is idempotent.
- `/reload` shows `UIParent` by itself. A resumed flight re-enters cinematic mode. A saved flight that can't
  resume (not on a taxi) gets cleaned up: orbit stopped and zoom restored.
- `Alt-Z` still works as a manual escape.

## Flight stats

`FlightTimerDB.stats = { flights, seconds, copper, longest, longestRoute }`, account-wide.

- **Cost:** `TaxiNodeCost(slot)` at takeoff, stored on the route and added when the flight actually starts (not on a resume).
- **Flights, time and longest flight:** added on landings that count as arrived. The route name is
  `"<origin> → <destination>"`.
- `/ft stats` prints the flight count, total time in the air (`h:mm:ss`), gold spent
  (`C_CurrencyInfo.GetCoinTextureString`), and the longest flight with its time.
- `/ft reset` doesn't clear stats. `/ft resetstats` does.

## Testing

- Unit: `CinematicWanted` boundaries, stats recording (count, sum, longest).
- In game:
  - Cinematic enters about 2s after takeoff: UI fades, letterbox slides in, camera zooms out and orbits,
    and the bar stays visible.
  - It leaves about 3s before landing: everything restored and the zoom back to where it was.
  - A recording flight leaves on landing.
  - `/reload` mid-cinematic: it resumes cleanly.
  - `/ft cinematic` mid-flight: it exits right away.
  - `/ft stats` output looks right.
