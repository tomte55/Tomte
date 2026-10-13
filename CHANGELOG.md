# Changelog

Newest first. Add a line under **Unreleased** with each change; at release time it becomes the version's section
(see "Releasing" in README.md).

## Unreleased

- Gathering: remembers where you mined and picked herbs and shows those spots on the world map, with the ore or herb as the icon and its name on hover. Pick in the settings whether you see spots for your own professions, all of them, or none.
- Gathering: a round button on the world map, under the other map buttons. Left-click for which nodes to show and the Gathering settings, right-click to hide or show the spots.
- Gathering: mining and herbalism on the same run is now a "Mining & Herbalism run" instead of being named after whichever had more nodes.
- Gathering: a route through each zone's node spots, drawn on the world map. Follow it (map button, `/tomte gather follow` or a key binding) and a map pin waits on the next spot, moving on as you reach each one and skipping spots you gathered a few minutes ago; another key skips a spot someone else took. Stopping gives back the quest or pin you tracked before.
- Gathering: node spots on the minimap too, small and see-through so the game's own tracking blips still show. While you follow a route, the route is drawn there as well.
- Gathering: spots you gathered in the last few minutes are dimmed on both maps, and the world map tooltip says when you gathered there.

- New module, Material uses: crafting materials say on their tooltip what they're for, so you know what to bank and what to sell. "Used by Tomten: Blacksmithing (4)" for your characters' recipes, "Also: Alchemy, Leatherworking" for other professions that use it, or "Not used in crafting". Hold Shift for the recipes and who knows them.
- Smart Mount: on the water surface where you can fly, the key now summons a flying mount so you can take off. Underwater it still picks a water mount.
- Waypoints: routes through the Wizard's Sanctum portal room now point at the right portal. Inside the room, an arrow over your head turns with you and points at the portal, instead of the marker sending you back out of the building. Leaving the room by its teleporter sends the route back to the entrance.

## v1.11.0 - 2026-10-12

- Showcase: hovering a gear slot shows a card with the item's 3D model, item level and upgrade track, your stats from it (with what each secondary is worth to you in percent), Use/Equip effects, enchant, gems and Gear Check's verdict. Hold Alt for the full game tooltip.
- Showcase: click a gear slot for a menu to swap the item for one in your bags, socket gems and apply enchant scrolls or weapon oils, without leaving the Showcase. The game's "this binds to you" and "replace enchant?" questions are asked right in the menu.
- Showcase: a small yellow diamond marks gear slots where your bags hold something better for your spec.
- Showcase: gear slots only react when the mouse is over the item, not the empty space beside it, and the view now updates when you change gear while it's open.
- New module, Dressing room: Blizzard's dressing room opens bigger (most of your screen's height, same size every time), with a slot bar under the model (click a piece to hide it, Shift-click to link it) and buttons to undress, show your target's outfit and copy the outfit as a list with where each piece comes from.

## v1.10.0 - 2026-10-11

- Minimap Buttons: pick which buttons sit on the minimap's edge in its settings. New: a Gold world quests button that opens its window and shows what's up in its tooltip. Each button is dragged on its own; Reset lines them up.
- New module, Showcase: `/tomte showcase` (or a key binding, or its minimap button) turns the camera on your character, fades the UI out and lays your gear and stats around you: item level, upgrade track, enchants and gems on every slot, an item level dial and your secondary stats as one split bar. The camera turns slowly until you drag it; Esc or combat puts everything back.
- Gear Check: "missing enchant" follows your expansion. War Within characters are no longer told to enchant their helm and shoulders, and do get told about back, wrists and legs.

## v1.9.1 - 2026-10-11

- Pet Battles: the Guides window shows again when you open it from the tamer card while DialogueUI is open (it was invisible, only a grey bar). The copy/paste window got the same fix.

## v1.9.0 - 2026-10-11

- Gear Check: each gear slot on the character sheet and the Inspect window shows its item level in the corner, in the item's quality color (option "Item level on gear slots").

## v1.8.0 - 2026-10-11

- New module, Gold world quests (`/tomte wgq`): a window with every gold world quest in your expansion's zones and their total, special assignments, weekly caches, a route that tracks the gold quests one by one, and world quest gold per character. Like GoldWQ, for The War Within and Midnight; a menu shows older expansions' gold quests too (Legion to Dragonflight).
- World quests: a Route button in the map tab tracks the listed world quests one by one, nearest first, and moves on when you hand one in.

## v1.7.0 - 2026-10-11

- Ready for patch 12.1.5: Tomte no longer uses game functions Blizzard is removing (the mailbox's postage line would have broken).
- Gear Check: the character sheet panel's row highlight now follows your theme.
- Smart Mount: its on-screen messages use your theme's heading color.
- Events page: clicking an achievement in combat now waits, like Collect here ("the journal opens after combat"), instead of trying to open it.
- Waypoints: a card distance of 325 yards no longer resets to 110 at every login.
- The copy/paste window (settings export and import, bug report, team scripts) and Pet Battles' Guides window show
  in front of the Tomte window again instead of behind it.
- Flight masters: "Around you" and the flight map's counts list only the flight masters in your zone (neighbors' ones
  showed up too, and clicking one did nothing). The Flight coverage page files each flight master under its own zone.
- Recent: Gathering, Trade Filter and the Rogue poison check can now be left out under "Include", like the others.
- Gear Check: the Baganator arrow settings describe the arrow colors correctly (they follow your theme).
- `/tomte help` lists `/tomte gather open` instead of a blank Gathering entry; `/tomte gather` still opens the page.
- AFK screen: turning the module off right after a reload no longer leaves the camera zoomed out.
- `/tomte mount why` no longer lists your last clicks (a leftover debugging aid).

## v1.6.0 - 2026-10-11

- Pet Battles: the tamer card (and its Heal button) stays visible when DialogueUI or a similar addon hides the UI
  while you talk to a tamer. Its "No strategy saved" hint no longer gets cut off.
- Pet Battles: Guides is a new window with a Copy button per link and a line saying what each one is for (world
  quest, Family Battler achievement, Trading Post task, Wowhead). When the tamer's world quest is up, its link is
  marked "Active now", comes first and is ready for Ctrl+C. Copied links no longer carry their label into the browser.
- Moments: the level-up moment replaces Blizzard's "You've Reached Level" text instead of showing on top of it. Its
  sound still plays. Turn it off under Moments, "Replace Blizzard's level-up text".
- Moments: each moment can now be set to "Cinematic at max level" (a banner while levelling), replacing the single
  "Cinematics only at max level" checkbox. New zones and campaign chapters play as cinematics at any level by
  default; your current settings carry over unchanged.
- Moments: the zone and subzone names you see when entering an area (and Sanctuary, Contested and so on) now show in
  the Tomte theme instead of Blizzard's text, with smoother changes when you cross several areas quickly. Turn it off
  under Moments, "Zone text in Tomte's style".
- Characters levelling in Chromie Time now see that expansion's content (for example Dragonflight renown on the
  Weekly board's Factions tab) instead of whatever their level alone pointed to.
- Weekly board, Factions: rewards on the reward track highlight on hover and show a tooltip with what the reward is
  and the renown level it unlocks at.
- New Chat category, all off until you turn them on:
  - Trade Filter: Trade chat shows only messages that name your professions (BS, smith, JC...) or your own keywords,
    and hides sellers and boosters. Matches are highlighted, with an optional toast.
  - Chat Tabs: Trade and other busy channels get their own chat tab. Turning it off puts your chat back.
  - Channel Tags: shorter tags such as [2. T] instead of [2. Trade - City], and [G] instead of [Guild].

## v1.5.0 - 2026-10-11

- New installs start with a short welcome: pick Collector, Crafter, Minimal or Everything (`/tomte setup` any time).
- `/tomte bug` makes a bug report to copy, with Tomte's last errors.
- Share settings with friends: Export and Import in the Tomte window settings, with a preview of what changes and an
  Undo.
- New Fishing module: one key to cast and to reel in, with auto loot while fishing, plus optional louder splash,
  raft, Oversized Bobber, dismount and an on-screen button (replaces Angleur's One Key).
- New Gathering module: tracks your mining, herbalism, skinning and fishing runs (nodes, items with ranks, gold per
  hour, rare finds, skill and knowledge, zones) with a small tracker, an end-of-run toast and a Gathering page; the
  recap card and Sessions page show what you gathered.
- New Delves module: today's bountiful delves (click to track), coffer keys and shards, which tier raises your Great
  Vault, your companion's level, role and curios, and a note beside the delve tier picker; plus Next up, Around you
  and a companion level moment.
- New Holidays & events module: what's on now and soon, what you're still missing from each holiday (mounts, pets,
  toys, achievements), the daily holiday boss and the Darkmoon Faire profession quests, on Home, in Next up and as a
  toast when a holiday starts.
- Almost Done's "running events" filter now reads the right month from the calendar.
- The character on the AFK screen, recap card and level-up moment now idles instead of standing frozen.
- The Smart Mount action bar macro now works with a mouse click too, not only with a key.
- Equipping an upgrade from its toast plays the item upgrade sound with the "Equipped" toast (Gear Check setting).
- Ctrl+C in Tomte's copy boxes (bug report, settings string, guide links) copies and closes the box.
- Fixed a Lua error from Gear Check on some item tooltips (`DoesItemExist` usage error).

## v1.4.1 - 2026-10-10

- Fixed an "AddOn 'Tomte' tried to call the protected function" error when a waypoint or world quest was tracked in
  combat with the map open: pins and tracking set in combat now wait until the fight ends.
- Discoveries shown as a moment also hide Blizzard's yellow "Discovered: <area>" line.
- Clicking a gear upgrade toast now confirms with a short "Equipped" toast once the item is worn.

## v1.4.0 - 2026-10-10

- New **Pet Battles** module. In pet battles a helper shows what hits the enemy hard, its attacks and your best pet
  ("Swap to X?"). Talking to a pet tamer shows a card: your team for the fight, whether your pets are ready, Load
  team, Heal and links to the fight on Xu-Fu's Pet Guides and Wowhead. Paste a strategy from Xu-Fu (its "Rematch
  string") and Tomte loads the team, shows the steps during the fight and plays its script with a Next move button
  or key, one press per move. Optional leveling slot with a queue, and a Pet Battles page with every tamer fight,
  your teams and a type chart.

## v1.3.0 - 2026-10-10

- Five more themes in Settings > Tomte window > Theme: **Tomte classic** (the look Tomte had before 1.2: flat
  near-black panels with gold borders and headings), **Northrend** (blue slate, frost-white text, rime in the corner),
  **Forge** (dark iron, ember-orange accent, bronze frames, faint runes), **Emerald Dream** (moss green, jade accent,
  curling vines) and **Void** (indigo night with faint stars, a vivid violet accent). After installing, restart the
  game once (not just a reload) so the new fonts and textures load.
- Pick Tomte's look in Settings > Tomte window > Theme. **Blizzard default** (new, and now the default) looks like
  the game's own tooltips: gold headings, white text, the game's font and tooltip borders. **Cartographer** is the
  map-paper look. "Reload now" switches right away. Background opacity is a Cartographer setting.
- Home no longer reloads your character's model every time the window opens (it floated up into place).
- Settings sliders always show their line, and settings buttons fit their text.
- New look for all of Tomte: a dark, softly textured map-paper background with faint contour lines, thin brown
  frames, Cinzel titles and Alegreya text, and a muted arcane-purple accent for bars, links and selections. Done,
  soon and missing keep their green, amber and red. Russian, Korean and Chinese clients keep the game's own fonts
  where the new ones have no letters for them.
- Almost Done and the Crafting list can be minimized: hover one and click the minus in its top-right corner to
  fold it down to its title (the plus opens it again). It stays folded after a reload.
- Flight cinematics: the character showcase's ground shadow now sits right under the feet for every race and size.
- New Rogue Poisons module (rogues only): a button appears when a poison is missing or about to run out, and one
  click (or the "Apply missing poison" key binding) puts it on. Poison check when entering a dungeon, raid or delve and
  on ready checks.
- Polish and bug pass over the whole addon:
  - Moments no longer throws Lua errors on German clients, and discoveries read the area name correctly in French,
    Italian, Russian and Korean. Recap counts looted stacks right on French and Spanish clients.
  - Moments wait while a window, bag or chat box is open, and a mouse button held while steering no longer ends one
    the moment it starts.
  - Waypoints: a route that can't place its next pin no longer repeats itself in chat; a route waits inside
    dungeons and delves (also over a reload) and picks up again outside; removing and re-placing a pin tries the
    route again.
  - Gear Check: wands count as one-handers, two-handers are compared against a worn off-hand, and the reason line
    for off-hands next to a two-hander makes sense. "Requires level" marks clear right after you level, and
    enchanting or socketing worn gear updates verdicts. Upgrade reveals wait for an item's stats to load.
  - Crafting: one-handed crafts are compared with your main hand when you carry a shield or off-hand item; warriors
    aren't offered bows or guns; short searches show the first 200 rows; "Materials on hand" is much faster.
  - Mailbox and bank: "Deposit for alts" shows with Baganator's bank view; mails never carry gold you typed in
    Blizzard's mail window; a cancelled gold top-up isn't counted; characters on realms you can't mail are left
    out (the Crafting list says to put their materials in the Warband bank); top-ups are sorted by name. Without
    Syndicator the Crafting list says materials on other characters aren't counted.
  - Unspent profession knowledge stays on the current expansion after browsing an older one.
  - Almost Done: pins on achievements that are already done are removed instead of blocking new pins; progress
    shows right after login; the tracker stays hidden after a reload in combat.
  - Collect here: a rare missing two drops names both; progress keeps updating in busy raids.
  - Whispers: unread spam is cleaned up over time; the inbox keeps your scroll position when someone else
    whispers; "While you were away" no longer comes back while you read. Battle.net names show in Recent after a
    relog, and sample toasts stay out of Recent.
  - Friends: adding a friend who's already online, or one only in the Battle.net app, doesn't toast.
  - Weekly board: alts' crests aren't shown as capped after the weekly reset; World quests count the same on Home,
    the map tab and "Around you", and never stay on "loading rewards".
  - Upkeep: equipping an already broken item doesn't say "An item broke"; guild repairs report who paid correctly.
  - Home: the character model no longer blinks on every refresh; "Around you" never shows an empty column.
  - Settings: a checkbox row only toggles on a left click.
  - AFK screen: a preview that turns into a real AFK starts fresh, and a preview ended by combat stays closed.
  - Smaller speed-ups: the Flight bar, Smart Mount macro, Teleports tab, pet health bar, achievement saves and the
    mailbox panel do less work.

## v1.2.0 - 2026-10-10

Routes to other continents, guard directions as map pins, crafting quality picks and Edit Mode support.

- Blizzard's Edit Mode moves Tomte's widgets too: the Almost Done tracker, the Crafting list, the Flight Timer bar,
  the Pet Health bar and the toasts show with a blue box while it's open, ready to drag. The Lock options and
  unlock commands still work.
- Crafting quality: pick the quality you mean to make in the Crafting tab or on a Crafting list card, and gear and
  tools show one item level and a clear upgrade verdict for it. "Compare crafts at" (Profession gear tab and
  Settings) does the same for the Gear for marks, the Profession gear tab and Next up. Click a material to use only
  one rank of it: counts, the to-do, the mailbox and the shopping list follow it. Open each crafter's profession
  window once so every quality's item level is read.
- Waypoints: a map pin on another continent now gets a route. The marker leads you to each portal, zeppelin or boat on
  the way (the same network the game uses for quests, for your faction), then back to your own pin once you're on
  its continent. `/tomte way route` lists the steps; "Route to other continents" turns it off.
- Waypoints: when a guard gives you directions, Tomte can place and track a map pin there. "Waypoint for guard
  directions": Never, Ask (a Yes/No question, the default) or Always.

## v1.1.0 - 2026-10-09

Works whatever expansion you own, plus resets, forgetting old characters and fixes for non-English clients. The
Midnight data hasn't been checked in game yet: if you own Midnight, run `/tomte data` on a level 90 character and
send the output.

- Tomte follows the expansion your character is in (by level, up to what your account owns), so it works whether
  you own Midnight or not, and a Midnight owner's level-80 alts get War Within data:
  - Weekly board: the snapshot is taken at that expansion's max level; Raids come from the Encounter Journal for
    that expansion; Activities, Resources, sub-factions, crests and profession knowledge have Midnight data too. A
    tab without data says so instead of showing nothing.
  - Crests: War Within characters see their Ethereal crests (Mistcrests, which a War Within account never gets,
    used to be the only ones listed).
  - Gear Check: War Within characters get War Within stat weights and Algari gems / Blasphemite advice instead of
    Midnight's; Midnight characters keep theirs. `/tomte gear weights` says which set is used.
- `/tomte data` shows which expansion Tomte follows for you and checks what it knows about it (paste it when
  something looks empty).
- The Tomte window's title bar shows the version, and `/tomte version` prints it with the game build (handy when
  reporting a bug).
- Moments: below max level, cinematic moments (level up, new zone, campaign chapter, gear upgrade) show as banners,
  so levelling isn't interrupted every few minutes. New mounts and tames keep their reveal. "Cinematics only at max
  level" in Moments turns it off.
- Every module has a "Reset to defaults", and the Tomte window page has "Reset all Tomte settings". Both keep what
  Tomte collected (history, alts, flight times, pins, favorites, your watch list and keywords).
- Forget a character everywhere: right-click another character in Alts > Characters, or `/tomte alts forget <name>`
  (or `<name>-<realm>`). Removes it from Alts, the Weekly board, Almost Done, Gear Check, Hunter Pets, Moments,
  Sessions and Recent. A realm-transferred twin with your current name can now be forgotten too.
- `/way` no longer clashes with TomTom: when TomTom is loaded it keeps `/way`, and Tomte's pin is `/tomte way <x> <y>`.
- Teleports: turning the tab on during combat no longer causes an "action blocked" error.
- Non-English clients: Almost Done's profession and holiday filters work, Collect here finds mounts and pets by
  their localized source text, the Hunter tame tooltip skips warlock and DK pets, profession gear shows its stats
  on Russian, Korean and Chinese clients, and Hero's Path dungeon teleports name their dungeon. Other teleport
  destinations show nothing instead of an English guess.

## v1.0.0 - 2026-10-08

First release for friends.

- 25 modules in one addon: Home screen, Weekly board, Alts and crafting list, Gear Check, Almost Done,
  Waypoints, Flight Timer, Smart Mount, Teleports, Collect here, World quests, Next up, Recent, Gold & value,
  Session recap, Moments, AFK screen, Hunter Pets, Pet Health, Whispers, Mentions, Friends Online, Group Alerts,
  Vendor Helper, Durability and the minimap button. See README.md for what each one does.
- Gear Check: an orange "maybe an upgrade" arrow in Baganator for gear whose stats say upgrade but that needs a
  sim or has a warning; the Catalyst hint only for Veteran track and up.
- Vendor Helper: "Use guild funds first" is now off by default.
- Hunter Pets: the dungeon pet check works on non-English game clients.
- Gear Check reads gem and enchant texts it used to skip (gems with two stats like "+N Critical Strike & +N
  Haste", "/"-joined and crafted texts), so more gem hints show.
- Works on non-English game clients: gem and enchant stats, unique-equipped limits, durability, Catalyst tracks,
  dungeon and class teleports, achievement expansions and titles, the G-99 in Undermine. Teleport destinations
  ("to X") are still English only.
