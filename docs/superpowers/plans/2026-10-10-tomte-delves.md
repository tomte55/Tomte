# Delves Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module `delves` that shows today's bountiful delves with a click to track them, keys and shards,
the delve tier that raises the Great Vault's World slots, and the companion's level, role and curios, on a page, at
the tier picker, in Home's "Around you", in Next up and as a Moments banner.

**Architecture:**
- Pure logic sits in `Modules/Delves/Data.lua` and is unit-tested with plain Lua: bountiful detection, sorting, the
  key line, the vault plan, the tier ladder, the tier suggestion and the role hint.
- Game readers (`Scan.lua`, `Read.lua`) turn APIs into plain tables, out of combat and debounced.
- UI (`Entrance.lua`, `Page.lua`) and the module file (`Delves.lua`) only render those tables.
- Per-expansion IDs live in `Data/<Expansion>/Delves.lua` through `ns.Content_Register`.

**Tech stack:** WoW retail 12.1 Lua (5.1), Tomte's `ns.UI` toolkit and theme roles, `ns.RegisterModule`, Home entries
(`page`, `around`, `next`), `ns.SafeTrack`, `ns.Moments_Trigger`.

**Spec:** `docs/superpowers/specs/2026-10-10-tomte-delves-design.md`.

**Execution:** nothing is committed before the user has checked it in game (CLAUDE.md). Work on a branch `delves`.

## Global constraints

- Lua 5.1 syntax (CI runs 5.1): no `goto`, no `//`, no integer division operators, no `utf8`.
- No numeric colors, `|cff` literals or font paths; colors via `UI.Color(role)` / `UI.Text(parent, size, role)`.
  `tests/test_theme.lua` scans every Lua file.
- `local addonName, ns = ...` in every file; no new globals.
- One event frame per file, dispatching with `self[event](self, ...)`.
- No reads in combat: every reader returns the last cache when `InCombatLockdown()` and re-reads on
  `PLAYER_REGEN_ENABLED`.
- Map pins and super-tracking only through `ns.SafeTrack(fn)`.
- Never call `C_DelvesUI.SelectDelveEntranceTier`, `C_Traits.SetSelection` or `C_Traits.CommitConfig`; never hook or
  modify Blizzard's delve frames. Anchoring a Tomte frame to `DelvesDifficultyPickerFrame` is allowed.
- Game text is shown as the game gives it (POI names, role subtree names, curio names). Logic never matches English
  game strings.
- Defaults are safe: nothing is spent, used or changed; only display and tracking on click.
- API facts are as checked in the spec's Research summary (wow-ui-source live, 12.1.0.69933). Any API not listed
  there gets checked on warcraft.wiki.gg before use.

## Review focus

1. **No delve data for the character** (below delve level, a trial, an expansion with no `delves` table, the map API
   returning nil before the zone is loaded): page, Around you and Next up show their empty text and raise no Lua
   error. → Data test "empty inputs"; reader guards reviewed by reading.
2. **A vault with only world activities (difficulty 1) or no runs at all:** the plan unlocks slots but never claims
   one is maxed, and the advice text never says "Tier 0". → Data tests "world activities only" and "no runs".
3. **`GetNextActivitiesIncrease` without season data, or returning a level that doesn't rise:** the ladder stops and
   the fallback top tier is used, with no endless loop. → Data tests "ladder: no data" and "ladder: stuck".
4. **The season's companion belongs to another expansion** (Midnight's Valeera while the user runs War Within delves):
   Tomte falls back to the expansion's companion faction and shows level only. → Data test "season companion for
   another expansion" on `ns.Delves_PickCompanionSource`.
5. **Tracking a delve on another continent or in combat:** another continent gets a routed map pin; in combat the
   track waits for the end of combat and says so. → `ns.Delves_TrackMode` test, plus review of `Delves_Track`.

---

### Task 1: Expansion data

**Files:**
- Create: `Data/WarWithin/Delves.lua`, `Data/Midnight/Delves.lua`
- Modify: `Tomte.toc` (after `Data/Midnight/Gear.lua`), `Data/WarWithin/Weekly.lua` (add `kind`)
- Test: `tests/test_delves.lua` (created here, grown in Task 2)

**Produces:** `ns.Content_Get(expansion, "delves")` →
`{ continent, zones = {...}, bountifulPOIs = { [poi] = true } | nil, keyCurrency, shards = { items = {...} } | { currency },
shardsPerKey, companionFaction, vaultTopTier }`.

- [ ] **Step 1: Write the failing test** (`tests/test_delves.lua`):

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_delves.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/WarWithin/Delves.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Delves.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

test("delves data for both expansions", function()
	for _, e in ipairs({ 10, 11 }) do
		local d = ns.Content_Get(e, "delves")
		assert(d, "expansion " .. e)
		assert(#d.zones >= 4, "zones " .. e)
		eq(d.keyCurrency, 3028, "key currency " .. e)
		eq(d.shardsPerKey, 100, "shards per key " .. e)
		assert(d.shards.items or d.shards.currency, "shards " .. e)
		assert(d.companionFaction, "companion " .. e)
		eq(d.vaultTopTier, 8, "top tier " .. e)
	end
	eq(ns.Content_Get(10, "delves").companionFaction, 2640)
	eq(ns.Content_Get(11, "delves").companionFaction, 2744)
	eq(ns.Content_Get(11, "delves").shards.currency, 3310)
	assert(ns.Content_Get(10, "delves").bountifulPOIs[7783], "The Sinkhole bountiful")
end)

-- (Task 2 adds its tests above this line.)

if failures > 0 then
	error(failures .. " test(s) failed")
end
print("all delves tests passed")
```

- [ ] **Step 2: Run it and check that it fails**

Run (from `AddOns`): `lua Tomte/tests/test_delves.lua`
Expected: error "cannot open Tomte/Data/WarWithin/Delves.lua".

- [ ] **Step 3: Write the data**

`Data/WarWithin/Delves.lua`:

```lua
local addonName, ns = ...

-- The War Within (expansion 10): Delves data. See Core/Content.lua. Zone, POI, currency, item and faction IDs from
-- Plumber (GPLv3; IDs only, checked 2026-10-10: Modules/MapPin_Delves.lua, ExpansionLandingPage/Retail/
-- ResourceList.lua, TWW_Activity.lua). Bountiful entrances are separate POIs from the normal ones; the atlas
-- "delves-bountiful" is checked first, these IDs are the fallback.

ns.Content_Register(10, "delves", {
	continent = 2274, -- Khaz Algar
	zones = { 2248, 2214, 2215, 2255, 2346, 2371 }, -- Isle of Dorn, Ringing Deeps, Hallowfall, Azj-Kahet, Undermine, K'aresh
	bountifulPOIs = {
		[7787] = true, [7779] = true, [7781] = true, -- Earthcrawl Mines, Fungal Folly, Kriegval's Rest
		[7788] = true, [7782] = true, [8181] = true, -- The Dread Pit, The Waterworks, Excavation Site 9
		[7780] = true, [7785] = true, [7789] = true, [7783] = true, -- Mycomancer Cavern, Nightfall Sanctum, Skittering Breach, The Sinkhole
		[7784] = true, [7790] = true, [7786] = true, -- Tak-Rethan Abyss, The Spiral Weave, The Underkeep
		[8246] = true, [8273] = true, -- Sidestreet Sluice, Archival Assault
	},
	keyCurrency = 3028, -- Restored Coffer Key
	shards = { items = { 245653, 236096 } }, -- Coffer Key Shard (season 3, earlier)
	shardsPerKey = 100,
	companionFaction = 2640, -- Brann Bronzebeard
	vaultTopTier = 8, -- fallback when the game has no season data
})
```

`Data/Midnight/Delves.lua`:

```lua
local addonName, ns = ...

-- Midnight (expansion 11): Delves data. See Core/Content.lua. Map IDs from RareScanner and Plumber, currency and
-- faction IDs from Plumber (GPLv3; IDs only, checked 2026-10-10: ExpansionLandingPage/Retail/MID_Activity.lua,
-- ResourceList.lua, FactionUtil.lua). The author doesn't own Midnight: a friend checks these with /tomte data.
-- No bountiful POI list: Midnight's bountiful entrances are found by their atlas.

ns.Content_Register(11, "delves", {
	continent = 2537, -- Quel'Thalas
	zones = { 2395, 2437, 2413, 2405, 2393 }, -- Eversong Woods, Zul'Aman, Harandar, Voidstorm, Silvermoon City
	keyCurrency = 3028, -- Restored Coffer Key
	shards = { currency = 3310 }, -- Coffer Key Shard (weekly cap from the currency)
	shardsPerKey = 100,
	companionFaction = 2744, -- Valeera Sanguinar
	vaultTopTier = 8,
})
```

In `Data/WarWithin/Weekly.lua`, mark the two flag entries (nothing else changes):

```lua
		{ label = "Restored Coffer Keys", kind = "keys", flags = { 91175, 91176, 91177, 91178 } },
		{ label = "Coffer Key Shards", kind = "shards", flags = { 84736, 84737, 84738, 84739 } },
```

TOC, after `Data/Midnight/Gear.lua`:

```
Data/WarWithin/Delves.lua
Data/Midnight/Delves.lua
```

- [ ] **Step 4: Run the test and check that it passes**

Run: `lua Tomte/tests/test_delves.lua`. Expected: `ok   delves data for both expansions`, `all delves tests passed`.
Also run `lua Tomte/tests/test_activities.lua` (unchanged, still passes).

### Task 2: Pure logic (`Modules/Delves/Data.lua`)

**Files:**
- Create: `Modules/Delves/Data.lua`
- Modify: `tests/test_delves.lua` (load Data.lua after the data files, add tests)

**Produces** (all pure, no WoW API):
- `ns.DELVES_BOUNTIFUL_ATLAS = "delves-bountiful"`; `ns.DELVES_ROLE_BY_ENUM = { [0] = "DAMAGER", [1] = "HEALER", [2] = "TANK" }`.
- `ns.Delves_IsBountiful(e, known) -> bool`. `e = { poi, atlas }`, `known = { [poi] = true } | nil`.
- `ns.Delves_Sort(list, myZone) -> list` (in place): bountiful first, then `map == myZone`, then name, then poi.
- `ns.Delves_Earned(curated, kind) -> { n, of } | nil`. `curated` is `ns.Weekly_ReadCurated`'s output.
- `ns.Delves_KeyLine(k) -> text, canCombine`. `k = { keys, shards?, perKey?, shardWeek = { n, of }?, earned = { n, of }? }`.
- `ns.Delves_VaultPlan(slots, runs, top) -> plan`.
  - `slots = { { threshold, progress } }` in index order; `runs = { { difficulty, numPoints } }` in any order.
  - `plan = { top, rows = { { index, threshold, unlocked, tier, maxed, need } }, advice = row | nil, text = string | nil }`.
- `ns.Delves_Ladder(step, level, tierID) -> ladder | nil, top`.
  - `step(tierID, level)` has the signature of `C_WeeklyRewards.GetNextActivitiesIncrease` and returns
    `hasData, nextTierID, nextLevel, itemLevel`.
  - `ladder = { { tier, ilvl } }`, ascending.
- `ns.Delves_LadderText(ladder) -> "Tier 4: 623 · Tier 8: 649" | nil`.
- `ns.Delves_SuggestTier(tiers, ilvl) -> tierInfo | nil`. `tiers` is `GetDelveEntranceTiers()`'s shape.
- `ns.Delves_RoleHint(playerRole, companionRole, companionName, names) -> text | nil`. Roles are "TANK", "HEALER" or
  "DAMAGER"; `names[role]` is the game's subtree name.
- `ns.Delves_PickCompanionSource(season, expansion) -> "season" | "fallback"`.
  `season = { expansionID, playerCompanionID } | nil`.
- `ns.Delves_TrackMode(myContinent, delveContinent) -> "poi" | "pin"`.

- [ ] **Step 1: Write the failing tests.** In `tests/test_delves.lua` add
  `assert(loadfile("Tomte/Modules/Delves/Data.lua"))("Tomte", ns)` after the data loads, and these tests above the
  final check:

```lua
test("bountiful by atlas, by ID, neither", function()
	eq(ns.Delves_IsBountiful({ poi = 1, atlas = "delves-bountiful" }, nil), true, "atlas")
	eq(ns.Delves_IsBountiful({ poi = 7783, atlas = "delves-regular" }, { [7783] = true }), true, "id")
	eq(ns.Delves_IsBountiful({ poi = 7870, atlas = "delves-regular" }, { [7783] = true }), false, "neither")
	eq(ns.Delves_IsBountiful({ poi = 7870 }, nil), false, "no atlas, no list")
end)

test("sort: bountiful, then my zone, then name", function()
	local list = {
		{ poi = 1, map = 2, name = "B" },
		{ poi = 2, map = 1, name = "C" },
		{ poi = 3, map = 2, name = "A", bountiful = true },
		{ poi = 4, map = 1, name = "D", bountiful = true },
		{ poi = 5, map = 1, name = "A" },
	}
	ns.Delves_Sort(list, 1)
	eq(list[1].poi, 4, "bountiful in my zone")
	eq(list[2].poi, 3, "bountiful elsewhere")
	eq(list[3].poi, 5, "my zone A")
	eq(list[4].poi, 2, "my zone C")
	eq(list[5].poi, 1, "elsewhere")
	eq(#ns.Delves_Sort({}, 1), 0, "empty")
end)

test("earned keys from Weekly's curated list", function()
	local curated = { { group = "Delves", entries = {
		{ label = "The Key to Success", state = "done" },
		{ label = "Restored Coffer Keys", kind = "keys", n = 3, of = 4 },
		{ label = "Coffer Key Shards", kind = "shards", n = 1, of = 4 },
	} } }
	local k = ns.Delves_Earned(curated, "keys")
	eq(k.n, 3)
	eq(k.of, 4)
	eq(ns.Delves_Earned(curated, "missing"), nil, "unknown kind")
	eq(ns.Delves_Earned(nil, "keys"), nil, "no list")
end)

test("key line", function()
	local text, combine = ns.Delves_KeyLine({ keys = 2, shards = 140, perKey = 100, earned = { n = 3, of = 4 } })
	eq(text, "2 keys · 140 shards (1 more key) · keys this week 3/4")
	eq(combine, true)
	text, combine = ns.Delves_KeyLine({ keys = 1, shards = 40, perKey = 100, shardWeek = { n = 200, of = 600 } })
	eq(text, "1 key · 40 shards, 200/600 this week")
	eq(combine, false)
	text = ns.Delves_KeyLine({ keys = 0 })
	eq(text, "0 keys")
end)

test("vault plan: mixed tiers", function()
	local slots = { { threshold = 2, progress = 5 }, { threshold = 4, progress = 5 }, { threshold = 8, progress = 5 } }
	local runs = { { difficulty = 8, numPoints = 2 }, { difficulty = 5, numPoints = 3 } }
	local plan = ns.Delves_VaultPlan(slots, runs, 8)
	eq(plan.rows[1].tier, 8, "slot 1 tier")
	eq(plan.rows[1].maxed, true, "slot 1 maxed")
	eq(plan.rows[2].tier, 5, "slot 2 tier")
	eq(plan.rows[2].maxed, false, "slot 2 maxed")
	eq(plan.rows[2].need, 2, "slot 2 needs 2 more at the top")
	eq(plan.rows[3].unlocked, false, "slot 3 locked")
	eq(plan.rows[3].tier, nil, "slot 3 tier")
	eq(plan.advice.index, 2, "advice slot")
	eq(plan.text, "Tier 8 or higher: 2 more runs max vault slot 2 (now Tier 5)")
end)

test("vault plan: thresholds 1/4/8, one run short", function()
	local slots = { { threshold = 1, progress = 7 }, { threshold = 4, progress = 7 }, { threshold = 8, progress = 7 } }
	local runs = { { difficulty = 11, numPoints = 4 }, { difficulty = 3, numPoints = 3 } }
	local plan = ns.Delves_VaultPlan(slots, runs, 8)
	eq(plan.rows[2].maxed, true, "4 runs at 11")
	eq(plan.advice.index, 3, "slot 3")
	eq(plan.rows[3].need, 4, "8 - 4")
	eq(plan.text, "Tier 8 or higher: 4 more runs unlock vault slot 3 at the top")
end)

test("vault plan: world activities only", function()
	local slots = { { threshold = 2, progress = 3 }, { threshold = 4, progress = 3 } }
	local plan = ns.Delves_VaultPlan(slots, { { difficulty = 1, numPoints = 3 } }, 8)
	eq(plan.rows[1].unlocked, true)
	eq(plan.rows[1].tier, 1)
	eq(plan.rows[1].maxed, false)
	eq(plan.text, "Tier 8 or higher: 2 more runs max vault slot 1 (now Tier 1)")
end)

test("vault plan: no runs, all maxed, empty inputs", function()
	local plan = ns.Delves_VaultPlan({ { threshold = 2, progress = 0 } }, {}, 8)
	eq(plan.rows[1].unlocked, false)
	eq(plan.text, "Tier 8 or higher: 2 more runs unlock vault slot 1 at the top")
	plan = ns.Delves_VaultPlan({ { threshold = 1, progress = 1 } }, { { difficulty = 9, numPoints = 1 } }, 8)
	eq(plan.advice, nil)
	eq(plan.text, "Every World slot is maxed")
	plan = ns.Delves_VaultPlan({}, {}, 8)
	eq(plan.text, nil, "no slots")
	eq(#plan.rows, 0)
end)

test("vault plan: one run left uses the singular", function()
	local plan = ns.Delves_VaultPlan({ { threshold = 2, progress = 2 } },
		{ { difficulty = 8, numPoints = 1 }, { difficulty = 4, numPoints = 1 } }, 8)
	eq(plan.text, "Tier 8 or higher: 1 more run maxes vault slot 1 (now Tier 4)")
end)

test("ladder: follows the steps to the top", function()
	local steps = { [1] = { 11, 2, 610 }, [2] = { 12, 4, 623 }, [4] = { 13, 8, 649 } }
	local calls = {}
	local ladder, top = ns.Delves_Ladder(function(tierID, level)
		calls[#calls + 1] = tierID
		local s = steps[level]
		if s then
			return true, s[1], s[2], s[3]
		end
		return true, nil, nil, nil
	end, 1, 10)
	eq(top, 8)
	eq(#ladder, 3)
	eq(ladder[3].tier, 8)
	eq(ladder[3].ilvl, 649)
	eq(calls[1], 10, "starts with the given tier ID")
	eq(calls[2], 11, "then the returned one")
	eq(ns.Delves_LadderText(ladder), "Tier 2: 610 · Tier 4: 623 · Tier 8: 649")
end)

test("ladder: no data, stuck", function()
	local ladder, top = ns.Delves_Ladder(function()
		return false
	end, 1, 10)
	eq(ladder, nil, "no season data")
	eq(top, nil)
	local n = 0
	ladder, top = ns.Delves_Ladder(function(_, level)
		n = n + 1
		return true, 10, level, 600 -- never rises
	end, 1, 10)
	eq(#ladder, 0)
	eq(top, 1)
	eq(n, 1, "stops at once")
	eq(ns.Delves_LadderText({}), nil)
end)

test("suggest tier", function()
	local tiers = {
		{ tier = 1, suggestedILvl = 560, unlocked = true },
		{ tier = 7, suggestedILvl = 640, unlocked = true },
		{ tier = 8, suggestedILvl = 650, unlocked = true },
		{ tier = 9, suggestedILvl = 655, unlocked = false },
	}
	eq(ns.Delves_SuggestTier(tiers, 652).tier, 8)
	eq(ns.Delves_SuggestTier(tiers, 660).tier, 8, "locked tier skipped")
	eq(ns.Delves_SuggestTier(tiers, 500), nil, "below every tier")
	eq(ns.Delves_SuggestTier({}, 600), nil)
end)

test("role hint", function()
	local names = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
	eq(ns.Delves_RoleHint("TANK", "TANK", "Brann", names), "Brann is set to Tank: Healer suits a tank")
	eq(ns.Delves_RoleHint("HEALER", "HEALER", "Brann", names), "Brann is set to Healer: Damage suits a healer")
	eq(ns.Delves_RoleHint("DAMAGER", "DAMAGER", "Brann", names), nil, "damage + damage is fine")
	eq(ns.Delves_RoleHint("TANK", "HEALER", "Brann", names), nil)
	eq(ns.Delves_RoleHint(nil, "TANK", "Brann", names), nil)
	eq(ns.Delves_RoleHint("TANK", "TANK", nil, {}), "Your companion is set to tank: healer suits a tank")
end)

test("season companion for another expansion", function()
	eq(ns.Delves_PickCompanionSource({ expansionID = 10, playerCompanionID = 1 }, 10), "season")
	eq(ns.Delves_PickCompanionSource({ expansionID = 11, playerCompanionID = 2 }, 10), "fallback")
	eq(ns.Delves_PickCompanionSource({ expansionID = 10 }, 10), "fallback", "no companion ID")
	eq(ns.Delves_PickCompanionSource(nil, 10), "fallback")
end)

test("track mode", function()
	eq(ns.Delves_TrackMode(2274, 2274), "poi")
	eq(ns.Delves_TrackMode(2274, 2371), "pin")
	eq(ns.Delves_TrackMode(nil, 2274), "pin", "unknown continent")
end)
```

- [ ] **Step 2: Run the tests and check that they fail**

Run: `lua Tomte/tests/test_delves.lua`. Expected: error "cannot open Tomte/Modules/Delves/Data.lua".

- [ ] **Step 3: Write `Modules/Delves/Data.lua`**

```lua
local addonName, ns = ...

-- Delves: pure logic (no WoW API calls; unit-tested with plain Lua 5.1). Bountiful detection and order, the key
-- line, the Great Vault World track plan, the tier ladder, the tier suggestion and the companion role hint.

ns.DELVES_BOUNTIFUL_ATLAS = "delves-bountiful"
ns.DELVES_ROLE_BY_ENUM = { [0] = "DAMAGER", [1] = "HEALER", [2] = "TANK" } -- Enum.CompanionRoleType

local LADDER_STEPS = 20
local SUGGEST = { TANK = "HEALER", HEALER = "DAMAGER" }
local WORD = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }

local function Plural(n, one, many)
	return n == 1 and one or many
end

function ns.Delves_IsBountiful(e, known)
	if e.atlas == ns.DELVES_BOUNTIFUL_ATLAS then
		return true
	end
	return known ~= nil and known[e.poi] == true
end

function ns.Delves_Sort(list, myZone)
	table.sort(list, function(a, b)
		local ab, bb = a.bountiful == true, b.bountiful == true
		if ab ~= bb then
			return ab
		end
		local am, bm = a.map == myZone, b.map == myZone
		if am ~= bm then
			return am
		end
		if (a.name or "") ~= (b.name or "") then
			return (a.name or "") < (b.name or "")
		end
		return (a.poi or 0) < (b.poi or 0)
	end)
	return list
end

function ns.Delves_Earned(curated, kind)
	for _, g in ipairs(curated or {}) do
		for _, e in ipairs(g.entries or {}) do
			if e.kind == kind and e.of then
				return { n = e.n or 0, of = e.of }
			end
		end
	end
	return nil
end

function ns.Delves_KeyLine(k)
	local keys = k.keys or 0
	local parts = { ("%d %s"):format(keys, Plural(keys, "key", "keys")) }
	local combine = false
	if k.shards then
		local perKey = k.perKey or 100
		local text = ("%d shards"):format(k.shards)
		if k.shards >= perKey then
			local n = math.floor(k.shards / perKey)
			text = text .. (" (%d more %s)"):format(n, Plural(n, "key", "keys"))
			combine = true
		end
		if k.shardWeek and (k.shardWeek.of or 0) > 0 then
			text = text .. (", %d/%d this week"):format(k.shardWeek.n or 0, k.shardWeek.of)
		end
		parts[#parts + 1] = text
	end
	if k.earned then
		parts[#parts + 1] = ("keys this week %d/%d"):format(k.earned.n, k.earned.of)
	end
	return table.concat(parts, " · "), combine
end

-- The tier of the threshold-th best run (a slot pays for that run), or nil with fewer runs.
local function TierAt(runs, threshold)
	local seen = 0
	for _, r in ipairs(runs) do
		seen = seen + (r.numPoints or 0)
		if seen >= threshold then
			return r.difficulty
		end
	end
	return nil
end

local function CountAtLeast(runs, tier)
	local n = 0
	for _, r in ipairs(runs) do
		if r.difficulty >= tier then
			n = n + (r.numPoints or 0)
		end
	end
	return n
end

local function VaultText(plan)
	local a = plan.advice
	if not a then
		return #plan.rows > 0 and "Every World slot is maxed" or nil
	end
	if a.unlocked then
		return ("Tier %d or higher: %d more %s vault slot %d (now Tier %d)"):format(plan.top, a.need,
			Plural(a.need, "run maxes", "runs max"), a.index, a.tier or 1)
	end
	return ("Tier %d or higher: %d more %s vault slot %d at the top"):format(plan.top, a.need,
		Plural(a.need, "run unlocks", "runs unlock"), a.index)
end

function ns.Delves_VaultPlan(slots, runs, top)
	local sorted = {}
	for i, r in ipairs(runs or {}) do
		sorted[i] = r
	end
	table.sort(sorted, function(a, b)
		return a.difficulty > b.difficulty
	end)
	local atTop = CountAtLeast(sorted, top)
	local plan = { top = top, rows = {} }
	for i, s in ipairs(slots or {}) do
		local row = { index = i, threshold = s.threshold, unlocked = (s.progress or 0) >= s.threshold,
			tier = TierAt(sorted, s.threshold) }
		row.maxed = row.unlocked and row.tier ~= nil and row.tier >= top
		row.need = math.max(s.threshold - atTop, 0)
		plan.rows[i] = row
		if not plan.advice and not row.maxed then
			plan.advice = row
		end
	end
	plan.text = VaultText(plan)
	return plan
end

function ns.Delves_Ladder(step, level, tierID)
	local ladder = {}
	for _ = 1, LADDER_STEPS do
		local hasData, nextTierID, nextLevel, itemLevel = step(tierID, level)
		if not hasData then
			if #ladder == 0 then
				return nil, nil
			end
			return ladder, level
		end
		if not nextLevel or nextLevel <= level then
			return ladder, level
		end
		ladder[#ladder + 1] = { tier = nextLevel, ilvl = itemLevel }
		level, tierID = nextLevel, nextTierID or tierID
	end
	return ladder, level
end

function ns.Delves_LadderText(ladder)
	if not ladder or #ladder == 0 then
		return nil
	end
	local parts = {}
	for i, step in ipairs(ladder) do
		parts[i] = ("Tier %d: %s"):format(step.tier, step.ilvl and tostring(step.ilvl) or "?")
	end
	return table.concat(parts, " · ")
end

function ns.Delves_SuggestTier(tiers, ilvl)
	local best
	for _, t in ipairs(tiers or {}) do
		if t.unlocked and (t.suggestedILvl or 0) <= ilvl and (not best or t.tier > best.tier) then
			best = t
		end
	end
	return best
end

function ns.Delves_RoleHint(playerRole, companionRole, companionName, names)
	if not playerRole or playerRole ~= companionRole then
		return nil
	end
	local suggest = SUGGEST[playerRole]
	if not suggest then
		return nil
	end
	names = names or {}
	return ("%s is set to %s: %s suits a %s"):format(companionName or "Your companion",
		names[companionRole] or WORD[companionRole], names[suggest] or WORD[suggest], WORD[playerRole])
end

function ns.Delves_PickCompanionSource(season, expansion)
	if season and season.playerCompanionID and season.expansionID == expansion then
		return "season"
	end
	return "fallback"
end

function ns.Delves_TrackMode(myContinent, delveContinent)
	if myContinent and myContinent == delveContinent then
		return "poi"
	end
	return "pin"
end
```

- [ ] **Step 4: Run the tests and check that they pass**

Run: `lua Tomte/tests/test_delves.lua`. Expected: every line `ok`, then `all delves tests passed`.
Then the whole suite: `for t in Tomte/tests/test_*.lua; do lua "$t"; done` (the theme scan sees the new files).

### Task 3: Weekly reader made public

**Files:** Modify `Modules/Weekly/Activities.lua:18-56`.

**Produces:** `ns.Weekly_ReadCurated(expansion) -> { { group, entries = { { label, kind, state | n, of, title } } } } | nil`.

- [ ] **Step 1:** Rename the local `ReadCurated` to `function ns.Weekly_ReadCurated(expansion)`. Update its one
  caller in `view:Render` to `ns.Weekly_ReadCurated(expansion)`. Change `local item = { label = e.label }` to
  `local item = { label = e.label, kind = e.kind }`.
- [ ] **Step 2:** Run `lua Tomte/tests/test_activities.lua` and `lua Tomte/tests/test_weekly.lua`; both pass
  unchanged. (The model ignores the extra `kind` field.)

### Task 4: Delve scan and tracking (`Modules/Delves/Scan.lua`)

**Files:** Create `Modules/Delves/Scan.lua`.

**Interfaces:**
- Consumes: `ns.Content_Get(e, "delves")`, `ns.Delves_IsBountiful`, `ns.Delves_Sort`, `ns.Delves_TrackMode`,
  `ns.SafeTrack`, `ns.ContentExpansion`.
- Produces:
  - `ns.DelvesScan_List() -> { { poi, map, name, x, y, atlas, widgetSet, bountiful } }`: sorted; empty when there's no
    data or nothing is readable yet.
  - `ns.DelvesScan_Invalidate()`.
  - `ns.DelvesScan_PlayerZone() -> mapID | nil`: the player's map, walked up to its `Zone` ancestor.
  - `ns.Delves_Track(entry)`.
  - `ns.Delves_Tooltip(owner, entry)`.

- [ ] **Step 1: Write the file**

```lua
local addonName, ns = ...

-- Delves: today's delve entrances for the character's content expansion and tracking one. Entrances come from
-- C_AreaPoiInfo.GetDelvesForMap per zone (the expansion's list plus its continent's zones), cached until
-- AREA_POIS_UPDATED, a zone change or the daily reset. Tracking: an AreaPOI super-track on the same continent (the
-- Waypoints marker shows the delve's name and atlas), else a map pin at the entrance so Waypoints routes it.

local MAX_DEPTH = 10

local cache, cacheKey, cacheUntil

local function MapOfType(mapID, mapType)
	local info = mapID and C_Map.GetMapInfo(mapID)
	for _ = 1, MAX_DEPTH do
		if not info then
			return nil
		end
		if info.mapType == mapType then
			return info.mapID
		end
		info = (info.parentMapID or 0) > 0 and C_Map.GetMapInfo(info.parentMapID) or nil
	end
	return nil
end

function ns.DelvesScan_PlayerZone()
	return MapOfType(C_Map.GetBestMapForUnit("player"), Enum.UIMapType.Zone)
end

local function Zones(def)
	local seen, list = {}, {}
	local function Add(id)
		if id and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	for _, id in ipairs(def.zones or {}) do
		Add(id)
	end
	for _, child in ipairs(def.continent and C_Map.GetMapChildrenInfo(def.continent, Enum.UIMapType.Zone) or {}) do
		Add(child.mapID)
	end
	return list
end

local function Read(def)
	local list, seen = {}, {}
	for _, map in ipairs(Zones(def)) do
		for _, poi in ipairs(C_AreaPoiInfo.GetDelvesForMap(map) or {}) do
			local info = not seen[poi] and C_AreaPoiInfo.GetAreaPOIInfo(map, poi)
			if info and info.position then
				seen[poi] = true
				local x, y = info.position:GetXY()
				local e = { poi = poi, map = map, name = info.name, x = x, y = y, atlas = info.atlasName,
					widgetSet = info.tooltipWidgetSet }
				e.bountiful = ns.Delves_IsBountiful(e, def.bountifulPOIs)
				list[#list + 1] = e
			end
		end
	end
	return list
end

function ns.DelvesScan_Invalidate()
	cache = nil
end

function ns.DelvesScan_List()
	local expansion = ns.ContentExpansion()
	local def = ns.Content_Get(expansion, "delves")
	if not def or not C_AreaPoiInfo.GetDelvesForMap then
		return {}
	end
	local stale = not cache or cacheKey ~= expansion or GetTime() >= (cacheUntil or 0)
	if stale and not InCombatLockdown() then
		cache, cacheKey = Read(def), expansion
		local reset = C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset() or 3600
		cacheUntil = GetTime() + math.max(reset, 60) + 5
	end
	local copy = {}
	for i, e in ipairs(cache or {}) do
		copy[i] = e
	end
	return ns.Delves_Sort(copy, ns.DelvesScan_PlayerZone())
end

function ns.Delves_Track(e)
	local here = MapOfType(C_Map.GetBestMapForUnit("player"), Enum.UIMapType.Continent)
	local mode = ns.Delves_TrackMode(here, MapOfType(e.map, Enum.UIMapType.Continent))
	if mode == "pin" and not C_Map.CanSetUserWaypointOnMap(e.map) then
		ns.Print("can't place a map pin there.")
		return
	end
	local now = ns.SafeTrack(function()
		if mode == "poi" then
			C_SuperTrack.SetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI, e.poi)
		else
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.map, e.x, e.y))
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
	ns.Print(("%s %s."):format(now and "tracking" or "after combat: tracking", e.name or "the delve"))
end

-- The game's own entrance tooltip under the name: the story variant comes from the POI's widget set.
function ns.Delves_Tooltip(owner, e)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(e.name or "?", ns.UI.RGB("heading"))
	if e.bountiful then
		GameTooltip:AddLine("Bountiful", ns.UI.RGB("accent"))
	end
	local info = C_Map.GetMapInfo(e.map)
	if info and info.name then
		GameTooltip:AddLine(info.name, ns.UI.RGB("textMuted"))
	end
	if e.widgetSet and GameTooltip_AddWidgetSet then
		GameTooltip_AddWidgetSet(GameTooltip, e.widgetSet)
	end
	GameTooltip:AddLine("Click to track it", ns.UI.RGB("textMuted"))
	GameTooltip:Show()
end
```

- [ ] **Step 2:** Before writing, check `C_Map.GetMapChildrenInfo(uiMapID, mapType, allDescendants)` and
  `GameTooltip_AddWidgetSet(tooltip, widgetSetID, verticalPadding)` on warcraft.wiki.gg / wow-ui-source live (the
  latter is in `Blizzard_GameTooltip/Mainline/GameTooltip.lua`). Fix the calls if the signatures differ.
- [ ] **Step 3:** `lua Tomte/tests/test_theme.lua` passes (no literal colors; `ns.UI.RGB` only).

### Task 5: Readers and the companion moment (`Modules/Delves/Read.lua`, Moments)

**Files:**
- Create: `Modules/Delves/Read.lua`
- Modify: `Modules/Moments/Data.lua` (`ns.MOMENT_TYPES`: add
  `{ key = "companion", name = "Companion level (delves)", style = "banner" }` after `renown`) and
  `Modules/Moments/Moments.lua` (add `SAMPLES.companion`).

**Interfaces:**
- Consumes: Task 2's functions, `ns.Weekly_ReadCurated`, `ns.Moments_Trigger`.
- Produces:
  - `ns.DelvesRead_Init(db)`.
  - `ns.DelvesRead_State() -> { keys, keyLine, canCombine, vault, companion }`, all cached; a part is nil while
    unread.
    - `keys`: Task 2's `k` shape.
    - `vault = { slots, runs, ladder, top, plan }`.
    - `companion = { faction, name, level, maxLevel, xp, xpMax, companionID?, role?, roleName?, roleNames?,
      displayID?, combat?, utility?, journey? }`; curios are `{ name, icon, spellID, rarity, link }`.
  - `ns.DelvesRead_Dirty(part)`: part is "keys", "vault", "companion" or nil for all. It marks the part and schedules
    one read after 1 s (out of combat; else at `PLAYER_REGEN_ENABLED`), then calls `ns.Delves_Changed()`.
  - `ns.DelvesRead_PlayerRole() -> "TANK" | "HEALER" | "DAMAGER" | nil`.
  - `ns.DelvesRead_RoleHint() -> text | nil`.

- [ ] **Step 1: Write the readers.** The key and vault readers:

```lua
local function ReadKeys(def, expansion)
	local k = { perKey = def.shardsPerKey or 100 }
	local info = C_CurrencyInfo.GetCurrencyInfo(def.keyCurrency)
	k.keys = info and info.quantity or 0
	local s = def.shards or {}
	if s.currency then
		local c = C_CurrencyInfo.GetCurrencyInfo(s.currency)
		if c then
			k.shards = c.quantity or 0
			if (c.maxWeeklyQuantity or 0) > 0 then
				k.shardWeek = { n = c.quantityEarnedThisWeek or 0, of = c.maxWeeklyQuantity }
			end
		end
	elseif s.items then
		local n = 0
		for _, id in ipairs(s.items) do
			n = n + (C_Item.GetItemCount(id, true) or 0)
		end
		k.shards = n
	end
	k.earned = ns.Delves_Earned(ns.Weekly_ReadCurated and ns.Weekly_ReadCurated(expansion), "keys")
	return k
end

local function ReadVault(def)
	local world = Enum.WeeklyRewardChestThresholdType.World
	local activities = C_WeeklyRewards.GetActivities(world) or {}
	table.sort(activities, function(a, b)
		return a.index < b.index
	end)
	local slots, tierID = {}, nil
	for i, a in ipairs(activities) do
		slots[i] = { threshold = a.threshold, progress = a.progress, level = a.level }
		if not tierID and (a.activityTierID or 0) > 0 then
			tierID = a.activityTierID
		end
	end
	local runs = C_WeeklyRewards.GetSortedProgressForActivity(world, true) or {}
	local ladder, top
	if tierID then
		ladder, top = ns.Delves_Ladder(C_WeeklyRewards.GetNextActivitiesIncrease, 1, tierID)
	end
	top = top or def.vaultTopTier or 8
	return { slots = slots, runs = runs, ladder = ladder, top = top, plan = ns.Delves_VaultPlan(slots, runs, top) }
end
```

  The companion reader (Blizzard_DelvesCompanionConfiguration's own calls):

```lua
local function ActiveEntry(configID, nodeID)
	local node = nodeID and nodeID > 0 and C_Traits.GetNodeInfo(configID, nodeID)
	return node and node.activeEntry and node.activeEntry.entryID or nil
end

local function Curio(configID, nodeID)
	local entryID = ActiveEntry(configID, nodeID)
	local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
	local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
	local spellID = definition and (definition.overriddenSpellID or definition.spellID)
	local spell = spellID and C_Spell.GetSpellInfo(spellID)
	if not spell then
		return nil
	end
	local curio = { name = spell.name, icon = spell.iconID, spellID = spellID }
	local condID = entry.conditionIDs and entry.conditionIDs[1]
	local cond = condID and C_Traits.GetConditionInfo(configID, condID)
	if cond and cond.traitCondAccountElementID then
		curio.rarity = C_DelvesUI.GetCurioRarityByTraitCondAccountElementID(cond.traitCondAccountElementID)
		curio.link = curio.rarity and C_DelvesUI.GetCurioLink(spellID, curio.rarity)
	end
	return curio
end

local function ReadCompanion(def, expansion)
	local seasonFaction = C_DelvesUI.GetDelvesFactionForSeason and C_DelvesUI.GetDelvesFactionForSeason() or 0
	local season = seasonFaction > 0 and C_MajorFactions.GetMajorFactionData(seasonFaction) or nil
	local useSeason = ns.Delves_PickCompanionSource(season, expansion) == "season"
	local companionID = useSeason and season.playerCompanionID or nil
	local faction = companionID and C_DelvesUI.GetFactionForCompanion(companionID) or def.companionFaction
	local ranks = faction and C_GossipInfo.GetFriendshipReputationRanks(faction)
	local data = faction and C_Reputation.GetFactionDataByID(faction)
	if not (ranks and data and data.name) then
		return nil
	end
	local c = { faction = faction, name = data.name, level = ranks.currentLevel or 0, maxLevel = ranks.maxLevel,
		companionID = companionID }
	local rep = C_GossipInfo.GetFriendshipReputation(faction)
	if rep and rep.nextThreshold then
		c.xp, c.xpMax = rep.standing - rep.reactionThreshold, rep.nextThreshold - rep.reactionThreshold
	end
	if useSeason and season.name then
		c.journey = { name = season.name, level = season.renownLevel, earned = season.renownReputationEarned,
			threshold = season.renownLevelThreshold, max = season.maxLevel }
	end
	if not companionID then
		return c
	end
	c.displayID = C_DelvesUI.GetCreatureDisplayInfoForCompanion(companionID)
	local tree = C_DelvesUI.GetTraitTreeForCompanion(companionID)
	local configID = tree and tree > 0 and C_Traits.GetConfigIDByTreeID(tree)
	if not configID then
		return c
	end
	c.roleNames = {}
	local subtreeRole = {}
	for enum, role in pairs(ns.DELVES_ROLE_BY_ENUM) do
		local sub = C_DelvesUI.GetRoleSubtreeForCompanion(enum, companionID)
		local info = sub and sub > 0 and C_Traits.GetSubTreeInfo(configID, sub)
		if info then
			c.roleNames[role] = info.name
			subtreeRole[sub] = role
		end
	end
	local roleEntry = ActiveEntry(configID, C_DelvesUI.GetRoleNodeForCompanion(companionID))
	local entry = roleEntry and C_Traits.GetEntryInfo(configID, roleEntry)
	if entry and entry.subTreeID then
		c.role = subtreeRole[entry.subTreeID]
		c.roleName = c.role and c.roleNames[c.role]
	end
	c.combat = Curio(configID, C_DelvesUI.GetCurioNodeForCompanion(Enum.CurioType.Combat, companionID))
	c.utility = Curio(configID, C_DelvesUI.GetCurioNodeForCompanion(Enum.CurioType.Utility, companionID))
	return c
end
```

- [ ] **Step 2: Write the state, the debounce and the moment.**
  - Write `ns.DelvesRead_Dirty` with one `C_Timer.NewTimer(1, ...)` at a time. In combat it registers
    `PLAYER_REGEN_ENABLED` on this file's event frame and reads then.
  - Each part is read inside `pcall`, and a failure leaves that part's old value. In the error case, print once per
    session: "delves: couldn't read <part> (<error>)".
  - Companion moment: after a companion read, `db.companionLevel[c.faction]` holds the last level.
    - When a stored level exists, `primed` is true (set after the first read this session), and `c.level` is higher:
      call `ns.Moments_Trigger("companion", { label = "Level " .. c.level, title = c.name })`.
    - Then store `c.level`. The first read of a session only stores.
  - `ns.DelvesRead_PlayerRole()`: `local i = C_SpecializationInfo.GetSpecialization()`. Then
    `select(5, C_SpecializationInfo.GetSpecializationInfo(i))` when `i` is set; nil otherwise.
  - `ns.DelvesRead_RoleHint()`: `db.roleHint` and a companion with a role → `ns.Delves_RoleHint(PlayerRole(), c.role,
    c.name, c.roleNames)`.
- [ ] **Step 3: Moments.** Add the type to `ns.MOMENT_TYPES` and a sample in `Moments.lua`'s `SAMPLES`:
  `companion = function() return { label = "Level 40", title = "Brann Bronzebeard" } end`. Run
  `lua Tomte/tests/test_moments.lua` ("DefaultStyles has every type" now includes `companion`).
- [ ] **Step 4: Check signatures** before writing on warcraft.wiki.gg / wow-ui-source live:
  - `C_Item.GetItemCount(item, includeBank, ...)`;
  - `C_GossipInfo.GetFriendshipReputationRanks` fields `currentLevel`, `maxLevel`;
  - `C_Traits.GetConditionInfo`;
  - the 5th return of `C_SpecializationInfo.GetSpecializationInfo` is the role.
  Fix the calls if anything differs.

### Task 6: Tier picker note (`Modules/Delves/Entrance.lua`)

**Files:** Create `Modules/Delves/Entrance.lua`.

**Interfaces:**
- Consumes: `ns.DelvesRead_State`, `ns.DelvesScan_List`, `ns.Delves_SuggestTier`, `ns.DelvesRead_RoleHint`.
- Produces: `ns.DelvesEntrance_Init(db)`, `ns.DelvesEntrance_Toggle(active)`.

- [ ] **Step 1:** Write an event frame for `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE`. When
  `type == Enum.PlayerInteractionType.TieredEntrance` and `db.entrance`:
  - `C_Timer.After(0, Show)`. `Show` returns if `DelvesDifficultyPickerFrame` is missing or hidden.
  - Otherwise it builds the card lazily: `UI.Panel(CreateFrame("Frame", nil, UIParent))`, 260 wide, `DIALOG` strata.
    Anchor it `TOPLEFT` to the picker's `TOPRIGHT` (+8, 0).
  - Fill four lines with `UI.Text(card, 12, role)`, each with a small heading in `textMuted`:
    1. **Vault:** `state.vault.plan.text`, with `state.vault.ladder`'s text under it in `textMuted`.
    2. **Your gear:** `Delves_SuggestTier(C_DelvesUI.GetDelveEntranceTiers(), equipped)`, where `equipped` is the
       2nd return of `GetAverageItemLevel()`. Text "Tier %d suits your item level %d". Skipped when either is nil
       or secret (`issecretvalue`).
    3. **Keys:** `state.keyLine`; `" · Bountiful"` in `accent` when an entry of `DelvesScan_List()` is bountiful and
       its `name` equals `C_DelvesUI.GetDelveEntranceTitleString()`. These are two game strings compared with each
       other, never with English.
    4. **Companion:** "Brann · level 45 · Healer", then the role hint in `warning` when there is one.
  - Height = sum of lines. Hide on `_HIDE` with the same type, and on `PLAYER_REGEN_DISABLED`.
- [ ] **Step 2:** Check `Enum.PlayerInteractionType.TieredEntrance` and the event's payload on warcraft.wiki.gg
  (`PLAYER_INTERACTION_MANAGER_FRAME_SHOW`). The spec's source is `Blizzard_DelvesDifficultyPicker_Bootstrap.lua`.
- [ ] **Step 3:** `lua Tomte/tests/test_theme.lua` passes.

### Task 7: Delves page (`Modules/Delves/Page.lua`)

**Files:** Create `Modules/Delves/Page.lua`.

**Interfaces:**
- Consumes: Tasks 4–5, `ns.WeeklySlot_Create/Set`, `ns.HomeKit` (`Kit.Heading`, `Kit.PoolRow`, `Kit.HideFrom`),
  `UI.Scroll`.
- Produces: `ns.DelvesPage = { title = "Delves", Create(frame), Refresh(frame) }` (same contract as `ns.PetsPage`),
  `ns.DelvesPage_Refresh()`.

- [ ] **Step 1:** Lay the page out in one `UI.Scroll`, top to bottom:
  - **Header:**
    - the key line in `text`;
    - "Combine 100 shards into a key" in `success` when `canCombine`;
    - the journey line "Delver's Journey: renown 7 (1200/2500)" in `textMuted`, or "renown 10 (max)".
  - **Today:** `Kit.Heading` "Today" with "n bountiful" on the right.
    - Rows from `DelvesScan_List()` via `Kit.PoolRow`. `row:Set(icon, name, color, right)`: icon `{ atlas = e.atlas }`
      or the bountiful atlas; color `accent` for bountiful; right is the zone name (`C_Map.GetMapInfo(e.map).name`).
    - `onClick` = `ns.Delves_Track(e)`; `onEnter` = `ns.Delves_Tooltip(row, e)`.
    - Empty: "No delves found for <expansion>. Open the world map once if this looks wrong." Below delve level:
      "Delves open at level N" (`C_DelvesUI.GetDelvesMinRequiredLevel()`).
  - **Great Vault: World:**
    - `Kit.Heading`, then up to 3 `ns.WeeklySlot_Create(c, 96, 40, 13)` boxes.
    - `WeeklySlot_Set(slot, { progress, threshold, ilvl = nil }, i == nextLocked, true)`, and under each box
      "Tier n" or "-" in `textMuted`.
    - Then `plan.text` (`accent` when there's advice, `success` when maxed) and the ladder text.
  - **Companion:**
    - a 48 px portrait (`SetPortraitTextureFromCreatureDisplayID(tex, c.displayID)` when set);
    - "Name · level L/max";
    - an XP bar (`UI.Bar` if Panel/Widgets has one, else a texture with `accent`);
    - the role name;
    - two curio rows: icon, name, rank text from `rarity` (Common, Uncommon, Rare, Epic via `ITEM_QUALITY*_DESC`
      globals). Hover shows `GameTooltip:SetHyperlink(curio.link)`.
    - The role hint in `warning`.
    - With no companion: "Unlocks with your first delve".
- [ ] **Step 2:** `Refresh` re-renders from cached state only; it never reads APIs itself, except
  `DelvesScan_List()`, which uses its cache.
- [ ] **Step 3:** Check `Panel/Widgets.lua` for an existing bar and row helpers before adding any. Check
  `SetPortraitTextureFromCreatureDisplayID` in wow-ui-source live.

### Task 8: Module, Home entries, TOC, docs (`Modules/Delves/Delves.lua`)

**Files:**
- Create `Modules/Delves/Delves.lua`.
- Modify `Tomte.toc`, `README.md`, `CHANGELOG.md`.

- [ ] **Step 1: `RegisterModule`:**

```lua
module = ns.RegisterModule({
	key = "delves",
	name = "Delves",
	category = "World",
	description = "Today's bountiful delves with a click to track them, your coffer keys and shards, the delve tier "
		.. "that raises your Great Vault's World slots, and your companion's level, role and curios. A note beside "
		.. "the tier picker at a delve entrance.",
	enabledByDefault = true,
	defaults = { around = true, entrance = true, roleHint = true, nextNeedsKey = true, companionLevel = {} },
	init = function(saved)
		db = saved
		ns.DelvesRead_Init(db)
		ns.DelvesEntrance_Init(db)
	end,
	toggle = Toggle, -- registers/unregisters the events below; DelvesEntrance_Toggle(active)
	home = { PAGE, AROUND, NEXT_BOUNTIFUL, NEXT_TIER, NEXT_ROLE },
	options = {
		{ type = "checkbox", key = "around", label = "Delves in Around you",
			tooltip = "The delves in your zone on Home, bountiful first. Click one to track it." },
		{ type = "checkbox", key = "entrance", label = "Note at the delve entrance",
			tooltip = "Beside the tier picker: the tier for your vault and your gear, your keys and your companion." },
		{ type = "checkbox", key = "roleHint", label = "Companion role hint",
			tooltip = "Say so when your companion has the same role as you (a tank with a tanking Brann)." },
		{ type = "checkbox", key = "nextNeedsKey", label = "Suggest bountiful delves only with a key",
			tooltip = "Next up's bountiful delve suggestion waits until you have a Restored Coffer Key." },
	},
	commands = {
		{ "open", "open the Delves page", Open },
		{ "list", "today's delves (bountiful marked) and your keys, in chat", List },
		{ "vault", "the Great Vault World plan and the tier ladder, in chat", Vault },
	},
})
```

  - **Events:**
    - `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `AREA_POIS_UPDATED` → `DelvesScan_Invalidate()` plus a panel
      refresh.
    - `CURRENCY_DISPLAY_UPDATE`, `BAG_UPDATE_DELAYED` → `Dirty("keys")`.
    - `WEEKLY_REWARDS_UPDATE` → `Dirty("vault")`.
    - `UPDATE_FACTION`, `TRAIT_CONFIG_UPDATED`, `DELVES_ACCOUNT_DATA_ELEMENT_CHANGED`,
      `PLAYER_SPECIALIZATION_CHANGED` → `Dirty("companion")`.
    - `ns.Delves_Changed()` calls `ns.Panel_Refresh()` only when the panel is shown (check how Weekly does it and
      do the same).
  - `PAGE = { kind = "page", key = "delves", order = 8, name = "Delves", icon = "Interface\\Icons\\INV_Misc_Key_15",
    page = ns.DelvesPage, summary = Summary }`. Summary is "2 bountiful · 3 keys", or "Delves open at level N".
    Check the icon path exists (`/dump GetFileIDFromPath(...)` in game), else use the atlas of a delve entrance.
  - `AROUND = { kind = "around", key = "delvesaround", order = 6, name = "Delves", maxRows = 3, open = Open, ... }`:
    - `title`: "Delves: n bountiful here" or "Delves: n here".
    - `items(limit)`: `DelvesScan_List()` filtered to `map == DelvesScan_PlayerZone()`, as rows `{ icon, text, right =
      "Bountiful" | nil, color = bountiful and "accent", onClick = Track, onEnter = Tooltip }`.
    - Empty when `db.around` is off or there are none (no `keepEmpty`).
  - `NEXT_BOUNTIFUL` (`nextbountiful`, score 60):
    - Candidates come from the bountiful entries, only when `keys > 0` or `not db.nextNeedsKey`.
    - `key = "delves:bountiful:" .. e.poi`, `text = "Bountiful delve: " .. e.name`, `why = zone .. " · " .. keyLine`.
    - `bonus = 9` in your zone; `onClick` tracks, with `hint = "Click to track it"`.
  - `NEXT_TIER` (`nextdelvetier`, score 55):
    - Only when `plan.advice` exists and `plan.advice.unlocked`, and only at `ns.ContentAtMax()`.
    - `key = "delves:tier:" .. advice.index`, `state = advice.tier`, `text = plan.text`.
    - `onClick` opens the page, with `stay = true`.
  - `NEXT_ROLE` (`nextcompanionrole`, score 45): the role hint, `key = "delves:role"`, `state = role`; `onClick`
    opens the page.
  - **Content check:** `ns.Content_AddCheck("delves", fn)` returns:
    - "N zones, M delves, B bountiful";
    - "companion: <name> level L (season faction F, expansion X)";
    - "!no delves table" when the expansion has none.
- [ ] **Step 2: TOC.** After `Modules/Pets/Pets.lua`, add:

```
Modules/Delves/Data.lua
Modules/Delves/Scan.lua
Modules/Delves/Read.lua
Modules/Delves/Entrance.lua
Modules/Delves/Page.lua
Modules/Delves/Delves.lua
```

- [ ] **Step 3: Docs.**
  - **README:** a module row "Delves | World |" with the player-facing summary; `/tomte delves list` and
    `/tomte delves vault` under Commands; "Delves" in the Layout's module list.
  - **README Credits:** "Delves: delve POI, currency, item and companion faction IDs from Plumber (GPLv3; IDs only);
    Midnight map IDs also from RareScanner."
  - **CHANGELOG Unreleased:** "New Delves module: today's bountiful delves (click to track), coffer keys and shards,
    which tier raises your Great Vault, your companion's level, role and curios, and a note beside the delve tier
    picker; Next up, Around you and a companion level moment."
- [ ] **Step 4:** Run the whole suite from `AddOns`: `for t in Tomte/tests/test_*.lua; do lua "$t"; done`. Every
  file passes, including the theme scan and `test_modules.lua`.

### Task 9: Review and in-game check

- [ ] One reviewer agent reads the branch diff against the spec and this plan, and checks:
  - the Global constraints;
  - each Review focus line;
  - the API facts marked "check" in Tasks 4–6.
  Fix its findings and re-run the tests.
- [ ] Hand the user this in-game checklist (War Within, level 80). After `/reload`, BugSack should stay empty
  throughout.
  1. `/tomte data`: the delves line lists zones, delves and bountiful counts, and the companion with its season
     faction and expansion.
  2. `/tomte delves list`: the bountiful ones match the bountiful icons on each Khaz Algar zone map.
  3. Click a bountiful row on the Delves page: the Waypoints marker shows the delve's name. Click one in K'aresh from
     Dornogal: a map pin with a portal route.
  4. The key line matches the currency tab (Restored Coffer Key) and your bags (shards). "keys this week" matches
     the Weekly board's Activities tab.
  5. `/tomte delves vault` matches the Great Vault's World row tooltips (tier per slot, "Run a Tier N delve" item
     level).
  6. The companion part matches Brann's window (level, role, both curios). If role and curios are missing, report
     the `/tomte data` companion line: it means the season companion is Midnight's (spec "Things only the game can
     answer").
  7. Open a delve entrance: the note sits right of the tier picker, with sensible lines, and closes with it.
  8. Home: "Around you" has a Delves block in a delve zone; Next up shows "Bountiful delve: ..." when you hold a key.
  9. `/tomte moments preview companion` shows the banner.
