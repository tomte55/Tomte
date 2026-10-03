# Tomte: Gear Check, Pawn replacement (built-in scales, off-spec, gems, enchants)

## Goal

Uninstall Pawn. Gear Check already scores items with Pawn-format weights, shows the upgrade %, and marks bag
upgrades in Baganator. The user also relied on three more Pawn features:

1. **Built-in spec scales**: it works without importing anything.
2. **Off-spec upgrades**: "upgrade for Marksmanship" while you're Beast Mastery.
3. **Gem and enchant hints.**

Scope is the user's own specs only: **Beast Mastery (253) and Marksmanship (254) Hunter, Protection Paladin (66)**.
Every other spec falls back to main stat 1.0 / secondaries 0.5, as before, with a notice.

## Constraints

- **Pawn is CC BY-NC-ND.** We don't copy its scale or gem tables. Weights and gem IDs come from our own sources
  (below). Gem stats are read in game.
- Built-in data goes stale each season, so it's kept small (3 specs, 16 gem IDs) and tagged with its season.

## Weights: where they come from

The priority order per character and spec:

1. **Imported** with `/tomte gear import` (Raidbots Pawn string). Per character, as before.
2. **Built-in** for the spec, in `Gear/Scales.lua`.
3. **Fallback**: main stat 1.0, secondaries 0.5.

The built-in weights come from SimulationCraft single-target sims of the default profiles, build 12.1.0.69933,
published by mythicsim.com/stat-priority (2026-09-27). They're normalized to main stat = 1. Noxxic's 12.1 Pawn
strings agree to within a few hundredths.

| Spec | Main | Crit | Haste | Mastery | Vers |
|---|---|---|---|---|---|
| Beast Mastery | AGI 1 | 0.63 | 0.63 | 0.50 | 0.45 |
| Marksmanship | AGI 1 | 0.71 | 0.55 | 0.51 | 0.44 |
| Protection Paladin | STR 1 | 0.64 | 0.63 | 0.63 | 0.63 |

- **Prot:** these are damage sims. All four secondaries are effectively tied, so item level decides. That's
  intended: guides say "gear by item level" for Prot.
- **BM:** Method ranks Mastery higher than the sims do. We follow the sims. An import overrides them anyway.

## Telling the user which weights are in use

| Source | Tooltip | Chat |
|---|---|---|
| Imported | nothing | nothing |
| Built-in | nothing | once ever per spec: "using built-in weights for X (sims, Midnight S2). For weights that fit your gear, sim on Raidbots and /tomte gear import." Shown again once per new season when the current season is past the scale's. |
| None | grey line under the verdict: "No weights for X: item level only. /tomte gear import" | once per session per spec, at login and on spec change |

- **Season:** `C_SeasonInfo.GetCurrentDisplaySeasonID()` (used by Blizzard's Encounter Journal at any time, no
  request call needed). 0 or nil means unknown, so no stale hint. Midnight S2 is season ID 37 (read in game with
  `/tomte gear weights`, which prints the current ID).
- **Saved state:** `db.hinted[specID]` = `"builtin"` or `"stale:<season>"`.
- **Where the source shows:** `/tomte gear weights` prints the source, the weights, the best gem and the season
  ID. The panel's "Stat weights" section has a row labelled with the source (e.g. "Beast Mastery: built-in, sims,
  Midnight S2") and a Show button. To support this, a panel button label can be a function.

## Off-spec verdicts

- For each other spec of the class that has weights (imported or built-in), the item is evaluated with that
  spec's context against the same equipped gear.
- One green line is added only for a plain **upgrade**: "Also an upgrade for Marksmanship +4.0%". "Upgrade, but",
  sidegrades, downgrades and empty slots say nothing.
- No off-spec lines on items you're wearing or on "Not for you" items.
- Bag arrows stay current-spec only.
- In practice this means BM ↔ MM. Prot Paladin's other specs have no weights, so they're skipped.
- Option: `offspec` (on).

## Rank on worn items (added after the first in-game test)

Pawn's "Beast Mastery: your best" line on worn items, by our own score.

- **Shown on:** worn items only. One line for the current spec, plus one for each other spec with weights (and
  only when that spec can use the item).
- **Compared against:** the other worn ring (for rings) and the gear in bags 0-4. The bank isn't included.
- **Peers** must fit the same slot and be usable by the spec (armor type, main stat, spec list). For weapons, they
  must be the same kind (bow against bow). Trinkets and items with effects are never ranked and never count as
  peers, since their value is the effect.
- **Lines:**
  - "<Spec>: your best" (green).
  - "<Spec>: your second best" (green, rings only).
  - "<Spec>: bag has better (<name>)" (orange) otherwise.
- **Score:** the same as the verdict's (weights, gems, best-gem value for empty sockets). Set bonuses and unique
  limits aren't considered.
- **Bag list:** cached, and rebuilt on `BAG_UPDATE_DELAYED`.
- Option: `rank` (on).

## Gems

- `Scales.lua` lists the **16 Flawless rank-2 gems** (240888–240918, even IDs; Peridot = Haste, Amethyst =
  Mastery, Garnet = Crit, Lapis = Vers). IDs were verified via Wowhead tooltips and Method's list.
- Stats are read with `C_Item.GetItemStats("item:<id>")`. If that returns nothing for gems, the gem's tooltip
  lines starting with "+" are parsed instead. Results are cached once loaded.
- **Best gem** = the highest score under the active weights.
- **Empty socket line** on any gear tooltip: "Empty socket: best gem Quick Peridot (Haste, Mastery)", or "2 empty
  sockets: ...".
- **Worn items:** if a socketed gem scores more than 5% below the best one, "Gem: X is better for your spec" is
  added. Unloaded or unknown gems are never flagged.
- **Eversong Diamonds** (Unique-Equipped: Thalassian Diamond (1), 8 IDs) are main-stat gems, most with an effect.
  They're never ranked. When no worn item has one, empty-socket lines add "Or your one Eversong Diamond (sim
  which)".
- **Scoring change:** an empty socket is now worth the best gem's value. It used to be the average of the worn
  gems. The old average stays as the fallback while the gem list hasn't loaded.
- Option: `gemHints` (on).

## Enchants

- The enchantable slots in Midnight are head, shoulder, chest, feet, rings and main hand (verified: Wowhead news
  2026-02-26, Method). Cloak and bracers were removed, and legs take spellthreads or armor kits rather than
  enchants. The off-hand counts only when it's a weapon. Shields and off-hand frills don't.
- A worn item that should be enchanted and isn't gets the orange tooltip line "Not enchanted".
- Opening the character pane (a `CharacterFrame` OnShow hook, `Blizzard_UIPanels_Game`) prints e.g. "Gear Check:
  2 missing enchants, 1 empty socket." It's printed only when the text differs from the last one printed, so it
  doesn't nag every time the pane opens.
- No "best enchant" advice: enchant stats can't be read in game.
- Option: `enchantHints` (on).

## Tooltip layout

The first Gear line carries the "Gear:" label. Later lines (off-spec, gems, enchant) are indented under it. If
there's no verdict (a worn item), the first gem or enchant line gets the label.

## Structure

- `Gear/Scales.lua` (new): data only. Weights per spec, season tag, gem IDs, diamond IDs.
- `Gear/Advice.lua` (new, pure): ResolveWeights, WeightsHint, BestGem, GemLines, StatLabel, WornSlot, WearsGem,
  MissingEnchant, Audit/AuditText, OffspecLine.
- `Gear/Data.lua`: exports `Gear_StatsScore`, adds `Gear_LinkGemIDs` and `Gear_EnchantSlot`. `ctx.gemValue`
  overrides the average-gem value.
- `Gear/Items.lua`: `desc.gemIDs`, `GearItems_GemStats`, `GearItems_Gems`.
- `Gear/Gear.lua`: per-spec contexts, tooltip lines, hints, character pane hook, options, `/tomte gear weights`
  output.
- `Panel/Options.lua`: a button label may be a function.

## Testing

- Plain Lua: `lua Tomte/tests/test_gear.lua` covers every Advice function, the gem ID parsing, enchant slots, the
  best-gem socket value, and Scales sanity checks.
- In game: the checklist in the plan.

## Not doing

- Scales for specs the user doesn't play.
- Valuing the diamonds' effects or the "per unique gem color" bonuses.
- Best enchant suggestions.
- Off-spec bag arrows.
