# Polish pass D: economy modules

2026-10-19. Part D of the polish pass (see `2026-10-19-tomte-polish-overview.md`). Covers Session recap, Gold & value,
Material uses, Alts (Send to alt / Deposit for alts), Vendor Helper and Durability (Upkeep), Weekly board, plus a check
of Gear Check and Next up. Each finding was checked in the code first; the ones that turned out wrong are at the end.
Plan A goes first (shared combat line `ns.Print_Combat`, modules-off check for commands); nothing here depends on it,
but Send.lua's `Busy()` may already call `ns.Print_Combat` when this plan starts: keep whatever is there.

## What the player notices

- **Session recap / Gold & value**: buying from a vendor no longer inflates "loot worth" and no longer lists a bought
  epic as notable loot. Items that arrive in the bags while a vendor, the mailbox, the auction house or a trade
  window is open aren't loot. Quest rewards, loot windows, bonus rolls and gathering still count. Crafted items
  ("You create") never counted and still don't.
- **Material uses**: Mythic Keystones and other context tokens no longer say "Not used in crafting". Neither do items
  newer than the generated table: the tooltip only says "Not used" when Tomte's list can know the item. The list is
  rebuilt from the 12.1.5 client data. The setting's tooltip no longer promises "safe to sell".
- **Alts, Deposit for alts**: the chat line says what really went into the Warband bank ("put 3 of 5 stacks ...; the
  rest stayed: the Warband bank is full"), and refuses up front with a reason when no Warband bank tab is bought or
  the Warband bank can't be used right now.
- **Gold & value**: turning the module off while the bank is open (and on again later) no longer saves that
  character's bank as worth 0. "Price loot" gets a tooltip.
- **Session recap settings**: "Sessions per character" shows only when keeping by number of sessions, "Days kept"
  only when keeping by days.
- **Money text**: the mailbox's postage line and Vendor Helper's toast use Tomte's money style ("30c", "12g") like
  the rest of the addon, instead of Blizzard's coin strings.
- **Durability**: "When an item breaks" gets a tooltip.
- **Weekly board**: while farming, currency changes and closing a loot window only re-read crests and profession
  knowledge/Concentration, not the vault, quest log, learned weeklies and saved instances.

## Decisions

### What counts as session loot (finding 1)

Loot messages split into two kinds by the global string they match:

| Kind | Globals | Counts |
| --- | --- | --- |
| looted | `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_BONUS_ROLL_SELF`, `..._MULTIPLE` | always |
| pushed | `LOOT_ITEM_PUSHED_SELF`, `LOOT_ITEM_PUSHED_SELF_MULTIPLE` | unless a vendor, mailbox, auction house or trade is open |

- Vendor (purchases, buyback), mail (AH purchases, alts' mail), auction (commodity purchases land in the bags) and
  trade are all "you paid for it or it was already yours". The trade window is added to the tracked contexts
  (`Enum.PlayerInteractionType.TradePartner`, checked on warcraft.wiki.gg); it doesn't change gold attribution,
  `Recap_MoneySource` ignores it.
- Crafting results use `LOOT_ITEM_CREATED_SELF`, which was never in the list: unchanged, not counted.
- The decision is pure: `ns.Recap_LootMessage(text, patterns)` returns link, count and kind; `ns.Recap_IsLoot(kind,
  ctx)` decides. Both in `Modules/Recap/Data.lua`, tested in `tests/test_recap.lua`.
- Past sessions keep what they recorded; nothing is recomputed.
- Edge: a client language where the looted and pushed strings are identical would match "looted" first and still
  count purchases. None of the shipped locales is known to do this; not handled.

### "Not used in crafting" only when we know (finding 2)

- A material is a trade good (`Enum.ItemClass.Tradegoods`) or a plain reagent (`Enum.ItemClass.Reagent` with
  subclass `Enum.ItemReagentSubclass.Reagent`, 0). Keystone (1) and ContextToken (2) are not (wiki ItemType page).
- `tools/materials.py` also reads the `Item` table and writes `ns.MATERIALS_LAST_ITEM`: the highest item ID of class
  5 or 7 in the build it was made from. An item with a higher ID is newer than the table: no "Not used" line. Item IDs
  are handed out in rising order, so this is a good proxy; an older ID added late would still be judged by the table.
- Pure rule `ns.Materials_Known(itemID, lastKnown)` in `Modules/Materials/Data.lua`; `Materials_Lines` takes
  `known` and only says "Not used in crafting" for `isMaterial and known`. No `lastKnown` (an old Generated.lua) means
  never "Not used".
- Regenerate `Modules/Materials/Generated.lua` for build 12.1.5.70391 (generated files are never hand-edited).
- `/tomte materials why` also says whether the item is newer than the table.

### Deposit for alts reports what moved (finding 3)

- Before moving: if `C_Bank.CanUseBank(Enum.BankType.Account)` is false ("can't be used right now") or
  `C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Account)` is 0 ("no tab bought"), print why and move nothing.
  A full Warband bank is not checked up front: stacks can still merge into partial ones.
- After moving: 1 s later look at each tried bag slot. Empty or a different item: moved. Fewer in the stack: moved
  (part of it merged). Still locked: on its way, look again (up to 3 looks), then count it as moved. Same item and
  count: stayed. If anything stayed, the reason is "full" when the Warband tabs (bags 12-16) have no free slot, else
  "the game didn't move them".
- Pure: `ns.Alts_DepositOutcome(tried, now)` and `ns.Alts_DepositText(tried, moved, reason)` in
  `Modules/Alts/SendData.lua`, tested in `tests/test_send.lua`.
- `Modules/Alts/Send.lua` is 955 lines (CLAUDE.md: split past about 900 before adding). First a pure move of its
  Warband bank section into a new `Modules/Alts/Deposit.lua` (its own commit), then the behavior change there.

### Weekly refresh cost (finding 7)

- Two refresh kinds: **full** (everything, as now) and **light** (`ReadCurrencies` and `ReadProfs`: crests, profession
  knowledge flags from looted treasures, Concentration). `CURRENCY_DISPLAY_UPDATE` and `LOOT_CLOSED` ask for light;
  every other event, the board's buttons, the popup and the reset timer ask for full. A burst that asks for both gets
  full. The debounce (3 s) is unchanged.
- Light needs an existing snapshot with its expansion; without one it reads in full.
- Pure merge rule `ns.Weekly_MergeRefresh(pending, kind)` in `Modules/Weekly/Model.lua` (880 lines; stays under 900),
  anything but "light" counts as full so a stray argument (an event frame, a timer) is never a light read.

### Smaller fixes

- **Value toggle (finding 4)**: `toggle(false)` sets `bankOpen = false` and cancels `worthTimer`.
- **Recap keep-by sliders (finding 5)**: `shown()` on both sliders; "Keep by" gets `onChange = ns.Panel_Refresh` so
  the page redraws at once (the options page only rebuilds by itself for parent switches).
- **Money (finding 6)**: `ns.Price` for postage (`Send.lua:637`) and Vendor Helper's `Money` (`Vendor.lua:28`). `ns.Price`
  shows the biggest unit only ("12g", "45s", "80c"); the toast loses the silver of a gold-sized repair bill, which is
  fine for a summary. `ns.Coins` needs a coin-icon table, which only the cinematic scenes carry. No other
  `GetCoinTextureString`, `GetMoneyString` or hand-made `%dg` in this plan's modules
  (`Modules/Flight/Flight.lua:113` has one: Plan E's area).
- **Tooltips (finding 8)**: Value "Price loot", Durability "When an item breaks", player wording (texts in the plan).

## Checked, not changed

- **Alts List.lua:385 `SetColorTexture(1, 1, 1, 0.08)` (finding 9)**: `tests/test_theme.lua` deliberately allows pure
  white or black shading with an alpha (`NumericColor`), so it didn't "miss" it. The same white wash is used in
  about a dozen places (Weekly BoardPage track at the same 0.08, ListTab, Raids, Recap Scene and SessionsPage), and
  every theme is dark. Turning shading into a theme role would be a theme-wide change for Plan A, not a one-line fix.
- **Saved keys without defaults**: Value, Upkeep (both files), Materials, Next up and Recap read only keys that have
  defaults.
- **toggle(false) leaks**: Recap (Deactivate unwatches, stops tracking, clears toasts), Vendor Helper, Durability,
  Materials and Weekly Collect undo what they start. Weekly's pending debounce runs once after Stop and returns
  because `db` is nil. Only Value leaked (finding 4).
- **Gear Check, Next up**: nothing found in this pass's scope.

## Testing

- Unit tests: `test_recap.lua` (LootMessage, IsLoot), `test_materials.lua` (Known, Lines with known),
  `test_send.lua` (DepositOutcome, DepositText), `test_weekly.lua` (MergeRefresh).
- In game (the user, after `/reload`): buy 5 of a vendor item and check `/tomte recap`; hover a keystone and an old
  unused trade good; Deposit for alts at the bank; Value off/on at the bank; Recap keep-by switch; postage and vendor
  toast; Weekly board while looting. Exact steps in the plan.
