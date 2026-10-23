# EnhanceQoL + Plumber takeover: status and what's left

Handoff for the next session (written 2026-10-23). Read with the spec,
`docs/superpowers/specs/2026-10-22-tomte-enhanceqol-plumber-absorption-design.md`, and CLAUDE.md.

## Done (on main, pushed)

| Commit | What |
| --- | --- |
| 993b652 | Step 0: twelve settings groups (`quests`, `chat`, `interface` added), scrolling sidebar rail |
| 3b858ec | Gear Check: `ns.GearRewards_BestChoice` for Quests' reward pick |
| d52e3d6 | Phase 1: Quests module (`Modules/Quests/`, off by default) |
| 2bc33d8 | Phase 2: Loot module (`Modules/Loot/`, on by default) |
| 367fc47 | Phase 3: Instances module (`Modules/Instances/`, on by default) |
| 5453431 | The phases 0-3 plan |

CHANGELOG **Unreleased** has a `### New` line for each module and an `### Improved` line for the settings groups,
next to the earlier Flight Timer games drawer line.

## Release: on hold

No release until the takeover phases are done **and** the Flight Timer games drawer (7ec7714) holds something
besides the Casino. The user's decision, 2026-10-23. Don't tag a version before both are true.

## Not yet confirmed in game

The user asked to commit these before checking them. Ask for a check before building on top of them:

- **Quests:** everything (it's off by default, so it hasn't been tried). Turn it on, then: accept and turn in,
  Shift to skip, the gossip pick, the reward pick with Gear Check, event sign-up gossip, cinematic skip, Talking Head
  modes, race medals at a skyriding timekeeper, quest item tooltips, the portrait menu's ignore entry,
  `/tomte quests why`.
- **Instances:** the queue plate by the queue eye (time, "avg M:SS" or "M:SS over avg", role icons that light up),
  the minimap badge on the rim at the top-right (and on a square minimap), the portal card, the lockout banner, the
  holiday dungeon pick, `/tomte instances why`.
- **Loot:** checked in game are List with auto loot and the Feed. Not checked: the Card style, the feed merge with
  its count-up, the Take all keycap and the E key while looting, loot pop-ups as feed lines, the boss loot banner
  choices, Edit Mode placement of the window and the feed.

## Measured while fixing Loot (keep these)

- With fast loot (LootSlot on LOOT_READY), every slot can be taken before LOOT_OPENED. LOOT_OPENED then finds the
  loot empty, or comes after LOOT_CLOSED. So with auto loot the window opens on LOOT_READY from the slots read
  there. A late LOOT_OPENED that finds nothing left is ignored, and a slot that reads empty keeps what it held.
- Fast loot can empty slots without LOOT_SLOT_CLEARED. When the loot closes under auto loot, every slot that isn't
  locked counts as taken.
- Plumber's loot window unregisters LootFrame's events. Tomte then shows no window and doesn't fast loot either
  (taking the slots first left Plumber's window empty).

## Where the build differs from the spec

- Instances: the queue "ring" became a small themed **plate** (the user found the dot ring ugly).
- Instances: the difficulty badge sits **on the minimap rim** (45°, top-right), not in Blizzard's flag spot.
- Loot: "Where it came from" (`extras.source`) is **off** by default and only sets the window's title. The feed
  never shows the corpse name (too much text).
- Loot: besides the key binding, a **take-all key while looting** (`lootKey`, default E, out of combat only).
- Loot: the window and the feed have Almost Done's quiet look: a subtle panel, hairline rows with an accent hover,
  "Take all" as accent text with a keycap. The feed lines have a quality bar and a strip that fades out to the
  right; a repeated item merges into its line and counts up (as Plumber does).

## Left to build

Each item gets its own short plan when it's reached (spec, "Planning"), and its own commit after the user's
in-game check. Defaults: anything that only shows information is on; anything that acts for the player is off.

### Phase 4: small helpers in existing modules

- [ ] **Rogue:** Handy Lockpick: right-click a lockbox in bags or the trade window to pick it (also the Mechagnome
      racial). Secure button, created out of combat. Off by default (it acts).
- [ ] **Dressing room:** Catalyst preview (Ctrl-click previews, Shift-click links), quick outfit button, restore
      unsaved transmog changes, collectable counts on ensemble tooltips, `/tomte` outfit command.
- [ ] **Gear Check:** open the character pane at upgrade NPCs; gem socket helper; stronger item quality glow; bag
      sort order switch.
- [ ] **Vendor Helper:** merchant prices (grey out only the currencies you lack, list all costs); a short lock on
      the Yes button for non-refundable purchases.
- [ ] **Professions:** unspent knowledge on the Professions book and in tooltips (Materials); the Underlight Angler
      fix (Fishing); Resilient Seeds quick slot (Gathering, Midnight only, through the content system).
- [ ] **Group Alerts:** inviter's level and class on group and guild invites.
- [ ] **Chat Tabs:** "Leave" entries in the channel right-click menu.
- [ ] **Waypoints:** map ping on the player arrow when the map opens; countdown on timed waypoints; keys to cycle
      focus through tracked quests. (Memory: never open the map from code.)
- [ ] **Session recap:** break reminder, off by default.
- [ ] **Backpack item tracker:** stackable items on the bag currency bar, holiday tokens pinned, upgrade currency
      tracked, zero-count items hidden. Home: Holidays or Gold & value (builder's call).
- [ ] **Title manager:** search and filter titles. Home: Dressing room or Almost Done (builder's call).
- [ ] **Clickable sources:** achievement names in the Mount Journal and the decor catalog become links (Collect
      here).
- [ ] **Tooltip extras (new module,** key `tips`, on by default, category `interface`): which key opens a chest or
      door, reputation tokens, reagents in combine items, token vendor locations (Ctrl-click pins through
      Waypoints), choice UI item counts. (Memory: no widget sets in GameTooltip.)

### Phase 5: larger pieces

- [ ] **Delves:** dashboard (Great Vault and Gilded Stash progress), season progress bar, auto-pick delve powers
      (off by default), coffer key and shard caps in tooltips.
- [ ] **Housing decor:** decorate-mode hover info and Alt-duplicate, customize-mode dye copy, editor clock, banana
      for scale, teleport-home macro, house list, click-to-preview acquired alert, catalog search.
- [ ] **Expansion summary:** factions, activities, raid lockouts, vault, upgrade currency: a Tomte page with a
      minimap entry, sharing data with Weekly board.
- [ ] **Nameplates (new module,** off by default, category `interface`): quest icons and progress on nameplates,
      soft-target name and cast bar, War Within Keyflame counts.
- [ ] **Drawer macros:** custom flyouts of items, spells, mounts and toys. Secure-heavy; last. (Memory: secure
      button gotchas.)
- [ ] **Expansion content:** Midnight Prey hunt table and Prey waypoint; War Within event extras.

### Also waiting

- [ ] **Flight Timer games drawer:** a second game (or other content) next to the Casino before it can ship.

## Picking it up

1. Ask the user for the in-game checks listed above, and fix what comes back first.
2. Pick the next phase 4 item with the user (or take them in the order listed). Write a short dated plan in
   `docs/superpowers/plans/`, build, run all tests from the AddOns folder, ask for an in-game check, then commit with
   a CHANGELOG line.
3. Tick the boxes here as items land.
