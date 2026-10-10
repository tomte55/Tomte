# Tomte: Holidays & events

Date: 2026-10-10. Design for review before anything is built. It grows the "Events & holidays" note in
`future-ideas.md`. Claude made the decisions below; the questions still open for the user are at the end.

## Goal

Know what's on in the world and what you're still missing from it, without opening the calendar:

1. **What's on.** World events active now and the ones starting in the next week, with the time left: holidays,
   the Darkmoon Faire, Timewalking and the weekly bonus events.
2. **What's left.** For the active holidays: the mounts, battle pets, toys and achievements you don't have yet, and
   the holiday's daily boss if you haven't done it today.
3. **Darkmoon Faire chores.** The faire's monthly profession quests for the professions you have, and whether each
   is done.
4. **Don't miss it.** A toast when a holiday with things left starts (it goes into Recent), Next up suggestions
   (daily boss, profession quests, an event about to end), a block on Home and the faire quests in the Weekly
   board's "Still open" list.

Success: on the first day of Hallow's End the user gets a toast saying what's left, Home shows the Headless Horseman
as not done today, and a click opens the Dungeon Finder.

## Research summary

API, checked against wow-ui-source live (12.1.0.69933) and warcraft.wiki.gg:

- **Calendar data needs a request.** `C_Calendar.OpenCalendar()` asks the server; `CALENDAR_UPDATE_EVENT_LIST`
  (no payload) fires when the data is there. The wiki says a request made during loading (even at
  `PLAYER_ENTERING_WORLD`) doesn't return, so Tomte asks a few seconds after the first loading screen. Holidays
  come from the static holiday table, so in practice they're usually readable without the answer, but Tomte reads
  again on the event either way.
- **Month offsets are relative to the calendar's selected month**, not today. Before the calendar is opened that
  month is `C_Calendar.GetMinDate()` (November 2004). Blizzard's own calendar calls `C_Calendar.SetAbsMonth(month,
  year)` with `C_DateAndTime.GetCurrentCalendarTime()` before `OpenCalendar()`; Plumber does the same. Tomte does
  this too, except while Blizzard's `CalendarFrame` is shown (the player is browsing). Then it reads the selected
  month with `C_Calendar.GetMonthInfo(0)` and computes the offset to the current month instead.
  - Side finding: Almost Done's holiday filter (`Modules/Achievements/Achievements.lua`, `Holidays()`) reads offset 0
    after `OpenCalendar()` without `SetAbsMonth`. It may read the wrong month. The shared reader fixes that (task 9).
- **Reading a day.** `C_Calendar.GetNumDayEvents(offset, day)`, then per index:
  - `C_Calendar.GetDayEvent(offset, day, i)` → `CalendarDayEvent`: `eventID`, `title`, `startTime`, `endTime`,
    `calendarType` (`"HOLIDAY"` for world events), `sequenceType` (`"START"`, `"ONGOING"`, `"END"`, `"INFO"`),
    `iconTexture` (fileID), `numSequenceDays`. **It is `SecretInChatMessagingLockdown`**: skip reading while
    `C_ChatInfo.InChatMessagingLockdown()` is true and guard fields with `issecretvalue`.
  - `C_Calendar.GetHolidayInfo(offset, day, i)` → `CalendarHolidayInfo`: localized `name`, `description`, `texture`
    (fileID) and the whole occurrence's `startTime` and `endTime`. Only offsets 0 and 1 are accepted, which is
    enough for "the next 7 days".
  - Times are `CalendarTime` tables in realm time: `year`, `month`, `monthDay`, `weekday`, `hour`, `minute`.
- **Calendar filters.** Blizzard's filter menu sets CVars `calendarShowHolidays`, `calendarShowDarkmoon`,
  `calendarShowWeeklyHolidays` and `calendarShowBattlegrounds`, and the UI itself doesn't skip events by them, so
  the filtering is probably done by the client before the API returns the list. Unverified: the first in-game check
  (`/tomte events calendar`) confirms it. If it holds, Tomte notes "Darkmoon Faire is hidden by your calendar
  filter" rather than changing the player's CVars.
- **Identifying a holiday in any language.** The client's Holidays table (wago.tools) gives each holiday an ID and
  three texture fileIDs (start, ongoing, end). They are stable for the yearly holidays: Darkmoon Faire 479, Lunar
  Festival 327, Love is in the Air 423, Noblegarden 181, Children's Week 201, Midsummer Fire Festival 341, Brewfest
  372, Hallow's End 324, Day of the Dead 409, Pilgrim's Bounty 404, Feast of Winter Veil 141, Pirates' Day 398.
  - Tomte matches `eventID` first. That `eventID` is the holiday ID for `HOLIDAY` events is likely but unverified;
    the texture fileIDs (`iconTexture` / `texture`) are the fallback, the way Plumber and RareScanner identify
    holidays.
  - Pilgrim's Bounty shares its textures with the old Harvest Festival, so it is matched by ID only.
  - Timewalking and the bonus events get a new holiday ID every season (dozens of them), so they aren't matched by
    ID.
- **Daily holiday bosses and Timewalking come from the Dungeon Finder.**
  - `GetNumRandomDungeons()` / `GetLFGRandomDungeonInfo(i)`: returns 16 `isHoliday` and 19 `isTimeWalker`; 2 is the
    localized name.
  - `IsLFGDungeonJoinable(id)` → `isAvailableForAll, isAvailableForPlayer, hideIfNotJoinable`.
  - `GetLFGDungeonRewards(id)`: the first return is `doneToday` (as Blizzard's `LFGFrame.lua` reads it).
  - The holiday bosses are LFG dungeons 285 The Headless Horseman, 286 The Frost Lord Ahune, 287 Coren Direbrew and
    288 The Crown Chemical Co. (wago.tools LFGDungeons). They are only listed while their holiday runs.
  - Timewalking is on when a random dungeon with `isTimeWalker` is joinable. It runs reset to reset, so its end is
    `C_DateAndTime.GetSecondsUntilWeeklyReset()`.
  - The `C_LFGInfo` namespace has nothing for this; the legacy globals are the only API.
  - Opening the finder: `PVEFrame_ShowFrame("GroupFinderFrame", LFDParentFrame)`; `LFDQueueFrame_SetType(id)`
    selects the boss (Plumber does this on `LFDParentFrame` show). Calling Blizzard UI functions from addon code
    can taint the queue button. Tomte only selects out of combat, and the in-game test checks that queueing still
    works. If it doesn't, Tomte opens the finder without selecting.
- **Achievements are game data.** The World Events category is 155. Its child categories are, by
  `GetCategoryInfo(id)` → `title, parentID`:
  - 160 Lunar Festival, 187 Love is in the Air, 159 Noblegarden, 163 Children's Week, 161 Midsummer;
  - 162 Brewfest, 158 Hallow's End, 14981 Pilgrim's Bounty, 156 Winter Veil;
  - 15101 Darkmoon Faire, 15454 Timewalking.

  `GetCategoryNumAchievements(cat)` counts the visible ones (no other faction's, no hidden later steps of a series);
  `GetAchievementInfo(cat, i)` reads them. No walk over all achievements is needed. The category's title is also a
  second localized name for the holiday.
- **Mounts and pets: source text.** The journals have no holiday field. The source text names the holiday on most
  holiday items. This was checked on the client's Mount, BattlePetSpecies and Toy tables (wago.tools):
  - Most say `Holiday: Brewfest` or `World Event: Hallow's End`, in the client's language.
  - Darkmoon items mostly say `Zone: Darkmoon Island` and cost `|Hcurrency:515|h` (Darkmoon Prize Ticket).
  - Holiday vendors' costs carry the currency's icon, a language-free texture path, for example
    `inv_valentinescard01`, `achievement_halloween_candy_01`, `inv_summerfest_fireflower`, `inv_misc_elvencoins`
    and `achievement_noblegarden_chocolate_egg`.
  - Timewalking items cost `|Hcurrency:1166|h` (Timewarped Badge).
  - Mount `sourceType` (World Event) is not reliable: the holiday mounts are mostly flagged Drop.
  - Collect here's parser (`ns.Collect_ParseSource`, `Collect_LowerMentions`) already reads these lines with
    localized labels.
- **Toys have no source API.** `C_ToyBox.GetToyInfo(itemID)` returns `itemID, name, icon, isFavorite, hasFanfare,
  quality`. The only way to list toys is the Toy Box's filtered list, which shares its filters with the Collections
  window (Tomte never touches journal filters). The client's Toy table has the source text, so a dev script
  generates a toy → holiday table from it. That is game data and IDs only, like Waypoints' network. Ownership:
  `PlayerHasToy(itemID)`.
- **Darkmoon Faire profession quests** are once per faire and their completion flag clears when the next faire
  starts, so `C_QuestLog.IsQuestFlaggedCompleted(id)` answers "done this faire".
  - The professions you have come from `GetProfessions()` and `GetProfessionInfo(i)` (7th return: `skillLine`).
  - Quest names come from `C_QuestLog.GetTitleForQuestID` (async: `C_QuestLog.RequestLoadQuestByID` and
    `QUEST_DATA_LOAD_RESULT`).
  - Quest IDs checked on warcraft.wiki.gg: 29506 Alchemy, 29507 Archaeology, 29508 Blacksmithing, 29514 Herbalism,
    29515 Inscription, 29517 Leatherworking, 29518 Mining, 29519 Skinning, 29520 Tailoring.
  - From memory, checked in game with `/tomte events ids` before release: 29509 Cooking, 29510 Enchanting, 29511
    Engineering, 29513 Fishing, 29516 Jewelcrafting.
- **No 12.x changes** to the calendar or LFG functions above in the 12.0.0 API change list. None of them is
  protected.

Sources and licenses: the holiday, LFG dungeon, category, currency, quest and texture IDs are game facts (Holidays,
LFGDungeons, Achievement_Category and Toy tables from wago.tools, already credited in README). No list is taken
from another addon. Plumber's use of `SetAbsMonth` and `LFDQueueFrame_SetType` was read for reference; no code is
taken.

## Pieces

Module key `events`, name "Holidays & events", category "Collections", **enabled by default**. Nothing it does
spends anything or changes a setting.

### 1. Calendar reader (`Calendar.lua`)

- `ns.Events_Request()` runs 5 s after the first `PLAYER_ENTERING_WORLD`. It sets the month to the current one (when
  Blizzard's calendar isn't shown) and calls `OpenCalendar()`. Reads happen on `CALENDAR_UPDATE_EVENT_LIST`
  (debounced 1 s), at the daily reset and when Home or the page is shown (cached for 60 s).
- It reads today through today + `soonDays` (default 7). For each `HOLIDAY` event, `GetHolidayInfo` gives the name,
  description and full start/end; `GetDayEvent` gives `eventID` and `iconTexture`.
- Pure step (`Data.lua`): dedupe the per-day rows into occurrences (key = holiday or name + start minute), work out
  "active" (started, not ended) or "soon" (starts within the window), and sort: active by time left, then soon by
  start.
- Timewalking from the Dungeon Finder joins the list as an active event named after the random dungeon ("Random
  Timewalking Dungeon (Cataclysm)"), ending at the weekly reset. The calendar's own Timewalking row (recognized by
  its texture, from the generated list; Timewalking gets new holiday IDs every season) is dropped when the finder
  found one, so it shows once.
- Every other calendar holiday (bonus events, anniversaries) is listed with its name and time left only. The
  "Other events" option (on) hides them.

### 2. Holiday table (`Table.lua`, facts) and generated data (`Generated.lua`)

One entry per yearly holiday:

```
{ key = "hallows", ids = { 324 }, textures = { 235460, 235461, 235462 }, category = 158,
  currencies = {}, icons = { "interface\\icons\\achievement_halloween_candy_01" }, maps = {}, lfg = { 285 },
  extra = { mount = {}, pet = {} } }
```

- `maps` lists uiMapIDs whose localized name counts as a holiday name: Darkmoon Island (407) for the faire.
- `extra` holds the mounts and pets whose source text doesn't name the holiday in any way Tomte can see. It is filled
  from the generator's report below and is expected to stay short.
- Timewalking has its own entry without ids: category 15454, currency 1166, icon `pvecurrency-justice`.
- `ns.EVENTS_DARKMOON_QUESTS = { [skillLine] = questID }` for the 14 professions.
- `Generated.lua` holds `ns.EVENTS_TOYS = { hallows = { itemID... }, ... }` and `ns.EVENTS_TW_TEXTURES`, the
  texture fileIDs of every "Timewalking Dungeon Event" holiday (one set per expansion).

`tools/events.py` (dev only; `tools/` is already left out of the zip):

- It reads wago.tools' Toy, Mount, BattlePetSpecies and HolidayNames CSVs.
- It writes `Modules/Holidays/Generated.lua`: the toys whose source matches a holiday by Tomte's own rules (English
  names plus the currency and icon signals), and the Timewalking textures.
- It prints a report: mounts and pets with a holiday word or currency the runtime rules miss, and toys with the
  World Event source type it couldn't place. Claude places those by hand into `extra` or the toy table.

### 3. What's missing (`Catalog.lua`)

Built per holiday in the window (active or soon) that has a table entry; nothing runs when none is.

- **Signals** per holiday:
  - localized names: the calendar name, the achievement category title and the `maps` names;
  - the currency IDs and icon paths;
  - the extra IDs.
- **Mounts and pets:** a budgeted reader (4 ms per frame, like Collect here's) goes over
  `C_MountJournal.GetMountIDs()` and species 1..6000 once per session:
  - It keeps uncollected, obtainable entries (`shouldHideOnChar` skipped) whose source text matches a holiday's
    signals.
  - A match is: a name mentioned as whole words (`Collect_LowerMentions` on the cleaned text), a
    `|Hcurrency:<id>|h` link, a `|T<icon>` path, or the ID in `extra`.
  - `NEW_MOUNT_ADDED` / `NEW_PET_ADDED` drop learned entries without a re-read.
- **Toys:** `ns.EVENTS_TOYS[key]`, minus `PlayerHasToy`. Names and icons load through
  `Item:CreateFromItemID(id):ContinueOnItemLoad`.
- **Achievements:** the visible achievements of the holiday's category that aren't completed (account-wide
  completion, like Almost Done), with progress from `ns.Ach_ReadCriteria` / `ns.Ach_Percent`. `ACHIEVEMENT_EARNED`
  removes them.
- Per holiday: `{ mounts = {...}, pets = {...}, toys = {...}, achievements = {...} }` and counts.

### 4. Daily bosses and the Darkmoon Faire (`Calendar.lua`)

- **Daily boss:** for each joinable random dungeon with `isHoliday` and not `isTimeWalker`, a row "The Headless
  Horseman: not done today" / "done today" (`GetLFGDungeonRewards`), under its holiday (the `lfg` field).
  `isAvailableForPlayer` false shows "not available on this character" (too low).
  - Click (out of combat): open the Dungeon Finder with the boss selected (see research). Read again on
    `LFG_UPDATE_RANDOM_INFO` and `LFG_COMPLETION_REWARD`.
- **Darkmoon Faire** (when it's active):
  - One row per profession the character has, with the quest name and done / not done. Open ones come first.
  - A note when the character has no primary profession: "No profession quests for this character".
  - Read again on `QUEST_TURNED_IN`.

### 5. Home, Next up, toast, Weekly board

- **Home block** (`kind = "section"`, new slot `"events"`): stacked in the right column after Recent and above
  Around you.
  - Heading "Events", the count of active events on the right. Then one row per active event (icon, name, "6 days
    left", and on the right "14 left" = the missing count), then soon ones greyed ("Brewfest starts in 2 days").
  - At most `homeRows` rows (default 4). It returns height 0 when nothing is active or soon, so it takes no room.
  - Clicking a row opens the Events page at that event. Hovering shows the description and the counts by kind.
  - Home.lua change: add `byslot.events` to the right-column stack.
- **Events page** (`kind = "page"`, key `events`, rail entry "Events", summary "Hallow's End · 6 days"):
  - Active and Soon sections. Each event is a header (name, time left, description in its tooltip). Under it:
    - daily boss row;
    - Darkmoon quests;
    - collapsible "Mounts", "Battle pets", "Toys" and "Achievements" lists. Rows show the icon, the name and the
      source line (Collect's `parsed.line`), or the percent for achievements.
  - Hover: source tooltip, and the model preview for mounts and pets (`Panel/ModelPreview.lua`).
  - Click: an achievement opens it in the Achievements window (`OpenAchievementFrameToAchievement`); other rows
    print their link to chat with Shift-click.
  - A footer line notes calendar filters that hide events, and "Open calendar" (`ToggleCalendar()`).
- **Next up** sources (each a `kind = "next"` home entry, so they get Next up's checkbox and priority):
  - `nextholidayboss` (score 70): "Headless Horseman: not done today"; why: "Hallow's End daily boss, 6 days left".
    Click opens the finder. State = the day, so "not now" with "until it changes" comes back tomorrow.
  - `nextevent` (score 60): an active holiday with things left that ends within 48 h: "Hallow's End ends in 1 day";
    why: "2 pets, 5 achievements left". Click opens the page.
  - `nextdarkmoon` (score 50): "3 Darkmoon Faire profession quests"; why: the profession names. Click opens the
    page.
- **Toast** (owner `events`, so Recent keeps it): when an active holiday with things left is first seen in an
  occurrence (key = holiday key + start minute, saved in `db.toasted`, account-wide since collections are):
  - title "Hallow's End has started", text "2 mounts, 5 pets, 3 toys and 12 achievements left · ends Nov 1".
  - Held in combat. Shown once the catalog is ready, at most 30 s after login. Click opens the page.
  - Recent.lua change: add `{ "events", "Holidays & events" }` to its owner list.
- **Weekly board:** while the faire is on, the Home "Still open for <name>" list gets the character's Darkmoon
  profession quests (done ones greyed, like the weekly quests), and the daily boss row when there is one.
  - Weekly HomeSection asks `ns.Events_WeeklyRows()` when it exists and the module is on.
  - The board's tabs are unchanged: the faire is monthly and the boss daily, not weekly.

## Settings (`TomteDB.events`)

```
home = true            -- block on Home
homeRows = 4           -- 2-8
soonDays = 7           -- 1-14, "Starting within"
other = true           -- list events Tomte has no table entry for (bonus events, anniversaries)
show = { mounts = true, pets = true, toys = true, achievements = true }
toasts = { start = true }
weekly = true          -- Darkmoon quests and the daily boss in the Weekly board's Home list
collapsed = {}         -- page lists, [eventKey .. kind] = true
toasted = {}           -- [occurrence key] = time; a collection (kept on reset), pruned after 60 days
```

Options page: these settings, a "Sample toast" button and "Open calendar".

## Commands

`/tomte events` (open the page), `events list` (what's on and what's left, printed), `events calendar` (raw calendar
rows for today with eventID, texture, and the filter CVars, for the first in-game check), `events ids` (the
Darkmoon quest IDs with their names from the game), `events test` (sample toast), `help`.

## Files

| File | Contents |
|---|---|
| `Modules/Holidays/Table.lua` | Facts: holiday entries, Timewalking entry, Darkmoon quests. |
| `Modules/Holidays/Generated.lua` | Generated by `tools/events.py`: holiday toys, Timewalking textures. |
| `Modules/Holidays/Data.lua` | Pure: calendar time math, month offset, dedupe/classify, holiday lookup, signals and source matching, counts text, Darkmoon and boss rows, toast decision, time text. |
| `Modules/Holidays/Calendar.lua` | Reads the calendar, the finder and the Darkmoon quests. |
| `Modules/Holidays/Catalog.lua` | Budgeted mount/pet reader, toys, achievements, missing per holiday. |
| `Modules/Holidays/Page.lua` | The Events page. |
| `Modules/Holidays/Holidays.lua` | `RegisterModule`, events, Home block, Next up sources, toast, options, commands. |
| `tools/events.py` | Generator for `Generated.lua` and the coverage report. |
| `tests/test_events.lua` | Unit tests for `Data.lua` (and that `Table.lua`/`Generated.lua` load and are well-formed). |
| `Panel/Home.lua` | `events` slot in the right-column stack. |
| `Modules/Recent/Recent.lua` | Owner `events`. |
| `Modules/Weekly/HomeSection.lua` | Rows from `ns.Events_WeeklyRows`. |

TOC: the seven module files after `Modules/Collect/Collect.lua` (they use Collect's `Data.lua`, which is loaded even
when Collect here is off, and `Ach_ReadCriteria` from Achievements, loaded earlier).

## Error handling

- Nothing is read in chat messaging lockdown; secret fields make the row skipped, not an error.
- `GetNumDayEvents` for a day past the end of the month: the reader walks real dates (month lengths from
  `GetMonthInfo(offset).numDays`), so no invalid day is passed. It still `pcall`s, as Almost Done does.
- A holiday without `startTime` / `endTime` (allowed by the docs) is treated as all of that day.
- The finder click does nothing in combat and says so; `PVEFrame_ShowFrame` and `LFDQueueFrame_SetType` are checked
  for existence first.
- The catalog read stops when the module is turned off. Counts show "reading your collections..." until it's done.
- Item and quest names that haven't loaded show "Loading..." and refresh on load.

## Testing

- **Unit tests** (`tests/test_events.lua`, plain Lua 5.1):
  - calendar time to minutes across month, year and leap-day boundaries;
  - month offset;
  - dedupe of a five-day holiday seen on each day;
  - active/soon/ended classification at the edges;
  - lookup by ID, then by texture; ambiguous textures ignored;
  - signal matching with real source strings from the client tables (Holiday:, World Event:, Darkmoon Island zone,
    currency link, cost icon, extra ID, no false match on "Hallowfall");
  - counts text;
  - Darkmoon rows (open first, professions without a quest skipped);
  - boss rows (holiday vs Timewalking, not joinable);
  - toast decision;
  - time text.
- **In game** (user):
  - `/tomte events calendar`: eventIDs, textures, the filter CVars;
  - Hallow's End or whichever holiday is on: page lists, counts, toast after `/reload` with `db.toasted` cleared;
  - the daily boss row and click (then queue to confirm no taint error);
  - at the next faire, the profession quests;
  - a non-English client if a friend has one.

## Out of scope / Later

- One shared journal walk for Collect here and this module (like the shared achievement walk), so mounts and pets
  are read once per session.
- Per-character Darkmoon quests and daily boss state in Alts and the Weekly board's Characters tab.
- Waypoints to holiday vendors, bosses and the faire portal; the items a Darkmoon quest needs.
- Holiday quest dailies (Brewfest, Hallow's End candy buckets) and holiday currencies on hand.
- A reminder before an event ends for things that are only sold then.
- Pet Battle Bonus Event tips (the pet battles spec's "Later").

## Open questions for the user

1. **Category:** "Collections" (next to Collect here) or "General"?
2. **Toast:** only when a holiday starts, or also a heads-up the day before?
3. **Other events:** list the weekly bonus events (battleground, pet battle, world quest, delves) by default, or only
   holidays and Timewalking?
4. **Weekly board:** is "Still open" the right place for the faire quests and the daily boss, or keep them on the
   Events page and Home only?
5. **Almost Done's holiday filter:** switch it to the shared calendar reader in this round (task 9), or leave it?

## User decisions (2026-10-10)

- Toast when a holiday starts. A setting adds a heads-up the day before (off by default).
- The rest of the open questions: Claude decides.
