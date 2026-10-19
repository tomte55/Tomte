<p align="center"><img src="Media/Logo.svg" width="96" alt="Tomte logo"></p>

<h1 align="center">Tomte</h1>

<p align="center">
One addon for everything around the fighting: your gear, your week, your alts, gold, travel and collecting,<br>
with a cinematic touch. For retail WoW <b>12.1.5</b>. English only.
</p>

![Showcase: your character in the game world with your gear around it](docs/screenshots/hero.png)

Tomte is a set of modules you switch on and off. Everything has a home in one window (`/tomte`), and the rest
lives where you already look: tooltips, the world map, the mailbox, the bags.

## Install

The easy way: install **Tomte** with the CurseForge app ([Tomte on CurseForge](https://www.curseforge.com/wow/addons/tomte)),
which also keeps it up to date.

By hand:

1. Download `Tomte-vX.Y.Z.zip` from the latest [release](../../releases/latest).
2. Unzip it into `World of Warcraft\_retail_\Interface\AddOns` so you get `AddOns\Tomte\Tomte.toc`.
3. Start the game (or `/reload`) and type `/tomte`.

On first login Tomte asks what you want: Minimal, Collector, Crafter or Everything (or choose yourself).
`/tomte setup` brings it back any time.

<p align="center"><img src="docs/screenshots/setup.png" width="560" alt="The setup choice on first login"></p>

To update, delete the old `Tomte` folder and unzip the new one. Your settings are kept (they live in `WTF`).
What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

Works better with (all optional): Baganator + Syndicator, Auctionator or TradeSkillMaster, Mount Journal Enhanced.

## A tour

### Home

`/tomte` opens the Tomte window on Home: your character, what's still open this week, all your characters with their
gold and professions, **Next up** (the best things to do right now, click one to start it), and **Around you**: what
to collect, world quests, teleports and delves where you stand.

![The Tomte window on Home](docs/screenshots/window-home.png)

### Your gear

**Showcase** (`/tomte showcase`) glides the camera in on your character and puts your gear around it: item level,
missing enchants and gems, and your stats. Hover a slot for a card with the item's 3D model and how good it is for
each of your specs; click to swap, socket or enchant.

![Showcase with the card for a ring](docs/screenshots/showcase-card.png)

**Gear Check** puts an upgrade verdict on item tooltips that knows what a simple score doesn't: armor type, main
stat, tier sets, lost effects, unique limits. It says "sim it" when only a sim can tell (while leveling, higher item
level just wins), and which of your other
characters an item would be an upgrade for.

<table>
<tr>
<td><img src="docs/screenshots/gearcheck-tooltip.png" alt="Gear Check: an upgrade"></td>
<td><img src="docs/screenshots/gearcheck-downgrade.png" alt="Gear Check: a downgrade"></td>
</tr>
<tr>
<td align="center">An upgrade, and for which other specs</td>
<td align="center">A downgrade: keep yours</td>
</tr>
</table>

### Your week and your alts

The **Weekly board** shows what you haven't done this week: Great Vault, weekly quests, profession knowledge,
factions, raids, and every alt in one grid.

![Weekly board, This week tab](docs/screenshots/weekly-board.png)

**Alts** keeps every character at a glance and crafts across them: who can make something, which materials are
where, and the crafts in order.

![Alts, Characters view](docs/screenshots/alts.png)

![Alts, Crafting tab: who crafts what, and where the materials are](docs/screenshots/crafting.png)

Put a craft on the **crafting list** and Tomte works out the rest: what to buy (with an Auctionator shopping list),
what each character has to craft first, and what to send where. At a mailbox, **For your alts** attaches what your
other characters need, and material tooltips say who uses them.

<table>
<tr>
<td width="62%"><img src="docs/screenshots/crafting-list.png" alt="The crafting list with shopping and steps"></td>
<td width="38%"><img src="docs/screenshots/material-tooltip.png" alt="A material tooltip with who uses it"></td>
</tr>
</table>

<table>
<tr>
<td width="62%"><img src="docs/screenshots/profession-gear.png" alt="Profession gear per character"></td>
<td width="38%"><img src="docs/screenshots/mailbox-alts.png" alt="For your alts at the mailbox"></td>
</tr>
<tr>
<td align="center">Profession gear: what each character could craft better</td>
<td align="center">At the mailbox</td>
</tr>
</table>

### Getting around

**Waypoints** puts a marker in the world on whatever you track, with distance and arrival time. Walk up to it and it
turns into a card with the objectives. A map pin on another continent is routed through the portals, zeppelins and
boats on the way.

<table>
<tr>
<td><img src="docs/screenshots/waypoints.png" alt="A waypoint from a distance"></td>
<td><img src="docs/screenshots/waypoints-card.png" alt="The same waypoint up close"></td>
</tr>
</table>

The world map gets a side panel: **World quests** sorted by what they're worth to you, **Collect here** with the
mounts, pets and achievements still missing on that map, and **Teleports** with every hearthstone, portal and
dungeon teleport you have.

![World quests tab on the world map](docs/screenshots/map-worldquests.png)

<table>
<tr>
<td><img src="docs/screenshots/map-collect.png" alt="Collect here tab"></td>
<td><img src="docs/screenshots/map-teleports.png" alt="Teleports tab"></td>
</tr>
</table>

Also: **Smart Mount** (one key that picks the right mount for where you are) and the **Flight Timer** (a countdown
on flight paths, or a cinematic flight mode).

### Gold and gathering

**Gold world quests** lists every world quest that pays gold, by zone, with a route through them. **Gathering**
remembers where you mined and picked herbs, shows the spots on the map and the minimap, and can walk you through a
zone's route one spot at a time.

<table>
<tr>
<td width="34%"><img src="docs/screenshots/gold-wq.png" alt="Gold world quests window"></td>
<td width="66%"><img src="docs/screenshots/gathering-map.png" alt="Gathering node spots and a route on the world map"></td>
</tr>
</table>

**Sessions** keeps every play session: time, gold per hour, loot worth, and a recap card for each.

![Sessions page with the gold per hour chart](docs/screenshots/sessions.png)

### The cinematic side

When you go AFK, log out, take a flight or get something new, Tomte gives it a moment. Cinematics never lock your
controls: any key or click ends them.

<table>
<tr>
<td><img src="docs/screenshots/afk.png" alt="AFK screen"></td>
<td><img src="docs/screenshots/recap.png" alt="Session recap card"></td>
</tr>
<tr>
<td align="center">The AFK screen</td>
<td align="center">Session recap</td>
</tr>
<tr>
<td><img src="docs/screenshots/moment.png" alt="A new mount reveal"></td>
<td><img src="docs/screenshots/flight.png" alt="Cinematic flight mode"></td>
</tr>
<tr>
<td align="center">A new mount</td>
<td align="center">Cinematic flight</td>
</tr>
</table>

### And more

Pet battle help (the right pet to swap to, tamer teams, Xu-Fu strategies), Delves, holidays and events, Almost Done
achievements, a bigger dressing room, whisper toasts and an inbox, a trade chat filter, one-key fishing, repairs and
junk selling, and class helpers for hunters and rogues. The full list is below.

## Using Tomte

Open the Tomte window with `/tomte`, the minimap button, the addon compartment or a key binding. `/tomte help` lists
all commands. The window is resizable and remembers its size and position. Every module has its settings in the
window; switch off what you don't want. A command, key binding or button of a module that's off tells you so. In
combat Tomte says what it can't do ("can't open the journal in combat") rather than waiting.

**Reporting a bug:** `/tomte bug` opens a report to copy: versions, which modules are on, related addons and Tomte's
last errors. Nothing is sent anywhere; paste it in a [GitHub issue](../../issues) or a CurseForge comment. `/tomte bug full` adds error details and
your settings string (read it before posting). Install BugSack to catch errors across sessions; without it Tomte
keeps its own last 5. `/tomte bug clear` empties that list. `/tomte version` (also in the window's title bar) says
which version you have.

**Sharing settings:** Tomte window settings > Setup and sharing, or `/tomte profile export` / `import` / `undo`.
Export gives a string of your settings (not your data: no characters, history, flight times or lists). Import shows
what would change, per module, before anything is written; it then reloads. Undo goes back to your settings from
before the last import.

**Other addons:** a page in the Tomte settings (Tomte group) lists every addon Tomte clashes with, works with or can
replace, and whether you have it. Hover a row to see which module cares and why.

<details>
<summary><b>Home in detail</b></summary>

Home shows your character with its item level, gold, durability and location (hover each for more: missing
enchants, this session's gold by source and the account total, the worst items, coordinates; click to open the
character pane with Gear Check, the Sessions page or the durability list), the Weekly board, your
characters, Next up, Recent and "Around you" (Collect here, World quests, Teleports, flight masters you haven't
timed a route from with a click for a waypoint, Delves in your zone, and your mount zone favorites with a click to summon). The rail on
the left shows a small count beside Alts (crafting list steps for this character) and Weekly board (vault rewards
waiting, full Concentration) when there's something to do. "Counts on the rail" and which "Around you" blocks show
are Tomte window settings.

</details>

<details>
<summary><b>All modules</b></summary>

| Module | Settings group | What it does |
| --- | --- | --- |
| Pet Battles | Collections | Help to win pet battles. In a battle, a helper shows the enemy team, which attack types hit the active enemy hard, its attack types, your best pet against it ("Swap to X?") and, in wild battles, rare pets you don't own yet. Talking to a pet tamer shows a card with the team Tomte will use, whether your pets are ready (dead, hurt, too low, missing), Load team, Heal (Revive Battle Pets or a bandage) and Xu-Fu's Pet Guides and Wowhead links. Paste strategies from Xu-Fu (a strategy's "Rematch string"): Load team picks your best copy of each pet and sets the abilities, the steps show during the fight, and a Next move button (key in Key Bindings > Tomte) plays the strategy's script, one press per action. A leveling slot swaps in the next pet from a queue once one reaches 25. A Pet Battles page lists every tamer fight on Xu-Fu's Pet Guides (524), your teams, the leveling queue and a type chart. |
| Minimap Button | Tomte | A button on the minimap's edge that opens the panel (right-click: the Weekly board popup). Drag it to move it. |
| Next up | Tomte | A short ranked list on Home of the best things to do right now: Great Vault rewards waiting, a rare up that drops a mount or pet you're missing, low durability, full Concentration, world quests worth doing, a vault slot one activity away, achievements one step from done, open knowledge sources, materials for your alts. Click one to start it (waypoint, track, open), right-click for "not now". Placement, rows, sources and their priority are settings. |
| Recent | Tomte | Every toast and banner also goes into a Recent list (a rail page with a quick action that counts what's new, or a block on Home), so one you missed can be read and clicked later. Saved across reloads, account-wide or per character, per-toast-type filters, optional dot on the minimap button. |
| Gold & value | Professions & gold | What things are worth, from Auctionator or TSM (vendor prices without either): loot value on the recap card and the Sessions page, each character's bags and bank in Alts, and material cost, sale price and profit in the Crafting tab. |
| Weekly board | Your week | What you haven't done this week: Great Vault, crests, weekly quests, profession knowledge and Concentration (toast when full), lockouts. Tabs: This week, Factions (renown emblems in progress rings with sub-factions, paragon glow, next rewards on hover, click for the reward track), Activities (Delves keys and shards, Worldsoul weekly, learned weekly quests by zone, Hide completed, a Resources list), Raids (each boss's kills this week per difficulty, collapsible raids), Characters (an alt grid) and Professions; alts roll over at the weekly reset without logging in. |
| Alts | Your week | Every character at a glance and crafting across them (who makes it, materials and where, crafts in order). Send to alt: at a mailbox a "For your alts" panel attaches and sends what your other characters craft with (12 stacks a mail), and at the bank "Deposit for alts" puts it in the Warband bank. Manual rules and gold top-ups are settings. Crafting list: add a craft with its amount from the Crafting tab, and a tracker on screen says what the character you're on has to do ("Grab 10 Iron Ingot from your bank", "Mail 20 Mycobloom to Mira", "Craft 3 Flask: you have everything"); the mailbox sends each craft's exact materials, Baganator marks the items to move, and crafts count down as you make them. With Auctionator, a "Shopping list" link on the materials headings makes an Auctionator shopping list of what's missing. Recipe items (patterns, plans...) say on their tooltip who knows the recipe or who could learn it. "Gear for" in the Crafting tab keeps only what one character can use (their armor type, weapons their class equips, their main stat, tools for their professions), "you" follows whoever is logged in, and each row marks how the craft's item level compares with what they wear (green +n at every quality, yellow +n only at the higher qualities). Profession gear: a Profession gear tab shows each character's tool and accessories per profession with the best one somebody can craft when it's an upgrade (click to open it in the Crafting tab), "Gear for" marks tools and accessories too, the mailbox's "Gear for <name>" groups include profession gear from your bags that's an upgrade for another character, and a Next up suggestion says when a better tool or accessory can be crafted with the materials on hand. Profession gear is compared by item level; its stats are shown, not weighed. The detailed Characters view shows each max-level character's Great Vault and Concentration (from Weekly); an unlit profession icon says who has a free profession slot; totals include the Warband bank's gold. Each character's worn gear and spec are stored for Gear Check's upgrades for alts: at the mailbox a "Gear for Mira" group attaches the Bind on Equip upgrades for that character, and "Deposit for alts" puts warbound ones in the Warband bank. |
| Material uses | Professions & gold | Crafting materials say on their tooltip what they're for, so you know what to bank and what to sell: "Used by Mira: Alchemy (3)" for your characters' recipes (from Alts, once a profession window has been opened), "Also: Leatherworking" for other professions that use it, or "Not used in crafting". Hold Shift for the recipes and who knows them. |
| Gathering | Professions & gold | Tracks gathering runs (mining, herbalism, skinning, fishing): nodes and nodes per hour, items with their quality rank, value and gold per hour (from Gold & value), rare finds, skill and knowledge gained, and zones. A run starts with your first gather and ends after 10 minutes without one; mining and herbalism together is a mixed run ("Mining & Herbalism run"). Remembers where you mined and picked herbs and shows those spots on the world map and the minimap (for your professions, all, or off; a round button on the map switches them, hides single ore or herb types, and forgets one map's spots), shared with friends through Friend sharing. Draws a route through each zone's spots and can follow it: a map pin on the next spot that moves on as you reach each one (a key binding starts it and skips a spot), skipping spots you gathered a few minutes ago. A small tracker (Edit Mode moves it), a toast when a run ends, a Gathering page (runs, items, zones), and the recap card and Sessions page show what you gathered. |
| Fishing | Professions & gold | One key (Key Bindings > Tomte > Fishing) casts, and while the bobber is out the same key reels in and loots. Auto loot while fishing, and a press while the loot window is open does nothing. Tomte turns on the game's interact setting while you fish and puts it back after. Optional (settings): louder splash (music and ambience down, effects up), a fishing raft when you're swimming, the Oversized Bobber toy, dismount with the key, and an on-screen button. Replaces Angleur's One Key. |
| World quests | Your week | A tab in the world map's side panel with the world quests on the map you're looking at, grouped by reward and sorted by what they're worth: missing mounts, pets and toys and real gear upgrades (from Gear Check) on top, then gear, gold, currencies and reputation, with time left. Click one to track it. Route tracks the listed quests one by one, nearest first from where you stand (fold a section to leave it out). A toast when you arrive in a zone with one worth doing. |
| Gold world quests | Your week | A window (like GoldWQ) with every world quest that gives gold in your expansion's zones, by zone with zone totals and the grand total, richest first: click to track. Also the special assignments (done, up with time left, or locked with how many world quests until it unlocks) and the weekly caches you haven't done this week (right-click hides one). Route tracks the gold quests one by one, nearest first from where you stand, and moves on when you hand one in. Characters shows each character's world quest gold this week and in all and its caches. A chat line at login with what's up and one per hand-in (both settings). Movable, resizable, foldable; scale and opacity are settings. Follows your expansion (The War Within or Midnight); a menu shows an older one's gold quests instead (Legion to Dragonflight), with Route through them. |
| Delves | Your week | Today's bountiful delves (click one to track it with the Waypoints marker, or a routed map pin on another continent), your Restored Coffer Keys and shards, which delve tier raises your Great Vault's World slots, and your companion's level, role and curios. A note beside Blizzard's tier picker at a delve entrance, a Delves block in Around you, Next up suggestions (bountiful delves while you hold a key, or always) and a companion level moment. |
| Collect here | Collections | A tab in the world map's side panel with the mounts and battle pets (from the journals' source text) and achievements still missing on the map you're looking at. A toast when you arrive in a zone with mounts or pets left, and when a rare that drops one is up. |
| Holidays & events | Collections | The world events on now and starting soon, what you're still missing from each holiday (mounts, battle pets, toys, achievements), the holiday's daily boss and the Darkmoon Faire profession quests. On Home, on an Events page, in Next up, in the Weekly board's "Still open" list, and as a toast when a holiday starts (optionally a day before). |
| Flight Timer | Travel | Times flight paths account-wide and shows a countdown while flying, with an optional cinematic flight mode. Coverage tab and a flight master map show which routes you've timed. |
| Waypoints | Travel | An in-world marker for whatever you track (quest, map pin, POI, rare, corpse): icon, optional beam, name, distance and arrival time. Up close it turns into a card with the objectives; off-screen, an arrow at the edge points to it. Classic or Minimal style. Map pins are tracked as soon as you place them, a map pin on another continent is routed through the portals, zeppelins and boats on the way, and a guard's directions can become a map pin (Never, Ask or Always). Replaces WaypointUI. |
| Smart Mount | Travel | One key (Key Bindings > Tomte > Smart Mount) that summons a mount that fits where you are (underwater, flying or ground) from your zone favorites, then journal favorites, then all usable mounts (a favorite list is skipped when nothing in it suits the spot). Pressed again it dismounts (not while flying), leaves a vehicle or leaves travel form / Ghost Wolf. In Undermine it calls the G-99 Breakneck instead (hold Shift for a normal mount). A star in the Mount Journal makes the selected mount a favorite for the zone or continent you're in; the Zones tab lists them. |
| Teleports | Travel | A Teleports tab in the world map's side panel: Hearthstone, a random hearthstone toy, your house, dungeon teleports (this season first, unearned ones greyed out), class teleports and teleport items, with cooldowns. Teleports to the map you're viewing float to the top, with a pin on dungeon entrances. Click to use (out of combat), right-click to favorite. |
| AFK Screen | Ambience | A cinematic screen while you're AFK: orbiting camera, your character, time away, clock, session stats and missed whispers. |
| Session recap | Ambience | What you got done this session: time, gold (and where it came from), notable loot, achievements, rares, tames, levels and renown. A card with the time left during the /camp logout countdown (Esc cancels the logout) and on `/tomte recap`, a highlights page on the AFK screen, and a toast at login for your last session (covers instant logouts). A Sessions page keeps past sessions: a gold-per-hour chart (with loot value), this character / all and this week / all time with totals, optional play nights, and each session's recap card. |
| Moments | Ambience | Title cards for level ups, achievements, new mounts/pets/toys, new zones, renown, campaign chapters, house levels, tamed pets and gear upgrades. Banner or small cinematic; new mounts, battle pets and tames get a centered reveal scaled by rarity (mount rarity via Mount Journal Enhanced). |
| Hunter Pets | Class & combat | Call Pet tooltips, a Stable tab with your pets and a tame log (with 3D models of the beasts you've seen), and a pet check on entering dungeons, raids and delves, and on ready checks. |
| Rogue Poisons | Class & combat | Out of combat, a button appears for each poison missing from your weapons or about to run out (10 minutes by default); click it, or press the "Apply missing poison" key, to apply it. Offers the poison you applied last (Deadly for Assassination, Instant for the others until you pick), two of each with Dragon-Tempered Blades. A poison check on entering dungeons, raids and delves, and on ready checks. Edit Mode moves the buttons. |
| Pet Health | Class & combat | Pet health bar under your character that glows when your pet needs healing, with Mend Pet and Exhilaration cooldowns and reminders for a dead or missing pet. |
| Whispers | Social & chat | A toast per whisper (click to reply), an unread recap when you're back from AFK, and a summary card for whispers received in combat or during a cinematic. The inbox is a resizable window with your conversations as chat bubbles: class avatars with online dots, unread counts, pinned conversations, a NEW line where unread messages start, who they are (level, class, zone) with an Invite button, and a right-click menu to pin, invite, add as a friend, copy or delete. |
| Mentions | Social & chat | A toast when someone says your name or a keyword in guild, group, say or channel chat. |
| Friends Online | Social & chat | Who's online at login, and toasts when friends (or watched people and guildmates) come online. |
| Friend sharing | Social & chat | Pools flight times and gathering node spots with your Battle.net friends who run Tomte, in the background: their times fill in your flight timer and coverage map, their node spots your world map, and what you know (yours and what friends sent) goes on to your other friends. Your own data always wins. Tells you once when a friend runs a newer Tomte, with the download link. A Friend sharing page lists who shares with you, with a Block switch. |
| Group Alerts | Social & chat | Invites, queue pops, ready checks and summons: a repeating sound on the Master channel until answered, plus a taskbar flash for summons. |
| Trade Filter | Social & chat | Trade and Services (or the channels you pick) show only messages with your keywords: your professions by name and abbreviation (Blacksmithing: BS, smith) plus your own words, minus messages with an ignore word (WTS, boost...). Matched words are highlighted; optional toast per match. Off by default. |
| Chat Tabs | Social & chat | Busy channels in their own chat tab; the main window keeps them (filtered) or drops them. Turning it off restores your chat. Off by default. |
| Channel Tags | Social & chat | Shorter chat tags: [2. Trade - City] as [2. Trade], [2. T], [T] or [2], custom labels, [Guild] as [G] and so on. Off by default. |
| Chat Copy | Social & chat | A copy icon on each chat window (shown while you hover it) opens its text as plain text for Ctrl+C, links reduced to their names. "Clean lines" drops timestamps, channel tags and name brackets. Off by default. |
| Gear Check | Gear | Upgrade verdict on item tooltips that checks what Pawn ignores: armor type and main stat, tier set count (and catalyst), lost embellishments and effects, unique limits, upgrade track. Trinkets and items with effects say "sim it" instead of guessing. While leveling, a higher item level is simply an upgrade (a setting). Built-in stat weights for every spec, for the expansion your character is in (Midnight: sims for damage and tanks, guide priority for healers; The War Within: guide priority; a Raidbots import per character overrides), and at max level a one-time hint and a Next up suggestion to sim your own. Also upgrades for your other specs, "your best" rank on worn items, best gem for empty sockets, missing enchants. A Gear button on the character sheet opens a panel with the weights in use, the best gem and every worn item missing an enchant or gem. Item level on each gear slot of the character sheet and the Inspect window. Marks clean upgrades in Baganator. New upgrades (loot, quest rewards, vault, mail) get a reveal moment with the item, and a toast you click to equip it. Upgrades for alts: warbound and Bind on Equip gear says on its tooltip which of your other characters it's a clean upgrade for ("Upgrade for Mira (Holy): +8.2%", judged with what they wore, their spec, level and weights when last played; all characters, max level only or off), gets a blue arrow in Baganator when it isn't an upgrade for you, and Bind on Equip pieces show up at the mailbox in Send to alt. Replaces Pawn. |
| Showcase | Gear | A character view in the game world: the camera glides in on your character (left of center), the UI fades out, and your gear sits in two columns around it (item level, upgrade track, enchant or "No enchant", gems) with your stats on the right. The camera turns slowly until you drag it; scroll to zoom. Hover a slot for a card with the item's 3D model, stats (with your percent), effects, enchant, gems and Gear Check's verdict (Alt: the full tooltip); click it to swap the item from your bags, socket gems or apply enchants and oils. A yellow diamond marks slots where your bags hold better gear. Opens with `/tomte showcase`, a key binding or its minimap button; Esc or combat closes it and puts the camera back. |
| Dressing room | Gear | Blizzard's dressing room opens bigger (a share of your screen's height, same size every open), with a slot bar under the model (hover for the item, click to hide or show a piece, Shift-click to link it) and buttons to undress, show your target's outfit, and list the outfit with where each piece comes from (to copy). Only hooks Blizzard's window, so its own Link and outfit buttons keep working. |
| Almost Done | Collections | Near-complete achievements in a list docked to the Achievements window: search, threshold, category/expansion/reward filters, reward icons (owned ones greyed out) with a model preview, and a meta browser. A Top 5 tracker (pins first) and toasts when something reaches the threshold, has one step left, or a pinned one moves. Replaces AlmostCompletedAchievements. |
| Vendor Helper | Gear | At a vendor: repairs (guild funds first when the withdraw limit covers it) and sells grey items, then one summary toast. Hold Shift while opening the vendor to skip it. |
| Durability | Gear | A toast when your worst item drops below a threshold (once per drop) or an item breaks, and a warning when you enter a dungeon, raid or delve with low gear. |

</details>

<details>
<summary><b>Commands and key bindings</b></summary>

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
- `/tomte materials why <item link or ID>` (which characters and professions use an item)
- `/tomte pets open`, `/tomte pets import` (paste Xu-Fu strategies), `/tomte pets types` (type chart), `/tomte pets load` (the team for the tamer you're talking to)
- `/tomte weekly popup` / `board`, `/tomte weekly quests` (learned weekly quests), `/tomte weekly forget <name>`, `/tomte weekly ids` (check crest and knowledge quest IDs)
- `/tomte chatcopy` (copy the chat window you last used)
- `/tomte setup` (the module picker), `/tomte bug` (`full`, `clear`), `/tomte profile export` / `import` / `undo`
- `/tomte gather` (the Gathering page), `/tomte gather start` / `end`, `/tomte gather why` (how the last loot window was counted), `/tomte gather nodes` (node spots remembered here and everywhere), `/tomte gather follow` (follow the zone's gathering route, or stop), `/tomte gather skip` (skip the route's next spot), `/tomte gather route` (the route in your zone)
- `/tomte fishing` (options), `/tomte fishing status` (key, reel state and settings waiting to be put back)
- `/tomte wgq` (the Gold world quests window), `/tomte wgq list` / `report` (in chat), `/tomte wgq route` / `stop`, `/tomte wgq reset` (window position)
- `/tomte share list` (friends sharing with you), `/tomte share sync` (ask everyone for what's new now), `/tomte share why <name>` (what was exchanged with that friend)
- `/tomte delves` (the Delves page), `/tomte delves list` (today's delves, bountiful marked, and your keys), `/tomte delves vault` (the Great Vault World plan and tier ladder)
- `/tomte events` (the Events page), `/tomte events list`, `/tomte events calendar` (today's raw calendar rows), `/tomte events ids` (Darkmoon Faire quest IDs with the game's names), `/tomte events test` (sample toast)

Key bindings for toggling the Tomte window, Smart Mount, the Gold world quests window, whisper reply, the whisper inbox, Next pet battle move, Heal battle pets, Apply missing poison, Fishing and Copy chat are under **Tomte** in the game's Key Bindings menu.

</details>

## For developers

<details>
<summary><b>Layout, tests and releasing</b></summary>

### Layout

```
Tomte.toc, Bindings.xml
Core/        saved variables, module registry, /tomte, play session, which expansion's content a character is in
Data/        hand-kept data per expansion (WarWithin/, Midnight/): weekly activities, crests, raids, gear weights
Cinematic/   shared cinematic engine and banners
Panel/       Tomte window, settings and widgets
Themes/      one file per theme (colors, fonts and art by role, registered with ns.Theme.Register)
Media/       logo, theme art and fonts (with their OFL licenses)
Modules/     one folder per module group (Flight, Travel, AFK, Moments, Hunter, Rogue, Combat, Social, Chat, Gear,
             Achievements, Upkeep, Mount, Teleports, Weekly, Alts, Recap, Collect, WorldQuests, NextUp, Recent, Value,
             Minimap, Pets, Fishing, Gather, Delves, Holidays, Share, Materials)
tests/       plain-Lua unit tests for the parts that don't touch the WoW API
tools/       dev scripts (waynet.py builds Modules/Travel/Network*.lua from Blizzard's waypoint tables, events.py
             builds Modules/Holidays/Generated.lua from the client's toy and holiday tables, materials.py builds
             Modules/Materials/Generated.lua from the client's recipe tables, fishing.py lists the fishing channel
             spells for Modules/Fishing/Data.lua, theme_art.py and themes/
             build the themes' art and fonts, bugfiles.lua regenerates Core/BugFiles.lua; artlib.py and wago.py are the
             helpers the art and data scripts share)
docs/        design specs and implementation plans
```

`tests/`, `tools/`, `docs/`, `CLAUDE.md`, `.github/` and `Media/Logo.svg` are left out of the release zip (`.gitattributes`).

### Tests

Run from the folder above the repo (the `AddOns` folder) with a standalone Lua interpreter (the release workflow uses
Lua 5.1, the game's version):

```sh
for t in Tomte/tests/test_*.lua; do lua "$t"; done
```

The tests share their `test`, `eq` and `near` helpers and the exit code through `tests/harness.lua`.

Everything else is tested in game: `/reload`, then check behavior and BugSack for errors. The release workflow runs
the unit tests too.

After adding or renaming a Lua file in `Tomte.toc`, run `lua Tomte/tools/bugfiles.lua` (from the `AddOns` folder) to
regenerate `Core/BugFiles.lua`, the file list `/tomte bug` uses to recognize Tomte's errors; `test_bugreport` fails
until it's done.

### Releasing

1. Move the lines under **Unreleased** in `CHANGELOG.md` into a new `## vX.Y.Z - <date>` section.
2. Set `## Version: X.Y.Z` in `Tomte.toc`.
3. Run the unit tests (see Tests), commit (`Tomte vX.Y.Z`), then `git tag -a vX.Y.Z -m "Tomte vX.Y.Z"` and
   `git push origin main vX.Y.Z`.

The GitHub Action checks that the tag matches the TOC and the changelog, runs the tests, zips the `Tomte` folder and
publishes the release with that changelog section as its notes. When the repo has a `CF_API_TOKEN` secret and
`Tomte.toc` has `## X-Curse-Project-ID`, it also uploads the same zip and notes to CurseForge. Versions: patch for fixes, minor for new features
or modules, major for changes that reset or break settings.

</details>

## Credits

- The Showcase and the Dressing room are inspired by [Narcissus](https://www.curseforge.com/wow/addons/narcissus)'s character view and dressing room (the
  idea only; no code or art from it).
- Minimap button placement is adapted from [LibDBIcon-1.0](https://www.wowace.com/projects/libdbicon-1-0) (Ace3-style
  BSD license; its notice and license text ship in `Modules/Minimap/LICENSE-LibDBIcon.txt`).
- The Weekly board's Factions, Activities and Raids tabs are modelled on [Plumber](https://github.com/Peterodox/Plumber)'s
  Expansion Summary (GPLv3); the progress-ring setup, the Resources list and several ID tables come from Plumber,
  including the Midnight raid, delve, resource, crest and sub-faction IDs.
- Almost Done follows [Almost Completed Achievements](https://www.curseforge.com/wow/addons/almost-completed-achievements);
  Waypoints follows [WaypointUI](https://github.com/Adaptvx/Waypoint-UI); Gear Check reads the
  [Pawn](https://www.curseforge.com/wow/addons/pawn) scale string format that Raidbots exports. No code from them.
  Almost Done's meta achievement IDs, and Light Up the Night's achievements that aren't its criteria, come from
  Almost Completed Achievements' meta data (IDs only).
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
- Pet Battles: the tamer list (`Data/<Expansion>/Pets.lua`) takes from [Xu-Fu's Pet Guides](https://www.wow-petguide.com) its encounter page ids,
  the game's NPC ids for each fight, its section names and the English encounter names. No strategies: Tomte links to
  the site, and strategies are pasted in by you. Team strings follow
  the format [Rematch](https://www.curseforge.com/wow/addons/rematch) and Xu-Fu share. The script interpreter is Tomte's
  own implementation of the [Pet Battle Scripts](https://github.com/axc450/pbs) language (MIT; formerly
  tdBattlePetScript), written from its documented behavior. No code from either addon.
- Fishing: the one-key idea follows [Angleur](https://www.curseforge.com/wow/addons/angleur) by LegolandoBloom (no
  code taken); the fishing channel spell IDs come from the client's spell tables on [wago.tools](https://wago.tools)
  (`tools/fishing.py`).
- Gathering: gathering spell IDs as listed in [GatherMate2](https://github.com/Nevcairiel/GatherMate2)'s collector and
  on Wowhead (IDs only).
- Delves: delve POI, currency, item and companion faction IDs from [Plumber](https://github.com/Peterodox/Plumber)
  (IDs only); Midnight map IDs also from RareScanner.
- Gold world quests is modelled on [GoldWQ](https://www.curseforge.com/wow/addons/goldwq) by DartrilasM (public
  domain): its window, features and its special assignment and route logic were the reference, and its cache item IDs
  come from it. Special assignment and weekly cache quest IDs from [WeeklyRewards](https://github.com/cybertk/WeeklyRewards) by cybertk (MIT); the 11.0 Khaz Algar special assignment quest IDs from [Plumber](https://github.com/Peterodox/Plumber) (IDs only); map IDs from [wago.tools](https://wago.tools).
- Holidays & events: holiday, Dungeon Finder, achievement category and toy source data from the client's tables on
  [wago.tools](https://wago.tools); Darkmoon Faire quest IDs from warcraft.wiki.gg.
- Fonts: [Cinzel](https://github.com/NDISCOVER/Cinzel) by Natanael Gama and
  [Alegreya](https://github.com/huertatipografica/Alegreya) by Juan Pablo del Peral (Huerta Tipográfica), both under
  the SIL Open Font License 1.1 (texts in `Media/Fonts`). `AlegreyaNumbers-Regular.ttf` is a modified Alegreya with
  lining, even-width digits as the default ones, built by `tools/theme_art.py`.
- Theme fonts, all from [Google Fonts](https://github.com/google/fonts) under the SIL Open Font License 1.1 (texts in
  `Media/Fonts`): [Forum](https://github.com/google/fonts/tree/main/ofl/forum) by Denis Masharov (Northrend titles,
  saved as `FrostForum-Regular.ttf`), [Grenze](https://github.com/Omnibus-Type/Grenze) by the Grenze Project Authors
  (Forge titles, a static SemiBold instance), [Uncial Antiqua](https://github.com/google/fonts/tree/main/ofl/uncialantiqua)
  by Astigmatic (Emerald Dream titles) and [Philosopher](https://github.com/alexeiva/philosopher) by the Philosopher
  Project Authors (Void). Their art is generated by the scripts in `tools/themes/`.

## License

GPL-3.0, see [LICENSE](LICENSE).
