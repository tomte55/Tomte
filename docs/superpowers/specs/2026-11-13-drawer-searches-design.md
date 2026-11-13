# Drawer searches (and Eat and drink removed)

2026-11-13. Short design, agreed in conversation.

## Why

Eat and drink (Forever) couldn't work well: Forever hides health and mana from addons, so its one button always
ate and drank, even at full health. The player wants a drawer of drinks that give mana and one of food that heals,
kept up to date from the bags without editing it by hand.

## Approaches

- **A. Search rows (picked).** A drawer entry can be a bag search in the Bags search language (`is:drink`). The
  drawer fills that place with every matching item in the bags, best first. Flexible, one parser for the addon.
- B. Fixed picks (Food, Drink, Bandages, Potions) from a dropdown. Easier, but closed.
- C. A plus quick buttons that insert a search. Possible later if typing turns out to be a chore.

## Design

- Entry `{ kind = "search", text = "is:drink" }` next to item/spell/mount/toy entries. Saved like the others; no
  migration (a new kind in an existing list).
- Typed text with search marks (`:`, comparisons, `|`, parentheses, quotes, leading `-`) is a search; a plain word
  is looked up as a name first, and becomes a search of names when nothing is called that.
- Expansion (pure, `Drawers_Expand`): each search is replaced in place by the items it finds; an item shows once,
  where it first comes; 24 buttons at most. Order (`Drawers_SortFound`): plain food before buff food, then required
  level, item level, name.
- Items above the player's level are left out. Bag-slot-only fields (markers, new, upgrade) don't match in drawers.
- New search words for bags and drawers: `is:eat`, `is:drink`, `is:bandage`, from the spell the item casts (Food,
  Drink, First Aid; `ns.ConsumableKind` in Core). `is:food` keeps meaning "food and drink".
- Drawer buttons are secure: a search drawer refills on `BAG_UPDATE_DELAYED` out of combat; in combat it waits for
  combat to end.
- Eat and drink is removed: module, key binding, README row; migration 21 drops `TomteDB.rest` and its switch.
