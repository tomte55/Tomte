# Polish pass E (travel modules) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the audit findings in the travel modules. World quest routes skip stops that expired, and step aside
when the player tracks something else. Delves errors reach BugSack. Gathering's minimap pins stop redrawing every
frame. Saved-variable, theme and number-format drift is cleaned up.

**Architecture:** The route rules become one pure function, `ns.WQRoute_Step`, in
`Modules/WorldQuests/RouteOrder.lua` (tested in a new `tests/test_wq_route.lua`). `Route.lua` only reads the game and
acts on its answer. The Teleports empty text is a pure `ns.Tp_EmptyText` in `Modules/Teleports/Data.lua`. Everything
else is a small edit in the module's own UI or main file, with no new files in the TOC.

**Tech Stack:** Lua 5.1 (WoW 12.1.5 retail), plain-Lua unit tests in tests/.
**Spec:** docs/superpowers/specs/2026-10-19-tomte-polish-travel-design.md

## Global Constraints

- Files are CRLF with tab indentation; edit Lua with the Edit/Write tools only (no sed, awk or heredocs).
- Lines wrap at about 120 columns, use double quotes, and private helpers are `local function`.
- Comments say why, in plain English; fix any comment that points at code this plan moves.
- Colors come from theme roles (`UI.Color`, `UI.RGB`, `UI.TipLine`), never numeric literals, and are never read at file load.
- Format money and counts with `ns.Gold` / `ns.Price` / `ns.Thousands`, never by hand.
- Never read another module's db directly; ask through an `ns.<Prefix>_*` function.
- Saved keys are only reshaped by a migration appended to the end of `ns.MIGRATIONS`, with a case in `tests/test_migrations.lua`.
- Register events only while the module is active; Stop undoes everything Start did.
- No bare `pcall` around our own code; errors go to `ns.errorHandler`.
- Don't simplify `InCombatLockdown()` guards, `C_Timer` deferrals or secret-value checks that have a reason comment.
- Plan A lands first (`ns.Print_Combat`, the modules-off command check, `ns.MapTabs_Open`); rebase on its edits to these files.
- Run every test from the AddOns folder before calling a task done; CI uses Lua 5.1.
- No commit before the user confirms the change in game; commit messages are `<Module>: what changed`.
- Nothing private goes into code, tests or docs (made-up names only).

## Review Focus

1. **The route pauses when it shouldn't.** Three cases: our own track waits for the end of combat, the player
   dies (the corpse takes over super-tracking), or a hand-in clears super-tracking a moment before
   `QUEST_TURNED_IN`. Covered by Task 1's "can't tell" and "handed-in" tests, plus in-game checks in Task 2 (die,
   fight mid-route).
2. **The route grabs tracking back.** After the player tracks something else, a later hand-in must not move tracking
   onto the next stop. Covered by Task 1's paused tests and Task 2's in-game check.
3. **Minimap pins stutter or trail.** The throttle must not make pins lag while running or turning with a rotating
   minimap, and pins must still update when you zoom the minimap or start following a route. Covered by Task 6's
   in-game check.
4. **Tomte's minimap button vanishes for an old install.** Migration 12 must leave `buttons.minimap.shown = true`
   when it creates the entry. Covered by Task 9's migration tests.
5. **Gathering tracker after off/on.** It must still hide in pet battles and instances after the module is turned
   off and back on mid-session, and nothing may fire while it's off. Covered by Task 7's in-game check.

---

### Task 1: Route rules (pure)

**Files:**
- Modify `Modules/WorldQuests/RouteOrder.lua` (header comment, append `ns.WQRoute_Step` at the end)
- Create `tests/test_wq_route.lua`

**Interfaces:**
- Produces `ns.WQRoute_Step(r, up, tracked) -> ids, action`. `r = { ids, current, paused }`; `up = { [questID] = true }`;
  `tracked` is a quest ID, `0` (nothing), `-1` (not a quest) or `nil` (can't tell). `action` is one of `"done"`,
  `"track"`, `"pause"`, `"resume"` or `nil`.

- [ ] Write the failing test `tests/test_wq_route.lua`:

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_wq_route.lua
local ns = {}
assert(loadfile("Tomte/Modules/WorldQuests/RouteOrder.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Up(...)
	local up = {}
	for _, id in ipairs({ ... }) do
		up[id] = true
	end
	return up
end

test("the first check tracks the first stop", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1, 2 } }, Up(1, 2, 3), 0)
	eq(table.concat(ids, ","), "3,1,2")
	eq(action, "track")
end)

test("the tracked stop expired: it drops out and the next is tracked", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1, 2 }, current = 3 }, Up(1, 2), 3)
	eq(table.concat(ids, ","), "1,2")
	eq(action, "track")
end)

test("a later stop expired: dropped, nothing else happens", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1, 2 }, current = 3 }, Up(3, 2), 3)
	eq(table.concat(ids, ","), "3,2")
	eq(action, nil)
end)

test("nothing left is done", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(), 0)
	eq(#ids, 0)
	eq(action, "done")
end)

test("handed in (already off the list) while the map still lists it: next is tracked", function()
	local _, action = ns.WQRoute_Step({ ids = { 1, 2 }, current = 3 }, Up(1, 2, 3), 0)
	eq(action, "track")
end)

test("the player tracks another quest: pause", function()
	local _, action = ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), 99)
	eq(action, "pause")
end)

test("the player tracks a map pin or nothing: pause", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), -1)), "pause")
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), 0)), "pause")
end)

test("can't tell (combat wait, corpse): never pauses", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1, 3), nil)), nil)
end)

test("can't tell, but the current stop expired: still moves on", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 1 }, current = 3 }, Up(1), nil)), "track")
end)

test("paused: a hand-in elsewhere only shortens the list", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 2 }, current = 3, paused = true }, Up(2, 3), 99)
	eq(table.concat(ids, ","), "3,2")
	eq(action, nil)
end)

test("paused: the current stop expired, still nothing tracked", function()
	local ids, action = ns.WQRoute_Step({ ids = { 3, 2 }, current = 3, paused = true }, Up(2), 99)
	eq(table.concat(ids, ","), "2")
	eq(action, nil)
end)

test("paused: the player tracks the current stop again: resume", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3, 2 }, current = 3, paused = true }, Up(2, 3), 3)), "resume")
end)

test("paused with nothing left is done", function()
	eq(select(2, ns.WQRoute_Step({ ids = { 3 }, current = 3, paused = true }, Up(), 99)), "done")
end)

H.done()
```

- [ ] Run `lua Tomte/tests/test_wq_route.lua` from the AddOns folder: it fails (`attempt to call field 'WQRoute_Step'`).
- [ ] In `RouteOrder.lua`, change the header comment to:

```lua
-- World quest routes: the order to visit stops in, and what a running route does next (pure, no WoW API; order in
-- tests/test_gold.lua, running in tests/test_wq_route.lua). Route.lua reads the spots and the game and runs the route.
```

- [ ] Append to the end of `RouteOrder.lua`:

```lua
-- Running a route: what to do after something changed. r = { ids, current, paused }: the stops left in order, the
-- stop tracked last (nil before the first) and whether the player stepped aside. up = { [questID] = true } for the
-- quests still up. tracked: the quest the game super-tracks now, 0 for nothing, -1 for something that isn't a quest
-- (a map pin, a delve), nil when it can't tell (a track waiting for the end of combat, your corpse).
-- Returns the stops still up, in order, and one action: "done" (none left), "track" (track ids[1]), "pause" (the
-- player tracks something else), "resume" (paused, and the player tracked the current stop again) or nil.
function ns.WQRoute_Step(r, up, tracked)
	local ids, hasCurrent = {}, false
	for _, id in ipairs(r.ids) do
		if up[id] then
			ids[#ids + 1] = id
			if id == r.current then
				hasCurrent = true
			end
		end
	end
	if #ids == 0 then
		return ids, "done"
	end
	if r.paused then
		if hasCurrent and tracked == r.current then
			return ids, "resume"
		end
		return ids, nil
	end
	if not hasCurrent then
		return ids, "track"
	end
	if tracked ~= nil and tracked ~= r.current then
		return ids, "pause"
	end
	return ids, nil
end
```

- [ ] Run `lua Tomte/tests/test_wq_route.lua`: all pass. Run `lua Tomte/tests/test_gold.lua`: still passes.

### Task 2: Route runtime and the Route buttons

**Files:**
- Modify `Modules/WorldQuests/Route.lua`: header (lines 3-6), constants (line 8), state (line 12), Running section
  (lines 81-159).
- Modify `Modules/WorldQuests/Tab.lua`: `UpdateRouteButton` (lines 544-547) and the route button (lines 577-602).
- Modify `Modules/GoldQuests/Window.lua`: the label (line 472) and the route button (lines 598-622).

**Interfaces:**
- Consumes `ns.WQRoute_Step` (Task 1), `ns.WQ_Track`, `ns.SafeTrack_Waiting` (Core/Core.lua), `ns.Gold_StartRoute`.
- Produces `ns.WQRoute_Paused() -> bool`, `ns.WQRoute_Resume()`, `ns.WQRoute_ButtonText() -> "Route" | "Stop route" |
  "Resume route"`, and `ns.WQRoute_Click(start)`. A click resumes a paused route, a shift-click or a click on a
  running route stops it, otherwise it calls `start()`.
- Removes the local `TrackNext` and the constant `NEXT_DELAY` (now `CHECK_DELAY`).

- [ ] `Route.lua` header, replace lines 3-6 with:

```lua
-- World quest routes, shared by the World quests map tab and the Gold world quests window: one route at a time that
-- tracks its stops one by one (ns.WQ_Track, so Waypoints shows them), nearest first from where you stand
-- (RouteOrder.lua). The rules for what happens next are ns.WQRoute_Step (RouteOrder.lua, pure): a stop handed in,
-- expired or done elsewhere drops out and the next is tracked; tracking something else yourself pauses the route
-- until you resume it (the Route button) or track its stop again. Owners pass a provider that reads the quests still
-- up for their route.
```

- [ ] Constants and state, replace line 8 and line 12 with:

```lua
local CHECK_DELAY = 1 -- seconds after a turn-in, a removed quest or a tracking change before the route looks (a
-- hand-in clears tracking a moment before QUEST_TURNED_IN; the map updates after it)
local CHECK_EVERY = 30 -- seconds between checks while a route runs: an expired world quest fires no event of its own
local ROUTE_EVENTS = { "QUEST_TURNED_IN", "QUEST_REMOVED", "SUPER_TRACKING_CHANGED" }
```

```lua
local route -- { ids, current, paused, owner, label, provider, earned }
local ticker, checkTimer
```

- [ ] Replace the Running section (from `local function Finish` to the end of the file) with:

```lua
local function Finish(text)
	route = nil
	events:UnwatchAll(OWNER)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if checkTimer then
		checkTimer:Cancel()
		checkTimer = nil
	end
	if text then
		ns.Print(text)
	end
	Changed()
end

-- What the game super-tracks, as WQRoute_Step reads it: a quest ID, 0 for nothing, -1 for something that isn't a
-- quest, nil when it can't tell (our own track waits for the end of combat; dead, the corpse comes first).
local function Tracked()
	if ns.SafeTrack_Waiting() then
		return nil
	end
	local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	if kind == nil then
		return 0
	elseif kind == Enum.SuperTrackingType.Quest then
		return C_SuperTrack.GetSuperTrackedQuestID() or 0
	elseif kind == Enum.SuperTrackingType.Corpse then
		return nil
	end
	return -1
end

-- Reads what's up and what's tracked, and does what WQRoute_Step says.
local function Check()
	if not route then
		return
	end
	local up = {}
	for _, q in ipairs(route.provider() or {}) do
		up[q.id] = q
	end
	local before = #route.ids
	local ids, action = ns.WQRoute_Step(route, up, Tracked())
	route.ids = ids
	if action == "done" then
		Finish(route.earned > 0 and ("route done: %s from it."):format(ns.Gold(route.earned)) or "route done.")
		return
	elseif action == "track" then
		local q = up[ids[1]]
		route.current = q.id
		ns.WQ_Track(q)
		local gold = (q.money or 0) > 0 and (", " .. ns.WQ_FormatGold(q.money)) or ""
		ns.Print(("next: %s (%s%s), %d left."):format(q.title, q.zone or "?", gold, #ids))
	elseif action == "pause" then
		route.paused = true
		ns.Print("route paused: you're tracking something else. Resume it with the Route button on the World quests "
			.. "map tab or the Gold world quests window.")
	elseif action == "resume" then
		route.paused = false
	end
	if action or #ids ~= before then
		Changed()
	end
end

local function CheckSoon()
	if route and not checkTimer then
		checkTimer = C_Timer.NewTimer(CHECK_DELAY, function()
			checkTimer = nil
			Check()
		end)
	end
end

-- quests: the quest records to route through (World quests' records: id, zoneID, zone, title, money). provider() ->
-- the records still up for this route. owner: who started it ("wq" | "wgq"); label: what it routes ("gold world
-- quests", a zone's name). Returns true when it started.
function ns.WQRoute_Start(quests, provider, owner, label)
	if #quests == 0 then
		ns.Print("nothing to route" .. (label and (" in " .. label) or "") .. ".")
		return false
	end
	local stops, start = Stops(quests)
	if #stops == 0 then
		ns.Print("the game gives no spots for these quests yet. Try again in a moment.")
		return false
	end
	if route then
		Finish()
	end
	route = { ids = ns.WQ_RouteOrder(stops, start), owner = owner, label = label, provider = provider, earned = 0,
		paused = false }
	for _, event in ipairs(ROUTE_EVENTS) do
		events:Watch(OWNER, event)
	end
	ticker = C_Timer.NewTicker(CHECK_EVERY, Check)
	local skipped = #quests - #stops
	ns.Print(("route through %s: %d stops%s. Hand one in and the next one is tracked."):format(label or "world quests",
		#route.ids, skipped > 0 and (" (%d without a spot left out)"):format(skipped) or ""))
	Check()
	return true
end

-- owner: only stop a route this owner started (a module turning off); nil stops any. silent: no chat line.
function ns.WQRoute_Stop(owner, silent)
	if route and (not owner or route.owner == owner) then
		Finish(not silent and "route stopped." or nil)
	end
end

function ns.WQRoute_Paused()
	return route ~= nil and route.paused
end

-- Tracks the next stop still up again.
function ns.WQRoute_Resume()
	if route and route.paused then
		route.paused, route.current = false, nil
		Check()
	end
end

-- The Route buttons (World quests map tab, Gold world quests window): their label, and a click. start() starts the
-- owner's route.
function ns.WQRoute_ButtonText()
	if not route then
		return "Route"
	end
	return route.paused and "Resume route" or "Stop route"
end

function ns.WQRoute_Click(start)
	if route and route.paused and not IsShiftKeyDown() then
		ns.WQRoute_Resume()
	elseif route then
		ns.WQRoute_Stop()
	else
		start()
	end
end

events:On(OWNER, "QUEST_TURNED_IN", function(_, questID, _, money)
	local index = ns.WQRoute_Index(questID)
	if index then
		table.remove(route.ids, index) -- even if the map still lists it for a moment
		route.earned = route.earned + (money or 0)
		CheckSoon()
	end
end)

events:On(OWNER, "QUEST_REMOVED", function(_, questID)
	if ns.WQRoute_Index(questID) then
		CheckSoon()
	end
end)

events:On(OWNER, "SUPER_TRACKING_CHANGED", CheckSoon)
```

  Check that `events:UnwatchAll` exists (Core/Events.lua line 73) and that no other code in the file still calls
  `TrackNext`. The old `Finish` unwatched only `QUEST_TURNED_IN`; `UnwatchAll(OWNER)` covers all three events.
  The `if route then Finish() end` line is new. It keeps a second Start from leaving the first route's ticker
  running.

- [ ] `Tab.lua`, `UpdateRouteButton` before:

```lua
	panel.route.label:SetText(ns.WQRoute_Active() and "Stop route" or "Route")
```

  after:

```lua
	panel.route.label:SetText(ns.WQRoute_ButtonText())
```

- [ ] `Tab.lua`, route button. Replace its `OnClick` and `OnEnter` scripts (lines 579-599) with:

```lua
	panel.route:SetScript("OnClick", function()
		ns.WQRoute_Click(StartRoute)
	end)
	panel.route:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if ns.WQRoute_Paused() then
			GameTooltip:SetText("Resume route", UI.Color("heading"))
			Line("You tracked something else, so the route stepped aside. Click to track its next stop again.",
				"text", true)
			Line("Shift-click: stop the route", "accent")
		elseif ns.WQRoute_Active() then
			GameTooltip:SetText("Stop the route", UI.Color("heading"))
		else
			GameTooltip:SetText("Route", UI.Color("heading"))
			Line("Tracks the quests listed here one by one, nearest first from where you stand. Hand one in and the "
				.. "next is tracked. Fold a section to leave its quests out.", "text", true)
		end
		if ns.WQRoute_Active() and ns.WQRoute_Owner() ~= "wq" then
			Line("Started in the Gold world quests window.", "textMuted")
		end
		GameTooltip:Show()
	end)
```

- [ ] `Window.lua` line 472 before:

```lua
	frame.routeButton.label:SetText(ns.WQRoute_Active() and "Stop route" or "Route")
```

  after:

```lua
	frame.routeButton.label:SetText(ns.WQRoute_ButtonText())
```

- [ ] `Window.lua` route button. Replace its `OnClick` and `OnEnter` scripts with:

```lua
	frame.routeButton:SetScript("OnClick", function()
		ns.WQRoute_Click(ns.Gold_StartRoute)
		Draw()
	end)
	frame.routeButton:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if ns.WQRoute_Paused() then
			GameTooltip:SetText("Resume route", UI.Color("heading"))
			Line("You tracked something else, so the route stepped aside. Click to track its next stop again.",
				"text", true)
			Line("Shift-click: stop the route", "accent")
		elseif ns.WQRoute_Active() then
			GameTooltip:SetText("Stop the route", UI.Color("heading"))
		else
			GameTooltip:SetText("Route", UI.Color("heading"))
			Line("Tracks the gold world quests one by one, nearest first from where you stand. Hand one in and the "
				.. "next is tracked.", "text", true)
		end
		if ns.WQRoute_Active() and ns.WQRoute_Owner() ~= "wgq" then
			Line("Started in the World quests map tab.", "textMuted")
		end
		GameTooltip:Show()
	end)
```

- [ ] `luac -l Tomte/Modules/WorldQuests/Route.lua | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` lists only WoW API and Lua
  globals (`C_SuperTrack`, `Enum`, `C_Timer`, `C_Map`, `C_TaskQuest`, `CreateVector2D`, `IsShiftKeyDown`, `ipairs`,
  `table`). Run the same check on `Tab.lua` and `Window.lua`.
- [ ] Run all tests (see Task 12).
- [ ] **In game** (Khaz Algar, level 80, a few world quests up). `/reload`, open the world map on a zone, World
  quests tab, click **Route**.
  1. Chat says "route through ...", then "next: ...". The first stop is tracked.
  2. Click another world quest on the map to track it. About a second later chat says "route paused ...", and the
     button reads **Resume route**. Hand in any quest. Tracking stays on what you picked.
  3. Click **Resume route**. The next stop still up is tracked with a "next: ..." line, and the button reads
     **Stop route**.
  4. Shift-click while paused: "route stopped.".
  5. Start a route, then pull a mob and fight. The route doesn't pause. Die if convenient (or skip): the route
     doesn't pause either, and tracks normally after you release and run back.
  6. Hand in a stop as usual: the next is tracked (no pause line).
  7. Open the Gold world quests window. Its Route button shows the same state.
  If something goes wrong, `/dump C_SuperTrack.GetHighestPrioritySuperTrackingType(), C_SuperTrack.GetSuperTrackedQuestID()`
  shows what the route saw.

### Task 3: World quests: Around rows track, slider in gold, tooltip color

**Files:** Modify `Modules/WorldQuests/WorldQuests.lua` (`items` of the `wqaround` home entry, lines 261-273; the
`worth.goldAmount` slider, lines 331-334).

**Interfaces:** Consumes `ns.WQ_Track`, `ns.Gold`. Produces nothing new.

- [ ] Around row before:

```lua
						rows[#rows + 1] = {
							icon = ns.WQ_RowIcon(q), text = main, right = ns.WQ_TimeText(q.seconds),
							color = s.key == "worth" and "success" or nil,
							onEnter = function(row)
								GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
								GameTooltip:SetText(q.title, 1, 1, 1)
								GameTooltip:AddLine(main, ns.UI.RGB("text"))
								GameTooltip:Show()
							end,
						}
```

  after:

```lua
						rows[#rows + 1] = {
							icon = ns.WQ_RowIcon(q), text = main, right = ns.WQ_TimeText(q.seconds),
							color = s.key == "worth" and "success" or nil,
							onClick = function()
								ns.WQ_Track(q)
							end,
							onEnter = function(row)
								GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
								GameTooltip:SetText(q.title, ns.UI.Color("heading"))
								GameTooltip:AddLine(main, ns.UI.RGB("text"))
								GameTooltip:AddLine("Click: track it", ns.UI.RGB("accent"))
								GameTooltip:Show()
							end,
						}
```

- [ ] Slider `format` before `return ("%dg"):format(v)`, after `return ns.Gold(v * 10000) -- the setting is in gold`.
- [ ] **In game**: `/reload`, open Tomte's Home in a zone with world quests. Click a row under "Around you: World
  quests": that quest is tracked (Blizzard's arrow and the Waypoints marker point at it) and the map does not open.
  The tooltip ends with "Click: track it". In settings, World quests, tick "Big gold rewards" and slide the amount
  to 1000: it reads "1,000g".

### Task 4: Gold world quests: slower polling while loading, tooltip colors

**Files:** Modify `Modules/GoldQuests/Window.lua` (line 15, line 577), `Modules/GoldQuests/Gold.lua` (lines 330-333).

**Interfaces:** none new.

- [ ] `Window.lua` line 15 before `local LOADING_TICK, CLOCK_TICK = 2, 30`, after:

```lua
-- Seconds between rescans while rewards load (World quests' Scan.lua sends at most one load request per quest every
-- 5 s, REQUEST_EVERY, and gives up after MAX_REQUESTS; QUEST_LOG_UPDATE shows loaded rewards at once), and between
-- redraws for the time left.
local LOADING_TICK, CLOCK_TICK = 5, 30
```

- [ ] `Window.lua` settings button: `GameTooltip:SetText("Settings", 1, 1, 1)` becomes
  `GameTooltip:SetText("Settings", UI.Color("heading"))`.
- [ ] `Gold.lua` minimap button tooltip before:

```lua
		tooltip = function(tooltip)
			tooltip:AddLine(currentGroup and ns.Gold_Summary(currentGroup) or "Not scanned yet", 1, 1, 1)
			tooltip:AddLine("Click to open or close the window", 1, 1, 1)
		end,
```

  after:

```lua
		tooltip = function(tooltip)
			tooltip:AddLine(currentGroup and ns.Gold_Summary(currentGroup) or "Not scanned yet", ns.UI.RGB("text"))
			tooltip:AddLine("Click to open or close the window", ns.UI.RGB("accent"))
		end,
```

- [ ] **In game**: `/reload` right after login (rewards still loading), `/tomte wgq`. The window says "Loading
  rewards…" briefly and fills in within about 5-10 s. Hover the Gold world quests minimap button (if shown) and the
  window's gear: the text is in the theme's colors.

### Task 5: Delves: errors to BugSack, a failed scan is cached

**Files:** Modify `Modules/Delves/Scan.lua` (constants near line 15, `ns.DelvesScan_List` lines 117-127),
`Modules/Delves/Read.lua` (header line 4, `ReadDirty` lines 202-208).

**Interfaces:** Consumes `ns.errorHandler` (Core/Core.lua). Produces nothing new.

- [ ] `Scan.lua`, after `local MAX_PROBED = ...` add:

```lua
local FAILED_RETRY = 60 -- seconds before a scan that errored is tried again (not on every redraw of the page)
```

- [ ] `Scan.lua` before:

```lua
	if stale and not InCombatLockdown() then
		local ok, list = pcall(Read, def)
		if ok then
			cache, cacheKey = list, expansion
			local reset = C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset() or 3600
			-- Nothing found may mean the zones' data isn't loaded yet: look again in a minute.
			cacheUntil = GetTime() + (#list > 0 and math.max(reset or 3600, 60) + 5 or 60)
		end
	end
```

  after:

```lua
	if stale and not InCombatLockdown() then
		-- Errors go to BugSack (ns.errorHandler); xpcall in Lua 5.1 takes no arguments, hence the closure.
		local ok, list = xpcall(function()
			return Read(def)
		end, ns.errorHandler)
		if ok then
			cache, cacheKey = list, expansion
			local reset = C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset() or 3600
			-- Nothing found may mean the zones' data isn't loaded yet: look again in a minute.
			cacheUntil = GetTime() + (#list > 0 and math.max(reset or 3600, 60) + 5 or 60)
		else
			-- Keep this expansion's last list (none for another expansion's) until the retry.
			if cacheKey ~= expansion then
				cache = {}
			end
			cacheKey, cacheUntil = expansion, GetTime() + FAILED_RETRY
		end
	end
```

- [ ] `Read.lua` header line 4: replace "inside pcall (a failure keeps the old value)" with "inside xpcall (a failure
  keeps the old value and goes to BugSack once per part per session)". Rewrap the comment to 120 columns.
- [ ] `Read.lua` `ReadDirty` before:

```lua
			local ok, err = pcall(READERS[part], def, expansion)
			if not ok and not reported[part] then
				reported[part] = true
				ns.Print(("delves: couldn't read %s (%s)"):format(part, tostring(err)))
			end
```

  after:

```lua
			xpcall(function()
				READERS[part](def, expansion)
			end, function(err)
				if not reported[part] then
					reported[part] = true
					ns.errorHandler(err)
				end
			end)
```

  Update the comment on `reported` (line 13) to "[part] = true once its read error went to BugSack".
- [ ] `luac -l` check on both files.
- [ ] **In game**: `/reload`, open the Delves page from Home. Entrances, keys, vault and companion show as before, and
  BugSack stays empty. (The error path can't be forced in game; the reviewer reads it.)

### Task 6: Gathering: minimap pins throttled

**Files:** Modify `Modules/Gather/MinimapPins.lua` (constants after line 18, state after line 32, `Update` lines 98-115,
`ns.GatherMini_Refresh` lines 202-224).

**Interfaces:** none new.

- [ ] Constants, after `local PICK_RANGE = ...` add:

```lua
local REDRAW = 1 / 30 -- seconds between redraws; a rotating minimap still redraws every frame while you turn
```

- [ ] State, after `local round, rotate = true, false` add:

```lua
local sinceDraw = 0
local drawn = {} -- what the last draw used (px, py, radius, half, facing, followPos): no redraw while all the same
```

- [ ] Rename the section ruler `-- Every frame ---...` to `-- Drawing ---...` (padded to 120 columns). In `Update`,
  before:

```lua
	if GetTime() >= pickAt then
		Pick(px, py, radius)
	end
	local half = Minimap:GetWidth() / 2
	local scale = half / radius -- pixels per yard
	local facing = rotate and Facing() or nil
	local followMap, followPos = ns.GatherFollow_Spot()
```

  after:

```lua
	local picked = GetTime() >= pickAt
	if picked then
		Pick(px, py, radius)
	end
	local half = Minimap:GetWidth() / 2
	local facing = rotate and Facing() or nil
	local followMap, followPos = ns.GatherFollow_Spot()
	if not picked and drawn.px == px and drawn.py == py and drawn.radius == radius and drawn.half == half
		and drawn.facing == facing and drawn.followPos == followPos then
		return -- nothing moved: the pins are where they were
	end
	drawn.px, drawn.py, drawn.radius, drawn.half, drawn.facing, drawn.followPos = px, py, radius, half, facing,
		followPos
	local scale = half / radius -- pixels per yard
```

  In the early return of `Update` (no position or radius), add `drawn.px = nil` before `return`, so the pins come
  back on the next good frame.
- [ ] Below `Update` add:

```lua
local function OnUpdate(_, elapsed)
	sinceDraw = sinceDraw + elapsed
	if sinceDraw < REDRAW and not (rotate and Facing() ~= drawn.facing) then
		return
	end
	sinceDraw = 0
	Update()
end
```

- [ ] In `ns.GatherMini_Refresh` add `wipe(drawn)` and `sinceDraw = REDRAW` next to `pickAt = 0`. Change
  `holder:SetScript("OnUpdate", Update)` to `holder:SetScript("OnUpdate", OnUpdate)`. Update the comment above
  `ns.GatherMini_Refresh` to say "runs the throttled update only while there's something to draw".
- [ ] `luac -l` check on the file.
- [ ] **In game**: `/reload` in a zone where you have gathered (rings on the minimap). Run past rings: they stay on
  their spots without trailing or jumping. Turn on "Rotate Minimap" (Interface options) and turn the camera with the
  mouse: rings turn smoothly. Zoom the minimap in and out: rings move at once. Start following a route from the
  Gathering map button: the legs and followed spot show. Stand still: `/etrace` isn't needed; nothing visible
  changes.

### Task 7: Gathering: tracker events on Start/Stop, point default comment, counts with commas

**Files:** Modify `Modules/Gather/Tracker.lua` (lines 21-26, line 108, lines 268 and 311, lines 346-351),
`Modules/Gather/Gather.lua` (line 431 default, `toggle` lines 491-505), `Modules/Gather/Page.lua` (lines 188, 223,
240, 296, 339, 356).

**Interfaces:** Produces `ns.GatherTracker_Start()`, `ns.GatherTracker_Stop()`.

- [ ] `Tracker.lua` before:

```lua
function ns.GatherTracker_Init(saved)
	db = saved
	for _, event in ipairs({ "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "PLAYER_ENTERING_WORLD" }) do
		events:Watch("tracker", event)
	end
end
```

  after (and add `local TRACKER_EVENTS = { "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "PLAYER_ENTERING_WORLD" }`
  to the file constants, after `TIER_ATLAS`):

```lua
function ns.GatherTracker_Init(saved)
	db = saved
end

function ns.GatherTracker_Start()
	for _, event in ipairs(TRACKER_EVENTS) do
		events:Watch("tracker", event)
	end
end

function ns.GatherTracker_Stop()
	events:UnwatchAll("tracker")
end
```

- [ ] `Gather.lua` `toggle`: in the `if active` branch add `ns.GatherTracker_Start()` before `ns.GatherMini_Start()`;
  in the `else` branch add `ns.GatherTracker_Stop()` before `ns.GatherMini_Stop()`.
- [ ] `Gather.lua` defaults line 431 after:

```lua
		tracker = { shown = true, collapsed = false }, -- also point = { point, relPoint, x, y } once moved in Edit Mode
		-- (Tracker.lua; nil: its DEFAULT_POINT). No point default: Core/Profile.lua skips tables with a point key.
```

- [ ] `Tracker.lua` line 108: `GameTooltip:SetText("End this run", 1, 1, 1)` becomes
  `GameTooltip:SetText("End this run", UI.Color("heading"))`.
- [ ] Counts, `%d` to `%s` with `ns.Thousands`:
  - `Tracker.lua` 268: `("%s nodes · %s"):format(ns.Thousands(n.nodes), perHour)`; `perHour`'s fallback
    `(n.nodesPerHour .. "/h")` becomes `(ns.Thousands(n.nodesPerHour) .. "/h")`.
  - `Tracker.lua` 311: `("%s %s · %s/h"):format(ns.Thousands(n.nodes), n.nodes == 1 and "node" or "nodes",
    ns.Thousands(n.nodesPerHour))`.
  - `Page.lua` 188: `("%s %s · %s · %s nodes (%s/h) · %s%s"):format(ns.Thousands(t.count), ..., ns.Thousands(t.nodes),
    ns.Thousands(t.nodesPerHour), ...)`.
  - `Page.lua` 223: `("%s %s over %s %s"):format(ns.Thousands(#totals), ..., ns.Thousands(#list), ...)`.
  - `Page.lua` 240: `("%s %s"):format(ns.Gather_RankMarkup(it.itemID, it.rank, 14), ns.Thousands(it.n))`.
  - `Page.lua` 296: `("%s · %s nodes (%s gathers) · %s/h · %s%s"):format(..., ns.Thousands(n.nodes),
    ns.Thousands(n.gathers), ns.Thousands(n.nodesPerHour), ...)`.
  - `Page.lua` 339: `("%s: %s %s%s"):format(MapName(mapID), ns.Thousands(z.nodes), ...)`.
  - `Page.lua` 356: `("%s: %s"):format(t.name, ns.Thousands(t.n))`.
  Leave the `date("%a %d %b ...")` calls alone (they aren't counts). Wrap any line that passes 120 columns.
- [ ] `luac -l` check on the three files.
- [ ] **In game**: `/reload`, `/tomte gather start`, gather a node. The tracker shows "1 node · .../h". Start a
  pet battle (or skip): the tracker hides, and comes back after. Turn Gathering off in settings: the tracker goes,
  and `/etrace` shows nothing of ours on `PET_BATTLE_*`. Turn it back on and start a run: the tracker comes back and
  still hides in a pet battle. On the Gathering page the totals read with commas once they pass 999 (items tab on a
  character with many runs).

### Task 8: Flight: Waypoints unit through an accessor, gold spent as text, tooltip colors

**Files:** Modify `Modules/Travel/Waypoint.lua` (after `Times`, near line 336), `Modules/Flight/Flight.lua` (line 113,
lines 450-453, line 484), `Modules/Flight/Tooltip.lua` (line 18).

**Interfaces:** Produces `ns.Way_Metric() -> bool` (Waypoints' "Use meters"; true before Waypoints' init, its default).
Consumes `ns.Price`.

- [ ] `Waypoint.lua`, after the `Times` function:

```lua
-- "Use meters", for other modules' distances (Flight's Around rows).
function ns.Way_Metric()
	if not db then
		return true -- the setting's default
	end
	return db.metric
end
```

- [ ] `Flight.lua` `DistanceText` before:

```lua
local function DistanceText(yards)
	local way = ns.modulesByKey.way
	return ns.Way_FormatDistance(yards, way and way.db and way.db.metric)
end
```

  after (Travel loads after Flight; both are looked up at call time):

```lua
local function DistanceText(yards)
	return ns.Way_FormatDistance(yards, ns.Way_Metric())
end
```

- [ ] `Flight.lua` line 113: `C_CurrencyInfo.GetCoinTextureString(st.copper)` becomes `ns.Price(st.copper)`.
- [ ] `Flight.lua` line 484: `GameTooltip:SetText(node.name, 1, 1, 1)` becomes
  `GameTooltip:SetText(node.name, ns.UI.Color("heading"))`.
- [ ] `Tooltip.lua` line 18: `GameTooltip:AddLine((isEstimate and "~" or "") .. ns.FormatTime(t), 1, 1, 1)` becomes
  `GameTooltip:AddLine((isEstimate and "~" or "") .. ns.FormatTime(t), ns.UI.RGB("text"))`.
- [ ] `luac -l` check on the three files.
- [ ] **In game**: `/reload`, `/tomte flight stats`: "Gold spent: 123g" (or "45s" on a fresh character) with no coin
  icons. On Home, "Around you: Flight masters" shows distances in meters (Waypoints' "Use meters" on, the default);
  untick it in Waypoints settings and reopen Home: yards. Open a flight map and hover a destination: the time line is
  in the theme's text color.

### Task 9: Minimap Buttons: old angle in a migration, tooltip colors

**Files:** Modify `Core/Migrations.lua` (append), `tests/test_migrations.lua` (append two tests before `H.done()`),
`Modules/Minimap/Minimap.lua` (`init` lines 230-247, `TomteTooltip` lines 187-199).

**Interfaces:** Produces migration 12 (plan A takes 10, plan B takes 11). If the numbering changed, this one takes the next
number: use that index in the comment, and that index minus one as `schema` in the tests.

- [ ] Failing tests, append to `tests/test_migrations.lua`:

```lua
test("Minimap Buttons: the old single angle moves to Tomte's button, shown", function()
	local db = { schema = 11, minimap = { angle = 200 } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.minimap.buttons.minimap.angle, 200)
	eq(db.minimap.buttons.minimap.shown, true)
	eq(db.minimap.angle, nil)
end)
test("Minimap Buttons: a button already placed keeps its spot", function()
	local db = { schema = 11, minimap = { angle = 200, buttons = { minimap = { shown = false, angle = 90 } } } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.minimap.buttons.minimap.angle, 90)
	eq(db.minimap.buttons.minimap.shown, false)
	eq(db.minimap.angle, nil)
end)
```

- [ ] Run `lua Tomte/tests/test_migrations.lua`: the first new test fails (`buttons` is nil).
- [ ] Append to `ns.MIGRATIONS` (after migration 9):

```lua
	-- 12: Minimap Buttons: the one button before 1.10 kept its spot in minimap.angle; it's Tomte's own button now
	-- (minimap.buttons.minimap), shown as it always was. Was done in Minimap.lua's init on every load.
	function(db)
		local saved = db.minimap
		if type(saved) ~= "table" or saved.angle == nil then
			return
		end
		if type(saved.buttons) ~= "table" then
			saved.buttons = {}
		end
		if saved.buttons.minimap == nil then
			saved.buttons.minimap = { shown = true, angle = saved.angle }
		end
		saved.angle = nil
	end,
```

- [ ] Run `lua Tomte/tests/test_migrations.lua`: all pass.
- [ ] `Minimap.lua` `init`: delete the comment `-- One button before 1.10: its spot was saved.angle.`, the line
  `local first = saved.buttons.minimap == nil`, and the block

```lua
		if first and saved.angle then
			saved.buttons.minimap.angle = saved.angle
		end
		saved.angle = nil
```

- [ ] `Minimap.lua` `TomteTooltip` after:

```lua
local function TomteTooltip(tooltip)
	local r, g, b = UI.RGB("text")
	tooltip:AddLine("Click to open Tomte", UI.RGB("accent"))
	if ns.Weekly_Active and ns.Weekly_Active() then
		tooltip:AddLine("Right-click for this week's open items", UI.RGB("accent"))
	end
	local nextUp = ns.NextUp_TooltipLines and ns.NextUp_TooltipLines()
	if nextUp and #nextUp > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine("Next up", UI.RGB("heading"))
		for _, line in ipairs(nextUp) do
			tooltip:AddLine(line, r, g, b, true)
		end
		tooltip:AddLine(" ")
	end
end
```

- [ ] **In game**: `/reload`. Tomte's minimap button is where it was. Hover it: the click hints are in the accent
  color and the Next up lines in the text color.

### Task 10: Teleports: empty text when sections are hidden, Around row tooltips, tooltip color

**Files:** Modify `Modules/Teleports/Data.lua` (after `ns.Tp_Sections`), `tests/test_teleports.lua` (before
`H.done()`), `Modules/Teleports/MapTab.lua` (line 37, line 418, line 473), `Modules/Teleports/Teleports.lua` (around
`items`, lines 158-169).

**Interfaces:** Produces `ns.Tp_EmptyText(entries, opts) -> text` (same `entries` and `opts` as `ns.Tp_Sections`).

- [ ] Failing tests, append to `tests/test_teleports.lua`:

```lua
test("empty text: nothing known", function()
	eq(ns.Tp_EmptyText({ entry({ key = "a", section = "class" }) }, {}), "No teleports on this character.")
end)

test("empty text: teleports there, their sections hidden", function()
	local list = { entry({ key = "a", section = "class", known = true }) }
	eq(ns.Tp_EmptyText(list, { hidden = { class = true } }), "Your teleports are all in sections hidden in settings.")
end)
```

- [ ] Run `lua Tomte/tests/test_teleports.lua`: fails (`Tp_EmptyText` missing).
- [ ] `Data.lua`, after `ns.Tp_Sections`:

```lua
-- The Teleports tab's text when it shows no section: the character has teleports but every section holding them is
-- hidden in settings, or it has none. entries, opts: as Tp_Sections.
function ns.Tp_EmptyText(entries, opts)
	if #ns.Tp_Sections(entries, { showUnearned = opts.showUnearned }) > 0 then
		return "Your teleports are all in sections hidden in settings."
	end
	return "No teleports on this character."
end
```

- [ ] Run `lua Tomte/tests/test_teleports.lua`: all pass.
- [ ] `MapTab.lua` line 418 before `panel.empty:SetShown(#sections == 0)`, after:

```lua
	if #sections == 0 then
		panel.empty:SetText(ns.Tp_EmptyText(entries, { showUnearned = db.showUnearned }))
	end
	panel.empty:SetShown(#sections == 0)
```

  Line 473: remove `panel.empty:SetText("No teleports on this character.")` (Build sets it now).
- [ ] `MapTab.lua` line 37: `GameTooltip:AddLine(e.desc, 1, 1, 1, true)` becomes `UI.TipLine(e.desc, "text", true)`.
- [ ] `Teleports.lua` around row before:

```lua
						rows[#rows + 1] = { icon = e.icon, text = e.name, right = "ready" }
```

  after:

```lua
						rows[#rows + 1] = { icon = e.icon, text = e.name, right = "ready",
							-- Casting needs a secure button, which Home doesn't have: the click opens the tab.
							onEnter = function(row)
								GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
								GameTooltip:SetText(e.name, ns.UI.Color("heading"))
								local r, g, b = ns.UI.RGB("accent")
								GameTooltip:AddLine("Click to open the Teleports tab on the world map, then click it there "
									.. "to use it.", r, g, b, true)
								GameTooltip:Show()
							end,
						}
```
- [ ] `luac -l` check on `MapTab.lua` and `Teleports.lua`.
- [ ] **In game**: `/reload`. In Teleports settings, turn off every section that lists something (Hearthstone,
  Dungeons, Class, Items and toys, plus Favorites and To this map). Open the map, Teleports tab: "Your teleports are
  all in sections hidden in settings." Turn them back on. On Home, hover a teleport under "Around you": the tooltip
  names it and says how to use it. Click it: the map opens on the Teleports tab.

### Task 11: Smart Mount: tooltip colors

**Files:** Modify `Modules/Mount/Mount.lua` (line 601), `Modules/Mount/Journal.lua` (line 88).

**Interfaces:** none.

- [ ] `Mount.lua` 601: `GameTooltip:SetText(name or ("#" .. mountID), 1, 1, 1)` becomes
  `GameTooltip:SetText(name or ("#" .. mountID), ns.UI.Color("heading"))`.
- [ ] `Journal.lua` 88 after:

```lua
	local tr, tg, tb = ns.UI.Color("text")
	GameTooltip:AddLine("Click to add this mount to the favorites for the zone or continent you're in. Smart Mount "
		.. "picks from those first there.", tr, tg, tb, true)
```

  And `GameTooltip:SetText("Smart Mount zone favorite")` (line 87) becomes
  `GameTooltip:SetText("Smart Mount zone favorite", ns.UI.Color("heading"))`.
- [ ] **In game**: `/reload`, open the Mount Journal, hover Smart Mount's zone favorite button: heading and text in the
  theme's colors. On Home, hover a mount under "Around you": its name is in the heading color.

### Task 12: Final checks, CHANGELOG, commit

**Files:** `CHANGELOG.md` (Unreleased), `README.md` only if a row or command changed (none expected: no new
commands or settings).

- [ ] From the AddOns folder, all tests:
  `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`. No output.
- [ ] `lua Tomte/tests/test_theme.lua`: passes (no new numeric colors; nothing read at file load).
- [ ] Global check on every changed Lua file:
  `for f in Modules/WorldQuests/RouteOrder.lua Modules/WorldQuests/Route.lua Modules/WorldQuests/Tab.lua Modules/WorldQuests/WorldQuests.lua Modules/GoldQuests/Window.lua Modules/GoldQuests/Gold.lua Modules/Delves/Scan.lua Modules/Delves/Read.lua Modules/Gather/MinimapPins.lua Modules/Gather/Tracker.lua Modules/Gather/Gather.lua Modules/Gather/Page.lua Modules/Travel/Waypoint.lua Modules/Flight/Flight.lua Modules/Flight/Tooltip.lua Modules/Minimap/Minimap.lua Core/Migrations.lua Modules/Teleports/Data.lua Modules/Teleports/MapTab.lua Modules/Teleports/Teleports.lua Modules/Mount/Mount.lua Modules/Mount/Journal.lua; do echo "== $f"; luac -l "Tomte/$f" | grep -E 'GETGLOBAL|GETTABUP.*_ENV' | grep -oE '"[^"]+"|_ENV "[^"]+"' | sort -u; done`.
  Every name listed is a WoW API or a Lua global.
- [ ] No TOC change, so `tools/bugfiles.lua` isn't needed. `tests/test_wq_route.lua` lives in `tests/`, so
  `.gitattributes` needs nothing.
- [ ] In-game checklist (the user, after `/reload`): Tasks 2, 3, 4, 5, 6, 7, 8, 9, 10 and 11's "In game" steps. The
  route pause/resume (Task 2) and the minimap pins (Task 6) matter most.
- [ ] Once the user confirms, add under **Unreleased** in `CHANGELOG.md`:

```markdown
- World quests: a route skips a stop that expired or was done some other way, and steps aside when you track something else (no more taking tracking back on your next hand-in). The Route button then reads "Resume route"; shift-click stops it.
- World quests: clicking a world quest under "Around you" on Home tracks it; the "Big gold is at least" setting reads in gold with commas.
- Teleports: the tab says when all your teleports are in sections hidden in settings, and Home's teleport rows tell you how to use them.
- Gathering: the node rings on the minimap cost much less while you stand still or walk; counts on the Gathering page and tracker use commas.
- Delves: if reading the delve entrances fails, the error shows in BugSack and the page no longer retries on every redraw.
- Flight: "/tomte flight stats" shows gold spent as plain gold text.
```

- [ ] Commit per confirmed step, one module per commit, messages like:
  `World quests: routes skip expired stops and step aside when you track something else`,
  `Gathering: minimap rings redraw only when something moved`,
  `Delves: read errors go to BugSack, a failed scan isn't retried every redraw`,
  `Minimap Buttons: old button spot moved into a migration`,
  `Teleports: say when every section with teleports is hidden`,
  `Flight: Waypoints unit through Way_Metric, gold spent as text`,
  `Smart Mount: tooltip colors from the theme`. End each with the attribution lines from the session's
  system-reminder.
