# Tomte: Upgrade reveal

Date: 2026-10-04. Decisions made autonomously (the user delegated them); the user picks changes after testing in game.

## Goal

When gear that is new to your bags is a clean upgrade by Gear Check's rules, celebrate it with a Moments reveal
and offer a one-click equip.

## Decisions

- **Lives in Gear Check** (`Modules/Gear/Reveal.lua`, part of the `gear` module). Gear Check owns the verdict; Moments
  only presents it. The presentation is a new Moments type **Gear upgrade** (`upgrade`, default style cinematic),
  so it follows the same off/banner/cinematic choice, idle wait and 10 s banner fallback as every other moment.
- **What counts as new**: an item GUID (`C_Item.GetItemGUID`) not seen in the bags or worn since login. Covers loot,
  quest rewards, the Great Vault, mail (AH, crafting orders) and trades without listening to chat (chat is secret in
  many 12.x contexts). Items swapped off your body are known (worn items are noted on `PLAYER_EQUIPMENT_CHANGED`).
- **Not new**: anything during the first 8 s after login or a loading screen (bags fill in), and anything that
  arrives while a bank, guild bank, warband bank or void storage is open (`PLAYER_INTERACTION_MANAGER_FRAME_SHOW`).
- **What gets revealed**: `Gear_IsCleanUpgrade` verdicts only (upgrade or empty slot), at least
  `revealMinPct` (default 2 %, empty slots always count), the best one per target slot, biggest first, at most 3 at
  once. "Upgrade, but", sim-it (trinkets, effects), sidegrades and off-spec upgrades are not revealed.
- **Tier** comes from item quality: green and below common, blue rare, purple epic, orange and up legendary. The tier
  drives the existing reveal effects (rays, flips, sparkles, sounds).
- **Visual**: the reveal stage shows a big item icon framed in the quality color instead of a creature model. It pops
  in, flips in for rare and up (whole turns, always ends facing the camera) and floats. Top card: "Upgrade +4.2%",
  item name, "Item level 684, replaces Old Helm (671)"; bottom line: the first verdict note (e.g. "Completes your
  4-set").
- **Equip**: a toast (shared toast stack) "click to equip, right-click to dismiss", held during cinematics and combat,
  30 s. The click re-finds the item by GUID, judges it again for the current target slot (rings: the weaker one) and
  equips via `C_Container.PickupContainerItem` + `EquipCursorItem`. Blizzard's bind-on-equip popup still asks. In
  combat it only prints a line.
- **Options** (Gear Check > Upgrade reveal): Reveal new upgrades, Smallest upgrade (0-10 %), Equip toast. The style is
  set under Moments > Gear upgrade.
- **Commands**: `/tomte gear upgrades` reveals the clean upgrades already in your bags (also the way to test the full
  flow). `/tomte moments preview upgrade [tier]` shows the visual with a worn item.

## Out of scope

Off-spec upgrade reveals, reveal of "upgrade, but" items, rolling/need-greed hints, items in the bank.
