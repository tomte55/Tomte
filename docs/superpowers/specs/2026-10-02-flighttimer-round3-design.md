# FlightTimer round 3: cinematic upgrades, showcase, stats, settings

Builds on rounds 1 and 2. The user approved the design and asked for everything in one go.

## Cinematic upgrades

- **Passing captions.** When the pass tracker commits a waypoint, the title group (label, title, divider,
  subtitle) shows `P A S S I N G` / `<flight master>`. On `ZONE_CHANGED_NEW_AREA` it shows
  `E N T E R I N G` / `GetZoneText()`. Timing: 0.3s fade out, swap, 0.3s fade in, hold until 4.0s,
  fade out, swap back, fade in. A new caption restarts the cycle. Cinematic mode only.
- **Arrival shot** (known flights only). `ns.OrbitFactor(expected, elapsed)` is 1 until 6s remain,
  falls linearly to 0 at 3s remaining (the cinematic end lead), and stays 0 after that. The orbit speed
  follows it. When the factor first drops below 1, the zoom is restored so the camera eases back in. A
  factor of 0 stops the orbit.
- **Vignette.** Left and right black gradients, each 16% of the screen width, peaking at 0.6 alpha. They
  fade with the letterbox.
- **Music** (off by default). A dropdown picks an expansion main theme (`SOUNDKIT.MUS_*_MAIN_TITLE`).
  - `PlaySound(kit, "Master")`. While it plays, zone music is muted by setting `Sound_MusicVolume` to 0.
    The old value is backed up in `db.musicVolumeBackup`.
  - On exit: `StopSound(handle, 3000)` to fade it, then put the volume back, but only if it's still 0,
    so a change the user made in the meantime wins.
  - A login that doesn't resume a flight also restores a leftover backup.
  - The handle lives on the flight (`db.current`), so a resume doesn't start a second copy.
- **Settings for orbit, cursor and minimum length.** Orbit and cursor hiding can each be turned off.
  The minimum flight length for cinematic mode is configurable (10–60s, default 20).

## Character showcase (left side, cinematic only)

- `PlayerModel:SetUnit("player")` shows your current transmog, slowly rotating.
- Gear icons like the character sheet:
  - Left column: head, neck, shoulder, back, chest, shirt, tabard, wrist.
  - Right column: hands, waist, legs, feet, two rings, two trinkets.
  - Below the model: main hand and off hand.
- Each icon has a 1px quality-colored border and its item level, using `ItemLocation` with
  `C_Item.DoesItemExist`, `GetItemIcon`, `GetItemQuality`, `GetCurrentItemLevel` and
  `GetItemQualityColor`.
- A soft black gradient backdrop sits behind it. It fades in slightly after the band contents.
- Setting: `showcase` (default on).

## Stats

- `RecordStats(db, duration, routeName, originName, mapID)` also tracks `byMap[mapID]` (seconds),
  `departures[originName]` (count) and `routeCounts[routeName]` (count).
- `ns.TopEntry(tbl) -> key, value` (largest value).
- The bottom-right of the band rotates every 6s, with a 0.3s cross-fade, through:
  - `Flight #N` / time in the air (live)
  - `Most visited` / flight master
  - `Most flown` / route
  - continent name (`C_Map.GetMapInfo(mapID).name`) / time flown there
- `/ft stats` prints everything.

## Bottom corner text

Bigger: character name 19, character info 13, stats title 18, stats line 13.

## Settings panel

Uses `Settings.RegisterVerticalLayoutCategory("FlightTimer")` with `RegisterAddOnSetting` on `FlightTimerDB`.

- **Timer:** lock bar, arrival alert, and a "Test alert" button.
- **Cinematic:** enabled, camera orbit, hide cursor, character showcase, music, music track
  (dropdown), and minimum flight length (slider).
- **Data:** "Reset flight times" and "Reset stats" buttons.

The addon compartment entry `FlightTimer_OnAddonCompartmentClick` (TOC `AddonCompartmentFunc`) opens the
panel. `/ft` keeps working, and `/ft options` opens the panel.

## Revision after the first in-game test

- **Passing captions removed.** Zone changes now show a separate hanging sign instead of a title-card caption.
- **Hanging zone sign (upper right).** It uses the `housing-woodsign` atlas (Midnight housing UI) with
  `ENTERING`-free text: just the zone name in Morpheus 20.
  - It hangs on two parallel rope lines from the bottom of the top band, so it stays level while
    swinging (text can't rotate).
  - The rope anchors slide in from the right edge (0.9s, ease-out). The sign follows a damped pendulum
    (`ns.PendulumStep`, unit-tested), driven by the anchor's acceleration.
  - It holds for 5s, then slides out (0.8s, ease-in). A new zone while hanging updates the text and
    restarts the hold.
- **Showcase redesigned as "Spotlight".**
  - The model has a frozen stand pose (`FreezeAnimation(0,0,0)`), and `ZeroCachedCenterXY` on
    `OnModelLoaded` keeps the feet steady while turning.
  - A full-height left gradient (no visible edges), a soft additive light beam, and a class-colored
    floor glow (`UI-Common-MouseHilight`).
  - Name with title (`UnitPVPName`) and item level above the model.
  - Slim gear columns that fade toward their ends, with weapons under the floor glow.
  - Band contents and the sign sit at explicitly higher frame levels than the showcase shade.
