# Graphics presets: plan

Spec: `docs/superpowers/specs/2026-10-20-tomte-graphics-design.md`.

1. Verify APIs: Blizzard's Graphics Quality slider (wow-ui-source live, Graphics.lua + GraphicsOverrides.lua),
   `C_CVar.SetCVar`, `CVAR_UPDATE`, `maxFPS`, `GetInstanceInfo`, `IsResting`, `UnitIsAFK`. Done.
2. `Modules/Graphics/Data.lua` (pure): situations and priority, per-group winner with fall-through, pause rule
   (`Graphics_Decide`), CVar list and write order, `Graphics_Plan` (keep originals, write, restore),
   `Graphics_ChangedGroups` + `Graphics_Adopt` (player wins), labels.
3. `tests/test_graphics.lua`: every rule above.
4. `Modules/Graphics/Graphics.lua` (main): read the game, wanted values via `GetGraphicsCVarValueForQualityLevel`
   (raid copies when `RAIDsettingsEnabled`), apply with read-back, detect hand changes on `CVAR_UPDATE`, 2 s
   debounce on zone/resting/AFK events, combat deferral, restore on `PLAYER_LOGOUT` and Stop, options, commands
   `why` and `restore`.
5. Run all tests, `luac -l` global check. Overseer adds the TOC lines (`Modules/Graphics/Data.lua`,
   `Modules/Graphics/Graphics.lua`), runs `lua Tomte/tools/bugfiles.lua`, README row and commands.
6. User tests in game (spec's test plan); CHANGELOG line and commit after that.
