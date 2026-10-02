# FlightTimer round 1: calibration, alert, stop markers, arrival clock, polish

Builds on `2026-10-02-flighttimer-design.md`. Cinematic mode and flight stats are round 2.

## 1. Estimate calibration

**Problem:** hop times measured while passing through a flight master leave out takeoff and landing.
Estimates built from them come out short (observed: 7s on one route).

**Fix:** learn one global offset and add it to every estimate.

- `FlightTimerDB.calibration = { offset = 0, samples = 0 }`.
- When a flight lands that had an estimated time, `sample = actual - rawEstimate`. `rawEstimate` is the
  hop sum without the offset.
- Ignore a sample if `|sample| > 0.5 * rawEstimate`, since that's an outlier.
- `samples = min(samples + 1, 10)`, then `offset += (sample - offset) / samples`. The first 10 samples
  give a plain mean; after that it's a moving average over roughly the last 10 flights.
- `LookupTime` returns `hopSum + offset` for estimates (at least 1s). Exact routes are unchanged.
- One flat offset fits because every estimate has exactly two endpoints (one takeoff and one landing)
  that the hops don't include.

## 2. Arrival alert

- In countdown mode, when 5s remain: `PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3, "Master")` and
  `FlashClientIcon()`. This fires once per flight and the flag survives `/reload`.
- In recording mode there's no known end, so the alert fires on landing instead.
- `/ft alert` turns it on or off (`FlightTimerDB.alert`, default on).
- Sound while alt-tabbed depends on the game's "Sound in Background" setting. The taskbar flash works
  either way.

## 3. Stop markers on the bar

- Countdown mode only. A thin vertical tick for each intermediate stop.
- Position: the fraction of the flight elapsed at that stop. If every hop time is known, the fraction
  comes from hop times. Otherwise it comes from the straight-line distance between the flight master
  positions.
- The countdown fill shrinks from right to left, so a stop at elapsed fraction `f` sits at `x = (1 - f) * width`.
- Ticks are bright while ahead and dim once passed.
- The unlock preview shows two sample ticks.

## 4. Arrival clock

- Countdown mode only: small text under the bar, right-aligned: `lands 21:47`, local 24-hour time
  from `date("%H:%M", time() + remaining)`.
- Hidden in recording mode and once the flight overruns.

## 5. Bar polish

- Fill texture `Interface\RaidFrame\Raid-Bar-Hp-Fill` (smooth gradient), as used by Blizzard arena frames.
- Tooltip-style border via `BackdropTemplate` (`Interface\Tooltips\UI-Tooltip-Border`) with a dark background.
- Flight-master icon `Interface\TaxiFrame\UI-Taxi-Icon-Green` left of the bar.
- Fades in over 0.3s and out over 0.4s instead of popping.

## Out of scope

Cinematic mode, flight stats (round 2), character model (dropped).

## Testing

- Unit: calibration math, `LookupTime` with offset, stop fractions (hop- and distance-based),
  alert trigger.
- In game: alert at 5s and on landing for a recording flight, ticks in the right places,
  arrival clock, look of the bar, fades, `/ft alert` toggle; the estimate gap shrinks over a few
  estimated flights (`/dump FlightTimerDB.calibration`).
