# Talent check: plan

Spec: `docs/superpowers/specs/2026-10-20-tomte-talents-design.md`.

1. `Modules/Talents/Data.lua` (pure): place kind and key, wanted loadout with override precedence, decision (none /
   learn / switch with a reason), offer rule, remember / forget / prune, saved-entry list, text builders.
2. `tests/test_talents.lua`: every rule above, including deleted loadouts, Starter Build, empty loadout lists,
   override precedence and "for all" dropping the override.
3. `Modules/Talents/Card.lua` (UI): the themed card with a title, text, detail and up to three buttons; Edit Mode
   registration; `ns.TalentsCard_Show/Hide/Shown`.
4. `Modules/Talents/Talents.lua` (main): reads the game (spec, place, active loadout, saved loadouts), runs the check
   on entering / ready check / after leaving an instance, switching through `C_ClassTalents.LoadConfig` with the async
   result, hand-switch detection (hook + `TRAIT_CONFIG_UPDATED`), offers, options with saved-entry rows, commands.
5. Tests green; `luac -l` global scan on the three new files.
6. Report TOC lines, README row and commands to the overseer (shared files are edited by the overseer).

TOC order: `Modules\Talents\Data.lua`, `Modules\Talents\Card.lua`, `Modules\Talents\Talents.lua`.
