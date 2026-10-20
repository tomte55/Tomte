# Housing decor (`decor`)

2026-10-20. Module 6 of the addon round (`2026-10-20-tomte-addon-round-overview.md`). Inspired by Home Bound,
HomeDecor and DecorDrops. Built before the user owns Midnight, so it can't be checked in game with a house yet. Every
decision below is **Claude's call** (the user handed them over: "pick sensible defaults, we tweak after").

## Intent

Player housing decor is the biggest new collection of Midnight. Blizzard's catalog shows what exists, but not "what am
I missing, where do I get it, and is there a vendor right here". Tomte answers that from the game's own data, read-only.

## Goals

- A **Decor page** (Tomte window): the decor you're missing, grouped by source (vendor, achievement, quest, drop,
  profession, other), a source filter, search (name, source line, vendor, zone), owned/missing counts, "Show
  collected", a turning model on hover, click to track, shift-click to link.
- A **tooltip line** on decor items: "Decor: collected (n)" / "Decor: not collected".
- **Next up** source and **Around you** block: "Decor vendor here: N decor you're missing" when a vendor in your zone
  sells decor you lack.
- `/tomte decor scan` (counts per source) and `/tomte decor why <item link or ID>`.

## Non-goals

- No hand-curated decor lists, vendor coordinates or other addons' data (license, CLAUDE.md "Sharing").
- No decor achievement rewards: Almost Done already shows them (`Modules/Achievements/Rewards.lua`).
- No buying, placing or house editing. No Housing Market (shop) data.

## Defaults (Claude's call)

- On by default: read-only, one tooltip line, nothing on screen unless asked.
- Tooltip line on, model preview on. Page filter: all sources, collected hidden.
- Next up score 40 (below vault/rares, above filler). Around you block hidden when no vendor here sells missing decor.

## API findings (12.1.5)

Sources: Blizzard's generated API docs in wow-ui-source (live), Blizzard's housing UI, warcraft.wiki.gg.

| What | API | Notes |
| --- | --- | --- |
| List every decor | `C_HousingCatalog.CreateCatalogSearcher()` then `SetCollected(true)`, `SetUncollected(true)`, `SetBaseVariantOnly(true)`, `SetResultsUpdatedCallback(fn)`, `RunSearch()`, `GetCatalogSearchResults()` -> entryVariantIDs | Async. As Blizzard_HousingDashboardCatalog.lua does. Other addon authors measured that the callback can stay silent right after login: Tomte waits 8 s and searches again after 10 s, up to 3 times. |
| Entry info | `C_HousingCatalog.GetCatalogEntryInfo(entryID)` -> `HousingCatalogEntryInfo` | `recordID` (decor ID), `entryType` (1 = Decor, 2 = Room), `itemID`, `name`, `iconTexture`/`iconAtlas`, `asset` (model file), `uiModelSceneID`, `quality`, `totalNumStored`, `remainingRedeemable`, `totalNumPlaced`, `sourceText`. Owned = stored + redeemable + placed (Blizzard_HousingCatalogUtil.GetEntryTotalOwned). |
| By item | `C_HousingCatalog.GetCatalogEntryInfoByItem(itemInfo)` | Tooltip line. 12.0.5 removed its `tryGetOwnedInfo` argument (wiki). Only asked for items of class `Enum.ItemClass.Housing` (20), subclass `Enum.ItemHousingSubclass.Decor` (0). |
| By decor ID | `C_HousingCatalog.GetCatalogEntryInfoByRecordID(entryType, recordID)` | Re-reads one decor after `HOUSE_DECOR_ADDED_TO_CHEST(decorGUID, decorID)`. |
| Changes | `HOUSING_STORAGE_UPDATED`, `HOUSE_DECOR_ADDED_TO_CHEST`, `HOUSING_SERVICES_AVAILABILITY_UPDATED` | Registered with pcall (a client without them stays quiet). |
| Housing on/off | `C_Housing.IsHousingServiceEnabled()` | What the Housing micro button checks. `C_Housing.HasHousingExpansionAccess()` exists too but gates owning a house, not the catalog. |
| Tracking | `C_ContentTracking.IsTrackable/IsTracking/StartTracking/StopTracking(Enum.ContentTrackingType.Decor, decorID)`, `GetCollectableSourceTrackingEnabled()`, `C_SuperTrack.SetSuperTrackedContent(type, id)` | Blizzard's catalog tracks decor the same way (Blizzard_HousingCatalogUtil.TrackHousingDecorID); the objective tracker shows the vendor/achievement/boss and the map leads there. |
| Model | ModelScene `TransitionToModelSceneID(uiModelSceneID or 1317)`, actor tag `"decor"`, `SetModelByFileID(asset)` | As Blizzard_HousingModelPreview.lua. |

**Accounts without Midnight.** Blizzard announced that players without Midnight can craft and buy decor from the
"The Warning" update on (the 12.0 pre-patch), and the Housing micro button is only disabled when the housing service is
off, not by expansion. So the catalog should answer on the user's account today. If it doesn't, the module shows
"Housing isn't available" on its page and stays silent elsewhere.

**Source text format.** The catalog's `sourceText` is assumed to use the journals' labelled lines
(`|cFFFFD200Vendor: |rName|n|cFFFFD200Zone: |rZone|n|cFFFFD200Cost: |r...`), possibly with currency hyperlinks
(another addon reads `currency:(%d+)` out of it). Not confirmed: `/tomte decor why` prints it raw to check.

### What's possible and what isn't

- Possible: every decor, its owned count, source text, icon, model; tracking through Blizzard (which gives navigation
  to vendors where Blizzard knows them).
- Not possible from the API: vendor coordinates for untracked decor, the achievement ID behind an achievement source
  (only its name in the text), drop rates. `C_ContentTracking.GetTrackablesOnMap` / `GetVendorTrackingInfo` look like
  they only answer for tracked items, so "vendor in your zone" matches the source text's zone line against your zone's
  names instead (localized: both come from the client).

## UI

- **Decor page** (`order = 42`, after Events): segmented source filter on top; search box, "Show collected" checkbox and
  the status ("312 of 1,840 collected · 1,528 missing", or "Reading the housing catalog... 40%") below; then sections
  per source with a "- Vendors   40 missing" header (click folds it). Rows: icon, name ("tracked" mark), right side
  vendor · zone, the source line, or "Collected (n)". Hover: the item tooltip, the source lines, the click hints and the
  model card. At most 400 rows at once, with a note to search or pick a source.
- **Rail pill:** decor you're missing from vendors in your zone (shown above 0).
- **Next up:** one candidate per zone; click tracks the first missing decor of the vendor with the most.
- **Around you:** one row per vendor with how many; hover lists the decor; click tracks the first.

## Settings

| Key | Default | Row |
| --- | --- | --- |
| `preview` | true | "Model preview" |
| `tooltip` | true | "Collected or not on decor items" |
| `filter.source`, `filter.owned` | `"all"`, false | the page's filter (not in settings) |
| `collapsed` | `{}` | folded page groups |

Buttons: "Decor page: Open", "Housing catalog: Read again".

## Commands

- `/tomte decor open`
- `/tomte decor scan`: reads the catalog again, then prints totals, per-source counts and the vendors here.
- `/tomte decor why <item link or ID>`: item class, catalog entry, owned breakdown, raw source text (escaped), how
  Tomte read it, zone names on both sides, trackable or not, model.

## Files

`Modules/Decor/Data.lua` (pure, `tests/test_decor.lua`), `Catalog.lua` (reader), `Preview.lua` (model card),
`Page.lua` (page), `Decor.lua` (main). The source text parser is Collect here's `ns.Collect_ParseSource` (pure, looked
up at call time).

## Test plan

Unit: `lua Tomte/tests/test_decor.lua` (classification, hyperlink cleaning, vendor/zone, owned count, filter, sections,
counts, vendors here, texts).

In game, **now (no Midnight)**:
1. `/reload`. No BugSack error in the first 15 seconds.
2. `/tomte decor scan`. Expect either counts per source, or "decor: Housing isn't available right now." No error.
3. Open the Tomte window: a Decor row on the rail. Open it: a list or the "isn't available" line.
4. Hover any normal item: no Decor line. If decor is collectable on your account, hover a decor item at a vendor:
   "Decor: not collected" (orange) or "Decor: collected (n)" (green).
5. Turn the module off in settings, hover the decor item again: no line. Turn it on again: the page fills again.

In game, **with Midnight**:
1. Decor page: counts look right against Blizzard's Housing catalog (Collected/Uncollected filters).
2. Pick Vendors, search a zone name: its vendors' decor shows. Hover: model turns next to the tooltip.
3. Click a row: "tracking X" in chat, the objective tracker lists it, the map arrow points to the vendor. Click again:
   stops. Shift-click: the item link in chat.
4. Stand in a zone with a decor vendor: Next up says "Decor vendor here: N decor you're missing"; Around you lists the
   vendor. Buy one decor: within a few seconds N drops by one.
5. `/tomte decor why <link>` on a vendor decor: the source text and "Read as: vendor; vendor <name>; zone <zone>".

## Learned vendor spots (added 2026-10-20 after the first in-game test)

In game, Blizzard's tracking (`C_ContentTracking.IsTrackable`) answered false for vendor decor, so clicking a vendor
row did nothing useful. Vendor coordinates aren't in the API or in DB2 (vendor stock is server-side), Wowhead blocks
scripted reads, and the decor addons that ship coordinates (HomeDecor, Homestead, DecorVendor) don't allow reuse.
The user picked learning on visit (no Friend sharing for now):

- `Vendors.lua`: on `MERCHANT_SHOW` / `MERCHANT_UPDATE`, if the shop sells decor (`GetMerchantNumItems`,
  `GetMerchantItemID`, item class Housing / subclass Decor), Tomte saves the vendor by NPC ID (from `UnitGUID("npc")`)
  with its name, your map position (you stand next to them) and the decor it sells: `db.vendors[npcID] = { name, mapID,
  x, y, items = { [itemID] = true }, seen }`, account-wide. Items add up across visits (rotating stock). No position in
  instances, so nothing is learned there. A chat line says so the first time a vendor is learned.
- Click order (`ns.Decor_Action`): stop Blizzard's tracking if tracked; Blizzard's tracking when it can lead there;
  a waypoint (`ns.TrackPin`) to the learned vendor; else a chat line saying to open that vendor's shop once. The row
  tooltip says which one a click does.
- Matching an entry to a learned vendor: by the item the vendor was seen selling (works in every client language),
  else by the vendor name in the source text.
- Vendors in your zone (rail count, Next up, Around you) also count decor sold by learned vendors on your map.
- `/tomte decor vendors` lists the learned vendors; `/tomte decor why` shows the learned spot for an item.
- Pure rules in Data.lua (`Decor_NpcID`, `Decor_LearnVendor`, `Decor_VendorSpot`, `Decor_LearnedItemsOn`,
  `Decor_Action`), tested in tests/test_decor.lua.
