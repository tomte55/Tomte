# Tomte: Stat weights for every spec, and upgrades for alts

Date: 2026-10-06. Asked for by the user ("our own weights for each spec, then when a character is max level they can
get a fresh one from Raidbots"). **Spec only, not built.** Builds on Gear Check and its scales
(`2026-10-03-tomte-gear-check-design.md`, `2026-10-03-tomte-gear-scales-design.md`) and Alts.

Two parts that depend on each other: part 2 judges gear for alts of any class, which only works well once part 1
gives every spec real weights.

## Part 1: built-in weights for every spec

### Why

Today only BM / MM Hunter and Prot Paladin have built-in weights. Every other spec gets main stat 1 /
secondaries 0.5, which is close to item level only. Alts of other classes (and the main's off-specs) deserve a
better default before they're max level and worth a Raidbots sim.

### Order of weights (unchanged, one more step)

1. **Imported** for this character and spec (`/tomte gear import`, Raidbots Pawn string). Per character, as today
   (`db.weights[guid][specID]`).
2. **Built-in** for the spec, in `Gear/Scales.lua`: now **every spec of every class** (13 classes, 40 specs
   in Midnight, Devourer Demon Hunter included).
3. **Fallback** main stat 1 / secondaries 0.5: only for a spec missing from the table (a new spec in a patch).

### Where the numbers come from

Same rules as the first three (Pawn is CC BY-NC-ND, so its scales aren't copied):

| Role | Source | Label in game |
|---|---|---|
| DPS | SimulationCraft single-target sims of the default profiles for the current build (mythicsim.com/stat-priority, as for BM/MM), normalized to main stat = 1 | "sims, Midnight S2" |
| Tank | Same damage sims (as Prot Paladin). Usually near-flat secondaries, so item level decides, which matches guides | "sims, Midnight S2" |
| Healer | There's no healing sim to copy. The current stat priority from class guides (Wowhead, Method, Icy Veins, agreeing on order), turned into weights on a fixed ladder: main 1, then 0.70 / 0.60 / 0.50 / 0.40 for the secondaries in priority order; two stats a guide calls "equal" share a value | "guide priority, Midnight S2" |

- The table keeps one `season` and `seasonName`; every entry has its `label`. The stale-season hint already exists
  and now covers every spec.
- Stamina stays out of the weights (as today). Armor for tanks stays out.
- Kept by hand each season. A small `tests/test_gear.lua` sanity check per entry: main stat is 1, it's the right
  main stat for the spec, secondaries are between 0 and 1, all four secondaries present.

### Telling the user (changes to the existing hints)

| When | Where | Text |
|---|---|---|
| Built-in weights in use, below max level | nowhere | (nothing: built-in is fine while leveling) |
| A character reaches max level with built-in weights for its spec, or logs in at max level and hasn't been told for that spec | chat, once per character and spec | "Mira is max level: sim Holy on Raidbots for weights that fit your gear, then /tomte gear import." |
| Same, as a suggestion | Next up (new source "Sim on Raidbots", score 30, on that character only) | "Sim Holy on Raidbots" · why: "Built-in weights are a guide; your own sim fits your gear". Click: prints the `/tomte gear sim` steps and opens the import dialog. "Not now" works as for other sources |
| Healer guide weights | Gear sheet's "Stat weights" row and `/tomte gear weights` | "built-in, guide priority, Midnight S2: import a sim for better" |

The once-per-spec "using built-in weights" chat hint from the scales spec is dropped for characters below max level
(it would fire on every alt) and replaced by the max-level hint above. Saved state: `db.hinted[guid][specID]`
(today it's per spec only; migrate the old key to the current character).

### Off-spec lines

Off-spec verdicts ("Also an upgrade for Marksmanship +4.0%") already run for every other spec with weights. With
weights for every spec they show up for every class. That's intended; the existing `offspec` option turns it off.

## Part 2: upgrades for alts

### Goal

"Is this item in my bags (or on this vendor / quest / AH) an upgrade for one of my other characters?" The main
gathers and the alts support, so warbound and BoE gear the main finds should go to whoever it helps.

### What Alts stores per character (new fields)

Read by Alts' Collect.lua on the triggers it already has (gear and spec changes included), debounced as today:

```
chars[guid].gear    = { [invSlot] = itemLink, ... }  -- worn items, slots 1-17 (no shirt, tabard)
chars[guid].specID  = number                         -- current spec
chars[guid].primary = "STR" | "AGI" | "INT"          -- that spec's main stat (GetSpecializationInfo's primaryStat)
chars[guid].classToken = "PRIEST", ...               -- for armor type
chars[guid].gearAt  = time()                         -- when the gear was read
```

Item links work on any character, so stats are read from the link when needed (`C_Item.GetItemStats` / Gear
Check's `GearItems` reader, which already waits for items to load).

### Judging an item for an alt

Gear Check's verdict is already pure: `ns.Gear_Evaluate(cand, equipped, ctx)`. For an alt:

- `equipped` = the alt's stored worn links, read into Gear Check's item descriptions (cached per link).
- `ctx` = a new `ns.Gear_ContextForChar(char)`: the alt's spec, main stat, armor type from its class
  (`Gear_ArmorForClass`), weights from part 1's order using **the alt's own** imported weights
  (`db.weights[altGuid][specID]`) or built-in, best gem for those weights.
- Required level is checked against the alt's level (stored), not the current character's.
- Unique-equipped and tier set counts use the alt's worn items (the evaluator already takes them from `equipped`).

**Only items that can get to the alt** are judged:

- Warbound / Warbound until equipped: yes.
- Bind on Equip, not yet bound: yes.
- Soulbound or already bound to this character: no.

**Only clean upgrades count** (`Gear_IsCleanUpgrade`), as with off-spec lines: "Upgrade, but…", sidegrades and "sim
it" items (trinkets, effects) say nothing for alts.

### Where it shows

| Place | What | Rule |
|---|---|---|
| Item tooltip | "Upgrade for Mira (Holy): +8.2%" in green, under Gear Check's own lines. Up to 2 alts, best first, then "+n more" | Only clean upgrades; only items that can reach the alt |
| Baganator | A second corner widget "Tomte: upgrade for an alt": a small map-blue arrow (`#8FC7FF`), so it's clearly not the gold arrow for this character | Only when the item is **not** an upgrade for the current character (the gold arrow wins) |
| Mailbox (Send to alt) | A "Gear for Mira" group in the "For your alts" panel, BoE items only | Warbound items go to the Warband bank deposit instead, as Send to alt already does for warbound materials |
| Home / Next up | nothing | Kept out to avoid clutter |

### Which alts count

Setting "Upgrades for alts: All characters / Max level only / Off" (default All characters). Characters not seen for
more than 60 days are skipped (their gear snapshot is old).

### Performance

- Verdicts cached per `(itemLink, altGuid)`; the cache for an alt is cleared when its gear, spec or weights change.
- Tooltip work is bounded by the number of alts (one evaluation each, cached).
- Baganator asks per item; the answer comes from the same cache. Items still loading return "unknown" and are
  asked again (as the existing upgrade arrow does).

### Settings (Gear Check)

| Setting | Choices | Default |
|---|---|---|
| Upgrades for alts | All characters / Max level only / Off | All characters |
| Mark alt upgrades in Baganator | on / off | on |
| Gear for alts at the mailbox | on / off | on (needs Send to alt) |

## Testing

- Plain Lua: every Scales entry passes the sanity check; the max-level hint fires once per character and spec and
  not below max level; `Gear_ContextForChar` builds the right armor type, main stat and weight source for a plate,
  cloth and leather alt; the transfer rule (warbound / BoE yes, soulbound no); alt verdicts use the alt's level and
  worn items; the "+n more" line.
- In game: a warbound helm on the main that's an upgrade for a cloth alt (tooltip and blue Baganator arrow); a BoE at
  the mailbox; an item that's an upgrade for both the main and an alt (gold arrow only, both tooltip lines); an alt
  reaching max level gets the Raidbots hint once.

## To verify

1. **Bind state of a bag item and of a link**: `C_Item.IsBound(itemLocation)`, `C_Item.IsBoundToAccountUntilEquip`
   / `C_Item.IsItemBindToAccountUntilEquip(link)`, and the bind type from `C_Item.GetItemInfo` (14th return) in 12.1;
   tooltip data lines as a fallback.
2. **Spec list**: the 40 spec IDs and main stats from `GetNumSpecializationsForClassID` /
   `GetSpecializationInfoForClassID` (Devourer's ID), read once in game with a debug command and copied into Scales.
3. **Current numbers**: mythicsim.com/stat-priority for every DPS and tank spec at the build we're on, and the
   healer guides' priorities, on the day the table is filled in.
4. **Baganator**: a second corner widget from the same addon (two `RegisterCornerWidget` calls) and how Baganator
   orders two widgets in one corner.
