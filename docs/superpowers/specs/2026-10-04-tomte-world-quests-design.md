# Tomte: World quests

Date: 2026-10-04. Backlog item 10. The user settled the main decisions in a brainstorm (ordering, hidden types,
"Worth it" rules, toast, actions, structure, tab layout), then handed the rest over ("build it and come back to me
when it is all done"). Choices made while building are marked *(decided while building)*.

## Goal

Answer "which world quests are worth doing right now?" for the map being viewed (zone or continent): every active
world quest, grouped and sorted by reward, with what stands out on top, so a route can be planned without hovering
every pin.

## Data: what the 12.1 client offers

Checked against wow-ui-source `live` at "12.1.0 (69933)" (generated API docs plus Blizzard's own use) and
warcraft.wiki.gg. No function used here has secret return values or `HasRestrictions` (they're only
`SecretArguments = "AllowedWhenUntainted"`). The 12.0.5 and 12.1.0 API notes change nothing about world quests.

- **Quests on a map:** `C_TaskQuest.GetQuestsOnMap(uiMapID)` returns `QuestPOIMapInfo` entries: questID, x, y, mapID,
  childDepth?, questTagType?, inProgress, isMapIndicatorQuest and more. (`GetQuestsForPlayerByMapID` was removed in 12.0.)
  - Blizzard's map keeps a quest when `C_QuestLog.IsWorldQuest(id)` is true or it's a map indicator quest.
  - On a continent it only shows the super-tracked one, so a continent here reads each zone child
    (`C_Map.GetMapChildrenInfo(id, Enum.UIMapType.Zone, true)`) and merges by questID.
  - `C_TaskQuest.GetQuestZoneID(id)` gives the quest's zone.
- **Title:** `C_TaskQuest.GetQuestInfoByQuestID(id)` (title, factionID), falling back to
  `C_QuestLog.GetTitleForQuestID`. This is what `QuestUtils_GetQuestName` does.
- **Type:** `C_QuestLog.GetQuestTagInfo(id)` returns tagName, worldQuestType (`Enum.QuestTagType`: Profession 1,
  PvP 3, PetBattle 4, Dungeon 6, Raid 8, WorldBoss 18 and others), quality (`Enum.WorldQuestQuality` 0/1/2), isElite
  and tradeskillLineID.
  - Known professions come from `GetProfessions()` and `GetProfessionInfo(index)`, whose 7th return is the skill line.
- **Time left:** `C_TaskQuest.GetQuestTimeLeftSeconds(id)`. Blizzard's thresholds are `WORLD_QUESTS_TIME_LOW_MINUTES`
  (75) and `WORLD_QUESTS_TIME_CRITICAL_MINUTES` (15).
- **Rewards** (legacy globals Blizzard 12.1 still uses):
  - Money: `GetQuestLogRewardMoney(id)`.
  - Items: `GetNumQuestLogRewards(id)` and `GetQuestLogRewardInfo(i, id)` (name, texture, count, quality, isUsable,
    itemID, itemLevel). The item link comes from `GetQuestLogItemLink("reward", i, id)` and is nil until the item is
    cached.
  - XP: `GetQuestLogRewardXP(id)`.
  - Currencies: `C_QuestLog.GetQuestRewardCurrencies(id)` gives { currencyID, name, texture, quality,
    totalRewardAmount }.
    - A currency for which `C_CurrencyInfo.GetFactionGrantedByCurrency(currencyID)` isn't nil is reputation, not
      currency. Blizzard's own world quest filter does the same.
  - Renown reputation: `C_QuestLog.GetQuestLogMajorFactionReputationRewards(id)` gives { factionID, rewardAmount }.
    The faction name comes from `C_MajorFactions.GetMajorFactionData(id).name` and max renown from
    `C_MajorFactions.HasMaximumRenown(id)`.
- **Async loading:** this follows Blizzard's pins.
  - When `HaveQuestRewardData(id)` is false, call `C_TaskQuest.RequestPreloadRewardData(id)` and redraw on
    `QUEST_LOG_UPDATE`.
  - Item links and item info also arrive late (`GET_ITEM_INFO_RECEIVED`).
  - The list shows a quest with "loading…" until its rewards are in.
- **Collectibles:**
  - Mount: `C_MountJournal.GetMountFromItem(itemID)` → mountID, then `GetMountInfoByID(mountID)` (11th return
    isCollected).
  - Pet: `C_PetJournal.GetPetInfoByItemID(itemID)` (13th return speciesID), then
    `C_PetJournal.GetNumCollectedInfo(speciesID)`.
  - Toy: `C_ToyBox.GetToyInfo(itemID)` returns the itemID for a toy (nil otherwise, *unverified: checked in game*),
    then `PlayerHasToy(itemID)`.
- **Appearances:** `C_TransmogCollection.GetItemInfo(link)` returns appearanceID and sourceID. Then
  `C_TransmogCollection.GetAppearanceInfoBySource(sourceID).appearanceIsCollected`, and
  `C_TransmogCollection.PlayerCanCollectSource(sourceID)` → canCollect (so other classes' armor doesn't count).
- **Max level:** `UnitLevel("player") >= GetMaxLevelForPlayerExpansion()`.
- **Actions:** these are what Blizzard's `WorldQuestPinMixin:OnMouseClickAction` does. None of them is protected.
  - Track: `C_QuestLog.AddWorldQuestWatch(id, Enum.QuestWatchType.Automatic)` and
    `C_SuperTrack.SetSuperTrackedQuestID(id)`.
    - `QuestUtil.TrackWorldQuest` is deliberately not called: it writes a Blizzard upvalue (`lastTrackedQuestID`),
      which would be tainted.
  - Untrack: `C_SuperTrack.SetSuperTrackedQuestID(0)`.
  - Link: `GetQuestLink(id)`. The wiki says it only works for quests in the log, but Blizzard's world quest pin
    links through it via `ChatFrameUtil.TryInsertQuestLinkForQuestID`.
  - Ping: `EventRegistry:TriggerEvent("MapCanvas.PingQuestID", id)`.
    - `WorldQuestDataProvider` registers it and calls `PingPin("questID", id)`, which is only an animation.
    - There's no single-pin highlight API. *(After review: not used, see "Decided while building".)*
  - Map: `WorldMapFrame:SetMapID(zoneID)` for right-click zoom.
- **Tooltip:** `GameTooltip:SetQuestLogItem("reward", index, questID)`, which is what Blizzard's embedded reward
  tooltip does.
  - It's an item tooltip, so Gear Check's `TooltipDataProcessor` post-call adds its verdict line.
- **Not available:**
  - Blizzard's code has no list of War Within currencies. Currencies are ranked generically (by amount within a
    currency), not by a hard-coded table.
  - `WorldMap_DoesWorldQuestInfoPassFilters` returns false until rewards load and follows the map's own filter CVars,
    so it isn't used.

## What's listed

- **Included:** world quests (`C_QuestLog.IsWorldQuest`) on the resolved map, not completed
  (`C_QuestLog.IsQuestFlaggedCompleted`).
- **Hidden by default (each type has an option):**
  - PvP.
  - Pet battles.
  - Profession quests whose `tradeskillLineID` isn't one of your professions. A known profession's quests show.
- **Shown:** everything else, including dungeon, raid and world boss quests, races and elites.
- **At max level, quests with no reward but XP are skipped.** Below max level, XP counts as "Other".

## Ordering (Data.lua)

Each quest is in exactly one section. Sections fold, and the folded state is saved. Order:

1. **Worth it**, which holds any quest whose reward is:
   - a missing mount, battle pet or toy;
   - a clean Gear Check upgrade (`ns.Gear_IsCleanUpgrade`: "upgrade" or "empty slot");
   - optional, off by default: an uncollected appearance you can collect;
   - optional, off by default: gold of at least the threshold (default 500g; a slider in options).
2. **Gear:** the main reward is a weapon or armor that isn't a clean upgrade.
3. **Gold:** the main reward is money.
4. **Currencies.**
5. **Reputation:** renown reputation, or a currency that grants reputation, is the only real reward.
6. **Other:** any other item, XP below max level, rewards still loading, or nothing recognised.

**Main reward,** for the quests not in Worth it: an item (gear → Gear, else Other), else a currency (non-rep) →
Currencies, else money → Gold, else rep → Reputation, else Other. Gold and rep that come along with something else
show as secondary text.

**Sort within a section** (ties always go to the one that expires first, then title):
- Worth it: collectible > upgrade (by %) > appearance > gold (by amount).
- Gear: Gear Check % when there is a verdict, otherwise item level (no-verdict rows after the ones with a verdict).
- Gold: amount. Reputation: amount.
- Currencies: currency name, then amount.
- Other: time left.
- **Dimmed and sorted last:**
  - A currency at its total or weekly cap, shown as "capped".
  - Reputation for a faction at max renown, shown as "max renown".

**Time text:**
- "45m", "3h 20m", "1d 4h". Color tier "critical" at ≤15 min (red), "low" at ≤75 min (orange), otherwise grey.
  These are the map's own thresholds.
- Quests with no time left reported (nil or 0) show no time.

## Where it lives

- **Main: a third map tab** (`ns.MapTabs_Add`, key `wq`, icon `Interface\Icons\INV_Misc_Map_01`, tooltip "World
  quests"), stacked under Teleports and Collect here. MapTabs handles switching. `QuestMapFrame:SetDisplayMode` is
  never called.
- **Extra: one toast on arriving in a zone.** A few seconds after `ZONE_CHANGED_NEW_AREA` (and the first
  `PLAYER_ENTERING_WORLD`), your zone is read.
  - Each quest there that rewards a missing collectible or a clean gear upgrade toasts once per session.
  - Several in one zone merge into one toast: "Hallowfall: 2 world quests worth doing", with the first one named.
  - Clicking it opens the map on this tab. It's on by default and can be turned off.
  - Rewards may still be loading, so the check retries twice, 5 seconds apart. Not in combat.

## The tab

- **Header line:** map name, "N quests", and "· loading rewards…" while anything is pending.
- **Row:** reward icon, title, time left on the right (colored). A second line has:
  - the zone (continent view);
  - tags (Elite, Dungeon, Raid, World boss, Rare/Epic, a profession name);
  - the reward summary, then secondary rewards in grey. Examples: "Mount: Sample Drake",
    "ilvl 619 · Upgrade +3.2%", "1,250g", "450 Resonance Crystals", "+250 Council of Dornogal".
- **Hover:**
  - Pings the quest's pin when the viewed map is a zone. On a continent the pins aren't there.
  - Tooltip:
    - Main reward is an item: the item's own tooltip via `SetQuestLogItem`, with Gear Check's line, under a header
      with the quest title, zone, type and time.
    - Otherwise: title, zone, type, time, then every reward on its own line.
    - Click hints at the bottom.
  - Mount and pet rewards also show the turning model card (`Panel/ModelPreview.lua`, option `preview`, on).
  - Appearance rewards show it as a try-on, through ModelPreview's `{ link }` mode.
- **Left-click:** super-track the quest (watch plus super-track), or stop if it's already super-tracked. The
  Waypoints marker follows super-tracked quests already.
- **Right-click:** on a continent, open the quest's zone on the map. On a zone, stop tracking it.
- **Shift-click:** link the quest in chat.
- Tooltip rule from Collect: a redraw hides GameTooltip only when one of our rows owns it, so map pin tooltips keep
  working.
- **Nothing secure,** so the list works in combat.

## Architecture

New folder `Tomte/Modules/WorldQuests/`:

| File | Purpose |
|---|---|
| `Data.lua` | Pure logic, unit-tested: `ns.WQ_Filter(q, opts)`, `ns.WQ_Classify(q, opts)` (section + sort key), `ns.WQ_Sections(quests, opts)`, `ns.WQ_TimeText(seconds)`, `ns.WQ_RewardText(q)`, `ns.WQ_Tags(q)`, `ns.WQ_ToastText(zone, list)`, `ns.WQ_FormatGold(copper)`. |
| `Scan.lua` | Reads the game into plain quest records: `ns.WQ_ForMap(viewedMapID)` → quests, mapName, kind, mapID, pending. Per-quest reward cache until the quest expires or `QUEST_TURNED_IN`; loading requests. |
| `Tab.lua` | The map tab, rows, tooltip, ping, clicks, model preview. |
| `WorldQuests.lua` | Module registration (`key = "wq"`, category "World"), events, zone toast, options, commands. |

**Quest record** (what Data.lua sees), all plain values:

```
{ id, title, zone, zoneID, seconds, tagName, type ("pvp"|"petbattle"|"profession"|"dungeon"|"raid"|"worldboss"|nil),
  elite, quality, skillLine, knownSkill (bool), loaded (bool), xp,
  money, items = { { name, icon, count, quality, itemID, link, ilvl, gear (bool), mount, pet, toy (each: "missing"|
  "owned"|nil), appearance ("missing"|nil), verdict = { kind, pct, headline } } },
  currencies = { { id, name, icon, amount, capped } }, reps = { { name, amount, max } } }
```

**Changes to existing code:**
- **`Panel/MapTabs.lua`:**
  - `ns.MapTabs_ResolveMap(mapID)` moves here from Collect's Catalog.lua (same code).
  - Collect here calls it. `ns.Collect_ResolveMap` is removed, since only Catalog used it.
  - Reason: World quests must work with Collect here turned off.
- **`Modules/Gear/Gear.lua`:** `ns.Gear_Verdict(link)` returns the verdict table (`kind`, `pct`, …) plus the
  headline text and color key. It returns nil when Gear Check is off, the item isn't loaded yet, or there's no spec.
  It wraps the local `Evaluate`, so no logic is copied.
- **`Tomte.toc`:** the four new files after Collect.

## SavedVariables (`TomteDB.wq`)

```
show = { pvp = false, petbattle = false, otherProfessions = false }
worth = { transmog = false, gold = false, goldAmount = 500 }
collapsed = { worth = false, gear = false, gold = false, currency = false, rep = false, other = true }
toast = true
preview = true
```

## Events

- **`QUEST_LOG_UPDATE`, `GET_ITEM_INFO_RECEIVED`:** redraw the tab, debounced to 0.5 s, only while it's visible.
- **`QUEST_TURNED_IN`, `WORLD_QUEST_COMPLETED_BY_SPELL`:** drop the quest from the cache and redraw.
- **`SUPER_TRACKING_CHANGED`:** redraw (the tracked row gets a marker).
- **`ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`:** the zone toast.
- **While anything is still loading,** an `OnUpdate` tick (1 s) on the visible panel also redraws, the same as Collect.

## Commands

- `/tomte wq open`: the map on this tab.
- `/tomte wq here`: your zone's world quests and their sections, printed in chat. It's also the debug view of what
  the scan read.
- `/tomte wq test`: a sample toast.

## Testing

- `tests/test_wq.lua` (plain Lua, loads Data.lua):
  - filtering by type and profession;
  - XP-only at max level versus below it;
  - main reward and section for each kind;
  - the Worth it rules, including the optional transmog and gold rules and their defaults;
  - sort orders and ties;
  - capped and max-renown dimming;
  - time text and tiers;
  - gold formatting, reward text, tags, toast text.
- The existing tests (`test_collect.lua` and the rest) must still pass after the ResolveMap move.

## Decided while building

- *(after review)* **No Blizzard ping on hover.** `MapCanvas.PingQuestID` fired from addon code writes the map's pin
  pools and ping state while tainted, which can block map pins later in combat. Instead the tab draws its own marker
  (a plain frame on `WorldMapFrame:GetCanvas()`, never a pin) at `C_TaskQuest.GetQuestLocation(id, viewedMapID)`.
  That works on continents too.
- *(after in-game feedback)* **The marker** is Blizzard's super-tracking arrow (`Navigation-Tracked-Arrow`).
  - It's turned to point down and bobs above the pin with a soft shadow. A gold glow got lost on the gold maps,
    and a hand-drawn chevron looked cheap.
  - The bob is a per-frame sine with pixel snapping off, because a looping animation snapped at the top.
  - The strata is `FULLSCREEN_DIALOG`, above RareScanner's `DIALOG` pins.
  - It's scaled to the UI, so it's the same size at any zoom.
  - It resumes rather than restarts when a redraw re-enters the same row.
- *(after review)* The reward cache drops a quest whose end time moved later (the same ID came back). Load requests
  are throttled to one per 5 s per quest. After 6 tries the quest shows "rewards unknown" and stops counting as
  loading, then it's tried again after 2 minutes.
- *(after review)* Gear Check's context is built once per scan (`ns.Gear_Context()`, `ns.Gear_Verdict(link, ctx)`).
  A redraw doesn't restart the model preview. The open tab also redraws every 30 s so time left stays current.
- Choice rewards (`GetNumQuestLogChoices`) aren't read: world quests give fixed rewards, and the choice API wasn't
  verified. A quest with only choices would land in "Other".
- Zone view keeps quests whose `GetQuestZoneID` resolves to the zone or one of its child maps (a city inside it).
  Continent rows are named after the quest's own zone.
- "Not for you" gear (Gear Check's verdict) is dimmed and sorted last within Gear.
- A tracked quest's row has a thin gold bar on its left edge.
- The settings use the module category "World".

## Later (not built)

- A list across every zone of the expansion (a background scan), and a toast for anything anywhere.
- A hard-coded table of War Within currencies to rank "important" currencies (crests, Valorstones) above others.
