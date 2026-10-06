# Tomte: Weekly board overhaul (This week)

Date: 2026-10-06. Agreed with the user in chat; scope is the This week tab only (Characters and Professions stay as
they are) plus the reset time in the page header.

## Why

The tab was one flat full-width list with a lot of empty space, the page never said when the week resets, and the
renown bars showed progress inside the current level next to "7 / 25", so bar and number disagreed.

## Design

- **Header** (every tab): "Resets in 11h 23m · Tue 05:00" (local time of the reset) on the right of the tab buttons.
- **Banner** when vault rewards are waiting: "Great Vault rewards waiting: open it before you queue".
- **Great Vault band**: Raid / Dungeons / World, three slot boxes each (gold with item level when unlocked, the next
  slot's progress, later slots' progress dimmed), and what the next slot needs: "1 more boss for slot 2",
  "2 more dungeons for slot 1", or "All 3 slots unlocked" in gold. The slot box is shared with Home (Vault.lua).
- **Two columns** (stacked under 760 px wide), one scroll for the whole tab:
  - **To do**: weekly quests (open first, done ones dimmed), then per profession a heading with Concentration on
    the right and a row per open knowledge source with its points (hover for where, click for a waypoint when it
    has a place). A profession with all knowledge done is one green row.
  - **Progress**: renown (bar = level out of max to match "7 / 25"; "1,250 / 2,500 to 8" in grey; maxed is a full
    gold bar and "max"), crests, raid lockouts with their own reset.

## Code

- `Data.lua`: `Weekly_BoardModel(v, learned, now, showLearned)` replaces `Weekly_WeekModel`;
  `Weekly_ResetText(seconds, now)`. Row items gained `note`, `dimLeft`, a `gold` state, and headers can carry
  `right`/`state`.
- `Vault.lua`: `WeeklySlot_Create` / `WeeklySlot_Set`, used by Home's section and the board.
- `BoardPage.lua`: the row drawing is `ns.WeeklyRows(parent)` (no scroll); `ns.WeeklyList` wraps it in a scroll
  for the Professions view and the popup.
- `WeekView.lua`: the This week view.

## Testing

- Plain Lua (`tests/test_weekly.lua`): board model vault notes, quest order, knowledge rows, renown bar and note,
  lockouts after the reset, maxed faction, collapsed profession, reset text.
- In game: open the Weekly board on a max-level character; resize the window narrow to see the columns stack.
