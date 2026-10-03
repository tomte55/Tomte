# Tomte: personal QoL addon with modules (FlightTimer becomes the first module)

The user approved structure sections 1 and 2 in conversation, then asked Claude to decide the rest.

## Goal

FlightTimer turns into **Tomte**, one personal QoL addon that hosts small features as modules. Each
module can be switched on and off live and cleans up after itself. FlightTimer is the first module, and
its data, settings and behavior carry over unchanged. The cinematic code is split into a shared engine
with scenes, so an AFK cinematic can be added later as a second scene.

**Success means:**

- After the hand-over, Tomte shows every flight time and stat FlightTimer had.
- Flights look and behave exactly as before.
- Turning the flight module off mid-flight brings the UI, camera, pitch limit and music back at once.
- Nothing in Tomte does per-frame work while idle.

**Out of scope:** the flight-master overview (zone coverage of recorded/estimated times; a follow-up
round that will use the `page` hook), the AFK scene itself, localization, release notes, "new" tags, sort filters, and
shared libraries.

## Decisions

| Topic | Decision |
|---|---|
| Packaging | One addon, modules as folders, all loaded from `Tomte.toc`. No load-on-demand children (they save almost no memory at this size). A module can become one later without changing the module interface. |
| Settings | Account-wide `TomteDB`. |
| Module options | A right-hand pane inside the panel, not a floating dialog. |
| Panel look | Custom dark/gold, hand-drawn widgets. Dropdown lists open with `MenuUtil.CreateContextMenu`. |
| Slash commands | Everything under `/tomte`. Modules add subcommands (`/tomte flight stats`). `/ft` goes away. |
| FlightTimer loaded too | Tomte copies its data and steps aside (details below). |
| Cinematic | A shared engine in `Cinematic/`. Flight is one scene. |

## File layout

```
Tomte/
  Tomte.toc
  Core/Core.lua          event frame, ADDON_LOADED, defaults merge, /tomte, compartment, ownFrames
  Core/Modules.lua       module registry and enable logic (no WoW API calls: unit-tested)
  Core/Migration.lua     FlightTimer hand-over; CopyFlightData is pure (unit-tested)
  Cinematic/Engine.lua   letterbox, vignette, UI hide/fade, world-frame sweep, camera, music, pause, idle resume, hint
  Cinematic/Showcase.lua character model + gear (moved from FlightTimer; scenes opt in)
  Panel/Widgets.lua      dark/gold checkbox, slider, button, dropdown button, header, section frame
  Panel/Panel.lua        main frame, search, categories, module list, options pane, Blizzard embed, Esc
  Modules/Flight/Data.lua      unchanged (pure logic)
  Modules/Flight/Flight.lua    today's Core.lua: tracking, tick, events, module registration, commands, options schema
  Modules/Flight/Bar.lua       unchanged apart from lazy creation and namespacing
  Modules/Flight/Tooltip.lua   unchanged apart from the active check
  Modules/Flight/Scene.lua     flight scene: today's Bands.lua contents minus the pause hint
  Modules/Flight/ZoneText.lua  unchanged; driven by the flight scene
  tests/test_flight_data.lua   moved from FlightTimer/tests/test_data.lua
  tests/test_modules.lua       new: registry + migration copy
```

TOC (`## Interface: 120100`):

```
## Title: Tomte
## Notes: Personal quality-of-life modules.
## Author: tomte55
## Version: 1.0.0
## IconTexture: Interface\Icons\INV_Misc_PocketWatch_01
## SavedVariables: TomteDB
## OptionalDeps: FlightTimer
## AddonCompartmentFunc: Tomte_OnAddonCompartmentClick
```

Load order: Core, Modules, Migration, Cinematic, Panel, then each module's files.

`.gitignore` gets `!/Tomte/`. `!/FlightTimer/` stays until the user deletes the folder; removing that
whitelist line is a separate final commit.

Namespace: everything sits in the addon's `ns` table, as today. Core-level functions are `ns.X`, the
engine is `ns.Cinematic`, the panel is `ns.Panel`, and flight internals stay `local` to their files or go
into a `ns.Flight` table. No globals except `TomteDB` and `Tomte_OnAddonCompartmentClick`.

## Performance rules

1. **No idle `OnUpdate`.**
   - The flight module's tick runs on a separate ticker frame. It's shown only while a route is pending
     or a flight is active, and hidden otherwise. Today FlightTimer's event frame `OnUpdate` runs every
     frame forever.
   - The letterbox only ticks while it's shown (it hides itself once the slide-out is done), as today.
   - The idle-resume watcher only ticks while a cinematic is paused, as today.
   - The bar only ticks while it's shown, as today.
2. **Lazy frames.** The letterbox, the scene contents, the showcase (the `PlayerModel` is the most
   expensive object), the bar and the panel are each built the first time they're needed.
   - At load, only the event frame, the ticker frame and the small Blizzard-settings holder frame
     exist.
3. **Events follow active state.** A module registers its events when it activates and unregisters them
   when it deactivates.
   - Hooks that can't be removed (`hooksecurefunc` on `TakeTaxiNode`, `TaxiNodeOnButtonEnter`,
     `FlightMap_FlightPointPinMixin.OnMouseEnter`) are installed once, on first activation, and start
     with `if not module.active then return end`.
4. **No per-frame allocation.** Same as today's code: tables are reused, and stat pages are built once
   per flight.

## Module system

### Registration (`Core/Modules.lua`)

```lua
ns.RegisterModule({
  key = "flight",                  -- TomteDB[key] and /tomte flight ...
  name = "Flight Timer",
  category = "Travel",
  description = "Times flight paths account-wide and shows a countdown, with an optional cinematic flight mode.",
  enabledByDefault = true,
  defaults = { ... },              -- merged into TomteDB[key]
  toggle = function(active) end,   -- start / fully undo the module's effects
  blocked = function() return reasonOrNil end, -- optional
  options = { ... },               -- schema, see "Options schema"
  panelClosed = function() end,    -- optional: the panel was hidden
  init = function(db) end,         -- optional: once after the defaults merge, before the first toggle
  cinematicState = function() return state end, -- optional: live engine state (music cleanup)
  page = { Create = function(frame) end, Refresh = function(frame) end }, -- optional, instead of options
  commands = {                     -- optional; listed by /tomte help in this order
    { "stats", "show flight stats", fn },
    ...
  },
})
```

Registration only stores the table; nothing is built and no events are registered. Modules appear in the
panel in registration order within their category, and categories appear in order of first use.

### Activation

- `module.db = TomteDB[key]`, after the `defaults` merge.
- `ns.ModuleWanted(module)` = `TomteDB.enabled[key]` (falling back to `enabledByDefault` when nil)
  **and** `blocked()` returns nil.
- `ns.RefreshModule(module)` compares wanted with `module.active`. On a change it sets `module.active`
  and calls `toggle(active)` inside `xpcall(..., geterrorhandler())`, so BugSack shows the error and the
  other modules still load. If `toggle(true)` errors, `module.active` stays true so that turning it off
  still runs the cleanup.
- On `ADDON_LOADED` (Tomte), the core merges defaults for every module, runs the migration, then refreshes
  every module.
- `ns.SetModuleEnabled(key, enabled)` (used by the panel checkbox) writes `TomteDB.enabled[key]` and
  refreshes the module.
- `toggle(true)` can run before or after login. A module that needs world state checks `IsLoggedIn()` and
  otherwise waits for `PLAYER_ENTERING_WORLD`.

`Modules.lua` doesn't call WoW APIs directly. The error handler is looked up through `ns.errorHandler`,
which defaults to `geterrorhandler()` in-game and can be replaced in tests.

### Defaults merge

`Modules.lua` defines `ns.MergeDefaults(defaults, dst)`, the same recursive merge as `Data.lua`'s local
one. The core uses it for every module's `defaults`. The flight `Data.lua` keeps its own local merge and
`ns.InitDB` (used by its tests and by the stats reset), so it stays self-contained. The twelve duplicated
lines are on purpose: the core must not depend on a module's file.

`Data.lua` changes in two places:

- The line `ns.ownFrames = {}` moves to `Core.lua`, which loads first, so the bar and letterbox register
  into one table that is never replaced.
- **Pace window** (added 2026-10-03, after the user unlocked +25% flight speed in Khaz Algar):
  `ns.RecordPace` weights only the last `ns.PACE_WINDOW = 10` flights per map. Older totals fade by 9/10
  per new flight, and pace data saved without a `flights` count starts fading immediately. Route and hop
  times already update to the latest flight, so faster taxis show up there after one flight per route.

`ns.defaults` stays the flight module's defaults table (it's what `ns.InitDB` reads). The flight module
registers with `defaults = ns.defaults`. Future modules keep their defaults in their own locals and don't
use `ns.defaults`.

## TomteDB layout

```lua
TomteDB = {
  enabled = { flight = true },          -- only keys the user has toggled; nil = enabledByDefault
  panel = { category = "Travel" },      -- last selected category
  cinematic = { musicVolumeBackup = nil }, -- engine-owned, see "Music"
  flightImported = true,                -- set once FlightTimer data was copied (record only)
  flight = { -- exactly FlightTimerDB's shape:
    routes, hops, paces, calibration, stats, frame,
    alert, cinematic, orbit, showcase, music, musicTrack, cinematicMin, resumeDelay,
    current,                            -- in-progress flight, as today
  },
}
```

`musicVolumeBackup` moves from the flight table to `TomteDB.cinematic`, because the engine owns the music.

## FlightTimer hand-over (`Core/Migration.lua`)

SavedVariables are per-addon files, so Tomte can only read `FlightTimerDB` while FlightTimer itself is
loaded. `OptionalDeps: FlightTimer` makes sure FlightTimer loads first.

On Tomte's `ADDON_LOADED`, before modules are refreshed:

- If `C_AddOns.IsAddOnLoaded("FlightTimer")` and `FlightTimerDB` is a table:
  - `TomteDB.flight = ns.CopyFlightData(FlightTimerDB)`, a deep copy without `current` and
    `musicVolumeBackup` (FlightTimer's runtime state for its own flight). The flight defaults are then
    merged again.
  - Set `TomteDB.flightImported = true`.
  - The flight module's `blocked()` returns `"The FlightTimer addon is still enabled."` while
    FlightTimer is loaded, so FlightTimer stays in charge for the whole session and nothing drives the
    camera twice.
  - Register `PLAYER_LOGOUT` and copy again there. It fires on logout and `/reload` just before
    SavedVariables are written (warcraft.wiki.gg/wiki/PLAYER_LOGOUT), so flights from this session are
    kept.
  - Print once:
    `Tomte: flight data copied from FlightTimer. Disable FlightTimer and /reload to switch over.`
- If FlightTimer isn't loaded, do nothing. Tomte owns its data.

**Order matters, and the test steps say so:** install Tomte, log in once with **both** enabled, then
disable FlightTimer and `/reload`. If FlightTimer is disabled before that first login, its data can't be
reached.

## Cinematic engine (`Cinematic/Engine.lua`)

This is today's `Cinematic.lua`, made scene-agnostic. It keeps everything the engine already does:

- Letterbox bands with soft edges, vignette and the slide timing.
- UI fade out/in; only a UI we hid ourselves comes back.
- The world-frame sweep that hides other addons' frames, skipping `ns.ownFrames`.
- Camera: zoom out to 20 yards and undo exactly that zoom; the pitch-limit ease and nudge; the orbit.
- Music, plus restoring the music volume.
- Mouse/wheel/keyboard capture: a click or Esc pauses.
- The idle-resume watcher and the `PlayerBusy` checks.
- Combat handling: pause on `PLAYER_REGEN_DISABLED`, and show a deferred UI on `PLAYER_REGEN_ENABLED`.

The **pause hint** ("Click or Esc to pause") moves from Bands into the engine, because pausing is an
engine feature. `ns.MUSIC_TRACKS` moves here as well.

### API

```lua
ns.Cinematic.Enter(scene, state, opts)
  -- opts = { orbit = bool, showcase = bool, music = trackIndex|nil, resumeDelay = seconds,
  --          skipCamera = bool }  -- skipCamera: no zoom/orbit/pitch (resumed during the arrival shot)
ns.Cinematic.Update(state, orbitFactor) -- per tick while active; orbitFactor < 1 eases orbit out and restores zoom
ns.Cinematic.Exit(state)       -- idempotent; also cleans up a stale state after /reload (not active)
ns.Cinematic.Release(state)    -- Exit + stop the idle watcher if it watches this state (state is done)
ns.Cinematic.Pause(state)      -- exit + set state.resumeAt = now + state.resumeDelay + start the idle watcher
ns.Cinematic.Watch(state)      -- idempotent; keeps topping up state.resumeAt while the player is busy
ns.Cinematic.IsActive()
ns.Cinematic.IsOwner(state)    -- true if the active cinematic belongs to this state
ns.Cinematic.RestoreMusicVolume()
```

- `state` is the persisted table that records what the engine changed: `zoomedOut`, `pitchLimited`,
  `musicHandle`, `musicStarted`, `cinematic`, `orbitFactor` and `resumeAt`. For flights it is
  `db.current`, as today, so a `/reload` mid-flight can still undo everything.
- `Enter` copies `opts.resumeDelay` into `state.resumeDelay`, so `Pause` and the watcher don't read
  flight settings. (`Watch` called on a state from before a `/reload` can lack it; it then falls back to
  20s.)
- Today the watcher stops itself when `watched ~= ns.db.current`. The engine can't see flight data, so
  the owner calls `Release(state)` when the state is finished (landing, deactivation). The watcher stops
  when `state.resumeAt` is nil or `Release` was called.
- **One scene at a time.** `Enter` while another scene is active does nothing; the caller tries again on
  its next tick.

### Engine events

The engine has its own small event frame. It registers `PLAYER_REGEN_DISABLED`/`ENABLED` only while a
cinematic is active or a UI show is waiting for combat to end, and unregisters them otherwise. Combat
during a cinematic calls `Pause(current state)`, which is today's behavior moved out of the flight Core.

`PLAYER_ENTERING_WORLD`: the core calls `ns.Cinematic.RestoreMusicVolume()` when no module has resumed a
cinematic. Concretely, the core calls it after modules have handled `PLAYER_ENTERING_WORLD`, if
`not ns.Cinematic.IsActive()`.

### Scene contract

```lua
scene = {
  Create = function(letterbox) end,      -- once, lazily, on the first Enter of this scene
  Begin = function(state) end,           -- on every Enter: fill in text and layout
  Update = function(contentAlpha, dt) end, -- every frame while the letterbox is visible
  End = function() end,                  -- optional, on Exit
}
```

The engine builds the letterbox frame on the first `Enter`, then `scene.Create` on that scene's first
`Enter`. Each scene draws in its own child frame of the letterbox, and the engine only shows the active
scene's frame. Content alpha timing is as today: scene content starts halfway through the slide, the
showcase from 70%.

### Showcase

`Cinematic/Showcase.lua` is today's file, moved. The engine creates it lazily the first time an `Enter`
has `opts.showcase` set. An AFK scene can reuse it later.

## Flight module (`Modules/Flight/`)

### Activation (`toggle(true)`)

- Register `PLAYER_ENTERING_WORLD`, `LOADING_SCREEN_ENABLED`/`DISABLED` and `ZONE_CHANGED_NEW_AREA`
  on the module's own event frame. Combat events are now handled by the engine.
- Install the hooks on first activation: `TakeTaxiNode`, the taxi frame tooltip and the flight map. If
  `Blizzard_FlightMap` isn't loaded yet, the flight module's event frame registers `ADDON_LOADED` until it
  loads, then installs the flight map hook and unregisters the event.
- If `IsLoggedIn()`, run the same resume check as `PLAYER_ENTERING_WORLD`: resume `db.current` if
  `UnitOnTaxi("player")` and it's younger than an hour, otherwise clean it up. That covers turning the
  module on mid-flight after a reload.

### Deactivation (`toggle(false)`)

- If a flight is active:
  - `ns.Cinematic.Release(flight)` brings back the UI (or schedules it for after combat), the camera, the
    pitch limit and the music, and stops the idle watcher.
  - `ns.Bar_Stop()`.
  - Drop `flight`, `tracker` and `pending`, and set `db.current = nil`. The interrupted flight isn't
    recorded.
- Otherwise, if `db.current` still holds a stale state, call `ns.Cinematic.Release` on it and clear it.
- `EndFlight` (landing) also calls `Release` instead of today's `Cinematic_Exit`.
- Hide the ticker and unregister events. A preview of the unlocked bar is hidden too.

### Tick

Today's `OnUpdate` body moves unchanged onto the ticker frame (0.2s throttle), calling the engine API.
The ticker is shown by `TakeTaxiNode` (pending route) and by `StartFlight`, and hidden by `EndFlight`, the
start timeout and deactivation.

Tick logic that needs the cinematic:

- `ns.Cinematic.Enter(scene, flight, { orbit = db.orbit, showcase = db.showcase, music = db.music and db.musicTrack or nil, resumeDelay = db.resumeDelay, skipCamera = ns.OrbitFactor(...) < 1 })`
- `ns.Cinematic.Update(flight, ns.OrbitFactor(flight.expected, elapsed))`
- `Exit` / `Watch`, as today

### Scene (`Scene.lua`)

Today's `Bands.lua` minus the hint, wrapped in the scene contract. `Begin(flight)` = today's
`Bands_SetFlight`. `Update` = today's `Bands_Update` plus `ZoneText_SetAlpha`. The zone text frame is
created in `Create`. `ZONE_CHANGED_NEW_AREA` shows the zone text only if
`ns.Cinematic.IsOwner(flight)`, matching today's "only while the cinematic is active".

### Commands (`/tomte flight ...`)

`stats`, `resetstats`, `reset`, `lock`, `unlock`, `testalert`. The `alert` and `cinematic` toggles are
dropped from the slash commands because they're one click away in the options pane. `/tomte flight` with
no subcommand lists these.

## Slash commands (`/tomte`)

- `/tomte` toggles the panel.
- `/tomte help` lists the core commands and each module's commands (shown only for modules that have
  any).
- `/tomte <moduleKey> <cmd>` runs a module command. It works while the module is inactive too (stats,
  reset). Commands that need the module running say so: `lock`/`unlock` print "Flight Timer is off." when
  inactive.

Chat prefix: `|cff66ccffTomte|r: `.

## Panel (`Panel/`)

### Frame and modes

- One frame, `TomtePanel` (named for `/fstack` debugging), about 780×500, built on first use.
  - **Standalone:** parented to `UIParent`, centered, movable by its title area, and toggled by
    `/tomte` and the compartment button.
  - **Embedded:** `Settings.RegisterCanvasLayoutCategory(holder, "Tomte")` and
    `Settings.RegisterAddOnCategory`. The holder's `OnShow` re-parents the panel into the holder (no
    title bar, no close button). Its `OnHide` hides the panel. Toggling standalone while embedded and
    shown does nothing (same as Plumber).
- **Esc:** a hidden dummy frame `TomtePanelEscape` is in `UISpecialFrames` and is shown only while the
  panel is standalone. Its `OnHide` hides the panel. Embedded, Blizzard's settings frame handles Esc.
- Hiding the panel calls each module's optional `panelClosed()` (the flight module stops its music
  preview there).
- The panel isn't protected and can open in combat. Opening Blizzard's Options in combat is Blizzard's
  problem, not ours.

### Layout

```
+--------------+-----------------------+---------------------------+
| TOMTE        |                       |                           |
| [search____] | TRAVEL                | Flight Timer              |
|              | [x] Flight Timer   *  | ------------------------- |
|  All         |                       | Timer                     |
| >Travel      |                       |  [x] Lock timer bar       |
|              |                       |  [x] Arrival alert        |
|              |                       |  Alert sound      [Test]  |
|              |                       | Cinematic flights         |
|              |                       |  ...                      |
+--------------+-----------------------+---------------------------+
   170px            ~260px                   rest (scrolls)
```

- **Left:** the search box, then "All" plus one button per category. The selected category is
  remembered in `TomteDB.panel.category`.
- **Center:** the modules of the selected category, or all modules (grouped under category headers)
  for "All" or while searching. Each row has a checkbox, the name and a gear (`*`) button.
  - The checkbox calls `ns.SetModuleEnabled`.
  - A blocked module's row is greyed out and its checkbox disabled.
  - The center list is a plain frame with pooled rows (the module count stays small). If it ever
    overflows, it gets the same scroll frame as the options pane.
- **Right:**
  - Hovering a row shows its name, description and (if blocked) the reason.
  - Clicking a row or its gear **selects** the module, and the right pane then shows its options. The
    selection stays until another module is selected.
  - With nothing hovered or selected, it shows a short "Select a module" line.
  - The options area scrolls: a `ScrollFrame` with a slim custom scrollbar, because Flight has about
    15 rows.
- **Search** filters by case-insensitive substring of name and description, live as you type. Esc in the
  search box clears it.

### Style

- The background is near-black (`0.06, 0.06, 0.07, 0.96`) with a 1px dark-gold border.
- The title "TOMTE" is in Morpheus.
- Column dividers are the same fading gold hairlines as the cinematic.
- Text: GOLD `1, 0.82, 0.45` for headers, WHITE `0.92` for labels, GREY `0.62` for descriptions.
- The selected category and module rows get a faint gold highlight bar.
- All color textures are `SetColorTexture`; no art files.

### Widgets (`Panel/Widgets.lua`)

All of them are built from color textures and font strings:

- **Checkbox:** a 14px square with a gold border and a gold fill when on.
- **Slider:** a 1px track, a gold fill and a small square thumb, plus a value label on the right using
  the `format` function. It's draggable, and the mouse wheel steps it.
- **Button:** a dark box with a gold border and a gold glow on hover.
- **Dropdown:** a button showing the current choice's text. A click opens
  `MenuUtil.CreateContextMenu(button, function(_, root) root:CreateRadio(text, isSelected, setSelected, value) ... end)`.
  `MenuUtil` is used by installed addons on this client; check `CreateRadio` on warcraft.wiki.gg
  (`API_MenuUtil.CreateContextMenu`, Blizzard_Menu docs) before building.
- **Header:** gold text plus a hairline.

Widgets are pooled per type. Selecting a module releases the pane's widgets and builds them from its
schema.

### Options schema

A list of rows. `key` is a path into `module.db`, using dots for nested keys (`"frame.locked"`).

```lua
{ type = "header", label = "Timer" },
{ type = "checkbox", key = "frame.locked", label = "Lock timer bar", tooltip = "...", onChange = fn },
{ type = "slider", key = "cinematicMin", label = "...", min = 10, max = 60, step = 5,
  format = function(v) return v .. "s" end, tooltip = "..." },
{ type = "dropdown", key = "musicTrack", label = "Music track",
  choices = function() return { { value = 1, text = "Midnight" }, ... } end },
{ type = "button", label = "Arrival alert sound", text = "Test", onClick = fn, tooltip = "...",
  confirm = "optional popup text" },
```

- Changing a value writes `module.db`, then calls `onChange(value)` if it's set.
- Tooltips use `GameTooltip`.
- `confirm` shows a `StaticPopup` (Yes/No) before running `onClick`.
- Values are read again whenever the pane is rebuilt or shown, so `/tomte flight lock` and dragging the
  bar stay in sync.

### Flight options (all of today's Settings.lua)

- **Timer:**
  - Lock timer bar (`frame.locked`, `onChange = ns.Bar_SetLocked`)
  - Arrival alert (`alert`)
  - Arrival alert sound [Test]
- **Cinematic flights:**
  - Cinematic mode (`cinematic`)
  - Camera orbit (`orbit`)
  - Character showcase (`showcase`)
  - Minimum flight length (`cinematicMin`, 10–60, step 5)
  - Resume after idle (`resumeDelay`, 10–60, step 5)
  - Flight music (`music`)
  - Music track (dropdown over `ns.MUSIC_TRACKS`)
  - Preview track [Play] (15s; click again to stop)
- **Data:**
  - Recorded flight times [Reset] (confirm)
  - Flight stats [Reset] (confirm)

Tooltips are copied from today's `Settings.lua`. The flight module's `Settings.lua` is deleted; its music
preview logic moves into `Flight.lua`.

## Error handling

- Module `toggle` errors are isolated with `xpcall` + `geterrorhandler()`; see Activation.
- The engine keeps today's guarantees:
  - `Exit` is idempotent.
  - The UI is never left hidden or invisible: in combat it is set to alpha 1 and shown after combat.
  - Camera changes are undone exactly, from the persisted `state`.
  - The music volume is restored only if it is still 0.
- If an options `onChange` errors, the BugSack trace is reported and the value stays written. No extra
  handling.

## Testing

### Unit tests (plain Lua, run from the AddOns folder)

- `lua Tomte/tests/test_flight_data.lua`: today's tests with only the `loadfile` path changed
  (`Tomte/Modules/Flight/Data.lua`). All must pass unchanged.
- `lua Tomte/tests/test_modules.lua`, which tests:
  - **Registry:** `enabledByDefault` falls back when `enabled[key]` is nil.
  - **Blocking:** a blocked module isn't active, and stops being blocked once the reason is gone.
  - **Toggle calls:** `toggle` is called only on state changes.
  - **Errors:** a `toggle` that errors is reported through the stubbed `ns.errorHandler`, and the other
    modules still activate.
  - **Copy:** `CopyFlightData` is a deep copy, drops `current`/`musicVolumeBackup`, and leaves the
    source unchanged.
  - **Merge:** `MergeDefaults` adds missing nested keys and keeps existing ones.

`Modules.lua` and the `CopyFlightData` part of `Migration.lua` call no WoW APIs at file load, so the tests
can `loadfile` them with a stub `ns`.

### In-game checks (the user, after `/reload`)

1. **Hand-over:** with FlightTimer and Tomte both enabled, log in. Expect the "flight data copied" line,
   FlightTimer still timing flights, and the Tomte panel showing Flight Timer greyed out with the reason.
   Fly once, then `/reload`. Disable FlightTimer and `/reload`. Expect no copy line, and the taxi-map
   tooltips showing the old times plus the flight you just flew. `/tomte flight stats` matches.
2. **Flight as before:** take a flight long enough for cinematic mode. Check the letterbox, title card,
   showcase, zone text, music (if on), the pause on click/Esc, the idle resume, the arrival shot and the
   alert.
3. **Off mid-flight:** during a cinematic flight, `/tomte` → uncheck Flight Timer. The UI, camera tilt,
   zoom and music come back at once, and the bar disappears. Check it again: no errors. On the next flight
   it works normally.
4. **Panel:** `/tomte`, the compartment button and Esc all work. Options > AddOns > Tomte shows the same
   panel embedded. Search filters. Hovering shows the description, and the gear opens options. Every
   flight option works, including the dropdown and the preview.

Idle cost isn't measured in game. It is checked in code review against the performance rules: no frame
with an `OnUpdate` is shown while nothing is happening, and only the listed events are registered while a
module is inactive.
