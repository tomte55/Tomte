# Plan: Gear Check, Pawn replacement

Spec: `docs/superpowers/specs/2026-10-03-tomte-gear-scales-design.md`

## Steps

1. **Pure logic + tests**: `Advice.lua` (weights source, hints, best gem, gem lines, audit, off-spec line),
   `Data.lua` exports (`Gear_StatsScore`, `Gear_LinkGemIDs`, `Gear_EnchantSlot`, `ctx.gemValue`). Tests in
   `tests/test_gear.lua`. ✅
2. **Data**: `Scales.lua` with the sim weights for 253/254/66, Flawless rank-2 gem IDs, Eversong Diamond IDs. ✅
3. **Item reading**: `desc.gemIDs`, gem stats with tooltip fallback (`Items.lua`). ✅
4. **Wiring**: `Gear.lua` contexts per spec, tooltip lines, chat hints, character pane hook, options and the
   `/tomte gear weights` output. Panel button labels can be functions. TOC load order: Data, Advice, Scales,
   Items, Gear. ✅
5. **In-game check** by the user (checklist below), then commit. ✅
6. **Fill in `season`** in `Scales.lua`: 37 (Midnight S2). ✅
7. **Disable Pawn**, play for a while, and fix what's missing.

## In-game checklist

1. `/reload` with Pawn still enabled. No BugSack errors.
2. On the Hunter in BM: about 8 seconds after login, chat shows "using built-in weights for Beast Mastery (sims,
   Midnight S2)" exactly once. `/reload` again and it doesn't repeat.
3. `/tomte gear weights` shows "built-in, sims, Midnight S2", the weights, a best gem and a season ID number.
4. Hover a bag item that's an upgrade for MM: "Also an upgrade for Marksmanship +x%".
5. Hover an item with an empty socket: "Empty socket: best gem ... (Haste, ...)" plus the Eversong Diamond line if
   you don't wear one.
6. Hover your worn items: an unenchanted head, shoulder, chest, feet, ring or weapon says "Not enchanted".
7. Open the character pane (C): if anything is missing, one chat line lists it. Close and reopen: no repeat.
8. On the Paladin as Prot: the same built-in hint for Protection, and no off-spec lines.
9. `/tomte` → Gear Check: the "Stat weights" row shows the source for your current spec, and the three new
   checkboxes toggle their lines.
