# Tomte: Gold & value

Date: 2026-10-06. Agreed with the user: choices are settings with defaults rather than fixed decisions. Auctionator is the price source (it's installed; TSM isn't supported).

## Goal

Tomte only knows vendor prices today (Upkeep's junk value). With Auctionator's price data the addon can say what
things are worth:

- **Sessions / Recap**: the value of everything looted and gathered this session, not just the gold.
- **Alts**: what each character carries in bags and bank, and the account total.
- **Crafting planner**: what a craft costs in materials and what the result sells for.

The user's main gathers (Herbalism + Mining), so "what did this farm earn" is the main use.

## Price source (Core/Price.lua)

`ns.Price(itemLinkOrID)` returns `copper, source` with `source` "auction" | "vendor" | nil.

- Auctionator v1 API (verified in Auctionator's current source, version 321):
  `Auctionator.API.v1.GetAuctionPriceByItemLink("Tomte", link)` (item level aware when the item is cached),
  `GetAuctionPriceByItemID("Tomte", id)`, `GetVendorPriceByItemID`, `GetAuctionAgeByItemID` (days since seen, nil
  after 21). All return copper or nil, also nil before Auctionator's database is ready. The callerID must be a
  non-empty string.
- Fallback: vendor sell price from `C_Item.GetItemInfo` (what Upkeep uses today).
- Guarded with `Auctionator and Auctionator.API and Auctionator.API.v1`; module `uses = { Auctionator: "auction
  prices" }`, so the module page shows it green or red.
- Prices older than 7 days (`GetAuctionAgeByItemID`) are marked stale (grey "?").
- `RegisterForDBUpdate("Tomte", fn)` refreshes open pages after an AH scan.

## Loot value in the session

Recap's tracker (Recap/Track.lua) already parses loot for items at `lootQuality` and above. New: every looted
item (any quality, gathering included) adds `count * price` to `session.value[category]`, priced **at loot time**
(the session remembers what it was worth that day). Categories: gathered (reagents: Tradeskill item class), gear,
other. The parse reads `CHAT_MSG_LOOT`; per the 12.1 API docs it isn't one of the chat events that go secret in
lockdown, but each value is still checked with `issecretvalue` and skipped if secret.

Recap card and Sessions page: "Gold +1 240g · Loot worth 3 860g (gathered 3 200g)".

## Alts: carried value

Per character: bags + bank + mail value, and the Warband bank once. Read from Syndicator when it's there (the
inventory lists per character; exact API to verify in Syndicator's source before building), else only the current
character from `C_Container`. Soulbound items count as vendor price. Shown as a column in the roster (detailed
view) and "Account worth" next to total gold.

## Crafting planner

Each material row gets a unit price and a total; the plan gets "Materials ~X", "Sells for ~Y" (the output item's
auction price), "Profit ~Y-X". Materials you already have still count at market price (opportunity cost); a toggle
"count owned materials as free".

## Options (module "Gold & value", category General)

| Setting | Choices | Default |
|---|---|---|
| Use Auctionator prices | on/off (off = vendor prices only) | on |
| Count loot value in sessions | on/off | on |
| Price loot | When looted / At today's price | When looted |
| Gear and BoEs | Auction price / Vendor price / Leave out | Vendor price |
| Carried value in Alts | on/off | on |
| Owned materials in craft cost | Market price / Free | Market price |
| Stale after | 1-21 days | 7 |

## Testing

- Plain Lua: price fallback order, stale marking, value categories, profit sums.
- In game: farm for a few minutes and check the recap card; open the Crafting tab with and without Auctionator.
