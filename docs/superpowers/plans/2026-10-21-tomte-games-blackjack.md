# Games: Blackjack: plan

Spec: `docs/superpowers/specs/2026-10-21-tomte-games-blackjack-design.md`. Another agent is building Trading Post
in parallel, so shared files (TOC, Bindings.xml, README, Core/BugFiles.lua, Flight.lua) are touched last, re-read
right before each edit, with small inserts only.

1. `Modules/Games/CardData.lua` + `tests/test_carddata.lua`: card numbers, rank, suit, shoe, Fisher-Yates.
2. `Modules/Games/BlackjackRules.lua` + `tests/test_blackjackrules.lua`: values (soft aces), new game, deal (with
   reshuffle and dealer peek), actions, hit / stand / double / split, dealer play, settle, stats, refill.
3. `tools/games_art.py` -> `Media/Games/*.tga` (suits).
4. `Modules/Games/Card.lua`: card widget.
5. `Modules/Games/Table.lua`: the window, buttons, paced reveal.
6. `Modules/Games/Blackjack.lua`: module, events (taxi, combat), command, binding, options.
7. Shared files: TOC lines (after Moments), `Bindings.xml` (`TOMTE_BLACKJACK`), Flight cinematic check,
   `lua Tomte/tools/bugfiles.lua`, README row + command + layout.
8. All tests, `luac -l` globals check. In-game test list to the user. CHANGELOG line and commit only after the
   user confirms in game.
