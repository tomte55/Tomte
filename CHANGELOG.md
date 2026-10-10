# Changelog

Newest first. Add a line under **Unreleased** with each change; at release time it becomes the version's section
(see "Releasing" in README.md).

## Unreleased

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
