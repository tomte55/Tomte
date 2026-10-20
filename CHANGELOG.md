# Changelog

Newest first. Add a line under **Unreleased** with each change; at release time it becomes the version's section
(see "Releasing" in README.md).

## Unreleased

- Gear Check: when a quest lets you choose a reward, a card names the best one for you and the one that sells for the most. With DialogueUI it sits above its window; otherwise move it in Edit Mode. Turn it off under Gear Check, "Reward pick".
- Moments: a new battle pet moment replaces Blizzard's "You have captured" text after a pet battle instead of showing on top of it. Turn it off under Moments, "Replace Blizzard's capture text".
- Moments: the house level moment no longer shows up at random (a burst of levels when the housing dashboard loaded, or while visiting a friend's house). It now shows only when one of your own houses actually levels up.
- New module, Mail: one click opens all your mail (never cash on delivery; Shift-click for gold only), keeps taking gold when your bags are full and sums up the gold and your Auction House sales, purchases, expired and cancelled auctions and outbids. On the Send tab, pick one of your characters or someone you mailed lately.
- New module, Talent check: remembers which saved talent loadout you use in the open world, dungeons, raids, delves and PvP (or in one particular dungeon). Arrive on the wrong one, or get a ready check, and a card offers a one-click switch; switch by hand inside a place and it asks whether to remember that.
- New module, Buff reminders: in dungeons, raids and delves and on ready checks, icons for what you're missing before the pull (food, flask, augment rune, weapon oil or stone, and the group buff your class brings when someone lacks it). Out of combat only; Edit Mode moves them.
- New module, Graphics presets (off by default): a graphics quality level and frame rate cap for the open world, cities, dungeons and delves, raids, PvP and while AFK. Your own settings come back when you leave, change them yourself or turn it off.
- New module, Cursor highlight (off by default): shake the mouse and a ring in your theme's color shows where the cursor is; optionally always in combat or always, with a short trail.
- New module, Housing decor: a Decor page with the housing decor you're missing by source, with search and a turning model. Click one to have Blizzard's tracking lead you there, or get a waypoint to a vendor Tomte has seen (it learns where a vendor stands when you open their shop). Decor tooltips say whether you have it, and Next up and Around you name decor vendors in your zone.

## v1.16.0 - 2026-10-19

- Tomte: when one feature runs into an error, the others reacting to the same game event keep working (the error still shows in BugSack).
- Tomte: a collection scan (Collect here, Holidays) that runs into an error reports it once instead of every frame.
- Everything Tomte won't do in combat now says so the same way ("can't open the journal in combat"), and nothing claims it will happen after combat when it won't.
- A command, key binding or button of a module that's off now says so ("Gathering is off. Turn it on in /tomte.") instead of doing nothing. Forget, reset and clear commands still work while their module is off.
- Map tabs: Tomte no longer opens the world map itself, which could get Blizzard's map blocked in combat afterwards. With the map open, /tomte wq, tp and collect open, Home and the zone toasts switch to their tab; with it closed they say how to get there. Home's location is no longer a map button.
- Esc closes one Tomte window at a time: a dialog over the Tomte window closes on its own. Alt+Z and the AFK screen no longer close the Tomte window.
- Around you shows now lists every block, Delves included; Delves' own switch moved there.
- Settings search also finds words inside each module's settings.
- Settings that depend on another choice show or hide right away.
- 3D previews and the tracker minus button: small fixes (fewer checks while hovering, no stuck scroll drag).
- World quests and Gold world quests: right-click no longer moves the world map (it could get the map blocked in combat afterwards). On the World quests tab right-click stops tracking; in the Gold window it does nothing on a quest.
- Delves: hovering a delve on the Delves page or Home no longer leaves errors behind on Blizzard's map tooltips ("attempt to compare a secret number value").
- Mentions, Trade Filter and Friends Online: names and keywords with accented or Cyrillic capitals (Ásgeir, Örn) now match whatever their case.
- New installs start quieter: Friend sharing off, Mentions without the taskbar flash and chime, Group Alerts ringing once on the sound effects channel. Existing installs keep their settings.
- Group Alerts: new Sound channel setting (Effects or Master); "Repeat every" only shows while repeating is on.
- Setup: a new Social preset (whispers, mentions, friends, group alerts and chat). Presets no longer switch Whispers, Mentions, Friends Online and Group Alerts off, and Crafter also turns on Trade Filter and Chat Tabs.
- Whispers: the inbox shows which of your characters each conversation is with. Unread counts, the Home count and the back-from-AFK recap only count the character you're on; other characters' conversations show "on <name>" and can be read but not answered from here. Battle.net whispers still show on every character.
- Mentions: clicking a mention from a community channel opens that channel's chat line, or says why it can't.
- Trade Filter: "Pause the filter" now lasts until you log out instead of forever.
- Chat Tabs: keeps track of the tab it opened after a character rename or realm transfer.
- Recent: Friend sharing toasts get their own Include checkbox, and Clear on the Home block asks first.
- Pet Health: now for Warlocks (your demon; no reminders with Grimoire of Sacrifice) and Unholy Death Knights (your ghoul, with Dark Transformation timed). New and not tried on those classes yet: tell us if something looks off.
- Hunter Pets: a beast's tooltip no longer calls its family new before Tomte has read your stable; it asks you to visit a stable master instead.
- Session recap: items you buy from a vendor, take from the mailbox, buy at the auction house or get in a trade no longer count as loot, so "loot worth" and the notable loot list show only what you really looted.
- Session recap: the settings show only the slider for the chosen "Keep by".
- Gold & value: turning the module off at the bank no longer saves that character's bank as worth nothing; "Price loot" has a tooltip.
- Material uses: Mythic Keystones and items newer than Tomte's list no longer say "Not used in crafting"; the list is updated for patch 12.1.5.
- Alts: "Deposit for alts" says how many stacks really went into the Warband bank, and why the rest stayed (bank full, no tab bought).
- Vendor Helper and Alts: the vendor toast and the mailbox postage show money in Tomte's style.
- Durability: "When an item breaks" has a tooltip.
- Weekly board: lighter while farming; looting and currency changes only read crests, renown and professions again.
- World quests: a route skips a stop that expired or was done some other way, and steps aside when you track something else (no more taking tracking back on your next hand-in). The Route button then reads "Resume route"; shift-click stops it.
- World quests: clicking a world quest under "Around you" on Home tracks it; the "Big gold is at least" setting reads in gold with commas.
- Delves: if reading the delve entrances fails, the error shows in BugSack and the page no longer retries on every redraw.
- Gathering: the node rings on the minimap cost much less while you stand still or walk.
- Gathering: counts on the Gathering page and tracker use commas.
- Flight: "/tomte flight stats" shows gold spent as plain gold text.
- Teleports: the tab says when all your teleports are in sections hidden in settings, and Home's teleport rows tell you how to use them.
- Pet Battles: the Heal button only shows after a battle when you can heal (Revive Battle Pets learned or a bandage in your bags; the tamer card's button says why not), and its key does nothing while Pet Battles is off.
- AFK Screen: closes for summons, duels, trades, invites and the game's other popups, so you can answer them.
- Dressing room: Target's outfit no longer changes what an open Inspect window shows; with it open on someone else, it asks you to close it first.
- Collect here: the zone toast shows once a day per zone, also after a /reload.
- Almost Done: the tracker does less work while no row is flashing.
- Moments: discovery cards read the game's message in any client language.
- Showcase: keeps your camera in a saved view with no key bound to it (5, else 4 ...), so it never overwrites a view you use; `/tomte showcase view` says which.
- Almost Done, Pet Battles and Moments: tooltips for the settings that had none.

## v1.15.2 - 2026-10-15

- Fishing: the Fishing key knows more of the game's special fishing casts (quest, toy and event fishing), read from the game's own spell data.
- Whispers: linked items in the whisper window show in their quality color (green, blue, purple ...), other links in the theme's accent, so links stand out from the text.
- Gold world quests: a shrunk window no longer takes over the tooltip of what lies below it (bank items, for example); the World quests and Collect map tabs had the same problem over the map.
- Gear Check: with "While leveling, higher item level wins" on, gear with a lower item level than yours is now a downgrade too, instead of an upgrade when only its secondary stats looked better.

## v1.15.1 - 2026-10-15

- Tomte is on CurseForge: install and update it with the CurseForge app.

## v1.15.0 - 2026-10-15

- AFK Screen: "Away for" counts from when you actually left: it includes the 5 idle minutes before the game marks you AFK, and starts at zero when you type /afk.
- Settings: new "Other addons" page under Tomte: every addon Tomte clashes with, works with or can replace (Pawn, InFlight, GoldWQ, WeeklyKnowledge, Pet Battle Scripts), and whether you have it. A module's page shows an amber chip while an addon doing its job is also running.
- Gathering: the world map button's menu can hide single ores and herbs (their Lush, Rich, Crystallized ... variants count as them) on the maps and in routes, and forget the node spots on one map. Pins and the route card name the ore or herb instead of the variant.
- Settings: the group icons on the left show their names underneath instead of sliding out over the module list, so clicking through groups shows each list right away.

## v1.14.0 - 2026-10-14

- Gear Check: while leveling, gear with a higher item level is an upgrade whatever its stats, trinkets and items with effects included (new setting, on by default).
- Gear Check: at max level, an item with stats over a worn one with only an effect says "Likely upgrade: yours has no stats" instead of "Can't judge: new slot".
- Settings: the knob in on/off switches is a little smaller and sits evenly centered in every switch.

## v1.13.1 - 2026-10-14

- Updated for patch 12.1.5: Tomte no longer shows as out of date in the AddOns list.

## v1.13.0 - 2026-10-13

- Whispers: the inbox is resizable and remembers its size and place. Messages are chat bubbles (theirs left, yours right) with a NEW line where the unread ones start, and item links show their tooltip on hover. Conversations have class avatars with an online dot, unread counts, and can be pinned to the top. The header says who they are (level, class and zone, the Battle.net app, offline, or not a friend) with an Invite button. Right-click a conversation to pin, invite, add as a friend, copy it or delete it.
- Toasts: the stack follows where you put it. In the upper half of the screen it grows down, in the lower half up; in the middle of the screen toasts drop in from the top or rise from the bottom. The newest toast sits nearest its spot, and the move handle shows arrows for the direction.
- Toasts: the name stands out from the text under it, and rare toasts read "Drops Teardrop Moth (pet)".
- Menus: dropdown lists and right-click menus (map pins, Alts roster, crafting ranks, Almost Done filters, the mount journal star) are drawn in Tomte's theme, with submenus where needed.
- Questions like "Reset ... to defaults?", "Forget this character?" or "Clear the Recent list?" use a themed dialog: Esc cancels, Enter accepts (except the guard's waypoint question, where Enter stays with your chat box).
- Settings: switches slide, with the accent filling in behind the knob. Cards are no wider than about half a page, so a switch stays near its label on a wide window. Hints in text boxes end in "..." inside the box.
- Settings: a new layout. Modules sit in nine groups on an icon rail that slides out to show the group names when you hover it, with the group's modules listed beside it (search still finds every module). Each module's page opens with its icon, a one-line summary, an on/off switch and the addons it uses, and its settings sit in cards, in two columns on a wide window. Checkboxes are switches, short choices are buttons side by side, and settings that only matter when another is on are indented and dimmed while it's off.
- Gathering: node spots on the minimap are now hollow rings, so the game's own node blip shows inside the ring instead of under our icon. An empty ring means nothing has spawned there.
- Gathering: following a route no longer throws a Lua error each time the map pin changes.

## v1.12.0 - 2026-10-13

- New module, Friend sharing: Tomte shares flight times and gathering node spots with your Battle.net friends who run Tomte, in the background. Their flight times fill in your flight timer and coverage map, and their node spots fill your maps. Your own data always wins. A Friend sharing page lists who shares with you, with a Block switch per friend, and you're told once when a friend runs a newer Tomte. On by default; switch it off in its settings.
- New module, Chat Copy: a copy icon on each chat window (shown while you hover it) opens its text as plain text to copy with Ctrl+C, links shortened to their names. "Clean lines" drops timestamps, channel tags and name brackets. Off by default.
- Gathering: remembers where you mined and picked herbs and shows those spots on the world map, with the ore or herb as the icon and its name on hover. Pick in the settings whether you see spots for your own professions, all of them, or none.
- Gathering: a round button on the world map, under the other map buttons. Left-click for which nodes to show and the Gathering settings, right-click to hide or show the spots.
- Gathering: mining and herbalism on the same run is now a "Mining & Herbalism run" instead of being named after whichever had more nodes.
- Gathering: a route through each zone's node spots, drawn on the world map. Follow it (map button, `/tomte gather follow` or a key binding) and a map pin waits on the next spot, moving on as you reach each one and skipping spots you gathered a few minutes ago; another key skips a spot someone else took. Stopping gives back the quest or pin you tracked before.
- Gathering: node spots on the minimap too, small and see-through so the game's own tracking blips still show. While you follow a route, the route is drawn there as well.
- Gathering: spots you gathered in the last few minutes are dimmed on both maps, and the world map tooltip says when you gathered there.

- New module, Material uses: crafting materials say on their tooltip what they're for, so you know what to bank and what to sell. "Used by Aldric: Blacksmithing (4)" for your characters' recipes, "Also: Alchemy, Leatherworking" for other professions that use it, or "Not used in crafting". Hold Shift for the recipes and who knows them.
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
