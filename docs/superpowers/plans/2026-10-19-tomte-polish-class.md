# Class helpers polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pet Health covers Warlocks and Unholy Death Knights (shipped marked untested), Hunter beast tooltips stop
claiming "new family" before the stable was read, and Rogue Poisons rebuilds once per burst of aura changes.

**Architecture:** Class profiles and every new rule live in the pure `Modules/Combat/Data.lua` and
`Modules/Hunter/Data.lua` (tested in `tests/test_combat.lua`, `tests/test_hunter.lua`); `PetHealth.lua`,
`Tooltips.lua` and `Rogue.lua` only read the game and call them. No saved-variable change, no migration, no TOC
change.

**Tech Stack:** Lua 5.1 (WoW 12.1.5 retail), plain-Lua unit tests in tests/.
**Spec:** docs/superpowers/specs/2026-10-19-tomte-polish-class-design.md

## Global Constraints

- CRLF files: edit Lua with the Edit/Write tools only (no sed, awk or heredocs).
- Tabs, about 120 columns, double quotes, `local function` for private code, comments say why.
- No numeric colors, `|cff` literals or font paths: text color through `UI.Wrap(text, role)`.
- No deprecated globals: `C_SpecializationInfo.*`, `C_SpellBook.IsSpellKnown`; nothing errors with
  `/console loadDeprecationFallbacks 0`.
- Secret values: test with `ns.IsSecret` before comparing; no logic on combat-only info.
- Don't simplify `InCombatLockdown()` guards, secure buttons or deferrals that carry a reason comment.
- A hook or deferred call does nothing harmful while its module is off.
- Labels, tooltips and CHANGELOG lines are player wording; no character, realm or guild names (examples: Aldric, Kesha, Mira).
- Run all tests from the `AddOns` folder before saying something is done.
- Commit only after the user (or for Warlock/DK, a friend) confirmed in game; message `<Module>: what changed`.

## Review Focus

1. **A Blood or Frost Death Knight gets a pet bar or a "No pet" banner** from the temporary Raise Dead ghoul or on
   every pull. Covered by the `ForSpec`/`Visible offSpec`/`WantsPet` tests (Task 1) and the friend check in Task 5.
2. **A warlock with Grimoire of Sacrifice is nagged "No pet" on every pull**, or the aura read errors on a secret in
   combat. Covered by the `WantsPet sacrificed` test (Task 1); `ReadSacrifice` only runs out of combat (Task 2) and
   the friend check in Task 5.
3. **Hunters regress**: the profile's `revive`/`call` became lists, so a missed call site shows an empty banner
   subtitle or a nil texture. Covered by the `SummonSpell` tests (Task 1) and the user's Hunter check in Task 2.
4. **Hunter tooltip says "not in your active pets" forever** for a hunter whose stable was read but who has no
   stabled pets, or still says "new family" with no snapshot. Covered by the `TameNote` tests (Task 3) and the
   in-game check there.
5. **A debounced Rogue refresh lands in combat or after the module was turned off** and touches secure buttons.
   `Refresh` keeps its `InCombatLockdown()` guard and hides everything when the module is off; checked in game in
   Task 4 (aura burst right before a pull, and turning the module off).

---

### Task 1: Pet Health profiles and rules (pure)

**Files:**
- Modify: `Modules/Combat/Data.lua:1-16` (header, PROFILES), `:30-33` (`ns.PetBar_WantsPet`), `:37-51`
  (`ns.PetBar_Visible`), new functions after `ns.PetBar_WantsPet`.
- Modify: `tests/test_combat.lua:17-32` (profile and WantsPet tests), add tests.

**Interfaces:**
- Consumes: nothing.
- Produces: `ns.PetBar_Profile(class)` (now also `"WARLOCK"`, `"DEATHKNIGHT"`; `revive`/`call` are lists, optional
  `specs`, `sacrifice`), `ns.PetBar_ForSpec(profile, specID) -> bool`,
  `ns.PetBar_WantsPet(profile, specID, optionOn, sacrificed) -> bool`,
  `ns.PetBar_SummonSpell(list, last, isKnown) -> spellID`, `ns.PetBar_IsSummon(profile, spellID) -> bool`,
  `ns.PetBar_HasOption(profile) -> bool`, `ns.PetBar_Visible(mode, s)` reads `s.offSpec`.

- [ ] **Step 1: Failing tests.** In `tests/test_combat.lua`, replace the test "Profile exists for hunters only" with
  the block below, and append the new tests before `H.done()`:

```lua
local AFF, DEMO, DESTRO = 265, 266, 267
local BLOOD, FROST, UNHOLY = 250, 251, 252

local function knows(ids)
	local set = {}
	for _, id in ipairs(ids) do
		set[id] = true
	end
	return function(id)
		return set[id] == true
	end
end

test("Profiles: hunters, warlocks and death knights", function()
	eq(ns.PetBar_Profile("HUNTER").unit, "pet")
	eq(ns.PetBar_Profile("HUNTER").spells[1].id, 136)
	eq(ns.PetBar_Profile("HUNTER").spells[2].id, 109304)
	eq(ns.PetBar_Profile("HUNTER").revive[1], 982)
	eq(ns.PetBar_Profile("HUNTER").call[1], 883)
	eq(ns.PetBar_Profile("WARLOCK").unit, "pet")
	eq(ns.PetBar_Profile("WARLOCK").spells[1].id, 333889)
	eq(ns.PetBar_Profile("WARLOCK").sacrifice, 196099)
	eq(ns.PetBar_Profile("DEATHKNIGHT").spells[1].id, 63560)
	eq(ns.PetBar_Profile("DEATHKNIGHT").spells[1].buff, true)
	eq(ns.PetBar_Profile("DEATHKNIGHT").revive[1], 46584)
	eq(ns.PetBar_Profile("WARRIOR"), nil)
	eq(ns.PetBar_Profile(nil), nil)
end)

test("Profiles: every spell is a number, revive and call are non-empty lists", function()
	for _, class in ipairs({ "HUNTER", "WARLOCK", "DEATHKNIGHT" }) do
		local p = ns.PetBar_Profile(class)
		for _, spell in ipairs(p.spells) do
			eq(type(spell.id), "number", class .. " spell")
		end
		assert(#p.revive > 0 and #p.call > 0, class .. " needs revive and call")
	end
end)

test("ForSpec: death knights only as Unholy, other profiles every spec", function()
	local dk = ns.PetBar_Profile("DEATHKNIGHT")
	eq(ns.PetBar_ForSpec(dk, UNHOLY), true)
	eq(ns.PetBar_ForSpec(dk, BLOOD), false)
	eq(ns.PetBar_ForSpec(dk, FROST), false)
	eq(ns.PetBar_ForSpec(dk, nil), false)
	eq(ns.PetBar_ForSpec(ns.PetBar_Profile("HUNTER"), nil), true)
	eq(ns.PetBar_ForSpec(ns.PetBar_Profile("WARLOCK"), DESTRO), true)
end)

test("WantsPet: every warlock spec, not with Grimoire of Sacrifice", function()
	local p = ns.PetBar_Profile("WARLOCK")
	for _, spec in ipairs({ AFF, DEMO, DESTRO }) do
		eq(ns.PetBar_WantsPet(p, spec, false, false), true, spec)
		eq(ns.PetBar_WantsPet(p, spec, false, true), false, spec)
	end
end)

test("WantsPet: Unholy only", function()
	local p = ns.PetBar_Profile("DEATHKNIGHT")
	eq(ns.PetBar_WantsPet(p, UNHOLY, false), true)
	eq(ns.PetBar_WantsPet(p, BLOOD, true), false)
	eq(ns.PetBar_WantsPet(p, FROST, true), false)
end)

test("SummonSpell: last summon if known, else the first known, else the first", function()
	local list = { 30146, 691, 697, 366222, 688 }
	eq(ns.PetBar_SummonSpell(list, 697, knows({ 691, 697, 688 })), 697)
	eq(ns.PetBar_SummonSpell(list, 30146, knows({ 691, 688 })), 691)
	eq(ns.PetBar_SummonSpell(list, nil, knows({ 30146, 691 })), 30146)
	eq(ns.PetBar_SummonSpell(list, 12345, knows({ 688 })), 688)
	eq(ns.PetBar_SummonSpell(list, nil, knows({})), 30146)
	eq(ns.PetBar_SummonSpell({ 883 }, nil, knows({})), 883)
end)

test("IsSummon: only the profile's revive and call spells", function()
	local p = ns.PetBar_Profile("WARLOCK")
	eq(ns.PetBar_IsSummon(p, 691), true)
	eq(ns.PetBar_IsSummon(p, 333889), false)
	eq(ns.PetBar_IsSummon(ns.PetBar_Profile("HUNTER"), 982), true)
	eq(ns.PetBar_IsSummon(ns.PetBar_Profile("DEATHKNIGHT"), 46585), false)
end)

test("HasOption: only hunters have the Marksmanship option", function()
	eq(ns.PetBar_HasOption(ns.PetBar_Profile("HUNTER")), true)
	eq(ns.PetBar_HasOption(ns.PetBar_Profile("WARLOCK")), false)
	eq(ns.PetBar_HasOption(ns.PetBar_Profile("DEATHKNIGHT")), false)
end)

test("Visible: never for an off spec, unless unlocked", function()
	eq(ns.PetBar_Visible("always", situation({ offSpec = true })), false)
	eq(ns.PetBar_Visible("combat", situation({ offSpec = true, dead = true, inCombat = true })), false)
	eq(ns.PetBar_Visible("combat", situation({ offSpec = true, unlocked = true })), true)
end)
```

- [ ] **Step 2: Run and see it fail.** From `D:\World of Warcraft\_retail_\Interface\AddOns`:
  `lua Tomte/tests/test_combat.lua` -> FAIL on "Profiles: hunters, warlocks and death knights" (`revive[1]` of a
  number) and errors on the missing functions.

- [ ] **Step 3: Implement.** In `Modules/Combat/Data.lua`, replace lines 6-16 (the comment above PROFILES and the
  table) with:

```lua
-- One entry per class that has a combat pet. spells: the icon row under the bar ({ id, buff = true } times the
-- buff on the pet), filtered to known spells at run time. revive / call: the spells a "dead" / "no pet" reminder
-- names (see ns.PetBar_SummonSpell). wantsPet: [specID] = true (always) or "option" (only with the "Marksmanship
-- uses a pet" style setting on). specs: when set, the bar and reminders are for these specs only. sacrifice: a
-- player aura that means the pet was given up on purpose.
-- Warlock demons in the order a reminder names them before any summon this session: Felguard (Demonology), then
-- the ones every spec has.
local DEMONS = { 30146, 691, 697, 366222, 688 } -- Felguard, Felhunter, Voidwalker, Sayaad, Imp
local PROFILES = {
	HUNTER = {
		unit = "pet",
		-- Icons under the bar: Mend Pet (its buff on the pet is timed too) and Exhilaration (heals the pet fully).
		spells = { { id = 136, buff = true }, { id = 109304 } },
		revive = { 982 }, -- Revive Pet
		call = { 883 }, -- Call Pet 1
		wantsPet = { [253] = true, [255] = true, [254] = "option" },
	},
	-- Untested in game (2026-10-19): the author has no warlock. Health Funnel (755) was removed in 12.0.0, so the
	-- row has no heal, only Fel Domination's cooldown.
	WARLOCK = {
		unit = "pet",
		spells = { { id = 333889 } }, -- Fel Domination
		revive = DEMONS,
		call = DEMONS,
		wantsPet = { [265] = true, [266] = true, [267] = true },
		sacrifice = 196099, -- Grimoire of Sacrifice's buff on the warlock
	},
	-- Untested in game (2026-10-19): the author has no death knight. Unholy only: the other specs' Raise Dead
	-- (46585) is a temporary ghoul.
	DEATHKNIGHT = {
		unit = "pet",
		spells = { { id = 63560, buff = true } }, -- Dark Transformation, its buff on the ghoul timed
		revive = { 46584 }, -- Raise Dead (Unholy's permanent ghoul)
		call = { 46584 },
		wantsPet = { [252] = true },
		specs = { [252] = true },
	},
}
```

  Replace `ns.PetBar_WantsPet` (lines 30-33) with this block (the new functions follow it):

```lua
-- Whether the bar and reminders apply to this spec. A profile without specs covers every spec; with specs, an
-- unknown spec (not loaded yet) doesn't pass.
function ns.PetBar_ForSpec(profile, specID)
	if not profile.specs then
		return true
	end
	return specID ~= nil and profile.specs[specID] == true
end

-- sacrificed: the profile's sacrifice aura is on (the pet was given up on purpose).
function ns.PetBar_WantsPet(profile, specID, optionOn, sacrificed)
	if sacrificed then
		return false
	end
	local want = specID and profile.wantsPet[specID]
	return want == true or (want == "option" and optionOn == true)
end

-- The spell a reminder names from list: the summon cast last when it's in the list and known, else the first known
-- one, else the first. isKnown(spellID) -> bool.
function ns.PetBar_SummonSpell(list, last, isKnown)
	if last then
		for _, id in ipairs(list) do
			if id == last and isKnown(id) then
				return id
			end
		end
	end
	for _, id in ipairs(list) do
		if isKnown(id) then
			return id
		end
	end
	return list[1]
end

-- Whether spellID is one of the profile's revive or call spells (remembered as the last summon).
function ns.PetBar_IsSummon(profile, spellID)
	for _, list in ipairs({ profile.revive, profile.call }) do
		for _, id in ipairs(list) do
			if id == spellID then
				return true
			end
		end
	end
	return false
end

-- Whether some spec of the profile only wants a pet with the option on (the settings row shows then).
function ns.PetBar_HasOption(profile)
	for _, want in pairs(profile.wantsPet) do
		if want == "option" then
			return true
		end
	end
	return false
end
```

  In `ns.PetBar_Visible`, update the comment's field list to `{ unlocked, offSpec, vehicle, ... }` and add after the
  `if s.unlocked then return true end` block:

```lua
	if s.offSpec then
		return false
	end
```

- [ ] **Step 4: Run and see it pass.** `lua Tomte/tests/test_combat.lua` -> all `ok`.
- [ ] **Step 5:** No commit yet (Task 2 uses the list shape; commit both after the in-game check in Task 2).

### Task 2: Pet Health reads spec, sacrifice and last summon

**Files:**
- Modify: `Modules/Combat/PetHealth.lua:3-6` (header), `:14-21` (locals), `:51-66` (`Situation`), `:76-105`
  (`Remind`), `:239-243`, `:245-249`, `:263-271` (events), `:273-286` (`Start`), `:361-388` (module fields),
  `:413-415` and `:427-428` (options).

**Interfaces:**
- Consumes: Task 1's `ns.PetBar_ForSpec`, `ns.PetBar_WantsPet` (4 args), `ns.PetBar_SummonSpell`,
  `ns.PetBar_IsSummon`, `ns.PetBar_HasOption`; `ns.IsSecret`.
- Produces: nothing new for other files.

- [ ] **Step 1: Header and locals.** Lines 3-6 become:

```lua
-- Pet Health: a pet bar under the character (UnitBar.lua) with a color and warning glow that follow pet
-- health, a "heal below this line" tick and the class's pet cooldowns; plus banner reminders when the pet dies,
-- when you pull without one, and when combat ends with it dead. Pure rules and the class profiles (hunters,
-- warlocks, Unholy death knights) in Data.lua.
```

  After `local spellsDirty = true ...` (line 21) add:

```lua
-- Grimoire of Sacrifice on (profiles with `sacrifice`). Read out of combat only: aura reads can come back secret in
-- combat, and the value from before the pull holds through the fight.
local sacrificed = false
local lastSummon -- the profile's summon spell cast last this session: the demon a reminder names
```

- [ ] **Step 2: Known, ReadSacrifice, Situation.** Before (lines 51-66):

```lua
local function Situation()
	local hasPet = UnitExists("pet")
	return {
		unlocked = not Locked(),
		hasPet = hasPet,
		dead = hasPet and PetDead(),
		hurt = hasPet and PetHurt() or nil,
		wantsPet = ns.PetBar_WantsPet(profile, SpecID(), db.marksman),
```

  After:

```lua
local function Known(spellID)
	return C_SpellBook.IsSpellKnown(spellID) and true or false
end

local function ReadSacrifice()
	if not profile.sacrifice or inCombat then
		return
	end
	sacrificed = C_UnitAuras.GetPlayerAuraBySpellID(profile.sacrifice) ~= nil
end

local function Situation()
	local hasPet = UnitExists("pet")
	local spec = SpecID()
	return {
		unlocked = not Locked(),
		offSpec = not ns.PetBar_ForSpec(profile, spec),
		hasPet = hasPet,
		dead = hasPet and PetDead(),
		hurt = hasPet and PetHurt() or nil,
		wantsPet = ns.PetBar_WantsPet(profile, spec, db.marksman, sacrificed),
```

  (rest of the table unchanged). In `KnownSpells`, use `Known(spell.id)` instead of
  `C_SpellBook.IsSpellKnown(spell.id)` (move `KnownSpells` below `Known` if needed; it already is, at line 113).

- [ ] **Step 3: Remind names the right spell.** Before (inside `Remind`):

```lua
	local name = petName or "Your pet"
	local spec
	if key == "dead" then
		spec = {
			title = trigger == "died" and (name .. " died") or (name .. " is dead"),
			subtitle = SpellName(profile.revive),
			icon = C_Spell.GetSpellTexture(profile.revive),
		}
	else
		spec = { title = "No pet", subtitle = SpellName(profile.call), icon = C_Spell.GetSpellTexture(profile.call) }
	end
```

  After:

```lua
	local name = petName or "Your pet"
	local spellID = ns.PetBar_SummonSpell(key == "dead" and profile.revive or profile.call, lastSummon, Known)
	local spec
	if key == "dead" then
		spec = { title = trigger == "died" and (name .. " died") or (name .. " is dead") }
	else
		spec = { title = "No pet" }
	end
	spec.subtitle, spec.icon = SpellName(spellID), C_Spell.GetSpellTexture(spellID)
```

- [ ] **Step 4: Events.** `PLAYER_ENTERING_WORLD`: call `ReadSacrifice()` right after `inCombat = InCombatLockdown()`.
  `PLAYER_REGEN_ENABLED`: call `ReadSacrifice()` right after `inCombat = false`. Replace `events:UNIT_AURA` with:

```lua
function events:UNIT_AURA(unit)
	if unit == "player" then -- registered only for a profile with a sacrifice aura
		local was = sacrificed
		ReadSacrifice()
		if sacrificed ~= was then
			Update()
		end
		return
	end
	if bar and bar:IsShown() and UnitExists("pet") and (Locked() or inCombat) then
		bar:RefreshBuff("pet")
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if not IsSecret(spellID) and ns.PetBar_IsSummon(profile, spellID) then
		lastSummon = spellID
	end
end
```

  In `Start`, replace `events:RegisterUnitEvent("UNIT_AURA", "pet")` with:

```lua
	-- The player's auras only matter for Grimoire of Sacrifice: other classes skip that busy stream.
	if profile.sacrifice then
		events:RegisterUnitEvent("UNIT_AURA", "pet", "player")
	else
		events:RegisterUnitEvent("UNIT_AURA", "pet")
	end
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
```

- [ ] **Step 5: Module text and options.**

```lua
	summary = "A pet health bar for Hunters, Warlocks and Unholy Death Knights that warns you when your pet needs healing.",
	description = "A pet health bar under your character that turns red and glows when your pet needs healing, and reminders when your pet dies or you pull without one. Under the bar: Mend Pet and Exhilaration for Hunters, Fel Domination for Warlocks (no reminders with Grimoire of Sacrifice), Dark Transformation for Unholy Death Knights.",
```

  `blocked`: `return "Only for Hunters, Warlocks and Unholy Death Knights."`.
  Threshold slider tooltip: `"Below this the bar turns red and glows. The tick on the bar marks it."`.
  Marksman checkbox: add `shown = function() return profile ~= nil and ns.PetBar_HasOption(profile) end,`.

- [ ] **Step 6: Checks.** `lua Tomte/tests/test_combat.lua` (all ok);
  `luac -l Tomte/Modules/Combat/PetHealth.lua | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` lists only WoW API and Lua
  globals (no `Known`, `sacrificed`, `lastSummon`, `ReadSacrifice`).

- [ ] **Step 7: In game (user, MM Hunter).** `/reload` on the Hunter. Turn on "Marksmanship uses a pet" in Tomte >
  Pet Health (the row is there), dismiss the pet, attack a training dummy: the bar shows "NO PET" and the banner says
  "No pet - Call Pet 1" with its icon. Let the pet die (or `/dump C_Spell.GetSpellName(982)`), leave combat: "<name>
  is dead - Revive Pet". On the Paladin: Tomte > Pet Health shows "Only for Hunters, Warlocks and Unholy Death
  Knights." and no "Marksmanship uses a pet" row is reachable. No BugSack errors, also with
  `/console loadDeprecationFallbacks 0` (set it back with `/console loadDeprecationFallbacks 1` afterwards).
- [ ] **Step 8: In game (a friend with a Warlock).** Summon a Felhunter, `/reload`, attack a dummy, let it get hit:
  the bar follows its health; Fel Domination's cooldown shows under it if talented. Dismiss the demon (`/run
  PetDismiss()`), pull: "No pet - Summon Felhunter". Affliction or Destruction with Grimoire of Sacrifice on: pull
  with no demon, no bar and no banner. Note whether a demon that dies shows "DEAD" on the bar or simply vanishes.
- [ ] **Step 9: In game (a friend with a Death Knight).** As Unholy: the ghoul's bar, Dark Transformation under it
  and "Dark Transformation 15s" while it's up; dismiss the ghoul and pull: "No pet - Raise Dead". Switch to Blood or
  Frost, cast Raise Dead, pull: no bar, no banner. Note whether a dead ghoul shows "DEAD" or vanishes.
- [ ] **Step 10: Commit** after the user's Hunter check (Step 7). If no friend has tried Steps 8-9, the user decides
  whether it ships marked untested (the CHANGELOG line in Task 5 says so). Message:
  `Pet Health: Warlocks and Unholy Death Knights`.

### Task 3: Hunter tame tooltip waits for the stable

**Files:**
- Modify: `Modules/Hunter/Data.lua` (new function after `ns.Hunter_Ownership`, line 198).
- Modify: `Modules/Hunter/Tooltips.lua:74-82`.
- Modify: `tests/test_hunter.lua` (new test after "Ownership counts the family and matches the creature", line 124).

**Interfaces:**
- Consumes: `ns.Hunter_Ownership`, `ns.Stable_Snapshot`.
- Produces: `ns.Hunter_TameNote(snapshot, count, same) -> "same" | "owned" | "unread" | "notActive" | "new"`.

- [ ] **Step 1: Failing test** in `tests/test_hunter.lua`:

```lua
test("TameNote: new family only once the stabled list was read", function()
	local wolf = pet(1, "Kesha", "Wolf", { creatureID = 50 })
	local activeOnly = { active = { [1] = wolf }, stabled = {} }
	local full = { active = { [1] = wolf }, stabled = { pet(2, "Mira", "Cat") }, stabledRead = true }
	eq(ns.Hunter_TameNote(nil, 0, nil), "unread")
	eq(ns.Hunter_TameNote(activeOnly, 0, nil), "notActive")
	eq(ns.Hunter_TameNote(full, 0, nil), "new")
	eq(ns.Hunter_TameNote(activeOnly, 1, nil), "owned")
	eq(ns.Hunter_TameNote(full, 1, wolf), "same")
	local cached = { active = { [1] = wolf }, stabled = { pet(2, "Mira", "Cat") } } -- stabled kept from an older read
	eq(ns.Hunter_TameNote(cached, 0, nil), "new")
end)
```

- [ ] **Step 2:** `lua Tomte/tests/test_hunter.lua` -> FAIL (`Hunter_TameNote` is nil).
- [ ] **Step 3: Implement** in `Modules/Hunter/Data.lua` after `ns.Hunter_Ownership`:

```lua
-- The tame-log tooltip line: "same" (this very creature is yours), "owned" (you have the family), "unread" (no
-- snapshot: the pets were never read), "notActive" (only the active pets were read so far: the family may be in
-- the stable), "new" (the stabled list was read and the family isn't in it).
function ns.Hunter_TameNote(snapshot, count, same)
	if same then
		return "same"
	elseif count > 0 then
		return "owned"
	elseif not snapshot then
		return "unread"
	elseif not snapshot.stabled or #snapshot.stabled == 0 then
		return "notActive"
	end
	return "new"
end
```

- [ ] **Step 4:** `lua Tomte/tests/test_hunter.lua` -> all ok.
- [ ] **Step 5: Tooltip.** Before (`Modules/Hunter/Tooltips.lua:74-82`):

```lua
	local count, same = ns.Hunter_Ownership(ns.Stable_Snapshot(), family, npcID)
	local right
	if same then
		right = UI.Wrap("you have this one (" .. same.name .. ")", "heading")
	elseif count > 0 then
		right = UI.Wrap(count .. " in your stable", "textMuted")
	else
		right = UI.Wrap("new family", "success")
	end
```

  After:

```lua
	local snapshot = ns.Stable_Snapshot()
	local count, same = ns.Hunter_Ownership(snapshot, family, npcID)
	local note = ns.Hunter_TameNote(snapshot, count, same)
	local right
	if note == "same" then
		right = UI.Wrap("you have this one (" .. same.name .. ")", "heading")
	elseif note == "owned" then
		right = UI.Wrap(count .. " in your stable", "textMuted")
	elseif note == "unread" then
		right = UI.Wrap("Visit a stable master to check", "textMuted")
	elseif note == "notActive" then
		right = UI.Wrap("not in your active pets", "textMuted")
	else
		right = UI.Wrap("new family", "success")
	end
```

- [ ] **Step 6:** `luac -l Tomte/Modules/Hunter/Tooltips.lua | grep -E 'GETGLOBAL|GETTABUP.*_ENV'`: only WoW API
  and Lua globals.
- [ ] **Step 7: In game (user, Hunter).** `/reload`. Visit a stable master and close it, then mouse over a tameable
  beast of a family you have in the stable but not out: "N in your stable". A family you don't own at all: green
  "new family". The "Visit a stable master to check" and "not in your active pets" lines only show on a hunter
  Tomte never read (a new hunter, if you make one); the unit test covers them. No BugSack errors.
- [ ] **Step 8: Commit** after the user confirms: `Hunter Pets: ask for a stable visit before calling a family new`.

### Task 4: Rogue Poisons, one rebuild per aura burst

**Files:**
- Modify: `Modules/Rogue/Rogue.lua:7-11` (constants), `:327-333` (event mapping).

**Interfaces:**
- Consumes: `UI.Debounce` (`Panel/Widgets.lua:53`, loaded before Modules), `Refresh`.
- Produces: nothing.

- [ ] **Step 1: Constant.** After `local ENTER_DELAY = 4 ...` (line 10) add:

```lua
-- Seconds to gather a burst of aura changes (a city full of buffs, applying a poison) into one rebuild.
local AURA_DELAY = 0.2
```

- [ ] **Step 2: Event mapping.** Before (lines 327-333):

```lua
for _, event in ipairs({
	"PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_CONTROL_GAINED", "PET_BATTLE_CLOSE",
	"UNIT_AURA", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
}) do
	events[event] = Refresh
end
```

  After:

```lua
for _, event in ipairs({
	"PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_CONTROL_GAINED", "PET_BATTLE_CLOSE",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
}) do
	events[event] = Refresh
end

-- Aura changes come in bursts: one rebuild per burst. In combat nothing can change anyway (Refresh would return),
-- so no timer then; a deferred Refresh that lands in combat or after Stop is handled by Refresh's own guards.
local refreshSoon = UI.Debounce(AURA_DELAY, Refresh)
function events:UNIT_AURA()
	if not InCombatLockdown() then
		refreshSoon()
	end
end
```

  `Refresh`'s `InCombatLockdown()` guard and the "made here, out of combat" comment stay as they are.

- [ ] **Step 3:** `lua Tomte/tests/test_rogue.lua` (unchanged, still ok);
  `luac -l Tomte/Modules/Rogue/Rogue.lua | grep -E 'GETGLOBAL|GETTABUP.*_ENV'`: no `refreshSoon` or `AURA_DELAY`.
- [ ] **Step 4: In game (a friend with a Rogue; the user has none).** `/reload` with no poisons on: the buttons
  appear. Click Deadly Poison: its button disappears within a moment. Apply a poison and pull a dummy within half a
  second: no "action blocked" message, no BugSack error. Tomte > Rogue Poisons off right after applying a poison: the
  buttons are gone and stay gone.
- [ ] **Step 5: Commit** after the check: `Rogue Poisons: one rebuild per burst of aura changes`. No CHANGELOG line
  (nothing a player sees changes).

### Task 5: Verification, docs and the in-game list

**Files:**
- Modify: `README.md:245` (Pet Health row), `CHANGELOG.md` (under `## Unreleased`).

**Interfaces:**
- Consumes: Tasks 1-4. Plan A (Core/Panel) goes first; this plan doesn't touch `ns.Hunter_ContentKind` (Plan A moves
  it to Core, as `ns.Check_ContentKind`) or the combat-refusal messages (`ns.Print_Combat`).
- Produces: nothing.

- [ ] **Step 1: All tests** from `D:\World of Warcraft\_retail_\Interface\AddOns`:
  `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done` -> no output.
- [ ] **Step 2: Globals.** For `Modules/Combat/Data.lua`, `Modules/Combat/PetHealth.lua`, `Modules/Hunter/Data.lua`,
  `Modules/Hunter/Tooltips.lua`, `Modules/Rogue/Rogue.lua`:
  `luac -l <file> | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` lists only WoW API and Lua globals.
- [ ] **Step 3: Deprecated globals stay gone.** Several files capture `C_SpecializationInfo.GetSpecialization` into a
  local of the same name, so a text grep can't tell them apart; the bytecode can. From the AddOns folder:
  `for f in $(grep -rlE 'GetSpecialization|IsPlayerSpell' --include=*.lua Tomte); do luac -l "$f" | grep -E 'GETGLOBAL.*; (GetSpecialization|GetSpecializationInfo|IsPlayerSpell)$' && echo "$f"; done`
  -> no output.
- [ ] **Step 4: README row** (`README.md:245`):

```
| Pet Health | Class & combat | Pet health bar under your character for Hunters, Warlocks and Unholy Death Knights that glows when your pet needs healing, with your pet cooldowns (Mend Pet and Exhilaration, Fel Domination, Dark Transformation) and reminders for a dead or missing pet. |
```

- [ ] **Step 5: CHANGELOG** under `## Unreleased`, once the matching in-game check passed:

```
- Pet Health: now for Warlocks (your demon; no reminders with Grimoire of Sacrifice) and Unholy Death Knights (your ghoul, with Dark Transformation timed). New and not tried on those classes yet: tell us if something looks off.
- Hunter Pets: a beast's tooltip no longer calls its family new before Tomte has read your stable; it asks you to visit a stable master instead.
```

  Drop "New and not tried on those classes yet: ..." if a friend confirmed Task 2 Steps 8-9.
- [ ] **Step 6: In-game checklist** (give the user this list):
  1. Hunter (user): Task 2 Step 7 (Pet Health still right, banner names Call Pet 1 / Revive Pet).
  2. Paladin (user): Pet Health page says "Only for Hunters, Warlocks and Unholy Death Knights."
  3. Hunter (user): Task 3 Step 7 (tooltip line before and after a stable visit).
  4. `/console loadDeprecationFallbacks 0`, `/reload` on both characters: no BugSack errors; set it back to 1.
  5. Friend, Warlock: Task 2 Step 8. Friend, Death Knight: Task 2 Step 9. Friend, Rogue: Task 4 Step 4.
- [ ] **Step 7: Commit** README and CHANGELOG with the task they belong to (Pet Health row and line with Task 2's
  commit, the Hunter line with Task 3's), only after the user confirms in game.
