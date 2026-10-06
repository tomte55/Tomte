# Tomte: Alts round 2 (shopping list, recipe items, roster status, profession gaps, Warband gold)

Date: 2026-10-06. Picked by the user from the post-Home ideas. **Spec only, not built.** Builds on Alts
(`2026-10-05-tomte-alts-design.md`) plus this branch's Crafting list, Send to alt and Gold & value.

Already covered on this branch, so not repeated here: craft cost and profit (Gold & value), the craft queue and
tracker (Crafting list), mailing materials (Send to alt and the Crafting list mailbox rows), "Needs attention"
(Next up). Upgrades for alts and stat weights for every spec have their own spec
(`2026-10-06-tomte-spec-weights-alt-upgrades-design.md`).

Same rule as Home polish: nothing new is always on screen; tooltips and clicks first, new rows last.

## 1. Auctionator shopping list (Crafting tab and Crafting list tab)

- A **Shopping list** link on the right of the "Materials (have / need)" heading in the Crafting tab, and on the
  combined materials heading in the Crafting list tab. Shown only when Auctionator is loaded and something is
  missing.
- Click: creates or replaces an Auctionator shopping list named "Tomte: <recipe name>" (Crafting tab) or
  "Tomte: Crafting list" (list tab), with one exact search per missing material and the missing amount as the
  quantity. A chat line says "Auctionator list 'Tomte: Flask of ...' (3 items)". Opening the AH's Shopping tab is
  left to the user.
- Crafted materials that someone on the account can make are **not** on the list in "Full chain" mode (their own
  materials are, as the plan already works them out). In "One step" mode the crafted material itself is listed.
- Alts module `uses` gains `{ addon = "Auctionator", why = "shopping lists for missing materials" }`.

## 2. "Learnable by" on recipe items

The tooltip of a **recipe item** (a pattern, plan, formula, technique… sold by vendors, dropped or on the AH)
gets one line, same style as "Crafted by":

- "Alts: Known by Tomten" (grey) when a character knows the recipe it teaches.
- "Alts: Learnable by Tomten, Mira (Blacksmithing)" (green) when nobody knows it and someone has the profession.
  Up to 3 names, then "+n".
- No line when nobody has the profession, or for recipe items whose recipe isn't stored yet and can't be
  resolved (see To verify).

Item class `Enum.ItemClass.Recipe` is the gate, so ordinary items cost nothing. Uses the existing "Crafted by"
tooltip setting.

## 3. Roster: Concentration and Great Vault per character

Only in the **detailed** roster view and in the **row tooltip** of the compact view, so the compact line stays as
it is.

- Detailed view: a third line, shown only for max-level characters that Weekly tracks:
  "Vault 4/9 · Concentration: Blacksmithing full, Alchemy full in 6h".
- Row tooltip (both views): the same, one line per profession with Concentration.
- Data is Weekly's per character snapshot through `ns.Weekly_View(snapshot, now)` (vault slots) and
  `ns.Weekly_ConcNow` (prediction). Alts doesn't store either itself. Weekly off: the line is left out.
- A full Concentration is gold, otherwise white with the time until full.

## 4. Profession gap hints

In Home's "Your characters" the eleven profession icons already light up when someone has the profession and
show "n of 11". New: the **tooltip of an unlit icon** gives a suggestion:

- "Nobody has Inscription. Free profession slot: Tomtis (lvl 80), Mira (lvl 34)." Characters with fewer than two
  primary professions, max level first, then by level.
- "Nobody has Inscription, and every character has two professions." when there's no free slot.
- The same hint on the Characters tab's footer tooltip ("n of 11 professions"), nowhere else.

Pure helper `ns.Alts_FreeSlots(chars)` → characters with fewer than two primary professions, sorted as above.

## 5. Warband bank gold in the total

- Read `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` on entering the world and on `ACCOUNT_MONEY` (and when
  the bank closes), stored once per account in `TomteDB.alts.warbandMoney` with the time read.
- Totals become "Total 1.24M (Warband 300k)" in Home's "Your characters", the Characters tab footer and the Alts
  rail tooltip summary. The Warband part is left out when it's 0 or was never read.
- `ns.Alts_TotalGold(chars, warband)` takes it as an optional second argument (tests updated).

## Settings (Alts module)

No new settings: the shopping list link only shows with Auctionator, the recipe line follows "Crafted by", the
roster line follows the detailed/compact toggle.

## Testing

- Plain Lua: shopping list contents (full chain vs one step, only missing, amounts), learnable-by names and "+n",
  `Alts_FreeSlots`, `Alts_TotalGold` with and without Warband gold.
- In game: make a list for a recipe with a missing material and check it in Auctionator's Shopping tab; hover a
  known and an unknown recipe item at a vendor; detailed roster with a crafter whose Concentration is full; hover an
  unlit profession icon; deposit gold in the Warband bank and check the total.

## To verify

1. **Auctionator's shopping list API**: `Auctionator.API.v1.CreateShoppingList(callerID, listName, searchStrings)` and
   `ConvertToSearchString(callerID, { searchString, isExact, quantity })` in Auctionator's current source, and
   whether creating a list with an existing name replaces it or fails.
2. **Recipe item → recipe**: which call maps a recipe item to the recipe it teaches in 12.x (candidates: a
   `C_TradeSkillUI` lookup by item if one exists, or the item's spell via `C_Item.GetItemSpell` matched against
   stored recipes' spell IDs). Fallback: match the tooltip's "Teaches you how
   to …" name against stored recipe names. Check Blizzard's UI source and the wiki before picking.
3. **Warband money**: `C_Bank.FetchDepositedMoney` works away from the bank (if not, it's read while the bank is
   open and the stored value shown with its age), and the event name (`ACCOUNT_MONEY`).
