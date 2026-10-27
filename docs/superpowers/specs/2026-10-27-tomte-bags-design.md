# Bags: Tomte's own bags, bank, categories and other characters' items

Date: 2026-10-27. New module: `Modules/Bags` (key `bags`). Mockups from the design talk are throwaway (scratchpad);
the reference for the look is the user's screenshot of their Baganator setup at the Warband bank, described under
"The windows" below.

## Why

The user's end goal is to play with Tomte as the only addon. Bags are the next step: one module replaces
**Baganator**, **Syndicator**, **EnhanceQoLBags**, and **CanIMogIt's** bag icons (CanIMogIt draws into Blizzard's
or Baganator's bags, so a Tomte bag has to bring its own transmog icon). It also helps modules that today depend on
Syndicator: Alts counts crafting materials on other characters only through Syndicator, and Gear Check's arrows
live in Baganator through its plugin API.

What the user loves in Baganator and wants kept: categories instead of one big bag (with one big bag as a setting
for players who prefer it), upgrade arrows and transmog icons on items, custom categories with rules (their
example: an "Upgrades" category that pulls every upgrade to the top), the bank and other characters visible, and
search with saved searches.

## Hard constraint: nothing taken from Baganator or Syndicator

Both are **All Rights Reserved** (plusmouse, 2023-2026). Tomte is GPL-3.0 and public. So:

- No code, no curated lists (their default category list, their search keywords), no layouts copied, and **their
  source is not read as a reference** while building. Their folders in `Interface\AddOns` are off limits for this
  work.
- What this design describes comes from the user's own experience of using Baganator, from the game's item data
  (item classes, subclasses, bind types, expansions) and from Blizzard's UI source (Gethe/wow-ui-source), which is
  the reference for item buttons, bank tabs and container APIs.
- Category names that are the game's own item classes ("Consumable", "Reagent", "Recipe") are facts and fine.
- README Credits does not credit Baganator (nothing is taken); it may say Tomte Bags covers what the user used it for.

## Goals

1. A bag window and a bank window in Tomte's look (theme roles, fonts) that replace Blizzard's bags while the
   module is on, with the same density as the user's Baganator setup.
2. Items sorted into categories by default; a "one bag" view as a setting.
3. Item overlays: item level, stack count, upgrade arrow (Gear Check), transmog not collected, junk, new.
4. One search language for the search box and for category rules. Saved searches; any search can become a
   category in one click.
5. Custom categories with an editor page in the Tomte window, a priority per category, sections and dividers,
   sharing (export/import).
6. Tomte's own record of every character's items, account-wide: tooltip counts, search across characters, read-only
   browsing of other characters, and Alts and Value reading from it instead of Syndicator.

## Non-goals

- Editing categories right in the bag (pencil on a header, drag headers in the bag). Wanted later, not now; the
  data model must not make it hard.
- A Baganator skin, or keeping Baganator support as the way forward. Existing integrations stay for players who
  keep Baganator (see "Living next to Baganator").
- Guild bank *window*. The guild bank is only read for counts (step 4), Blizzard's guild bank frame stays.
- Auto-selling junk: that's Upkeep's Vendor Helper; the bag only marks junk (and its value).

## Anti-goals (would make it a failure even if it works)

- Clicking an item in combat does nothing or errors (taint, secure button rebuilt in combat).
- Blizzard's bags broken or still hidden after the module is turned off mid-session.
- Opening the bags stutters (whole rebuild on every `BAG_UPDATE`), or the bags look sparse and roomy instead of
  dense.
- Anything that reads as a copy of Baganator.

## Steps

Each step is usable on its own and gets its own in-game check and commit(s). The user agreed on this order.

1. **Bags**: the bag window, categories view and one-bag view, overlays, search (no saved searches yet), sort.
   The default categories are fixed in this step (not editable yet).
2. **Bank**: character bank and Warband bank windows, deposit, gold, tabs. After this step Baganator can be
   turned off.
3. **Categories editor**: custom categories, priority, sections, saved searches and "Save as category", sharing.
4. **Other characters**: the "Item counts" module (the record, tooltip counts), search across characters and
   read-only browsing in Bags, Alts and Value switched over. After this step Syndicator can be turned off.

CanIMogIt can go after step 1 (the transmog icon is in step 1).

**Testing step 1** (user's decision): the user turns Baganator off while testing step 1 and uses Blizzard's bank
until step 2. No side-by-side mode with Baganator is built. (Building steps 1 and 2 before the first in-game check
is also acceptable to the user.)

## The windows

Described from the user's screenshot; this is the target look.

**Two separate windows**, bag and bank, each placed by the user (Edit Mode via `ns.EditMode_Register`, or dragged;
builder's choice which, positions remembered). In the screenshot the bank is on the left of the screen and the bags
bottom right; they don't snap together.

**Density.** Small categories sit side by side on one line and wrap like text (Potion, Food, Consumable, Quest on
one line). Each category is a small muted label above its icons: no boxes, no big headers, no spacing beyond a
small gap. Bigger groups are **sections** with a fold arrow and a heading (▼ Equipment holding Weapon and Armor,
▼ Crafting holding Reagent and Recipe); a folded section stays folded (remembered). Thin rules between top-level
blocks. Window width is a setting (icons per row); icon size a setting.

**Top bar** (both windows): title ("Bags", "Character Bank", "Warband Bank"), a search box with the saved-search
button, and small buttons: sort, settings (opens the module's page in the Tomte window), close. The bag window also
has a bag-slots button (shows the equipped bags to swap them) and a character switcher (step 4).

**Bottom bar.** Bag window: free slots, gold. Bank window: Character / Warband switch, "Deposit warbound items"
with an "Include reagents" check, gold Withdraw / Deposit for the Warband bank, the Warband gold amount. Bank tabs
as a column of icons along the bank window's side (click to show only that tab, click again for all; buying and
the tab settings reachable from there).

**Empty slots** are a category of their own, with a count, split by kind (normal, reagent bag).

**Fading at the Warband bank** (user agreed): while the Warband bank is open, items in the bags that can't go
into it (soulbound and the like) are faded. A setting, on by default.

**One-bag view** (setting): all items in one grid, no categories, sorted by the sort rules; empty slots at the end.

## Items and overlays

On each item: stack count; item level on gear; the upgrade arrow (Gear Check's verdicts, the same arrows as its
Baganator plugin today, including the alt and maybe arrows); a transmog icon when the appearance isn't collected
(and can be collected by someone on the account; builder decides whether to tell "this character" from "another
class"); junk mark; a "new" glow for items new this session (game's new-item flags). Quality border by quality
color. Each overlay can be turned off in settings.

Tomte already reads transmog collection state in three places (`Modules/Loot/Read.lua`,
`Modules/WorldQuests/Scan.lua`, `Modules/Achievements/Rewards.lua`). The bag must not add a fourth copy: move the
"is this appearance collected / collectable" check into a shared helper (Core or a shared Gear piece) first, as a
pure move, and use it everywhere.

Gear Check's arrows: today they reach Baganator through `Modules/Gear/Baganator.lua`. The decision logic already
lives in Gear (`ns.Gear_EvaluateLink`); the Tomte bag asks Gear through an `ns.Gear_*` function (or
`ns.HomeCall`-style safe call) so Bags works with Gear Check off.

Tooltips on items are the game's normal item tooltips (with whatever other Tomte modules add).

## Search language (shared by the search box and category rules)

Tomte's own design, a pure file with unit tests. Requirements:

- Plain words match item names (and, builder's call, item type/subtype names), case-insensitive, any client
  language (match through localized item data, not English strings).
- Keywords for item properties, written so they can't be confused with words in item names (a prefix or marker,
  builder's choice): at least gear, weapon, armor, consumable, reagent, recipe, quest, junk, upgrade, transmog
  (not collected), soulbound / warbound / BoE, quality names, expansion, equipment set, new, housing (decor),
  toy, pet, mount, key, bag.
- Comparisons for numbers: item level, count, vendor price (e.g. item level over 600).
- and, or, not, parentheses.
- An unparseable search shows that it's wrong (muted note under the box), never an error.
- A short in-game help list of the keywords (the "?" next to the box).

The user's Upgrades category, written in it, must be a short readable rule ("gear and upgrade" in spirit).

## Categories

**Default set** (step 1, fixed; editable from step 3). Tomte's own list from the game's item classes plus Tomte's
own knowledge. In the user's screenshots these groups are in use and the default set must cover them: Recent/new
(automatic), Hearthstone, Keystone, Potion, Food, Consumable, Quest, Equipment section (Equipment sets automatic,
Weapon, Armor), Crafting section (Reagent, Tradeskill, Profession equipment, Recipe), Housing (decor), Gem, Item
enhancement, Bag, Key, Miscellaneous, Battle pets, Toy, Other, Junk, Empty. The exact names, order and rules are the
builder's, matched against item classes, not copied from anywhere.

**A category is**: a name, a rule (search language), a priority, where it shows (bags, character bank, Warband
bank, other characters), hidden or not, and a hand-kept list of item IDs that always belong to it. Automatic
categories (new items, equipment sets, empty) have no rule; their contents come from the game.

**Which category gets an item.** Each item lands in exactly one category. Highest priority wins; among equal
priorities, the one higher in the list wins (user's decision). Hand-kept item IDs beat rules. Items that match
nothing go to "Other". Pure logic, unit-tested.

**Order and structure**: an ordered list with sections (folders holding categories) and dividers.

## The categories page (step 3)

A page in the Tomte window (the user chose this over editing in the bag). Left: the ordered list with drag
handles, sections and dividers, each category with a live count of matching items in the current bags. Right: the
selected category: name, rule (with live match preview: the matching item icons while typing), priority, where it
shows, hidden, the always-include item list (drop an item or paste IDs). Buttons to add a category, a section, a
divider; delete; share. Sharing is export/import text through `ns.Dialog_Show` (one category or all).

This is a custom page, not an `options` schema (the schema can't draw a draggable list). Module settings
(views, sizes, overlays, tooltips) stay in the normal `options` schema.

**Saved searches**: the search box's star saves the current search with a name; the saved list opens from the
same button; each saved search has "Save as category". A saved search and a category share the rule format.

## Other characters (step 4)

**The record is its own module, not part of Bags** (user's decision). Bags is off by default and must do nothing
while off, but Alts and Value need other characters' counts for everyone. So a separate small module, "Item counts"
(own folder and key, builder names them; its own `TomteDB` table), **on by default**, holds the record and the
tooltip counts and exposes it through `ns.<Prefix>_*` functions. Bags (the windows) reads from it for search across
characters and browsing; with Item counts off, those parts of Bags are hidden. Alts and Value read from it whatever
the state of Bags.

Account-wide record, per character keyed by GUID: bags, bank, equipped gear, mail, plus the Warband bank stored
once per account; the guild bank per guild when its window is opened (user agreed mail and the guild bank count).
Auction house listings: builder's call. Item counts and item links (enough for tooltips and read-only icons),
recorded when the game says they changed and on logout, budgeted like `ns.Journal_Scan` so login doesn't stutter.

- **Tooltip counts**: a short line per character with where ("Aldric: 12 bank, Kesha: 3") plus the Warband bank,
  class-colored names (`UI.ClassColored`). A setting, on by default. Also on the current character's other
  places (bank while not at the bank).
- **Search across characters**: the search box can switch to all characters and lists where matching items are.
- **Browsing**: the character switcher shows another character's bags or bank read-only (no clicks act on them).
- **Alts and Value** read from this record through the Item counts module's functions instead of Syndicator, and
  their "without Syndicator" notes go (with Item counts turned off they fall back to what they read today). Syndicator stays supported until then and is no longer needed after.
- Forgetting a character (deleted, moved) from the record: a button or command.

## Living next to Baganator and other bag addons

- `conflicts` lists Baganator (and other full bag replacements the builder knows of: Bagnon, ArkInventory,
  AdiBags, BetterBags, EnhanceQoLBags). While one is loaded, Tomte Bags doesn't start and its settings page says so.
- `Modules/Gear/Baganator.lua` and `Modules/Gear/Bags.lua` (Blizzard bag quality border and sort direction) stay
  as they are; they apply when Tomte Bags is off. With Tomte Bags on, Bags.lua's border is not drawn on Blizzard's
  (hidden) bags.
- `Modules/Value/Backpack.lua` (tracked items on Blizzard's bag currency bar) only works on Blizzard's bags.
  With Tomte Bags on, the tracked items and currencies show on the bag window's bottom bar instead (step 1).

## Module facts

- Key `bags`, name "Bags", category `gear` (gear & loot), icon a bag file ID checked to exist, a one-sentence
  summary.
- **Off by default** (`enabledByDefault = false`): it replaces a core part of the UI, so friends choose it.
  *(Claude's call.)*
- Turning it on mid-session takes over the bag keys and windows; turning it off gives Blizzard's back fully (no
  leftover hidden frames, hooks inert).
- Key bindings for opening the bags and the bank view if the builder finds the normal bag keys aren't enough.
- Commands, at least: `/tomte bags why <item link>` (which category got it and why, its rule and priority).
- Saved shape (in `TomteDB.bags`, defaults commented): view and size settings, overlay switches, folded
  sections, categories (list, sections, dividers, rules, priorities, item IDs), saved searches. The category list
  is exportable. The character record lives in the Item counts module's own table and is `noShare`.
- **Sort button** *(Claude's call, after the builder check)*: calls the game's own sort (`C_Container.SortBags`
  and the bank equivalents, with Gear Check's existing left-to-right / right-to-left setting). The on-screen order
  is Tomte's own in both views already, so physically moving items into Tomte's order is not built.

## Constraints from the game (12.x)

- **Item buttons are secure**: using an item (right-click) is protected. Buttons are created out of combat, ahead
  of need (a pool sized to the bag and bank slots), never created, re-parented or re-anchored in combat. New items
  arriving in combat go into existing buttons; a layout change that needs new buttons waits for
  `PLAYER_REGEN_ENABLED`. How Blizzard's container item buttons do this (template, bag ID / slot ID) is read from
  Blizzard's UI source. Opening and closing the bag window in combat must still work. See memory notes on secure
  button gotchas (no anchoring secure buttons to normal frames in some cases; measure in game).
- **Taint**: hooking the bag toggles (`ToggleAllBags`, `OpenAllBags`, `ToggleBackpack` and the like) with
  `hooksecurefunc` and hiding Blizzard's container frames must not taint anything; check with
  `/console loadDeprecationFallbacks 0` and a combat test.
- **Hardware events**: sorting, depositing and moving many items may be limited; every API used is checked on
  warcraft.wiki.gg first (bank tabs, `C_Bank`, `C_Container`, Warband deposit and gold). Anything protected is a
  button the player clicks, never a loop.
- **Performance**: updates batched on `BAG_UPDATE_DELAYED` and redrawn only for what changed; item data that
  isn't loaded yet fills in when it arrives (no blocking).
- File roles per CLAUDE.md: pure files for the search language, category assignment, sorting and layout packing
  (all unit-tested); readers for bags/bank/characters; UI files per window and the categories page; `Bags.lua`
  main file last. Files over ~900 lines get split.

## Step 1 additions (after the first in-game check, 2026-10-27)

The user's feedback on the first build, all in step 1:

- Sections with no items hide; items from outside the bags (bank, equipped) dropped anywhere on the window go into
  a free slot; search words also match tooltip text.
- Marks: item level (quality color or plain, outlined numbers, a number size), Gear Check's arrow, the crafting
  list's count, the transmog diamond, an equipment set mark, a battle pet's level, the junk coin. Each picks a
  corner or Off; marks sharing a corner show the first that applies in a fixed order (Data.lua's BAGS_MARKS).
  *(Claude's call: a fixed order instead of a per-corner ordered list, which the options schema can't draw.)*
- Item looks: grey out junk, red tint on gear and recipes you can't use (a red tooltip line), the game's "fade
  what doesn't fit" (item context matching), new item glow.
- Bag slots open as a row of the equipped bags above the window's top-left, each with its free slots.
- Layout: category spacing, group identical items (one icon, the total; clicks act on the first stack), top bar
  buttons only on hover, lock the window.
- Sorting: order inside a category (quality, item type, name, item level), reverse, Clean Up when the bags open.
- Auto open: per window, on or off: the ones the game opens the bags for (vendor, mail, bank, Auction House,
  scrapping, catalyst) can be turned off; item upgrade, guild bank, professions, character panel, socketing and
  trade can be turned on. Tomte never calls Blizzard's bag open/close functions for this (taint on
  FRAME_THAT_OPENED_BAGS, read by Esc's CloseAllWindows): it shows its own window, and closes by hiding Blizzard's
  invisible bag frames.

## Steps 2-4 as built (2026-10-27, one batch, the user's call)

- **Bank** (Bank.lua, drawing shared with the bag window in View.lua): Blizzard's BankFrame stays shown at alpha 0
  off screen (it runs the visit: OnShow picks the tab, OnHide ends it; hiding it under a hidden parent would skip
  both). Character / Warband switch: BankFrame.BankPanel:SetBankType from addon code (the secure-click overlay
  didn't work in game; right-click deposits with a bank type work from addon code, as Alts' Deposit for alts
  measured; BankFrame:SetTab is avoided for its UI panel layout call). Close: C_Bank.CloseBankFrame. Tabs as an icon column (click: only that tab), Clean Up
  (C_Container.SortBank), deposit all (C_Bank.AutoDepositItemsIntoBank, refund warning through ns.Confirm_Show,
  "Include reagents" = CVar bankAutoDepositReagents), Warband gold (C_Bank.DepositMoney / WithdrawMoney, amount via
  ns.Dialog_Show). Tabs hang in a column outside the window's right edge (user's wish); right-click renames
  (C_Bank.UpdateBankTabSettings); a "+" shown only when a tab can be bought asks (ns.Confirm_Show, the cost from
  C_Bank.FetchNextPurchasableBankTabData) and buys it with C_Bank.PurchaseBankTab on that click. The player never
  needs Blizzard's bank window (user's requirement). The bank follows the bag
  window's search. While the Warband bank is shown, bag items it won't take fade (C_Bank.IsItemAllowedInBankType).
- **Categories editor** (EditPage.lua, rules in EditData.lua): a page with the list left, the picked node right.
  Moving is Move up / Move down and a Section dropdown *(Claude's call, instead of drag and drop)*. The player's
  layout is a copy of the defaults made on the first edit (`layout`, empty until then); Defaults empties it again.
  Sharing: a text format with a version header (EditData.lua). Saved searches (`searches`) in a star menu by the
  search box, with Save as category.
- **Item counts** (Modules/Counts, on by default): the record per character GUID; bank and Warband bank read while
  the bank is open, mail while the mailbox is open, guild bank tabs as you look at them. Tooltip lines; Alts reads
  it first (then Syndicator, then this character). Bags: a character button shows another character's bags
  (display-only buttons, no upgrade arrows) and "Find on all characters" lists matches with who has them. Auction
  listings: not recorded.

## Left to the builder

- Search keyword spelling and the exact default category list, names and order (within the coverage above).
- Sort rules (the order items take on screen inside a category and in the one-bag view).
- Exact layout packing (how categories flow into lines), spacing, and window sizing within "dense".
- Whether windows move by Edit Mode or by dragging.
- Auction listings in the record; transmog icon detail; how the bank tabs column behaves for buying and settings.
- How to split each step into commits and in-game test lists (batch the checks, per memory).
