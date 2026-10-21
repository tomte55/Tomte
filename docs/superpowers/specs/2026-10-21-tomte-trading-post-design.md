# Trading Post (module `tradingpost`)

2026-10-21. The user asked for help with the Trading Post: "I forget to open the chest to get tender, I also don't know
when I can collect or when the shop refreshes". They didn't know about the Traveler's Log, and want the module to
cover it too. Decisions were delegated ("spec it, plan it, build it"); the calls below are Claude's.

## Why

- Earned Trader's Tender sits in the Collector's Cache at a Trading Post until you open it. That includes the 500
  each month that every account with game time gets, so there's always something to forget.
- The month (shop stock and Traveler's Log) turns over on the 1st and nothing in the game reminds you.
- The Traveler's Log is hidden in the Adventure Guide; friends may not know it exists.

## Goals

1. Say when Tender is waiting in the Collector's Cache, and where to go (one click for a waypoint).
2. Say when the month ends and when a new one has started (new stock).
3. Show the Traveler's Log: points, milestones and the Tender they pay, and the activities sorted so the closest
   ones come first, with a click to track one in the objective tracker.
4. Remember the shop from your last visit this month: what's in it, what it costs, what you already own.

Non-goals: buying, freezing or refunding (Blizzard's UI does that, and buying needs a hardware event); opening
Blizzard's Adventure Guide or Trading Post from code (taint risk, see the map lesson); a wishlist.
Anti-goals: nagging. Every reminder is once per day or once per month, and each can be turned off.

## What the game lets us read (checked on the live UI source, 12.x)

- `C_PerksActivities.GetPerksActivitiesInfo()`: `activePerksMonth`, `displayMonthName`, `secondsRemaining`,
  `activities` (`ID`, `activityName`, `description`, `thresholdContributionAmount`, `completed`, `inProgress`,
  `tracked`, `requirementsList[{completed, requirementText}]`, `eventStartTime`/`eventEndTime` for timed ones),
  `thresholds` (`thresholdOrderIndex`, `currencyAwardAmount`, `requiredContributionAmount`, `itemReward`).
  Readable anywhere. Points earned are not a field: Blizzard sums `thresholdContributionAmount` of completed
  activities and caps it at the largest threshold (copied as `ns.TradingPost_Points`).
- Per-activity progress is only the localized text "3 / 5" in `requirementText`; we parse the two numbers.
- `C_PerksProgram.RequestPendingChestRewards()` then `CHEST_REWARDS_UPDATED_FROM_SERVER` and
  `GetPendingChestRewards()` -> `{ rewardAmount, perksVendorItemID, activityMonthID, thresholdOrderIndex, ... }`.
  Blizzard requests it from the Adventure Guide, so it works away from the vendor (to confirm in game).
- Tender: currency 2032 through `C_CurrencyInfo.GetCurrencyInfo` (account-wide). Events
  `PERKS_PROGRAM_CURRENCY_REFRESH`, `PERKS_PROGRAM_CURRENCY_AWARDED`, `CURRENCY_DISPLAY_UPDATE`.
- The shop (`C_PerksProgram.GetAvailableVendorItemIDs`, `GetVendorItemInfo`) only between `PERKS_PROGRAM_OPEN`
  and `PERKS_PROGRAM_CLOSE`. Item info: `name`, `price`, `purchased`, `perksVendorCategoryID`, `iconTexture`,
  `itemID`, `mountID`, `speciesID`, `transmogSetID`, `itemModifiedAppearanceID`, `doesNotExpire`.
- `C_PlayerInfo.IsTravelersLogAvailable()`: false for trial accounts and low levels.
- No secret values or protected calls involved; tracking (`Add/RemoveTrackedPerksActivity`) is what Blizzard's
  own list calls on a shift-click.

## What the player sees

### Reminders (toasts, owner `tradingpost`, all feed Recent)

- **Tender waiting** (`toasts.waiting`, on): at login, once per day, when the cache holds Tender:
  "500 Trader's Tender waiting in the Collector's Cache." Click: waypoint to the cache.
- **In a Trading Post city** (`toasts.city`, on): entering Stormwind, Orgrimmar or Dornogal with Tender waiting,
  once per session per city. Same click.
- **New month** (`toasts.newMonth`, on): the first login in a new Trading Post month: "New month at the Trading
  Post: new stock and a fresh Traveler's Log." When Tender is also waiting it's one toast with both lines (the
  login "waiting" toast is then skipped that day).
- **Month ending** (`toasts.ending`, on): in the last 3 days, once per day, when a milestone is still open:
  "3 days left in the Traveler's Log: 150 points to the next 100 Tender."

The decision of which toast to show is pure (`ns.TradingPost_LoginToasts`), with the remembered state in db
(`seen.month`, `seen.waitingDay`, `seen.endingDay`).

### Next up

- `nexttender` "Trader's Tender waiting" (score 85): click for a waypoint to the cache.
- `nexttravelerslog` "Traveler's Log milestone" (score 45): in the last 7 days, when a milestone is open:
  "Traveler's Log: 150 points to the next milestone", why = the closest open activity. Click opens the page.

### Around you

`tradingpostaround` "Trading Post", only in Stormwind, Orgrimmar or Dornogal: rows for the cache (Tender waiting,
click for a waypoint), the shop ("3 things you don't have, you have 750 Tender") and the time left.

### The page (rail row "Trading Post", pill = 1 while Tender is waiting)

Top to bottom:
1. Tender line: "750 Trader's Tender" and, if any, "500 waiting in the Collector's Cache" with a Waypoint link.
   "October ends in 9 days: new stock on the 1st."
2. Traveler's Log: points bar to the top milestone with tick marks, "450 / 1000 points", and each milestone as
   "200 · 100 Tender" (reached ones dimmed with a check).
3. Activities: open ones sorted by progress (closest to done first: parsed fraction, then points), then not
   started by points (highest first); each row "name" + right "3/5 · 50 pts", tracked ones marked. Click toggles
   tracking in the objective tracker; hover shows the description and requirements. Completed ones fold into one
   line "12 done" (click to show them).
4. This month's shop (from your last visit this month): rows sorted by category, then price; right side the price;
   colored by state: bought (faint, "Bought"), already owned elsewhere (muted, "Owned"), affordable (accent), not
   affordable (text). Without a visit this month: "Visit a Trading Post to see this month's stock." A shop from an
   earlier month is not shown.

When the Traveler's Log isn't available (trial, below level 10): one line saying so; Tender and cache still show.

### Commands

`/tomte tradingpost` (opens the page), `status` (Tender, waiting, points, time left in chat), `shop` (the remembered
shop in chat), `way` (waypoint to the nearest cache), `test` (sample toast).

### Settings (category `week`)

Header "Reminders": the four toast switches. Header "Page": Open button. Defaults on: each reminder is rare and
about the player's own Tender. `enabledByDefault = true`.

## Where the cache is

Known spots (wiki, Collector's Cache page): Stormwind (uiMap 84) 51.3, 72.4; Orgrimmar (uiMap 85) 48.4, 75.7.
Dornogal has a Trading Post but no published coordinates, so the module learns spots: on `PERKS_PROGRAM_OPEN` it
saves the player's map and position under the city's key (`db.spots`, account-wide). The waypoint picks the
Trading Post on the player's continent if one is known, else the faction's capital (Alliance Stormwind, Horde
Orgrimmar, neutral: none). Pure: `ns.TradingPost_PickSpot`.

City detection for toasts and Around you: the player's best map or its parents match 84, 85 or 2339 (Dornogal).

## Saved variables (`TomteDB.tradingpost`)

```
toasts = { waiting = true, city = true, newMonth = true, ending = true },
seen = { month = 0, waitingDay = "", endingDay = "" }, -- last perks month seen, last day each toast showed
spots = {}, -- [city key] = { map = uiMapID, x = 0..1, y = 0..1 }, learned at the vendor
shop = {}, -- { month = activePerksMonth, at = server time, items = { { id, name, icon, price, category, itemID,
           --   mountID, speciesID, setID, appearanceID, bought } } }
```
`keep` = none needed (all collections). `noShare`: `seen`, `spots`, `shop`.

## Files

- `Modules/TradingPost/Data.lua` (pure, `tests/test_tradingpost.lua`): points, milestones, progress parsing,
  activity sorting, waiting sum, time-left text, toast decision, spot pick, shop summary.
- `Modules/TradingPost/Read.lua`: reads the game into plain tables, chest-reward requests, shop snapshot, owned
  checks, spot learning; events bus `ns.TradingPost_Events`.
- `Modules/TradingPost/Page.lua`: the page.
- `Modules/TradingPost/TradingPost.lua`: registration, toasts, Next up, Around you, commands.

## Testing in game (user)

1. `/reload`, open Tomte: rail row "Trading Post", page fills; compare with Shift+J > Traveler's Log.
2. With Tender in the cache: login toast, Next up row, rail pill; click sets a waypoint to the cache.
3. Click an activity: it shows in the objective tracker; click again removes it.
4. Visit the Trading Post: page shows the shop; Owned/Bought marks right; `/tomte tradingpost shop`.
5. Open the cache: waiting line, pill and Next up row go away.
6. `/console loadDeprecationFallbacks 0` then `/reload`: no errors.
