# EnhanceQoL + Plumber takeover, phases 4 and 5: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task.

**Goal:** every remaining Plumber / EnhanceQoL feature from the spec's phases 4 and 5, so both addons can be
uninstalled.

**Delegation:** the user said (2026-10-23) "go ahead with phase 4 and 5, spec, plan and build it all and come back
to me when it is all done". All open choices below are the coordinator's calls, recorded here. Nothing is committed
before the user's in-game check; then one commit per task.

**Spec:** `docs/superpowers/specs/2026-10-22-tomte-enhanceqol-plumber-absorption-design.md` (phases 4 and 5).
Status/handoff: `docs/superpowers/plans/2026-10-23-tomte-takeover-status.md`.

## Global constraints

- All of `CLAUDE.md` applies (module shape, file headers, theme roles, events only while active, hooks inert while
  off, `UI.ContextMenu`, `ns.Confirm_Show`, `ns.EditMode_Register`, `ns.Content_Register`, no deprecated globals,
  `ns.IsSecret` guards, CRLF via Edit/Write only).
- **No copied code** from Plumber or EnhanceQoL (no license). Reading them (in `Interface\AddOns\Plumber`,
  `Interface\AddOns\EnhanceQoL*`) to learn which API/event/frame does the job is fine; game IDs are facts and may be
  taken, credited in the task's report for README Credits.
- Verify every API on warcraft.wiki.gg and Gethe/wow-ui-source (live) before use.
- Defaults: anything that only shows information is **on**; anything that acts for the player is **off**.
- Each module that now covers part of Plumber/EnhanceQoL adds or extends `replaces = { { addon = ..., why = ... } }`.
- **Builders never edit** the TOC, `Bindings.xml`, README, CHANGELOG, `Core/`, `Panel/`, `CLAUDE.md` or a folder
  owned by another task. They report the TOC lines (in load order), `<Binding>` entries + `BINDING_NAME_*` text,
  README rows/commands/credits and a CHANGELOG line they need. A builder that truly needs a Core/Panel helper says
  so in the report instead of adding it.
- Every new or changed pure file gets tests in `tests/test_<name>.lua`; all of that builder's tests green under
  Lua 5.1; `luac -l` global scan on every new/changed file.

## Tasks and file ownership

| # | Task | Owns |
| --- | --- | --- |
| 1 | Small helpers: Rogue lockpick, Group Alerts inviter info, Chat Tabs leave, Recap break reminder | `Modules/Rogue/`, `Modules/Social/Alerts.lua` (+ Social `Data.lua` additions only at its end), `Modules/Chat/Tabs.lua` (+ Chat `Data.lua` end), `Modules/Recap/` |
| 2 | Dressing room extras + Title manager | `Modules/DressUp/` |
| 3 | Gear Check helpers | `Modules/Gear/` |
| 4 | Vendor Helper prices + Professions helpers | `Modules/Upkeep/`, `Modules/Materials/` (not Generated.lua), `Modules/Fishing/`, `Modules/Gather/`, `Data/Midnight/Seeds.lua` |
| 5 | Waypoints extras, clickable sources, backpack tracker | `Modules/Travel/` (not Network*.lua), `Modules/Collect/`, `Modules/Value/` |
| 6 | Tooltip extras (new module) | `Modules/Tips/`, `Data/*/Tips.lua` |
| 7 | Delves extras | `Modules/Delves/`, `Data/*/Delves*.lua` additions |
| 8 | Housing decor extras | `Modules/Decor/` |
| 9 | Expansion summary (new module) + expansion content (Prey) | `Modules/Summary/`, `Modules/Prey/`, `Modules/Weekly/` (new exports only), `Data/Midnight/Prey.lua` |
| 10 | Nameplates (new module) | `Modules/Nameplates/` |
| 11 | Drawers (new module) | `Modules/Drawers/` |
| 12 | Integration (coordinator) | TOC, `Bindings.xml`, README, CHANGELOG, `Core/BugFiles.lua`, status doc |

## Task decisions

### 1. Small helpers

- **Rogue, Handy Lockpick:** right-clicking a locked lockbox in the bags (or in the trade window's "will not be
  traded" slot) casts Pick Lock (or the Mechagnome racial) on it. Built as a secure action button overlaid on the
  hovered bag slot, created lazily out of combat, hidden in combat (`PLAYER_REGEN_DISABLED`). Off by default
  (`lockpick = false`). Only shown for a character who knows one of the spells. Lockbox detection by tooltip line /
  item info that works in every client language (Blizzard's `LOCKED` global), not English text.
- **Group Alerts:** party and guild invite popups gain a line with the inviter's level, class (class colored) and,
  for party invites, guild; read from the friend/guild/community data or `C_BattleNet` when known, never by
  /who. On by default. Uses Blizzard's popup by hooking, never replacing it.
- **Chat Tabs:** right-click on a chat tab offers "Leave <channel>" for each joined channel shown in that tab.
  Through `UI.ContextMenu` if Tabs already owns a menu there; otherwise extend Blizzard's menu with `Menu.ModifyMenu`
  (the documented 11.0+ way; not `MenuUtil` construction). On by default.
- **Session recap, break reminder:** after N minutes played in one sitting (setting, default 60, 30 to 180), a toast
  (`ns.Toast_Show`) suggests a break; snoozes until the next interval; never in combat, an instance or a cinematic
  (shows afterwards). Off by default.

### 2. Dressing room

- **Catalyst preview:** in the Catalyst (ItemInteractionFrame in catalyst mode), the result item's tooltip and a
  small strip show the converted piece; Ctrl-click previews it in the dressing room, Shift-click links it.
- **Quick outfit button** on the dressing room: a menu (`UI.ContextMenu`) of saved outfits
  (`C_TransmogCollection`/12.x outfit API, verified) to try on.
- **Restore unsaved transmog changes:** when the Transmogrify frame closes with pending changes, remember them;
  next open offers a "Restore last changes" button. Info + one click, on by default.
- **Ensemble tooltips:** "N of M appearances collected" on ensemble items. On.
- **`/tomte dressup outfit <name>`** wears (or previews, out of a transmogrifier) a saved outfit by name.
- **Title manager:** a search box and "Owned / Missing" filter on the character pane's title list (PaperDoll
  Titles). On. Lives in DressUp (character appearance).

### 3. Gear Check

- **Upgrade NPC:** opening the item upgrade window also opens the character pane beside it (CharacterFrame is a
  normal UI panel; `ToggleCharacter("PaperDollFrame")` out of combat), closing it again if Tomte opened it. On.
- **Gem socket helper:** while the socketing frame is open, a strip of the gems in your bags that fit the open
  sockets (Gear Check's gem advice marks the recommended one); click picks up the gem for the socket (cursor
  pickup is allowed). On.
- **Stronger item quality glow:** bag item buttons get a thicker quality-colored border (rare+). Off by default
  (visual change to Blizzard frames). Works with Blizzard bags; Baganator untouched.
- **Bag sort order switch:** setting with "Left to right" / "Right to left"
  (`C_Container.SetSortBagsRightToLeft`) applied on change and on login; "don't change" default.

### 4. Vendor Helper and Professions

- **Merchant prices:** items costing currencies/items show every cost on the merchant row; only the costs you
  lack are greyed (red), not the whole button. On.
- **Non-refundable lock:** the purchase confirmation's accept button is disabled for 1 second when the purchase
  can't be refunded (Blizzard's confirm popup, hooked, not replaced). On.
- **Unspent knowledge:** the Professions book (and the profession button tooltips) shows unspent specialization
  knowledge per profession (`C_ProfSpecs` / `C_Traits`). Materials item tooltips on knowledge items say how much
  knowledge they give if that's readable. On.
- **Underlight Angler fix (Fishing):** whatever Plumber's fix does (read it for the problem, rebuild from scratch);
  the builder documents the problem in the header comment. On.
- **Resilient Seeds quick slot (Gathering, Midnight only):** when you stand near a rich soil spot with seeds in
  your bags, a secure item button appears (one click plants). Content data `Data/Midnight/Seeds.lua` through
  `ns.Content_Register`. Off by default (acts; the button is the action).

### 5. Waypoints, Collect, Value

- **Map ping:** opening the world map pulses a ring on the player arrow for ~2 s (our own canvas frame on the map,
  never Blizzard's ping; memory: never open the map from code). On.
- **Timed waypoints:** waypoints for things with a known end time (world quest, event) show a countdown on the
  Waypoints card. On.
- **Cycle focus:** two key bindings (next / previous tracked quest) that super-track through the quest watch list.
  Bindings `TOMTE_WAY_NEXT`, `TOMTE_WAY_PREV`.
- **Clickable sources:** in the Mount Journal's and the decor catalog's source text, achievement names become
  clickable (open the achievement). Hook, inert while Collect is off. On.
- **Backpack item tracker** lives in **Gold & value** (`Modules/Value/Backpack.lua`): tracked items shown on the
  bag currency bar next to Blizzard's tracked currencies; holiday tokens auto-pinned during their holiday; upgrade
  currency (crests) tracked; zero counts hidden. Add/remove from the item's right-click is not possible on bag
  buttons safely, so a `/tomte value track <item link>` command and a settings list. On.

### 6. Tooltip extras (new module)

Key `tips`, name "Tooltip extras", category `interface`, on by default. Through
`TooltipDataProcessor.AddTooltipPostCall`, inert while off. Lines: which key opens a chest/door (data per
expansion), reputation tokens (which faction, how much, whether you're capped), reagents in combine items (owned
counts), token vendor locations (Ctrl-click pins through Waypoints: `ns.Way_*` export looked up at call time),
choice UI item counts (PlayerChoiceFrame options: how many of the reward you own). No widget sets
(memory: no widget sets in GameTooltip).

### 7. Delves

Dashboard additions to the existing Delves page: Great Vault delve row progress and the Gilded Stash count, a
season progress bar (delve season journey renown), coffer key and shard caps in tooltips (On). **Auto-pick delve
powers** (Off): when the delve power choice opens and one option is on your preference list (or only one option),
pick it; a hardware event may be required, in which case it becomes one key press.

### 8. Housing decor

Decorate mode: hover info (name, owned count, placement cost) and Alt-click duplicate (place another of the
hovered decor). Customize mode: copy dyes from one decor to another. Editor clock (real time while editing),
"banana for scale" (a reference model toggle), teleport-home macro (secure button in the Decor page / a `/tomte
decor home` that tells the player to use the button: casting needs a hardware event), house list (all your houses
with Visit), click-to-preview on the "decor acquired" alert, catalog search box. Each its own switch; info on,
actions off. The builder checks every C_Housing* API on the wiki and drops any piece whose API is protected or
missing, saying so.

### 9. Expansion summary and expansion content

- **Expansion summary** (new module `summary`, folder `Modules/Summary/`, category `week`, on): a Tomte page and a
  minimap button showing factions, activities, raid lockouts, vault and upgrade currency for the current character.
  Data comes from Weekly board's model through new `ns.Weekly_*` exports (added in Weekly, read-only), never by
  duplicating its collectors.
- **Prey** (new module `prey`, folder `Modules/Prey/`, category `quests`, on, Midnight only through
  `ns.Content_Register`): the Prey hunt table (current prey, rewards) and a waypoint to the active prey via
  `ns.Way_*`. **War Within event extras:** the builder reads Plumber's War Within-only modules, picks what's live
  and small (if anything), and folds it into this task or reports it as skipped.

### 10. Nameplates (new module)

Key `plates`, name "Nameplates", category `interface`, **off by default**. Quest icon + progress ("3/8") on enemy
nameplates of units tied to your quests (tooltip data of the unit, not English text), soft-target name and cast bar
for the soft (interact) target, War Within Keyflame counts. Only decorates Blizzard nameplates (no replacement),
guards every unit value with `ns.IsSecret`, never in a way that taints.

### 11. Drawers (new module)

Key `drawers`, name "Drawers", category `interface`, off by default. Custom flyouts: a drawer is a list of items,
spells, mounts and toys; it opens from a secure button (placeable via Edit Mode, and bindable) and each entry is a
secure action button. Built per memory "secure button gotchas" (no anchoring secure buttons to normal frames,
mounts by `/cast` macro). Edited from its settings page (add by link/name/drag).

### 12. Integration (coordinator)

TOC lines, `lua Tomte/tools/bugfiles.lua`, `Bindings.xml` + strings, README rows/commands/layout/credits, CHANGELOG
Unreleased lines, all tests, `luac` scans, one fresh review per task, fixes, and one combined in-game test list.
