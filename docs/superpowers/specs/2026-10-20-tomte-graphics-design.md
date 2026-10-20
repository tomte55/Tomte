# Graphics presets (`graphics`)

2026-10-20. Part of the addon round (`2026-10-20-tomte-addon-round-overview.md`). Inspired by PeaversPerformance.
The user handed every decision to Claude; decisions marked **(Claude's call)** can be tweaked after testing.

## Intent

Lower (or raise) the game's graphics depending on where you are: crisp in the open world, light in a 20-player raid
or a battleground, a frame rate cap while AFK. Tomte switches as you move and always gives your own settings back.

## Goals

- Six situations: open world, cities and inns (rested), dungeons and delves, raids, battlegrounds and arenas, AFK.
- Per situation: a Graphics Quality level 1-10 or "Leave alone", and a frame rate cap or "Leave alone".
- Tomte keeps the player's own values the first time it changes a CVar and restores them when no preset applies,
  on logout/reload and when the module turns off.
- A change the player makes by hand always wins (rule below). Tomte never fights the player.
- Never changes graphics in combat; one write per loading screen.

## Non-goals

- No individual sub-settings (shadows, view distance ...) per situation: the overall level moves them the way the
  game's own slider does.
- No render scale, no background frame rate, no automatic "detect a slow frame rate and lower graphics".
- No change to the AFK Screen module.

## Defaults (Claude's call)

- Module off by default (it changes the game's settings).
- Every situation is "Leave alone" for both quality and frame rate cap: turning the module on changes nothing until
  the player picks a level for a place. Any level would be a guess about the friend's hardware.

## Situations and priority (Claude's call)

Priority order: PvP, raid, dungeon/delve, AFK, city, open world. Instances exclude each other and only the instance
counts inside one (AFK inside a dungeon doesn't switch graphics: coming back mid-pull to a texture reload is worse).
Outside instances AFK beats a city, a city beats the open world.

- PvP: `GetInstanceInfo()` instanceType `pvp` or `arena`.
- Raid / dungeon / delve: `ns.Check_ContentKind` (Core/CheckData.lua). Every other scenario (visions, story
  scenarios) counts as "Dungeons and delves".
- AFK: `UnitIsAFK("player")` (secret in chat lockdown: the last readable value is kept). The AFK flag, not the AFK
  Screen module's scene: AFK has no public `ns.AFK_*` signal for "screen showing", and capping the frame rate while
  flagged AFK is what matters. A frame rate cap does make the AFK screen's orbit less smooth; the player chooses.
- City: `IsResting()` (cities and inns).
- Open world: everything else (also housing instances or unknown instance types).

Each group (quality, frame rate) falls through "Leave alone" on its own: AFK in a city with AFK quality "Leave
alone", city quality 5 and AFK cap 30 gives quality 5 and a 30 fps cap. No situation with a preset: the player's
own values.

## The "player wins" rule (Claude's call)

Tomte records what each CVar it set reads back as (`db.applied`). When one of those reads differently later
(`CVAR_UPDATE`, checked 0.5 s after the last one, because Blizzard's slider writes ~14 CVars in a row), the player
(or another addon) changed it:

1. That group's (quality or frame rate) kept originals and applied values are forgotten: the values the player just
   picked are now their own. Nothing is written.
2. Tomte keeps out of that group until a different situation wins (or none does). Coming back to the same place
   later applies the preset again.
3. One chat line says so.

So: the last graphics you picked yourself is what Tomte restores. "Restore my settings now" works the same way:
restores everything and keeps out until the situation changes. Moving a Tomte slider clears all pauses.

At the first check of a session a difference means the previous session ended without the logout restore (crash):
adopted quietly, without the pause.

## API findings

- Blizzard's Graphics Quality slider (`Blizzard_SettingsDefinitions_Shared/Graphics.lua`, `OnGCChanged`, live
  branch of https://github.com/Gethe/wow-ui-source) writes `graphicsQuality` (0-9, shown as 1-10 via
  `IncrementByOne`), then for each sub-setting sets `GetGraphicsCVarValueForQualityLevel(cvar, value, raid)`, raised
  to the setting's `minQualityValue`. The sub-setting list is `GraphicsOverrides.CreateAdvancedSettingsTable`
  (`Blizzard_Settings_Shared/Mainline/GraphicsOverrides.lua`): shadow, liquid, particle density (minimum 1, base
  set only), SSAO, depth effects, compute effects, outline, texture resolution, spell density (only when
  `C_VideoOptions.IsSpellVisualDensitySystemSupported()`), projected textures, view distance, environment detail,
  ground clutter. So setting `graphicsQuality` alone does not move the sub-settings from Lua; Tomte mirrors the
  slider exactly (overall CVar first, then the rest).
- Raid and Battleground copies: `raidGraphicsQuality` + `raidGraphics*`, used by the game while `RAIDsettingsEnabled`
  is on. Tomte writes the raid copies with the same level only when that switch is on (else they're unused), and
  restores them the same way **(Claude's call)**.
- `GetGraphicsCVarValueForQualityLevel`: a global C function used by Blizzard's live settings code, not on
  warcraft.wiki.gg and not in the generated API docs. Guarded: existence check plus `pcall`; without it only the
  overall CVar is set.
- `C_CVar.SetCVar` (https://warcraft.wiki.gg/wiki/API_C_CVar.SetCVar): refuses secure CVars in combat
  (`RequiresNonSecureCVar`); graphics CVars aren't secure, but Tomte still never applies in combat (a texture reload
  stalls a frame) and waits for `PLAYER_REGEN_ENABLED`. The wiki recommends restoring temporary CVars on
  `PLAYER_LOGOUT` and adopting a user's change: both done.
- `CVAR_UPDATE` (https://warcraft.wiki.gg/wiki/CVAR_UPDATE): payload `cvarName, value`; `SynchronousEvent = true` in
  `CVarDocumentation.lua`, so it fires inside our own `SetCVar` calls (ignored with a `writing` flag; the read-back
  compare is the backup).
- Frame rate cap: `useMaxFPS` (bool) + `maxFPS` (Blizzard's slider 8-200; https://warcraft.wiki.gg/wiki/CVar_maxFPS).
- `GetInstanceInfo`, `IsResting`, `PLAYER_UPDATE_RESTING`, `UnitIsAFK`, `PLAYER_FLAGS_CHANGED`: wiki-checked.
- Debounce: `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_UPDATE_RESTING`, `PLAYER_FLAGS_CHANGED` restart
  a 2 s timer; one apply after the last.

## Saved data

`TomteDB.graphics`: `quality = { [situation] = 0 | 1-10 }`, `fps = { [situation] = 0 | fps }`,
`saved = { [cvar] = player's value }` (while changed), `applied = { [cvar] = value read back after Tomte set it }`.
`saved`/`applied` are collections: kept by Reset, not in profile strings. Pauses are session-only.

## Settings

Group `tomte`. Card "Graphics quality": one slider per situation (0 = Leave alone, 1-10). Card "Frame rate cap": one
slider per situation (0 = Leave alone, 10-200 step 10). Card "Your settings": "Restore my settings now" (Restore),
"What's applied" (Show).

## Commands

- `/tomte graphics why`: which place this counts as, what's applied per group (or paused), current quality level
  and the player's own, current frame rate cap.
- `/tomte graphics restore`: your own settings back now; hands off until you go somewhere else.

## Test plan (in game)

Before: note your own Graphics Quality level (Esc > Options > Graphics) and frame rate cap.

1. `/reload`. Tomte window > Tomte group > Graphics presets: turn it on. Nothing changes (all Leave alone).
   `/tomte graphics why` says "Open world" (or "Cities and inns, Open world" in a city) and "leave alone".
2. In the open world set Open world quality to 3. Half a second after letting go the world looks worse; the game's
   Graphics settings show Graphics Quality 3 and the sub-settings moved like dragging the game's own slider. `why`
   says "yours: level <your level>".
3. Set Cities and inns quality to 8 and Open world back to Leave alone. Fly into a city: ~2 s after entering the rest
   area, level 8; leave the city: your own level again.
4. Frame rate: set While AFK cap to 30, type `/afk`, show the frame rate (Ctrl+R): ~30 fps after 2 s. Clear AFK:
   back to your own cap.
5. Player wins: with a preset active (step 2), change Graphics Quality yourself in the game's settings. One chat line
   ("you changed your graphics ..."); Tomte doesn't change it back. Leave and come back: preset applies again.
6. "Restore my settings now": your own level back at once; stays until you go somewhere else.
7. With a preset active, `/reload`: after reload the preset is back (the logout restore wrote your own values to the
   config, the login applies the preset again). Log out fully and check Config.wtf (`WTF/Config.wtf`,
   `SET graphicsQuality`) holds your own level.
8. With a preset active, turn the module off: your own settings back immediately.
9. Combat: set Dungeons and delves to a level, enter a dungeon and pull before 2 s pass: nothing changes until combat
   ends.
10. If "Raid and Battleground" graphics are on in the game's settings, entering a raid with a raid level set moves
    that copy too (`why` says "raid and battleground copy follows").

Errors: BugSack. `/etrace` filtered on `CVAR_UPDATE` shows the writes.
