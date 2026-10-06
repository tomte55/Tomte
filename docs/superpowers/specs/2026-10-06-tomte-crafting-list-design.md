# Tomte: Crafting list, craft tracker and bank highlights

Date: 2026-10-06. Designed with the user; built the same day on the user's request (before the Send to alt mailbox
panel was tried in game; both use the same attach-and-send step, see `2026-10-06-tomte-send-to-alt-design.md`).
Choices are settings with defaults. The unknowns are listed under "To verify" at the end and get checked when we can
test in game and read the addons' code.

Builds on Alts (`2026-10-05-tomte-alts-design.md`: Crafting tab, `ns.Alts_Plan`, `ns.Alts_Have`), Send to alt and
Gold & value (prices).

## Goal

Plan crafts ahead and get walked through them across characters:

1. In the Crafting tab, after setting the amount, **add the craft to a crafting list**.
2. A small **on-screen tracker** for the tracked crafts: the materials and a to-do list for the character you're on
   ("Grab 10 Iron Ingot from Tomte's bank", "Mail 20 Mycobloom to Mira", "Craft 3 Flask: you have everything").
3. At the **mailbox**, the tracked crafts are listed and each one can be sent from there.
4. At the **bank**, the items a tracked craft needs from it are **highlighted**.

## 1. Crafting list (Crafting tab)

- An **Add to list** button next to the amount (- [n] +) adds `{ recipeID, crafts }`. Adding a recipe that's already
  listed adds to its amount.
- Saved account-wide: `TomteDB.alts.list = { { recipeID, crafts, added } }`.
- A **List** view in the Crafting tab (beside the recipe search): every tracked craft with its crafter, amount (editable)
  and a remove button. Under them, **all materials added up** across the list (one plan per craft, with shared
  materials counted once in the totals), each with have / need and where it is.
- The combined plan is worked out with `ns.Alts_Plan` per craft. Materials are claimed in list order, so two crafts
  can't both count the same 20 herbs.

## 2. Craft tracker (on screen)

A movable widget in the style of Almost Done's Top 5 tracker (lock/unlock, scale, reset position).

- One block per tracked craft: recipe name (quality color), "x3", the crafter in class color, and a progress bar
  (materials in place / needed).
- Under it, the **to-do for the character you're on now**, worked out from `ns.Alts_Have`'s per-character bags /
  bank / mail and the Warband bank (Syndicator reports them separately):

| Situation | Line |
|---|---|
| You are not the crafter and carry a material it needs | "Mail 20 Mycobloom to Mira" (or "Put 20 Mycobloom in the Warband bank" when it's warbound) |
| It's in your bank | "Grab 10 Iron Ingot from your bank" |
| It's in the Warband bank | "Take 10 Iron Ingot from the Warband bank" |
| It's on another character | "Tolvan has 10 Iron Ingot (bags)" (grey: nothing to do here) |
| It's in a mailbox | "Collect 20 Mycobloom from your mail" |
| Nobody has enough | "Buy or gather 15 more Bismuth (~450g)" (price from Gold & value) |
| A crafted material is needed first | "Tolvan: craft 10 Iron Ingot first" |
| You are the crafter and have everything in your bags | "Craft 3 Flask: you have everything" (green) |

- Done lines tick off and fade as bags, bank and mail change (`BAG_UPDATE_DELAYED`, bank and mail events,
  Syndicator updates).
- Click a line: a waypoint to a mailbox / bank / the crafter's profession table where that makes sense; a "Grab"
  line also highlights the item in the bank (part 4).
- Right-click a craft: remove it, or mark it done.
- Hidden in combat (setting) and while a cinematic is up.

### Crafts done

A craft comes off the list when it has been crafted that many times (setting: automatically / by hand). Automatic
needs the event that says a craft finished (see "To verify"). Right-click "Mark done" always works.

## 3. Mailbox

Tracked crafts go **at the top** of the "For your alts" panel (Send to alt), one row per craft that needs something
this character carries:

- "Flask of Tempered Swiftness x3 → Mira: 20 Mycobloom, 5 Bismuth" with **Attach** and then **Send** (as for the
  other groups; up to 12 attachments a mail).
- Only what that craft still needs is attached: **exact amounts**, so 20 out of a stack of 200, by splitting the
  stack (setting: exact amounts / whole stacks).
- The general "who uses this" groups stay below the tracked crafts.

## 4. Bank highlights

When the bank is open, the items a tracked craft still needs from **this character's bank** or the **Warband bank**
are marked:

- **In Baganator** (what the user plays with): a corner widget on the item icon, the way Gear Check puts its upgrade
  arrow on bag items (`Baganator.API.RegisterCornerWidget`). It can show how many to take ("10" on a stack of 200).
  Like Gear Check's arrow, Baganator only shows it once it's switched on in Baganator's settings (Icons), so the
  module's settings page says so.
- The same mark on **bag** items that should be mailed for a tracked craft.
- Clicking a "Grab" line in the tracker could also **set Baganator's search** to that item, so everything else dims.
- **Without Baganator**, optionally the same mark on Blizzard's own bank and bag buttons (setting, off by default).

## Settings (Alts module, "Crafting list" header)

| Setting | Choices | Default |
|---|---|---|
| Craft tracker | on / off | on |
| Show the tracker | While something is tracked / Only on the crafter | While something is tracked |
| Hide in combat | on / off | on |
| Tracker position, scale, lock | button / slider / checkbox | under the minimap, 1, locked |
| Crafts come off the list | Automatically when crafted / By hand | Automatically |
| Mail tracked crafts | Exact amounts (split stacks) / Whole stacks | Exact amounts |
| Mark items in Baganator | on / off | on |
| Mark items on Blizzard's bags and bank | on / off | off |
| Price missing materials | on / off (needs Gold & value) | on |

## Testing

- Plain Lua: combining plans, claiming materials in list order, the to-do rules (each row of the table above for a
  given character and its locations), amounts per mail, "done" counting.
- In game: add two crafts that share a material; check the tracker on the gatherer, on a bank alt and on the crafter;
  send one craft from the mailbox with exact amounts; open the bank with Baganator and check the marks.

## To verify (later, when we can)

1. **Crafting finished event**: which event says a craft completed and for which recipe, in 12.x
   (`TRADE_SKILL_ITEM_CRAFTED_RESULT` or similar, and/or `UNIT_SPELLCAST_SUCCEEDED` with the recipe's spell), in
   Blizzard's UI source and in game.
2. **Splitting a stack into a mail**: `C_Container.SplitContainerItem(bag, slot, n)` then
   `ClickSendMailItemButton(i)` in one click, from our button (same open question as the rest of the mail code).
3. **Baganator corner widget in the bank view**: that the widget Gear Check uses also draws on Baganator's bank and
   Warband bank buttons, and whether it can show a number.
4. **Baganator search from an addon**: whether Baganator's API lets an addon set its search text (read Baganator's
   source); if not, the corner widget is the only highlight.
5. **Syndicator's split counts**: `GetInventoryInfoByItemID` per character `bags` / `bank` / `mail` (Alts already reads
   them, summed) and the Warband bank, and how soon they update after a mail or a bank move.
6. **Blizzard bank buttons** (only if the no-Baganator option is wanted): how to find the item buttons of the 12.x
   bank frame and its tabs to overlay a mark.

## As built (2026-10-06)

Not yet tested in game.

- Files: `Modules/Alts/ListData.lua` (pure, `tests/test_list.lua`), `List.lua` (where items are, to-do cache, tracker,
  craft events, Baganator), `ListTab.lua` (the Alts page's new "Crafting list" tab), rows at the top of Send.lua's
  mailbox panel, and an "Add to list" button under the amount in the Crafting tab.
- Where items are: Syndicator's `GetInventoryInfoByItemID` per character `bags` / `bank` / `mail` and `warband[1]`
  (checked in Syndicator's source); without Syndicator, this character and the Warband bank from `C_Item.GetItemCount`.
  Crafts take from one pool in list order: the crafter's bags, bank, mail, the Warband bank, you, then everyone else.
- Crafts done: `TRADE_SKILL_CRAFT_BEGIN(recipeSpellID)` marks the craft, each `TRADE_SKILL_ITEM_CRAFTED_RESULT`
  (not `bonusCraft`) counts one (both in the 12.1 API docs; recipe IDs are the recipes' spell IDs). Still to see in game
  that it's one result per craft.
- Mail: `C_Container.SplitContainerItem` (12.1 API docs: not restricted) then `ClickSendMailItemButton(i)`; still
  to try in game.
- Baganator: a corner widget "Tomte Crafting list" (top right, enabled by default through its default position,
  per Baganator's source) with the count to move, on bag and bank buttons. Clicking a Grab / Take / Mail line runs
  Baganator's `search` slash command (there's no search API; it opens the bags too, and an open bank view
  highlights the matches).
- Not built: marks on Blizzard's own bags and bank (the "without Baganator" option), since the user plays with
  Baganator; it stays in "To verify" (6).
- Settings are as in the table, except "Mark items on Blizzard's bags and bank" (not built). Commands:
  `/tomte alts list`, `/tomte alts tracker`.
