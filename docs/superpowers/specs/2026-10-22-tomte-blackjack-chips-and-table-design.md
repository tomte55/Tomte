# Blackjack: earned chips, the Cashier and a classic table (2026-10-22)

Follows `2026-10-21-tomte-games-blackjack-design.md`. Three parts: chips come from playing the game, chips buy looks
at a Cashier, and the table is redrawn as a classic casino half-moon with the rules printed on the felt. Plus one new
auto-open moment: the dungeon/raid/battleground queue.

Out of scope: real gold (an addon can't move gold; a casino for real gold invites trouble), boats and zeppelins (no
API tells an addon you're on one), playing with friends.

## 1. Earning chips

Each source is a checkbox under a new **Earning** settings card, all on by default. Earning works whether the table
is open or not, as long as the module is on.

| Source | Pays | How it's read |
| --- | --- | --- |
| Flight path | 10 per full minute in the air | Taxi start time (the existing taxi detection) to landing; paid on landing |
| Quest turned in | 25; daily 50; weekly 250 | `QUEST_TURNED_IN`; daily/weekly noted at `QUEST_COMPLETE` (quest frame) or from the quest log while the quest is still in it. Quests with no title (hidden tracking flags) pay nothing |
| Great Vault | 1,000, once per week | The first claim of the week (Vault rewards go from available to claimed) |
| Gold looted | 1 per whole gold, at most 500 a day | `PLAYER_MONEY` gains while a loot window is open (`LOOT_READY` .. `LOOT_CLOSED`), so vendor, mail, AH and quest gold don't count |

- A day is one daily reset to the next, a week one weekly reset to the next (the game's reset times, not midnight).
- When the table is open, each payout floats over the chip count ("+25 quest") and the count rolls up. When it's
  closed, nothing shows.
- Stats gain **Chips earned** (all time) and the chip tooltip shows **Earned today** by source.
- The session recap gets a line for each Cashier purchase and each feat unlock, through `ns.Session_Note`. (A
  per-session total was the first idea, but the recap keeps event notes, not running totals.)
- `/tomte blackjack today` prints the day's tally.

## 2. Running out

- The "House chips" button tops you up **to 500** (not +1,000) and works **once per daily reset**.
- Used today: the button is replaced by "The house refills at reset (in 6h)".
- `stats.refills` keeps counting chips the house gave.
- Start over still gives 1,000 and clears stats; it keeps owned Cashier items (they were bought, not stats).

## 3. The Cashier

A second face of the table window (a "Cashier" button in the title bar; "Back to the table" returns). Two rows of
swatches, each showing a mini preview, its price or how to unlock it, and Buy / Use. Buying asks
`ns.Confirm_Show` first. Can't buy during a hand.

**Card backs** (a pattern drawn in one theme role over a base role; patterns are generated art):

| Back | Cost |
| --- | --- |
| Classic (today's back) | owned |
| Lattice | 2,500 |
| Sunburst | 5,000 |
| Royal (crimson) | 10,000 |
| Midnight (blue) | 25,000 |
| Natural | feat: 50 blackjacks |
| Hot streak | feat: a 10-hand win streak |
| Whale | feat: hold 100,000 chips at once |

**Felts** (the felt texture tinted by a theme role, darkened):

| Felt | Cost |
| --- | --- |
| Green (`success`) | owned |
| Blue (`info`) | 5,000 |
| Crimson (`danger`) | 10,000 |
| Black and gold (`frameDark`, print in `accent`) | 25,000 |

**Rank**, shown under the chip count, from the most chips ever held (`stats.peak`), so spending never lowers it:
Regular (start), High roller (25,000), Whale (100,000).

Feats are checked against the stats, so players who already qualify get them on first load.

## 4. The classic table

The window grows to about 560 x 440. Title bar on top (title, rank, chips, Cashier, close), then the felt:

```
 ________________________________________________________
| [discard]           DEALER CARDS                [shoe] |
|                                                        |
|      ‿‿  BLACKJACK PAYS 3 TO 2  ‿‿                     |   <- large arc, accent, Cinzel
|        Dealer must draw to 16 and stand on all 17s     |   <- small arc, felt print role
|          (  DOUBLE ON ANY TWO CARDS  )                 |   <- ribbon band arc
|                                                        |
|                 YOUR CARDS                             |
|                   ( bet circle with chips )            |
 \______________________________________________________/   <- padded rail, the curved player side
   [10] [50] [100] [500]  Clear        Bet 150   [Deal]
```

- **Felt**: a D-shape (straight dealer edge, curved player side) with a subtle weave, tinted by the chosen felt.
- **Rail**: a padded edge along the curve, `frameDark` with a soft highlight.
- **Print**: three arcs, as above, baked into textures (white, tinted in game). The rule text matches the rules
  (dealer stands on soft 17 = stands on all 17s). No insurance line, since there's no insurance.
- **Betting circle**: a ring in front of your hand. The bet shows as a small stack of chips in it, colored by
  denomination (10 `info`, 50 `danger`, 100 `success`, 500 `heading`). Two circles after a split.
- **Shoe and discard tray**: drawn top right (where cards slide from today) and top left.
- The message line moves off the print (just above the bet controls), so the two never overlap.
- Card backs and felts follow the Cashier choice; all colors stay theme roles.

Art: `tools/games_art.py` gains the felt mask, weave, rail, the three print arcs (Cinzel, OFL, already in
`Media/Fonts`), betting ring, chip, shoe, tray and the back patterns. All white or grey on transparent. New .tga
files need a full client restart.

## 5. Open while in queue

Setting under **Table**, off by default: "Open while you wait in a queue".

- Opens when you're queued for a dungeon, raid or battleground (LFG or PvP queue) and not in an instance.
- Closes when the queue pops (`LFG_PROPOSAL_SHOW`, or a battleground ready to enter), so nothing covers the accept
  button. Also closes if you leave the queue, but only if it opened for the queue (like flights today).
- Combat still hides it and brings it back.

## Files

| File | Role |
| --- | --- |
| `ChipRules.lua` (new, pure) | Payouts, daily/weekly windows, loot cap, refill rules, rank, earned-today text |
| `CashierData.lua` (new, pure) | The catalog (backs, felts), prices, feats, owned/use checks |
| `BlackjackRules.lua` | Refill becomes a top-up to 500 gated by the day; `stats.earned` |
| `Earn.lua` (new, reader) | Flight minutes, quests, Vault, loot gold; pays through ChipRules |
| `Felt.lua` (new, UI) | The felt, rail, print, ring, chip stacks, shoe, tray |
| `Cashier.lua` (new, UI) | The Cashier face |
| `Card.lua` | Back from the chosen pattern and roles |
| `Table.lua` | Uses Felt, new layout, Cashier button, earned floats. 791 lines now: the felt and Cashier go in their own files so it doesn't pass ~900 |
| `Blackjack.lua` | Settings (Earning card, queue), queue events, Start/Stop of Earn |

Saved (all new keys have defaults, no migration needed):

```lua
earn = { flight = true, quests = true, vault = true, loot = true },
queue = false,
look = { back = "classic", felt = "green" },
owned = {}, -- [item key] = true, bought Cashier items
earned = {}, -- { day = <reset time>, today = { flight = n, quest = n, loot = n }, vaultWeek = <reset time>, refillDay = <reset time> }
```

Tests: `tests/test_chiprules.lua`, `tests/test_cashierdata.lua`, and refill cases added to
`tests/test_blackjackrules.lua`.

## To verify on the wiki before building

`QUEST_COMPLETE` with `QuestIsDaily`/`QuestIsWeekly`, the Vault claim signal (`C_WeeklyRewards`,
`WEEKLY_REWARDS_UPDATE`), `C_DateAndTime.GetSecondsUntilDailyReset`/`WeeklyReset`, `GetLFGMode` and
`GetBattlefieldStatus` on 12.1.
