# Tomte World Quests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A third world map side tab that lists the viewed map's world quests grouped and sorted by reward, with a "Worth it" section and a zone-arrival toast.

**Architecture:** Pure logic in `Modules/WorldQuests/Data.lua` (tested with plain Lua). Game reading into plain quest records in `Scan.lua`, UI in `Tab.lua`, wiring in `WorldQuests.lua`. Shared map resolution moves to `Panel/MapTabs.lua`, and Gear Check exports one verdict wrapper.

**Tech Stack:** WoW retail 12.1 Lua addon (Tomte), plain Lua 5.x for tests (`lua Tomte/tests/test_wq.lua` from the AddOns folder).

**Spec:** `docs/superpowers/specs/2026-10-04-tomte-world-quests-design.md`

## Global Constraints

- TOC `## Interface: 120100`. No new globals. Use the addon namespace `local addonName, ns = ...`.
- Never call `QuestMapFrame:SetDisplayMode`, and never call `QuestUtil.TrackWorldQuest` (it writes a Blizzard upvalue).
- No combat logic. Nothing secure, so no secure buttons.
- Tooltip redraws hide GameTooltip only when one of our rows owns it.
- No commit until the user confirms in game (CLAUDE.md).
- Defaults: `show = { pvp = false, petbattle = false, otherProfessions = false }`,
  `worth = { transmog = false, gold = false, goldAmount = 500 }`, `toast = true`, `preview = true`, and the "Other"
  section folded by default.

## Review Focus

- **Rewards still loading** (`loaded = false`, item link nil): the quest still shows, in Other with "loading…", and
  moves to its section once the data is in. Test: `classify an unloaded quest`.
- **Quest without time left** (`seconds` nil or 0): no time text, sorted after timed quests in ties, no error. Test:
  `time text edge cases`.
- **A quest with a collectible and a gear upgrade:** it shows once, in Worth it, as a collectible. Test:
  `collectible beats upgrade`.
- **Gear Check off** (`verdict` nil): Gear rows sort by ilvl and never go to Worth it. Test: `gear without verdict`.
- **Gold option on with a quest of exactly the threshold:** it counts (≥). Test: `gold threshold inclusive`.

---

### Task 1: Move ResolveMap to MapTabs

**Files:**
- Modify: `Tomte/Panel/MapTabs.lua` (add `ns.MapTabs_ResolveMap`)
- Modify: `Tomte/Modules/Collect/Catalog.lua:171-190` (remove `ns.Collect_ResolveMap`, call `ns.MapTabs_ResolveMap`, drop `MAX_DEPTH` if unused)

**Interfaces:** Produces `ns.MapTabs_ResolveMap(mapID) -> mapID, info, "zone"|"continent"` or nil. The code is the
same as the old `Collect_ResolveMap`.

- [ ] Move the function with its comment. Replace the two call sites in Catalog.lua.
- [ ] Run `lua Tomte/tests/test_collect.lua` and `lua Tomte/tests/test_teleports.lua`. Expected: all ok.

### Task 2: Gear verdict export

**Files:** Modify `Tomte/Modules/Gear/Gear.lua` (after the local `Evaluate`).

**Interfaces:** Produces `ns.Gear_Verdict(link) -> verdict | nil, headline, colorKey`, where `verdict` is
`ns.Gear_Evaluate`'s table (`kind`, `pct`, …). It returns nil when the module isn't active, items are loading, the
link is worn, or there's no spec.

```lua
function ns.Gear_Verdict(link)
	if not (module and module.active) then
		return nil
	end
	local v = Evaluate(link)
	if not v then
		return nil
	end
	return v, ns.Gear_Headline(v)
end
```

- [ ] Add it. Run `lua Tomte/tests/test_gear.lua`. Expected: ok (no behavior change).

### Task 3: Data.lua (pure logic, TDD)

**Files:** Create `Tomte/Modules/WorldQuests/Data.lua`. Test: `Tomte/tests/test_wq.lua`.

**Interfaces (produced):**
- `ns.WQ_FormatGold(copper) -> "1,250g"`: floors to gold, thousands separators, and "<1g" for under 1 gold.
- `ns.WQ_TimeText(seconds) -> text, tier` where tier is `"critical"` (≤900 s), `"low"` (≤4500 s), `"normal"`, or
  nil for nil/≤0. Text is "45m", "3h 20m" or "1d 4h".
- `ns.WQ_Filter(q, opts) -> bool`, opts = `{ show = { pvp, petbattle, otherProfessions }, maxLevel = bool }`. False
  for hidden types, for a profession quest with `knownSkill == false` unless `otherProfessions`, and at max level for
  a loaded quest whose only reward is XP.
- `ns.WQ_Classify(q, opts) -> section, sortKey, reason`, opts adds `worth = { transmog, gold, goldAmount }`.
  - section: `"worth"|"gear"|"gold"|"currency"|"rep"|"other"`.
  - reason, Worth it only: `"collectible"|"upgrade"|"appearance"|"gold"`.
  - sortKey is a table compared by `ns.WQ_Less`.
- `ns.WQ_Sections(quests, opts) -> { { key, title, quests, collapsed } }` in the fixed order, without empty sections.
  Each quest gets `q.section`, `q.reason` and `q.dim`.
- `ns.WQ_RewardText(q) -> main, secondary`.
- `ns.WQ_Tags(q) -> "Elite · Dungeon"`.
- `ns.WQ_ToastText(zoneName, list) -> title, text`.

Steps:
- [ ] Write `tests/test_wq.lua` with the cases named in Review Focus plus: filter by type and profession, XP-only
  below max level → other, each main-reward section, the transmog and gold rules off by default, Worth it sort
  (collectible > upgrade by pct > appearance > gold), gear sort (verdict pct, then ilvl, no-verdict last),
  currency grouping, capped and max-renown dim-last, time ties, gold format, reward text, tags, toast text.
- [ ] Run it. Expected: FAIL (Data.lua missing).
- [ ] Implement Data.lua.
- [ ] Run it. Expected: all ok.

### Task 4: Scan.lua (game reading)

**Files:** Create `Tomte/Modules/WorldQuests/Scan.lua`.

**Interfaces:**
- Consumes `ns.MapTabs_ResolveMap` and `ns.Gear_Verdict`.
- Produces:
  - `ns.WQ_ForMap(viewedMapID) -> quests, mapName, kind, mapID, pending`. On a world/cosmic map or no map:
    `nil`.
  - `ns.WQ_Forget(questID)` and `ns.WQ_ClearCache()`.
  - `ns.WQ_ReadQuest(questID, zoneID) -> record`, for tests in game.

Behavior:
- **Zone:** `GetQuestsOnMap(zone)`. Keep `IsWorldQuest` and not completed. Keep a quest only when its
  `GetQuestZoneID` resolves to this zone; unknown keeps it.
- **Continent:** each `GetMapChildrenInfo(id, Zone, true)` child, deduped by questID, with the zone from the child.
- **Record:**
  - Tag info goes into the record's type keys. `knownSkill` is checked against `GetProfessions()` skill lines.
  - Rewards are cached per questID once `loaded` is true and every item has its link and verdict state; a quest
    that's still loading is read again on every call.
  - Collectible checks and appearance per item; verdict for gear only when Gear is active (nil otherwise).
  - Currency caps from `C_CurrencyInfo.GetCurrencyInfo`. Rep from the major faction rewards plus rep currencies.
- **Time:** time left is read fresh on every call (not cached).

- [ ] Write it. Check every call against the spec's Data section.

### Task 5: Tab.lua

**Files:** Create `Tomte/Modules/WorldQuests/Tab.lua` (pattern: `Modules/Collect/Tab.lua`).

**Interfaces:**
- Consumes `ns.MapTabs_Add`, `ns.WQ_ForMap`, `ns.WQ_Sections`, `ns.WQ_RewardText`, `ns.WQ_Tags`, `ns.WQ_TimeText`
  and `ns.ModelPreview_*`.
- Produces `ns.WQTab_Init(db)`, `ns.WQTab_SetEnabled(bool)`, `ns.WQTab_IsShown()`, `ns.WQTab_Refresh()` and
  `ns.WQTab_Open()`.

- [ ] Rows, folding headers and tooltip: `SetQuestLogItem` for an item main reward, text otherwise.
- [ ] Ping on hover (zone view). Clicks: track/untrack, right-click zoom/untrack, shift link. Model preview.
- [ ] OnUpdate redraw while pending. OnShow redraw.

### Task 6: WorldQuests.lua + TOC

**Files:** Create `Tomte/Modules/WorldQuests/WorldQuests.lua`. Modify `Tomte/Tomte.toc` (4 files after Collect).

- [ ] Register the module (`key = "wq"`, name "World quests", category "World", enabled by default) with the
  defaults above.
- [ ] Events per the spec, debounced. The zone toast with retries.
- [ ] Options, and the commands `open` / `here` / `test`.
- [ ] Run every `tests/test_*.lua`. Expected: all ok. Byte-compile all new files with `luac -p` if available.

### Task 7: Review

- [ ] One whole-diff review against the spec (requesting-code-review), fix findings, re-run tests.
- [ ] Hand the user the in-game checklist. No commit.
