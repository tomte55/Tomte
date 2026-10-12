# Showcase: slot card, gear menu, gems and enchants

2026-10-12. Follow-up to the Showcase (2026-10-11-tomte-showcase-design.md): items 2-4 of its open list. The user
delegated the decisions ("plan and build 2-5 in one go, we tweak after") and sent three Narcissus screenshots
as reference (card with an Alt hint, a three-row menu beside the slot, a list with "No compatible items"). Behavior
only, no Narcissus code (no license).

The bigger dressing room (item 5 in the session's list) is a small module of its own, at the end.

## Slot card (Card.lua)

Replaces Blizzard's item tooltip on a slot hover with our own card, as in the approved mockup frame "Slot tooltip":

- Quality-colored top rule and soft glow; item icon in a diamond at the top right.
- Name (quality color), big item level, upgrade track with pips and "max <ilvl>" (when the track has a higher
  level), a meta line "Head · Mail · Soulbound" (Blizzard's slot name, the item's subtype for armor/weapons, bind
  state from Gear Check's reader).
- Stats: armor, your primary stat (only the one your spec uses), stamina; then the secondary stats with a swatch
  in the Showcase's stat color and their percent for you ("1.72%", `GetCombatRatingBonusForCombatRatingValue`,
  mastery times your spec's mastery factor).
- Effects: the item's Use / Equip / proc lines, wrapped (the card would otherwise hide them).
- Enchant: the enchant (success) or "No enchant" (danger) with "<slot> takes one"; one row per socket: the gem's
  icon, name and stats, or "Empty socket" with Gear Check's best gem.
- Gear Check box: the same rank lines Gear Check adds to the item tooltip ("Beast Mastery: your best", "bag has
  better"), via a new `ns.Gear_ItemLines(link)` (Tooltip.lua's own-character lines without a tooltip). Hidden while
  Gear Check is off.
- Footer: "Click for options", "Shift-click to link". Above the card a small key hint: [Alt] "Full tooltip".
- Holding Alt swaps the card for the full Blizzard tooltip (set bonuses, flavor, everything we leave out).

Pure parts (Data.lua, tested): the stat rows, the meta line, percent text.

## Gear menu (Menu.lua)

A click on a slot opens a panel beside it (the card hides). Three rows, each with an icon, a title and a status:

- **Equipment**: "No other item for Head" (danger) or "3 items in your bags".
- **Enchants**: the current enchant (success), "No enchant" (danger), or "Doesn't take one" (muted, and no
  enchants in the bags for it).
- **Gems**: "No socket" (danger), "1 empty socket" (warning) or "All sockets filled".

A row opens its list in the same panel (a back arrow returns): icon, name in quality color, a detail line. An empty
list says "No compatible items". The panel closes with its x, a click on the same slot, a click on the world or
the Showcase closing. Clicking another slot moves it there.

### Equipment

- Candidates: `GetInventoryItemsForSlot(slot, t)`; keys decoded with Blizzard's pure
  `EquipmentManager_GetLocationData`; only bag items (not bank, not other worn slots). Detail: item level and Gear
  Check's headline (colored), best first.
- Equip by click: `ClearCursor`, `C_Container.PickupContainerItem`, `PickupInventoryItem(slot)` (Blizzard's own
  sequence; not its EquipmentManager functions, which write its globals).
- Bind on equip: `EQUIP_BIND_CONFIRM` / `_REFUNDABLE_` / `_TRADEABLE_CONFIRM` show our own confirm in the panel
  ("Equipping binds it to you"): Equip -> `EquipPendingItem(slot)`, Cancel -> `CancelPendingEquip(slot)`.
  Blizzard's own popups (on the hidden UIParent) are left alone: `StaticPopup_Hide` from addon code taints the popup
  system, and the game hides them itself once answered.

### Gems

- Socket chips at the top (current gem or an empty ring); the first empty one is picked. Gems are read by socket
  (`Gear_LinkGemSlots`, holes kept), so an empty first socket never makes the list replace a gem unasked.
- List: gems in the bags (item class 3, not relics), Gear Check's best one first with "Best for <spec>", detail
  the stats it gives.
- Socket by click: `SocketInventoryItem(slot)`, then (same click) `PickupContainerItem`,
  `C_ItemSocketInfo.ClickSocketButton(i)`, `AcceptSockets()`; `CloseSocketInfo()` after. When the socket info
  isn't ready inside the click, it finishes on `SOCKET_INFO_UPDATE`. A gem that doesn't fit
  (`GetNewSocketInfo` gemMatchesSocket false) is put back and the row says so.
- Replacing a gem destroys the old one: the panel asks first (the click on "Replace" does the socketing).
- `SOCKET_INFO_BIND_CONFIRM` / `_REFUNDABLE_CONFIRM` -> the panel asks, `CompleteSocketing()`.

### Enchants

- List: bag items of class Item Enhancement (8) whose subclass fits the slot (head 0, neck 1, shoulder 2, cloak 3,
  chest 4, wrist 5, hands 6, waist 7, legs 8, feet 9, finger 10, weapon 11 (any weapon), two-hand 12, off-hand 13);
  for weapons also temporary enchants (consumables of subclass Item Enhancement 6). Detail: the item's Use line.
- Using a bag item is protected, so the rows use one SecureActionButton (parented to WorldFrame, since UIParent is
  hidden, placed over the hovered row in WorldFrame coordinates, the Teleports map tab's pattern). Macro:
  `/use <bag> <slot>` then `/use <inventory slot>`. PostClick: if a targeting cursor is still up,
  `PickupInventoryItem(slot)` applies it.
- `REPLACE_ENCHANT`, `REPLACE_TRADESKILL_ENCHANT`, `BIND_ENCHANT`, `ACTION_WILL_BIND_ITEM` -> the panel asks
  ("Replace <old> with <new>?"), then `C_Item.ReplaceEnchant()` / `ReplaceTradeskillEnchant()` / `BindEnchant()` /
  `ActionBindsItem()`. Cancel clears the targeting.

## Unverified until tested in game

1. `GetInventoryItemsForSlot` values (we only use the keys).
2. `ClickSocketButton` / `AcceptSockets` needing a hardware event (done inside the click when possible).
3. Item class of War Within enchant scrolls and oils (if the list stays empty: `/dump C_Item.GetItemInfoInstant(id)`).
4. `/use <slot>` applying a pending enchant; the PostClick fallback covers it.
5. A secure button parented and anchored to WorldFrame.
6. `CancelPendingEquip` from Blizzard's hidden popup after `EquipPendingItem`.

## Dressing room (module `dressup`, Modules/DressUp/)

Blizzard's dressing room (DressUpFrame) with the Narcissus features that don't need to replace Blizzard code. The
user asked for "the features from Narcissus"; a survey of Narcissus's dressing room (behavior only, no code) showed
it overwrites several Blizzard functions (Link button, outfit loading, popups), which taints the window (Narcissus
even ships a popup explaining the blocked "Copy to clipboard"). Tomte only hooks and talks to the model's actor.

- **Size:** the window takes a share of the screen's height (setting "Size", default 80%, 50-95%) through its scale,
  applied on every show and size change. Never the panel manager (taint).
- **Slot bar** (Slots.lua): a button per slot along the bottom of the model (head, shoulders, back, chest, wrists |
  hands, waist, legs, feet | main hand, off hand | shirt, tabard), read from `actor:GetItemTransmogInfo`. Icon
  (`GetSourceIcon`), a dot when the appearance is collected, the item on hover, click hides (`UndressSlot`, the info
  kept) or shows it again (`SetItemTransmogInfo`), Shift-click links the item. Faint (35%) until the mouse is near or
  something is tried on, then fades back after 2 s. Refreshed from the ModelScene's OnDressModel (hooked).
- **Toolbar** (Tools.lua), right of the model: Undress (`actor:Undress`); Target's outfit (`NotifyInspect`, then on
  `INSPECT_READY` `C_TransmogCollection.GetInspectItemTransmogInfoList` onto the actor; the target's own body by
  default, yours with "Target's outfit on your character"); Item list ("Slot: Name - source" lines, source from
  `GetAppearanceSourceDrops` or `TRANSMOG_SOURCE_n`, in a copyable dialog). Blizzard's own Link button already posts
  or copies the outfit, so Tomte doesn't redo that.
- Bar and toolbar show only in player mode (not mounts or pets): `SetMode` is hooked.
- Left out: set panel (Blizzard has one), outfit icon picker, Dracthyr/Worgen form switch, turntable, Wowhead link,
  favorites.

## Not in this round

Item source line ("dungeon > boss"), Narcissus's "Owned" toggle (enchants you could craft), transmog.
