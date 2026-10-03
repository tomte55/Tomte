# wow-addons

Personal World of Warcraft addons for retail **12.1.0** (Midnight, `## Interface: 120100`).
Not published anywhere: no CurseForge packaging, no localization.

This repo lives directly in `World of Warcraft\_retail_\Interface\AddOns`. The `.gitignore` ignores
everything and whitelists only our own folders, so third-party addons installed alongside are never tracked.

## Tomte

One addon with toggleable modules. Type `/tomte` to open the settings panel (also from the minimap
button and the addon compartment), or `/tomte help` for all commands. The panel is resizable and remembers its
size and position.

| Module | Category | What it does |
| --- | --- | --- |
| Minimap Button | General | A button on the minimap's edge that opens the panel. Drag it to move it. |
| Flight Timer | Travel | Times flight paths account-wide and shows a countdown while flying, with an optional cinematic flight mode. Coverage tab and a flight master map show which routes you've timed. |
| Waypoints | Travel | An in-world marker for whatever you track (quest, map pin, POI, rare, corpse): icon, optional beam, name, distance and arrival time. Up close it turns into a card with the objectives; off-screen, an arrow at the edge points to it. Classic or Minimal style. Map pins are tracked as soon as you place them. Replaces WaypointUI. |
| AFK Screen | Ambience | A cinematic screen while you're AFK: orbiting camera, your character, time away, clock, session stats and missed whispers. |
| Moments | Ambience | Title cards for level ups, achievements, new mounts/pets/toys, new zones, renown, campaign chapters, house levels and tamed pets. Banner or small cinematic; new mounts, battle pets and tames get a centered reveal scaled by rarity (mount rarity via Mount Journal Enhanced). |
| Hunter Pets | Class | Call Pet tooltips, a Stable tab with your pets and a tame log (with 3D models of the beasts you've seen), and a pet check on entering dungeons, raids and delves, and on ready checks. |
| Pet Health | Combat | Pet health bar under your character that glows when your pet needs healing, with Mend Pet and Exhilaration cooldowns and reminders for a dead or missing pet. |
| Whispers | Social | A toast per whisper (click to reply), unread badge, an inbox, and a summary card for whispers received in combat or during a cinematic. |
| Mentions | Social | A toast when someone says your name or a keyword in guild, group, say or channel chat. |
| Friends Online | Social | Who's online at login, and toasts when friends (or watched people and guildmates) come online. |
| Group Alerts | Social | Invites, queue pops, ready checks and summons: a repeating sound on the Master channel until answered, plus a taskbar flash for summons. |
| Gear Check | Gear | Upgrade verdict on item tooltips that checks what Pawn ignores: armor type and main stat, tier set count (and catalyst), lost embellishments and effects, unique limits, upgrade track. Trinkets and items with effects say "sim it" instead of guessing. Built-in stat weights for BM/MM Hunter and Prot Paladin (Raidbots import overrides), upgrades for your other spec, "your best" rank on worn items, best gem for empty sockets, missing enchants. A Gear button on the character sheet opens a panel with the weights in use, the best gem and every worn item missing an enchant or gem. Marks clean upgrades in Baganator. Replaces Pawn. |
| Almost Done | Achievements | Near-complete achievements in a list docked to the Achievements window: search, threshold, category/expansion/reward filters, reward icons (owned ones greyed out) with a model preview, and a meta browser. A Top 5 tracker (pins first) and toasts when something reaches the threshold, has one step left, or a pinned one moves. Replaces AlmostCompletedAchievements. |
| Vendor Helper | Upkeep | At a vendor: repairs (guild funds first when the withdraw limit covers it) and sells grey items, then one summary toast. Hold Shift while opening the vendor to skip it. |
| Durability | Upkeep | A toast when your worst item drops below a threshold (once per drop) or an item breaks, and a warning when you enter a dungeon, raid or delve with low gear. |

Cinematics never lock your controls: any key or click ends them.

### Commands

Each module's commands are `/tomte <module> <command>`, for example:

- `/tomte flight stats`, `/tomte flight lock` / `unlock`, `/tomte flight testalert`
- `/tomte moments preview mount` (or `levelup`, `zone`, `tame`, ...); add a tier for creatures: `/tomte moments preview mount legendary`
- `/tomte afk preview`, `/tomte whispers inbox`, `/tomte hunter check`, `/tomte pet unlock`
- `/tomte alerts test`
- `/tomte gear sim` (how to check an item on Raidbots), `/tomte gear import` / `weights` (source, best gem, season) / `clear`
- `/tomte way test` (pin ahead of you), `/tomte way clear`
- `/tomte ach scan`, `/tomte ach tracker`, `/tomte ach lock` / `unlock`, `/tomte ach test`
- `/tomte vendor last`, `/tomte dura list`

Key bindings for whisper reply and the whisper inbox are under **Tomte** in the game's Key Bindings menu.

### Migrating from FlightTimer

Tomte replaces the old standalone FlightTimer addon. If FlightTimer is still installed, Tomte copies its
recorded flight times and keeps its own flight module off. Disable FlightTimer once you've logged in with
Tomte at least once.

## Layout

```
Tomte/
  Tomte.toc, Bindings.xml
  Core/        saved variables, module registry, /tomte, FlightTimer migration
  Cinematic/   shared cinematic engine and banners
  Panel/       settings panel and widgets
  Modules/     one folder per module group (Flight, Travel, AFK, Moments, Hunter, Combat, Social, Gear, Achievements, Upkeep)
  tests/       plain-Lua unit tests for the parts that don't touch the WoW API
docs/          design specs and implementation plans
```

## Tests

Run from the `AddOns` folder with a standalone Lua interpreter:

```sh
for t in Tomte/tests/test_*.lua; do lua "$t"; done
```

Everything else is tested in game: `/reload`, then check behavior and BugSack for errors.

## Adding a new addon

Create `<AddonName>/<AddonName>.toc`, then add `!/<AddonName>/` to the whitelist in `.gitignore`.
See `CLAUDE.md` for conventions.
