# Tomte: Weekly board

Date: 2026-10-04. Designed with the user (backlog items 1 and 2: Weekly board + Profession timers).
The user plays one main per week (gathering professions only) but wants a full alt grid for future alts, and
Concentration support that appears automatically for any character with a crafting profession.

## Goal

Answer "what haven't I done this week?" for the current character (panel page + compact popup), show the same for
every tracked character in a grid, and track profession knowledge sources and Concentration, all of it aware of the
weekly reset without the character being logged in.

## APIs (checked against wow-ui-source live + warcraft.wiki.gg, client 12.1.0)

None of these are hardware-event protected; none changed in the 12.0.0 / 12.1.0 API change notes. Read them out of
combat only (no combat logic at all).

- **Vault**: `C_WeeklyRewards.GetActivities(type)` with `Enum.WeeklyRewardChestThresholdType` Raid=3,
  Activities=1 (dungeons), World=6 (delves/world). Fields used: `index, threshold, progress, id, level,
  activityTierID`. Slot item level: `C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)` then
  `C_Item.GetDetailedItemLevelInfo(link)` (what Blizzard_WeeklyRewards does). Vault waiting:
  `C_WeeklyRewards.HasAvailableRewards() and not C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()` (Blizzard's
  own test). Event `WEEKLY_REWARDS_UPDATE`.
- **Currencies**: `C_CurrencyInfo.GetCurrencyInfo(id)` → `quantity, maxQuantity, canEarnPerWeek,
  quantityEarnedThisWeek, maxWeeklyQuantity, totalEarned, useTotalEarnedForMaxQty, rechargingCycleDurationMS,
  rechargingAmountPerCycle`. Event `CURRENCY_DISPLAY_UPDATE`. Season 2 Mistcrests: Adventurer 3442, Hero 3445
  (wiki-verified); Veteran 3443, Champion 3444, Myth 3446 (Wowhead only; one source says Myth 3441, so verify in game).
- **Renown**: `C_MajorFactions.GetMajorFactionIDs(LE_EXPANSION_MIDNIGHT)` (11), `GetMajorFactionData(id)` →
  `name, renownLevel, maxLevel, renownReputationEarned, renownLevelThreshold, isUnlocked`,
  `HasMaximumRenown(id)`. Event `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`.
- **Lockouts**: `GetNumSavedInstances` / `GetSavedInstanceInfo(i)` → `name, lockoutId, reset, difficultyId, locked,
  extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress`. `RequestRaidInfo()` →
  `UPDATE_INSTANCE_INFO`. World bosses: `GetNumSavedWorldBosses` / `GetSavedWorldBossInfo(i)` → `name, id, reset`.
- **Reset**: `C_DateAndTime.GetSecondsUntilWeeklyReset()`, `GetServerTime()`. Next reset is stored as an absolute
  server time, so no region table is needed (EU Wed 04:00 UTC, US Tue 15:00 UTC).
- **Quests**: `C_QuestLog.IsQuestFlaggedCompleted(id)`. Weekly learning: quest log entries with
  `C_QuestLog.GetInfo(i).frequency == Enum.QuestFrequency.Weekly`. Events `QUEST_TURNED_IN`, `QUEST_ACCEPTED`.
- **Professions**: `GetProfessions()` + `GetProfessionInfo(i)` → base `skillLine`. Midnight child skill lines
  (third-party data, WeeklyKnowledge): Alchemy 2906, Blacksmithing 2907, Enchanting 2909, Engineering 2910,
  Herbalism 2912, Inscription 2913, Jewelcrafting 2914, Leatherworking 2915, Mining 2916, Skinning 2917,
  Tailoring 2918. Concentration: `C_TradeSkillUI.GetConcentrationCurrencyID(childSkillLine)` → currency read with
  `GetCurrencyInfo` (gathering returns none). Whether this works without the profession window open is unverified:
  if it returns nothing at login, the snapshot is also refreshed on `TRADE_SKILL_SHOW`.
- **Logout**: `PLAYER_LOGOUT` fires just before SavedVariables are written. API data at that point is not
  guaranteed, so the logout handler only stamps `at`/`nextReset`; the data itself comes from the event-driven
  refreshes.

## Module

Key `weekly`, name "Weekly board", category "General", on by default. One module; Profession timers is a view of it.

## Data model (`TomteDB.weekly`)

```
chars[guid] = {
  name, realm, class, level, at, nextReset,
  vault      = { raid = {slots}, dungeons = {slots}, world = {slots} },  -- slot: { progress, threshold, ilvl? }
  vaultReady = bool,
  currencies = { [id] = { qty, earnedWeek, weeklyCap, total, seasonCap } },
  quests     = { [questID] = true },                 -- completed, for tracked + learned IDs
  renown     = { [factionID] = { level, max, earned, threshold } },
  lockouts   = { { name, difficulty, killed, total, expires, raid = bool } },  -- expires = absolute server time
  profs      = { [childSkillLine] = { name, gathering = bool,
                  knowledge = { [questID] = true },
                  conc = { qty, max, cycleMS, perCycle, at, notified? } } },
}
quests[id] = { title, firstSeen }   -- learned weekly quests, account-wide
hidden[guid] = true                 -- hidden from the grid/professions view
view = "week" | "chars" | "profs"   -- last page view
popup = { point }                   -- popup position
toast = true                        -- Concentration-full toast
learned = true                      -- show learned quests
```

Only characters at max level (`GetMaxLevelForPlayerExpansion()`) write a snapshot.

## Refresh

The current character's snapshot is refreshed (debounced, at most once per second) on: `PLAYER_ENTERING_WORLD`
(after `RequestRaidInfo`), `WEEKLY_REWARDS_UPDATE`, `CURRENCY_DISPLAY_UPDATE`,
`MAJOR_FACTION_RENOWN_LEVEL_CHANGED`, `UPDATE_INSTANCE_INFO`, `QUEST_TURNED_IN`, `QUEST_ACCEPTED`,
`TRADE_SKILL_SHOW`, `SKILL_LINES_CHANGED`. Nothing is read in combat; a refresh requested in combat runs on
`PLAYER_REGEN_ENABLED`. Open views redraw after a refresh.

## View rules (pure, `Data.lua`)

`View(snapshot, now)` returns the display model used by every UI:

- **Stale** (`now >= nextReset`): vault progress 0, weekly quests and knowledge sources not done, weekly currency
  earnings 0. `vaultReady` becomes true if the stale snapshot had any slot with `progress >= threshold` (or was
  already ready). Seasonal currency quantities stay.
- **Lockouts**: dropped when `now >= expires`.
- **Renown**: unchanged.
- **Concentration**: `qty + floor((now - at) * 1000 / cycleMS) * perCycle`, capped at `max`.
  `fullAt = at + ceil((max - qty) / perCycle) * cycleMS / 1000`. Missing rate fields → no prediction (shows the
  stored value and "as of <date>").
- **Next vault goal** per track: the first slot with `progress < threshold`: "2/4 to slot 2", with the ilvl of the
  highest unlocked slot.

## UI

### Board page (panel)

Panel tabs: Options + Weekly. Three buttons at the top of the page: **This week | Characters | Professions**
(remembered in `view`).

- **This week** (current character, sections hidden when empty): a gold "Great Vault waiting" banner when
  `vaultReady`; Great Vault (Raid / Dungeons / World: three slot pips, ilvl on unlocked slots, next goal); Currencies
  (Mistcrests, `qty / cap`, green when capped); Weekly quests (profession weeklies always; learned quests only when in
  the log or done this week); Renown (Midnight factions, level/max + bar); Lockouts (raids + world bosses,
  difficulty, killed/total, reset day).
- **Characters**: grid, one column per tracked character (current first, then by last login), one row per item:
  vault tracks, vault waiting icon in the header, each crest, weekly quests done/total (profession weeklies plus
  learned quests that were in the log or done at snapshot time), each renown, each raid
  lockout. Stale cells are dimmed and show the reset value. Hovering a cell shows the detail tooltip.
- **Professions**: per character, per profession, a card: knowledge sources (trainer weekly, treatise, crafting
  treasures 0-2, gathering drops 0-5 + big drop) and for crafting professions a Concentration bar with
  "Full <day> <time>" or "Full, wasting" (orange).

### Popup

Right-click on the minimap button toggles a small movable window (Esc closes, position saved). It lists only open
items for the current character: vault waiting, vault tracks with next goal, crests under cap, open weekly quests and
knowledge sources, full Concentration. "All done this week ✓" when empty. "Open board" button opens the panel page.
The Minimap module calls `ns.Weekly_TogglePopup` on right-click when the weekly module is active.

### Toast

When a tracked character's predicted Concentration reaches max, one shared-stack toast (owner `weekly`):
"Concentration full: <name>, <profession>". Checked at login and by one `C_Timer` scheduled for the earliest
`fullAt`. `conc.notified` stores the `fullAt` it toasted for, so it fires once per fill; a new reading below max
clears it. `ns.Toast_Clear("weekly")` on toggle-off.

## Commands

`/tomte weekly popup`, `/tomte weekly board`, `/tomte weekly quests` (list learned quests),
`/tomte weekly forget <name>`, `/tomte weekly ids` (prints each crest currency and knowledge quest ID with its name or
"unknown" for in-game validation).

## Options

Concentration-full toast (on), Show learned quests (on), hidden characters (a checkbox per tracked character).

## Files

`Tomte/Modules/Weekly/`: `Data.lua` (pure: ID tables, View, prediction, next goal, grid cells, popup items, sort and
filter), `Collect.lua` (API reads, snapshot, quest learning, events), `Weekly.lua` (registration, options,
commands, toast timer), `BoardPage.lua`, `Popup.lua`. Also `Modules/Minimap/Minimap.lua` (right-click),
`Tomte.toc`, `README.md`, `tests/test_weekly.lua`.

## Testing

Plain Lua on `Data.lua`: stale vs fresh snapshots (one and several weeks old), vault waiting only when slots were
unlocked, lockout expiry (incl. extended), Concentration prediction, cap and fullAt, toast once per fill, next vault
goal at every threshold, popup items (all done / partly done), grid cells incl. stale, character filter and sort.

In game: `/dump C_CurrencyInfo.GetCurrencyInfo(3446)` and `(3441)` for the Myth crest and the cap fields;
`/tomte weekly ids` for the knowledge quest IDs (the gathering drop IDs may be stale); `/reload` with vault progress,
renown and a lockout and compare against Blizzard's vault and raid info.

## Out of scope

PvP vault track, Mythic+ keystone and score, daily quests, gold and bags, opening the vault remotely, automatic
quest pickup, a world event calendar, account-wide currency transfers.

## Changes during the build

- **Vault waiting** is `C_WeeklyRewards.HasAvailableRewards()` alone. Blizzard_WeeklyRewards shows "return to the
  vault to claim" on exactly that when you're away from the vault; the `AreRewardsForCurrentRewardPeriod` part only
  drives its "previous week" notice while at the vault.
- **Logout** stamps only `seen` (grid order). `nextReset` is written only together with fresh data, so a reset
  that happens while you're logged in can never be hidden by a logout stamp. A timer also refreshes 30 s after the
  reset if you're online then.
- **Extra refresh triggers**: `LOOT_CLOSED` (weekly profession drops are hidden quests flagged on loot),
  `QUEST_REMOVED`, `MAJOR_FACTION_UNLOCKED`, `PLAYER_LEVEL_UP`, and opening the board or the popup.
- **Learned quests** are quest log entries with `frequency == Enum.QuestFrequency.Weekly` (not `ResetByScheduler`,
  which also covers dailies); hidden quests and the profession knowledge IDs are skipped.
- **Concentration readings** that fail (nothing returned before the profession window opens) keep the last good
  reading instead of dropping it.
- **This week** also has a Professions section (knowledge done/total and Concentration per profession), so the
  current character's whole week is on one page.
- **Grid header**: "vault waiting" (orange) or "reset since" (grey) under the character's name; hovering the name
  shows when it was last updated.
- **Panel**: `ns.Panel_OpenModule(key, tab)` takes an optional tab ("page"), used by "Open board" and the toast.

## Follows the player's expansion (after the first in-game test)

The user's account doesn't own Midnight (12.1 client, The War Within content). Renown now reads
`C_MajorFactions.GetMajorFactionIDs(GetExpansionLevel())`, and profession data is kept per expansion
(`ns.WEEKLY_PROFS[10]` The War Within / Khaz Algar, `[11]` Midnight, from WeeklyKnowledge's current data). A character
uses the newest table its `GetExpansionLevel()` reaches, and each profession snapshot stores its `expansion`. Buying
Midnight switches over by itself. Mistcrests stay Midnight-only and are hidden while undiscovered. Also fixed: the
gathering drop IDs were never checked (the ID list stopped at the missing `treasures`).

## Knowledge points, hints and waypoints (after the second in-game test)

Every knowledge source carries its point value (trainer quest 1-4, treatise 1, treasures 1-2 each, drops 1 each,
big drop 2-4, per expansion, from WeeklyKnowledge), a hint (where and how) and, for the trainer quest and the treatise,
a location (`ns.WEEKLY_EXPANSIONS`: Dornogal / Silvermoon City, the trainer or Artisan's Consortium, the crafting
orders). Rows read "open · 3 pts" / "2/5 · 1 pt each" / "done", and a profession line shows the points left this week.
Hovering a row (board or popup) shows the hint; clicking a row with a location sets a map pin and super-tracks it
(`C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint`), which the Waypoints module displays.
