# Casino: Video poker and Slots: plan

Spec: `docs/superpowers/specs/2026-10-22-tomte-video-poker-and-slots-design.md`. Built in one go (delegated), one
combined in-game test, then one commit per task.

1. **Split the window (pure move).** `Modules/Games/Window.lua` takes the shell out of `Table.lua`: frame, title bar,
   chip count, stats tooltip, rank, Cashier swap, refill, sounds, place, the `ns.BlackjackTable_*` API (renamed
   `ns.GamesWindow_*`). `Table.lua` keeps the blackjack face, registered with `ns.GamesWindow_AddFace`. TOC,
   `tools/bugfiles.lua`, tests green, `luac -l` globals check. No behavior change.
2. **Pure rules.** `PokerRules.lua` + `tests/test_pokerrules.lua`; `SlotsRules.lua` + `tests/test_slotsrules.lua`
   (exact return rate by enumeration); `CashierData.lua` takes the game table, feats name their game, two new backs
   (`tests/test_cashierdata.lua` updated).
3. **Window: game tabs.** Tabs in the title bar, `db.lastGame`, faces created lazily, the active face drawn, the
   tooltip's game section from the face, refill and broke text shared.
4. **Video poker face** (`PokerMachine.lua`): screen in the felt color, pay table, five cards (scaled), hold by click,
   coin chips, Bet one, Bet max, Deal/Draw, results with the shared effects.
5. **Slots face** (`SlotMachine.lua`): three clipped reels driven by `ns.GamesFx_Tween`, stop early, paylines with
   `CreateLine`, pay table in chips, bet chips, Spin, results and jackpot banner.
6. **Module.** Name Casino, commands `poker` / `slots`, stats for all games, binding name, Repair of `game.poker` and
   `game.slots`, Start over text.
7. **Docs.** README row (Casino) and commands, CHANGELOG Unreleased lines (after the in-game check), memory.

Checks after each task: all unit tests, `lua Tomte/tools/bugfiles.lua` after TOC edits, `luac -l` on new files.
