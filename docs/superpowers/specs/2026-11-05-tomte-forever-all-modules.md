# Tomte on World of Warcraft: Forever: every module that can work there (2026-11-05)

The user asked for Tomte to be as complete as it can be on Forever and left the decisions to Claude. This replaces the
"After launch" list in `2026-10-25-tomte-forever-design.md`, which was written before launch.

## What launch day corrected

The launch spec assumed "a Classic-style client". It isn't. Blizzard's UI source for Forever (branch `forever` of
https://github.com/Gethe/wow-ui-source, 1.60.1.70790) shows the game type `camelot` on the retail engine:

- Nearly every `C_*` API and event Tomte calls exists. An API check can't rule a module out; whether a system has content
  on Forever can. A name existing in the API docs does not mean the system is live.
- `[Game]\` files in Blizzard's TOCs are camelot overrides (in `Camelot/` folders); `mainline` in a TOC includes camelot
  unless it says `ExcludeLoadGameType camelot`; `standard` is retail only.
- Loaded there: Edit Mode, Collections (mounts, pets, toys, heirlooms, wardrobe), Professions (no profession book),
  talents and specs (`PlayerSpells`), Achievements UI with the Legacy System, Calendar, Auction House, a Vanilla-style
  group finder frame, Bags, Stable, Inspect, ranged slot (`C_PaperDollInfo.IsRangedSlotShown`).
- Not loaded: Housing, Delves, Encounter Journal, Mythic+ (`ChallengesUI`), landing page.
- warcraft.wiki.gg: level cap 60, nine classes, no flying, no Dungeon Finder or summoning stones, collections are
  account-wide, transmog is optional, achievements are replaced by Legacy Challenges, dual spec at 40.

## Rule for including a module

As the launch spec: a Forever player never sees a module or setting that does nothing or errors. If it doesn't work
there, it isn't loaded. Retail behavior stays identical (`ns.FOREVER` checks only).

## The set

| Module | Decision |
| --- | --- |
| Gear Check | Forever version (done: `Modules/Gear/Forever*.lua`) |
| Bags, Item counts | bring over |
| Smart Mount, Teleports | bring over; no flying; `Core/Journal`, `Panel/Entries`, `Panel/ModelPreview` come back |
| Alts | bring over |
| Achievements, Moments, Recap, Holidays | bring over |
| Dressing Room, Showcase, Talents | bring over |
| Hunter, Rogue, Combat, Buffs | bring over |
| Waypoints, Instances, Collect, Gathering, Tooltip extras, Graphics, Performance | bring over what has content |
| Decor, Delves, Prey | left out: Blizzard's UI for them doesn't load |
| World Quests, Gold Quests, Weekly, Summary | left out: retail endgame content and data |
| Pets, Trading Post | left out until the game shows them live (pet battles and the shop aren't confirmed) |
| Material Use | left out: generated from retail's recipe data |

## Outcome of the build (from Blizzard's source; game test still to come)

| Module | On Forever | Cut there |
| --- | --- | --- |
| Bags, Item counts | yes; bank tabs are bag slots, keyring shown in the bag window | scrapper, catalyst, upgrade and socket auto-open, battle pet level, keystone and decor categories |
| Smart Mount | yes; ground only | G-99, repair and passenger mounts, flying rules; shaman has no form on the move |
| Teleports | yes; Hearthstone, class spells, two engineering items (`Data/Forever/Teleports.lua`) | Hero's Path, dungeons, house, hearthstone toys |
| Alts | yes; roster, crafting, list, mailbox, tooltips | profession gear tab, "Gear for"; Warband deposit only if the client has that bank |
| Almost Done | yes; on Legacy Challenges in `LegacySystemFrame` | expansion, world event and decor filters, metas |
| Moments | yes | companion, campaign, house, gear upgrade; renown becomes Legacy reward |
| Session recap | yes | |
| Dressing room | yes, with the ranged slot | Catalyst, ensemble counts, title search |
| Showcase | yes, with the ranged slot and its own stats | secondary bar, upgrade track, sockets, rank box |
| Talent check | yes, through dual spec (no loadouts there) | |
| Hunter Pets | yes; happiness and loyalty added | pet specs, Call Pet 2-5 |
| Rogue Poisons | yes; poisons are bag items (`Modules/Rogue/Forever.lua`, `Data/Forever/Rogue.lua`) | lethal and non-lethal rows |
| Pet Health | yes; Hunter and Warlock | Death Knight |
| Buff reminders | yes; food, weapon oil, group buffs | flask, rune, Battle Shout |
| Waypoints | yes | portal routes (`Network*`, `Route`, `Router`), countdown |
| Instances | lockout banner only | difficulty badge and picker, queue plate, holiday pick |
| Gathering | yes; node maps fill in as you gather | knowledge drops, soil, seeds |
| Tooltip extras | reagents of combine items, no use left | keys, tokens, vendors, choice windows |
| Graphics, Performance | yes | |
| Material uses | yes; its table is generated from Forever's own recipes (`GeneratedForever.lua`, `tools/materials.py 1.60.1.70790`) | |
| Collect | **left out**: mount and pet catalogs can't be verified there | |
| Holidays | **left out**: retail data; no sign of scheduled holidays in the source | |

The world map's side panel exists there but Blizzard hides all its tabs, so `Panel/MapTabs.lua` adds a Quests tab of our
own on Forever, and Home's map entries are back.

## Content data

`ns.ContentExpansion` answers `ns.CONTENT_FOREVER` on Forever, whatever the client's expansion numbers say, so a Forever
character never reads retail's data. Forever's own data goes in `Data/Forever/` through `ns.Content_Register`.

## Testing

Nothing can run outside the game. One batch, one test list, BugSack empty; fixes in a loop. No commit before that.
