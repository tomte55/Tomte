# Tomte: Collect here

Date: 2026-10-04. Backlog item 5. Research was shared with the user. The user then handed over every decision
("you decide everything, build it with what works best and come back when it is all done"), so all choices below
were made while building.

## Goal

Answer "what can I still collect here?" for the map being viewed in the world map, or for the zone you're in. It
lists the mounts, battle pets and achievements still missing, so you can farm them while you're there instead of
looking them up on Wowhead.

## Data: what the 12.1 client actually offers

Checked against Blizzard's generated API docs and UI source (wow-ui-source live) and warcraft.wiki.gg. Nothing changed
in the 12.0.0 through 12.1.0 API change notes, apart from the new `C_PetJournal.GetPetInfoTableBySpeciesID` (not used).

**No API ties a mount, pet, toy or achievement to a uiMapID.** Where zone information exists at all, it is free text,
and the client language is enUS (`Config.wtf`), so parsing that text is the honest approach. Coverage is partial: only
items whose source names a zone can be listed.

- **Mounts**
  - `C_MountJournal.GetMountIDs()` returns every mount and ignores the journal filters, so reading it has no side effects.
  - `GetMountInfoByID(id)` returns `name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific,
    faction, shouldHideOnChar, isCollected, mountID`.
  - `GetMountInfoExtraByID(id)` returns `creatureDisplayInfoID, description, source, ...`.
  - The source text is made of labelled lines separated by `|n`, for example
    `|cFFFFD200Drop: |rDoomwalker|n|cFFFFD200Zone: |rTanaris` or
    `|cFFFFD200Vendor:|r Ando|n|cFFFFD200Zone: |rLiberation of Undermine|n|cFFFFD200Cost:|r 777|T…|t`.
  - About 700 of 1700 mounts have a `Zone:` line. `C_MountJournal.GetMountLink(spellID)` gives the chat link.
- **Battle pets**
  - Species IDs are looped with `C_PetJournal.GetPetInfoBySpeciesID(id)`. It returns `name, icon, petType, creatureID,
    sourceText, description, isWild, canBattle, tradable, unique, obtainable, displayID` (the same positional use as
    Blizzard_PetCollection). The journal filters are never touched.
  - `C_PetJournal.GetNumCollectedInfo(id)` returns the number owned.
  - Wild pets list their zones as `Pet Battle: A, B, C`; other pets use `Zone:`. There is no pet chat link without an
    owned pet.
- **Toys: left out.** There is no list of all toys: `GetNumFilteredToys`/`GetToyFromIndex` obey the user's Toy Box
  filters, so we would have to save, clear and restore those filters. No API returns toy source text either; it might
  only be in the tooltip, which is unverified. See "Later".
- **Achievements**
  - There is no structured zone link (`C_AchievementInfo` has nothing for it, and criteria assets are not map IDs).
  - Most zone achievements name their zone in the title or description ("Explore Hallowfall", "Hallowfall Loremaster",
    "Treasures of the Ringing Deeps"), so achievements are matched by zone name.
  - Data comes from Almost Done's category walk; see Architecture.
- **Map names**
  - `C_Map.GetMapInfo`, `GetMapChildrenInfo(id, nil, true)` and `C_EncounterJournal.GetDungeonEntrancesForMap`, all
    already used by Teleports' `ns.Tp_MapNames`, which is reused.
  - Dungeon entrance names mean a raid's mount ("Zone: Liberation of Undermine") shows up when you view the zone the
    raid's entrance is in.
- **Rares with coordinates**
  - The game holds no drop tables for rares. RareScanner has a large one, but it's private to that addon, and it
    already pins rares with loot on the map.
  - What we can do honestly is match live vignettes: `C_VignetteInfo.GetVignettes()`, `GetVignetteInfo(guid).name`,
    `GetVignettePosition(guid, uiMapID)`, events `VIGNETTES_UPDATED` / `VIGNETTE_MINIMAP_UPDATED`.
  - When a vignette's name equals a missing mount's or pet's `Drop:` name, that row shows "Up now" and can be pinned
    as a waypoint.
- **Journals**
  - `SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS / _PETS)` (Blizzard_Collections_Bootstrap),
    then `MountJournal_SelectByMountID(id)` or `PetJournal_SelectSpecies(PetJournal, speciesID)`.
  - Achievements open with the existing `ns.Ach_Open(id)` and link with `ns.Ach_Link(id)`.

## What counts and what's hidden

- **Mounts:** not collected, `shouldHideOnChar` false (this hides the other faction's mounts), and the source has a
  `Zone:` or `Location:` line that matches the map.
- **Pets:** `obtainable`, none owned, and the source has a `Zone:`, `Location:` or `Pet Battle:` line that matches.
- **Achievements:** account-incomplete, not in Feats of Strength or Legacy (Almost Done already skips those), and the
  title or description names the map (whole-word, case-insensitive).
- Removed mounts can't be told apart through the API; most of them have no zone line anyway.

## Where it lives

- **Main: a "Collect" tab in the world map's side panel, under the Teleports tab.** It follows the map you're viewing:
  - **Zone or dungeon map:** that map.
  - **Micro or orphan map** (a cave, a building): its zone, found by walking up the parent maps.
  - **Continent:** every zone on it, with the zone name on each row.
  - **World or cosmic:** a hint to pick a zone.
- **Extra: toasts** (both can be turned off):
  - **Arriving in a new zone,** once per zone per session, only when at least one mount or pet is missing there.
    Example: "Hallowfall: 2 mounts, 3 pets, 18 achievements left". Clicking it opens the tab.
  - **A rare is up** whose drop you're missing: "Up now: Kordac drops Mount X". Clicking it sets a waypoint. Shown once
    per vignette.
- No panel page. The module's settings show in the Tomte panel through its `options`, like other modules.

## The tab

- Sections **Mounts (n)**, **Pets (n)** and **Achievements (n)**. Headers fold open and closed when clicked, and the
  folded state is saved.
- **Mount and pet rows:** icon, name, and one source line, the first useful one: "Drop: Doomwalker", "Vendor: Ando ·
  777g", "Wild pet battle", "Quest: …", and so on.
  - Continent view adds the zone ("Tanaris · Drop: Doomwalker").
  - A rare that's up shows "Up now" in green.
- **Achievement rows:** icon, name, progress ("40% · 2/5") and points.
- **Sort order:** mounts and pets by name; "up now" rows come first. Achievements by percent, highest first, then name.
- **Tooltip:** mounts and pets show the full source text (Blizzard's colored lines). Achievements show the standard
  achievement tooltip (`SetHyperlink`).
- **Clicks:** left-click opens the journal on the entry (Achievements window for achievements; not in combat).
  Shift-click puts a link in chat (mounts, achievements). Right-click on an "Up now" row sets a waypoint
  (`C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint`, the same as `/way`).
- **Model preview** *(added on request)*: hovering a mount or pet row shows its turning model next to the tooltip
  (`collect.preview`, on by default). The card is Almost Done's reward preview, moved to the shared
  `Panel/ModelPreview.lua`.
- **No secure actions,** so no secure overlay button is needed. The list keeps working in combat; only opening
  journals is refused.
- **While loading:** "Reading the journals..." with progress until the catalogs are built.

## Architecture

New folder `Tomte/Modules/Collect/`:

| File | Purpose |
|---|---|
| `Data.lua` | Pure logic, unit-tested: source parsing (labels, zone candidates, display line, drop name), name normalization and aliases, zone matching, whole-word achievement matching, building the sections, toast text. |
| `Catalog.lua` | Builds the mount and pet catalogs a few milliseconds per frame, once per session on first need. Keeps only uncollected entries that have zone names. Builds the achievement index through the shared walker. Answers `ns.Collect_ForMap(mapID)`. |
| `Tab.lua` | The world map tab and its rows. |
| `Collect.lua` | Module registration, events, toasts, commands. |

Changes to existing code (the targeted improvements this work needs):

- **`Panel/MapTabs.lua` (new): shared world map side tabs.**
  - Teleports did all the tab work itself. A second Tomte tab has to switch off the first, and the
    `QuestMapFrame:SetDisplayMode` hook and the stacking under the Map Legend tab should exist once.
  - API: `ns.MapTabs_Add({ key, icon, tooltip, onShow, onHide, onMapChanged })` returns `tab, panel`.
    `ns.MapTabs_SetShown(key, shown)`, `ns.MapTabs_Select(key)`, `ns.MapTabs_IsActive(key)`.
  - Same taint-free approach as before: it never calls `SetDisplayMode`, hides Blizzard's content frames itself and
    gives them back when a Blizzard tab is used.
  - Teleports' `MapTab.lua` moves onto it with unchanged behavior.
- **`Modules/Achievements/Walk.lua` (new): the shared achievement walk.**
  - The budgeted category/achievement loop moves out of `Scan.lua`.
  - Subscribers join with `ns.AchWalk_Join(key, { visit(id, categoryID), category(), finish() })`.
  - One pass serves everyone. A subscriber that joins mid-pass starts at the next category and gets a full lap, so a
    walk that's already running is extended instead of restarted.
  - Feats of Strength and Legacy are skipped for all subscribers.
  - Almost Done's scan becomes the "ach" subscriber with the same results and the same progress reporting. Collect is
    the "collect" subscriber: it works with Almost Done on or off, and when both are on there is still only one walk.
- **Achievement index:** `[id] = lowercased "name\ndescription"` for every account-incomplete achievement (thousands
  of short strings, built once a session).
  - Matching a map runs over the index with that map's names (map name, plus zone children on a continent) and is
    cached per map until the index changes.
  - `ACHIEVEMENT_EARNED` removes an entry. Matching is cached per map; progress is read live every time the tab
    draws (`ns.Collect_ReadProgress`: `ns.Ach_ReadCriteria` + `ns.Ach_Percent`), so `CRITERIA_UPDATE` only
    redraws an open tab.
  - *(decided after review)* Dungeon maps also match their Encounter Journal instance name, for mounts, pets and
    achievements: `EJ_GetInstanceForMap(uiMapID)` + `EJ_GetInstanceInfo(id)`. A few sources break lines with real
    newlines; those are treated like `|n`.

### Matching details (Data.lua)

- **Cleaning:** color codes `|cXXXXXXXX`, `|r` and textures `|T…|t` are stripped for matching. The display keeps the
  cost texture so gold shows as an icon.
- **Zone values:** every `Zone:`, `Location:` and `Pet Battle:` value is split on ", ". The candidates are the whole
  value, each piece, and each pair of neighbours joined back with ", ", because names like "Amirdrassil, the Dream's
  Hope" contain a comma.
  - A trailing qualifier "(Mythic)" or "(Burning Crusade)" is dropped from each candidate.
  - Candidates are compared lowercased and exactly against the map's name set.
  - A known limit: duplicate names (Nagrand, Shadowmoon Valley) match both maps.
- **Aliases:** a small table. "Capital Cities" covers the capitals, and "Stormwind" covers "Stormwind City".
- **Achievements:** a map name of 4+ characters, found whole-word in the achievement's text.
- **Drop name** for vignettes: the `Drop:` value with any qualifier removed. "World Drop" is never a drop name.

## SavedVariables (`TomteDB.collect`)

```
show = { mounts = true, pets = true, achievements = true }
collapsed = { mounts = false, pets = false, achievements = false }
toasts = { zone = true, rare = true }
```

## Events

- `PLAYER_ENTERING_WORLD`: catalog and walk start 6 seconds after the first one.
- `ZONE_CHANGED_NEW_AREA`: the zone toast.
- `NEW_MOUNT_ADDED`, `NEW_PET_ADDED`, `ACHIEVEMENT_EARNED`, `CRITERIA_UPDATE`: refresh the tab, debounced, only while
  it's visible.
- `VIGNETTES_UPDATED`, `VIGNETTE_MINIMAP_UPDATED`: the rare toast and "Up now".

Nothing is computed for toasts in combat (the toast stack already holds cards in combat).

## Commands

- `/tomte collect open`: the map on this tab.
- `/tomte collect here`: counts for your zone printed in chat, plus the source values on this map that matched
  nothing (for adding aliases).
- `/tomte collect test`: sample toasts.
- `/tomte collect help` comes from the shared command list.

## Testing

- `tests/test_collect.lua` (plain Lua): parsing real source strings, the comma'd instance names, qualifiers, aliases,
  whole-word achievement matching, sections and sort order, drop names, toast text.
- `tests/test_achwalk.lua`: the walker with stubbed globals. It checks a single pass for two subscribers, a mid-pass
  join getting a full lap, skipped top categories, and leaving.
- The existing `tests/test_achievements.lua` and `test_teleports.lua` must still pass.

## Later (not built)

- **Toys:** if a Toy Box tooltip on an uncollected toy shows "Drop:" / "Zone:" lines, toys could come in by saving,
  clearing and restoring the Toy Box filters once a session and scanning tooltips.
- **A hand-made achievement table** for zone achievements that don't name their zone.
