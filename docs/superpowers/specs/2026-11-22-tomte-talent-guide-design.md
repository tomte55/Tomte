# Talent guide (World of Warcraft: Forever)

2026-11-22. A small module, Forever only.

## Why

The user levels a mage without knowing the class. A talent build from a guide site, with its point order, should be
something you paste once and then follow in the talent window: the next talent to take is marked, so you never have
to look the guide up again while levelling.

## Goals

- Paste a build string from Method's Forever talent calculator ("Export String"). The string carries the finished
  build and, when the build was clicked out in order, the order of all points.
- Builds are saved per class (account wide), so alts of that class can use them; each character picks one.
- With the talent window open: the next talent of the build is marked; talents you put points in that the build
  doesn't have are marked as off the build; a line at the bottom says the build and the step.
- Leveling's "Talent points to spend" toast names the next talent.

## Non-goals and anti-goals

- No builds shipped with Tomte. Method's guide builds are their work ("All rights reserved"); the repo is public.
  A "Find a build" button gives the guide and calculator links instead.
- Tomte never spends points: the player clicks the talent and Apply Changes.
- No reasons per talent (the user dropped this).
- Not retail: retail has Blizzard's own loadout import.

## Approaches

1. **Paste Method's export string (picked).** Method's calculator records the click order and exports it after the
   loadout (`<loadout>;<order>`). Exact, works for any class and build, one paste per build.
2. Tomte ships hand-made builds per class: rejected, nobody here knows the classes and copying guides is out.
3. Record your own picks and replay them on alts: no help for a class you never played.

## The string (read from Method's ForeverTalents.min.js, data version 1.60.1)

- `<loadout>[;<order>]`, characters `A-Z a-z 0-9 + /` (values 0..63).
- Loadout: Blizzard's loadout serialization: 6 bits per character, least significant bits first. Header: version
  8 bits (Method writes 2), an ID 16 bits that names the class (Method's table: Mage 1482, Druid 1484, Hunter 1485,
  Paladin 1486, Priest 1487, Rogue 1488, Shaman 1489, Warlock 1490, Warrior 1491), tree hash 16 x 8 bits (zeros).
  Then per talent node of the class tree, **sorted by node ID**: selected (1); if selected: purchased (1); if
  purchased: partially ranked (1), and if so rank (6), else the node's max rank; choice node (1), and if so the
  choice index (2).
- Order: one character per point, its value the index (0-based) into the same sorted node list. At most 51.
- Node IDs are the game's trait node IDs (Method's data: mage tree 1112, 53 nodes, IDs 105762 to 113627, three
  groups 11582/11594/11601 for Arcane, Fire, Frost). Every class tree has 50 to 54 nodes and no choice nodes.

## Design

- `Modules/TalentGuide/Data.lua` (pure, tested): decode against a sorted node list, check the order fits the ranks,
  the next step against current ranks, nodes off the build, points per tree ("18/0/33"), the build's name.
- `Read.lua`: the class tree from the game: `C_ClassTalents.GetActiveConfigID`, `C_Traits.GetConfigInfo().treeIDs`,
  `C_Traits.GetGroupDisplayInfoByTreeID` (the three trees, by `orderIndex`), `C_Traits.GetTreeNodes`,
  `C_Traits.GetNodeInfo` (`ranksPurchased`, `maxRanks`, `groupIDs`, `entryIDs`; staged ranks count).
- `Marker.lua`: marks on `PlayerSpellsFrame.TalentsFrame` (`GetTalentButtonByNodeID`, `GetConfigID`), our own frames
  anchored to Blizzard's buttons, refreshed on the frame's show and `TRAIT_NODE_CHANGED` /
  `TRAIT_CONFIG_UPDATED` / `TRAIT_TREE_CURRENCY_INFO_UPDATED` while it's shown.
- `TalentGuide.lua`: db, settings (paste, pick, forget, find a build, marks on/off), commands, the toast text.
- The string is rejected with a reason when it isn't Method's format, is another class's build, or doesn't fit the
  tree (the in-game node list differs from Method's: the first in-game test).

## Left to check in game

- `C_Traits.GetTreeNodes` lists the same nodes Method does (`/tomte talentguide scan`).
- `ranksPurchased` includes points placed but not yet applied.
