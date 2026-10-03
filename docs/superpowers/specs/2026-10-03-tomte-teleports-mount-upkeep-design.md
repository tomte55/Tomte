# Tomte: Teleports, Smart Mount, Vendor Helper, Durability

Four new modules. Teleports and Smart Mount go in the **Travel** category next to Flight Timer and Waypoints.
Vendor Helper and Durability go in a new **Upkeep** category.

| Module | Folder | Default |
|---|---|---|
| Teleports | `Modules/Teleports/` (`Data.lua`, `Owned.lua`, `MapTab.lua`, `Teleports.lua`) | on |
| Smart Mount | `Modules/Mount/` (`Data.lua`, `Pick.lua`, `Journal.lua`, `Mount.lua`) | on |
| Vendor Helper | `Modules/Upkeep/Vendor.lua` | on |
| Durability | `Modules/Upkeep/Durability.lua` (+ shared `Modules/Upkeep/Data.lua`) | on |

Pure logic (choosing a mount, deciding repair funding, durability thresholds, sorting teleports) goes in
plain-Lua functions with unit tests in `Tomte/tests/`, like the existing modules.

## APIs (checked against Blizzard UI source, live branch, 12.1.0.69933)

The proxy blocked warcraft.wiki.gg, so hardware-event and protected flags come from Blizzard's own code and from
current addons that call these functions. Items marked *(test)* need an in-game check.

| Need | API | Notes |
|---|---|---|
| Sell junk | `C_MerchantFrame.GetNumJunkItems()`, `C_MerchantFrame.SellAllJunkItems()`, `C_MerchantFrame.IsSellAllJunkEnabled()` | No confirmation; the popup belongs to Blizzard's button. Current addons call it from `MERCHANT_SHOW`. Junk = grey items; bags flagged "Ignore junk selling" are respected by the game. |
| Repair | `CanMerchantRepair()`, `GetRepairAllCost()` → `cost, canRepair`, `CanGuildBankRepair()`, `GetGuildBankWithdrawMoney()`, `RepairAllItems(useGuild)` | `CanGuildBankRepair` doesn't check the remaining daily limit (Blizzard's own FIXME), so we compare cost against `GetGuildBankWithdrawMoney()`. *(test: -1 = unlimited?)* |
| Merchant events | `MERCHANT_SHOW`, `MERCHANT_CLOSED` | |
| Durability | `GetInventoryItemDurability(slot)` → `cur, max` (nil without durability), `UPDATE_INVENTORY_DURABILITY` | Not combat data, no secret values. |
| Restrictions | `C_RestrictedActions.IsAddOnRestrictionActive(type)` | Vendor Helper does nothing while any restriction is active. |
| Mounts | `C_MountJournal.GetMountIDs()`, `GetMountInfoByID` (`isUsable`, `isFavorite`, `isCollected`, `isSteadyFlight`, `spellID`), `GetMountInfoExtraByID` (`mountTypeID`), `GetMountUsabilityByID(id, true)` | Raw `mountTypeID` → ground/flying/aquatic table in `Mount/Data.lua` *(community values, test)*. |
| Mount context | `IsMounted()`, `IsFlyableArea()`, `IsAdvancedFlyableArea()`, `IsSubmerged()`, `IsIndoors()`, `C_Map.GetBestMapForUnit("player")`, `C_Map.GetMapInfo(id).parentMapID` | |
| Secure button | `SecureActionButtonTemplate`, `type=macro` + `macrotext`; `type=spell` / `toy` / `item`; 12.x also adds `teleporthome` (housing) | Mouse clicks fire on button-up. For a keybind (`CLICK ...:LeftButton`) we register `AnyUp` and set `useOnKeyDown=false`. |
| `/cancelform`, `/dismount`, `/leavevehicle` | Secure slash commands, fine in a `macrotext` | `CancelShapeshiftForm` can't be called from addon Lua. |
| Teleport ownership | `PlayerHasToy(itemID)`, `C_SpellBook.IsSpellKnown(spellID)`, `C_Item.GetItemCount(itemID)` | Global `IsSpellKnown`/`IsPlayerSpell` are deprecated in 12.x. Don't use them. |
| Cooldowns | `C_Spell.GetSpellCooldown(id)` (table), `C_Item.GetItemCooldown(itemID)` | Spell cooldowns are **secret while restrictions are active** (combat, M+ etc.). We only read them out of combat and show "–" otherwise. |
| Dungeon teleports | No API. `GetFlyoutInfo` / `GetFlyoutSlotInfo` enumerate the Hero's Path flyouts | We hardcode `spellID → name, mapID, season` in `Teleports/Data.lua`, scan the flyouts as a cross-check and print any spell we don't know. |
| World map tab | `QuestMapFrame` tabs: `QuestLogTabButtonTemplate`, `.displayMode`, `QuestMapFrame:SetDisplayMode(mode)`, `QuestMapFrame.ContentFrames`, `EventRegistry` `"QuestLog.SetDisplayMode"` | Adding a tab needs no hooks. *(test for taint with BugSack.)* |

## Teleports

### Where it lives

A fourth tab in the world map's side panel, after Quests / Events / Map Legend, with a portal icon. The tab shows a
scrolling list of every teleport this character can use.

**The combat problem:** a secure button inside the world map would make the map protected, and then it
couldn't be opened or closed in combat. So the list rows are ordinary frames. There's a **single secure button
parented to UIParent** that moves over whichever row the mouse is on, and gets that row's `type` and
`spell`/`toy`/`item` attributes (the hover-overlay pattern). Out of combat, that button does the actual cast. On
`PLAYER_REGEN_DISABLED` it hides and the list greys out with an "In combat" note; it's back on
`PLAYER_REGEN_ENABLED`. The map itself keeps working normally in combat.

### What's in the list

Sections, in order (an empty section is hidden):

1. **To this map**: teleports whose destination is on the map you're viewing (that zone, or anywhere on that
   continent if you're viewing a continent). This is the part a world map tab gives you that a popup can't.
   Browse to Valdrakken and its teleports float to the top.
2. **Hearthstone**: your hearthstone with its bound location (`GetBindLocation()`), and hearthstone toys you own,
   plus a **Random toy** row that picks a different owned hearthstone toy each time. Also Dalaran Hearthstone,
   Garrison Hearthstone, and **Home** (housing, through the `teleporthome` button type) if you have a house.
3. **Dungeons**: Hero's Path teleports you've earned, this season's first, then older ones grouped by expansion.
   Unearned ones from the current season are listed greyed out, so you can see what's left.
4. **Class**: Mage teleports and portals, Death Gate, Dreamwalk, Zen Pilgrimage, Astral Recall. These only show on
   classes that have them; they're there for alts and friends.
5. **Items and toys**: Engineering wormholes and tinkers, Kirin Tor and Dalaran rings, Argent Crusader's
   Tabard, Ruby Slippers-style items, and so on: a hand-curated list in `Data.lua`.

Each row shows the icon, name, destination and cooldown. On cooldown it greys out with the remaining time. Items
you need to equip, such as rings and the tabard, say "(equips)": the `item` button type equips them on the first
click, and you click again to use them.

Hovering a row shows the normal spell, toy or item tooltip. Hovering also places a small pin on the map at the
destination when it's on the map you're viewing.

### Data

**As built:** dungeon and mage teleports are discovered from the spellbook's flyouts (Hero's Path, and any flyout whose spells teleport), the current season from `C_ChallengeMode.GetMapTable()`, and "To this map" by matching each teleport's destination (parsed from its description, or the bind location) against the viewed map, its child zones and their dungeon entrances (`C_EncounterJournal.GetDungeonEntrancesForMap`). Only class spells outside flyouts, hearthstone items/toys and teleport items are hardcoded. Hearthstone toys show as one "Random hearthstone toy" row unless "List every hearthstone toy" is on. The original plan follows.


`Teleports/Data.lua`: `{ kind = "spell"|"toy"|"item"|"home", id = 12345, dest = "Valdrakken", mapID = 2112,
section = "dungeon", season = "12.1S1", expansion = 11 }`. `Owned.lua` filters the list on login and on
`SPELLS_CHANGED`, `TOYS_UPDATED`, `BAG_UPDATE_DELAYED` and `NEW_TOY_ADDED`.

### Settings

- Show unearned current-season dungeon teleports (on)
- Hide sections (checkbox per section)
- Favorites: right-click a row to pin it to the top of the list

### Commands

`/tomte tp` opens the world map on the Teleports tab. `/tomte tp scan` prints flyout spells that `Data.lua`
doesn't know about.

## Smart Mount

### The key

One key binding, **Tomte → Smart Mount**, which is a `CLICK TomteMountButton:LeftButton` binding in `Bindings.xml`.
The button is a secure `type=macro` button. Its `macrotext` is rebuilt out of combat whenever the context can change
(`PreClick` when not in combat, plus `ZONE_CHANGED*`, `PLAYER_ENTERING_WORLD`, `MOUNT_JOURNAL_USABILITY_CHANGED`,
`PLAYER_REGEN_DISABLED`), so there's always a valid macro in place:

```
/leavevehicle [canexitvehicle]
/dismount [mounted]
/cancelform [form:<travel-like forms for this class>]
/stopmacro [mounted][vehicleui][form:<same>]
/cast <chosen mount name>
```

- **Mounted, in a vehicle, or in travel form / Ghost Wolf:** the first lines get you out and the macro stops there.
- **Otherwise:** it summons the chosen mount. `/cast` doesn't take IDs, so we use the mount's spell name from
  `C_Spell.GetSpellInfo(spellID)`.
- **Which forms to cancel:** per class, in `Mount/Data.lua`. Druid Travel/Flight/Aquatic forms and Shaman Ghost Wolf.
  Never Bear/Cat, and never Paladin auras or Rogue stealth. *(The form index per class needs an in-game check.)*
- **In combat:** you can't mount, so the macro just does whatever dismount/leave vehicle it last held.

### Choosing the mount (pure function, tested)

1. **Context:**
   - `IsSubmerged()` → **water**
   - `IsFlyableArea()` and not `IsIndoors()` → **flying**
   - otherwise → **ground**
2. **Candidate pool, first match wins:**
   1. **Zone favorites** for the current map, walking up `parentMapID` (zone, then continent, then world). The
      first level that has a list wins.
   2. Your **journal favorites**.
   3. All usable collected mounts.
3. **Filter the pool** to mounts that suit the context and are usable now (`GetMountUsabilityByID(id, true)`):
   - water: aquatic mounts, falling back to flying, then ground
   - flying: flying mounts
   - ground: any mount (flying mounts run fine on the ground), preferring ground-type mounts if the pool has any
4. **Pick at random**, but never the same mount twice in a row when there's a choice.
5. If nothing is left, fall back to `/cast` on Blizzard's random favorite.

**Skyriding vs steady flight:** the game uses whichever flight style you've set ("Switch Flight Style"). If you've
set skyriding, we skip mounts marked `isSteadyFlight`, since those can't skyride.

### Per-zone favorites

- **In the Mount Journal:** a small **Zone favorite** star button next to Blizzard's favorite button, for the
  selected mount. Clicking it opens a menu: "Add to *Zone name*" or "Add to *Continent name*", with a check on
  whichever it's already in. The zone and continent come from where you're standing.
- **In the Tomte panel:** a Smart Mount page lists each zone or continent that has favorites, with the mount icons,
  and lets you remove mounts or clear a whole list.
- **Storage:** zone favorites are **account-wide**, in `TomteDB.mount.zones[mapID] = { mountID, ... }`, because
  mounts are account-wide. Faction-specific mounts are filtered out when you're on the other faction.

### Settings

- Prefer ground-type mounts on the ground (on)
- Use zone favorites (on)
- Avoid repeating the last mount (on)

### Commands

`/tomte mount why` prints the context, which pool was used, and the chosen mount, for debugging. `/tomte mount
zone` lists the favorites for where you are.

## Vendor Helper

On `MERCHANT_SHOW`, unless **Shift is held** (the standard "don't touch anything" override) or an addon
restriction is active:

1. **Repair** (if `CanMerchantRepair()` and the cost is > 0):
   - If `CanGuildBankRepair()` and the remaining guild withdraw limit covers the full cost, call
     `RepairAllItems(true)`.
   - Otherwise call `RepairAllItems()` with your own gold, if you can afford it. If you can't, print a warning.
   - We don't split a repair between guild and own gold: `RepairAllItems` is all or nothing.
2. **Sell junk** (if `GetNumJunkItems() > 0`): before selling, add up the value of the grey items (sell price ×
   count, from the bag scan), then call `C_MerchantFrame.SellAllJunkItems()`.
3. **A toast** (Tomte's toast style) summing it up, for example:
   `Repaired 112g (guild)  ·  Sold 14 junk items +38g 20s`
   If nothing happened, there's no toast.

### Settings

- Auto repair (on)
- Use guild funds first (on)
- Auto sell junk (on)
- Summary toast (on); otherwise one chat line

### Command

`/tomte vendor` prints what happened at the last vendor visit.

## Durability

**Lowest durability** means the lowest `cur/max` across equipped slots that have durability. The module watches it
on `UPDATE_INVENTORY_DURABILITY` and `PLAYER_ENTERING_WORLD`.

- **Threshold toast:** one toast when the lowest durability drops below the threshold (default **30%**), naming the
  worst item: *"Gear at 27%: Legs"*. Another, red, toast when an item **breaks** (reaches 0).
  - It warns only once per threshold crossing. It warns again after durability goes back above the threshold
    (you repaired) and drops below once more.
- **Instance check:** on entering a dungeon, raid, delve or scenario (same `GetInstanceInfo` check and same short
  delay as the Hunter pet check), if the lowest durability is below the check threshold (default **50%**), show a
  banner like the pet check does: *"Repair before you pull: gear at 41%"*, with the raid warning sound.
  - If the Hunter pet check also has a problem, both still show. The banner queue handles this already.

### Settings

- Toast threshold (slider 10–60%, default 30)
- Toast when an item breaks (on)
- Instance check (on) and its threshold (slider 20–80%, default 50)

### Command

`/tomte dura` prints every slot's durability, worst first.

## Out of scope for now

- A keybind popup for teleports (we can add one later using the same list code)
- Vendor and passenger mounts on modifier keys
- Selling non-grey items and keeping a "junk list"
- A durability gauge on screen, and a line on the AFK screen

## Build order

Each step is a separate commit after you've confirmed it in game:

1. **Vendor Helper + Durability.** Small, and confirms the Upkeep category and toasts.
2. **Smart Mount.** First secure button and key binding in Tomte; zone favorites in the Mount Journal come second.
3. **Teleports.** The world map tab, the hover-overlay secure button, and the data list (the biggest step).
