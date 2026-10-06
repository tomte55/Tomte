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
| Minimap Button | General | A button on the minimap's edge that opens the panel (right-click: the Weekly board popup). Drag it to move it. |
| Next up | General | A short ranked list on Home of the best things to do right now: Great Vault rewards waiting, a rare up that drops a mount or pet you're missing, low durability, full Concentration, world quests worth doing, a vault slot one activity away, achievements one step from done, open knowledge sources, materials for your alts. Click one to start it (waypoint, track, open), right-click for "not now". Placement, rows, sources and their priority are settings. |
| Recent | General | Every toast and banner also goes into a Recent list (a rail page with a quick action that counts what's new, or a block on Home), so one you missed can be read and clicked later. Saved across reloads, account-wide or per character, per-toast-type filters, optional dot on the minimap button. |
| Gold & value | General | What things are worth, from Auctionator or TSM (vendor prices without either): loot value on the recap card and the Sessions page, each character's bags and bank in Alts, and material cost, sale price and profit in the Crafting tab. |
| Weekly board | General | What you haven't done this week: Great Vault, crests, weekly quests, profession knowledge and Concentration (toast when full), renown, lockouts. Tabs for this character, an alt grid and professions; alts roll over at the weekly reset without logging in. |
| Alts | General | Every character at a glance and crafting across them (who makes it, materials and where, crafts in order). Send to alt: at a mailbox a "For your alts" panel attaches and sends what your other characters craft with (12 stacks a mail), and at the bank "Deposit for alts" puts it in the Warband bank. Manual rules and gold top-ups are settings. Crafting list: add a craft with its amount from the Crafting tab, and a tracker on screen says what the character you're on has to do ("Grab 10 Iron Ingot from your bank", "Mail 20 Mycobloom to Mira", "Craft 3 Flask: you have everything"); the mailbox sends each craft's exact materials, Baganator marks the items to move, and crafts count down as you make them. |
| Flight Timer | Travel | Times flight paths account-wide and shows a countdown while flying, with an optional cinematic flight mode. Coverage tab and a flight master map show which routes you've timed. |
| Waypoints | Travel | An in-world marker for whatever you track (quest, map pin, POI, rare, corpse): icon, optional beam, name, distance and arrival time. Up close it turns into a card with the objectives; off-screen, an arrow at the edge points to it. Classic or Minimal style. Map pins are tracked as soon as you place them. Replaces WaypointUI. |
| Smart Mount | Travel | One key (Key Bindings > Tomte > Smart Mount) that summons a mount that fits where you are (underwater, flying or ground) from your zone favorites, then journal favorites, then all usable mounts (a favorite list is skipped when nothing in it suits the spot). Pressed again it dismounts (not while flying), leaves a vehicle or leaves travel form / Ghost Wolf. In Undermine it calls the G-99 Breakneck instead (hold Shift for a normal mount). A star in the Mount Journal makes the selected mount a favorite for the zone or continent you're in; the Zones tab lists them. |
| Teleports | Travel | A Teleports tab in the world map's side panel: Hearthstone, a random hearthstone toy, your house, dungeon teleports (this season first, unearned ones greyed out), class teleports and teleport items, with cooldowns. Teleports to the map you're viewing float to the top, with a pin on dungeon entrances. Click to use (out of combat), right-click to favorite. |
| AFK Screen | Ambience | A cinematic screen while you're AFK: orbiting camera, your character, time away, clock, session stats and missed whispers. |
| Session recap | Ambience | What you got done this session: time, gold (and where it came from), notable loot, achievements, rares, tames, levels and renown. A card with the time left during the /camp logout countdown (Esc cancels the logout) and on `/tomte recap`, a highlights page on the AFK screen, and a toast at login for your last session (covers instant logouts). A Sessions page keeps past sessions: a gold-per-hour chart (with loot value), this character / all and this week / all time with totals, optional play nights, and each session's recap card. |
| Moments | Ambience | Title cards for level ups, achievements, new mounts/pets/toys, new zones, renown, campaign chapters, house levels, tamed pets and gear upgrades. Banner or small cinematic; new mounts, battle pets and tames get a centered reveal scaled by rarity (mount rarity via Mount Journal Enhanced). |
| Hunter Pets | Class | Call Pet tooltips, a Stable tab with your pets and a tame log (with 3D models of the beasts you've seen), and a pet check on entering dungeons, raids and delves, and on ready checks. |
| Pet Health | Combat | Pet health bar under your character that glows when your pet needs healing, with Mend Pet and Exhilaration cooldowns and reminders for a dead or missing pet. |
| Whispers | Social | A toast per whisper (click to reply), unread badge, an inbox, and a summary card for whispers received in combat or during a cinematic. |
| Mentions | Social | A toast when someone says your name or a keyword in guild, group, say or channel chat. |
| Friends Online | Social | Who's online at login, and toasts when friends (or watched people and guildmates) come online. |
| Group Alerts | Social | Invites, queue pops, ready checks and summons: a repeating sound on the Master channel until answered, plus a taskbar flash for summons. |
| Gear Check | Gear | Upgrade verdict on item tooltips that checks what Pawn ignores: armor type and main stat, tier set count (and catalyst), lost embellishments and effects, unique limits, upgrade track. Trinkets and items with effects say "sim it" instead of guessing. Built-in stat weights for BM/MM Hunter and Prot Paladin (Raidbots import overrides), upgrades for your other spec, "your best" rank on worn items, best gem for empty sockets, missing enchants. A Gear button on the character sheet opens a panel with the weights in use, the best gem and every worn item missing an enchant or gem. Marks clean upgrades in Baganator. New upgrades (loot, quest rewards, vault, mail) get a reveal moment with the item, and a toast you click to equip it. Replaces Pawn. |
| Almost Done | Achievements | Near-complete achievements in a list docked to the Achievements window: search, threshold, category/expansion/reward filters, reward icons (owned ones greyed out) with a model preview, and a meta browser. A Top 5 tracker (pins first) and toasts when something reaches the threshold, has one step left, or a pinned one moves. Replaces AlmostCompletedAchievements. |
| Vendor Helper | Upkeep | At a vendor: repairs (guild funds first when the withdraw limit covers it) and sells grey items, then one summary toast. Hold Shift while opening the vendor to skip it. |
| Durability | Upkeep | A toast when your worst item drops below a threshold (once per drop) or an item breaks, and a warning when you enter a dungeon, raid or delve with low gear. |

Cinematics never lock your controls: any key or click ends them.

### Commands

Each module's commands are `/tomte <module> <command>`, for example:

- `/tomte flight stats`, `/tomte flight lock` / `unlock`, `/tomte flight testalert`
- `/tomte moments preview mount` (or `levelup`, `zone`, `tame`, `upgrade`, ...); add a tier for creatures and upgrades: `/tomte moments preview mount legendary`
- `/tomte recap` (this session), `/tomte recap last`, `/tomte recap preview`
- `/tomte afk preview`, `/tomte whispers inbox`, `/tomte hunter check`, `/tomte pet unlock`
- `/tomte alerts test`
- `/tomte gear sim` (how to check an item on Raidbots), `/tomte gear import` / `weights` (source, best gem, season) / `clear`, `/tomte gear upgrades` (reveal the upgrades already in your bags)
- `/tomte way test` (pin ahead of you), `/tomte way clear`
- `/tomte ach scan`, `/tomte ach tracker`, `/tomte ach lock` / `unlock`, `/tomte ach test`
- `/tomte vendor last`, `/tomte dura list`
- `/tomte mount why` (context, pool and pick of the last press), `/tomte mount zone`
- `/tomte tp open`, `/tomte tp scan` (what the Teleports tab found)
- `/tomte next list` (what Next up suggests and why), `/tomte next reset` (bring back everything you hid)
- `/tomte alts list` (the crafting list), `/tomte alts tracker` (show/hide the craft tracker)
- `/tomte recent open` / `clear`, `/tomte value price <item link or ID>`
- `/tomte weekly popup` / `board`, `/tomte weekly quests` (learned weekly quests), `/tomte weekly forget <name>`, `/tomte weekly ids` (check crest and knowledge quest IDs)

Key bindings for Smart Mount, whisper reply and the whisper inbox are under **Tomte** in the game's Key Bindings menu.

### Migrating from FlightTimer

Tomte replaces the old standalone FlightTimer addon. If FlightTimer is still installed, Tomte copies its
recorded flight times and keeps its own flight module off. Disable FlightTimer once you've logged in with
Tomte at least once.

## Layout

```
Tomte/
  Tomte.toc, Bindings.xml
  Core/        saved variables, module registry, /tomte, FlightTimer migration, play session
  Cinematic/   shared cinematic engine and banners
  Panel/       settings panel and widgets
  Modules/     one folder per module group (Flight, Travel, AFK, Moments, Hunter, Combat, Social, Gear, Achievements, Upkeep, Mount, Teleports, Weekly, Alts, Recap, Collect, WorldQuests, NextUp, Recent, Value)
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
