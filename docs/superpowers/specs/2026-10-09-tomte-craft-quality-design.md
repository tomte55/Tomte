# Tomte: Choosing quality for crafts

Date: 2026-10-09. Scope picked by the user (option 3 of three, as two separate choices); the details below were
decided by Claude on the user's "build it like that" and are recorded here.

Builds on Alts (`2026-10-05-tomte-alts-design.md`), the Crafting list (`2026-10-06-tomte-crafting-list-design.md`)
and Profession gear (Crafting tab "Gear for", Profession gear tab, Next up).

## Goal

1. **Target quality** for a craft: what quality you mean to make. For gear and profession tools it gives one item
   level and an exact upgrade verdict instead of "590-606 by quality". For everything else it's a label that follows
   the craft (Crafting list, tracker, to-do).
2. **Reagent rank** per material: "use rank 3 Bismuth". Have / need, where it is, what's missing, prices, the to-do,
   the mailbox and the Auctionator shopping list then count and buy only that rank. Default stays "any rank".

The two are independent. Tomte doesn't work out which reagent ranks reach which quality: that depends on skill,
specialization and Concentration, and the game only tells it on the crafter with the profession window open. A later
step could read the game's predicted quality there as a check (not built).

## Data

- Recipes (Collect.lua, `RECIPE_VERSION` 4, so recipes are read again the next time a profession window opens):
  - `nq`: how many qualities the recipe has (`#GetRecipeInfo(id).qualityIDs`, nil when it has none or one).
  - `outQ`: gear and tools only, the output link at **every** quality, lowest first
    (`GetRecipeOutputItemData(id, {}, nil, qualityID)` per quality ID, as `out` already does for two). `out`
    (lowest, highest) stays as it is.
- Crafting list entries: `{ recipeID, crafts, added, quality?, ranks? }`. `quality` = 1..nq, `ranks` =
  `{ [slot key] = itemID }` where the slot key is the reagent slot's full rank list (`"a,b,c"`).
- Crafting tab: `db.quality` and `db.ranks` for the selected recipe, cleared when another recipe is picked.
- Setting `gearQuality` (Alts, default `"range"`): the quality crafted gear is compared at wherever no quality is
  picked for that craft: "Every quality (a range)" (today's behavior) or "Quality 1".."Quality 5" (a recipe with fewer
  qualities uses its highest).

## Plan (Data.lua `Alts_Plan`)

- `ctx.ranks` (optional): a material whose slot has a chosen rank is that one item (`items = { itemID }`), so it's
  counted, taken and bought on its own; "any rank" and a chosen rank of the same reagent are two materials.
- Each material keeps `slot` (the full rank list). A crafted material is still looked up by the full list (recipes
  are indexed by their base item, not each rank), and its craft step gets `quality` = the chosen rank's position.
- `Alts_StepOf` (ListData.lua) matches materials by `slot`, so the to-do still finds the crafter.

## Where it shows

- **Crafting tab**: a "Quality" dropdown under Add to list for recipes with more than one quality ("Quality: as
  set" uses the setting). The For line gives one item level at that quality. Material rows of a slot with ranks
  show the rank (icon) or "any rank"; click a row to choose. Add to list stores quality and ranks with the entry
  (adding a listed recipe again adds the crafts and takes the new choices). Opening a list card in the Crafting tab
  loads its choices.
- **Crafting list tab**: the card name has the quality icon; a small Quality dropdown on cards with more than one
  quality. Shopping rows of a slot with ranks: right-click chooses the rank for every craft on the list that uses
  it (left-click still searches Baganator).
- **Tracker and to-do**: the quality icon after the recipe name; crafted-material steps say their quality; items
  in the lines show their rank icon.
- **Profession gear tab, "Gear for" marks, Next up**: compared at `gearQuality` (a range when it's "Every quality").
  The Profession gear tab has the same choice as a dropdown at the top.
- Recipes read before version 4 have no `outQ`: they show the range until their profession window is opened again,
  and the For line says so.

## Testing

- Plain Lua (`tests/test_alts.lua`, `tests/test_list.lua`): a chosen rank narrows the material and keeps "any rank"
  separate, the producer is still found and its step gets the quality, the to-do finds the crafter with a chosen
  rank, list add stores and replaces choices, the item level at a quality (clamped), the upgrade verdict at one
  quality.
- In game: see the report.

## As built (2026-10-09)

Not yet tested in game.

- The Crafting tab's Quality is the first line of the detail; material rows of a ranked slot are clickable (rank
  menu). Opening a list card in the Crafting tab takes its quality and ranks (the amount starts at 1).
- The card's Quality dropdown sits at the end of the crafter line. The Profession gear tab's dropdown is labelled
  "Compare crafts at".
- A picked rank's material key keeps its slot (`"a,b,c=b"`), so it can't merge with an unranked slot of that item.
- If one middle quality's link doesn't answer, `out` is still stored and only `outQ` is dropped (range only).
- Known gaps: Gold & value's "sells for" still prices `recipe.item`, not the chosen quality's item (matters for
  consumables, where each quality is its own item). "Craft the rest: ..." on a material row doesn't show the quality.
