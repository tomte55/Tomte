# Tomte: Alts

Date: 2026-10-05. Designed with the user; built autonomously after the design was agreed. Spec 2 of 2 (spec 1:
`2026-10-05-tomte-home-design.md`; Alts is a page on the new home screen).

## Goal

The user's main (Tomte, Hunter: Herbalism + Mining) gathers; alts become "support" crafters, aiming to cover every
profession across the account. Alts answers two questions:

1. **"Who can make this, and do we have what it takes?"** Search a recipe: who knows it (or could learn it), the
   materials needed with how many the account has and where, crafted materials worked out through other known
   recipes, and the crafts in order with who does each.
2. **"What do my characters look like?"** A roster of every character.

Decided with the user: no "what can I craft right now" view (Blizzard's window does it); materials count from
everywhere (all characters, banks, Warband bank, mail); known and learnable recipes are searchable; full crafting
chain with a setting for one step; item tooltips say who crafts an item; roster shows gold + total, item level + spec,
unspent knowledge, location + last played + rested, with a compact/detailed toggle.

## APIs (Blizzard UI source 12.1.0 build 69933 + warcraft.wiki.gg)

- Professions: `GetProfessions()` + `GetProfessionInfo(i)` → `name, icon, skillLevel, maxSkillLevel, _, _, skillLine`
  (base profession). The player's expansion skill line comes from Weekly's table (`ns.Weekly_ProfDef(expansion,
  base).child`, War Within lines for this account).
- Unspent knowledge: `C_ProfSpecs.SkillLineHasSpecialization(line)` and
  `C_ProfSpecs.GetCurrencyInfoForSkillLine(line).numAvailable`. Unverified with the window closed; also read on
  `TRADE_SKILL_CLOSE`, and the last reading is kept if a later one returns nothing.
- Recipes, only while the profession window is open: `TRADE_SKILL_LIST_UPDATE` (skip while
  `IsDataSourceChanging()`), gated on `IsTradeSkillReady()` and not `IsTradeSkillLinked/Guild/GuildMember`,
  `IsNPCCrafting`, `IsRuneforging`. `GetAllRecipeIDs()` (falls back to `GetFilteredRecipeIDs()`), filtered to the
  player's expansion with `IsRecipeInSkillLine(id, line)`. `GetRecipeInfo(id)` (`learned`, `name`, `icon`, skip
  dummy/recraft/salvage/gathering) and `GetRecipeSchematic(id, false)` (`outputItemID`, `quantityMin/Max`,
  `reagentSlotSchematics`). Kept slots: `required` and `reagentType == Basic` and not currency; a slot's `reagents`
  are its quality ranks (one entry per rank).
- `NEW_RECIPE_LEARNED(recipeID)` marks a stored recipe known without the window.
- Character: `UnitName/UnitClass/UnitRace/UnitLevel` (`PLAYER_LEVEL_UP`'s level, UnitLevel can lag),
  `C_SpecializationInfo.GetSpecialization/GetSpecializationInfo`, `GetAverageItemLevel()` (equipped), `GetMoney()`,
  `GetZoneText()`, `GetXPExhaustion()/UnitXPMax` (rested %, capped 150), `GetServerTime()`.
- Item counts: `Syndicator.API.GetInventoryInfoByItemID(itemID, false, false)` → `characters[{character, bags, bank,
  mail, ...}]`, `warband[1]`. Without Syndicator: `C_Item.GetItemCount(id, true, false, true[, true])` (this
  character + Warband bank).
- Tooltips: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`, `data.id` guarded with
  `issecretvalue`.

## Module

Key `alts`, name "Alts", category "General", on by default. `uses = Syndicator`. Home page entry "Alts" (first tile),
summary "N characters · total gold". Commands: `/tomte alts` (opens the page), `open`, `forget <name>`.
Options: "Crafted by" tooltips (on), Crafted materials: Full chain / One step.

## Data (`TomteDB.alts`)

```
chars[guid]  = { guid, name, realm, class, race, level, spec, ilvl, money, zone, seen, rested,
                 profs = { [base] = { name, icon, base, line, skill, max, unspent, known = { [recipeID] = true },
                                      scannedAt } } }
recipes[id]  = { v, name, icon, base, line, item, qMin, qMax, reagents = { { items = { rank itemIDs }, qty } } }
view, chain ("full" | "one"), crafts, roster ("compact" | "detailed"), sort, tooltip, selected
```

Recipes are shared per account (stored once even if two characters have the profession). Snapshots exist for every
character at any level. Refresh: entering the world, level, spec, item level, zone, gold, rest, skill lines, knowledge
currency, profession window; debounced 1 s; never in combat; logout stamps `seen` and gold.

## Plan (Data.lua, pure, unit-tested)

`Alts_Plan(recipeID, crafts, ctx)`: for each reagent slot, need = qty × crafts; use what the account has (quality
ranks summed, stock shared between slots is reserved once); a shortfall is crafted through a recipe that makes the
item (one somebody knows first), `ceil(short / yield)` crafts with yield = `quantityMin`, recursively up to
`maxDepth` (8 = full chain, 1 = one step), with a cycle guard. Output: materials (need, have, missing, crafted-by
recipe), steps in the order to do them (sub-crafts first, repeated recipes merged) with who knows each and who could
learn it, total missing, and how many steps nobody knows.

## Page (Tomte window, page view)

Tabs **Crafting** | **Characters** with a Full chain / One step button on the Crafting tab.

- **Crafting**: search box + results (known first: crafter name; learnable: grey; no one: red) on the left. Right:
  recipe name, profession and who knows it, a status line (everything's there / missing N / a recipe on the way
  isn't known), a − x1 + craft count, then **Materials (have / need)** rows (red missing with where the rest is,
  yellow "craft the rest", green with the top 3 places; hover = item tooltip + every place) and **Craft in order**
  ("1. Tomten crafts 2x Charged Alloy"). Without Syndicator a note says only this character + Warband are counted.
- **Characters**: current character first, sort by level / name / item level / gold / last played. Compact view: one
  line with sortable column headers (name in class color, level, spec, item level, short professions with unspent
  knowledge in a gold [n], gold, last played); details in the row tooltip. Detailed view: two lines (name, level, spec,
  item level, gold / full professions, zone, last played, rested). Footer: count and total gold.

## Tooltip

"Alts: Crafted by Tomten (Blacksmithing)" (up to 3 names + n) or, when nobody knows it, "Learnable by X
(Profession)" in grey.

## Testing

- Plain Lua (`tests/test_alts.lua`): crafters/learnable, search order, plans (in stock, full chain order, quality
  ranks summed, yields rounding, shortages, one step, shared stock, self-loop), roster sort, gold, ago, profession text.
- In game: see the checklist in the hand-over message.

## Fixes after the first in-game test (2026-10-05)

- Recipes are read for the expansion the profession window shows (`GetChildProfessionInfo().professionID`), not the
  player's expansion: Tomten (72) had Dragon Isles Blacksmithing open and every recipe was filtered out. Switching
  the window's expansion reads that one too; the profession remembers the last line it was read on (also used for
  unspent knowledge). `/tomte alts scan` reads the open window now and says why when it can't.
- Gold is no longer read at logout: `GetMoney()` already returns 0 during `PLAYER_LOGOUT`, which wiped the saved gold.

## Crafting list: filters and groups (2026-10-05)

- Filter bar under the search: character (all, or one character's recipes; with "Known + learnable" also what it
  could learn), profession, Known + learnable / Known only, and "Only what the account has materials for" (a plan
  per listed recipe, reagent counts shared within the pass).
- The list is grouped like the profession window: profession > expansion > Blizzard category, each foldable (saved).
  The expansion of the continent you're on comes first (its line name starts with the continent's name, with aliases
  for Broken Isles, Kul Tiras, Zandalar, Shadowlands) and other expansions start folded; then newest first. A search
  opens every group.
- Recipes now store `category` (`C_TradeSkillUI.GetCategoryInfo(info.categoryID).name`) and `lineName` (the window's
  child profession name); recipe version 2, so older recipes are read again the next time their window opens.
