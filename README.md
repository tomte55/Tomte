# Tomte

A World of Warcraft addon for retail **12.1.0** (`## Interface: 120100`), made for a few friends. English only.

## Install

1. Download `Tomte-vX.Y.Z.zip` from the latest [release](../../releases/latest).
2. Unzip it into `World of Warcraft\_retail_\Interface\AddOns` so you get `AddOns\Tomte\Tomte.toc`.
3. Start the game (or `/reload`) and type `/tomte`.

To update, delete the old `Tomte` folder and unzip the new one. Your settings are kept (they live in `WTF`).
What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

Works better with (all optional): Baganator + Syndicator, Auctionator or TradeSkillMaster, Mount Journal Enhanced.

## What it does

One addon with toggleable modules. Type `/tomte` to open the settings panel (also from the minimap
button, the addon compartment or a key binding), or `/tomte help` for all commands. `/tomte version` (also in the window's title bar) says which version you
have: mention it when you report a bug. The panel is resizable and remembers its
size and position.

Home shows your character with its item level, gold, durability and location (hover each for more: missing
enchants, this session's gold by source and the account total, the worst items, coordinates; click to open the
character pane with Gear Check, the Sessions page, the durability list or the world map), the Weekly board, your
characters, Next up, Recent and "Around you" (Collect here, World quests, Teleports, flight masters you haven't
timed a route from with a click for a waypoint, and your mount zone favorites with a click to summon). The rail on
the left shows a small count beside Alts (crafting list steps for this character) and Weekly board (vault rewards
waiting, full Concentration) when there's something to do. "Counts on the rail" and which "Around you" blocks show
are Tomte window settings.

| Module | Category | What it does |
| --- | --- | --- |
| Minimap Button | General | A button on the minimap's edge that opens the panel (right-click: the Weekly board popup). Drag it to move it. |
| Next up | General | A short ranked list on Home of the best things to do right now: Great Vault rewards waiting, a rare up that drops a mount or pet you're missing, low durability, full Concentration, world quests worth doing, a vault slot one activity away, achievements one step from done, open knowledge sources, materials for your alts. Click one to start it (waypoint, track, open), right-click for "not now". Placement, rows, sources and their priority are settings. |
| Recent | General | Every toast and banner also goes into a Recent list (a rail page with a quick action that counts what's new, or a block on Home), so one you missed can be read and clicked later. Saved across reloads, account-wide or per character, per-toast-type filters, optional dot on the minimap button. |
| Gold & value | General | What things are worth, from Auctionator or TSM (vendor prices without either): loot value on the recap card and the Sessions page, each character's bags and bank in Alts, and material cost, sale price and profit in the Crafting tab. |
| Weekly board | General | What you haven't done this week: Great Vault, crests, weekly quests, profession knowledge and Concentration (toast when full), lockouts. Tabs: This week, Factions (renown emblems in progress rings with sub-factions, paragon glow, next rewards on hover, click for the reward track), Activities (Delves keys and shards, Worldsoul weekly, learned weekly quests by zone, Hide completed, a Resources list), Raids (each boss's kills this week per difficulty, collapsible raids), Characters (an alt grid) and Professions; alts roll over at the weekly reset without logging in. |
| Alts | General | Every character at a glance and crafting across them (who makes it, materials and where, crafts in order). Send to alt: at a mailbox a "For your alts" panel attaches and sends what your other characters craft with (12 stacks a mail), and at the bank "Deposit for alts" puts it in the Warband bank. Manual rules and gold top-ups are settings. Crafting list: add a craft with its amount from the Crafting tab, and a tracker on screen says what the character you're on has to do ("Grab 10 Iron Ingot from your bank", "Mail 20 Mycobloom to Mira", "Craft 3 Flask: you have everything"); the mailbox sends each craft's exact materials, Baganator marks the items to move, and crafts count down as you make them. With Auctionator, a "Shopping list" link on the materials headings makes an Auctionator shopping list of what's missing. Recipe items (patterns, plans...) say on their tooltip who knows the recipe or who could learn it. "Gear for" in the Crafting tab keeps only what one character can use (their armor type, weapons their class equips, their main stat, tools for their professions), "you" follows whoever is logged in, and each row marks how the craft's item level compares with what they wear (green +n at every quality, yellow +n only at the higher qualities). Profession gear: a Profession gear tab shows each character's tool and accessories per profession with the best one somebody can craft when it's an upgrade (click to open it in the Crafting tab), "Gear for" marks tools and accessories too, the mailbox's "Gear for <name>" groups include profession gear from your bags that's an upgrade for another character, and a Next up suggestion says when a better tool or accessory can be crafted with the materials on hand. Profession gear is compared by item level; its stats are shown, not weighed. The detailed Characters view shows each max-level character's Great Vault and Concentration (from Weekly); an unlit profession icon says who has a free profession slot; totals include the Warband bank's gold. Each character's worn gear and spec are stored for Gear Check's upgrades for alts: at the mailbox a "Gear for Mira" group attaches the Bind on Equip upgrades for that character, and "Deposit for alts" puts warbound ones in the Warband bank. |
| Flight Timer | Travel | Times flight paths account-wide and shows a countdown while flying, with an optional cinematic flight mode. Coverage tab and a flight master map show which routes you've timed. |
| Waypoints | Travel | An in-world marker for whatever you track (quest, map pin, POI, rare, corpse): icon, optional beam, name, distance and arrival time. Up close it turns into a card with the objectives; off-screen, an arrow at the edge points to it. Classic or Minimal style. Map pins are tracked as soon as you place them, a map pin on another continent is routed through the portals, zeppelins and boats on the way, and a guard's directions can become a map pin (Never, Ask or Always). Replaces WaypointUI. |
| Smart Mount | Travel | One key (Key Bindings > Tomte > Smart Mount) that summons a mount that fits where you are (underwater, flying or ground) from your zone favorites, then journal favorites, then all usable mounts (a favorite list is skipped when nothing in it suits the spot). Pressed again it dismounts (not while flying), leaves a vehicle or leaves travel form / Ghost Wolf. In Undermine it calls the G-99 Breakneck instead (hold Shift for a normal mount). A star in the Mount Journal makes the selected mount a favorite for the zone or continent you're in; the Zones tab lists them. |
| Teleports | Travel | A Teleports tab in the world map's side panel: Hearthstone, a random hearthstone toy, your house, dungeon teleports (this season first, unearned ones greyed out), class teleports and teleport items, with cooldowns. Teleports to the map you're viewing float to the top, with a pin on dungeon entrances. Click to use (out of combat), right-click to favorite. |
| AFK Screen | Ambience | A cinematic screen while you're AFK: orbiting camera, your character, time away, clock, session stats and missed whispers. |
| Session recap | Ambience | What you got done this session: time, gold (and where it came from), notable loot, achievements, rares, tames, levels and renown. A card with the time left during the /camp logout countdown (Esc cancels the logout) and on `/tomte recap`, a highlights page on the AFK screen, and a toast at login for your last session (covers instant logouts). A Sessions page keeps past sessions: a gold-per-hour chart (with loot value), this character / all and this week / all time with totals, optional play nights, and each session's recap card. |
| Moments | Ambience | Title cards for level ups, achievements, new mounts/pets/toys, new zones, renown, campaign chapters, house levels, tamed pets and gear upgrades. Banner or small cinematic; new mounts, battle pets and tames get a centered reveal scaled by rarity (mount rarity via Mount Journal Enhanced). |
| Hunter Pets | Class | Call Pet tooltips, a Stable tab with your pets and a tame log (with 3D models of the beasts you've seen), and a pet check on entering dungeons, raids and delves, and on ready checks. |
| Rogue Poisons | Class | Out of combat, a button appears for each poison missing from your weapons or about to run out (10 minutes by default); click it, or press the "Apply missing poison" key, to apply it. Offers the poison you applied last (Deadly for Assassination, Instant for the others until you pick), two of each with Dragon-Tempered Blades. A poison check on entering dungeons, raids and delves, and on ready checks. Edit Mode moves the buttons. |
| Pet Health | Combat | Pet health bar under your character that glows when your pet needs healing, with Mend Pet and Exhilaration cooldowns and reminders for a dead or missing pet. |
| Whispers | Social | A toast per whisper (click to reply), unread badge, an inbox, and a summary card for whispers received in combat or during a cinematic. |
| Mentions | Social | A toast when someone says your name or a keyword in guild, group, say or channel chat. |
| Friends Online | Social | Who's online at login, and toasts when friends (or watched people and guildmates) come online. |
| Group Alerts | Social | Invites, queue pops, ready checks and summons: a repeating sound on the Master channel until answered, plus a taskbar flash for summons. |
| Gear Check | Gear | Upgrade verdict on item tooltips that checks what Pawn ignores: armor type and main stat, tier set count (and catalyst), lost embellishments and effects, unique limits, upgrade track. Trinkets and items with effects say "sim it" instead of guessing. Built-in stat weights for every spec, for the expansion your character is in (Midnight: sims for damage and tanks, guide priority for healers; The War Within: guide priority; a Raidbots import per character overrides), and at max level a one-time hint and a Next up suggestion to sim your own. Also upgrades for your other specs, "your best" rank on worn items, best gem for empty sockets, missing enchants. A Gear button on the character sheet opens a panel with the weights in use, the best gem and every worn item missing an enchant or gem. Marks clean upgrades in Baganator. New upgrades (loot, quest rewards, vault, mail) get a reveal moment with the item, and a toast you click to equip it. Upgrades for alts: warbound and Bind on Equip gear says on its tooltip which of your other characters it's a clean upgrade for ("Upgrade for Mira (Holy): +8.2%", judged with what they wore, their spec, level and weights when last played; all characters, max level only or off), gets a blue arrow in Baganator when it isn't an upgrade for you, and Bind on Equip pieces show up at the mailbox in Send to alt. Replaces Pawn. |
| Almost Done | Achievements | Near-complete achievements in a list docked to the Achievements window: search, threshold, category/expansion/reward filters, reward icons (owned ones greyed out) with a model preview, and a meta browser. A Top 5 tracker (pins first) and toasts when something reaches the threshold, has one step left, or a pinned one moves. Replaces AlmostCompletedAchievements. |
| Vendor Helper | Upkeep | At a vendor: repairs (guild funds first when the withdraw limit covers it) and sells grey items, then one summary toast. Hold Shift while opening the vendor to skip it. |
| Durability | Upkeep | A toast when your worst item drops below a threshold (once per drop) or an item breaks, and a warning when you enter a dungeon, raid or delve with low gear. |

Cinematics never lock your controls: any key or click ends them.

### Commands

Each module's commands are `/tomte <module> <command>`, for example:

- `/tomte flight stats`, `/tomte flight lock` / `unlock`, `/tomte flight testalert`
- `/tomte moments preview mount` (or `levelup`, `zone`, `tame`, `upgrade`, ...); add a tier for creatures and upgrades: `/tomte moments preview mount legendary`
- `/tomte recap` (this session), `/tomte recap last`, `/tomte recap preview`
- `/tomte afk preview`, `/tomte whispers inbox`, `/tomte hunter check`, `/tomte rogue check` (your poisons and what's missing), `/tomte pet unlock`
- `/tomte alerts test`
- `/tomte gear sim` (how to check an item on Raidbots), `/tomte gear import` / `weights` (source, best gem, season) / `clear`, `/tomte gear upgrades` (reveal the upgrades already in your bags)
- `/tomte way test` (pin ahead of you), `/tomte way clear`, `/tomte way route` (the portal route to a pin on another continent), `/tomte way <x> <y>` (also `/way <x> <y>` when TomTom isn't loaded)
- `/tomte ach scan`, `/tomte ach tracker`, `/tomte ach lock` / `unlock`, `/tomte ach test`
- `/tomte vendor last`, `/tomte dura list`
- `/tomte mount why` (context, pool and pick of the last press), `/tomte mount zone`
- `/tomte tp open`, `/tomte tp scan` (what the Teleports tab found)
- `/tomte next list` (what Next up suggests and why), `/tomte next reset` (bring back everything you hid)
- `/tomte alts list` (the crafting list), `/tomte alts tracker` (show/hide the craft tracker)
- `/tomte recent open` / `clear`, `/tomte value price <item link or ID>`
- `/tomte weekly popup` / `board`, `/tomte weekly quests` (learned weekly quests), `/tomte weekly forget <name>`, `/tomte weekly ids` (check crest and knowledge quest IDs)

Key bindings for toggling the Tomte window, Smart Mount, whisper reply and the whisper inbox are under **Tomte** in the game's Key Bindings menu.

## Layout

```
Tomte.toc, Bindings.xml
Core/        saved variables, module registry, /tomte, play session, which expansion's content a character is in
Data/        hand-kept data per expansion (WarWithin/, Midnight/): weekly activities, crests, raids, gear weights
Cinematic/   shared cinematic engine and banners
Panel/       Tomte window, settings and widgets
Modules/     one folder per module group (Flight, Travel, AFK, Moments, Hunter, Combat, Social, Gear, Achievements,
             Upkeep, Mount, Teleports, Weekly, Alts, Recap, Collect, WorldQuests, NextUp, Recent, Value, Minimap)
tests/       plain-Lua unit tests for the parts that don't touch the WoW API
tools/       dev scripts (waynet.py builds Modules/Travel/Network.lua from Blizzard's waypoint tables)
docs/        design specs and implementation plans
```

`tests/`, `tools/`, `docs/`, `CLAUDE.md` and `.github/` are left out of the release zip (`.gitattributes`).

## Tests

Run from the folder above the repo (the `AddOns` folder) with a standalone Lua interpreter:

```sh
for t in Tomte/tests/test_*.lua; do lua "$t"; done
```

Everything else is tested in game: `/reload`, then check behavior and BugSack for errors. The release workflow runs
the unit tests too.

## Releasing

1. Move the lines under **Unreleased** in `CHANGELOG.md` into a new `## vX.Y.Z - <date>` section.
2. Set `## Version: X.Y.Z` in `Tomte.toc`.
3. Run the unit tests (see Tests), commit (`Tomte vX.Y.Z`), then `git tag -a vX.Y.Z -m "Tomte vX.Y.Z"` and
   `git push origin main vX.Y.Z`.

The GitHub Action checks that the tag matches the TOC and the changelog, runs the tests, zips the `Tomte` folder and
publishes the release with that changelog section as its notes. Versions: patch for fixes, minor for new features
or modules, major for changes that reset or break settings.

## Credits

- Minimap button placement is adapted from [LibDBIcon-1.0](https://www.wowace.com/projects/libdbicon-1-0) (Ace3-style
  BSD license).
- The Weekly board's Factions, Activities and Raids tabs are modelled on [Plumber](https://github.com/Peterodox/Plumber)'s
  Expansion Summary (GPLv3); the progress-ring setup, the Resources list and several ID tables come from Plumber,
  including the Midnight raid, delve, resource, crest and sub-faction IDs.
- Almost Done follows [Almost Completed Achievements](https://www.curseforge.com/wow/addons/almost-completed-achievements);
  Waypoints follows [WaypointUI](https://github.com/Adaptvx/Waypoint-UI); Gear Check reads the
  [Pawn](https://www.curseforge.com/wow/addons/pawn) scale string format that Raidbots exports. No code from them.
- Profession weekly IDs and places from WeeklyKnowledge.
- Built-in stat weights: Midnight from SimulationCraft sims published by mythicsim.com for damage and tank specs and
  the Icy Veins and Method guides for healers; The War Within (Season 3) from the Icy Veins stat priority guides.
  Algari gem and Blasphemite IDs and the display season IDs from [wago.tools](https://wago.tools).
- Waypoints' portal routes use Blizzard's own waypoint network (the WaypointNode, WaypointEdge, WaypointSafeLocs,
  WaypointMapVolume, PlayerCondition and ModifierTree tables) as exported by [wago.tools](https://wago.tools);
  condition logic as documented by TrinityCore and wowdev.wiki.
- Mount rarity in Moments comes from the MountsRarity library bundled with Mount Journal Enhanced.
- Upgrade track IDs (Gear Check's Catalyst note) as used by [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings)
  and [SpartanUI](https://github.com/spartanui-wow/SpartanUI); the G-99 Breakneck's spell IDs from
  [LiteMount](https://github.com/xod-wow/LiteMount)'s notes. Flyout and achievement category IDs from the game data
  on [wago.tools](https://wago.tools).

## License

GPL-3.0, see [LICENSE](LICENSE).
