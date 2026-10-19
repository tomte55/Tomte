# Polish pass E: travel modules

2026-10-19. Part E of the polish pass (`2026-10-19-tomte-polish-overview.md`). Covers Waypoints (Travel), Flight,
Teleports, Smart Mount, Minimap Buttons, Gathering, Fishing, World quests, Gold world quests and Delves. Plan A goes
first and owns the shared combat line (`ns.Print_Combat`), the "module is off" check for commands and key bindings,
and `ns.MapTabs_Open` (WQTab_Open, TpTab_Open); none of that is repeated here. Fishing had no findings.

## What the player notices

- **World quest route steps aside.** A route used to move on only when you handed in the tracked stop. Now:
  - a stop that expires, or is done some other way, is skipped and the next one is tracked ("next: ...");
  - tracking something else yourself (another quest, a map pin, a delve) pauses the route. Chat says so once. The
    route never takes tracking back on a later hand-in; stops you hand in while it's paused still come off the list
    and count toward its gold;
  - the Route button (World quests map tab and Gold world quests window) then reads **Resume route**: a click tracks
    the next stop again, a shift-click stops the route. Tracking the paused stop again yourself also resumes it.
- **Home, "Around you"**: clicking a world quest row tracks that quest (as Next up's rows do) instead of opening the
  map tab. Teleport rows say in their tooltip that a click opens the Teleports tab, where you click the teleport to
  use it (a teleport can't be cast from Home: it needs a secure button).
- **Teleports tab**: with every section that holds your teleports turned off in settings, the tab says "Your
  teleports are all in sections hidden in settings." instead of "No teleports on this character."
- **Numbers and money**: the World quests "Big gold is at least" slider reads "1,000g"; Gathering's page and
  tracker group counts with commas ("1,234 nodes"); `/tomte flight stats` prints gold spent like other gold lines
  ("1,234g", or silver below a gold) instead of coin icons.
- **Tooltips** in these modules use the theme's heading and text colors instead of plain white.

## What changes underneath

- **Delves errors** reach BugSack. The entrance scan (`Scan.lua`) and the keys/vault/companion readers (`Read.lua`)
  ran inside a bare `pcall`. Now `xpcall(..., ns.errorHandler)`. A failed entrance scan is cached for a minute, so
  the page doesn't rescan on every redraw. A failed part reader reports once per part per session and keeps its old
  value, as before. None of the calls inside is an API that legitimately fails on this client, so no narrow `pcall`
  stays.
- **Gathering minimap pins** redraw at most 30 times a second, and not at all while nothing moved (same position,
  zoom, minimap size, facing, followed spot). A rotating minimap still redraws every frame while you turn, so pins
  don't stutter. Before, the update ran every frame whenever the zone had remembered spots, with a
  `C_Map.GetPlayerMapPosition` table each frame.
- **Gathering tracker** events (pet battle start/end, entering the world) are watched from the module's start, not
  from `init`, and unwatched on stop.
- **Gold world quests window**: while rewards load, it rescans every 5 s instead of every 2 s. That matches
  `REQUEST_EVERY` in `Modules/WorldQuests/Scan.lua`: a scan can't send a new load request more often than that.
  Loaded rewards still show at once through `QUEST_LOG_UPDATE` (Gold.lua's `RefreshSoon`). The per-quest retry
  budget already exists (`MAX_REQUESTS`, then `failed`, which leaves `pending`), so the fast polling already stops.
- **Flight** reads the Waypoints unit setting through a new `ns.Way_Metric()` (Modules/Travel/Waypoint.lua) instead
  of `ns.modulesByKey.way.db.metric`.
- **Minimap Buttons**: the pre-1.10 `angle` key moves into migration 12 (`Core/Migrations.lua`, test in
  `tests/test_migrations.lua`) instead of being reshaped in `init` on every load.
- **Gathering defaults**: the comment on `tracker` names the `point` key Edit Mode saves. A `point = false` default
  isn't added: Core/Profile.lua skips any default table with a `point` key, so `tracker.shown` would drop out of
  settings strings.

## Route rules (pure)

In `Modules/WorldQuests/RouteOrder.lua` (already pure; tests in a new `tests/test_wq_route.lua`):

`ns.WQRoute_Step(r, up, tracked) -> ids, action`

- `r = { ids, current, paused }`: the stops left in order, the stop last tracked (nil before the first), paused.
- `up = { [questID] = true }`: the quests still up (the owner's provider).
- `tracked`: the super-tracked quest ID, `0` for nothing, `-1` for something that isn't a quest, `nil` when it can't
  tell (a track waiting for the end of combat, or your corpse).
- Returns the stops still up, in order, and one action: `"done"` (none left), `"track"` (track `ids[1]`; the current
  stop is gone or there is none yet), `"pause"` (the player tracks something else), `"resume"` (paused, and the
  player tracked the current stop again) or `nil`.
- While paused only `"done"` and `"resume"` come back. With `tracked == nil` it never pauses.

Route.lua runs a check one second after `QUEST_TURNED_IN` (for a stop), `QUEST_REMOVED` (for a stop) or
`SUPER_TRACKING_CHANGED`, so a hand-in's own events land first. It also checks every 30 s while a route runs, since
an expired world quest fires no event of its own. warcraft.wiki.gg: `QUEST_REMOVED` (questID, wasReplayQuest),
`SUPER_TRACKING_CHANGED` (no payload). `C_TaskQuest.IsActive` isn't used: the wiki marks it AllowedWhenUntainted. The
owners' providers already rescan what is up.

New: `ns.WQRoute_Paused()`, `ns.WQRoute_Resume()`, `ns.WQRoute_ButtonText()`, `ns.WQRoute_Click(start)`.

## Checked, not changed

- **Minimap "new" dot and the Flight zone-text diamond read the theme color once.** The theme only changes on a
  reload (Panel/Window.lua: "The new theme shows after a reload"; `Theme.Apply` runs once from Core.lua at
  ADDON_LOADED). Both are created after that, so they always get the current theme's color. No theme-change callback
  exists, and none is needed.
- **tests/test_theme.lua didn't catch the white tooltip colors.** That's by design: `NumericColor` lets pure white
  and black through (white shading on textures, Blizzard's tooltip white). Tightening it for tooltip calls now would
  fail on 66 lines in 39 files, most outside this part. This part fixes its own 17 lines. Closing the hole belongs
  in a later pass once every part has cleared its files.
- **Gold world quests opacity and scale sliders build their own percent.** They already go through the slider's
  `format` option (Panel/Options.lua), the same way Fishing, Pet Health, DressUp and Waypoints do. A shared percent
  formatter in Core would touch every module, so it isn't added here.
- **Gold window retry cap.** Already in place (`MAX_REQUESTS` per quest, then `failed`, then a retry after
  `RETRY_FAILED`). Only the polling interval changes.
- **`C_CurrencyInfo.GetCoinTextureString` in `Modules/Alts/Send.lua`**: not a travel module; left to its part.
- **"not in combat." in Flight's Around open and the commands that refuse while a module is off**: Plan A rewrites
  them.
