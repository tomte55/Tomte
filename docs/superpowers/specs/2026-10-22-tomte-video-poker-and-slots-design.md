# Casino: Video poker and Slots (2026-10-22)

Follows `2026-10-21-tomte-games-blackjack-design.md` and `2026-10-22-tomte-blackjack-chips-and-table-design.md`.
The user picked video poker and slots and delegated the rest ("spec, plan and build those, come back when it is all
done"). Every decision below is Claude's call.

## One module, one window, three games

The first spec planned one module per game. Since then the chips became a shared economy (earned in the world,
spent at the Cashier, a rank, a daily refill), so a second module would need its own wallet or reach into Blackjack's
db. Instead the `blackjack` module becomes the **Casino**: one window, one chip count, one Cashier, three games.

- Module key stays `blackjack` (saved data and the `TOMTE_BLACKJACK` binding keep working, no migration). Its name
  becomes **Casino**; summary and description cover all three games.
- The window's title becomes a game switcher: **Blackjack · Video poker · Slots** (text tabs, the active one in
  `heading` with an `accent` underline). The rank sits left of the chip count; Cashier and close stay.
- The last game played is remembered (`db.lastGame`) and is what the window opens on, also when it opens on its own
  (flight paths, queues). Switching games mid-hand is fine: every game saves its state.
- Commands: `/tomte blackjack` (open or close), `open`, and new `poker` and `slots` (open on that game). `stats`
  prints all three games. The key binding's name becomes "Casino".
- Chips: one stack (`db.game.chips`), the same earning, the same refill (under 10 chips, once a day, to 500), the
  same rank. Start over resets all three games' stats.

## Video poker (Jacks or Better)

The standard machine, full-pay 9/6 table (99.5% return with perfect play).

- Bet: a **coin** value picked with the chip buttons (10, 50, 100, 500) times **1 to 5 coins** ("Bet one" steps 1..5,
  "Bet max" sets 5 and deals). Defaults: 10 x 5.
- Deal: five cards from a freshly shuffled 52-card deck. Click a card to hold it (it lifts and shows "Held"). Draw
  replaces the others from the same deck. The hand pays by the table, in coins, times the coin value; the bet is gone
  either way (a pay of 1 is your bet back).

| Hand | Pays per coin |
| --- | --- |
| Royal flush | 250 (800 with 5 coins: 4,000) |
| Straight flush | 50 |
| Four of a kind | 25 |
| Full house | 9 |
| Flush | 6 |
| Straight | 4 |
| Three of a kind | 3 |
| Two pair | 2 |
| Jacks or better | 1 |

- Ace counts high or low in a straight (A-2-3-4-5 and 10-J-Q-K-A), no wrap-around.
- The pay table is on the machine's screen: one column per coin count, the current bet's column lit, the winning row
  flashing. While holding, the message line names what you already have ("You have two pair").
- No double-up, no auto-hold hints (non-goals).
- The screen takes the Cashier's felt color, and the cards the chosen back.
- Stats (`game.poker.stats`): hands, wins, biggest win, and a count per hand (royal, straight flush, four of a kind
  ...). Shown on the chip count tooltip while the game is open.

## Slots

A three-reel machine with WoW item icons, three rows, five paylines (the three rows and both diagonals, always on).

- Bet per spin with the chip buttons: 10, 50, 100 or 500; a fifth of it rides on each line.
- Symbols, low to high: Murloc, Copper bar, Silver bar, Gold bar, Ruby, Hearthstone (bars and the ruby replaced
  coins and a diamond after the first in-game test: they were hard to tell apart). Each reel is a 26-stop
  strip (10 murlocs, 5 copper, 4 silver, 3 gold, 3 rubies, 1 Hearthstone), in a different order per reel.
- Pays per line (times the line bet): three Murlocs 4, Copper 15, Silver 30, Gold 60, Rubies 120, Hearthstones
  1,000 (the jackpot); **any three bars** mixed 2.
- That returns 94.9% of what's bet over time (exact, from enumerating every stop; a unit test checks it), about 58%
  of spins win something, and the jackpot comes about once in 3,500 spins.
- The reels spin with a decelerating roll and stop left to right with a click; clicking Spin while they roll stops
  them at once. Winning lines are drawn across the reels, their symbols glow, and the win floats up; a jackpot gets a
  banner and the big sound.
- The pay table sits beside the reels, in chips for the current bet.
- Stats (`game.slots.stats`): spins, wins, biggest win, jackpots.

## Feats

Two card backs unlock with feats from the new games (patterns reused, no new art):

- **Four of a kind** (base `danger`, `warning` lattice): 3 fours of a kind in video poker.
- **Jackpot** (base `success`, `warning` stars): a slots jackpot.

Feats name their game (`feat.game = "poker"`), so `CashierData.lua` now takes the whole game table instead of the
blackjack stats.

## Files

| File | Role |
| --- | --- |
| `PokerRules.lua` (new, pure) | Hand evaluation, pay table, deal / hold / draw, coins, stats, text |
| `SlotsRules.lua` (new, pure) | Symbols, reel strips, paylines, line pays, spin, stats, return rate |
| `CashierData.lua` | Feats from any game; two new backs |
| `Effects.lua` | Exposes the tween (`ns.GamesFx_Tween`, `ns.GamesFx_TweenStop`), new sounds (hold, spin, reel stop, jackpot) |
| `Window.lua` (new, UI) | The window shell, split out of `Table.lua`: title bar, game tabs, chip count and tooltip, rank, Cashier swap, refill button, sounds, place |
| `Table.lua` | The blackjack face only |
| `PokerMachine.lua` (new, UI) | The video poker face |
| `SlotMachine.lua` (new, UI) | The slots face |
| `Blackjack.lua` | Module name Casino, new commands, `lastGame` default, Repair of the new games |

`Table.lua` is 877 lines, so the shell moves to `Window.lua` first as a pure move (its own commit).

Saved (new keys have defaults or are filled by Repair, no migration):

```lua
lastGame = "blackjack", -- "blackjack", "poker" or "slots": what the window opens on
game.poker = { coin = 10, coins = 5, round = nil | { phase, cards, held, deck, next, coin, coins, result, payout },
	stats = { hands, wins, biggestWin, royal, straightFlush, quads, fullHouse, flush, straight, trips, twoPair, jacks } },
game.slots = { bet = 10, stops = { 1, 1, 1 }, last = nil | { wins, payout, bet }, stats = { spins, wins, biggestWin, jackpots } },
```

## API

Nothing new from the game: plain frames, `math.random`, `SOUNDKIT` keys checked in
`Blizzard_SharedXML/Mainline/SoundKitConstants.lua` (live): `IG_MAINMENU_OPTION_CHECKBOX_ON/OFF`,
`UI_80_AZERITEARMOR_ROTATIONSTARTCLICKS`, `UI_PROFESSION_SPEC_PIP_LOCKIN`, `TRADING_POST_UI_REWARD_TIER_COMPLETE`.
Icons (wago.tools listfile): 134169 inv_misc_head_murloc_01, 133216 inv_ingot_02, 133215 inv_ingot_01,
133217 inv_ingot_03, 134129 inv_misc_gem_ruby_02, 134414 inv_misc_rune_01. Frame `SetClipsChildren` masks
the reels; `CreateLine` draws the paylines.

## Testing (in game)

Switch games with the tabs and `/tomte blackjack poker|slots`; reopen lands on the last game. Poker: deal, hold,
draw, bet one / bet max, coin value, a `/reload` while holding. Slots: spin, stop early, wins drawn, bet change,
pay table in chips. Out of chips in each game; Cashier from each game; feats; combat and Esc; a theme switch.
