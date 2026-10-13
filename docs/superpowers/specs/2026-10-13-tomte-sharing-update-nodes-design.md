# Tomte: Friend sharing round 2 (update notice, gathering nodes)

Date: 2026-10-13. Status: decisions delegated to Claude by the user ("you make decisions, we can revise later").
Builds on `2026-10-13-tomte-friend-sharing-design.md` (the hello/request/chunk backbone). Items 1 and 2 of
"Wanted next" in `future-ideas.md`.

## 1. Update notice

**Goal:** when a friend runs a newer Tomte, you hear about it once and can grab the link.

- The hello already carries the friend's Tomte version (`row.version`). A pure `ns.Share_NewerVersion(a, b)` in
  `Protocol.lua` compares dotted numeric versions ("1.12.0" > "1.11.3"; missing parts count as 0; anything
  non-numeric, like "?" from a dev checkout, never counts as newer, so nobody is nagged by odd strings).
- When a hello brings a version newer than ours and newer than `db.toldVersion`: a toast "Kalle runs Tomte
  v1.12.0, you have v1.11.0. Click for the download link." and one chat line. Click opens the copy dialog
  (`ns.Dialog_Show`, read-only) with `https://github.com/tomte55/Tomte/releases/latest`. `db.toldVersion` is set,
  so each new version is told once (not every login). Not gated by the "toast for new data" setting: it's rare.
- The Friend sharing page shows a strip at the top while any friend seen runs a newer version than ours:
  "A newer Tomte is out: v1.12.0 (Kalle has it)" and a "Get link" button (same dialog). It goes away by itself
  once you update.
- `/tomte share list` already shows versions.

## 2. Gathering nodes

**Goal:** Gathering remembers where you mined and picked herbs, shows those spots on the world map, and pools them
with friends through Friend sharing. A base to grow later (minimap pins, routes).

### Recording (Gathering module)

- On a committed gather (Detect.lua) of kind `mining` or `herbalism` the position is read with
  `C_Map.GetPlayerMapPosition(mapID, "player")` (nil in instances: then nothing is recorded; x, y checked with
  `ns.IsSecret`). The player is next to the node when the loot window opens, so that's the node's spot.
- Skinning (corpses) and fishing (pools move) are not recorded.
- The node type is the GameObject ID from the loot source GUID (already parsed). Its name comes from the cast
  target (already read), and its main item is the first loot slot whose item kind matches the gather kind; the
  item's icon is the pin's icon (Bismuth ore on a Bismuth node).
- Recording is its own setting ("Remember node spots", on), independent of runs: it records even when automatic
  runs are off.

### Saved data (`TomteDB.gather`)

```lua
nodes = {},     -- [uiMapID] = { [pos] = objectID or "m"/"h" }, pos = x * 10000 + y with x, y in 0..9999
nodeTypes = {}, -- [objectID] = { kind = "mining", name = "Bismuth", item = 210930 }
```

`pos` packs the position in 1/10000 of the map (well under a yard in a zone). The value is the node's object ID, or
the kind letter when no source GUID was readable. Both tables are collections (kept by Reset settings), and
`noShare` leaves them out of profile strings (they can be large).

### Duplicates (pure, `Modules/Gather/Nodes.lua`)

- Two spots on the same map within `MERGE_YARDS` (10) of each other, of the same kind, are one node: the one
  already there stays (your own spots win over a friend's, as with flight times). Yards come from
  `C_Map.GetMapWorldSize(mapID)`; when that's 0/nil a fallback of 0.2% of the map is used.
- Lookups use a grid of 10-yard cells per map (built lazily, kept until the map's nodes change), so importing
  thousands of spots checks only the 9 cells around each one.

### The data set (`Nodes.lua`, pure)

- Registered by Gathering's init with `ns.Share_Register` as key `nodes`, label "Gathering nodes";
  `active = function() return module.active end` (new optional field: a set whose module is off isn't offered).
- **Payload**: node types first, then one entry per map, all sorted:
  `t<objectID>=<m|h>:<itemID or empty>:<name>;` and `n<mapID>:<pos>=<objectID|m|h>,<pos>=...;`
  Names are cut to 60 bytes with `;`, `,`, `:`, `=`, `^` and `|` removed (a name is display text only).
- **Import** parses everything first and rejects the whole payload if anything is malformed: unknown kind letter,
  `pos` outside 0..99999999 or with x or y over 9999, a map or object ID not a positive integer, a node naming an
  object ID with no type in the payload or in your data, more than 50000 nodes. Then node types are filled in where
  missing (yours win), and each spot is added unless it merges with one already there. Returns the added count.
- **Revision**: djb2 over the sorted `map:pos` keys, like flight times.

### Friend sharing change: don't ask twice for the same revision

Merging means two installs can keep different revisions forever (my spot and your spot 3 yards apart are one
node, but different keys), so every hello would request a transfer that adds nothing. Fix in Share.lua: after a
successful import the friend's revision is saved (`friends[tag].sets[key].rev`), and a hello whose revision equals
the saved one sends no request. This also saves traffic for flight times. Side effect, answering the open
question from round 1: after "Reset recorded flight times", friends' unchanged data is not asked for again, so a
reset sticks until a friend's data actually changes.

### World map pins (`Modules/Gather/MapPins.lua`)

- Plain textures in frames on `WorldMapFrame:GetCanvas()` (no data provider, no Blizzard pin pools: taint), at
  the frame level Blizzard uses for dig sites (`GetPinFrameLevelsManager():GetValidFrameLevel(
  "PIN_FRAME_LEVEL_DIG_SITE")`): above the map art and fog, under quests and points of interest.
- Redrawn on `OnMapChanged` and `OnShow`; resized on `OnCanvasScaleChanged` and `OnCanvasSizeChanged`
  (hooksecurefunc: the hooks do nothing while Gathering or the pins setting is off).
- Pin: 16 px on screen at any zoom, the item icon (or the profession icon) clipped round, a thin dark ring.
  Hover: tooltip with the node name, the profession and the item ("Bismuth ore"). Clicks pass through to the map
  (`SetMouseClickEnabled(false)`).
- Setting "Show nodes on the world map": "For your professions" (default) / "All" / "Off".
- Frames come from a pool, so hundreds of spots don't create new frames each time the map changes.

### Settings and commands

Gathering, new header "Nodes": "Remember node spots" (checkbox), "Show nodes on the world map" (dropdown), a
"Forget node spots" button (confirm) with the count. Friend sharing: "Gathering nodes" checkbox (`sets.nodes`, on).
`/tomte gather nodes`: how many spots per kind on the map you're in and in total.

## 3. Mixed runs (added by the user mid-build)

A character with mining and herbalism usually does both on one run, which used to be called after whichever kind
had more nodes. Now `ns.Gather_RunKinds(run)` lists the biggest kind plus every other kind with at least 2 nodes
and a fifth of the run's nodes; with two or more the run's main kind is `"mixed"`.
- Title: "Mining & Herbalism run" (biggest first) on the tracker, toast, Home line and run detail.
- Icon: the biggest kind's.
- Runs table Kind column and zone stats: "Mixed" (the column is too narrow for both names).
- The page's kind filter already shows a run under every kind it has nodes of, so a mixed run is under both.
- A herbalist who taps one ore vein on the way is still on a Herbalism run.

## As built: map button (2026-10-13, after the first in-game test)

A round button in the world map's top-right column (Blizzard's look: dark disc, mining icon, gold tracking ring).
Left-click opens a menu: which nodes to show (For your professions / All / Off), Remember node spots, Gathering page,
Settings. Right-click turns the pins off and back on to the last choice (`mapPinsOn`). Greyed icon while pins are
off. When an addon has loaded Krowi_WorldMapButtons (RareScanner embeds it), the button is added through that
library's API so it stacks under theirs; otherwise it sits below Blizzard's two buttons. Built on the first map
open, so it lands below buttons other addons add at login. Setting "Button on the world map" (`mapButton`).

## Testing

Unit (plain Lua): `tests/test_gather_nodes.lua` (pack/unpack, record + merge radius, kinds kept apart, export
deterministic, import round trip, fill gaps, rejection rules, revision, two installs converge, relay A→B→C, grid
lookup equals a full scan); `tests/test_share_protocol.lua` gets version comparison cases.

In game (user):
1. `/reload`, mine or pick a few nodes, open the world map: an icon on each spot, tooltip with the node's name.
2. Zoom the map in and out, switch zones: pins keep their size and stay on their spots.
3. Settings: "Off" hides them, "All" shows the other profession's spots too.
4. `/tomte gather nodes` counts them.
5. With a friend: `/tomte share sync`, `/tomte share why <name>` shows `nodes` sent/received.
6. Update notice: can only be seen with a friend on a higher version (or by editing your TOC version down and
   restarting); the page strip and a toast appear once.

## Later

Minimap pins (the main thing a gatherer wants next; needs the minimap's yard radius per zoom and rotation),
showing nodes on continent maps, "last gathered" per spot, a route through a zone's nodes.
