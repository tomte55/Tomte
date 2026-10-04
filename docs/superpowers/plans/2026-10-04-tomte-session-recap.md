# Session recap: implementation plan

Spec: `docs/superpowers/specs/2026-10-04-tomte-session-recap-design.md`. Executed inline (the build was delegated).
TDD for the pure files: write the tests in `tests/test_recap.lua` first, then the code.

1. **Core session (pure)**
   - Write `Core/SessionData.lua`: `Session_New(guid, now, money, level, xp)`,
     `Session_Begin(db, guid, isInitialLogin, baseline)` (rollover into `sessionLast`), and
     `Session_Migrate(db)` (`afk.session` → `session`).
   - Tests: initial login, reload, another character, migration.
2. **Core session (events)**
   - Write `Core/Session.lua`: `PLAYER_ENTERING_WORLD`, `PLAYER_MONEY` (moneyNow + `ns.Session_OnMoney`),
     `PLAYER_XP_UPDATE`/`PLAYER_LEVEL_UP`, and `PLAYER_LOGOUT` (seen).
   - Add `ns.Session_Current`, `ns.Session_Last` and `ns.Session_Note`.
   - Hook it up from `Core.lua` (`ns.Session_Init(db)` after migration) and add it to the TOC.
3. **AFK switch-over**
   - Remove `EnsureSession` and `ns.afkDB.session`, and read `ns.Session_Current()` instead.
   - Add the extra Highlights page via `ns.Recap_AFKPage()` (controlled by the Recap option "On the AFK screen").
4. **Recap pure logic**
   - Write `Modules/Recap/Data.lua`: AddNote, GoldAttribute, GoldSources, MoneySource, Counts, Duration, SummaryLine,
     Highlights, Worth, IsRareVignette, LootPatterns/LootLink, RowLabel. Tests first.
5. **Tracking**
   - Write `Modules/Recap/Track.lua`: money context (loot/merchant/mail/AH), `CHAT_MSG_LOOT` with a quality check
     (with retry for uncached items), the rare candidates (vignettes, target, mouseover), and kills (target died,
     party kill, loot source).
6. **Hooks**
   - Moments (achievement, mount, pet, toy, renown), Gear Reveal (upgrade) and Hunter Stable (tame) call
     `ns.Session_Note`.
7. **Card scene**
   - Write `Modules/Recap/Scene.lua`: top band, highlights list, bottom band, countdown label.
8. **Module**
   - Write `Modules/Recap/Recap.lua`: registration, options, commands (fallback "" = this session, `last`, `preview`),
     the camp/quit/cancel handling, the login toast, and the ticker for the card lifetime.
9. **Docs and tests**
   - Update the TOC order, README (module table + commands + tests) and the spec's "changes during the build".
   - Run every `tests/test_*.lua`, then do a static check (luac -p if available).
