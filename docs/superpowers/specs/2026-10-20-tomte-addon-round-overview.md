# Addon round: overview

2026-10-20. Six new modules picked from a survey of popular and new addons (Raider.io "Must-Have AddOns for
Midnight", NextTier, Zygor 12.1, PCGamesN October 2026). The user picked all six and handed every design decision to
Claude ("pick sensible defaults, we tweak after"). Each module has its own spec and plan; this file holds the defaults
and the rules that tie them together.

| # | Module (key) | Folder | Group | Inspired by | Spec |
| --- | --- | --- | --- | --- | --- |
| 1 | Mail (`mail`) | `Modules/Mail/` | `professions` | Postal (no Midnight update), Mailbox Plus | `2026-10-20-tomte-mail-design.md` |
| 2 | Talent check (`talents`) | `Modules/Talents/` | `class` | MKeysTalents | `2026-10-20-tomte-talents-design.md` |
| 3 | Graphics presets (`graphics`) | `Modules/Graphics/` | `tomte` | PeaversPerformance | `2026-10-20-tomte-graphics-design.md` |
| 4 | Cursor highlight (`cursor`) | `Modules/Cursor/` | `ambience` | CursorGlow, CursorTrail | `2026-10-20-tomte-cursor-design.md` |
| 5 | Buff reminders (`buffs`) | `Modules/Buffs/` | `class` | BuffReminders, Class Reminders | `2026-10-20-tomte-buffs-design.md` |
| 6 | Housing decor (`decor`) | `Modules/Decor/` | `collections` | Home Bound, HomeDecor, DecorDrops | `2026-10-20-tomte-decor-design.md` |

Plans go in `docs/superpowers/plans/2026-10-20-tomte-<key>.md`.

## Defaults Claude picked (the user can tweak after testing)

1. **Mail.** Button-driven, so on by default. An "Open all" button on the inbox takes gold and items letter by letter
   (never COD letters, stops when bags are full, paced so the server keeps up), then prints and toasts a summary
   (gold, Auction House sold/won/expired/cancelled counts) and feeds the session recap. On the send tab: an alt picker
   next to the To box (your characters from the Alts module, same realm/connected realms, current faction) and the
   last recipient remembered. Hardware-event rules for taking mail must be checked on the wiki first; if a press is
   needed per letter, the button becomes "Open next" (one press per letter) instead of a loop.
2. **Talent check.** On by default, quiet: per character and spec, remember which saved loadout you use per kind of
   place (open world, dungeon, raid, delve, PvP), with optional per-instance overrides. On entering an instance or at a
   ready check, out of combat, if the active loadout isn't the one for that place, show a card with "Switch to <name>"
   (one click). When you switch loadouts by hand inside a place, Tomte offers to remember it for that place. Reuses
   `ns.Check_ContentKind`.
3. **Graphics presets.** Off by default (changes CVars). Per situation (open world, city/rested, dungeon/delve, raid,
   PvP, AFK screen) a graphics quality level or "leave alone"; Tomte restores what it changed when the situation ends
   and when the module turns off. Never touches settings outside its list.
4. **Cursor highlight.** Off by default (cosmetic and noticeable). A ring around the cursor in the theme's accent
   color: shown while you shake the mouse (find the cursor), and optionally always in combat or always; optional short
   trail. Size, opacity and modes are settings. No work when nothing is shown beyond a cheap position check.
5. **Buff reminders.** On by default for instances only. Out of combat only, never reads secret values: missing food
   buff, flask/phial, augment rune, weapon oil/stone (not for rogues: Rogue Poisons covers them), and the group buff
   your class provides when someone in the group lacks it. Shown as an icon strip (Edit Mode widget) in dungeons,
   raids and delves and on ready checks; hidden in combat. Consumable IDs live in `Data/<Expansion>/` through
   `ns.Content_Register`. Builds on the readiness checks service (`ns.Check_*`) where it fits.
6. **Housing decor.** On by default (read-only). Shipped before the user owns Midnight, so untested in game until they
   buy it; every housing API is guarded. A Decor page lists decor you're missing by source (vendor, achievement,
   quest, drop, profession), a Next up source for a vendor near you selling decor you lack, a tooltip line "Decor: not
   collected" on decor items, and an Around you entry when a decor vendor is in the zone. Almost Done already shows
   decor achievement rewards; don't duplicate it.

## Rules for all six

- Follow CLAUDE.md exactly (file roles, header comments, theme colors, events while active only, toggle off undoes
  everything, `ns.*` names with the module prefix, tests for every pure file).
- Each module stays inside its own folder, plus `tests/test_<name>.lua` and `Data/<Expansion>/` files it owns.
  Shared files (`Tomte.toc`, `Bindings.xml`, `README.md`, `CHANGELOG.md`, `Core/BugFiles.lua`) are edited once at the
  end by the overseer from each builder's report. A builder that truly needs a Core or Panel change says so in its
  report instead of making it.
- No migrations needed: every module is new and only adds defaults.
- Nothing is committed before the user has tested in game; CHANGELOG lines come after that.
