# Tomte: Material uses

Date: 2026-10-13. Status: design approved in chat, spec waiting for review.

## Goal

Hovering a crafting material says what it's used for, so the player knows whether to bank it or sell it: first
what their own characters craft with it, then which other professions use it (worth keeping for a profession they
may pick up later), or that nothing uses it at all (safe to sell). The tooltip stays minimal: at most two lines,
details only while Shift is held.

## Decisions (from the talk)

| Question | Decision |
|---|---|
| Whose recipes | Both: your characters' known recipes (from Alts) and every profession in the game (generated table) |
| Clutter | At most two lines; Shift shows the details |
| Which items | Anything a recipe uses, plus trade goods and reagents that nothing uses |
| No use at all | A faint "Not used in crafting" line on trade goods and reagents |
| Module | Its own module, so it can be turned off without touching Alts |

## Tooltip

```
Mycobloom
...
Used by Aldric: Alchemy (3)          accent: your characters' known recipes
Also: Leatherworking                 textFaint: other professions that use it
```

- **Line 1, "Used by"**: characters who know a recipe that uses the item (any quality rank of it), from the recipes
  Alts has read. One character: `Used by Aldric: Alchemy (3)` (profession, number of known recipes). Several:
  `Used by Aldric, Mira +1` (sorted by recipe count, then name; two names at most, `+n` for the rest). No line when
  no character knows such a recipe, or Alts is off.
- **Line 2, "Also"**: the professions in the generated table that use the item, minus the professions already on
  line 1, in alphabetical order. Shown even when you have that profession but haven't learned (or haven't scanned)
  the recipes, because the item is still useful to it.
- **Nothing uses it**: when neither source knows a use and the item is a trade good or reagent
  (`Enum.ItemClass.Tradegoods` / `Enum.ItemClass.Reagent`), one faint line: `Not used in crafting`.
- **Shift held** (the tooltip refreshes on modifier change, like Blizzard's compare tooltips): line 1 becomes one line
  per known recipe, up to 5, `Sturdy Ingot - Aldric` (`+n more` after that), and line 2 shows counts:
  `Also: Leatherworking (1)`. Line 2 and the "not used" line are unchanged in meaning.
- Lines go below Alts' "Crafted by" lines. No lines on items the table and Alts don't know, unless they're trade goods
  or reagents. Nothing is shown when the tooltip's item ID is a secret value (`ns.IsSecret`).
- Profession names come from the game (`C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)`, to be checked on
  warcraft.wiki.gg), never English strings, so friends on other client languages read their own.

## Data

### Generated table: `Modules/Materials/Generated.lua`

Made by a new `tools/materials.py <build> [csv-dir]` (stdlib only, uses `tools/wago.py` like `events.py`):

```lua
ns.MATERIALS_USES = {
	[210796] = { [171] = 22, [165] = 1 }, -- [itemID] = { [profession skill line] = recipe count }
	...
}
```

- Old recipes: `SpellReagents` (recipe spell -> reagent items).
- Dragonflight-style recipes: `CraftingReagentQuality` (item -> crafting category) -> `MCRSlotXMCRCategory` (category ->
  reagent slot) -> `ModifiedCraftingSpellSlot` (slot -> recipe spell).
- Recipe spell -> profession: `SkillLineAbility` (spell -> skill line) and `SkillLine.ParentSkillLineID`, so every
  expansion's tier ("Khaz Algar Alchemy") folds into its profession (Alchemy, 171).
- Kept: the crafting professions, Cooking and Mining's smelting. Dropped: spells that aren't recipes (gathering skill
  lines' own abilities, class and other skill lines). Milling and prospecting (Inscription and Jewelcrafting salvage)
  count when the tables carry them; the tool's output is checked against a few known items (Mycobloom, Copper Bar,
  Bismuth) before committing.
- Probe on build 12.1.0.69933: about 2,150 items from `SpellReagents` and 1,050 quality-ranked items from the slot
  tables, about 100 KB of Lua.
- All expansions count: an old material used by old recipes is still a use (leveling a profession goes through them).

### Your characters: asked through Alts

Alts already stores every scanned recipe with its reagents (`TomteDB.alts.recipes[id].reagents`, quality ranks per
slot) and each character's known recipes (`chars[guid].profs[base].known`). The new module never reads Alts' db; Alts
answers through one new function:

- `ns.Alts_UsedBy(itemID)` -> `{ { name, class, base, profName, recipes = { { id, name }, ... } }, ... }`, one entry
  per character and profession, or an empty table when Alts is off.
- The pure part goes in `Modules/Alts/PlanData.lua`: `ns.Alts_ReagentIndex(recipes)` -> `[itemID] = { recipeID, ... }`
  (every quality rank of a slot points at the recipe) and `ns.Alts_UsedBy` building on it with `ns.Alts_Crafters`.
  Alts caches the index the way it caches `producers` for "Crafted by", and drops it when a recipe scan stores new
  recipes.

## Module

- Key `materials`, name "Material uses", category General (next to Alts and Gold & value), `enabledByDefault = true`
  (two lines on materials only, nothing invasive).
- Folder `Modules/Materials/`, TOC order after `Modules/Alts/`: `Generated.lua`, `Data.lua` (pure),
  `Materials.lua` (main: the tooltip hook, settings).
- `Data.lua` (pure, `tests/test_materials.lua`): given the generated entry, Alts' answer, the item class and Shift,
  return the tooltip lines as `{ text, role }`. All wording, sorting, `+n`, the "Also" subtraction and the "not used"
  rule live here; profession names are passed in as a lookup so the file needs no WoW API.
- `Materials.lua`: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)` once in `init`; the
  handler does nothing while `module.active` is false (hooks can't be undone).
- Settings: `tooltip` (checkbox, "Material uses on item tooltips", default on) and `notUsed` (checkbox, "Say when
  nothing uses a material", default on). Defaults in `module.defaults`.
- `uses`: Alts, for the "Used by" line (the settings page says the line needs Alts and opened profession windows).
- Command: `/tomte materials why <item link or ID>` prints both sources' answers for the item, for checking the
  table against the game.

## Limits

- "Used by" only knows a character's recipes after their profession window has been opened once (Alts reads recipes
  then). Until then that profession appears on the "Also" line.
- The generated table is as fresh as the build it was made from; a new patch's recipes need `tools/materials.py` run
  again (same as the Holidays and Travel tables).
- Optional reagents (embellishments, finishing reagents) count only through the slot tables; Alts' side reads
  required basic reagents only, so line 1 may miss a recipe that line 2's profession covers.

## Testing

- `tests/test_materials.lua`: one character, several characters (sorting, `+n`), "Also" minus line-1 professions,
  "not used" only for trade goods and reagents and only with the setting on, Shift details (cap at 5, `+n more`).
- `tests/test_alts*.lua`: a case for `ns.Alts_ReagentIndex` and `ns.Alts_UsedBy` (quality ranks, unknown recipes left
  out).
- In game: hover Mycobloom (or a material your profession uses) with and without Shift; a grey vendor trade good
  for "Not used in crafting"; turn the module off and on with no `/reload`.
