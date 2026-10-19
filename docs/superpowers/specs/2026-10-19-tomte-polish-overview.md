# Polish pass: overview

2026-10-19. A read-only audit of the whole addon (five reviewers, one per area) found about 60 issues: a few that
players notice, rough edges, robustness gaps and drift from CLAUDE.md. All 60 unit tests passed at the start and every
pure file had a test. This overview ties the six themed specs and plans together; each pair stands on its own.

## The six parts

| Part | Spec | Plan | Covers |
| --- | --- | --- | --- |
| A | `2026-10-19-tomte-polish-core-design.md` | `../plans/2026-10-19-tomte-polish-core.md` | Core/Panel robustness, Esc handling, settings search, shared combat line, modules-off commands, map tab opening |
| B | `2026-10-19-tomte-polish-social-design.md` | `../plans/2026-10-19-tomte-polish-social.md` | Defaults, setup presets, whisper inbox per character, chat/social fixes, Recent, README and CurseForge text |
| C | `2026-10-19-tomte-polish-class-design.md` | `../plans/2026-10-19-tomte-polish-class.md` | Pet Health for Warlock and Unholy Death Knight, deprecated spec globals, Hunter and Rogue fixes |
| D | `2026-10-19-tomte-polish-economy-design.md` | `../plans/2026-10-19-tomte-polish-economy.md` | Recap loot value, Materials labels, Warband deposit, Value, Weekly refresh cost, money formatting |
| E | `2026-10-19-tomte-polish-travel-design.md` | `../plans/2026-10-19-tomte-polish-travel.md` | World quest route, Delves errors, Gather pins, theme and format drift in the travel modules |
| F | `2026-10-19-tomte-polish-collections-design.md` | `../plans/2026-10-19-tomte-polish-collections.md` | AFK popups, pet tamers (incl. Midnight), Pets and DressUp fixes, Battle.lua split, Showcase camera |

## Decisions taken with the user

- Friend sharing is off by default. Mentions keeps its toast, without taskbar flash or chime by default. Group Alerts
  rings once on the SFX channel instead of three times on Master.
- Changed defaults reach new installs only; existing users keep what they have.
- Whispers: one shared inbox, each conversation tagged with the character it's with. Unread counts and the AFK recap
  count only the current character; other characters' conversations say "on <Name>" with Reply/Invite disabled.
- Pet Health gets Warlock and Unholy Death Knight profiles (shipped untested; a friend checks them).
- Setup presets leave the social modules alone; Crafter adds Trade Filter and Chat Tabs; a new Social preset.
- Actions blocked in combat refuse with one shared wording; nothing pretends to queue.
- The AFK screen ends for summons, role checks, group invites, pet battle matches, duels and trades, as it does for
  queue pops.
- Pet tamers move into `Data/<Expansion>/` and gain Midnight entries (shipped untested).

## Order

1. **A first.** It adds the shared pieces the others use (`ns.Print_Combat`, the modules-off check for commands and
   key bindings, `ns.MapTabs_Open`, the content-kind rule moved out of Hunter into Core) and rewrites every
   combat-refusal line, which touches files in all modules. Doing it first keeps the other plans' edits clean.
2. **F's Battle.lua split** next, as its own pure-move commit, before any Pets behavior change.
3. B, C, D, E and the rest of F in any order. They touch disjoint module folders; where two plans touch the same
   file (Core/Setup.lua in B, Core/Check.lua in A and C, README/CHANGELOG in all), the later one rebases its edit on
   what is there.

## Cross-plan facts (checked after all six were written)

- **Migrations:** A takes 10 (Delves' Around-you switch), B takes 11 (new defaults for new installs only), E takes 12
  (the old minimap `angle`). If they are built in another order, renumber the comment, the test's `schema` and B's
  `NEW_DEFAULTS` to match.
- **Shared names from A:** `ns.Print_Combat`, `ns.Module_RequireOn`, `ns.Module_OffText`, `ns.Module_CommandAllowed`
  and the `whileOff` command flag, `ns.Binding_Add`, `ns.MapTabs_Open(key, mapID)`, `UI.CloseOnEscape`,
  `ns.Check_ContentKind` (replaces `ns.Hunter_ContentKind`), `ns.Home_AroundChoices`, `ns.PanelLayout_Visibility`.
  A also teaches `tests/harness.lua` WoW's `xpcall` with arguments under Lua 5.1.
- **Moments tests:** B moves `FormatToPattern`/`Match` from Moments into `Core/Format.lua` (with their tests out of
  `tests/test_moments.lua`); F adds parser tests to `tests/test_moments.lua`. Whichever runs second edits the file
  as it then stands.
- **Plain white shading** (`SetColorTexture(1, 1, 1, a)`) is allowed by `tests/test_theme.lua` on purpose and stays;
  D and E only fix the literal tooltip text colors.
- **Findings that turned out wrong** (see each spec's "Checked, not changed"): no deprecated spec globals are used
  (they are local copies of `C_SpecializationInfo`); themes only switch on reload, so colors read at creation are
  fine; Gold window retries were already capped; Recent only lacked Friend sharing; no new Midnight pet tamers exist
  (Xu-Fu, 2025-11), so the five Midnight Family Battler sections just move into `Data/Midnight/`; a crash backup of
  camera view 5 can't work, so Showcase borrows an unbound view instead.

## Working rules for all six

- One plan task at a time; the user tests each in game after `/reload` before it is committed (CLAUDE.md).
- A CHANGELOG **Unreleased** line per player-visible fix, written once the user confirmed it in game.
- Findings a plan's author found to be wrong are listed in that spec's "Checked, not changed" section.
- Midnight-only and other-class work (Midnight tamers, Warlock/DK pet profiles) can't be tested by the user; the
  specs say so and the CHANGELOG lines don't claim more than was checked.
