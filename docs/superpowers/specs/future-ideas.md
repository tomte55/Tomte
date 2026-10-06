# Tomte: future ideas

Ideas the user wants kept for later, not designed or scheduled yet. Each needs a design pass with the user before
building. Parked items inside a module's own spec stay there ("Later" / "Out of scope" sections); this file is for
ideas that don't belong to one existing spec.

## Events & holidays (2026-10-06)

Weekly parked "a world event calendar". Combined with Collect's catalog it becomes: the world events active now
(and starting soon) and the holiday mounts, pets, toys and achievements you're still missing from them. Shown on
Home as an "around"-style block or a section, with a toast when an event with missing collectibles starts.

- `C_Calendar` lists the holidays (needs `C_Calendar.OpenCalendar()` before the month data is there; verify in 12.x).
- Mapping holidays to collectibles probably needs a small hand-made table (holiday achievements live under the
  World Events category, which helps for achievements; mounts/pets/toys name the holiday in their source text).

## Collection goals (2026-10-06)

Pin a mount, pet, toy or achievement as a goal (from Collect here, Almost Done or the journals). Home lists the
goals with progress, currency have/need summed across alts (Alts + Syndicator), and a waypoint or teleport to the
source (Waypoints, Teleports). Ties the collecting modules together into a "working toward" view.

- Open questions: where goals are pinned from (a star in each journal, like Smart Mount's zone favorites?), how a
  vendor source's cost is known (source text vs. a hand-made table), and whether Almost Done's pins become goals.
