# Polish: collections and ambience modules (Pets, Collect, Achievements, DressUp, Showcase, Moments, AFK)

2026-10-19. Part F of the audit follow-up (six spec + plan pairs written in parallel). Plan A (Core/Panel) goes first
and owns `ns.Print_Combat`, the central "module is off" check for commands and bindings, and `ns.MapTabs_Open`
(which fixes the Collect tab open, `Modules/Collect/Tab.lua:350-362`). None of that is repeated here. Holidays was
in this part's scope; the audit found nothing in it, so it isn't touched.

User decisions (final): the AFK screen gives way to more popups, the same way it does for queue pops today; the pet
tamer table moves into `Data/<Expansion>/` through `ns.Content_Register`, keyed by IDs, with Midnight's pet battle
content added (shipped untested: the user owns only War Within content).

## What the player sees

- **AFK Screen** closes (for the rest of that AFK, as for a queue pop today) when one of these needs the UI: a summon,
  a dungeon finder role check or its ready check, an invite to a premade group you applied to, a pet battle PvP
  match, a duel request, a trade request or an opened trade window, a resurrection offer, a guild invite and a
  "someone in your group wants to invite" confirmation. Queue pops, ready checks, party invites and battleground
  pops keep working as before.
- **Pet Battles**
  - The tamer list is unchanged on screen (same sections, same order). The tamer card and the links window show the
    tamer's name in the game's language when the game knows the creature, instead of always English.
  - Midnight: Xu-Fu lists no new tamers or pet battle world quests for Midnight's zones (Xu-Fu news 581, "Midnight
    Pet Compilation", 2025-11-11: "No new tamers will be added to the upcoming/revamped zones"; its Midnight menu,
    checked 2026-10-19, holds only the five old-world Family Battler sections). Those five sections are Midnight's
    pet battle content and already in the table; they move to `Data/Midnight/Pets.lua`. Shipped untested for a
    Midnight owner.
  - Heal button: when you don't know Revive Battle Pets and have no Battle Pet Bandage, the button is greyed out and
    its tooltip says why ("You haven't learned Revive Battle Pets yet: a Battle Pet Trainer teaches it."), and it no
    longer pops up after a battle. Before, it tried `/cast Revive Battle Pets` and failed with the game's error.
  - Turning Pet Battles off stops the Heal key binding (it did nothing visible but could still cast) and the
    after-battle Heal timer.
  - Settings: the Leveling "Slot" dropdown has a tooltip.
- **Collect here**: the "mounts and pets left in this zone" toast shows once per zone per day (it was once per zone
  per session, so every login or `/reload` repeated it).
- **Almost Done**: no visible change; the Top 5 tracker stops running per-frame code while no row is flashing.
  "Hide in combat" gets a tooltip.
- **Dressing room**: "Target's outfit" no longer breaks Blizzard's Inspect window. With the Inspect window open on
  the same player it works and leaves that window's inspect running; open on someone else, it says "close the
  Inspect window first."
- **Showcase**: it no longer overwrites a camera view you use. It borrows the highest of views 5, 4, 3, 2 that has
  no Set View or Save View key bound; when all four are bound it uses none (the camera zooms and tilts back on close,
  but may face another way). `/tomte showcase view` says which view it borrows and why.
- **Moments**: no visible change; a parser error would now reach BugSack instead of being swallowed. Settings: the
  preview "Moment" dropdown has a tooltip.

## Data

- `Data/Midnight/Pets.lua`, `Data/WarWithin/Pets.lua`, `Data/Older/Pets.lua` (new, hand-kept):
  `ns.Content_Register(e, "petSections", { { id, name, kind? }, ... })` in display order and
  `ns.Content_Register(e, "petEncounters", { [xufuID] = { section, name, npcs = { npcID, ... } } })`.
  `e` is the expansion the content was added in (the old `expansion` field, now implied by where it's registered).
  Older registers 4 to 9 each under its own number, as `Data/Older/Gold.lua` does. Names stay Xu-Fu's English page
  labels: they title links to an English-only site and are facts with credit (README Credits says so already).
  Matching never uses them: the card, the store and the guides match by NPC ID.
- `Modules/Pets/Tamers.lua` becomes the pure merger: `ns.Pets_MergeTamers(expansions, get)` builds
  `ns.PETS_SECTIONS` (newest expansion first, file order inside one) and `ns.PETS_ENCOUNTERS` at file load, and
  sets each section's `expansion`. The tamer list is a catalog across all expansions on purpose (a level 80 War
  Within character fights Pandaria tamers too), so it merges every registered expansion rather than following the
  character's. A `/tomte data` check reports this expansion's sections and fights.
- Pets: localized NPC names come from the game's creature cache: `C_TooltipInfo.GetHyperlink` on a
  `unit:Creature-0-0-0-0-<npcID>-0000000000` link, first line. Order: the name the game showed at gossip
  (`db.learned`), then the creature cache (session cache), then the table's label. The tamer list's rows keep the
  labels; its search also matches names already known (learned or cached), without new lookups per keystroke. The
  lookup is gated by an in-game `/dump` first: if it returns nothing, that part is dropped and the plan says so.
- Collect: `zoneToasts = {}, -- [uiMapID] = "YYYY-MM-DD" (local date) the zone toast last showed`. Account-wide like
  the rest of the module's db (the counts are account-wide too). Entries from other days are pruned when a toast is
  marked. In `noShare`. No migration (a new key with a default).
- DressUp: `debug = false` default (with comment, `noShare`). Showcase: `debugCamera = false` default (with comment,
  `noShare`); a comment in both AFK and Showcase defaults that `current` (the live cinematic state, saved for
  `/reload`) has no default on purpose.
- AFK: `ns.AFK_INTERRUPTS` in `Modules/AFK/Data.lua`: event -> `true` or `{ arg = n, value = v }`; every name and
  payload checked on warcraft.wiki.gg 2026-10-19:
  - `LFG_PROPOSAL_SHOW`, `READY_CHECK`, `PARTY_INVITE_REQUEST` (already handled; moved into the table)
  - `CONFIRM_SUMMON: summonReason, skippingStartExperience`
  - `LFG_ROLE_CHECK_SHOW: isRequeue`, `LFG_READY_CHECK_SHOW: isRequeue`
  - `LFG_LIST_APPLICATION_STATUS_UPDATED: searchResultID, newStatus, oldStatus, groupName` -> only `newStatus ==
    "invited"`
  - `PET_BATTLE_QUEUE_PROPOSE_MATCH` (no payload), `DUEL_REQUESTED: playerName`
  - `TRADE_REQUEST: name`, `TRADE_SHOW` (no payload): both, as a trade usually opens straight away
  - `RESURRECT_REQUEST: inviter`, `GUILD_INVITE_REQUEST: inviter, guildName, ...`,
    `GROUP_INVITE_CONFIRMATION` (no payload)
  - `UPDATE_BATTLEFIELD_STATUS` stays in `AFK.lua` (it needs `GetBattlefieldStatus(index) == "confirm"`).
  Considered and left out: `LFG_LIST_APPLICANT_LIST_UPDATED` (an applicant to your own listing: no popup, the eye
  just flashes). Registration skips any name `C_EventUtils.IsEventValid` rejects, so a renamed event can't break the
  module.

## Code

- **Split first**: `Modules/Pets/Battle.lua` (948 lines) loses its game readers (round cache, the interpreter's live
  `api`, `ReadSide`, lines 96-260) to a new `Modules/Pets/Read.lua`, verbatim, before any Pets behavior change.
  Exports `ns.PetsRead_Init(db)`, `ns.PetsRead_Cache`, `ns.PetsRead_ResetCache`, `ns.PetsRead_Api`,
  `ns.PetsRead_Side`. TOC: after `Journal.lua`, before `Battle.lua`. Commit "Split Pets Battle into Battle and
  Read (pure moves)".
- `Modules/Pets/Journal.lua`: `ReviveKnown()` via `C_SpellBook.IsSpellKnown(REVIVE)` (checked on the wiki);
  `ns.PetsHeal_CanHeal()`; Refresh sets no action when neither spell nor bandage is there; `ns.PetsHeal_Disarm()`
  (out of combat: clears the secure button's `type`/`macrotext`, hides it, cancels `healTimer`) and an `armed` flag
  so Refresh does nothing while off. `ns.PetsHeal_Ensure()` re-arms and refreshes on every enable (before, it only
  refreshed the first time, so re-enabling would have left a disarmed button).
- `Modules/Pets/Battle.lua` toggle(false): disarms; if that's in combat (a secure button's attributes can't change
  then), it keeps `PLAYER_REGEN_ENABLED` alone registered and disarms once combat ends. The binding is a
  `CLICK TomtePetHeal:LeftButton` on a secure button: Plan A's central off-check can't stop it, which is why the
  button itself is disarmed.
- `Modules/DressUp/Tools.lua`: owns the inspect only when it started it and `InspectFrame` isn't showing; never
  calls `ClearInspectPlayer` while `InspectFrame` is shown.
- `Modules/Collect/Data.lua`: `ns.Collect_ZoneToastDue(seen, mapID, today)`, `ns.Collect_MarkZoneToast(seen,
  mapID, today)`.
- `Modules/Achievements/Tracker.lua`: the row's OnUpdate is set when a flash starts and cleared when it ends.
- `Modules/Moments/Moments.lua`: no `pcall` around `ns.Moments_DiscoveredArea`. The parser already copes with every
  client format tested (deDE, frFR, esES, ruRU with `|4...;`, koKR with `|1...;`, zhCN; real strings from wago.tools
  GlobalStrings, build of 2026-10-19); the new tests pin that, plus odd inputs that must return nil, not error.
- `Modules/Showcase/Data.lua`: `ns.CharShow_PickView(bound)`; `Showcase.lua` passes its result as `saveView`
  (nil = the engine's zoom/pitch restore, already there for the AFK screen).

## Checked, not changed

- Showcase: "persist the player's original view 5 to db and restore it after a crash" can't work. No API reads a
  saved view's position (`SaveView`/`SetView`/`ResetView` only, checked on the wiki), so there is nothing to back up;
  and SavedVariables are written only on logout or `/reload`, never on a crash. The engine already persists
  `state.savedView` for `/reload` and goes back to it (`Cinematic/Engine.lua` `C.Exit`); that part stays. Picking a
  view the player doesn't use replaces the backup idea.
- Moments: the parser needed no fix for any tested locale; only the `pcall` goes.
- Pets tamer names: no tamer matching uses English strings (all by NPC ID), so nothing else needed rewiring.
- Holidays: no findings.

## Testing

Unit tests: `test_pets` (merge order, expansions set, no duplicate encounter IDs, same tables as before the move,
creature link), `test_afk` (interrupt rules), `test_collect` (once per day, pruning), `test_moments` (six locales,
odd inputs), `test_showcase` (view picking). In game (user, level 80 in War Within content): AFK popups (duel and
trade from a friend, summon), Heal button with and without the spell on an alt, Pets off -> Heal key does nothing,
Target's outfit with the Inspect window open, Collect toast across a `/reload`, Showcase with a key bound to Set
View 5, `/tomte data` pet check, a localized tamer name (if a non-English client is at hand; else `/dump` of the
lookup).
