# Quest list: a replacement for the objective tracker

2026-11-10. New module. Forever first; retail sections designed in, built second.

## Why

Blizzard's objective tracker (and Forever's copy of it) is a flat list of titles and `0/6` lines sorted by category.
It doesn't know where your quests are, what they give, or which one you should do next. Tomte already knows those
things (Leveling's Next quests widget groups quests into nearby stops), and Spoken (the Forever voice-over addon) puts
a Play button on each tracker quest. The goal is one quest list on screen that does all of it, looks like Tomte, and
can be shaped by each player to their taste.

## Goals

- Replace the default quest tracker while the module is on; give it back untouched when it's off.
- Group quests by where they are (Next quests' stops), nearest first, turn-ins first.
- Play buttons for Spoken on every quest row, with Spoken's own states.
- Hook into Travel (route to a quest), Leveling (XP, stops), Recent/Session (completed quests).
- Plenty of settings: layout, look, visibility, per-quest details, Spoken, sections. A friend who never opens the
  settings still gets a calm, readable list.

## Non-goals

- Achievement tracking (Almost Done has its own tracker), scenario/dungeon objective blocks, bonus objectives on
  Forever. While in a scenario or instance with objectives, the module either steps aside or hides (setting).
- Our own waypoint arrow: Travel's arrow and the map marker do that.
- Automating anything that needs a hardware event.

## Anti-goals

- A list that taints Blizzard's frames: clicking a quest item, opening the map or using Esc in combat must keep
  working ([[never-open-map-from-code]], [[never-call-isanybagopen]]).
- Two quest widgets on screen at once (this list plus Next quests, or this list plus EllesmereUI's tracker).
- Losing Spoken's Play buttons because the tracker they hook is gone.

## Where it runs

- **Forever (phase 1):** the full module. Stops come from Leveling (`ns.Leveling_NextStops`, Forever only).
- **Retail (phase 2):** same list, grouped by zone (no stops), plus sections for world quests (`wq`), gold quests
  (`wgq`) and weekly (`weekly`), each asked through `ns.HomeCall` / `ns.<Prefix>_*` functions, never their db.
  Phase 1 must not hardcode Forever: the grouping is a setting with a fallback when stops are not available.

## Module

- Folder `Modules/QuestList/`, key `questlist`, name "Quest list", category `quests`, `enabledByDefault = false`
  (it replaces a Blizzard frame).
- `uses` Spoken (and lists EllesmereUIQuestTracker under `conflicts`: when it's loaded, the module's settings page
  says so and the list doesn't start).
- Files (load order): `Data.lua` (pure: grouping, order, folding, row text, "+N more"), `Read.lua` (quests,
  objectives, points, items), `Spoken.lua` (Play buttons), `Item.lua` (secure item buttons), `List.lua` (the frame),
  `QuestList.lua` (main: events, db, options, commands, Edit Mode).
- Test: `tests/test_questlist.lua`.

## Hiding Blizzard's tracker

Hide `ObjectiveTrackerFrame` (Forever: whatever frame holds `QuestObjectiveTracker`) while the module is on, restore
it on stop. Never in combat: if the module starts or stops in combat, wait for `PLAYER_REGEN_ENABLED`. How to hide it
without taint (Hide vs alpha 0 + mouse off vs reparenting) is to be measured in game; the builder tries the least
invasive one first and checks that quest items, map and Esc still work in combat.

## Layout

- **Group by:** nearby stop (default on Forever), zone (default on retail), or plain list.
- Stop header: place name and distance ("Camp Taurajo · 180 yd", meters if Leveling's metric setting is on: ask
  Leveling through a function). The nearest N stops open (setting, default 1); the rest fold into one line each
  ("Stonetalon · 3 quests · 900 yd"), click to open.
- Inside a stop: turn-ins first (setting), then Next quests' order (timed, lowest level, most XP).
- "+N more" after the per-stop limit; click expands.
- Quests with no map point go to a last "Elsewhere" group.
- Click a quest: make it the active quest (`C_SuperTrack.SetSuperTrackedQuestID`, as Next quests does), which Travel
  then routes to. Shift-click: untrack / track. Right-click: `UI.ContextMenu` (fold, untrack, share, abandon via
  `ns.Confirm_Show`, open in the quest log through the safe opener, Play in Spoken).
- Hover a quest: tooltip with description summary, rewards, XP.
- Fold: click a stop header to fold it; a minus in the corner folds the whole list to its title
  (`ns.EditMode_Fold`, as Almost Done does).

## Rows

- Level pill (colored by difficulty, plain number, or hidden), title, then on the right: item button, Play button.
- Objectives under the title: thin progress bars in the theme accent, or text `0/6` (setting).
- Turn-in quests: success color, a tick, and "Turn in to <NPC>" when the client gives the name, else "Ready to turn in".
- Optional detail line: XP and/or distance (settings).
- Focus glow: the active (super-tracked) quest gets an accent edge.

## Motion

Uses the existing Motion kit ([[motion-facts]]): a progress flash and bar fill when an objective moves, a row that
glides to the turn-in group when a quest completes, rows fading in and gliding when the order changes. One setting
turns it all off. No OnUpdate while nothing animates.

## Visibility

- In combat: show / fade to a set alpha / hide (default fade).
- Fade until mouse-over (default off).
- Hide in dungeons and raids (default off).
- Auto-fold quests not progressed in a while (default off; "a while" is the builder's call, about 30 minutes of
  play).
- Fully hidden while Moments cinematics play (they already hide UI; check it covers this frame).

## Spoken

Spoken's tracker Play buttons hook `QuestObjectiveTracker:AddBlock`; with the tracker hidden they never show. The list
draws its own Play button per quest, only when `Spoken and Spoken:IsCompatible(1)` and Spoken_Quests is loaded.

- States follow Spoken's (playing, queued, played, no recording); right-click stops / replays.
- "Now speaking" marker: the quest Spoken reads gets a small speaker mark and a progress line under its title.
- Quests with no recording: Spoken's Contribute hint, only if `Spoken:AreContributeButtonsHidden()` is false.
- **How:** Spoken's public API (`API.lua`) has no "bind a button to a quest" call; the binding lives in Spoken_Quests'
  private `QuestOverlayUI:BindPlayButton`. Preferred: a new public call in Spoken (see Open). Fallback: reach the
  private one behind `pcall`, guarded on every field, and hide the buttons if it's missing.

## Other modules

- **Leveling:** stops and order from `ns.Leveling_NextStops` (moved out to a shared call if needed). While the Quest
  list is on, the Next quests widget doesn't show (Leveling asks `ns.QuestList_Active()`), and its settings say why.
  XP per quest on the row; optional header line "3 turn-ins: 42% of a level" via `ns.Leveling_XPView`.
- **Travel:** the active quest is the one Travel routes to; stop distance is the straight distance (route distance
  later if Travel exposes it cheaply).
- **Quest items:** a usable quest item shows as a button on its row. Secure (`SecureActionButtonTemplate`), created
  out of combat, lazily, never anchored to a normal frame ([[secure-button-gotchas]]): it is positioned by its own
  points and moved only out of combat. In combat the row's button stays where it was; layout changes wait.
- **Recent / Session:** quest completed and turned in feed `ns.Session_Note` (check what Quests already sends, don't
  double).
- **EllesmereUI:** `ns.Ellesmere_Loaded("QuestTracker")` → the module doesn't start and says so.

## Settings (options schema, one card per header)

**Layout**: Group by (stop / zone / list) · Stops shown open (1–5, default 1) · Turn-ins on top (on) · Quests per stop
before "+N more" (3–15, default 6) · Width (220–400, default 280) · Scale (0.7–1.3) · Max height (300–900) · position
in Edit Mode.

**Look**: Objectives as bars / text (bars) · Level: colored / plain / hidden (colored) · Background: none / faint /
panel (faint) · Completed objectives: fade out / keep / hide (fade out) · Animations (on) · Focus glow (on).

**Visibility**: In combat: show / fade / hide (fade) · Combat alpha slider (parent: fade) · Fade until mouse-over (off) ·
Hide in dungeons and raids (off) · Auto-fold idle quests (off).

**Details**: XP line (on) · Distance (on) · Quest item buttons (on) · Level-progress header (off).

**Spoken** (rows shown only with Spoken): Play buttons (on) · Now speaking marker (on) · Contribute hint (off).

**Sections** (retail only, phase 2): World quests, Gold quests, Weekly, each on/off, plus their order.

Hover previews per [[setting-preview-rules]]: a sample list (like Almost Done's `DrawSample`) for visual rows.

## Commands

`/tomte questlist why` (why a quest is where it is: stop, distance, order reason), `/tomte questlist reset`
(position).

## Phases

1. Forever: module, list, stops, rows, settings, Blizzard tracker hidden, Next quests steps aside.
2. Spoken Play buttons and now-speaking marker.
3. Quest item buttons (secure), motion polish.
4. Retail: zone grouping, world/gold/weekly sections.

Each phase is tested in game before the next.

## Left to the builder

Exact pixel sizes, colors by role, animation timings, how to read the turn-in NPC's name, the auto-fold time, how
Blizzard's tracker is hidden (measured), splitting files past 900 lines.

## Decided after review (Claude's calls; the user can overturn them)

- **Next quests while the list is on:** the widget and its follow behaviour (`nextFollow`, `addedWatch`) stop
  entirely; Leveling asks `ns.QuestList_Active()`. The list has its own "Follow the nearest quest" setting
  (Layout card, default on) that super-tracks the top quest the same way. Leveling's settings stay untouched (no
  migration) and say "Shown by the Quest list" while it's on.
- **Other maps:** quests with points on your map and the maps around it (what Next quests reads today) get real
  stops. Every other quest is grouped one line per zone, with no distance, under "Elsewhere". No new reader work.
- **Phase 1 loads on Forever only** (listed in `tools/forever_list.lua`, not in `Tomte.toc` until phase 4). Phase 4
  adds retail with zone grouping and the sections.
- **EllesmereUI quest tracker loaded:** the list doesn't start, and Next quests behaves exactly as today.

## Decided with the user

- **Which quests:** a Layout setting "Show": *all quests* (default) or *tracked only*. In *all quests*, every quest in
  the log is grouped by stop; untracking a quest (Shift-click or the menu) moves it into a folded, dimmed "Hidden"
  line at the bottom, click to open, track again to bring it back. In *tracked only*, untracked quests aren't shown
  (Blizzard's behaviour), still grouped by stop. Tracking is the game's own watch list, so the quest log stays in
  sync.
- **Spoken:** Spoken can't be changed. Tomte reaches Spoken_Quests' private `QuestOverlayUI` (through the global
  `VoiceOver` environment table that Spoken_Quests' `Environment.lua` exposes: `VoiceOver.QuestOverlayUI`; `BindPlayButton`,
  `SetPlayButtonState`, `FollowQueue`, `ShowsTrackerButton`) and `Spoken.DressBoxButton`, the same calls Spoken's own
  tracker hook makes (`Spoken_Quests/Compatibility.lua`). Every field is checked before use and every call goes
  through `pcall`; if anything is missing or errors, the Play buttons hide and the Spoken settings card says
  "This Spoken version isn't supported". `/tomte questlist why` reports which piece was missing. Credited in a
  comment; no Spoken code is copied.
