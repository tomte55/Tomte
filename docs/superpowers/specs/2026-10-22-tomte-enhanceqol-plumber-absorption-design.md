# Absorbing EnhanceQoL and Plumber into Tomte

Date: 2026-10-22. Status: design, approved phase by phase in conversation.

## Intent

The user and their friend want Tomte to be the only addon they need. The user runs Plumber; the friend runs
EnhanceQoL. Tomte takes over every feature either of them uses (and, for Plumber, every live feature: "take it all,
if a user doesn't want it they can keep it off"), each with its own settings, so both addons can be uninstalled.
The "Other addons" page then lists EnhanceQoL and Plumber under "Tomte can replace" on every module that covers part
of them.

## What they actually use (read from their saved variables, 2026-10-22)

**Friend, EnhanceQoL** (one profile; almost every module's master switch is off). Deliberately on:
- Auto accept + turn in quests (`autoChooseQuest`), no modifier, **skip daily/weekly quests** (`ignoreDailyQuests`).
- Auto-pick gossip (`autoChooseGossip`) in every context, no saved option IDs.
- Auto-skip cinematics (`autoCancelCinematic`).
- Gem socket helper (`enableGemHelper`), stronger item quality glow (`enhancedRarityGlow`), bag sort order switch
  (`bagSortOrderEnabled`, direction left at default).

Not used, and **not** in scope: unit frames, cast bar, damage meter, cooldown panels, resource bars, custom bags,
square minimap, button bin, data panels, mover, tooltip IDs, chat history/IM window, mouse ring, auto repair/junk
(Tomte's Vendor Helper already does that), group-finder helpers, M+ tools, consumable macros, combat text.

**User, Plumber.** Turned on beyond the defaults: Loot window (forced auto-loot, **E** as Take all, owned counts,
reputation and currency lines, replaces loot alerts, 6 items per page), Queue status (with time), Merchant price,
Boss loot banner (master switch only), Map player ping. Everything else is left at Plumber's defaults; the user
wants all of it.

Explicitly requested by the user on top: instance difficulty selector, loot window, queue status, fast loot, auto
accept/turn in quests, auto skip cinematics.

## Goals

- Every feature below exists in Tomte with settings, behaving at least as well as the original.
- After all phases, uninstalling EnhanceQoL and Plumber loses nothing the two of them used.
- The Other addons page tells a player when it's safe to turn each addon off.

## Non-goals

- EnhanceQoL features nobody uses (list above).
- Plumber code that Plumber itself doesn't load (commented out in its TOC/XML): Legion Remix, Dreamseeds,
  Technoscryers, Plunderstore, WoW Anniversary, Event Toast fix, Appearances tab, Craft search, Spellcasting info,
  TWW map pins, Snapdragon/Dye tooltips, Tillers, action bar art fix, druid model fix. Plumber's Dragonflight
  "Old" modules (Dreamseed list and choice UI, Technoscryers) are skipped as well.
- MoP/Classic support (Tomte is retail only).
- Importing settings from EnhanceQoL or Plumber (the user declined it): everyone sets Tomte's switches once.

## Anti-goals

- **No copied code.** Neither addon has a license (no LICENSE file, no TOC field), so both are all rights reserved.
  Rebuild every feature from scratch in Tomte's shape. Reading them to learn which API and event does the job is
  fine; game IDs (gossip option IDs, widget IDs, quest IDs) are facts and may be taken, credited in README.
- No feature that acts in a way the player didn't switch on: invasive automation starts off for a new player.
- No second copy of something Tomte already has: fold into the existing module.
- Nothing that locks controls, taints Blizzard frames or breaks with `/console loadDeprecationFallbacks 0`.

## Constraints

- All of CLAUDE.md applies: module shape, pure files with tests, theme roles, `UI.ContextMenu` (not `MenuUtil`),
  `ns.Confirm_Show` (not StaticPopup), `ns.EditMode_Register` for anything movable, `ns.Content_Register` for
  expansion IDs, events registered only while active, hooks inert while off.
- Verify every API on warcraft.wiki.gg and in Blizzard's UI source before use. In particular: `AcceptQuest`,
  `CompleteQuest`, `GetQuestReward`, `C_GossipInfo.SelectOptionByIndex`/`SelectActiveQuest`/`SelectAvailableQuest`,
  `C_QuestLog.IsQuestTrivial`/`IsRepeatableQuest`, `StopCinematic`, `CanCancelScene`/`CancelScene`,
  `MovieFrame` close path, `LootSlot`, `GetLootSlotInfo`, `SetDungeonDifficultyID`, `SetRaidDifficulties`,
  `GetSavedInstanceInfo`, `GetLFGQueueStats`, `C_Container.SetSortBagsRightToLeft`, the housing `C_House*` APIs.
  If any of them turns out to need a hardware event in 12.1, the feature becomes one key/click per action.
- Secret values: guard GUIDs, names and gossip fields with `ns.IsSecret`.
- The user owns Midnight as of 2026-10-22 and tests the Midnight-only pieces too. Midnight-only features still go
  through the content system and appear only on a character in that expansion.
- One phase at a time: build, user tests in game, commit, CHANGELOG line, then the next phase.

## Other addons entries

Every module that covers part of EnhanceQoL or Plumber adds `replaces = { { addon = "EnhanceQoL" | "Plumber",
why = "<what it covers>" } }`. Two features clash rather than merely overlap and also get a `conflicts` entry:
quest automation (EnhanceQoL), and the loot window (Plumber, plus Leatrix Plus's fast loot). **My call:** a clash
only warns (the page and the module's header chips say so), it doesn't switch Tomte's feature off, because
EnhanceQoL/Plumber's own toggle for that feature may well be off and Tomte can't see their settings.

## Step 0: settings groups reorganized

With ~56 modules the groups are rebalanced into 12 (`ns.PANEL_GROUPS` in `Panel/Layout.lua`), 3 to 5 modules
each. The sidebar's icon rail scrolls (mouse wheel, selected group kept in view) instead of shrinking rows. Short
labels stay one word (the existing step-down from 10 to 8 pt handles "Interface"); the full name is the tooltip
and the list heading. Only `category` fields and the group table change; no saved setting moves.

| Group (short) | Modules |
|---|---|
| Tomte (Tomte) | Tomte window, Other addons, Recent, Next up, Minimap buttons |
| Your week (Week) | Weekly board, Alts, Delves, Trading Post, Expansion summary |
| Quests (Quests), new | Quests, World quests, Gold world quests |
| Gear & loot (Gear) | Gear Check, Loot, Durability, Vendor Helper, Dressing room |
| Professions & gold (Profs) | Fishing, Gathering, Material uses, Gold & value, Mail |
| Collections (Collect) | Almost Done, Collect here, Housing decor, Holidays & events, Pet Battles |
| Travel (Travel) | Flight Timer, Smart Mount, Teleports, Waypoints |
| Groups & friends (Groups), new | Instances, Group Alerts, Friends Online, Whispers, Friend sharing |
| Chat (Chat), split from Social | Chat Copy, Trade Filter, Chat Tabs, Channel Tags, Mentions |
| Interface (Interface), new | Tooltip extras, Nameplates, Drawers, Cursor highlight, Graphics presets |
| Class & combat (Class) | Buff reminders, Pet Health, Hunter Pets, Rogue Poisons, Talent check |
| Ambience (Ambience) | AFK Screen, Moments, Session recap, Showcase, Casino |

Group keys for the builder to pick (keep existing keys where the group survives: `tomte`, `week`, `gear`,
`professions`, `collections`, `travel`, `class`, `ambience`; `social` becomes the groups-and-friends group or is
renamed, builder's call). Icons for new groups: file IDs checked to exist. Update CLAUDE.md's category list and
the README if it names groups. The categories for the new modules in the phases below follow this table.

## Phase 1: Quests and NPCs (new module)

**My calls:** folder `Modules/Quests/`, key `quests`, name "Quests", `enabledByDefault = false`.

- **Accept and turn in** on QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_GREETING and GOSSIP_SHOW (active
  completed quests first, then available ones). Holding a **skip key** (setting: Shift, Ctrl, Alt; default Shift)
  skips automation for that window.
- **Filters**, each a switch: skip daily/weekly/repeatable quests (default **on**), skip trivial (grey) quests, skip
  turn-ins that cost gold or currency, skip quests already done on another character of the account. Per-NPC
  ignore list, added from the target's right-click menu.
- **Reward choice:** one reward, take it; none, finish. Several: a separate switch **"Pick the reward for me"**
  (default off) takes Gear Check's best pick when Gear Check names a clear upgrade (via `ns.GearRewards_Pick` /
  a new `ns.Gear_*` export, not Gear's db); otherwise stop and leave Gear Check's reward card as today.
- **Gossip auto-pick:** the option flagged as a quest step, or the only option, once per conversation. Plus
  **event gossip** (Time Rift, Theater Troupe, and similar) from per-expansion content data, so it follows the
  character's expansion. Skyriding race gossip shows the medal you've earned (Plumber's GossipFrameMedal).
- **Cinematics:** setting with three choices: off, **skip ones you've seen** (default), skip all. Movies
  (PLAY_MOVIE carries an ID) can be "seen before"; in-engine cinematics have no ID, so under "seen" they behave as
  configured by a second switch "also skip in-engine cutscenes" (my call). Plus a quick-skip switch: Space, Esc or
  Enter confirms the skip in one press (from the real key handler).
- **Talking Head:** off / hide / text only (Plumber's text replacement, with its instance and world quest options).
- **Quest items:** deleting a quest-starting item shows which quest; its tooltip names the quest and its state.
- Commands: `why` (why the last NPC was or wasn't automated), `ignore` list.
- `replaces` EnhanceQoL (quest/gossip automation, cinematics) and Plumber (talking head, quest item alert, quest
  item tooltip, auto join events, race medal); `conflicts` EnhanceQoL (both auto-accept).

## Phase 2: Loot (new module)

**My calls:** folder `Modules/Loot/`, key `loot`, name "Loot". **User's decision:**
`enabledByDefault = true` for everyone, existing players included (no prompt, no migration).

- One window, three **styles** (setting): **List** (default; compact, close to Plumber), **Card** (source header,
  best item on top with Gear Check's verdict, auction values from Gold & value), **Feed** (no window; lines slide
  in beside the character and fade; a window appears only when something can't be auto-looted: full bags, roll
  items, locked loot).
- **Extras**, each a switch working in every style: fold junk into one line, owned counts, new-appearance tag,
  reputation and currency lines, Gear Check verdict, auction value, source header.
- **Take all** on a key binding (`Bindings.xml`, category Tomte). Default binding: none set by Tomte (bindings
  are the player's); the settings row tells them to bind it, suggesting E.
- **Look:** font size, background opacity, items per page, grow up/down, fade delay per line, open at mouse or at
  the Edit Mode position.
- **Fast loot** (its own switch): loots every slot on LOOT_READY, respecting the game's auto-loot key
  and CVar; nothing left stuck.
- **Replace loot pop-ups:** Blizzard's loot toasts are suppressed while this shows the same lines (switch, default
  on). Must be undone on Stop.
- **Boss loot banner:** off / hide when solo / valuable items only.
- `replaces` Plumber (loot window, fast loot, boss banner) and EnhanceQoL (fast loot); `conflicts` Plumber (two
  loot windows) and Leatrix_Plus (fast loot).

## Phase 3: Instances and queues (new module)

**My calls:** folder `Modules/Instances/`, key `instances`, name "Instances",
`enabledByDefault = true`. Each piece is its own switch, all default on.

- **Entrance picker:** near a dungeon or raid portal, a small card with Normal / Heroic / Mythic (segmented) and
  your lockout on each difficulty. Only usable by you solo or as group leader; otherwise read-only. How "near a
  portal" is detected is the builder's to find (Plumber's approach may be read for the API, not copied).
- **Minimap difficulty badge:** readable text replacing Blizzard's flag ("5 · H", "M+12", "D8", "LFR", "TW",
  "25 · M"), click outside an instance for a quick difficulty menu (`UI.ContextMenu`). Blizzard's indicator is
  restored on Stop.
- **Lockout banner** on zone-in: difficulty, saved or not, bosses down.
- **Queue status:** a ring on the queue eye that fills as the group forms (tanks and healers weigh more), time in
  queue, and the difference from the average wait.
- **Holiday dungeon:** the first time Dungeon Finder opens in a session, select the holiday/Timewalking dungeon.
- `replaces` Plumber (difficulty selector, queue status, holiday dungeon) and EnhanceQoL (difficulty text).

## Phase 4: small helpers folded into existing modules

- **Rogue:** Handy Lockpick: right-click a lockbox in bags or the trade window to pick it (also Mechagnome racial).
  Secure button, created out of combat.
- **Dressing room:** Catalyst preview (Ctrl-click previews, Shift-click links), quick outfit button, restore
  unsaved transmog changes, collectable counts on ensemble tooltips, `/outfit` (via `/tomte` command, my call).
- **Gear Check:** open the character pane at upgrade NPCs; gem socket helper; stronger item quality glow; bag sort
  order switch.
- **Vendor Helper:** merchant price (grey out only the currencies you lack, list all costs); short lock on the Yes
  button for non-refundable purchases.
- **Professions:** unspent knowledge on the Professions book and in tooltips (Materials); Underlight Angler fix
  (Fishing); Resilient Seeds quick slot (Gathering, Midnight only).
- **Group Alerts:** inviter's level and class on group and guild invites.
- **Chat Tabs:** "Leave" entries in the channel right-click menu.
- **Waypoints:** map ping on the player arrow when the map opens; countdown on timed waypoints; keys to cycle focus
  through tracked quests.
- **Session recap:** break reminder, off by default.
- **Backpack item tracker** (stackable items on the bag currency bar, holiday tokens pinned, upgrade currency
  tracked, zero-count items hidden): its home is the builder's call (Holidays or Gold & value).
- **Title manager** (search and filter titles): Dressing room or Almost Done, builder's call.
- **Clickable sources:** achievement names in the Mount Journal and the decor catalog become links (Collect here).
- **New module "Tooltip extras"** (my call: key `tips`, on by default): which key opens a chest
  or door, reputation tokens, reagents in combine items, token vendor locations (Ctrl-click pins via Waypoints),
  choice UI item counts.

## Phase 5: larger pieces

- **Delves:** dashboard (Great Vault and Gilded Stash progress), season progress bar, auto-pick delve powers,
  coffer key and shard caps in tooltips.
- **Housing decor:** decorate-mode hover info and Alt-duplicate, customize-mode dye copy, editor clock, banana for
  scale, teleport-home macro, house list, click-to-preview acquired alert, catalog search.
- **Expansion summary:** factions, activities, raid lockouts, vault, upgrade currency: a Tomte page with a minimap
  entry, sharing data with Weekly board rather than duplicating it.
- **Nameplates** (new module, off by default): quest icons and progress on nameplates, soft-target name and cast
  bar, War Within Keyflame counts.
- **Drawer macros:** custom flyouts of items, spells, mounts and toys. Secure-heavy; last.
- **Expansion content:** Midnight Prey hunt table and Prey waypoint; War Within event extras.

## Defaults in phases 4 and 5

**My call**, following the user's "if a user doesn't want it they can keep it off or turn it off depending on our
defaults": Tomte's rule, not Plumber's. Anything that shows information (tooltips, dashboards, pings, counts) is
on; anything that acts for the player (auto-pick delve powers, event gossip, lockpick on right-click) is off.

## Planning

**My call:** the implementation plan details phases 1 to 3. Phases 4 and 5 are approved at the level written
here; each item gets its own short plan when it's reached, since most are independent small changes.

## Tests

Each new module gets a pure file with tests: quest automation decisions (filters, skip key, reward choice, gossip
choice, cinematic policy), loot line building (junk folding, owned counts, styles' content), badge text and queue
progress weighting and lockout summaries. In-game testing per phase by the user.

## Left to the builder

File splits inside each module, exact visuals within the theme, portal detection approach, where the backpack
tracker lives, debug commands, the order of items inside phases 4 and 5 (each can be its own commit).
