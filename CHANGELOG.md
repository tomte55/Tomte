# Changelog

Newest first. Add a line under **Unreleased** with each change; at release time it becomes the version's section
(see "Releasing" in README.md).

## Unreleased

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
