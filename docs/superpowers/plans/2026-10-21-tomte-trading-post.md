# Trading Post: plan

Spec: `docs/superpowers/specs/2026-10-21-tomte-trading-post-design.md`. Built in one pass (decisions delegated),
no commit before the user's in-game check.

1. `Modules/TradingPost/Data.lua` (pure) + `tests/test_tradingpost.lua`, test first:
   `TradingPost_Points`, `TradingPost_Milestones`, `TradingPost_ParseProgress`, `TradingPost_SortActivities`,
   `TradingPost_Waiting`, `TradingPost_TimeLeft`, `TradingPost_LoginToasts`, `TradingPost_EndingNote`,
   `TradingPost_PickSpot`, `TradingPost_ShopSummary`, `TradingPost_SortShop`, constants (`TRADINGPOST_CURRENCY`,
   `TRADINGPOST_CITIES`).
2. `Modules/TradingPost/Read.lua`: events bus `ns.TradingPost_Events`, `TradingPost_State()` (log, tender,
   waiting), chest-reward requests (debounced, after login and on activity/threshold changes), shop snapshot
   between `PERKS_PROGRAM_OPEN`/`CLOSE`, owned checks, spot learning, `TradingPost_Waypoint`, `TradingPost_InCity`.
3. `Modules/TradingPost/Page.lua`: the page (tender, log bar + milestones, activities with tracking, shop).
4. `Modules/TradingPost/TradingPost.lua`: register (defaults, options, commands, toasts, page with pill, Next up x2,
   Around you).
5. TOC lines after Delves, `lua Tomte/tools/bugfiles.lua`, all tests, `luac -l` globals check.
6. README row + commands + layout; CHANGELOG line waits for the in-game check.
