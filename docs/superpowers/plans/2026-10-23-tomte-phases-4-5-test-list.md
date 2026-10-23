# Phases 4 and 5: in-game test list

`/reload` first (a full client restart isn't needed: no new media). Keep BugSack open throughout; paste any stack
with its locals. Settings are in the Tomte window; new modules are under the group named.

## New modules

**Tooltip extras** (Interface, on)
1. Five switches in its settings; the header warns about Plumber if it's loaded (Plumber's tooltip lines would double).
2. Reputation token (an old insignia/commendation, or a delve companion experience chunk): faction, standing, "maxed" when capped.
3. Combine item (a Fractured Spark or similar): "Reagents" with have/need and "You have enough for N".
4. A vendor token in the bags (Sizzling Cinderpollen, Firelight Ruby, Vile Essence...): "Spend at <NPC>, <zone>". Ctrl-click it in Blizzard's bags and in Baganator: one chat line, a map pin.
5. Link such an item in chat and click the link: the lines appear on the link's tooltip.
6. In a delve, hover a Bountiful Coffer: the key line with your count.
7. Any choice window with item rewards: a "You have" strip under it.

**Nameplates** (Interface, off: turn it on)
1. Open world, enemy plates on: quest mobs get an icon with "3/8"; kills update it; other mobs nothing.
2. Fight quest mobs: no errors; updates after combat. In a dungeon or delve: nothing at all.
3. Interact key with target icons on: the herb/ore/chest name under its icon, a cast bar while gathering. "Also for characters" for NPCs.
4. `/tomte plates why` on a target. Size, switches, module off and on again.

**Drawers** (Interface, off: turn it on)
1. Editor (Edit on the Drawer 1 card, or `/tomte drawers edit`): drag in a bag item, a spell, a mount, a toy; shift-click an item into the box; type a name; type `99999999` ("Not found.", no error). Up/down/remove.
2. The button appears; click opens the row. Each entry works with one mouse click (mount entry especially). "Close after use" on and off.
3. Bind "Open drawer 1": one press opens, the next closes. All of it in combat too, plus an edit made in combat applies after combat. Look for ADDON_ACTION_BLOCKED.
4. Two drawers: opening one closes the other. Directions, buttons per line, names, size.
5. Edit Mode moves them and the spot survives `/reload`. Pet battle / vehicle hides them.
6. Turn a drawer off, press its key, turn it back on: it shows closed. Module off in combat: they vanish after combat.

**Expansion summary** (Your week, on)
1. Rail entry and tooltip. Page: vault rows, crests, raid kills, renown factions (tooltips), this week's activities; two columns wide, one narrow. With everything done: "Everything tracked is done this week."
2. Minimap button (turn it on under Minimap buttons): tooltip, click opens/closes the page.

**Prey** (Quests, on, Midnight characters only)
1. Page with no hunt: "No hunt active", this week per difficulty, targets defeated. `/tomte prey status` and `/tomte data` (look for `!` lines; paste the prey lines).
2. Hunt Table in Silvermoon: difficulty labels and dots under the pins, tooltip lines; off switch hides them.
3. Active hunt: target, zone and trail; Set waypoint / `/tomte prey way`. Clicking Blizzard's hunt icon at the final stage sets a waypoint; clicking the prey quest in the tracker or quest log doesn't.
4. Does the weekly hunt count reset after the weekly reset?

## Additions to existing modules

**Gear Check**
1. Settings: "Upgrades and gems" card; under Bags, "Stronger quality border" (off) and "Clean Up Bags order".
2. Upgrade NPC: the character pane opens beside it and closes when you leave (stays if you had it open). Then in combat press C, B, Esc: no blocked action.
3. Socket an item with gems in your bags: the strip, BEST marked, click puts it in the socket, then Apply. No gems: "No gems in your bags fit."
4. Quality border on Blizzard's bags (rare+), dims with bag search, off removes it.
5. Sort order: Right to left, Clean Up; "Don't change" restores the game's setting. Gear Check off + change the order: no error.

**Dressing room**
1. Catalyst: name and "New look"/"Look collected" under the result; Ctrl-click tries it on (closed and open dressing room), Shift-click links. Do the result slot's clicks still respond?
2. Outfits button (4th button) lists saved outfits and dresses the model.
3. `/tomte dressup outfit`, with a name, at the transmogrifier, an ambiguous name, a transmog outfit name.
4. After 1 and 3 opened the dressing room: does its Link > Copy still work (taint check)?
5. Transmogrifier: change slots (a weapon, split shoulders), close without applying, reopen: "Restore last changes" brings them back; Apply works.
6. Ensemble tooltips: "N of M appearances collected".
7. Character pane Titles: search, Owned / Missing / All, click sets the title, mouse wheel scrolls our list; switch off brings Blizzard's back.

**Delves**
1. Midnight open world: the page shows the journey bar and "Gilded Stash: n/4 this week"; inside a delve it shows "as last seen in the open world".
2. Restored Coffer Key and shard tooltips: this week's caps and the next key; check the cap isn't listed twice.
3. Auto-pick powers (on, off by default): a single-option power picks once, chat says so, the window closes. `/tomte delves powers` with several options; a name in "Preferred powers" gets picked.

**Rogue Poisons: Handy Lockpick** (rogue or Mechagnome, off by default)
1. Hover a locked lockbox: highlight and "Right-click: Pick Lock"; right-click picks it, also facing a mailbox/chair. Drag still works. At a vendor/bank/mailbox: no overlay. Baganator bags. Trade window "will not be traded" slot. Combat hides it, no blocked action.

**Group Alerts**: a party invite and a guild invite from a friend/guildmate show level, class, guild; the line goes with the popup.

**Chat Tabs** (module must be on): right-click a tab with Trade/General: "Leave ..." entries work.

**Session recap**: break reminder at 30 min: a toast out of combat and instances, not again after `/reload`.

**Vendor Helper**
1. An item you can't afford in one of two costs: only the missing cost is red; page turns; setting off.
2. A non-refundable purchase: Yes greyed about a second; No/Esc work at once; no taint.

**Material uses**: Professions book (K) with unspent knowledge: "N knowledge to spend" under each profession and on the button tooltips; updates when spent; check placement.

**Fishing**: Underlight Angler artifact window shows its traits and lines.

**Gathering: seeds** (Midnight herbalist, off by default): plant a Resilient Seed from the bags next to Rich Soil once ("learned a Rich Soil spot"), `/tomte gather soil` (send me the object ID). Then pointing at soil shows the buttons; one click plants; gone in combat.

**Housing decor**
1. Search finds decor by achievement/currency names; switch off.
2. Banana in the preview: where does it land (beside, inside, floating)? Size in bananas.
3. House editor: hover info in decorate mode; clock above the mode bar (tooltip times); Alt places another (on; watch for ADDON_ACTION_BLOCKED; dyed decor; 0 in storage).
4. Customize mode: right-click copies dyes (a right-drag doesn't), Paste dyes previews, Blizzard's Apply saves.
5. Houses window (Decor page or `/tomte decor houses`): teleport, Return while visiting, closes in combat, Esc closes. Teleport home key binding.
6. Click a "decor acquired" alert: preview opens.
7. Decor off and on mid-session, also in combat.

**Waypoints**
1. Open the map in the open world: rings from your arrow (none in a dungeon); setting off. Then M in combat: no blocked action.
2. Super-track a world quest: countdown in the footer and on the card (Classic and Minimal).
3. Bind the focus next/previous keys: they cycle tracked quests, also in combat; check the objective tracker for blocked actions after.
4. `/way 45 60 My spot` names the pin.

**Collect here**: Mount Journal and Housing catalog: an achievement source is accent colored; hover tooltip, click opens it, Shift-click links; the decor model still rotates; setting off restores the text.

**Gold & value**: open the bags: crests left of the currency bar (or the gold line); `/tomte value track` + shift-click an item adds it; right-click removes; combined and separate bags; nothing with Baganator; module off hides it.

Finally: `/console loadDeprecationFallbacks 0`, `/reload`, and a quick pass over the above for errors.
