# Tomte: Delves

Date: 2026-10-10. Research and a design for the user to review before anything is built. Claude made the decisions
below; the questions still open for the user are at the end.

## Goal

Delves are the main solo weekly activity, and the game spreads what you need to know over the world map, the Great
Vault, the companion window, the currency tab and the tier picker. The module answers four questions in one place:

1. **Where today?** Which delves are bountiful right now, and a click to go there.
2. **Can I open the coffer?** Restored Coffer Keys and shards on hand, and how many keys are left to earn this week.
3. **Which tier?** The tier that raises your Great Vault's World slots, and how many more runs that takes.
4. **Is my companion set up?** Companion level, role and curios, and a hint when the role clashes with yours.

Success: the user opens Home, sees "Bountiful: The Sinkhole, Skittering Breach (2 keys)", clicks one, flies there
with the Waypoints marker, and at the entrance Tomte says "Tier 8 raises vault slot 2 (2 more runs)".

The user plays War Within content at level 80 on the 12.1 client without owning Midnight. Friends may own Midnight.
Everything follows the character's content expansion (`ns.ContentExpansion()`), with data per expansion in `Data/`.

## Research summary

API, checked against wow-ui-source live at build 12.1.0 (69933) (`Blizzard_APIDocumentationGenerated`) and Blizzard's
own use of it:

- **No secret returns.** None of `C_DelvesUI`, `C_AreaPoiInfo`, `C_WeeklyRewards`, `C_SuperTrack`,
  `C_GossipInfo.GetFriendshipReputation*` or `C_MajorFactions.GetMajorFactionData` is marked `SecretReturns`. They
  are only `SecretArguments = "AllowedWhenUntainted"`: Tomte must never pass a secret value in. Tomte reads nothing
  during combat anyway, and nothing here depends on combat info.
- **Nothing protected.** Reading is free. Tracking a delve (`C_SuperTrack.SetSuperTrackedMapPin`, `C_Map.SetUserWaypoint`)
  goes through `ns.SafeTrack`, because in combat the map's pin refresh in tainted code hits a blocked call. Tomte never
  calls `C_DelvesUI.SelectDelveEntranceTier` (Blizzard's own button does it) and never changes curios
  (`C_Traits.SetSelection`/`CommitConfig`).
- **Delve entrances on a map:** `C_AreaPoiInfo.GetDelvesForMap(uiMapID)` returns area POI IDs, and
  `GetAreaPOIInfo(uiMapID, id)` gives `name`, `position`, `atlasName`, `description`, `tooltipWidgetSet`,
  `iconWidgetSet`. Blizzard's `DelveEntranceDataProvider` uses exactly this pair.
- **Bountiful:** a bountiful delve is a different POI ID than the same delve's normal entrance (The War Within pairs:
  Plumber's `MapPin_Delves.lua`, e.g. The Sinkhole 7870 normal / 7783 bountiful). Its `atlasName` is
  `"delves-bountiful"` (Plumber's `ActivityUtil.lua`). Plumber notes that bountiful POIs used to be missing from
  `GetDelvesForMap` and that this "no longer works", so they are in it now. Tomte uses both signals: the atlas, or the
  ID in the expansion's known bountiful set. Checked in game in Task 1.
- **Story variant:** the entrance tooltip's widget set (`tooltipWidgetSet`) is what shows the story and its
  description on the map pin. `GameTooltip_AddWidgetSet(GameTooltip, setID)` (Blizzard_GameTooltip) puts it in a
  tooltip, so Tomte shows the game's own text and never parses it.
- **Tracking a delve:** Blizzard's map pin super-tracks it with
  `C_SuperTrack.SetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI, poiID)`
  (`SuperTrackablePoiPinMixin`). Tomte's Waypoints module already shows an AreaPOI super-track with the POI's name
  and atlas (`Modules/Travel/Target.lua`). Portal routes (`Router.lua`) only follow a user waypoint, so on another
  continent Tomte places a user waypoint at the POI's position instead.
- **Great Vault, World track:** `C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.World)` gives
  each slot's `threshold`, `progress`, `level` (the delve tier the slot pays for now) and `activityTierID`.
  - `GetSortedProgressForActivity(World, true)` lists this week's runs as `{ difficulty, numPoints }`, highest first.
    For delves, difficulty is the tier and numPoints the run count; difficulty 1 also covers world activities.
    Blizzard's vault tooltip uses it this way.
  - A slot with threshold *t* pays for the *t*-th best run. That is Blizzard's "top N activities" line,
    `WEEKLY_REWARDS_WORLD_TOP_ACTIVITIES`.
  - `GetNextActivitiesIncrease(activityTierID, level)` returns `hasSeasonData, nextActivityTierID, nextLevel, itemLevel`.
    Blizzard's vault tooltip uses it for "Run a Tier N delve for item level X". Following it from tier 1 upwards
    gives the item level per tier and the top tier, where it returns no next level. Tomte reads this from the game
    and keeps a hard-coded `vaultTopTier` per expansion only for when `hasSeasonData` is false.
- **Tier picker:** opening a delve entrance fires `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with
  `Enum.PlayerInteractionType.TieredEntrance`, and it loads `Blizzard_DelvesDifficultyPicker`.
  `C_DelvesUI.GetDelveEntranceTiers()` then returns `{ tier, suggestedILvl, unlocked, lockedReason, ... }`.
- **Companion:**
  - The season's delve faction is `C_DelvesUI.GetDelvesFactionForSeason()`. `C_MajorFactions.GetMajorFactionData()`
    of that faction carries `playerCompanionID` and the renown level, which is the Delver's Journey.
  - `C_DelvesUI.GetFactionForCompanion(companionID)` gives the companion's friendship faction:
    `C_GossipInfo.GetFriendshipReputationRanks` (`currentLevel`, `maxLevel`) and `GetFriendshipReputation` (XP). Its
    name comes from `C_Reputation.GetFactionDataByID`.
  - `GetRoleSubtreeForCompanion(roleType, companionID)` gives the subtree of each role (`Enum.CompanionRoleType`
    Dps 0, Heal 1, Tank 2).
  - `GetTraitTreeForCompanion` → `C_Traits.GetConfigIDByTreeID`. Then `GetRoleNodeForCompanion` and
    `GetCurioNodeForCompanion(Enum.CurioType.Combat|Utility)` → `C_Traits.GetNodeInfo(configID, nodeID).activeEntry`
    → entry → `GetSubTreeInfo` (role name) or `GetDefinitionInfo` (curio spell). The curio's rank comes from
    `GetCurioRarityByTraitCondAccountElementID`.
  - All of this is Blizzard's `Blizzard_DelvesCompanionConfiguration`. Brann is faction 2640 (The War Within) and
    Valeera 2744 (Midnight). Both are facts from Plumber, used as a fallback when the season faction has no companion.
- **Currencies and items** (facts, from Plumber's `ResourceList.lua`, `TWW_Activity.lua`, `MID_Activity.lua`):
  - Restored Coffer Key: currency 3028, both expansions.
  - Coffer Key Shard: in The War Within an item (245653 in season 3, 236096 earlier); in Midnight currency 3310, with a
    weekly cap read from `maxWeeklyQuantity`. 100 shards make a key.
  - Weekly key and shard flags (The War Within): 91175–91178 and 84736–84739, already in `Data/WarWithin/Weekly.lua`.
    Plumber has no Midnight flags (commented out), so Midnight shows the shard cap from the currency and no key flags.
- **Zones** (uiMapIDs; Plumber and RareScanner): The War Within 2248 Isle of Dorn, 2214 Ringing Deeps,
  2215 Hallowfall, 2255 Azj-Kahet, 2346 Undermine, 2371 K'aresh (continent Khaz Algar 2274). Midnight
  2395 Eversong Woods, 2437 Zul'Aman, 2413 Harandar, 2405 Voidstorm, 2393 Silvermoon City (continent Quel'Thalas
  2537).

What exists already and is reused, not duplicated:

| Already in Tomte | Delves uses it for |
|---|---|
| Weekly Activities tab: "Restored Coffer Keys n/4", "Coffer Key Shards n/4", The Key to Success / A Gnawing Void of Curiosity (`Data/<exp>/Weekly.lua` `activities`) | The "earned this week" numbers. Its reader becomes public (`ns.Weekly_ReadCurated`), so both show the same thing. |
| Weekly Resources list (3028, 3310) | Unchanged. Delves shows keys next to bountiful delves, where they matter. |
| Weekly vault boxes (`ns.WeeklySlot_Create/Set`) | The World track on the Delves page, with tier text. |
| Next up "Vault slot one activity away" | Unlocking a slot stays Weekly's job. Delves only suggests raising an unlocked slot's tier. |
| Moments "Renown" | The Delver's Journey is a major faction, so its renown moment already fires. Nothing to add. |
| Waypoints (AreaPOI super-track, portal routes) | Tracking a delve. |

## Decisions

| Idea | Decision | Why |
|---|---|---|
| Today's bountiful delves, list + waypoint | **In** | The core of "where today", and cheap: one API pair per zone. |
| Bountiful on the world map | **Out** | Blizzard already draws bountiful entrances on zone maps (and natively on Quel'Thalas). A Tomte map tab would only repeat it. |
| Keys and shards | **In**, reusing Weekly | Bountiful is pointless without a key; the count belongs next to the list. |
| Tier for the vault | **In** | The question the vault UI answers worst. The game's own data, nothing hard-coded. |
| Companion level and curios | **In**, read-only | One line plus a role-clash hint. Changing curios stays in Blizzard's window. |
| Delver's Journey renown | **In**, one line | Free from the same read. The moment already exists. |
| Story variants | **In**, as the game's tooltip | `GameTooltip_AddWidgetSet` shows them; rating variants needs curated data (Later). |
| Seasonal nemesis (Zekvir and successors) | **Out** | Different per season and expansion, mostly achievements; Almost Done already tracks those. |
| Gilded Stash / weekly crest stash | **Out** (Later) | Only readable through a widget in some places (Plumber's "info unavailable in your location"). Too fragile. |
| Tier picker note | **In** | It's where the tier decision happens. Small, read-only, next to Blizzard's frame. |
| Companion level moment | **In** (banner) | One event compare; the Moments engine does the rest. |

## Pieces

Module key `delves`, name "Delves", category "World", enabled by default. Nothing runs before the character can
enter delves (`C_DelvesUI.GetDelvesMinRequiredLevel()`), and nothing reads during combat.

### 1. Bountiful today (`Scan.lua`)

- For each zone in the expansion's `delves.zones` (plus the `Zone` children of `delves.continent`, deduped, in case a
  zone is missing from the list):
  - `GetDelvesForMap(zone)` → `GetAreaPOIInfo(zone, id)`.
  - Each entry: `{ poi, map, name, x, y, atlas, widgetSet, bountiful }`, where `bountiful` means
    `atlas == "delves-bountiful"` or the POI is in `delves.bountifulPOIs`.
- Cached until `AREA_POIS_UPDATED`, a zone change or the daily reset (`C_DateAndTime.GetSecondsUntilDailyReset`).
- **List order** (pure, `Delves_Sort`): bountiful first, then your zone first, then by name.
- **Click** (`Delves_Track(entry)`):
  - On the same continent: `SetSuperTrackedMapPin(AreaPOI, poi)`, so the marker shows the delve's name and atlas.
  - On another continent: `C_Map.SetUserWaypoint` at the POI's position plus `SetSuperTrackedUserWaypoint(true)`,
    so Waypoints routes it.
  - Both go through `ns.SafeTrack`, and print "tracking <name>".
- **Hover:** the delve name, "Bountiful" (accent), the zone, then `GameTooltip_AddWidgetSet` with the POI's widget set
  (the story variant).

### 2. Keys

Read on `CURRENCY_DISPLAY_UPDATE` and `BAG_UPDATE_DELAYED` (debounced 1 s):

- **Keys:** `GetCurrencyInfo(3028).quantity`.
- **Shards:**
  - The War Within: the sum of `C_Item.GetItemCount(id)` over `delves.shards.items`.
  - Midnight: `GetCurrencyInfo(3310)`: quantity, plus earned/cap this week when `maxWeeklyQuantity > 0`.
- **Earned this week:** the "Delves" group from `ns.Weekly_ReadCurated(expansion)`, so the n/4 flag counts are
  Weekly's.
- **Line** (pure, `Delves_KeyLine`): "2 keys · 140 shards (1 more key) · keys this week 3/4". With 100 or more shards
  it adds "combine 100 shards into a key". This is only a hint: using an item needs a click, and Tomte doesn't make
  a button for it.

### 3. Tier for the vault (`Vault.lua` pure + reader)

- Reader:
  - `slots`: from `GetActivities(World)` sorted by index, each `{ threshold, progress, level, activityTierID }`.
  - `runs`: from `GetSortedProgressForActivity(World, true)`.
  - `ladder`: `{ [tier] = itemLevel }` and `top`, by following `GetNextActivitiesIncrease` from tier 1 with the
    first non-zero `activityTierID`, at most 20 steps. When `hasSeasonData` is false: `top = delves.vaultTopTier`
    and no item levels.
- Pure `Delves_VaultPlan(slots, runs, top)` → one row per slot:
  - `{ index, unlocked, tier, maxed, runsToUnlock, runsAtTop }`:
    - `tier`: the threshold-th best run's tier;
    - `maxed`: `tier >= top`;
    - `runsAtTop`: `threshold` minus the runs at `top` or higher, never below 0.
  - plus `advice`, the first slot that isn't maxed. Its text: "Run Tier 8 or higher: 2 more maxes vault slot 2
    (now Tier 5)", or "Every World slot is maxed".
- Runs at difficulty 1 count as world activities: they unlock slots but never raise one.

### 4. Companion (`Companion.lua`)

- Read on `UPDATE_FACTION`, `TRAIT_CONFIG_UPDATED` and `DELVES_ACCOUNT_DATA_ELEMENT_CHANGED` (debounced, out of
  combat):
  - `{ name, level, maxLevel, xp, xpMax, role, roleName, combat = { name, icon, rank }, utility = {...} }`.
  - Companion ID: `GetMajorFactionData(GetDelvesFactionForSeason()).playerCompanionID`, but only when that faction's
    `expansionID` is the character's content expansion. On a 12.1 client the season may be Midnight's (Valeera) while
    the user runs War Within delves with Brann. Otherwise Tomte reads the expansion's `delves.companionFaction`
    directly: name and level only, no role or curios, since those need the companion ID.
- **Role clash** (pure, `Delves_RoleHint(playerRole, companionRole)`):
  - You're a tank and the companion tanks: "Brann is set to Tank: Healer suits a tank".
  - You're a healer and the companion heals: "...: Damage suits a healer".
  - Otherwise nil.
  - Your role is the 5th return of `C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())`
    ("TANK", "HEALER", "DAMAGER").
  - The companion's role: the role node's active entry `subTreeID`, compared with
    `C_DelvesUI.GetRoleSubtreeForCompanion(Enum.CompanionRoleType.Dps|Heal|Tank, companionID)`. The role names shown
    are the subtree names from the game, so this works in any client language.
- **Delver's Journey:** the same `GetMajorFactionData` → "Delver's Journey: renown 7 (1200/2500)".

### 5. Tier picker note (`Entrance.lua`)

- On `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `TieredEntrance`, a small `UI.Panel` card is anchored to the right
  of `DelvesDifficultyPickerFrame`, after a 0-second timer so the frame exists. It hides on the matching `_HIDE`.
  - Tomte doesn't hook or change Blizzard's frame; it only anchors to it (a normal frame, not secure).
- Lines:
  - **For your vault:** the `Delves_VaultPlan` advice.
  - **For your gear:** pure `Delves_SuggestTier(tiers, ilvl)`: the highest unlocked tier whose `suggestedILvl` is at
    most your equipped item level ("Tier 7 suits your item level 652"), from `GetDelveEntranceTiers()` and
    `GetAverageItemLevel()` (equipped).
  - **Keys:** the key line, plus "Bountiful" when this entrance is today's bountiful one, matched by the map name and
    `GetDelveEntranceTitleString()` against the scan.
  - **Companion:** level, role, and the role hint.
- Option "Note at the delve entrance", on by default.

### 6. Delves page (Tomte window)

A Home page entry (`kind = "page"`, key `delves`). It shows:

- **Header:** the key line and the Delver's Journey line.
- **Today:** every delve of the expansion, bountiful first, with zone, a "Bountiful" tag and click to track. With no
  bountiful delves found: "No bountiful delves found. Open the map once if this looks wrong." The cache fills from
  map APIs that may need the zone's data.
- **Great Vault, World:** three `ns.WeeklySlot` boxes with "Tier n" under each, the advice line, and the item level
  ladder ("Tier 4: 623 · Tier 6: 636 · Tier 8: 649") when the game gives it.
- **Companion:** portrait (`SetPortraitTextureFromCreatureDisplayID`), level and XP bar, role, the two curios with
  rank (hover: the curio link's tooltip), and the role hint.
- Summary on Home's rail: "2 bountiful · 3 keys".

### 7. Integration

- **Home "Around you"** (`kind = "around"`, key `delvesaround`): the delves in your zone, bountiful first; click to
  track. The title is "Delves: 1 bountiful here". The block hides when the zone has no delves.
- **Next up:**
  - `nextbountiful` "Bountiful delve with a key", score 60: one candidate per bountiful delve while you hold a key;
    bonus 9 for your zone. Its key includes the POI, so a new day is a new suggestion. Click to track.
  - `nextdelvetier` "Delve tier for your vault", score 55: the vault advice, only for a slot that is unlocked but
    below the top tier. Unlocking a slot is Weekly's "Vault slot one activity away". Click opens the Delves page.
  - `nextcompanionrole` "Companion role", score 45: the role hint, when there is one.
- **Moments:** a new type `companion` "Companion level" (banner by default). Delves calls
  `ns.Moments_Trigger("companion", { label = "Level " .. n, title = companionName })` when the friendship level
  rises (compared with the level stored at the last read, never on the first read after login).
- **Weekly:**
  - `ReadCurated` in `Modules/Weekly/Activities.lua` becomes `ns.Weekly_ReadCurated(expansion)`, and it passes an
    entry's new optional `kind` through.
  - `Data/WarWithin/Weekly.lua` marks its key and shard flag entries `kind = "keys"` / `"shards"`, so Delves finds
    them without matching labels.
  - Nothing else in Weekly changes.

## Data

New files `Data/WarWithin/Delves.lua` and `Data/Midnight/Delves.lua` register `"delves"`:

```lua
{
	continent = 2274,
	zones = { 2248, 2214, 2215, 2255, 2346, 2371 },
	bountifulPOIs = { [7787] = true, ... },   -- The War Within only (from Plumber, facts); Midnight relies on the atlas
	keyCurrency = 3028,
	shards = { items = { 245653, 236096 } },  -- Midnight: { currency = 3310 }
	shardsPerKey = 100,
	companionFaction = 2640,                  -- Midnight 2744
	vaultTopTier = 8,                         -- fallback only
}
```

A `Content_AddCheck("delves", ...)` line for `/tomte data`: zones read, delves found, bountiful found, companion
faction and season number. That way a friend with Midnight can check the Midnight IDs.

`TomteDB.delves`:

```
around = true
entrance = true
roleHint = true
nextNeedsKey = true      -- Next up only suggests bountiful delves while you hold a key
companionLevel = {}      -- [companion faction] = last level seen (for the moment)
```

## Files

| File | Contents |
|---|---|
| `Data/WarWithin/Delves.lua`, `Data/Midnight/Delves.lua` | The `delves` table. |
| `Modules/Delves/Data.lua` | Pure: sort, key line, vault plan, tier suggestion, role hint, ladder from steps. |
| `Modules/Delves/Scan.lua` | Delve POI scan and cache, tracking. |
| `Modules/Delves/Read.lua` | Keys, vault, companion readers (out of combat, debounced), companion level moment. |
| `Modules/Delves/Entrance.lua` | The tier picker note. |
| `Modules/Delves/Page.lua` | The window page. |
| `Modules/Delves/Delves.lua` | `RegisterModule`, events, options, commands, Home entries, content check. |

- **Commands:** `/tomte delves` opens the page; `/tomte delves list` prints today's delves (bountiful marked) and the
  key line; `/tomte delves vault` prints the plan and ladder; `help`.
- **Options:**
  - "Delves in Around you", "Note at the delve entrance", "Companion role hint";
  - "Suggest bountiful delves only when you have a key" (Next up).
  - The Next up sources have their own switches in Next up, and the moment has its style in Moments.
- **Look:** `UI.Panel`, `UI.Text` with roles. Bountiful uses the `accent` role and its atlas `delves-bountiful`; a
  normal delve uses its POI atlas. No `|cff` literals.

## Error handling

- Every reader checks `InCombatLockdown()` and waits for `PLAYER_REGEN_ENABLED`. Every `C_*` table that may be missing
  (`C_DelvesUI` in a trial account, a nil `GetAreaPOIInfo`) is guarded and leaves that part empty.
- `GetNextActivitiesIncrease` loops stop at 20 steps or a level that doesn't rise.
- No companion (before the delves intro quest): the companion part says "Unlocks with your first delve". No season
  faction: the fallback faction. Neither: hidden.
- Below the delve level: page says "Delves open at level N"; Around you and Next up stay empty.
- Entrance card: if `DelvesDifficultyPickerFrame` isn't there after the timer, nothing shows.

## Testing

- **Unit tests** (`tests/test_delves.lua`, plain Lua 5.1):
  - sort;
  - key line, both shard kinds and with no shards;
  - vault plan: no runs, only world activities, mixed tiers, all maxed, thresholds 1/4/8 and 2/4/8;
  - ladder from stubbed steps, including no season data and a loop that doesn't rise;
  - tier suggestion: locked tiers, ilvl below every tier;
  - role hint for each role pair;
  - bountiful detection (by atlas, by ID, neither);
  - content data for both expansions loads and has the fields.
- **In game** (user, War Within at 80):
  - `/tomte delves list` matches the bountiful icons on the zone maps;
  - click one: the marker shows the delve's name;
  - keys match the currency tab;
  - the vault advice matches the Great Vault tooltip;
  - the companion level, role and curios match Brann's window;
  - the entrance note at a delve;
  - `/tomte data` delves line.
  - A Midnight friend runs `/tomte data` and `/tomte delves list`.

## Later (not in this design)

- Bountiful pins on the continent map (Khaz Algar), as Plumber does.
- Story variant ratings ("good for Brann XP", "fast"): needs a curated list per season.
- The weekly crest stash count (Gilded Stash), if a reliable API appears.
- Seasonal nemesis and its weekly lair.
- Delver's Bounty / Trovehunter's Bounty map item reminder.
- A secure "Combine shards" button.

## Things only the game can answer (checked in the first in-game test)

- Whether War Within bountiful delves still rotate daily for an account without Midnight on 12.1, and whether
  their POIs carry the `delves-bountiful` atlas or only the known IDs.
- Which season `GetDelvesFactionForSeason()` returns for that account (Midnight's or none), and so whether Brann's
  role and curios can be read for it.
- Whether `GetNextActivitiesIncrease` has season data for War Within delves on 12.1. If not, the vault advice uses
  `vaultTopTier` 8 and shows no item levels.

## Open questions for the user

1. **Next up with no key:** suggest bountiful delves only while you hold a key (the default above), or always? A
   bountiful delve without a key still gives a normal run.
2. **Entrance note:** a card beside Blizzard's tier picker (decided above), or keep the picker untouched and show it
   only on the page?
3. **Companion role hint:** useful, or noise? (A Prot Paladin with Brann on Tank is the case it catches.)
4. **Map:** no Tomte map tab or pins (Blizzard draws bountiful on zone maps). Want the continent pins anyway?

## User decisions (2026-10-10)

- Next up and bountiful delves: the user wasn't sure. Default: only while you hold a Restored Coffer Key, with a setting "Suggest bountiful delves: with a key / always".
- The rest of the open questions: Claude decides.
