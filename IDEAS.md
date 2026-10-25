# Tomte ideas

Feature ideas captured for later. Newest first. Status: New, Discussing, Planned, In Progress, Built, Parked, Rejected.

---

## Live previews for visual settings

**Date:** 2026-10-25
**Status:** Planned (next up after the loot window looks, `docs/superpowers/specs/2026-10-25-tomte-loot-window-looks-design.md`)

**Description:**
When a player changes a setting that changes how something looks (the loot window's look, font size, opacity, grow
upward ...), they get a small preview right in the settings, in its tooltip, so they see what they're picking without
leaving the Tomte window. Every setting that changes something visual should get one.

Decided: **live miniatures, not screenshots.** The preview is drawn by the same code that draws the real widget, with
sample data, so it always matches the theme, the font and the player's other settings. Screenshots were turned down:
they'd ignore the theme, go stale, and every new image needs a full client restart.

**Use Cases:**
- Choosing between the loot window's Strips, Panel and Tiles looks without looting something to see each.
- Any slider or switch that changes a look (size, opacity, layout): see the effect before closing the settings.
- Friends who didn't build the addon and don't know what "Panel" or "Grow upward" means.

**Benefits:**
- Settings explain themselves; fewer "what does this do" questions.
- Pushes every visual widget to have a sample mode, which Edit Mode and `/tomte <module> test` use too.

**Complexity:** Medium for the framework, then Low per setting.
- Settings renderer: an optional `preview` field on an options row (`Panel/Options.lua`, `Panel/OptionRows.lua`), shown
  as a tooltip-like card beside the row on hover; for dropdowns/segmented buttons, one preview per choice under the
  mouse.
- Widgets need a way to draw into a given parent with sample data and given settings (a value not yet chosen) rather
  than their one on-screen frame. Today's sample modes (`ns.LootWindow_Preview`, `ns.LootFeed_Preview`, Edit Mode
  `refresh`) show the real frame in place; that may be the cheap first step (show the real widget beside the
  settings window) before true miniatures.
- The loot window looks should be built so each look can draw itself with sample loot into any frame: the first user.

**Notes:**
- Open: tooltip on hover vs a preview area always shown in the settings card; scaling (real size vs shrunk); which
  modules' settings count as visual (a list to make when we start).

## Rares: a module to replace RareScanner

**Date:** 2026-10-25
**Status:** Parked (researched, decision later)

**Description:**
A Tomte module that does what RareScanner does: alert when a rare NPC, treasure or event shows up, show where it is,
whether you've already done it and what it drops. RareScanner was kept on purpose on 2026-10-22 because its value is
maintained data, so the question is how much of that data we can build ourselves.

**Use Cases:**
- Anyone out in the world who wants to know a rare or treasure is nearby and go get it.
- Collectors hunting rares that drop mounts, pets, toys or transmog they're missing.

**Benefits:**
- One fewer third-party addon ("we only need Tomte").
- Shares data with Collect, Waypoints, Recent and Toasts instead of living apart.

**Complexity:** Low for the alert part, High (and never finished) for a full RareScanner database.

Three tiers:

| Tier | What | Effort | Data |
| --- | --- | --- | --- |
| 1. Live alerts | A vignette appears: toast/banner with name, model, sound; buttons for waypoint, map ping, secure "target it" | Small to medium (Rogue-sized) | None, all live |
| 2. Memory | Remember seen/killed, where and when; learn drops on loot; "seen nearby" map tab | Medium | Only what we see ourselves |
| 3. Full RareScanner | Pins for every rare/treasure per zone before you've been there, "drops a mount you lack", respawn timers | Large, ongoing per patch | Hand-collected; see below |

Already in Tomte to reuse: `ns.Toast_Show` / `ns.Banner_Show`, Waypoints and `MapPing` (Modules/Travel),
`ns.ModelPreview_*`, `ns.MapTabs_Add`, `ns.EditMode_Register`, Collect's vignette reading
(`ns.Collect_ApplyVignettes` in `Modules/Collect/Catalog.lua`) and its "missing" checks, Gather's map pins as a pin
template. A secure target button follows the secure-button rules (create out of combat, macrotext, no anchoring to
normal frames). Check on warcraft.wiki.gg first: `C_VignetteInfo` in 12.x, and whether `/target <name>` macrotext
still works.

**How RareScanner gets its data** (read from its 12.1.5 install, 2026-10-24):
- **Shipped tables** (`Tables/`, about 3 MB, updated each release): NPC ID, zone, display ID, quest ID that marks it
  done (`NpcInfoTables.lua`); item IDs per rare/container (`NpcLootTables.lua`, `ContainerLootTables.lua`); respawn
  min/max/exact (`NpcSpawnInfoTables.lua`); achievements, Drakewatcher, mounts, pets, missing transmog sources.
  Internal names like `[DNT]` and `<Vignette Placeholder>` show the NPC info is datamined from client files. Loot
  and respawn times can't be datamined, so they're collected by hand or from players.
- **Learned by each client** (saved in `RareScannerDB`): positions when a vignette appears
  (`RSGeneralDB.AddAlreadyFoundEntity`), or the player's position for rares found by nameplate, mouseover, target
  or soft-interact; drops on `LOOT_OPENED` (`GetLootSlotLink` + `GetLootSourceInfo`); a completed-quest cache. Its
  unit reads use `issecretvalue` guards, so this works on 12.1.5.
- **Shared live** (Telemetry plugin, AceComm to guild and group): kill and spawn times with shard IDs, so respawn
  timers work for rares you haven't seen yourself. Asks for recent samples on login or joining a group.
- RareScanner has no license file: its tables can't be copied (single game IDs are facts and fine).

**What datamining can give us** (checked against wago.tools DB2 CSVs, 2026-10-24; `tools/wago.py` already loads
these):
- `Vignette` (7,250 rows): name, type, `VisibleTrackingQuestID` (4,134 have one, so "already done" comes free via
  `C_QuestLog.IsQuestFlaggedCompleted`), `RewardQuestID`. The most useful table.
- `Creature`: name, `Classification` (2 = rare elite, 4 = rare), display IDs for the model. Sparse: about 23k of
  278k creature IDs, only 333 rares; 216 vignette names match a rare in it.
- `QuestPOIPoint` / `AreaPOI`: positions for quests and fixed POIs, not rares.
- Not in the client at all: spawn positions, loot and respawn times (all server-side).

Ways to fill the gaps:
1. Learn them ourselves (tier 2). Clean and free, but starts empty: a zone only gets pins once someone has been there.
2. Scrape Wowhead or similar. Ruled out: that's a curated database (CLAUDE.md Sharing rule) and against their terms.
3. Share between Tomte users (profile export or addon messages). Grows faster, but a sync protocol to build and test.

**Notes:**
- Realistic shape: tier 1 + tier 2 + a generated `Data/<Expansion>/Rares` from a `tools/rares.py` (Vignette table:
  names and done-quests), regenerated per patch like the other generated files. Optional small hand-kept list of the
  current season's mount/pet rares (20-40 per expansion) for the most valuable bit of tier 3.
- What it can't match: RareScanner's "here are all 40 rares in this zone, and this one drops a mount" before you've
  explored. If that's the main reason to use RareScanner, keep it.
- Open question: is the pre-filled zone map why RareScanner is used, or are alerts plus done-tracking enough?

---

## Delves: alert when a Mislaid Curiosity spawns

**Date:** 2026-10-15
**Status:** Rejected (2026-10-15: the game only reports the bags while a L00T RAID-R reveal is active, see Notes;
built, tested and removed)

**Description:**
Inside delves, "bags" spawn that you can open for companion curios. Detect them and alert the player to go pick
them up. In game they're called **Mislaid Curiosities**, and depending on the delve they look like a bag, a
mushroom, a vase or a void container. Opening one gives companion XP, Resonance Crystals and sometimes a curio.

**Use Cases:**
- A player running a delve who would otherwise walk past a bag and miss the companion XP or a curio.
- Friends levelling a companion or hunting for specific curios.

**Benefits:**
- Fewer missed bags, so the companion levels faster and curios come sooner.
- Fits the existing Delves module, which already shows the companion's level, role and curios.

**Complexity:** Low if the bags are vignettes, otherwise High or not possible.
- A container on the ground isn't a unit, so nameplates and targeting can't see it. The clean route is
  vignettes (`C_VignetteInfo.GetVignettes` / `GetVignetteInfo`, `VIGNETTES_UPDATED`,
  `VIGNETTE_MINIMAP_UPDATED`).
- `Modules/Collect/Catalog.lua` (`ns.Collect_ApplyVignettes`) and `Modules/Collect/Collect.lua` already read
  vignettes for rares and can serve as the pattern.
- Plan if they are vignettes: in the Delves module, watch vignette events only while inside a delve. On a new
  Mislaid Curiosity, matched by `vignetteID` (never the English name, so other client languages work), show
  `ns.Toast_Show` with a sound and remember the GUID so each bag alerts once. A map pin is optional.
- The vignette IDs go in `Data/<Expansion>/Delves.lua` through `ns.Content_Register`.
- If they aren't vignettes, all that's left is counting bags as you loot them, which doesn't help you find them.

**Notes:**
- Step one: the user checks in game whether the bags are vignettes. In a delve, with a bag spawned or in view:
  ```
  /run for _,g in ipairs(C_VignetteInfo.GetVignettes()) do local i=C_VignetteInfo.GetVignetteInfo(g) if i then print(i.name, i.vignetteID, i.atlasName, i.onMinimap, i.onWorldMap) end end
  ```
  A line with "Mislaid Curiosity" (or similar) means it's buildable. Note the `vignetteID` and check whether
  every container style shares one ID or each has its own.
- 2026-10-15 in-game check (a Midnight delve with Valeera, the Labyrinth doors): **they are vignettes.**
  `Mislaid Curiosity 6699 VignetteLoot onMinimap=true onWorldMap=false`, three bags at once, all vignetteID 6699
  with their own GUIDs. Still unknown: whether War Within delves and the other container styles use 6699 too.
  Since each bag is listed before you reach it, a Tomte map pin is possible; the minimap already shows its own
  `VignetteLoot` icon.
- 2026-10-15 second check: the bags are only vignettes while revealed. The first dump was taken after a friend
  used a L00T RAID-R Mini (item 244193); without it `/tomte delves vignettes` listed only Brann and the exit.
  RareScanner says the same (alerts need the L00T RAID-R curio). Built as: alert + pins while revealed, and a
  reminder on entering a delve when a Mini is in your bags.
- Open questions: toast plus sound only, or a minimap/world map marker too? On by default or a Delves setting?
  Is a per-run count of bags opened useful? (The CurseForge addon "Mislaid Curiosity Counter" does that count.)
- Sources: https://warcraft.wiki.gg/wiki/Mislaid_Curiosities, https://warcraft.wiki.gg/wiki/Curio
