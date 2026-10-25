# Tomte on World of Warcraft: Forever (2026-10-25)

## Why

World of Warcraft: Forever launches on 2026-11-04. It is a third permanent game next to retail and Classic: a
Classic-style level-60 Azeroth with no expansions, included in a normal subscription. The user wants Tomte to run there
too, with as much of it as works or makes sense. Friends who play Forever get the same addon from the same download.

The user decided:

- **Same addon, same repo, a second TOC file.** Not a separate addon.
- **No private server.** Emulators don't run the Forever client and are against Blizzard's terms. Testing starts in game
  on launch day (the user doesn't have the client before that), with the usual `/reload` and BugSack loop.
- **Launch-day goal: the modules that need little work run well on Forever.** The modules that need a Forever version
  follow one by one after launch, each as its own small project.
- **Modules wanted on Forever (eventually):** Alts, Quests, Gear Check, Dressing Room, Vendor Helper, Durability,
  Loot, Material Use, Gold & Value, Mail, Fishing, Gathering, Flight Timer, Waypoints, Smart Mount, Teleports, the
  whole Groups & friends and Chat categories, Cursor highlight, Tooltip extras, Nameplates, Drawers, the Class
  category and the Ambience category.

## Goals

- On 2026-11-04 Tomte loads on Forever with no Lua errors, the Tomte window opens, and the launch set (below) works.
- The retail addon is unchanged in behavior. Nothing here may break or slow down retail.
- Launch day takes one short round of in-game checks, not an evening of chasing errors. Everything that can be done
  before the client exists is done before.

## Non-goals

- Forever versions of the bigger modules (listed under "After launch"). They come after launch, one spec each.
- Supporting Classic Era, Season of Discovery, Mists Classic or other Classic flavors. Only retail and Forever.
- Forever content data beyond what the launch set needs.

## Anti-goals

- A retail player notices anything different.
- A Forever player sees a module or setting that does nothing or errors. If it doesn't work there, it isn't loaded.
- Copies of whole files with `if forever then ... else ... end` everywhere. Differences live in one shared shim, in
  guards at the few places that need them, or in separate Forever files for modules that differ a lot.

## What the code review found

A read-through of the code (2026-10-25) against the Classic Era 1.15 API, the closest known client. Forever's real API
is unknown until launch, so "missing" means "missing in Classic Era". Forever may have more.

### Foundations (Core, Panel, Cinematic, Themes)

Mostly fine. The registry runs every module under `xpcall`, so one module's error doesn't stop the others. Needed:

1. **Compatibility shim.** APIs that retail moved or renamed and the launch set calls:
   - `C_AddOns.GetAddOnMetadata` (`Core/Core.lua:6`, at file load: if it fails, the whole addon dies).
   - `ChatFrameUtil.*` (retail 11.x namespace): `Chat/Filter.lua:72,143,147`, `Social/Friends.lua:133,135`,
     `Social/Mentions.lua:77`, `Social/Whispers.lua:213,235,241,304`, `Panel/Widgets.lua:82` (`InsertLink`).
     Classic names: `ChatFrame_SendTell`, `ChatFrame_ReplyTell`, `ChatFrame_OpenChat`,
     `ChatFrame_AddMessageEventFilter`, `ChatEdit_InsertLink`.
   - `C_ChatInfo.SendChatMessage` (hooked at file load in `AFK/AFK.lua:194`; also `AFK.lua:138`,
     `Social/Whispers.lua:286`).
   - `C_SpecializationInfo.GetSpecialization` (`Panel/HomeHero.lua:365-367`, unguarded on the default Home view).
2. **Edit Mode fallback.** 16 modules place widgets through `ns.EditMode_Register`, which only listens to Blizzard's
   Edit Mode (`Core/EditMode.lua:97`). Classic has no Edit Mode, so nothing could be moved, and the boxes use retail
   `editmode-*` atlases.
3. **Content for expansion 0.** `Core/Content.lua` resolves Forever to expansion 0 without errors, but data is only
   registered for expansions 4-11, so every `ns.Content_Get` returns nil.
4. **Map tabs and pins.** `Panel/MapTabs.lua` uses retail `QuestMapFrame` and templates; `MapTabs_Opener`'s PreClick
   indexes `QuestMapFrame` unguarded (:117-118) and is used by `Panel/Rail.lua:26` and Home's map buttons.
   `ns.TrackPin` (`Core/Core.lua:127-128`) calls `C_SuperTrack` unguarded.
5. **Retail-only, left out of the Forever TOC:** `Core/Journal.lua`, `Panel/Entries.lua`, `Panel/ModelPreview.lua`,
   `Data/WarWithin`, `Data/Midnight`, `Data/Older`.
6. Smaller guards: `Panel/Panel.lua:407-408` (`Settings.RegisterCanvasLayoutCategory`), `Panel/Share.lua:15-25`
   (`C_EncodingUtil`, profile export only), `Panel/HomeHero.lua:375` (`GetAverageItemLevel`),
   `Cinematic/Showcase.lua:82-106` (item level).

### Launch set (ready, or a few guards)

| Module | Files on Forever | Known work |
| --- | --- | --- |
| Cursor highlight | all | none |
| Mail | all | none known |
| Durability | `Upkeep/Durability.lua` | delve wording (:104-105) |
| Vendor Helper | `Upkeep/Vendor.lua`, `Merchant.lua` | `C_MerchantFrame.SellAllJunkItems` and junk flags (Vendor.lua:67-69,149-153) likely missing: sell greys with `C_Container.UseContainerItem`; `C_MerchantFrame.GetItemInfo` (Merchant.lua:56) -> `GetMerchantItemInfo` |
| Loot | all | `C_TransmogCollection` (Read.lua:22-30), `C_ToyBox` (Toasts.lua:126), `CurrencyContainerUtil` (Read.lua:119) |
| Gold & Value | `Value/Data.lua`, `Value.lua`; `Backpack.lua` out | warband bank tabs (Value.lua:14-16, 204-241) |
| Flight Timer | all but `Blizzard_FlightMap` hooks (already skipped) | `C_TaxiMap.GetTaxiNodesForMap`, `Enum.FlightPath*` uncertain (Atlas.lua, Tooltip.lua:27); pace data is per map ID, so it starts empty |
| Fishing | all but `Angler.lua` | `C_ToyBox`/`PlayerHasToy` (Key.lua:74,95,119), `C_PetBattles` (Key.lua:137), Fishing spell ID 131474 is retail (Data.lua:7-18; Era uses ranked spells) |
| Drawers | all | `C_ToyBox` (Read.lua:94), `C_MountJournal` (Read.lua:21,45,69,100): toy and mount drawers off |
| Nameplates | all | Keyflame data out (Data.lua:7-19); `C_QuestLog.UnitIsRelatedToActiveQuest` (Read.lua:69) uncertain |
| Chat (Copy, Filter, Tabs, Tags) | all | channel table (Data.lua:9-15) needs Forever channels (no Trade (Services)); `GetProfessions` (Filter.lua:30-32) -> skill line scan; `Menu.ModifyMenu` (Tabs.lua:262) uncertain |
| Friends, Whispers, Mentions, Toasts | `Social/*` | shim only |
| Group Alerts | `Social/Alerts.lua` | `LFG_PROPOSAL_SHOW` registered raw (:19); `C_SummonInfo` (:59) |
| Friend sharing | all | must only pair with Forever friends (Roster.lua:12 checks `wowProjectID`) |
| AFK screen | all | shim; `C_PetBattles` (:51); `C_EventUtils.IsEventValid` (:247) |
| Casino | all | works; retail sounds play nothing (Effects.lua:41 is nil-safe); `C_QuestLog.IsWorldQuest` (Earn.lua:73-74) |
| Quests | all but `TalkingHead.lua`, `Medals.lua` | `C_QuestLog` functions in Read.lua:120-141 and `IsQuestFlaggedCompletedOnAccount` (Read.lua:48, Items.lua:45) may be missing |
| Tomte's own (Recent, Minimap Buttons, Next up) | all | Recent and Minimap Buttons are needed (Toasts feed Recent, the minimap button opens the window); Next up if it loads clean |

### After launch (each needs a Forever version and its own spec)

Smart Mount (mounts are bag items, no flying), Teleports (Forever list), Waypoints (no `C_SuperTrack`/`C_Navigation`),
Gathering (no super-track, Forever map IDs, no seeds), Buff reminders (vanilla buffs, `GetWeaponEnchantInfo`),
Hunter and Pet Health (pet happiness, loyalty, old stable API), Rogue (poisons are bag items applied to a weapon),
Gear Check (vanilla stats, no item level, no sockets or upgrades), Alts (roster first, then crafting on the old
tradeskill API), Material Use (regenerate data, drop Knowledge), Tooltip extras (Forever data), Moments, Recap,
Showcase, Instances (lockout banner only), Dressing Room (no transmog: at most a bigger dressing room). Talent check
doesn't fit (no loadouts) and stays retail-only.

Four class files capture `C_SpecializationInfo` at file load (`Rogue/Rogue.lua:22-23`, `Hunter/Checks.lua:11-12`,
`Combat/PetHealth.lua:11-12`, `Talents/Talents.lua:18-19`). They stay out of the Forever TOC until their Forever
version exists.

## Design

### Two TOC files

- `Tomte.toc` stays the retail TOC, unchanged.
- A second TOC with Forever's flavor suffix (Blizzard's convention, like `Tomte_Vanilla.toc`; Forever's suffix and
  `## Interface:` number are only known on launch day). Until then the builder uses a placeholder and the launch-day
  checklist fills it in. The client loads only the TOC matching its flavor, so retail never sees it.
- The Forever TOC carries `## X-Tomte-Flavor: forever`. Core reads it at load and sets `ns.FOREVER = true`. Code
  that differs checks `ns.FOREVER`, never `WOW_PROJECT_ID` directly (Forever's project ID is unknown; if a runtime
  check is needed, Core does it once, see "What Forever's client turns out to be"). *(Claude's call.)*
- **The Forever TOC is generated**, not hand-kept: `tools/forevertoc.lua` reads `Tomte.toc` and keeps the lines in an
  allowlist (whole folders or single files, in `tools/`), so load order always matches retail and a new retail file
  never sneaks in. Forever-only files (shim, Data/Forever, Forever versions of modules) are listed in the allowlist
  at their place in the order. A test fails when the generated TOC is out of date, like `test_bugreport` does for
  `Core/BugFiles.lua`. *(Claude's call.)*
- `tools/bugfiles.lua` keeps reading `Tomte.toc` and also adds any file only the Forever TOC lists.
- `Bindings.xml` is shared. CLICK bindings to buttons that don't exist on Forever are harmless.

### Saved variables

Each game flavor keeps its own `WTF` folder, so `TomteDB` on Forever starts empty and never mixes with retail. No
migration needed.

### Shim

One new file, `Core/Compat.lua`, loaded right after `Core/Format.lua` and before anything that calls these APIs,
in **both** TOCs. It exports Core-wide helpers (`ns.ChatSendTell`, `ns.ChatReply`, `ns.ChatOpen`, `ns.ChatInsertLink`,
`ns.ChatFilter_Add`, `ns.SendChat`, `ns.AddOnMetadata`, `ns.Spec` (nil where there are no specs)) that pick the
retail API when present and the Classic one otherwise. Retail behavior stays identical. Call sites in the launch set
switch to these helpers. Exact names are the builder's choice within CLAUDE.md's naming rules. `Core/Core.lua:6`
can't use `ns.AddOnMetadata` if Compat loads after it, so either Compat moves before Core.lua or line 6 gets its own
fallback; the builder picks.

### Edit Mode fallback

`ns.EditMode_Register` keeps its interface. When Blizzard's Edit Mode isn't there (`EditModeManagerFrame` nil),
`/tomte unlock` (and a button on Tomte's settings home) turns the same boxes on, and `/tomte lock` or the button again
turns them off. The boxes use a theme border (`UI.Border`) instead of the retail atlases when those atlases don't
exist. Modules don't change. *(Claude's call.)*

### Content

`Data/Forever/` registers expansion 0 through `ns.Content_Register`, with only what the launch set reads. Retail data
folders are left out of the Forever TOC. Modules already handle a nil `Content_Get`.

### Map pieces

On Forever the map tabs aren't loaded and no Home entry of kind `map` is shown. `MapTabs_Opener` and `ns.TrackPin`
get guards so a call does nothing (or uses `C_Map.SetUserWaypoint` alone if it exists) instead of erroring.

### Modules on Forever

A module shows on Forever only if its main file is in the Forever TOC. Inside the launch set, each "known work" item
above is guarded at the call site (existence check, or `ns.FOREVER` for a data choice), or the file is left out of
the TOC when the whole file is retail-only. Settings rows for parts that are cut on Forever get `shown = function()
return not ns.FOREVER end`.

### Launch-day probe

The probe can't live inside Tomte: before launch nobody knows Forever's TOC suffix or Interface number, so a Forever
TOC with a guessed suffix might not load at all, and the retail TOC would load every retail file. So the probe is a
**separate tiny dev addon, `tools/TomteProbe/`** (its own unsuffixed TOC, one Lua file, no dependency on Tomte, plain
Blizzard frames). The user copies it into Forever's AddOns folder, ticks "Load out of date AddOns" if needed, and
types `/tomteprobe`. It shows, in a copyable edit box:

- `GetBuildInfo()` (Interface number), `WOW_PROJECT_ID`, `GetExpansionLevel()`, the client's folder name if readable;
- present / missing for every API, event (`C_EventUtils.IsEventValid` when it exists, else a pcall'd
  `RegisterEvent` on a scratch frame), frame, template and constant this spec marks uncertain or uses in the launch
  set.

It works on retail too (useful to check the probe itself before launch). It lives in `tools/`, so it is never in the
release zip. *(Claude's call.)*

### What Forever's client turns out to be

Not known before launch. The probe settles it:

- **Forever has its own flavor** (expected): it gets its own TOC suffix, its own `WTF` folder, and the design above
  holds as written.
- **Forever shares Classic Era's client and suffix**: the Forever TOC would also load on Classic Era. Then Core sets
  `ns.FOREVER` only when the TOC tag is there **and** a runtime check the probe identifies (a project ID, a realm
  flag, or the expansion/max level) says Forever. On Classic Era Tomte prints one line ("Tomte doesn't support this
  game yet") and registers nothing. Saved variables would then share a folder with Classic Era, which is harmless
  because Tomte stores nothing there on Classic Era. *(Claude's call.)*

### When things ship

All Forever work happens on a **`forever` branch** (the user's decision), including this spec. `main` stays free for
retail fixes and releases in the meantime; `forever` takes `main` in (merge) whenever `main` moves. Because this repo
is the live addon folder, the checked-out branch is what the game runs: while testing Forever work the folder is on
`forever`, and a retail hotfix means switching back to `main` first. `forever` is merged into `main` on launch day,
after the user has tested on Forever.

- **Before launch (now):** all retail-neutral prep (the shim, the Edit Mode fallback, the guards, `Data/Forever`, the
  TOC generator, the probe, the workflow change) is built and checked by the user **on retail** (`/reload`, nothing
  looks or behaves differently, BugSack empty). Committed per the usual rule after that check. The Forever TOC is
  generated and kept in the repo but with a placeholder suffix no client recognises (`Tomte_ForeverPending.toc`),
  so no client loads it and a release before launch can't make Tomte appear on Classic Era.
- **Launch day:** the user runs the probe; Claude renames the TOC to the real suffix, sets `## Interface:`, adds
  guards for anything missing; the user tests on Forever; commit on `forever`, merge into `main`; the user asks for a
  release when happy. The
  CHANGELOG line "runs on Forever" is only written then.
- `release.yml` ignores a TOC whose name ends in `Pending`. *(Claude's call.)*

### Release

- The zip carries both TOCs; one release serves both games.
- `.github/workflows/release.yml` uploads to CurseForge with both game versions: retail from `Tomte.toc`, Forever from
  the Forever TOC's `## Interface:`. How CurseForge lists Forever (a version under a new game version type) is only
  known after launch: until the Forever version exists there, the workflow uploads retail only and says so, instead
  of failing.
- README: a short "Forever" section listing what works there. CHANGELOG under `### New`:
  "- **Tomte:** runs on World of Warcraft: Forever (...)".

## Launch-day checklist (for the user, 2026-11-04)

1. Install Forever. Link the `Tomte` folder into Forever's `Interface\AddOns` (a directory junction, so one copy of
   the code serves both games), and copy `Tomte\tools\TomteProbe` there too. Install BugSack/BugGrabber for Forever
   if they exist for it.
2. Log in, type `/tomteprobe`, paste the result. Claude names the Forever TOC, sets `## Interface:`, adds guards for
   anything reported missing, and you `/reload`.
3. Test list (Claude writes it with the build): open the Tomte window, Home, each launch-set module's main action,
   `/tomte unlock` and drag a widget, BugSack empty.

## Left to the builder

- Order of work, file names inside the rules above, helper names in the shim.
- Which "uncertain" items to guard pre-emptively versus leave for the launch-day probe. Lean towards guarding when it
  costs one line; leave the rest to the probe.
- Exact allowlist format for `tools/forevertoc.lua`.
- Tests: the shim's pick logic (pure part), the TOC generator, and an extension of existing tests that parse the TOC.
