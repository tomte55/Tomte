# Games: Blackjack (`blackjack`): design

2026-10-21. First game in a new `Modules/Games/` folder (one module per game, like `Modules/Social`). The user
picked the folder, blackjack first, play chips, and playing against friends as a later step. Everything marked
"(Claude's call)" was delegated ("spec, plan and build it").

## Intent

A blackjack table to pass the time on flight-path rides, or any time you're bored: you against the dealer, play
chips only, stats that stay between sessions.

## Goals

- A movable table window (`UI.Dialog`): dealer row, your hand(s), a message line, chip count, bet controls.
- Standard rules (Claude's call): a 6-deck shoe, reshuffled before a deal once fewer than a quarter of the cards are
  left; dealer stands on soft 17; dealer peeks with an ace or ten-value card showing; blackjack pays 3:2; double on
  any first two cards, also after a split; one split (two hands), any two ten-value cards may split; split aces get
  one card each; 21 on a split hand is 21, not blackjack. No insurance, no surrender.
- Chips: 1,000 to start, chip buttons 10 / 50 / 100 / 500 (all multiples of 10, so 3:2 is always whole), Clear,
  Deal; after a round the same bet stays up so Deal plays again. Broke (under 10 chips): a "House chips" button gives
  a fresh 1,000 and counts a refill in the stats.
- Stats on hovering the chip count: hands, won / lost / pushed, blackjacks, biggest win, best win streak, most chips
  held, refills.
- The game is saved (chips, stats, shoe, the round in progress), so a `/reload` mid-hand carries on.
- Opens with `/tomte blackjack`, a key binding (Key Bindings > Tomte > Blackjack table) or the settings page's Open
  button. Setting: open it on its own when you take a flight path (off by default), and close it again when you
  land if it opened for that flight.
- Cards are drawn one by one with a short slide; the dealer's hole card turns and the dealer's cards follow at a
  steady pace; the result shows once every card is down.
- Sounds and effects (added after the first in-game test, `Modules/Games/Effects.lua`, shared by later games):
  Blizzard sound kits on the Effects channel (a Sounds setting, on by default) for dealing, the hole card, chips,
  win / big win / blackjack / push / loss and opening the table; dealt cards grow as they land; the result line
  pops in its outcome color; floating +/- chips over each hand and the chip count; the chip count rolls to the
  payout; winning hands glow, losing hands dim, a bust and a dealer bust shake; a "Blackjack!" banner.

## Non-goals (v1)

- No real gold, ever (Blizzard's rules on gambling; a public addon).
- No playing against friends yet. Later: an addon-message table (`C_ChatInfo.SendAddonMessage`), like Friend
  sharing's protocol. Pure rules are kept separate from the UI so a shared table can reuse them.
- No in-table key bindings (Hit / Stand ...): mouse only, so it never takes movement keys. Easy to add later.
- No session recap line (it would fire on every short flight).

## Defaults

`enabledByDefault = true` (nothing shows unless opened). Open on flight paths: off. Close on landing: on (only
matters with the first). Window position saved; Esc closes it.

## Interactions

- **Combat:** the table hides when combat starts and comes back when it ends, if it was open. Nothing in it is
  protected (plain frames), so there's no taint risk; it just stays out of the way.
- **Flight cinematic (Flight module):** while the table is open the flight cinematic doesn't start (and ends if it
  was running), otherwise the cinematic would fade the table out mid-hand. Flight asks `ns.Blackjack_IsOpen()` at
  call time (one line in `Modules/Flight/Flight.lua`). So with "Open on flight paths" on, flights show the table
  instead of the cinematic; the setting's tooltip says so.
- **Turned off:** window closed, events unregistered, timers cancelled. The saved game stays.

## API (verified 2026-10-21)

- `UnitOnTaxi(unit)` -> boolean (https://warcraft.wiki.gg/wiki/API_UnitOnTaxi), no 12.x notes.
- `PLAYER_CONTROL_LOST` / `PLAYER_CONTROL_GAINED` (https://warcraft.wiki.gg/wiki/PLAYER_CONTROL_LOST): no payload;
  fire for taxis, fear and mind control, so the handler checks `UnitOnTaxi("player")` a moment later (the Flight
  module also waits for `UnitOnTaxi` after taking a route). `PLAYER_ENTERING_WORLD` covers a `/reload` in flight.
- `math.random` for the shuffle (Fisher-Yates in the pure file, the random function passed in so tests can fix it).

## Files

| File | Role |
| --- | --- |
| `Modules/Games/CardData.lua` | Pure: cards as numbers 1-52, rank/suit, shoe build and shuffle. Shared by later card games. |
| `Modules/Games/BlackjackRules.lua` | Pure: hand values, the round (deal, hit, stand, double, split, dealer, settle), chips and stats. |
| `Modules/Games/Card.lua` | UI: one playing card widget (face, back, deal slide). |
| `Modules/Games/Table.lua` | UI: the blackjack table window. |
| `Modules/Games/Blackjack.lua` | Main: events (taxi, combat), db, module registration, command, binding. |
| `Media/Games/{Spade,Heart,Diamond,Club}.tga` | White suit shapes, tinted by role; from `tools/games_art.py`. Need a client restart. |
| `tests/test_carddata.lua`, `tests/test_blackjackrules.lua` | Unit tests. |

Card faces use the theme's `text` color as the card (light on every theme), `bg` for spades and clubs, `danger` for
hearts and diamonds; the back is `accentDeep` with an `accent` rule.

## Saved data (`TomteDB.blackjack`)

```
taxi = false, closeOnLand = true,
frame = { point, relPoint, x, y },
game = { chips = 1000, bet = 0, shoe = { cards }, next = 1, round = nil | { ... }, stats = { ... } }
```

`game` is account-wide (one chip stack for all characters).

## Testing (in game)

Deal, hit, stand, double, split (pairs come rarely: `/tomte blackjack split` deals a pair to test it), blackjack,
dealer blackjack, going broke and House chips, `/reload` mid-hand, taking a flight path with the setting on,
combat while open, Esc, a theme switch.
