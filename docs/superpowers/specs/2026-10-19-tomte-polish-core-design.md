# Polish A: core services

2026-10-19. First of six polish passes from the audit (A core, B social/defaults/docs, C class helpers, D economy,
E travel/world, F collections). A goes first: it adds the shared Core and Panel pieces the other five call, and fixes
the Core/Panel findings. Decisions marked **(user)** came from the user; the rest follow CLAUDE.md.

## What the player notices

- **One combat line.** Everything Tomte refuses in combat says it the same way: "Tomte: can't open the map in
  combat." **(user)** It refuses; nothing pretends to queue ("the journal opens after combat" didn't open anything).
  Actions that really do wait for the end of combat (map pins through `ns.SafeTrack`: "after combat: tracking ...")
  keep their wording, because they do happen.
- **Off modules say so.** `/tomte <module> <command>`, a key binding or a module's button while that module is off
  prints "Gathering is off. Turn it on in /tomte." (or, for a module that can't run here, its reason: "Hunter Pets:
  Only for hunters."). Today some commands do that with a different wording each, some silently do nothing, some run
  half-working. A command that is meant to work while off (Fishing's `status`, which reports the off state itself)
  still runs.
- **Map tabs open themselves.** `/tomte wq open`, `/tomte tp open`, `/tomte collect open`, the zone toasts and Home
  open the world map with its quest log side panel and select the tab, instead of printing "open the map's quest
  log panel, then click the tab". A maximized map becomes the windowed map with the panel, as the L key does.
- **Esc closes one thing.** With a Tomte dialog (copy text, import preview, setup, pet guides, a yes/no question)
  over the Tomte window, Esc closes the dialog only; the next Esc closes the window. Same for the whisper inbox and
  the weekly popup: last opened, first closed. Works in combat too.
- **Alt+Z keeps the window.** Hiding the UI (Alt+Z, the AFK screen, a flight cinematic) and bringing it back shows
  the Tomte window again where it was; today it is gone.
- **Around you shows** lists every "Around you" block, Delves included (it was missing). Delves' own "Delves in
  Around you" switch moves there (one switch per block, all in one place). An unticked Delves switch stays unticked.
- **Settings search** also finds a module by the words in its settings: searching "node spots" finds Gathering,
  "guild funds" finds Vendor.
- **Settings rows appear and hide right away.** A row that only applies in some cases (the theme's "Reload now",
  "Undo import", rows that depend on another choice) shows or hides as soon as the choice changes, not only after
  leaving and reopening the page.
- **Fewer error floods.** A Lua error in one module's event handler no longer stops other Tomte code listening to the
  same event; a journal scan whose callback errors reports once and stops instead of erroring every frame.
- Readiness check wording: "Tomte: can't run the pet check in combat." / "... while you're dead."

## Decisions

- **Combat**: `ns.Print_Combat(action)` prints `can't <action> in combat.` through `ns.Print` (so "Tomte: " in the
  accent). `action` is lower case, no period. Every refusal site uses it (list in the plan, task 3).
- **Off modules**: the gate lives in `Core/Core.lua` `RunModuleCommand`: a command (or `fallbackCommand`) runs when
  its module is active or the command has `whileOff = true`. Otherwise it prints `ns.Module_OffText`. The rule and the
  text are pure (`Core/Modules.lua`, tested). `ns.Module_RequireOn(moduleOrKey)` prints the same line and returns
  false: it replaces every module's own `RequireActive` (Achievements, Collect, Flight, Gold world quests, Holidays,
  Waypoints, World quests) and the inline "X is off." checks (AFK, Chat Copy, Trade Filter, Gear Check, Pet Health,
  Hunter, Moments, Smart Mount, Session recap, Friend sharing, Showcase, Group Alerts, Friends Online, Mentions,
  Whispers). Key bindings go through `ns.Binding_Add(name, moduleKey, fn)`, which gates the same way.
  Only Fishing `status` gets `whileOff` (it prints the off state itself). Chat Tabs `restore` stays gated: turning
  the module off already restores the chat.
- **Map side panel**: `ns.MapTabs_Open(key, mapID)` in `Panel/MapTabs.lua`. It calls Blizzard's global
  `OpenQuestLog(mapID)` (Blizzard_WorldMap.lua, live 12.1.5: `WorldMapFrame:HandleUserActionOpenQuestLog`, the L
  key's path: `SetDisplayState(OPEN_MINIMIZED_WITH_LOG)`), then `ns.MapTabs_Select(key)`. It does not set the
  `questLogOpen` CVar (that is the user's own preference, only Blizzard's side panel toggle writes it) and never
  calls `QuestMapFrame:SetDisplayMode` (taints the quest log, see MapTabs.lua's header). Our code already opens the
  map the same way (`ToggleWorldMap` goes through the same `SetDisplayState`), so this adds no new taint path. When a
  game rule hides the quest log panel (`QuestLogPanelDisabled`), it says the panel can't open here. Not in combat.
- **Esc**: one dummy frame, `TomteEscape`, in `UISpecialFrames`; `UI.CloseOnEscape(frame)` (Panel/Controls.lua)
  keeps a list of open Tomte frames in show order. Esc (Blizzard's `CloseSpecialWindows`) hides the dummy; its
  OnHide closes only the top frame and shows the dummy again a frame later while more are open. The dummy is a child
  of UIParent and ignores an OnHide while it is still `IsShown()` (UIParent hid, not Esc): that is also the fix for
  Alt+Z. `UI.Dialog` uses it instead of adding its name to `UISpecialFrames`; the Tomte window, the whisper inbox and
  the weekly popup drop their own dummies (`TomtePanelEscape`, `TomteInboxEscape`, `TomteWeeklyEscape`). The yes/no
  dialog keeps its own Esc/Enter keys (out of combat) and joins the list for combat, where it can't take the
  keyboard. `RegisterGameMenuEscHandler` (new in 12.1) was considered and not used: registering from addon code
  taints the Esc chain (Plumber's notes say so).
- **Around you**: the switches are built from every module's `kind = "around"` home entries (on or off), in Home's
  order, when the Tomte window module's `init` runs (all files are loaded by then). Delves' `around` setting goes away
  with migration 10.
- **Search** matches string `label`, `text` (button text) and `tooltip` of every options row, headers included.
  Label functions are not called (they can read the game).
- **shown()**: after every option change and button click the options page compares which `shown()` rows show (a
  pure "visibility" string) with what it built, and rebuilds when it differs (after the switch animation, as parent
  options already do). Opening a page already rebuilds it.
- **Errors**: the event bus calls each handler through `xpcall(h.fn, ns.errorHandler, bus, ...)`; the journal scan
  advances its index before each callback, calls callbacks through `xpcall` and stops the scan when one errors.
  The test harness gives Lua 5.1 WoW's `xpcall(f, handler, ...)` (WoW passes the extra arguments; CI's 5.1 doesn't).
- **Content kind** ("dungeon" / "raid" / "delve" on entering an instance) moves out of Hunter Pets into a pure Core
  file, `Core/CheckData.lua` as `ns.Check_ContentKind`: Core's readiness checks and Durability used a module's
  function. `ns.Hunter_ContentKind` is removed.
- **Model preview**: the bare `pcall` around our own code goes; only `actor:SetModelByCreatureDisplayID` and
  `actor:TryOn` (game calls that can error on an unknown ID or link) stay in `pcall`, and a failure clears the preview.
- **Collapse button**: keeps polling (its comment says why: the widget's rows take the mouse, so OnEnter/OnLeave on
  the widget can't tell), but a few times a second instead of every frame.
- **Scroll thumb**: hiding it mid-drag ends the drag (no stale OnUpdate when it shows again).

## Data and migrations

- Migration 10 (appended to `ns.MIGRATIONS`): `delves.around == false` becomes `window.around.delvesaround = false`;
  `delves.around` is removed either way. Copes with missing `delves`, `window` and `window.around`. Other polish
  plans append 11 and later.
- `window.around` gets a `true` default for every around block at init (missing keys only), so the switches never
  show off for a block the user never touched, and Reset puts them back on.
- An old settings string that still carries `delves.around` imports without it (no options row reads it any more).

## Code touched

- Core: `Core/Core.lua` (Print_Combat, Module_RequireOn, Binding_Add, RunModuleCommand gate), `Core/Modules.lua`
  (Module_OffText, Module_CommandAllowed, Home_AroundChoices), `Core/Events.lua`, `Core/Journal.lua`,
  `Core/Check.lua`, new `Core/CheckData.lua`, `Core/Migrations.lua`, `Tomte.toc`, `Core/BugFiles.lua` (generated).
- Panel: `Panel/MapTabs.lua`, `Panel/Controls.lua` (CloseOnEscape), `Panel/Widgets.lua` (UI.Dialog, CollapseButton,
  ScrollThumb), `Panel/Confirm.lua`, `Panel/Setup.lua`, `Panel/Panel.lua`, `Panel/Window.lua`, `Panel/Layout.lua`,
  `Panel/Options.lua`, `Panel/ModelPreview.lua`, `Panel/Entries.lua`, `Panel/HomeHero.lua`, `Panel/Share.lua`.
- Modules (call sites only): Achievements, AFK, Alts/Send, Chat/Copy, Chat/Filter, Collect (Collect, Tab), Combat/PetHealth,
  Delves, Fishing, Flight, Gather, Gear (Gear, Reveal, Sheet), GoldQuests (Gold, Window), Holidays (Holidays,
  Calendar), Hunter (Data, Checks, Hunter), Moments, Mount, Recap, Share, Showcase, Social (Alerts, Friends,
  Mentions, Whispers, Inbox), Teleports/MapTab, Travel/Waypoint, Upkeep/Durability, Weekly/Popup, WorldQuests
  (WorldQuests, Tab).
- Tests: `tests/harness.lua`, `test_eventbus`, new `test_journal`, `test_modules`, `test_home`, `test_migrations`,
  `test_panel_layout`, new `test_check`, `test_hunter`.

## Checked, not changed

- Collapse button "replace polling with OnEnter/OnLeave": not done as asked; the widget's rows take the mouse, so the
  widget's own OnEnter/OnLeave fire while the pointer is still over it (the code's comment, measured). Throttled
  instead.
- "Options re-evaluated on page show": already true; `Panel/ModulePage.lua` rebuilds the options each time the page
  refreshes. Only changes made on the page itself were missed.
- "~29 combat sites": 22 real refusal lines found (task 3 lists them). The rest are not refusals: queued pin changes
  (`SafeTrack`: Collect/Catalog, Delves/Scan, Flight, Travel/Waypoint, Weekly), Showcase and AFK (one line for
  several reasons), Pets' "can't swap pets now: not in combat" (a reason inside a longer sentence), Teleports' map
  tab note and tooltip (state shown in the panel), Moments' and Fishing's descriptions.
- `ns.Hunter_ContentKind` was not broken (Hunter's Data.lua always loads); the move is about layering.
- Rogue's `offMessage` in `ns.Check_Report`: left as is; with the central gate it is only reachable from code, and
  the readiness checks are plan C's.
