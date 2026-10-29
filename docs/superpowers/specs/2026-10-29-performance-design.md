# Performance module (2026-10-29)

Inspired by WoW Task Manager (CurseForge), scoped to the user's goal: **make sure Tomte is fast**, and when it isn't,
name the module, the file and the event so the fix is obvious ("Bags, Read.lua, BAG_UPDATE, 34 ms"). Other addons get
Blizzard's numbers, nothing more. All design decisions below were delegated to Claude.

## What the game gives us

- `C_AddOnProfiler` (retail 11.0.7+, Forever 1.60.1): always on, no `scriptProfile`. Per addon, overall and for the
  whole application: session / recent (60 ticks) / encounter averages, last, peak (ms), and counts of ticks over
  1/5/10/50/100/500/1000 ms. Blizzard's percentages (Blizzard_AddOnList) are `addon / (app - overall + addon)`.
- `GetAddOnMemoryUsage` after `UpdateAddOnMemoryUsage` (slow with many addons: every 5 s while the page shows),
  `GetFramerate`, `GetNetStats`.
- Blizzard can't split Tomte into modules. Tomte measures itself.

## Self-measurement (Core/Perf.lua, Core/PerfData.lua)

- `debugprofilestop()` around each handler; `collectgarbage("count")` before and after for the memory a call makes
  (an estimate: a GC step inside the call hides some).
- Attribution is automatic: a bus (`ns.NewEvents`) and `ns.Perf_Wrap` find the file that created them with
  `debugstack`, once, at creation. Group = the module folder (`Modules/Bags/*` -> Bags), or Core / Window / Cinematics.
  Inside a group, a breakdown per owner or file, then per event or script.
- Covered: every event bus handler (no call-site changes), module init and first start (`Core/Modules.lua`), and
  every plain `OnEvent` / `OnUpdate` script and tooltip post-call wrapped with `ns.Perf_Wrap` / `ns.Perf_WrapEvents`.
  Not covered: `C_Timer` callbacks and `hooksecurefunc` hooks (hundreds of sites); they show as the gap between
  Blizzard's total for Tomte and ours ("measured: about N%").
- Recording runs only while the module is on (one flag check per call when off). Startup times are always recorded
  (a few dozen numbers, once).
- A call at or above 5 ms counts as slow; at or above 16 ms (a 60 fps frame) it's a hitch, kept in a list of the
  last 30.
- The first 20 seconds after entering the world count separately as "login", which was the 14% the user saw.

## The module (Modules/Performance, key `perf`, category tomte, off by default)

- **Page** "Performance": a headline (Tomte's share of frame time, colored green / yellow / red at 1% and 5%),
  tiles (frame rate, latency, all addons, Tomte memory), Tomte's modules as a table (Now ms/s, Session, Peak, Slow,
  Memory churn; sort Now / Session / Peak; hover = top files and events), recent hitches, startup per module, all
  addons from Blizzard's profiler. Buttons: Reset (start measuring from now), Copy report (a text report for
  pasting into a bug report or to Claude).
- **Hitch warning** (off by default): a chat line when one Tomte call takes over N ms (20 to 200, default 50),
  at most once a minute per module and event.
- **Readout** (off by default): a small Edit Mode widget, "58 fps · 18 ms · Tomte 0.1%".
- Commands: `/tomte perf show` (top modules and hitches in chat), `report`, `reset`, `open`.

## Left out on purpose

Flight recorder, timeline, sessions across reloads, per-addon event counts, benchmark mode. History over time was
offered and not asked for.
