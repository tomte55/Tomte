# Buff reminders: plan

Spec: `docs/superpowers/specs/2026-10-20-tomte-buffs-design.md`.

1. Data: `Data/WarWithin/Buffs.lua` and `Data/Midnight/Buffs.lua` register `buffs = { food, flask, rune }` spell IDs
   (one per buff name) through `ns.Content_Register`.
2. Pure rules: `Modules/Buffs/Data.lua` (`ns.BUFFS_GROUP`, `ns.BUFFS_CHECKS`, `ns.Buffs_PlaceAllows`,
   `ns.Buffs_Watching`, `ns.Buffs_Evaluate`, `ns.Buffs_Missing`, `ns.Buffs_MissingText`, `ns.Buffs_NameList`,
   `ns.Buffs_Label`) with `tests/test_buffs.lua`.
3. Reader: `Modules/Buffs/Read.lua` (`ns.Buffs_Read`): aura reads by localized name only while
   `C_Secrets.ShouldAurasBeSecret()` is false, weapons via `C_PaperDollInfo.GetTemporaryEnchantmentInfo`, group units.
4. UI: `Modules/Buffs/Strip.lua` (`ns.Buffs_StripShow`, `ns.Buffs_StripHide`, `ns.Buffs_StripLayout`,
   `ns.Buffs_StripFrame`).
5. Main: `Modules/Buffs/Buffs.lua`: events while active, Refresh (hidden in combat), buff check through
   `ns.Check_Report`, Edit Mode, options, `why` / `test` / `check` commands.
6. Tests green, `luac -l` globals check. Overseer adds the TOC lines, runs `tools/bugfiles.lua`, README and
   CHANGELOG after the in-game test.
