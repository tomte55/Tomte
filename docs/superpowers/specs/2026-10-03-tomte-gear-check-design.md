# Tomte: Gear Check (upgrade advisor, Pawn replacement)

## Goal

Pawn often calls items upgrades that aren't. The user wants an in-game verdict they can trust. "Better than Pawn"
here doesn't mean a smarter formula. It means two things: never show a false upgrade, and say "can't judge, sim it"
instead of guessing when an item's value is in an effect.

## Why Pawn gets it wrong (from reading Pawn 2.13.16 source)

- **Item level arrow, on by default** (`PawnIsItemAnItemLevelUpgrade`, Pawn.lua:4845). It flags any item above the
  best ilvl ever worn in that slot. It doesn't check armor type, main stat or spec, and it applies to trinkets.
  This arrow is OR'd into bag arrows and the green tooltip border.
- **Effects are worth 0 on both sides.** Equip, Use and proc lines, set bonuses and embellishments are all ignored
  (TooltipParsing.lua:40-57). So breaking a 4-set, or dropping an embellishment, shows as an upgrade.
- **Enchant and gems are stripped from the equipped item before comparing** (Pawn.lua:3010-3039), which overstates
  the gain of switching.
- **Unique-equipped limits aren't checked.** Pawn's own comment admits it (Pawn.lua:3729).
- **Upgrade tracks are ignored.**
- **Trinkets:** no stat scoring at all, only the item level arrow.
- **An empty slot or missing data becomes a 10,000% upgrade** (Pawn.lua:3740).
- **Fixed weights:** one Ask Mr. Robot weight set per spec. Stats come from parsing tooltip text.

## Midnight facts that shape the design

- Raidbots: stat weights are only "a quick in-game evaluation"; direct sims are better. In Midnight S2 the
  secondary weights are close to each other and to the primary stat, so **item level usually decides** and weights
  break ties.
- Tier: 5 slots (head, shoulders, chest, hands, legs), bonuses at 2 and 4 pieces. **Since 12.1, catalysed items keep
  their secondary stats and procs**, so any item in a tier slot is a potential tier piece.
- Embellishments: max 2. Enchantable slots: head, shoulders, chest, boots, rings, weapons.
- Upgrade tracks have 6 ranks (Adventurer, Veteran, Champion, Hero, Myth). We read them from the API and never
  hardcode item levels.

## APIs (verified on warcraft.wiki.gg and Gethe/wow-ui-source live, 12.1.0)

| Need | API | Notes |
|---|---|---|
| Stats | `C_Item.GetItemStats(link)` | Works on any link; nil until cached (`Item:ContinueOnItemLoad`) |
| Item level | `C_Item.GetDetailedItemLevelInfo(link)`, tooltip line `ItemLevel` | |
| Slot, class, armor type | `C_Item.GetItemInfoInstant(link)` | Synchronous |
| Spec can use it | `C_Item.DoesItemContainSpec(link, classID, specID)` | |
| setID | `C_Item.GetItemInfo(link)` return 16 | Count equipped pieces ourselves (no API for that) |
| Current tier set | `C_LootJournal.GetItemSets(classID, specID)` | Highest `itemLevel` = current tier |
| Upgrade track | `C_Item.GetItemUpgradeInfo(link)` | `{currentLevel, maxLevel, maxItemLevel, trackString}` |
| Uniqueness | `C_Item.GetItemUniqueness(link)` | Embellishment category needs an in-game check |
| Sockets and gems | `C_Item.GetItemNumSockets`, `C_Item.GetItemGem(link, i)` | |
| Enchant | Item string field 2 | |
| Effects | `C_TooltipInfo.GetHyperlink(link).lines`, types `ItemSpellTriggerOnUse/OnEquip/OnProc` (44/45/46) | |
| Spec, primary stat | `C_SpecializationInfo.GetSpecialization` / `GetSpecializationInfo` (return 6 = primaryStat) | |
| Tooltip hook | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` | |
| Bags | `Baganator.API.RegisterUpgradePlugin(label, id, fn(link) -> true/false/nil)` | Only if Baganator is loaded |

Item APIs don't return secret values. The player's own stat APIs (`UnitStat`, `GetCombatRating`) are secret under
restrictions since 12.0.5. We don't use them. As a guard, any tooltip text gets an `issecretvalue` check before use.

## What it shows

### Tooltip (every item tooltip: bags, loot, links, vendors, Encounter Journal)

One verdict line, then up to 3 short reason lines (grey, indented). Examples:

```
Gear Check: Upgrade +2.4%
Gear Check: Upgrade +1.1%  (but read below)
   Breaks your 4-set (4 → 3)
   Your current one is enchanted: re-enchant
Gear Check: Sidegrade (−0.4%)
Gear Check: Downgrade −3.2%
Gear Check: Not for you: wrong armor type (Leather)
Gear Check: Sim it: on-use effect not valued (stats alone −1.5%)
   Champion 2/6, upgrades to 308
   Can be catalysed into tier (completes 4-set)
```

Verdicts, colored:

- **Upgrade** (green): score > +1%, no warnings.
- **Upgrade, but** (yellow): score > +1% with at least one warning: breaks a set bonus, loses an
  embellishment, loses an enchant or gems, or loses an effect the equipped item has.
- **Sidegrade** (grey): within ±1%.
- **Downgrade** (red, dim).
- **Not for you** (grey): wrong armor type (cloaks exempt), wrong or no main stat for the spec (non-jewelry),
  `DoesItemContainSpec` false, or a level requirement above the player.
- **Sim it** (orange): the candidate's value is in an effect. That means any trinket, or a candidate with a
  Use, Equip or proc line, or an embellishment. Stats-only % shown in brackets as information.
- **Completes a set bonus** (2 or 4) upgrades a Sidegrade or Downgrade within −5% to **Upgrade, but**, with the
  reason "completes 4-set". It can't be valued, so it's flagged rather than scored.

Never "huge upgrade" for an empty slot: an empty slot shows "Upgrade (slot empty)".

### Bags (Baganator)

Through `RegisterUpgradePlugin`: `true` only for a clean **Upgrade** (green). Yellow and orange give `false`, so the
bag arrow is never wrong. Returns `nil` while item data isn't cached.

## Scoring

`score = Σ weight[stat] × amount + socket value`, using the spec's primary stat only. The other primary stats count as 0.

- **Weights per spec**: pasted from Raidbots (or any Pawn string) through an import dialog. Format
  `( Pawn: v1: "Name": Class=..., Spec=..., Agility=1.00, CritRating=0.61, ... )`. Mapped keys: Strength, Agility,
  Intellect, Stamina, CritRating, HasteRating, MasteryRating, Versatility, Dps (weapons), and Armor (tanks).
  Unknown keys are ignored.
- **No weights for this spec**: primary 1.0, each secondary 0.5. That is effectively an item level comparison;
  the tooltip says "(no weights: item level based)". `/tomte gear` explains how to import.
- **Sockets**: an empty socket is valued as the average gem the player has socketed now, read from the equipped gem
  links' stats. With no gems equipped, sockets aren't valued and the reason says "+1 socket".
- **Enchants**: there is no enchant → stats API, so they're not valued. They become a warning if the equipped item
  in that slot is enchanted and enchantable. Gems already in the equipped item count in its score; the candidate
  gets the socket value.
- **% =** (new − old) / old.

### What it compares against

- Normal slots: the equipped item in that slot.
- Rings and trinkets: the weaker of the two. A unique-equipped item that matches one of them (same item or unique
  category) is compared against that one only.
- Two-hander vs main hand + off-hand: the 2H is compared to the sum of both. A one-hander or off-hand when a 2H is
  worn: "Replaces your two-hander, needs a partner" plus the % against the 2H score. A main hand when dual-wielding:
  the weaker hand, if the item can go there.
- **Tier**: equipped pieces of the current tier are counted. A candidate in a tier slot gives a new count (remove
  the equipped piece, add the candidate). Going below 4 or below 2 is a warning. Reaching 2 or 4 is "completes".
  A non-set candidate in a tier slot with an upgrade track gets the "can be catalysed" note, with what that would
  do to the count.
- **Embellishments and unique**: if the candidate would push a unique category over its limit (e.g. 3
  embellishments) the verdict is **Not for you: would exceed Embellished (2)**. If the equipped item is embellished
  and the candidate isn't, the warning is "loses embellishment".
- **Upgrade track**: a reason line like "Champion 2/6, upgrades to 308" when not maxed. No % at max ilvl, because
  there's no API for stats at another ilvl and guessing would bring back false arrows.

## Not doing (v1)

- Diminishing returns or rating caps (needs player stats, secret under restrictions; rarely matters below 30%).
- Valuing effects, set bonuses or enchants numerically.
- Best-in-bags or cross-slot optimisation (e.g. ring swaps).
- Loot roll frame overlay, Great Vault, or our own bag overlay. The tooltip covers hovering all of these.
- Reading Pawn's or SimulationCraft's data.

## Structure

- `Modules/Gear/Data.lua`: pure logic, unit-tested. Pawn string parser, score, comparison choice (rings, trinkets,
  2H), set count rules, verdict and reasons from item descriptors.
- `Modules/Gear/Items.lua`: WoW API. Builds an item descriptor from a link (stats, ilvl, slot, armor subclass,
  sockets, gems, enchant, setID, upgrade info, uniqueness, effect flags, spec usability), and keeps a snapshot of
  equipped descriptors, rebuilt on `PLAYER_EQUIPMENT_CHANGED` and spec change.
- `Modules/Gear/Gear.lua`: module registration, tooltip hook, Baganator plugin, import dialog, options, commands.

Descriptor shape (what Data.lua sees):

```lua
{ link, itemID, equipLoc, classID, subclassID, ilvl, stats = { HASTE = 210, AGILITY = 560, ... },
  sockets = 1, gems = { gemLink... }, enchanted = true, setID = 1234, uniqueCategory = 42, uniqueMax = 2,
  effects = { use = true, equip = false, proc = false }, upgrade = { cur = 2, max = 6, maxIlvl = 308, track = "Champion" },
  usable = true }
```

## Options (Tomte panel, category "Gear", module key `gear`, on by default)

- Show reasons (default on).
- Show on comparison tooltips (default off: the main tooltip already has the verdict).
- Show downgrades (default on).
- Mark upgrades in Baganator (default on, only listed when Baganator is loaded).
- Button: "Import weights for <spec>" (opens the paste dialog). Status line: "Weights: Raidbots BM (imported) /
  none".
- Commands: `/tomte gear import`, `/tomte gear weights` (show current), `/tomte gear clear`, `/tomte gear help`.

Weights are saved per character and spec (`db.weights[guid][specID]`).

## In-game checks before relying on them

1. `/dump C_Item.GetItemStats(link)`: keys and whether gem or enchant stats are included.
2. `/dump C_Item.GetItemUniqueness(link)` on an embellished item: is there a category?
3. `/dump C_LootJournal.GetItemSets(classID, specID)`: is the current tier first by itemLevel?
4. `/dump C_Item.GetItemUpgradeInfo(link)` on a track item.
5. One tooltip with an effect: line types 44 to 46 present.

## Testing

`lua Tomte/tests/test_gear.lua` for Data.lua (parser, score, ring/trinket/2H choice, set counts, every verdict).
In game: hover gear in the bags, check against the five checks above, a tier piece vs. a non-set item, a trinket, a
wrong-armor item, a ring pair, Baganator arrows.

## Changes during the build (2026-10-03)

- **Stat mix rule** (after Raidbots' "Beware of stat weights"): within 4 ilvl, a difference between 1% and 3% is
  a **Sidegrade** with "Same level, different stats: sim to be sure". Weights flap exactly here, so these never get a
  bag arrow.
- **Headlines say what to do**:
  - "Upgrade +2.4%: equip it"
  - "Downgrade -3.2%: keep yours"
  - "Sidegrade: either is fine"
  - "Can't judge (stats alone ...)" with "check with /tomte gear sim"
  `/tomte gear sim` prints the Raidbots Top Gear steps, since the user doesn't use Raidbots yet.
- **Enchants are information, not a warning.** Re-enchanting is routine, and as a warning it would have blocked the
  bag arrow on every upgrade for an enchantable slot.
- **"Replaces your two-hander"** has no %. A single hand against a two-hander is always lower, which says nothing.
- **No "(no weights)" line in the tooltip.** It would show on every tooltip for a user without weights.
  `/tomte gear weights` and the option tooltip explain it instead.
- **Not for you** also uses any red tooltip line (class, weapon type, level, profession; durability excluded).
  Spec usability comes from `C_Item.GetItemSpecInfo` (nil or empty means everyone).
- Gem and enchant fields are read from the item string (`Gear_LinkInfo`). Item stats are read from the stripped
  link. Socketed gem stats come from `GemSocketEnchantment` tooltip lines.
