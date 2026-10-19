# Polish: collections and ambience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the audit's findings in Pets, Collect, Achievements, DressUp, Showcase, Moments and AFK: the AFK screen
gives way to more popups, the tamer table moves into `Data/<Expansion>/`, the Heal button and its key behave when the
spell is unknown or the module is off, and smaller fixes (inspect, toast frequency, OnUpdate, defaults, pcall, camera
view, tooltips).

**Architecture:** Pure rules go into each module's pure file with a test (`Modules/AFK/Data.lua`,
`Modules/Collect/Data.lua`, `Modules/Showcase/Data.lua`, `Modules/Pets/Tamers.lua`, `Modules/Pets/Data.lua`); the
tamer data moves to `Data/<Expansion>/Pets.lua` via `ns.Content_Register` and is merged at load. `Modules/Pets/Battle.lua`
is split first (pure move to `Modules/Pets/Read.lua`), before any Pets behavior change.

**Tech Stack:** Lua 5.1 (WoW 12.1.5 retail), plain-Lua unit tests in tests/.
**Spec:** docs/superpowers/specs/2026-10-19-tomte-polish-collections-design.md

## Global Constraints

- Files are CRLF: edit Lua only with the Edit/Write tools (no sed, awk or heredocs on repo files).
- Every Lua file starts `local addonName, ns = ...` then a header comment; tabs, about 120 columns, double quotes.
- Comments say why, no TODOs, no commented-out code; fix comments that point at moved code in the same change.
- Only `ns.<Prefix>_<Name>` cross-file names; no new globals except the existing `Tomte*` frame names.
- Expansion IDs and lists live in `Data/<Expansion>/` through `ns.Content_Register`, never in a module.
- Check warcraft.wiki.gg before using any API or event (done for those named here, 2026-10-19).
- Test any value that can be secret with `ns.IsSecret` / `ns.Readable` before comparing it.
- Secure frames: no attribute changes in combat; keep the existing `InCombatLockdown()` guards and their comments.
- A module turned off undoes everything (events, timers, shown frames); `hooksecurefunc` hooks check `module.active`.
- Every saved key has a default with a comment for a non-obvious shape; no renames without a migration.
- No numeric colors, `|cff` literals or font paths: colors by role (`UI.Color`, `UI.RGB`).
- Cinematics never lock controls; the AFK screen keeps ending on any key or click.
- No `pcall` around our own code.
- Run every test from the AddOns folder; after a TOC change run `lua Tomte/tools/bugfiles.lua`.
- No commit before the user confirmed the change in game, except the pure-move split (Task 1), which only needs the
  in-game smoke check in its last step. Commit messages `<Module>: what changed`; CHANGELOG lines in player wording.
- Public repo: made-up names only (Aldric, Kesha, Mira) in examples and tests.

## Review Focus

1. **Pets off, Heal key still casts.** A `CLICK TomtePetHeal:LeftButton` binding clicks a secure button whatever the
   module's state, and turning the module off in combat can't clear its attributes. Owned by Task 4: in-game check
   "turn Pet Battles off (also once while in combat), press the Heal key: nothing casts".
2. **Tamer list silently changed by the data move.** A dropped block or a wrong expansion number would lose fights
   or reorder the list with no error. Owned by Task 2: the fingerprint test (counts, section order, ID sums) taken
   from the table before the move.
3. **AFK screen closing on events that aren't popups.** `LFG_LIST_APPLICATION_STATUS_UPDATED` fires for every
   status change; closing on "applied" or "declined" would hide the screen for the whole AFK. Owned by Task 5: the
   "only when invited" test.
4. **"Target's outfit" breaking Blizzard's Inspect window.** Owned by Task 6: in-game check with the Inspect window
   open on the same and on another player.
5. **Showcase taking a view the player uses.** Owned by Task 11: the PickView test and the in-game check with a key
   on Set View 5.

---

### Task 1: Split Pets Battle into Battle and Read (pure moves)

**Files:**
- Create `Modules/Pets/Read.lua`
- Modify `Modules/Pets/Battle.lua` (move lines 96-260; header lines 3-8; `ns.PetsBattle_Init` at about line 902)
- Modify `Modules/Pets/Pets.lua` (defaults comment, about line 55)
- Modify `Tomte.toc` (after `Modules/Pets/Journal.lua`, line 247)
- Regenerate `Core/BugFiles.lua`

**Interfaces:**
- Produces: `ns.PetsRead_Init(db)`, `ns.PetsRead_Cache()`, `ns.PetsRead_ResetCache()`, `ns.PetsRead_Api` (table),
  `ns.PetsRead_Side(o)`.
- Consumes: nothing new.

- [ ] Create `Modules/Pets/Read.lua` with this head, then the block from `Battle.lua` lines 96-260 copied verbatim
  (from `-- Round counters and played pets ...` through the `end` of `ReadSide`), then the exports:

```lua
local addonName, ns = ...

-- Pet Battles: reads the battle. The round counters and played pets as Pet Battle Scripts counts them (in db.cache,
-- so they survive a /reload), the live api the script interpreter calls (Script.lua lists its methods) and ReadSide,
-- the plain tables the matchup rules (Data.lua) and the battle helper (Battle.lua) use.

local ALLY, ENEMY = 1, 2

local db

function ns.PetsRead_Init(moduleDB)
	db = moduleDB
end

-- (verbatim: Battle.lua lines 96-260)

ns.PetsRead_Cache = Cache
ns.PetsRead_ResetCache = ResetCache
ns.PetsRead_Api = api
ns.PetsRead_Side = ReadSide
```

- [ ] In `Battle.lua`, delete lines 96-260 (and the blank line after them) and add, right after
  `local IsSecret = ns.IsSecret`:

```lua
local Cache, ResetCache = ns.PetsRead_Cache, ns.PetsRead_ResetCache
local api, ReadSide = ns.PetsRead_Api, ns.PetsRead_Side
```

- [ ] In `ns.PetsBattle_Init`, before:

```lua
	db, module = moduleDB, mod
	if not db.cache then
```

  after:

```lua
	db, module = moduleDB, mod
	ns.PetsRead_Init(db)
	if not db.cache then
```

- [ ] Header of `Battle.lua`, replace "reads the battle into plain tables for the matchup rules (Data.lua) and the
  script interpreter (Script.lua), keeps the round counters the scripts use (they survive a /reload), and draws" with
  "uses Read.lua's readers (round counters, the interpreter's api, the plain tables for the matchup rules) and
  draws". In `Pets.lua`'s defaults comment, `cache (round counters, Battle.lua)` becomes
  `cache (round counters, Read.lua)`.
- [ ] `Tomte.toc`: add `Modules/Pets/Read.lua` on the line after `Modules/Pets/Journal.lua`. Run
  `lua Tomte/tools/bugfiles.lua`.
- [ ] Check: `wc -l Tomte/Modules/Pets/Battle.lua` is under 800. `luac -l Tomte/Modules/Pets/Read.lua | grep -E
  'GETGLOBAL|GETTABUP.*_ENV'` lists only `C_PetBattles`, `C_PetJournal`, `Enum`, `PET_BATTLE_PAD_INDEX`, `_G`,
  `select`, `ipairs`, `pairs`; the same for `Battle.lua` lists no `Cache`, `ResetCache`, `api`, `ReadSide`, `db`.
- [ ] Run all tests (command in Task 13): all pass.
- [ ] In game: `/reload`, fight one wild pet battle. The helper shows the enemy team and "Round N" counts up; no
  BugSack error. Then commit: `Split Pets Battle into Battle and Read (pure moves)`. No CHANGELOG line.

### Task 2: Pet tamer tables move to Data/<Expansion>/Pets.lua

**Files:**
- Create `Data/Midnight/Pets.lua`, `Data/WarWithin/Pets.lua`, `Data/Older/Pets.lua`
- Rewrite `Modules/Pets/Tamers.lua` (671 lines -> the merger)
- Modify `tests/test_pets.lua` (loads at lines 1-4; tamer tests at lines 404-422)
- Modify `Modules/Pets/Pets.lua` header (line 7: "the tamer table in Tamers.lua")
- Modify `Tomte.toc` (after `Data/Older/Gold.lua`, line 43); regenerate `Core/BugFiles.lua`

**Interfaces:**
- Produces: `ns.Content_Register(e, "petSections", list)`, `ns.Content_Register(e, "petEncounters", map)`,
  `ns.Pets_MergeTamers(expansions, get) -> sections, encounters, dupes`; `ns.PETS_SECTIONS` and
  `ns.PETS_ENCOUNTERS` keep their shape (sections still carry `expansion`).
- Consumes: `ns.Content_Expansions`, `ns.Content_Get`, `ns.Content_AddCheck` (Core/Content.lua).

- [ ] Write the failing tests. In `tests/test_pets.lua` replace the line
  `assert(loadfile("Tomte/Modules/Pets/Tamers.lua"))("Tomte", ns)` with:

```lua
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
for _, file in ipairs({ "Data/WarWithin/Pets.lua", "Data/Midnight/Pets.lua", "Data/Older/Pets.lua" }) do
	assert(loadfile("Tomte/" .. file))("Tomte", ns)
end
assert(loadfile("Tomte/Modules/Pets/Tamers.lua"))("Tomte", ns)
```

  and add after the existing tamer tests:

```lua
test("tamer merge: newest expansion first, file order inside one, expansion set", function()
	local reg = {
		[4] = { petSections = { { id = 3, name = "Old" } },
			petEncounters = { [1] = { section = 3, name = "Aldric", npcs = { 9 } } } },
		[10] = { petSections = { { id = 104, name = "New" }, { id = 105, name = "Newer list" } },
			petEncounters = { [1589] = { section = 104, name = "Kesha", npcs = { 8 } } } },
	}
	local sections, encounters, dupes = ns.Pets_MergeTamers({ 4, 10 }, function(e, key)
		return reg[e] and reg[e][key]
	end)
	eq(sections[1].id, 104)
	eq(sections[2].id, 105)
	eq(sections[3].id, 3)
	eq(sections[1].expansion, 10)
	eq(sections[3].expansion, 4)
	eq(encounters[1].name, "Aldric")
	eq(encounters[1589].name, "Kesha")
	eq(#dupes, 0)
end)

test("tamer merge: an encounter id registered twice is reported, the newer kept", function()
	local reg = {
		[4] = { petEncounters = { [7] = { section = 3, name = "Mira", npcs = { 1 } } } },
		[10] = { petEncounters = { [7] = { section = 104, name = "Kesha", npcs = { 2 } } } },
	}
	local _, encounters, dupes = ns.Pets_MergeTamers({ 4, 10 }, function(e, key)
		return reg[e] and reg[e][key]
	end)
	eq(list(dupes), "7")
	eq(encounters[7].name, "Kesha")
end)

test("tamer data: no encounter id in two expansions", function()
	local _, _, dupes = ns.Pets_MergeTamers(ns.Content_Expansions(), ns.Content_Get)
	eq(list(dupes), "")
end)

test("tamer data: Midnight holds the five Family Battler sections", function()
	local ids = {}
	for i, s in ipairs(ns.Content_Get(11, "petSections")) do
		ids[i] = s.id
	end
	eq(list(ids), "114,115,116,117,118")
end)

-- Taken from the single-file table before the move (2026-10-19): the move must not lose or reorder anything.
test("tamer data: same sections and fights as before the move", function()
	local ids = {}
	for i, s in ipairs(ns.PETS_SECTIONS) do
		ids[i] = s.id
	end
	eq(list(ids), "114,115,116,117,118,104,105,111,107,94,97,98,99,100,101,70,73,72,74,51,54,61,62,52,66,60,53,"
		.. "16,17,35,28,42,36,33,31,2,5,9,12,3,6,10,8,7")
	local perExpansion = {}
	for _, s in ipairs(ns.PETS_SECTIONS) do
		perExpansion[s.expansion] = (perExpansion[s.expansion] or 0) + 1
	end
	eq(list({ perExpansion[4], perExpansion[5], perExpansion[6], perExpansion[7], perExpansion[8], perExpansion[9],
		perExpansion[10], perExpansion[11] }), "5,4,8,8,4,5,5,5")
	local count, idSum, npcSum, npcCount, nameBytes, sectionSum = 0, 0, 0, 0, 0, 0
	for id, e in pairs(ns.PETS_ENCOUNTERS) do
		count, idSum, sectionSum, nameBytes = count + 1, idSum + id, sectionSum + e.section, nameBytes + #e.name
		for _, npc in ipairs(e.npcs) do
			npcSum, npcCount = npcSum + npc, npcCount + 1
		end
	end
	eq(count, 524, "encounters")
	eq(idSum, 416150, "encounter id sum")
	eq(sectionSum, 26116, "section sum")
	eq(npcCount, 541, "npc count")
	eq(npcSum, 67118418, "npc id sum")
	eq(nameBytes, 10860, "name bytes")
end)
```

- [ ] Run `lua Tomte/tests/test_pets.lua`: fails (no `Data/WarWithin/Pets.lua`).
- [ ] Create the three data files with the Write tool, each block copied verbatim from the current `Tamers.lua`,
  minus each section's `expansion = n,` field (where the file registers it says that now). Every file has the same
  header shape:

```lua
local addonName, ns = ...

-- The War Within (expansion 10): pet battle tamers. See Core/Content.lua; merged in Modules/Pets/Tamers.lua.
-- Every NPC battle on Xu-Fu's Pet Guides (https://www.wow-petguide.com), from its section pages, 2026-10-10. Encounter
-- keys are Xu-Fu's encounter page ids (https://www.wow-petguide.com/Encounter/<id>), npcs are the game's NPC ids for
-- that fight. Ids are facts; no strategy content is copied. Names are Xu-Fu's English labels (they title links to an
-- English site); nothing matches on them. One NPC can be in several encounters (a world quest and a Family Battler
-- set). Registered under the expansion that added the content. kind, for the Guides window: "wq" (a pet battle
-- world quest), "family" (a Family Battler style achievement) or "tradingpost".

local E = 10

ns.Content_Register(E, "petSections", {
	{ id = 104, name = "The War Within world quests", kind = "wq" },
	{ id = 105, name = "Family Battler of Khaz Algar", kind = "family" },
	{ id = 111, name = "Undermine" },
	{ id = 107, name = "Incognitro mount hunt" },
	{ id = 94, name = "Gurgl, the blue murloc" },
})

ns.Content_Register(E, "petEncounters", {
	-- [Xu-Fu encounter id] = { section, name, npcs = { npcID, ... } }
	-- (verbatim: Tamers.lua lines 108-135, "The War Within world quests" through "Gurgl, the blue murloc")
})
```

  - `Data/Midnight/Pets.lua` (`local E = 11`): sections 114-118 (Tamers.lua lines 11-15), encounters lines 60-107.
    Its header's first line reads `-- Midnight (expansion 11): pet battle tamers. ...` and adds: "Midnight added no
    tamers in its own zones (Xu-Fu news 581, 2025-11-11: "No new tamers will be added to the upcoming/revamped
    zones"; Xu-Fu's Midnight menu checked 2026-10-19): its pet battle content is these Family Battler achievements
    for old-world tamers. The author doesn't own Midnight: shipped untested for a Midnight owner."
  - `Data/Older/Pets.lua`: header `-- Older expansions (Mists of Pandaria to Dragonflight): pet battle tamers. ...`;
    one `petSections` and one `petEncounters` registration per expansion, newest first: 9 (sections 97, 98, 99, 100,
    101; encounters lines 136-206), 8 (70, 73, 72, 74; lines 207-252), 7 (51, 54, 61, 62, 52, 66, 60, 53; lines
    253-380), 6 (16, 17, 35, 28, 42, 36, 33, 31; lines 381-529), 5 (2, 5, 9, 12; lines 530-625), 4 (3, 6, 10, 8, 7;
    lines 626-670), each with a comment naming the expansion (`-- Dragonflight`, ...).
- [ ] Replace all of `Modules/Pets/Tamers.lua` with:

```lua
local addonName, ns = ...

-- Pet Battles: the tamer table, merged from Data/<Expansion>/Pets.lua (pure logic: no WoW API calls; unit-tested in
-- tests/test_pets.lua). Each expansion registers "petSections" (Xu-Fu's sections, in list order) and "petEncounters"
-- ([Xu-Fu encounter id] = { section, name, npcs }) under the expansion that added the content; sources and fields are
-- described in Data/WarWithin/Pets.lua. The list covers every expansion on purpose (any character can fight old
-- tamers), so it doesn't follow the character's content expansion.

-- expansions: oldest first (ns.Content_Expansions), get = ns.Content_Get. Returns sections (newest expansion first,
-- registration order inside one; each gets .expansion), encounters (one map) and dupes (encounter ids registered by
-- two expansions, sorted; the newer one is kept).
function ns.Pets_MergeTamers(expansions, get)
	local sections, encounters, dupes = {}, {}, {}
	for i = #expansions, 1, -1 do
		local e = expansions[i]
		for _, s in ipairs(get(e, "petSections") or {}) do
			s.expansion = e
			sections[#sections + 1] = s
		end
		for id, encounter in pairs(get(e, "petEncounters") or {}) do
			if encounters[id] then
				dupes[#dupes + 1] = id
			else
				encounters[id] = encounter
			end
		end
	end
	table.sort(dupes)
	return sections, encounters, dupes
end

ns.PETS_SECTIONS, ns.PETS_ENCOUNTERS = ns.Pets_MergeTamers(ns.Content_Expansions(), ns.Content_Get)

-- /tomte data: what this expansion adds to the list (a Midnight owner can paste it).
ns.Content_AddCheck("Pet tamers", function(expansion)
	local count = 0
	for _ in pairs(ns.Content_Get(expansion, "petEncounters") or {}) do
		count = count + 1
	end
	local sections = ns.Content_Get(expansion, "petSections") or {}
	return { ("%d sections and %d fights from this expansion; %d sections in all"):format(#sections, count,
		#ns.PETS_SECTIONS) }
end)
```

- [ ] `Tomte.toc`: after `Data/Older/Gold.lua` add `Data/WarWithin/Pets.lua`, `Data/Midnight/Pets.lua`,
  `Data/Older/Pets.lua`. Run `lua Tomte/tools/bugfiles.lua`.
- [ ] `Pets.lua` header: "the tamer table in Tamers.lua" becomes "the tamer table in Data/<Expansion>/Pets.lua,
  merged in Tamers.lua".
- [ ] Run `lua Tomte/tests/test_pets.lua`: passes (the fingerprint test is what proves the move).
- [ ] `luac -l` check on the four files: only `ipairs`, `pairs`, `table` as globals.
- [ ] In game: `/reload`, open the Pet Battles page's tamer list: Midnight's Family Battler sections at the top,
  Darkmoon Faire at the bottom, same as before. `/tomte data` shows a "Pet tamers:" line ("5 sections and 18 fights
  from this expansion; 44 sections in all" on a War Within character). Pure refactor: no CHANGELOG line; commit
  `Pets: tamer table moves to Data/<Expansion>/ (no behavior change)` once confirmed.

### Task 3: Pets: tamer names in the game's language

**Files:**
- Modify `Modules/Pets/Data.lua` (new function near `ns.Pets_IndexEncounters`, line 114)
- Modify `Modules/Pets/Store.lua` (`ns.PetsStore_NPCName`, lines 102-110)
- Modify `Modules/Pets/Page.lua` (tamer list search, line 334)
- Modify `tests/test_pets.lua`

**Interfaces:**
- Produces: `ns.Pets_CreatureLink(npc) -> string`, `ns.PetsStore_KnownName(npc) -> string|nil`.
- Consumes: `C_TooltipInfo.GetHyperlink` (wiki: returns `TooltipData`, added 10.0.2), `ns.IsSecret`.

- [ ] Gate first. In game, out of combat: `/dump C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-64330-0000000000")`
  (Julia Stevens, Elwynn). Expected: a table whose `lines[1].leftText` is "Julia Stevens". If it's nil, run it once
  more (creature data may load on request). Still nil: stop this task, drop it from the CHANGELOG list and report it
  to the user; Tasks 4-13 don't depend on it.
- [ ] Failing test in `tests/test_pets.lua`:

```lua
test("creature link for the name lookup", function()
	eq(ns.Pets_CreatureLink(64330), "unit:Creature-0-0-0-0-64330-0000000000")
end)
```

- [ ] Run `lua Tomte/tests/test_pets.lua`: fails. Add to `Modules/Pets/Data.lua`:

```lua
-- A unit hyperlink for an NPC id: the game's tooltip for it names the creature in the client's language.
function ns.Pets_CreatureLink(npc)
	return ("unit:Creature-0-0-0-0-%d-0000000000"):format(npc)
end
```

- [ ] Run: passes.
- [ ] `Store.lua`, before:

```lua
-- A name to show for an NPC: what the game called it, else the tamer table's encounter name.
function ns.PetsStore_NPCName(npc)
	local learned = npc and db.learned[npc]
	if learned and learned.name then
		return learned.name
	end
	local e = ns.PetsStore_Encounters(npc)[1]
	return e and e.name or (npc and ("NPC " .. npc)) or "?"
end
```

  after:

```lua
local cachedNames = {} -- [npcID] = the creature's name from the game's cache, this session

-- The creature's name in the client's language when the game has it cached; nil otherwise (a later call may have it).
local function CreatureName(npc)
	if not cachedNames[npc] then
		local data = C_TooltipInfo.GetHyperlink(ns.Pets_CreatureLink(npc))
		local text = data and data.lines and data.lines[1] and data.lines[1].leftText
		if text and not ns.IsSecret(text) and text ~= "" then
			cachedNames[npc] = text
		end
	end
	return cachedNames[npc]
end

-- A name the game already gave this NPC (gossip, target or the creature cache), without asking: for the search.
function ns.PetsStore_KnownName(npc)
	local learned = npc and db.learned[npc]
	return learned and learned.name or (npc and cachedNames[npc])
end

-- A name to show for an NPC: what the game called it, else its cached creature name, else the tamer table's label.
function ns.PetsStore_NPCName(npc)
	local known = ns.PetsStore_KnownName(npc) or (npc and CreatureName(npc))
	if known then
		return known
	end
	local e = ns.PetsStore_Encounters(npc)[1]
	return e and e.name or (npc and ("NPC " .. npc)) or "?"
end
```

- [ ] `Page.lua`, above `function v:Render()` of the tamer list, add:

```lua
	-- The search also finds a tamer by a name the game already gave it (another client language than the labels).
	local function KnownNameMatches(npcs, query)
		for _, npc in ipairs(npcs) do
			local name = ns.PetsStore_KnownName(npc)
			if name and name:lower():find(query, 1, true) then
				return true
			end
		end
		return false
	end
```

  and change `if query == "" or e.name:lower():find(query, 1, true) then` to
  `if query == "" or e.name:lower():find(query, 1, true) or KnownNameMatches(e.npcs, query) then`.
- [ ] Run all tests; `luac -l` on `Store.lua` and `Page.lua`: no new globals except `C_TooltipInfo`.
- [ ] In game: talk to Julia Stevens (Elwynn Forest) or any tamer: the card's title is the game's name for her.
  `/tomte pets open`, Tamers: rows look as before; searching a tamer you've talked to by its in-game name finds it.
  CHANGELOG (after confirmation): "Pet Battles: tamer cards and the links window show tamer names in your game's
  language."

### Task 4: Pets: Heal button when the spell is unknown, and nothing left running when off

**Files:**
- Modify `Modules/Pets/Journal.lua` (Heal section, lines 174-334)
- Modify `Modules/Pets/Battle.lua` (`events:PLAYER_REGEN_ENABLED`, `ns.PetsBattle_Toggle`)

**Interfaces:**
- Produces: `ns.PetsHeal_CanHeal() -> boolean`, `ns.PetsHeal_Disarm() -> boolean` (false: in combat, not done).
  `ns.PetsHeal_Ensure()` now arms and refreshes on every call.
- Consumes: `C_SpellBook.IsSpellKnown(spellID)` (wiki: `isKnown = C_SpellBook.IsSpellKnown(spellID [, spellBank])`).

- [ ] `Journal.lua`: replace `local holder, heal` with:

```lua
local holder, heal
local armed = false -- the module is on: Refresh may give the button an action (Disarm takes it away)

local function ReviveKnown()
	return C_SpellBook.IsSpellKnown(REVIVE)
end
```

  and after `BandageCount` add:

```lua
-- Can the button do anything: Revive Battle Pets learned, or a Battle Pet Bandage in the bags?
function ns.PetsHeal_CanHeal()
	return ReviveKnown() or BandageCount() > 0
end
```

- [ ] `HealTooltip`, before:

```lua
	local ready, left = ReviveReady()
	if not ready then
```

  after:

```lua
	local ready, left = ReviveReady()
	if self.unknown then
		GameTooltip:AddLine("You haven't learned Revive Battle Pets yet: a Battle Pet Trainer teaches it.",
			UI.RGB("warning"))
	elseif not ready then
```

- [ ] `ns.PetsHeal_Ensure`, before:

```lua
function ns.PetsHeal_Ensure()
	if not holder and not InCombatLockdown() then
		CreateHeal()
		ns.PetsHeal_Refresh()
	end
end
```

  after (comment above it becomes "Makes the button (hidden) and arms it, so its key binding works from the start.
  Out of combat only."):

```lua
function ns.PetsHeal_Ensure()
	if InCombatLockdown() then
		return
	end
	armed = true
	if not holder then
		CreateHeal()
	end
	ns.PetsHeal_Refresh()
end
```

- [ ] `ns.PetsHeal_Refresh`: the first guard becomes `if not heal or not armed or InCombatLockdown() then`; replace
  the body from `local ready, _, start, duration = ReviveReady()` to the end with:

```lua
	local known = ReviveKnown()
	local ready, _, start, duration = ReviveReady()
	local bandages = BandageCount()
	heal.useBandage = (not known or not ready) and bandages > 0
	heal.unknown = not known and not heal.useBandage -- nothing to heal with: no action, the tooltip says why
	local name = C_Spell.GetSpellName(REVIVE)
	if heal.useBandage then
		heal:SetAttribute("type", "macro")
		heal:SetAttribute("macrotext", "/use item:" .. BANDAGE)
		heal.icon:SetTexture(C_Item.GetItemIconByID(BANDAGE))
		heal.count:SetText(bandages)
		heal.label:SetText("Bandage")
	else
		-- A /cast macro rather than type=spell: on 12.1 type=spell silently failed to cast mounts (Smart Mount), and
		-- whether it would work for Revive Battle Pets hasn't been tested.
		local action = known and name
		heal:SetAttribute("type", action and "macro" or nil)
		heal:SetAttribute("macrotext", action and ("/cast " .. name) or nil)
		heal.icon:SetTexture(C_Spell.GetSpellTexture(REVIVE))
		heal.count:SetText("")
		heal.label:SetText("Heal pets")
	end
	local waiting = not heal.unknown and not ready and not heal.useBandage
	heal.icon:SetDesaturated(heal.unknown or waiting)
	if waiting then
		heal.cooldown:SetCooldown(start, duration)
	else
		heal.cooldown:Clear()
	end
```

- [ ] `ns.PetsHeal_ShowAfterBattle`: first line `if not ns.PetsHeal_CanHeal() then return end` (nothing to offer:
  no button after the battle; the tamer card still shows it, greyed, with the reason).
- [ ] After `ns.PetsHeal_OnCombat` add:

```lua
-- Module off: the button and its key binding do nothing until Ensure. A secure button's attributes can't change in
-- combat: returns false then, and the caller disarms once combat ends.
function ns.PetsHeal_Disarm()
	if healTimer then
		healTimer:Cancel()
		healTimer = nil
	end
	if InCombatLockdown() then
		return false
	end
	armed = false
	if heal then
		heal:SetAttribute("type", nil)
		heal:SetAttribute("macrotext", nil)
		holder:Hide()
	end
	return true
end
```

- [ ] `Battle.lua`, `ns.PetsBattle_Toggle` else-branch, before:

```lua
		events:UnregisterAllEvents()
		ctx = nil
		ns.PetsHeal_Hide()
```

  after:

```lua
		events:UnregisterAllEvents()
		ctx = nil
		if not ns.PetsHeal_Disarm() then
			events:RegisterEvent("PLAYER_REGEN_ENABLED") -- turned off in combat: disarm the Heal key once it ends
		end
```

  and `events:PLAYER_REGEN_ENABLED` starts with:

```lua
	if not module.active then
		ns.PetsHeal_Disarm()
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
```

- [ ] Run all tests; `luac -l Journal.lua` lists `C_SpellBook` and no `armed`/`healTimer` global.
- [ ] In game (level 80, Revive Battle Pets known): win a pet battle with a hurt pet: the Heal button shows and
  heals. Settings > Pet Battles off: press the Heal key: nothing; on again: the key heals again. Off while in combat
  (fight a mob, open the Tomte window, switch it off), leave combat, press the key: nothing. On a new alt without
  the spell and no bandage: talk to a tamer: the card's Heal is greyed, its tooltip says "You haven't learned Revive
  Battle Pets yet ..."; no Heal pops up after a wild battle. CHANGELOG: "Pet Battles: the Heal button is greyed out
  with the reason when you haven't learned Revive Battle Pets, and its key does nothing while Pet Battles is off."

### Task 5: AFK Screen gives way to more popups

**Files:**
- Modify `Modules/AFK/Data.lua` (append), `Modules/AFK/AFK.lua` (lines 5, 12-15, 240-253), `tests/test_afk.lua`

**Interfaces:**
- Produces: `ns.AFK_INTERRUPTS` (event -> `true` | `{ arg, value }`), `ns.AFK_Interrupts(event, ...) -> boolean`.
- Consumes: `C_EventUtils.IsEventValid(eventName)` (wiki: added 10.0.0), `ns.Readable`.

- [ ] Failing tests, append to `tests/test_afk.lua` before `H.done()`:

```lua
test("interrupts: every entry is an event name with a rule", function()
	for event, rule in pairs(ns.AFK_INTERRUPTS) do
		eq(event:match("^[A-Z_]+$") ~= nil, true, "name " .. event)
		eq(rule == true or (type(rule) == "table" and type(rule.arg) == "number" and rule.value ~= nil), true,
			"rule " .. event)
	end
end)

test("interrupts: popups close the screen", function()
	for _, event in ipairs({ "LFG_PROPOSAL_SHOW", "READY_CHECK", "PARTY_INVITE_REQUEST", "CONFIRM_SUMMON",
		"LFG_ROLE_CHECK_SHOW", "LFG_READY_CHECK_SHOW", "PET_BATTLE_QUEUE_PROPOSE_MATCH", "DUEL_REQUESTED",
		"TRADE_REQUEST", "TRADE_SHOW", "RESURRECT_REQUEST", "GUILD_INVITE_REQUEST", "GROUP_INVITE_CONFIRMATION" }) do
		eq(ns.AFK_Interrupts(event), true, event)
	end
end)

test("interrupts: a premade group application only when invited", function()
	local event = "LFG_LIST_APPLICATION_STATUS_UPDATED" -- searchResultID, newStatus, oldStatus, groupName
	eq(ns.AFK_Interrupts(event, 12, "invited", "applied", "Mira's keys"), true)
	eq(ns.AFK_Interrupts(event, 12, "applied", "none", "Mira's keys"), false)
	eq(ns.AFK_Interrupts(event, 12, "declined", "applied", "Mira's keys"), false)
	eq(ns.AFK_Interrupts(event, 12, "inviteaccepted", "invited", "Mira's keys"), false)
	eq(ns.AFK_Interrupts(event), false, "no payload")
end)

test("interrupts: anything else doesn't", function()
	eq(ns.AFK_Interrupts("CHAT_MSG_WHISPER", "hi", "Aldric"), false)
	eq(ns.AFK_Interrupts("UPDATE_BATTLEFIELD_STATUS", 1), false, "AFK.lua checks the status itself")
end)
```

- [ ] Run `lua Tomte/tests/test_afk.lua`: fails. Append to `Modules/AFK/Data.lua` (above the `ns.AFK_MoneyText`
  line):

```lua
-- Popups the AFK screen gives way to: it closes for the rest of this AFK so the popup can be seen. true = always,
-- { arg, value } = only when the payload's arg-th value is value. Names and payloads from warcraft.wiki.gg,
-- 2026-10-19. UPDATE_BATTLEFIELD_STATUS is handled in AFK.lua: it needs GetBattlefieldStatus.
ns.AFK_INTERRUPTS = {
	LFG_PROPOSAL_SHOW = true, -- a Dungeon or Raid Finder group is ready
	READY_CHECK = true,
	PARTY_INVITE_REQUEST = true,
	CONFIRM_SUMMON = true,
	LFG_ROLE_CHECK_SHOW = true,
	LFG_READY_CHECK_SHOW = true,
	LFG_LIST_APPLICATION_STATUS_UPDATED = { arg = 2, value = "invited" }, -- searchResultID, newStatus, ...
	PET_BATTLE_QUEUE_PROPOSE_MATCH = true, -- a PvP pet battle was found
	DUEL_REQUESTED = true,
	TRADE_REQUEST = true,
	TRADE_SHOW = true, -- a trade usually opens straight away, without a request
	RESURRECT_REQUEST = true,
	GUILD_INVITE_REQUEST = true,
	GROUP_INVITE_CONFIRMATION = true, -- someone in your group wants to invite a player
}

function ns.AFK_Interrupts(event, ...)
	local rule = ns.AFK_INTERRUPTS[event]
	if rule == true then
		return true
	end
	if type(rule) == "table" then
		return select("#", ...) >= rule.arg and (select(rule.arg, ...)) == rule.value
	end
	return false
end
```

- [ ] Run: passes.
- [ ] `AFK.lua` line 5 header: "a queue pop, ready check or invite closes it so the popup is visible" becomes "a
  popup (queue pop, ready check, invite, summon, duel, trade ...; Data.lua lists them) closes it so it's visible".
- [ ] `AWAY_EVENTS`, before:

```lua
local AWAY_EVENTS = { -- only while AFK
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
	"LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS", "READY_CHECK", "PARTY_INVITE_REQUEST",
}
```

  after:

```lua
local AWAY_EVENTS = { -- only while AFK; the popups of ns.AFK_INTERRUPTS (Data.lua) are added below Interrupt
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "UPDATE_BATTLEFIELD_STATUS",
}
```

- [ ] Replace

```lua
events.LFG_PROPOSAL_SHOW = Interrupt
events.READY_CHECK = Interrupt
events.PARTY_INVITE_REQUEST = Interrupt
```

  with:

```lua
-- One handler per popup event; an event this client doesn't know is skipped (RegisterEvent would error).
for event in pairs(ns.AFK_INTERRUPTS) do
	if C_EventUtils.IsEventValid(event) then
		AWAY_EVENTS[#AWAY_EVENTS + 1] = event
		events[event] = function(_, ...)
			if (select("#", ...) == 0 or ns.Readable(...)) and ns.AFK_Interrupts(event, ...) then
				Interrupt()
			end
		end
	end
end
```

- [ ] Run all tests; `luac -l AFK.lua` lists `C_EventUtils` and nothing unexpected.
- [ ] In game: `/afk`, wait for the AFK screen. Have a friend (or alt on a second account) challenge you to a duel:
  the screen closes and the duel popup is visible; it stays closed until you come back and go AFK again. Repeat with
  a trade; `/tomte afk preview` then a ready check from a party member closes the preview too. `/etrace` while AFK
  shows the new events registered only while the AFK flag is up. CHANGELOG: "AFK Screen: also gets out of the way
  for summons, role checks, premade group invites, pet battle PvP matches, duels, trades, resurrections and guild
  invites."

### Task 6: Dressing room: Target's outfit leaves the Inspect window alone

**Files:** Modify `Modules/DressUp/Tools.lua` (lines 38-82).

**Interfaces:** Consumes `InspectFrame` / `InspectFrame.unit` (Blizzard_InspectUI, load on demand: may be nil;
`InspectFrame_Show` sets `.unit`, `OnHide` clears it), `UnitIsUnit`.

- [ ] Above `local function TargetOutfit()` add:

```lua
-- Blizzard's Inspect window's unit while it's open (Blizzard_InspectUI loads on demand), else nil. That window owns
-- the inspect then: we may read it but never clear it.
local function InspectWindowUnit()
	return InspectFrame and InspectFrame:IsShown() and InspectFrame.unit or nil
end
```

- [ ] In `TargetOutfit`, before:

```lua
	local actor = BAR.Actor()
	if not actor then
		return
	end
	if not db.ownBody then
```

  after:

```lua
	local inspecting = InspectWindowUnit()
	if inspecting and not UnitIsUnit(inspecting, unit) then
		ns.Print("close the Inspect window first.")
		return
	end
	local actor = BAR.Actor()
	if not actor then
		return
	end
	if not db.ownBody then
```

- [ ] In the `INSPECT_READY` handler, before:

```lua
	local list = C_TransmogCollection.GetInspectItemTransmogInfoList()
	ClearInspectPlayer()
```

  after:

```lua
	local list = C_TransmogCollection.GetInspectItemTransmogInfoList()
	if not InspectWindowUnit() then
		ClearInspectPlayer() -- ours alone; the Inspect window clears its own when it closes
	end
```

- [ ] Run all tests; `luac -l Tools.lua` adds only `InspectFrame`, `UnitIsUnit`.
- [ ] In game, in Dornogal next to another player: open the dressing room (Shift-click an item), target them,
  Target's outfit: their outfit appears. Then inspect them (right-click portrait > Inspect), keep it open, Target's
  outfit again: the outfit appears and the Inspect window still shows their gear and talents. Target someone else
  with the Inspect window still open: chat says "close the Inspect window first." CHANGELOG: "Dressing room:
  Target's outfit no longer empties Blizzard's Inspect window when it's open."

### Task 7: Collect here: zone toast once per zone per day

**Files:** Modify `Modules/Collect/Data.lua` (append after `ns.Collect_ZoneToastText`), `Modules/Collect/Collect.lua`
(line 22, lines 106-121, defaults at line 395), `tests/test_collect.lua`.

**Interfaces:** Produces `ns.Collect_ZoneToastDue(seen, mapID, today)`, `ns.Collect_MarkZoneToast(seen, mapID,
today)`; saved `zoneToasts`.

- [ ] Failing tests, append before `H.done()`:

```lua
test("zone toast: once per zone per day", function()
	local seen = {}
	eq(ns.Collect_ZoneToastDue(seen, 2248, "2026-10-19"), true)
	ns.Collect_MarkZoneToast(seen, 2248, "2026-10-19")
	eq(ns.Collect_ZoneToastDue(seen, 2248, "2026-10-19"), false, "same day")
	eq(ns.Collect_ZoneToastDue(seen, 2214, "2026-10-19"), true, "another zone")
	eq(ns.Collect_ZoneToastDue(seen, 2248, "2026-10-20"), true, "next day")
end)

test("zone toast: marking drops other days", function()
	local seen = { [2248] = "2026-10-18", [2214] = "2026-10-19" }
	ns.Collect_MarkZoneToast(seen, 2215, "2026-10-19")
	eq(seen[2248], nil, "yesterday's")
	eq(seen[2214], "2026-10-19")
	eq(seen[2215], "2026-10-19")
end)
```

- [ ] Run `lua Tomte/tests/test_collect.lua`: fails. Append to `Data.lua`:

```lua
-- Zone toast: once per zone per day. seen = db.zoneToasts ([uiMapID] = "YYYY-MM-DD"), today = the local date.
function ns.Collect_ZoneToastDue(seen, mapID, today)
	return seen[mapID] ~= today
end

-- Marks the zone's toast as shown today and drops other days' entries (the table holds one day at most).
function ns.Collect_MarkZoneToast(seen, mapID, today)
	for id, day in pairs(seen) do
		if day ~= today then
			seen[id] = nil
		end
	end
	seen[mapID] = today
end
```

- [ ] Run: passes.
- [ ] `Collect.lua`: delete `local toastedZones = {} -- [mapID] = true, this session`. In `ZoneToast`, before:

```lua
	if not entries or kind ~= "zone" or toastedZones[mapID] then
		return
	end
	toastedZones[mapID] = true
```

  after:

```lua
	local today = date("%Y-%m-%d")
	if not entries or kind ~= "zone" or not ns.Collect_ZoneToastDue(db.zoneToasts, mapID, today) then
		return
	end
	ns.Collect_MarkZoneToast(db.zoneToasts, mapID, today)
```

- [ ] Defaults: add `zoneToasts = {}, -- [uiMapID] = "YYYY-MM-DD" (local date) the zone toast last showed` and, after
  `defaults`, `noShare = { "zoneToasts" }, -- toast history: not in settings strings (Core/Profile.lua)`.
- [ ] Run all tests.
- [ ] In game: fly into a War Within zone with mounts or pets left: the toast shows. `/reload`: it doesn't show
  again for that zone. `/dump TomteDB.collect.zoneToasts` shows the zone's map ID with today's date. CHANGELOG:
  "Collect here: the zone toast shows once per zone a day instead of after every login and /reload."

### Task 8: Almost Done: the tracker runs no per-frame code while nothing flashes

**Files:** Modify `Modules/Achievements/Tracker.lua` (row OnUpdate at lines 107-117; flash start in
`ns.AchTracker_Refresh`, about line 177).

- [ ] Above `local function CreateRow(i)` add:

```lua
-- A row's flash fading out. Set as OnUpdate when a flash starts, removed when it's done.
local function FlashUpdate(self, dt)
	self.flashLeft = self.flashLeft - dt
	if self.flashLeft <= 0 then
		self.flashLeft = nil
		self.flash:SetAlpha(0)
		self:SetScript("OnUpdate", nil)
	else
		self.flash:SetAlpha(0.25 * self.flashLeft / FLASH)
	end
end
```

- [ ] Delete the `row:SetScript("OnUpdate", function(self, dt) ... end)` block in `CreateRow`.
- [ ] In `ns.AchTracker_Refresh`, before `row.flashLeft = FLASH`, after:

```lua
				row.flashLeft = FLASH
				row:SetScript("OnUpdate", FlashUpdate)
```

- [ ] Run all tests.
- [ ] In game: with the Top 5 tracker shown, make progress on a listed achievement (loot or kill something it
  counts): its row flashes and fades as before, no BugSack error. No CHANGELOG line (no visible change).

### Task 9: Saved keys get defaults (DressUp debug, Showcase debugCamera)

**Files:** Modify `Modules/DressUp/DressUp.lua` (defaults line 178), `Modules/Showcase/Showcase.lua` (defaults line
254), `Modules/AFK/AFK.lua` (defaults).

- [ ] DressUp defaults, after `ownBody = false,` add
  `debug = false, -- chat lines when the dressing room's size is set (hidden /tomte dressup debug)` and after the
  `defaults` table `noShare = { "debug" }, -- a debug switch: not in settings strings (Core/Profile.lua)`.
- [ ] Showcase defaults, after `heights = {}, ...` add
  `debugCamera = false, -- chat lines for each camera step on close (hidden /tomte showcase debug)` and a comment line
  `-- current: the open Showcase's cinematic state, saved for /reload. No default: nil while closed.`; after
  `defaults`, `noShare = { "debugCamera" }, -- a debug switch: not in settings strings (Core/Profile.lua)`.
- [ ] AFK defaults, after `clearAFK = true,` add the comment line
  `-- current: the AFK screen's state, saved for /reload. No default: nil while not AFK.`
- [ ] Run all tests (`test_modules`, `test_profile` included).
- [ ] In game: `/tomte dressup debug` twice prints on then off; `/tomte showcase debug` likewise. No CHANGELOG line.

### Task 10: Moments: discovery parser errors reach BugSack; locale tests

**Files:** Modify `Modules/Moments/Moments.lua` (lines 402-406), `tests/test_moments.lua`.

- [ ] Add tests before `H.done()` (the strings are the game's own, from wago.tools GlobalStrings,
  `ERR_ZONE_EXPLORED_XP` and `ERR_ZONE_EXPLORED`, 2026-10-19; area names made up from each locale's Goldshire):

```lua
-- The game's discovery formats per client language (wago.tools GlobalStrings, ERR_ZONE_EXPLORED_XP and
-- ERR_ZONE_EXPLORED, 2026-10-19): xp format, plain format, an xp message, a plain message, the area.
local LOCALES = {
	{ "deDE", "%1$s entdeckt: %2$d Erfahrung erhalten.", "Entdeckt: %s",
		"Goldhain entdeckt: 30 Erfahrung erhalten.", "Entdeckt: Goldhain", "Goldhain" },
	{ "frFR", "Découverte : %s, %d points d’expérience gagnés", "Découverte : %s",
		"Découverte : Comté-de-l'Or, 30 points d’expérience gagnés", "Découverte : Comté-de-l'Or", "Comté-de-l'Or" },
	{ "esES", "Has descubierto %s: %d p. de experiencia obtenidos.", "Has descubierto: %s",
		"Has descubierto Villadorada: 30 p. de experiencia obtenidos.", "Has descubierto: Villadorada", "Villadorada" },
	{ "ruRU", "Открыта новая территория: %s. Получено %d |4очко:очка:очков; опыта.", "Открыта новая территория: %s",
		"Открыта новая территория: Златоземье. Получено 30 очков опыта.", "Открыта новая территория: Златоземье",
		"Златоземье" },
	{ "koKR", "%s 발견: 경험치 %d 획득", "%s|1을;를; 발견했습니다!",
		"골드샤이어 발견: 경험치 30 획득", "골드샤이어를 발견했습니다!", "골드샤이어" },
	{ "zhCN", "发现%s：获得%d点经验值", "发现：%s", "发现闪金镇：获得30点经验值", "发现：闪金镇", "闪金镇" },
}

test("DiscoveredArea: the game's formats in six client languages", function()
	for _, l in ipairs(LOCALES) do
		local patterns = ns.Moments_DiscoveryPatterns(l[2], l[3])
		eq(ns.Moments_DiscoveredArea(l[4], patterns), l[6], l[1] .. " with xp")
		eq(ns.Moments_DiscoveredArea(l[5], patterns), l[6], l[1] .. " plain")
	end
end)

test("DiscoveredArea: odd formats and messages return, never error", function()
	local formats = { "", "%d", "%s%%", "|4a:b;%s", "%2$s %1$d", "|1x;y;", "%s|4", "100%% %s" }
	local messages = { "", "%", "50% done", "Discovered: (x)", "a:b" }
	for _, fmt in ipairs(formats) do
		local patterns = ns.Moments_DiscoveryPatterns(fmt, fmt)
		for _, message in ipairs(messages) do
			ns.Moments_DiscoveredArea(message, patterns) -- an error here fails the test
		end
	end
end)
```

- [ ] Run `lua Tomte/tests/test_moments.lua`. Expected: passes (checked 2026-10-19 against the current parser). If a
  locale fails, that's a real bug: fix it in `ns.Moments_FormatToPattern` / `ns.Moments_Match` (Data.lua) until it
  passes, and add a CHANGELOG line for that language.
- [ ] `Moments.lua`, before:

```lua
	-- A client format we don't parse right must not raise an error on every info message.
	local ok, area = pcall(ns.Moments_DiscoveredArea, message, discoveryPatterns)
	if not ok or not area then
		return
	end
```

  after:

```lua
	local area = ns.Moments_DiscoveredArea(message, discoveryPatterns)
	if not area then
		return
	end
```

- [ ] Run all tests.
- [ ] In game: the handler runs on every yellow info message. Make quest progress (a "Thing slain: 1/5" line) and,
  on an alt with unexplored areas, ride into a new subzone: the discovery card shows, no BugSack error either time.
  No CHANGELOG line.

### Task 11: Showcase borrows a camera view nobody uses

**Files:** Modify `Modules/Showcase/Data.lua` (Camera section), `Modules/Showcase/Showcase.lua` (lines 11-14, 118,
commands), `tests/test_showcase.lua`.

**Interfaces:** Produces `ns.CharShow_PickView(bound) -> 2..5 | nil`. Consumes `GetBindingKey(command)`; binding
names `SETVIEW2`-`SETVIEW5`, `SAVEVIEW2`-`SAVEVIEW5` (Blizzard_FrameXML/Bindings_Standard.xml, live branch).

- [ ] Failing test, before `H.done()`:

```lua
test("PickView: the highest view with no key bound, none when all are", function()
	local bound = {}
	local function IsBound(view)
		return bound[view] == true
	end
	eq(ns.CharShow_PickView(IsBound), 5)
	bound[5] = true
	eq(ns.CharShow_PickView(IsBound), 4)
	bound[4], bound[3] = true, true
	eq(ns.CharShow_PickView(IsBound), 2)
	bound[2] = true
	eq(ns.CharShow_PickView(IsBound), nil)
end)
```

- [ ] Run `lua Tomte/tests/test_showcase.lua`: fails. Add to `Data.lua`'s Camera section:

```lua
-- The saved camera view (2-5) the Showcase keeps your camera in while open: the highest one without a Set View or
-- Save View key (a player who binds a view uses it). nil when all are bound. bound(view) -> true when one is.
function ns.CharShow_PickView(bound)
	for view = 5, 2, -1 do
		if not bound(view) then
			return view
		end
	end
	return nil
end
```

- [ ] Run: passes.
- [ ] `Showcase.lua`, before:

```lua
-- The game's saved camera view the player's camera is kept in while open (close goes back to it exactly). 5, as
-- Narcissus uses: the views players bind are mostly 1-3.
local SAVED_VIEW = 5
```

  after:

```lua
-- The game's saved camera view the player's camera is kept in while open (close goes back to it exactly). A view
-- can't be read back, so the Showcase only takes one with no key bound (Data.lua); with none free the engine
-- restores zoom and pitch instead, and facing may differ.
local function FreeView()
	return ns.CharShow_PickView(function(view)
		return GetBindingKey("SETVIEW" .. view) ~= nil or GetBindingKey("SAVEVIEW" .. view) ~= nil
	end)
end
```

  and in the `Enter` options `saveView = SAVED_VIEW,` becomes `saveView = FreeView(),`.
- [ ] Commands, after `open`:

```lua
		{ "view", "which camera view the Showcase borrows", function()
			local view = FreeView()
			ns.Print(view and ("the Showcase keeps your camera in view %d (no key is bound to it)."):format(view)
				or "views 2-5 all have keys: the Showcase zooms back on close without a saved view (facing may differ).")
		end },
```

- [ ] Run all tests; `luac -l Showcase.lua` adds only `GetBindingKey`.
- [ ] In game: `/tomte showcase view` says view 5. Key Bindings > Camera: bind Set View 5 to a spare key, set the
  camera at an odd angle, Save View 5 (bind it too, or `/run SaveView(5)`), move the camera, open and close the
  Showcase: the camera returns to where it was before opening; press the Set View 5 key: your odd angle, not the
  Showcase's. `/tomte showcase view` now says view 4. README Commands: add `/tomte showcase view`. CHANGELOG:
  "Showcase: no longer overwrites a camera view you've bound a key to; `/tomte showcase view` says which one it
  borrows."

### Task 12: Tooltips for three settings

**Files:** Modify `Modules/Achievements/Achievements.lua` (line 505), `Modules/Pets/Pets.lua` (Slot dropdown,
about line 133), `Modules/Moments/Moments.lua` (line 688).

- [ ] Achievements, the `tracker.hideInCombat` row gets
  `tooltip = "Hides the tracker while you're in combat; it comes back when the fight ends."`.
- [ ] Pets, the `leveling.slot` dropdown gets `tooltip = "Which of your three team slots holds the leveling pet."`.
- [ ] Moments, the `previewKind` dropdown gets `tooltip = "Which moment the Preview button below shows."`.
- [ ] Run all tests.
- [ ] In game: hover each of the three settings: the tooltip shows. No CHANGELOG line.

### Task 13: Final checks, docs and commits

- [ ] From the AddOns folder: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`:
  no output.
- [ ] `lua Tomte/tools/bugfiles.lua` (TOC changed in Tasks 1 and 2); `lua Tomte/tests/test_bugreport.lua` passes.
- [ ] `for f in Tomte/Modules/Pets/Read.lua Tomte/Modules/Pets/Battle.lua Tomte/Modules/Pets/Tamers.lua
  Tomte/Data/*/Pets.lua Tomte/Modules/Pets/Store.lua Tomte/Modules/Pets/Journal.lua Tomte/Modules/AFK/AFK.lua
  Tomte/Modules/DressUp/Tools.lua Tomte/Modules/Collect/Collect.lua Tomte/Modules/Showcase/Showcase.lua; do echo
  "== $f"; luac -l "$f" | grep -E 'GETGLOBAL|GETTABUP.*_ENV' | sed 's/.*; //' | sort -u; done`: only WoW API and Lua
  globals.
- [ ] README: AFK Screen row adds "It gets out of the way for queue pops, ready checks, invites, summons, duels and
  trades."; Collect here row: "A toast (once a day per zone) when you arrive ..."; Commands: `/tomte showcase view`;
  Credits, Pet Battles line: "the tamer list (Data/<Expansion>/Pets.lua) takes from Xu-Fu's Pet Guides ..." (same
  facts, new place); Credits, Moments: none (the locale strings are test data only).
- [ ] CHANGELOG **Unreleased**, after the user confirmed each in game (one line per task, wording from the tasks):
  Pet Battles (names, Heal), AFK Screen, Dressing room, Collect here, Showcase.
- [ ] In-game checklist for the user (one `/reload`, level 80, War Within):
  1. Wild pet battle: helper and round counter work (Task 1); Heal shows after and heals (Task 4).
  2. Pet Battles off: Heal key does nothing; on again: it heals (Task 4).
  3. Tamer card title and list search (Task 3); tamer list order and `/tomte data` line (Task 2).
  4. AFK, then a duel or trade from a friend: screen closes, popup visible (Task 5).
  5. Target's outfit with the Inspect window open on the same and another player (Task 6).
  6. Zone toast, `/reload`, no second toast (Task 7).
  7. Almost Done row flash still fades (Task 8).
  8. `/tomte showcase view`, and the Set View 5 test (Task 11).
  9. Three new tooltips (Task 12).
- [ ] Commit per confirmed task, never mixing the split: `Split Pets Battle into Battle and Read (pure moves)` (Task
  1), `Pets: tamer table moves to Data/<Expansion>/ (no behavior change)`, `Pets: tamer names in the game's
  language`, `Pets: Heal button knows when you can't heal and stops when the module is off`, `AFK Screen: closes for
  summons, duels, trades and other popups`, `Dressing room: Target's outfit leaves the Inspect window alone`,
  `Collect here: zone toast once a day`, `Almost Done: tracker rows update only while flashing`, `DressUp, Showcase:
  defaults for the debug switches`, `Moments: discovery parser without pcall, tested in six languages`, `Showcase:
  borrow a camera view without a key`, `Achievements, Pets, Moments: setting tooltips`.
