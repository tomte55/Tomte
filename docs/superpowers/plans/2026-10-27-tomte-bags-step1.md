# Bags step 1 (the bag window) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tomte's own bag window (categories view and one-bag view, item overlays, search, sort) replacing
Blizzard's bags while the new Bags module is on.

**Architecture:** A new module folder `Modules/Bags/`: three pure files (search language, categories and
sorting, layout packing) with unit tests, a reader that turns bag slots into plain item records, an item button
pool built on Blizzard's own container item button template, the window, the takeover of Blizzard's bag toggles,
and the main file registering the module. Gear Check and Gold & value are asked through `ns.*` functions looked up
at call time.

**Tech Stack:** Lua 5.1 (WoW 12.1.5 client, interface 120105), plain-Lua unit tests (`tests/harness.lua`).

**Spec:** `docs/superpowers/specs/2026-10-27-tomte-bags-design.md`

## Global Constraints

- Nothing from Baganator or Syndicator: no code, no lists, no layouts, their folders are not opened.
- Every WoW API used is checked on warcraft.wiki.gg (or Blizzard's UI source) first. No deprecated globals.
- CLAUDE.md applies: `local addonName, ns = ...` first line, header comment, tabs, ~120 columns, theme roles only
  (no numeric colors, no `|cff`, no font paths; `tests/test_theme.lua` scans this), CRLF, Edit/Write tools only.
- Module key `bags`, name "Bags", category `gear`, `enabledByDefault = false`.
- Item buttons never created, re-parented or re-anchored in combat if they are protected (see Task 6).
- Turning the module off mid-session gives Blizzard's bags back fully.
- No commit before the user's in-game check, except this plan and the spec (docs). Then one commit per task.
- Tests: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done` from `AddOns`;
  after TOC changes `lua Tomte/tools/bugfiles.lua`; new files pass the `luac -l ... | grep GETGLOBAL` check.

## Review Focus

1. Clicking (use, pick up, drop on an empty slot, split with Shift) works on every item, in and out of combat.
2. Items whose data isn't loaded yet (first open after login) appear in the right category once loaded, without a
   reopen.
3. Bags full (no empty slot) and a reagent bag missing: no errors, Empty shows only kinds that exist.
4. An invalid or half-typed search ("is:", "ilvl>", "(", "or") never errors: it shows a muted note and keeps the
   last good filter or none.
5. Turning the module off while the window is open hides it and Blizzard's bags open again on the bag key.

Tests for 2 and 4 are in Tasks 2 and 5; 1, 3 and 5 are in the in-game list (Task 10).

---

### Task 1: One shared check for uncollected appearances (refactor)

**Files:**
- Modify: `Core/Core.lua` (add `ns.NewAppearance`)
- Modify: `Modules/Loot/Read.lua:21-33` (NewLook → `ns.NewAppearance(link) == "you"`)
- Modify: `Modules/WorldQuests/Scan.lua:223-234` (MissingAppearance → same)

**Interfaces:**
- Produces: `ns.NewAppearance(link) -> "you" | "other" | nil`: "you" when the appearance isn't collected on the
  account and this character can collect the source; "other" when it isn't collected and this character can't;
  nil otherwise or for non-transmog items.

- [ ] Step 1: Add the function with the existing calls (`C_TransmogCollection.GetItemInfo`,
  `GetAppearanceInfoBySource`, `PlayerCanCollectSource`), returning "other" where the old copies returned false
  because `canCollect` was false.
- [ ] Step 2: Replace both local copies; behavior unchanged for Loot and World Quests.
- [ ] Step 3: Run all tests; GETGLOBAL check on the three files.
- [ ] Step 4 (after in-game check): commit `Share the uncollected-appearance check (refactor)`.

### Task 2: Search language (pure)

**Files:**
- Create: `Modules/Bags/Search.lua`
- Test: `tests/test_bagssearch.lua`

**Interfaces:**
- Consumes: the item record (defined in Task 3's Data.lua header; Search.lua loads first, so it documents the
  fields it reads): `name, typeName, subTypeName, itemID, count, quality, ilvl, classID, subclassID, equipLoc,
  bind ("soulbound" | "warbound" | "boe" | nil), expansion, price, upgrade ("upgrade" | "maybe" | "alt" | nil),
  look ("you" | "other" | nil), junk, new, set (equipment set names or nil), toy, mount, pet, decor, hearth,
  keystone`.
- Produces: `ns.BagsSearch_Compile(text) -> match | nil, err` where `match(item) -> bool`; empty or blank text
  returns nil with no error. `ns.BagsSearch_Keywords() -> { { word, help } }` for the "?" list.

Syntax (Tomte's own):
- Words: case-insensitive substring of `name`, `typeName` or `subTypeName`. Quoted text keeps spaces.
- `is:<word>`: gear, weapon, armor, consumable, potion, food, reagent, tradegoods, profession (profession
  equipment), recipe, quest, gem, enhancement, key, bag, misc, battlepet, toy, mount, pet, decor, hearth, keystone,
  junk, new, set, upgrade, maybe, altupgrade, transmog (`look ~= nil`), mytransmog (`look == "you"`), soulbound,
  warbound, boe, and the quality words poor, common, uncommon, rare, epic, legendary, artifact, heirloom.
- Comparisons: `ilvl`, `count`, `price` (gold), `q` (quality number) with `= > < >= <=`, e.g. `ilvl>=600`.
- `exp:<short>`: classic, tbc, wrath, cata, mop, wod, legion, bfa, sl, df, tww, midnight (expansion IDs 0-11).
- Space or `and` = and; `or` or `|` = or; `not` or a leading `-` = not; parentheses. Precedence: not > and > or.
- Errors: unknown `is:` word, unbalanced parentheses, a dangling operator, a comparison without a number:
  `nil, "<short player-facing reason>"`.

- [ ] Step 1: Write the failing tests in `tests/test_bagssearch.lua`, at least:
  - `Compile("")` and `Compile("  ")` → nil, nil.
  - "bread" matches `{ name = "Fresh Bread" }`, not `{ name = "Potion" }`.
  - "is:upgrade" matches `{ upgrade = "upgrade" }` only; "is:maybe" matches `upgrade = "maybe"`.
  - "is:gear ilvl>=600" matches `{ classID = 4, ilvl = 610 }`, not ilvl 590, not classID 0.
  - "is:potion or is:food" with consumable subclasses 1 and 5 (and not 0).
  - "-is:junk" excludes `junk = true`; "not (is:rare or is:epic)" on quality 3, 4, 2.
  - "price>10" true at 100001 copper, false at 100000.
  - `"\"fresh bread\""` matches the quoted phrase.
  - "exp:tww" matches expansion 10.
  - Errors return nil + a string: "is:", "is:nonsense", "(is:gear", "is:gear or", "ilvl>", "ilvl>abc".
- [ ] Step 2: Run `lua Tomte/tests/test_bagssearch.lua`: FAIL (file missing).
- [ ] Step 3: Implement: a tokenizer, a recursive-descent parser building closures, tables `FLAGS[word] = fn(item)`
  and `FIELDS[name] = fn(item) -> number`. Item class numbers as named constants with comments (Enum.ItemClass:
  Consumable 0, Container 1, Weapon 2, Gem 3, Armor 4, Reagent 5, Tradegoods 7, ItemEnhancement 8, Recipe 9,
  Questitem 12, Key 13, Miscellaneous 15, Battlepet 17, Profession 19; consumable subclasses Potion 1, Food and
  drink 5 — each checked on warcraft.wiki.gg/wiki/ItemType before use; decor uses the record's `decor` flag).
- [ ] Step 4: Tests pass.

### Task 3: Categories, assignment and sorting (pure)

**Files:**
- Create: `Modules/Bags/Data.lua`
- Test: `tests/test_bags.lua`

**Interfaces:**
- Consumes: `ns.BagsSearch_Compile`.
- Produces:
  - `ns.BAGS_LAYOUT`: the default layout, a list of nodes: `{ kind = "category", key, name, rule = "<search>" |
    auto = "new" | "set" | "empty" | "other", priority = number (default 0) }`, `{ kind = "section", key, name,
    children = { nodes } }`, `{ kind = "divider" }`.
  - `ns.Bags_Flatten(layout) -> categories` (ordered list of category nodes with `.order` and `.section`).
  - `ns.Bags_Assign(items, categories) -> byKey` (`byKey[categoryKey] = { items }`): each item in exactly one
    category; auto categories: `new` (item.new), `set` (item.set), `empty` (item.empty records), `other` (no
    match); for rule categories the highest `priority` wins, ties go to the lower `.order`; an auto category takes
    part in the same contest with its priority. Compiled rules are cached by text.
  - `ns.Bags_SortItems(list)` in place: quality high first, then ilvl high, name, itemID, count high, bag, slot.
  - `ns.Bags_Why(item, categories) -> lines` (matching categories in contest order, the winner first).

Default layout (Tomte's own, from item classes): New (auto new, priority 10), Upgrades (`is:upgrade`, priority 5),
Hearthstone (`is:hearth`), Keystone (`is:keystone`), Potion, Food, Consumable, Quest; section Equipment: Equipment
sets (auto set, priority 1), Weapon, Armor; section Crafting: Reagent (`is:reagent or is:tradegoods`), Profession
equipment, Recipe; section Housing: Decor; Gem, Item enhancement, Bag, Key, Toy, Battle pets, Miscellaneous;
divider; Other (auto other); Junk (`is:junk`, priority 8); Empty (auto empty, priority 20).

- [ ] Step 1: Failing tests: a reagent goes to Reagent; an upgrade armor piece to Upgrades not Armor; a new
  upgrade to New (10 > 5); a grey to Junk even though it's Armor (8 > 0); two equal-priority matches go to the
  earlier one; an item matching nothing to Other; an empty record to Empty; `Flatten` keeps section order and
  sets `.section`; `SortItems` orders epic 600 before rare 610 before rare 600; `Why` lists the winner first.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: pass.

### Task 4: Layout packing (pure)

**Files:**
- Create: `Modules/Bags/Layout.lua`
- Test: `tests/test_bagslayout.lua`

**Interfaces:**
- Produces: `ns.Bags_Pack(blocks, opts) -> placed, height`. `blocks`: ordered list of `{ kind = "category",
  key, label, count }`, `{ kind = "section", key, label, folded }`, `{ kind = "divider" }` (a section's categories
  follow it in the list with `section = key`; a folded section's categories are skipped). `opts`: `columns, icon,
  gap, label (label line height), section (heading height), spacing (horizontal gap between categories on one
  line), lineGap`. `placed[i] = { block, x, y, cells = { { x, y } ... } }` in pixels from the top-left; sections
  and dividers get `x = 0, y`, `width`.

Rules: a category is `min(count, columns)` cells wide. It goes on the current line when it fits after `spacing`;
otherwise a new line. A category wider than what's left starts a new line and wraps its icons over full rows.
Sections and dividers always start a new line. A line is as tall as its tallest category. Categories with
count 0 are skipped. One-bag view passes one category with `label = nil` (no label line).

- [ ] Step 1: Failing tests: two 3-icon categories on 10 columns share a line (second x = 3 cells + spacing);
  a 9-icon one after them starts a new line; 25 icons on 10 columns make 3 rows; a section starts a new line and
  its folded children are skipped; `height` equals the last line's bottom; unlabeled block has no label offset.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: pass.

### Task 5: Reading the bags

**Files:**
- Create: `Modules/Bags/Read.lua`
- Modify: `Modules/Gear/Baganator.lua` (add `ns.Gear_BagArrow`; Baganator's widgets keep their own switches)

**Interfaces:**
- Produces:
  - `ns.BagsRead_Bags() -> items, pending` for the backpack, bags 1-4 and the reagent bag: an item record per
    filled slot (Task 2 fields plus `bag, slot, link, icon, locked, readable`), one `empty = true, kind =
    "normal" | "reagent", bag, slot` record per empty slot; `pending` true when some item's data wasn't loaded
    (those are re-read on `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT`).
  - `ns.BagsRead_Invalidate(bag)` drops cached records of one bag (nil: all).
  - `ns.Gear_BagArrow(link, location, isBound) -> "upgrade" | "maybe" | "alt" | nil`: nil while Gear Check is off;
    "alt" only while `altUpgrades ~= "off"`; same verdict functions as the Baganator widgets.
- Sources (check each on the wiki): `C_Container.GetContainerNumSlots`, `GetContainerItemInfo` (iconFileID,
  stackCount, isLocked, quality, hyperlink, itemID, isBound), `C_Item.GetItemInfo` (name, type, subtype,
  sell price, classID, subclassID, expansion), `C_Item.GetCurrentItemLevel(ItemLocation)` for gear,
  `C_NewItems.IsNewItem`, `C_Container.GetContainerItemEquipmentSetInfo`, `C_Item.IsBoundToAccountUntilEquip` or
  the warbound check the wiki gives, `C_ToyBox.GetToyInfo`, `C_MountJournal.GetMountFromItem`,
  `C_PetJournal.GetPetInfoByItemID`, `ns.NewAppearance`, `ns.Gear_BagArrow`. Secret values: `ns.IsSecret` before use.
  Hearthstone item IDs (6948 and the other hearth items the wiki lists) as a constant list with a comment.

- [ ] Step 1: Implement; caching per slot keyed by link and count; records for items not loaded are marked
  `readable = false` and placed in Other until loaded.
- [ ] Step 2: GETGLOBAL check.

### Task 6: Item buttons

**Files:**
- Create: `Modules/Bags/Buttons.lua`

**Interfaces:**
- Produces: `ns.BagsButtons_Get(bag, slot) -> button` (from a pool, made out of combat), `ns.BagsButtons_Paint(
  button, record, opts)` (icon, count, quality border, item level, upgrade arrow, transmog mark, junk mark, new
  glow, search fade; `opts` holds the overlay switches and the empty-slot count text), `ns.BagsButtons_ReleaseAll()`,
  `ns.BagsButtons_Prepare(n)` (grows the pool out of combat).
- Built on Blizzard's container item button template (exact template, how bag and slot are given to a button, and
  whether it is protected: from the research notes below, filled in before this task starts).

- [ ] Step 1: Implement; overlays use theme roles and Gear Check's arrow art (`bags-greenarrow`, tinted per role as
  in `Modules/Gear/Baganator.lua`).
- [ ] Step 2: GETGLOBAL check.

### Task 7: The bag window

**Files:**
- Create: `Modules/Bags/Window.lua`
- Modify: `Modules/Value/Backpack.lua` (export `ns.ValueBackpack_Entries()`, `ns.ValueBackpack_EntryEnter(owner,
  entry)`, `ns.ValueBackpack_EntryClick(entry, button)`, and call `ns.Bags_RefreshFooter` when present)

**Interfaces:**
- Produces: `ns.BagsWindow_Show()`, `ns.BagsWindow_Hide()`, `ns.BagsWindow_Toggle()`, `ns.BagsWindow_IsShown()`,
  `ns.BagsWindow_Refresh()` (re-read and redraw, batched to the next frame), `ns.Bags_RefreshFooter()`.
- Global frame name `TomteBagsWindow` (for `/fstack` and key bindings).

Window: `UI.Panel`, dragged by the top bar, position in `db.position`, Escape closes (`UI.CloseOnEscape`).
Top bar: title "Bags", search box (`UI.SearchBoxClear`, placeholder "Search, try is:upgrade", muted error line
under it), buttons: bag slots (toggles a row of the equipped bags), sort (`C_Container.SortBags()`; out of
combat only), settings (opens the module's page), close. Body: `ns.Bags_Pack` output; category labels
`UI.Text(…, 10, "textMuted", "label")`; section headings with a fold arrow (`db.folded[key]`); dividers
`UI.Hairline`. Search: items that don't match fade to 0.25 alpha (categories keep their place). Footer: "N free",
the game's tracked currencies (`C_CurrencyInfo.GetBackpackCurrencyInfo`), Gold & value's entries, gold
(`ns.Coins`). Settings: `view` ("categories" | "single"), `columns` (8-24, default 12), `iconSize` (28-44,
default 36).

- [ ] Step 1: Implement; redraw on the next frame after a batch of events (`BAG_UPDATE_DELAYED`).
- [ ] Step 2: GETGLOBAL check.

### Task 8: Taking over the bag keys

**Files:**
- Create: `Modules/Bags/Takeover.lua`

**Interfaces:**
- Produces: `ns.BagsTakeover_Start()`, `ns.BagsTakeover_Stop()`.

While started: the bag toggles open, close and toggle Tomte's window instead of Blizzard's, and Blizzard's
container frames stay hidden; Stop gives everything back. Exact functions and the taint-safe way to keep
Blizzard's frames hidden: from the research notes below.

- [ ] Step 1: Implement; hooks inert while stopped.
- [ ] Step 2: GETGLOBAL check.

### Task 9: The module

**Files:**
- Create: `Modules/Bags/Bags.lua`
- Modify: `Tomte.toc` (after `Modules/Gear/Bags.lua`: `Modules/Bags/Search.lua`, `Data.lua`, `Layout.lua`,
  `Read.lua`, `Buttons.lua`, `Window.lua`, `Takeover.lua`, `Bags.lua`), `Modules/Gear/Bags.lua` (no quality border
  while `ns.Bags_Active()`), `Modules/Gear/Context.lua` (`InvalidateVerdicts` also calls `ns.BagsWindow_Refresh`
  when present), `README.md`, `CHANGELOG.md`, run `lua Tomte/tools/bugfiles.lua`

**Interfaces:**
- Produces: `ns.Bags_Active() -> bool`.

Registration: key `bags`, name "Bags", category `gear`, icon a bag file ID checked to exist, summary "Your bags
sorted into categories, with upgrade and transmog marks.", `enabledByDefault = false`, `conflicts` and `blocked`
for Baganator, Bagnon, ArkInventory, AdiBags, BetterBags, EnhanceQoLBags, `replaces` CanIMogIt ("transmog marks on
bag items"). Defaults: `view = "categories"`, `columns = 12`, `iconSize = 36`, `overlays = { ilvl = true, upgrade
= true, transmog = true, junk = true, new = true }`, `folded = {}` (`[section key] = true`), `position = {}`.
Events while active: `BAG_UPDATE_DELAYED`, `ITEM_LOCK_CHANGED`, `BAG_NEW_ITEMS_UPDATED`, `BAG_CONTAINER_UPDATE`,
`GET_ITEM_INFO_RECEIVED`, `PLAYER_MONEY`, `CURRENCY_DISPLAY_UPDATE`, `EQUIPMENT_SETS_CHANGED`,
`TRANSMOG_COLLECTION_UPDATED`, `PLAYER_REGEN_ENABLED` (deferred rebuilds). Options rows for each setting (view as
segmented, sliders, overlay switches). Commands: `why <item link>` (`ns.Bags_Why` lines), `show`.
README: module row, `/tomte bags why`, folder in Layout. CHANGELOG Unreleased `### New`: "- **Bags (new
module):** ...".

- [ ] Step 1: Implement and wire.
- [ ] Step 2: All tests, bugfiles, GETGLOBAL checks.

### Task 10: In-game check (user)

One combined list for the user (Baganator turned off at character select first): turn Bags on; open with B and
each bag key; categories as expected; one-bag view; use/move/split items (also in combat); drop on Empty; sort;
search incl. errors; arrows with Gear Check on/off; transmog marks; turn the module off with the window open;
`/console loadDeprecationFallbacks 0` no errors; BugSack clean. Then per-task commits.

## Research notes (Blizzard item buttons and bag toggles)

From Blizzard's `live` source (`Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua/.xml`) and the wiki, 2026-10-27.

- **Buttons:** `CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")` (mixin
  `ContainerFrameItemButtonMixin`; Blizzard itself makes them through `CreateFramePool` the same way). Not
  protected, not secure: they can be made and moved in combat. The button's slot is `button:SetID(slot)`; its bag is
  `GetBagID()` = `self.bagID or self:GetParent():GetID()`. So each bag gets a plain holder frame with
  `holder:SetID(bag)` and its buttons are parented to it (anchored anywhere in the window). Never write
  `button.bagID` and never call `button:Initialize` (it calls `GetParent():IsCombinedBagContainer()`); don't add
  methods to holders (Blizzard's click code would call addon code and taint). The click goes to
  `ContainerFrameItemButton_OnClick` → `C_Container.UseContainerItem` (protected) / `PickupContainerItem`:
  Blizzard's own code, so it should stay clean. **Unverified:** right-click use in combat (in-game test).
- **Updating a button's look:** use the mixin's own refresh calls where they exist (`SetItemButtonTexture`,
  `SetItemButtonCount`, `SetItemButtonQuality`, `UpdateCooldown`, `UpdateNewItem`, `SetMatchesSearch` — check each
  in ContainerFrame.lua before use) and draw Tomte's overlays on our own textures.
- **Taking over:** Blizzard's open state comes from its frames being shown (`IsBagOpen`, `IsAnyBagOpen`). Parent
  `ContainerFrame1..6` (normally `ContainerFrameContainer`) and `ContainerFrameCombinedBags` (normally `UIParent`) to
  a hidden frame: Blizzard keeps opening and closing them (merchants, mail, bank, Esc through `CloseAllBags`'s return
  value, `securecall("CloseAllBags")`), they stay invisible, and Tomte's window follows `IsAnyBagOpen()` after
  `hooksecurefunc` on `OpenAllBags, CloseAllBags, ToggleAllBags, ToggleBackpack, OpenBackpack, CloseBackpack,
  ToggleBag, OpenBag, CloseBag`. Our close button calls `CloseAllBags()`. Stop parents them back. No
  `UISpecialFrames` entry, no `UI.CloseOnEscape` (Esc already reaches `CloseAllBags`).
- **Events:** `BAG_UPDATE_DELAYED`, `BAG_UPDATE_COOLDOWN`, `ITEM_LOCK_CHANGED`, `BAG_NEW_ITEMS_UPDATED`,
  `BAG_CONTAINER_UPDATE`, `INVENTORY_SEARCH_UPDATE`.
- **Item level:** `C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bag, slot))`.
- **Binding:** `C_Item.IsBound(location)`, `C_Item.IsBoundToAccountUntilEquip(location)`; `ContainerItemInfo`
  fields: iconFileID, stackCount, isLocked, quality, isReadable, hasLoot, hyperlink, isFiltered, hasNoValue,
  itemID, isBound, itemName. Quest items: `C_Container.GetContainerItemQuestInfo`.
- Bag IDs: backpack 0, bags 1-4, reagent bag 5 (`Enum.BagIndex`). The reagent bag has its own Blizzard frame.
- Item classes (wiki ItemType): no housing class is listed, so decor is detected another way (Task 5 checks the
  wiki for a decor API, else decor is left out of step 1's defaults and noted).
