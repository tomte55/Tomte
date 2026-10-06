# Tomte: Sessions page

Date: 2026-10-06. Agreed with the user: choices are settings with defaults rather than fixed decisions. Picks up two items
the Session recap spec parked: "a panel page" and "cross-session history beyond the last session".

## Goal

See how past sessions went, not just the last one: when you played, for how long, gold earned and where it came
from, gold per hour, and what you got. With Gold & value (`2026-10-06-tomte-gold-value-design.md`) loot gets a
price too, so a farming night shows what it was really worth.

## Storage

Today `TomteDB.sessionLast[guid]` keeps one session per character and is overwritten at login
(Core/SessionData.lua). New:

- `TomteDB.sessions[guid]` = list, newest first, capped (default 30 per character).
- When a session ends (at the next login, where `sessionLast` is written today), a compact copy is added:
  `{ start, duration, zoneTop, net, gold = {in, out}, value (loot value, from Gold & value), levelFrom, levelTo,
  counts, highlights (up to 6 log entries), log (only for the newest 5) }`.
- Sessions under 2 minutes aren't kept (reloads and quick swaps).
- `sessionLast` stays as is for the login toast and `/tomte recap last`.

`zoneTop` (where most of the time went) needs a little tracking: seconds per zone in the live session, updated on
`ZONE_CHANGED_NEW_AREA`.

## Page

A Home rail page **Sessions**:

- Top: a bar chart of the last 30 sessions for the selected character (or all characters, stacked by color):
  gold earned per hour, a second series for loot value when Gold & value is on. Hover a bar for its summary.
- Below: a list, newest first: date and time, character, duration, zone, net gold, gold/hour, value. Click a row to
  open its recap card (the same card as `/tomte recap`, fed with the stored copy).
- Filter: this character / all characters, and a "This week" / "All" toggle with totals for the range.

## Options (Session recap module)

| Setting | Choices | Default |
|---|---|---|
| Keep history | on/off | on |
| Keep by | Count / Days | Count |
| Sessions per character | 10-100 | 30 |
| Days kept | 7-90 | 28 |
| Main number | Gold per hour / Net gold per session | Gold per hour |
| Group sessions into play nights | on/off (sessions less than an hour apart, any character) | off |
| Clear history | button (confirm) | |

## Testing

- Plain Lua: compacting a session, the cap, the 2-minute rule, gold/hour, week totals across the weekly reset.
- In game: log out and in a few times, check the page and that old cards still open.
