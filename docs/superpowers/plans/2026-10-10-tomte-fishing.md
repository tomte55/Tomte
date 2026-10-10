# Fishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module `fishing` that replaces Angleur's One Key: one bound key casts Fishing and, while the bobber
is out, reels in and loots it; with auto loot while fishing, loot protection, an optional louder splash, optional
raft and Oversized Bobber toys, and an optional on-screen button.

**Architecture:** The decisions (what the next press does, which channel is fishing, which CVars to set and when to
put them back) are pure functions in `Data.lua`, unit-tested with plain Lua. `Helpers.lua` applies CVars with a saved
backup. `Key.lua` owns the secure button `TomteFishing`, its `PreClick`, and the `INTERACTTARGET` override binding
that exists only while a fishing channel runs. `Fishing.lua` registers the module.

**Tech stack:** WoW retail 12.1 Lua (5.1), `SecureActionButtonTemplate`, `SetOverrideBinding`, `C_CVar`, Tomte's
`ns.RegisterModule`, `ns.UI` theme roles, `ns.EditMode_Register`, Bindings.xml.

**Spec:** `docs/superpowers/specs/2026-10-10-tomte-fishing-design.md`.

**Execution:** Work on branch `fishing`, uncommitted until the user has checked it in game (CLAUDE.md). Answers to the
spec's open questions change only defaults in Task 5.

## Global constraints

- Lua 5.1 syntax (CI runs 5.1): no `goto`, no `//`, no integer-only operators, no `utf8`.
- No numeric RGB in `SetTextColor`, `SetVertexColor`, `SetColorTexture` or `CreateColor`; colors from theme roles
  (`UI.Color(role)`). No `|cff` literals, no font paths. `tests/test_theme.lua` scans for them.
- One event frame per file, dispatching with `self[event](self, ...)`.
- Globals: only the named frames `TomteFishing` and `TomteFishingBar` (the CLICK binding needs the button's name) and
  the `BINDING_NAME_*` string.
- No Angleur code. IDs only, credited in a comment and in README Credits.
- Defaults are safe: nothing happens until a key is bound or the button is shown; louder splash, dismount, raft and
  bobber are off; every CVar change is put back.
- Bindings and secure attributes change only out of combat and outside Combat/Encounter/ChallengeMode/PvPMatch
  restrictions. Secure CVars (`SoftTargetInteract`, `SoftTargetInteractRange`) only out of combat.
- One hardware press per action. Nothing casts, reels or uses a toy on its own.
- A binding is never changed while one of its keys is held down.

## Review focus

1. **The cast press is still held when the channel starts.** The reel override must wait for release, and the next
   press must reel, not cast. → `Fishing_KeysUp` test + Key.lua review; in-game test 2.
2. **Combat starts mid-cast, or the client crashes mid-cast.** Soft interact and auto loot must come back exactly as
   they were, and a change the player made meanwhile must not be overwritten. → `Fishing_RestoreList` tests
   ("player changed it", "nothing to restore").
3. **Secret or nil event arguments** (`spellID`, GUIDs in restricted states) must be ignored, not compared. →
   Key.lua checks `issecretvalue` before calling Data.lua (reviewed by reading); the `Fishing_IsFishingSpell` and
   `Fishing_ObjectID` tests cover nil and non-string input.
4. **Toys the player doesn't own, raft chosen but sold/removed, toy data not loaded** must fall back to casting. →
   `Fishing_PickRaft` and `Fishing_NextAction` tests.
5. **The player unbinds or rebinds the key mid-session, or binds two keys.** Every bound key gets the override and
   nothing stays overridden after unbinding. → Key.lua `UPDATE_BINDINGS` handling, `Fishing_KeysUp` with two keys.

---

### Task 1: Pure rules (`Modules/Fishing/Data.lua`) and tests

**Files:**
- Create: `Modules/Fishing/Data.lua`
- Create: `tests/test_fishing.lua`

**Interfaces — Produces (all pure, no WoW calls):**
- Constants: `ns.FISHING_SPELL = 131474`, `ns.FISHING_BOBBER_OBJECT = 35591`,
  `ns.FISHING_CHANNELS = { [id] = true }` (retail IDs below), `ns.FISHING_RAFTS = { { item, aura }... }`,
  `ns.FISHING_BOBBER_TOY = { item = 202207, aura = 397827 }`, `ns.FISHING_RAFT_RENEW = 60`,
  `ns.FISHING_LOOT_TIMEOUT = 3`.
- `ns.Fishing_IsFishingSpell(spellID, spellName, fishingName) -> bool`
- `ns.Fishing_ObjectID(guid) -> number|nil` (game objects only)
- `ns.Fishing_PickRaft(owned, pick, random) -> item|nil` — `owned` = list of item IDs, `pick` = 0 or an item ID,
  `random(n)` returns 1..n.
- `ns.Fishing_NextAction(s, opts) -> action` where
  `s = { known, dead, blocked, mounted, flying, swimming, lootOpen, rafts = {items owned}, raftLeft = seconds|nil,
  bobberOwned, bobberUp, bobberReady }`,
  `opts = { lootProtect, dismount, raft = { on, pick }, bobber, random }`,
  `action = { kind = "cast"|"none"|"toy"|"dismount", item?, reason }`.
- `ns.Fishing_CVarPlan(opts, current) -> { [cvar] = value }` — `opts = { autoLoot, loud = { on, sfx, background } }`,
  `current = { [cvar] = string }`; only CVars whose value would change are listed.
- `ns.Fishing_Backup(restore, plan, current)` — adds `{ old, set }` for each planned CVar not already in `restore`.
- `ns.Fishing_RestoreList(restore, current) -> { [cvar] = old }` — only entries whose current value still equals
  `set`; every entry is removed from `restore` either way.
- `ns.Fishing_MacroText(action, names) -> string` — `names = { fishing, toy }`.
- `ns.Fishing_KeysUp(keys, isDown) -> bool` — true when no key in the list is held.

- [ ] **Step 1: Write the failing tests** in `tests/test_fishing.lua` (same harness as `tests/test_mount.lua`):

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_fishing.lua
local ns = {}
assert(loadfile("Tomte/Modules/Fishing/Data.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then print("ok   " .. name) else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end
local function first() return 1 end

test("fishing spell by id and by name", function()
	eq(ns.Fishing_IsFishingSpell(131476, "Fishing", "Fishing"), true, "id")
	eq(ns.Fishing_IsFishingSpell(999999999, "Fishing", "Fishing"), true, "name")
	eq(ns.Fishing_IsFishingSpell(999999999, "Fireball", "Fishing"), false, "other")
	eq(ns.Fishing_IsFishingSpell(nil, nil, "Fishing"), false, "nil")
	eq(ns.Fishing_IsFishingSpell(999999999, "Fishing", nil), false, "no fishing name")
end)

test("object id from guid", function()
	eq(ns.Fishing_ObjectID("GameObject-0-3767-2444-2424-35591-0000ABCDEF"), 35591)
	eq(ns.Fishing_ObjectID("Creature-0-3767-2444-2424-12345-0000ABCDEF"), nil, "creature")
	eq(ns.Fishing_ObjectID("junk"), nil, "junk")
	eq(ns.Fishing_ObjectID(nil), nil, "nil")
	eq(ns.Fishing_ObjectID(""), nil, "empty")
end)

test("raft pick", function()
	eq(ns.Fishing_PickRaft({ 85500, 198428 }, 198428, first), 198428, "chosen")
	eq(ns.Fishing_PickRaft({ 85500 }, 198428, first), 85500, "chosen not owned -> first owned")
	eq(ns.Fishing_PickRaft({ 85500, 198428 }, 0, function(n) return n end), 198428, "random")
	eq(ns.Fishing_PickRaft({}, 0, first), nil, "none owned")
end)

local OPTS = { lootProtect = true, dismount = false, raft = { on = false, pick = 0 }, bobber = false, random = first }
local function S(t)
	local s = { known = true, rafts = {} }
	for k, v in pairs(t or {}) do s[k] = v end
	return s
end
local function O(t)
	local o = {}
	for k, v in pairs(OPTS) do o[k] = v end
	for k, v in pairs(t or {}) do o[k] = v end
	return o
end

test("next action: plain cast", function()
	eq(ns.Fishing_NextAction(S(), O()).kind, "cast")
end)

test("next action: blockers in order", function()
	eq(ns.Fishing_NextAction(S({ lootOpen = true }), O()).reason, "loot")
	eq(ns.Fishing_NextAction(S({ lootOpen = true }), O({ lootProtect = false })).kind, "cast", "protection off")
	eq(ns.Fishing_NextAction(S({ dead = true }), O()).kind, "none")
	eq(ns.Fishing_NextAction(S({ blocked = true }), O()).kind, "none")
	eq(ns.Fishing_NextAction(S({ known = false }), O()).reason, "unknown")
end)

test("next action: mounted", function()
	eq(ns.Fishing_NextAction(S({ mounted = true }), O()).kind, "none")
	eq(ns.Fishing_NextAction(S({ mounted = true }), O({ dismount = true })).kind, "dismount")
	eq(ns.Fishing_NextAction(S({ mounted = true, flying = true }), O({ dismount = true })).kind, "none", "flying")
end)

test("next action: swimming and rafts", function()
	eq(ns.Fishing_NextAction(S({ swimming = true }), O()).kind, "none", "no raft option")
	local raftOn = O({ raft = { on = true, pick = 0 } })
	eq(ns.Fishing_NextAction(S({ swimming = true }), raftOn).kind, "none", "no raft owned")
	local a = ns.Fishing_NextAction(S({ swimming = true, rafts = { 85500 } }), raftOn)
	eq(a.kind, "toy"); eq(a.item, 85500)
	eq(ns.Fishing_NextAction(S({ rafts = { 85500 }, raftLeft = 30 }), raftOn).kind, "toy", "renew under 60 s")
	eq(ns.Fishing_NextAction(S({ rafts = { 85500 }, raftLeft = 300 }), raftOn).kind, "cast", "plenty left")
end)

test("next action: oversized bobber", function()
	local on = O({ bobber = true })
	local a = ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = true }), on)
	eq(a.kind, "toy"); eq(a.item, 202207)
	eq(ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = true, bobberUp = true }), on).kind, "cast", "up")
	eq(ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = false }), on).kind, "cast", "cooldown")
	eq(ns.Fishing_NextAction(S({ bobberOwned = false, bobberReady = true }), on).kind, "cast", "not owned")
	eq(ns.Fishing_NextAction(S({ bobberOwned = true, bobberReady = true }), O()).kind, "cast", "option off")
end)

test("cvar plan: soft interact always, helpers by option", function()
	local cur = { SoftTargetInteract = "1", SoftTargetInteractRange = "10", SoftTargetInteractRangeIsHard = "0",
		autoLootDefault = "0", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.6", Sound_SFXVolume = "0.5",
		Sound_EnableSoundWhenGameIsInBG = "0" }
	local p = ns.Fishing_CVarPlan({ autoLoot = true, loud = { on = false } }, cur)
	eq(p.SoftTargetInteract, "3"); eq(p.SoftTargetInteractRange, "15"); eq(p.autoLootDefault, "1")
	eq(p.SoftTargetInteractRangeIsHard, nil, "already 0"); eq(p.Sound_MusicVolume, nil, "loud off")
	p = ns.Fishing_CVarPlan({ autoLoot = false, loud = { on = true, sfx = 1, background = true } }, cur)
	eq(p.autoLootDefault, nil); eq(p.Sound_MusicVolume, "0"); eq(p.Sound_AmbienceVolume, "0")
	eq(p.Sound_SFXVolume, "1"); eq(p.Sound_EnableSoundWhenGameIsInBG, "1")
	cur.SoftTargetInteract, cur.SoftTargetInteractRange = "3", "20"
	p = ns.Fishing_CVarPlan({ autoLoot = false, loud = { on = false } }, cur)
	eq(p.SoftTargetInteract, nil, "already on"); eq(p.SoftTargetInteractRange, nil, "already wider")
end)

test("backup and restore", function()
	local restore = {}
	ns.Fishing_Backup(restore, { autoLootDefault = "1", SoftTargetInteract = "3" },
		{ autoLootDefault = "0", SoftTargetInteract = "1" })
	eq(restore.autoLootDefault.old, "0"); eq(restore.autoLootDefault.set, "1")
	ns.Fishing_Backup(restore, { autoLootDefault = "1" }, { autoLootDefault = "1" })
	eq(restore.autoLootDefault.old, "0", "second backup keeps the first old value")
	local back = ns.Fishing_RestoreList(restore, { autoLootDefault = "1", SoftTargetInteract = "2" })
	eq(back.autoLootDefault, "0", "still ours -> restore")
	eq(back.SoftTargetInteract, nil, "player changed it -> leave it")
	eq(next(restore), nil, "backup emptied")
	eq(next(ns.Fishing_RestoreList({}, {})), nil, "nothing to restore")
end)

test("macro text", function()
	local names = { fishing = "Fishing", toy = "Anglers Fishing Raft" }
	eq(ns.Fishing_MacroText({ kind = "cast" }, names), "/cast Fishing")
	eq(ns.Fishing_MacroText({ kind = "dismount" }, names), "/dismount\n/cast Fishing")
	eq(ns.Fishing_MacroText({ kind = "toy", item = 85500 }, names), "/use Anglers Fishing Raft")
	eq(ns.Fishing_MacroText({ kind = "none" }, names), "")
	eq(ns.Fishing_MacroText({ kind = "toy", item = 85500 }, { fishing = "Fishing" }), "", "toy name not loaded")
end)

test("keys up", function()
	local down = { ["§"] = true }
	local isDown = function(k) return down[k] == true end
	eq(ns.Fishing_KeysUp({ "§" }, isDown), false)
	eq(ns.Fishing_KeysUp({ "F", "§" }, isDown), false, "second key held")
	eq(ns.Fishing_KeysUp({ "F" }, isDown), true)
	eq(ns.Fishing_KeysUp({}, isDown), true, "no keys")
end)

print(failures == 0 and "all passed" or (failures .. " failed"))
if failures > 0 then os.exit(1) end
```

- [ ] **Step 2: Run, expect failure** (from the AddOns folder): `lua Tomte/tests/test_fishing.lua` → fails, Data.lua
  doesn't exist.

- [ ] **Step 3: Write `Modules/Fishing/Data.lua`.** Header comment: pure rules for the Fishing module; IDs credited.

```lua
local addonName, ns = ...

-- Fishing: pure rules (no WoW API; unit-tested in tests/test_fishing.lua).
-- Fishing channel spell IDs and the bobber's game-object ID (35591) are game facts taken from Angleur's tables
-- (LegolandoBloom, All Rights Reserved: IDs only, no code). Toy and aura IDs checked on wowhead.

ns.FISHING_SPELL = 131474 -- the Fishing spell you cast (spellbook); its channel is 131476
ns.FISHING_BOBBER_OBJECT = 35591
ns.FISHING_RAFT_RENEW = 60 -- renew a raft with less than this many seconds left
ns.FISHING_LOOT_TIMEOUT = 3 -- loot protection never blocks longer than this
ns.FISHING_CHANNELS = {}
for _, id in ipairs({
	7620, 131476, 51294, 18248, 131474, 33095, 7732, 7731, 110410, 88868, 131490, 139505, 1252746, 158743,
	219847, 227511, 262860, 249045, 301092, 295727, 361269, 377895, 405274, 398703, 377831, 437890, 438491,
	463743, 1224771, 1294463, 1303761, 1239040, 1239227, 1241356, 1286703, 1303612, 1282907, 1239033,
}) do
	ns.FISHING_CHANNELS[id] = true
end
ns.FISHING_RAFTS = { -- toy item, its aura
	{ item = 85500, aura = 124036 }, -- Anglers Fishing Raft
	{ item = 198428, aura = 383268 }, -- Tuskarr Dinghy
	{ item = 166461, aura = 288758 }, -- Gnarlwood Waveboard
	{ item = 235801, aura = 1218420 }, -- Personal Fishing Barge
}
ns.FISHING_BOBBER_TOY = { item = 202207, aura = 397827 } -- Reusable Oversized Bobber: 1 h buff, 15 min cooldown

function ns.Fishing_IsFishingSpell(spellID, spellName, fishingName)
	if type(spellID) == "number" and ns.FISHING_CHANNELS[spellID] then
		return true
	end
	return type(spellName) == "string" and type(fishingName) == "string" and spellName == fishingName
end

-- "GameObject-0-server-instance-zone-<id>-spawn" -> id. Anything else -> nil.
function ns.Fishing_ObjectID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	-- guid:match, not strsplit: the same code runs in plain Lua tests and in game.
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	if kind ~= "GameObject" then
		return nil
	end
	return tonumber(id)
end
```

  Then `PickRaft`, `NextAction` (order: lootOpen+lootProtect → dead/blocked →
  not known → mounted (dismount unless flying) → swimming (raft or none) → bobber → raft renew → cast), `CVarPlan`
  (soft interact: `SoftTargetInteract` "3" unless already "3"; `SoftTargetInteractRange` "15" unless the number is
  already ≥ 15; `SoftTargetInteractRangeIsHard` "0" unless "0"; then auto loot and loud entries, each only when the
  current value differs; `sfx` written with `tostring`), `Backup`, `RestoreList`, `MacroText`, `KeysUp`.

- [ ] **Step 4: Run the tests until they pass:** `lua Tomte/tests/test_fishing.lua` → `all passed`.

### Task 2: CVar helpers (`Modules/Fishing/Helpers.lua`)

**Files:** Create `Modules/Fishing/Helpers.lua`.

**Interfaces:**
- Consumes: `ns.Fishing_CVarPlan`, `ns.Fishing_Backup`, `ns.Fishing_RestoreList` (Task 1); `db.restore`, `db.autoLoot`,
  `db.loud` (Task 5 defaults).
- Produces:
  - `ns.FishingHelpers_Init(db)`.
  - `ns.FishingHelpers_Start()`: reads the current values of the planned CVars, saves the backup in `db.restore`
    (before any `SetCVar`), sets them. Secure CVars are skipped when `InCombatLockdown()`.
  - `ns.FishingHelpers_Stop()`: restores via `RestoreList`. In combat it sets `pendingRestore` and registers
    `PLAYER_REGEN_ENABLED` to finish.
  - `ns.FishingHelpers_Pending() -> bool` (for `status`).
  - At `PLAYER_ENTERING_WORLD` (first one only): if `db.restore` has entries and no fishing channel runs, restore
    (crash recovery).

- [ ] **Step 1:** Write the file: own event frame, `C_CVar.GetCVar`/`C_CVar.SetCVar`, a `CVARS` list of every name
  `CVarPlan` can return (to read `current`), comment that the secure ones are `SoftTargetInteract` and
  `SoftTargetInteractRange` (wiki CVar list).
- [ ] **Step 2:** Read it against Review focus 2: backup written before the first `SetCVar`; a second `Start` without
  `Stop` doesn't overwrite `old`; `Stop` with an empty backup does nothing.
- [ ] **Step 3:** `lua Tomte/tests/test_theme.lua` passes (no literals added).

### Task 3: The key (`Modules/Fishing/Key.lua`)

**Files:** Create `Modules/Fishing/Key.lua`; modify `Bindings.xml`.

**Interfaces:**
- Consumes: Task 1 functions and constants; `ns.FishingHelpers_Start/Stop` (Task 2); `db` (Task 5).
- Produces:
  - `ns.FishingKey_Init(db, module)`, `ns.FishingKey_Toggle(active)`, `ns.FishingKey_Refresh()`.
  - `ns.Fishing_IsFishing() -> bool`, `ns.Fishing_LastCast() -> time|nil` (for Gathering).
  - `ns.FishingKey_Status() -> { keys = {...}, fishing, lootOpen, overridden }` (for `status`).
  - Globals: button `TomteFishing`, holder `TomteFishingBar`; `BINDING_NAME_CLICK TomteFishing:LeftButton` =
    "Fishing (cast / reel in)".

- [ ] **Step 1: Button.** Holder `CreateFrame("Frame", "TomteFishingBar", UIParent, "SecureFrameTemplate")`, button
  `CreateFrame("Button", "TomteFishing", holder, "SecureActionButtonTemplate")`, `RegisterForClicks("AnyDown")`,
  `SetAttribute("useOnKeyDown", true)`, icon texture, label (`UI.Text(button, 10, "textMuted", "label")`). Created
  in `Init` (out of combat at load). Holder hidden unless `db.button.shown` (or Edit Mode preview). Never anchor the
  holder to a normal frame (memory note).
- [ ] **Step 2: PreClick.** If `InCombatLockdown()` return. Build `s` from the game:
  `known = IsPlayerSpell(ns.FISHING_SPELL)`, `dead = UnitIsDeadOrGhost("player")`, `blocked` = in a vehicle, on a
  taxi or in a pet battle, `mounted = IsMounted()`, `flying = IsFlying()`, `swimming = IsSwimming()`, `lootOpen`
  (Step 4), owned rafts via `PlayerHasToy`, `raftLeft` from `C_UnitAuras.GetPlayerAuraBySpellID(aura)`
  (`expirationTime - GetTime()`, ignored when secret or 0), bobber owned / up / ready
  (`C_Container.GetItemCooldown(item)` start 0). Call `ns.Fishing_NextAction`, then set `type`/`macrotext` (toy:
  `type = "toy"`, `toy = item`; if that doesn't work in game, `macro` with `/use <name>` from
  `C_ToyBox.GetToyInfo`). Reasons `unknown`, `loot` show a short `UIErrorsFrame` message ("Fishing: not learned").
  The fishing name: `C_Spell.GetSpellName(ns.FISHING_SPELL) or PROFESSIONS_FISHING`.
- [ ] **Step 3: Reel override.** Event frame `keyEvents`:
  - `UNIT_SPELLCAST_CHANNEL_START(unit, _, spellID)`: return unless `unit == "player"`; return if `issecretvalue`
    on `spellID`; `name = C_Spell.GetSpellName(spellID)`; if `ns.Fishing_IsFishingSpell(spellID, name,
    fishingName)` → `fishing = true`, `ns.FishingHelpers_Start()` (only when `Active()`: a key is bound or the
    button shows), `want = "reel"`, start the waiter.
  - `UNIT_SPELLCAST_CHANNEL_STOP` (same checks, or `fishing` already true) → `fishing = false`, `lastCast =
    GetTime()`, `ns.FishingHelpers_Stop()`, `want = "clear"`, start the waiter.
  - Waiter: a hidden frame with `OnUpdate` every 0.05 s; when `ns.Fishing_KeysUp({ GetBindingKey(BINDING) },
    IsKeyDown)` and not in combat and not restricted, apply `want`: `"reel"` →
    `ClearOverrideBindings(keyEvents)` then `SetOverrideBinding(keyEvents, true, key, "INTERACTTARGET")` for each
    key; `"clear"` → `ClearOverrideBindings(keyEvents)`. Then hide. Gives up after 10 s.
  - `PLAYER_REGEN_DISABLED`: `ClearOverrideBindings(keyEvents)`, button `macrotext` "" and `type` "macro", hide the
    waiter. `PLAYER_REGEN_ENABLED`: if `fishing` still true, `want = "reel"` and start the waiter.
  - `ADDON_RESTRICTION_STATE_CHANGED`: refresh a local `restricted` flag from
    `C_RestrictedActions.IsAddOnRestrictionActive` for Combat, Encounter, ChallengeMode, PvPMatch.
  - `UPDATE_BINDINGS`: if `fishing`, reapply the override to the new key set (via the waiter); else clear.
  - `PLAYER_ENTERING_WORLD`: if `UnitChannelInfo("player")` returns a fishing spell (8th return is the spellID),
    `fishing = true` and reel again (after `/reload`). `PLAYER_LEAVING_WORLD`: clear.
- [ ] **Step 4: Loot protection.** `LOOT_OPENED`/`LOOT_READY` → `lootOpen = GetTime()`; `LOOT_CLOSED` → `lootOpen =
  nil`. `PreClick` treats `lootOpen` older than `ns.FISHING_LOOT_TIMEOUT` as closed.
- [ ] **Step 5: Button look.** `ns.FishingKey_Refresh()` (out of combat) sets the icon from the action PreClick would
  pick now, and the label: "Cast", "Reel in: <key>" while fishing, "Looting", "No key bound" when
  `GetBindingKey(BINDING)` is nil. Ticks every 1 s only while the holder is shown. Edit Mode:
  `ns.EditMode_Register({ name = "Fishing button", frame = ..., refresh = ..., saved = ... })`, position in
  `db.button.frame`.
- [ ] **Step 6: Bindings.xml.** Add `<Binding name="CLICK TomteFishing:LeftButton" category="Tomte"/>` after
  `TomtePetHeal`.
- [ ] **Step 7:** `lua Tomte/tests/test_theme.lua` passes; re-read Review focus 1, 3 and 5 against the code.

### Task 4: Raft dropdown data

**Files:** Modify `Modules/Fishing/Key.lua` (or `Fishing.lua`).

**Interfaces:** Produces `ns.Fishing_OwnedRafts() -> { item... }` and `ns.Fishing_RaftChoices() -> { { value, label }
}` with "Random" (0) first and each owned raft by `C_ToyBox.GetToyInfo(item)` name; when none are owned, one disabled
entry "You own no fishing raft".

- [ ] **Step 1:** Write both functions; names that aren't loaded yet show "Raft <item>" until the next open.
- [ ] **Step 2:** Same for the bobber checkbox tooltip: "You don't own the Reusable Oversized Bobber" when
  `PlayerHasToy(202207)` is false.

### Task 5: Module (`Modules/Fishing/Fishing.lua`), TOC, docs

**Files:** Create `Modules/Fishing/Fishing.lua`; modify `Tomte.toc`, `README.md`, `CHANGELOG.md`, `.gitattributes`
(no change needed: tests/ and docs/ are already ignored).

- [ ] **Step 1: `RegisterModule`:**
  - `key = "fishing"`, `name = "Fishing"`, `category = "General"`, `enabledByDefault = true`.
  - `description = "One key for fishing (Key Bindings > Tomte > Fishing): press it to cast, press it again when the
    bobber splashes to reel in and loot. Auto loot while fishing, no recast while looting, and optional louder
    splash, raft, Oversized Bobber and an on-screen button."`
  - `defaults` exactly as the spec's Data section (`restore = {}` is a collection and survives Reset).
  - `init` → `ns.FishingHelpers_Init(db)`, `ns.FishingKey_Init(db, module)`.
  - `toggle(active)` → `ns.FishingKey_Toggle(active)`; when off: clear the override and `ns.FishingHelpers_Stop()`.
  - `conflicts = { { addon = "Angleur", why = "both bind a fishing key, and Angleur's override wins on its own key. Turn one off." } }`.
  - `commands = { { "status", "key, soft interact and pending restores", Status } }`; `/tomte fishing` opens the
    options.
- [ ] **Step 2: Options:**
  - header "Key": a line with the bound key or "No key: Key Bindings > Tomte > Fishing".
  - checkbox `autoLoot` "Auto loot while fishing".
  - checkbox `lootProtect` "No recast while looting".
  - checkbox `loud.on` "Louder splash" (tooltip: music and ambience off, effects up, while the bobber is out);
    slider `loud.sfx` 0.2–1 step 0.1 "Effects volume"; checkbox `loud.background` "Also when WoW is in the
    background".
  - checkbox `dismount` "Dismount with the key (never while flying)".
  - checkbox `raft.on` "Use a raft when swimming" + dropdown `raft.pick` (Task 4).
  - checkbox `bobber` "Keep the Oversized Bobber up".
  - checkbox `button.shown` "Show the fishing button"; slider `button.scale`.
- [ ] **Step 3: Angleur notice.** At `PLAYER_LOGIN`, when `C_AddOns.IsAddOnLoaded("Angleur")` and a Tomte key is
  bound: `ns.Print("Angleur is on too. Disable it so your Fishing key works.")` once per session.
- [ ] **Step 4: TOC.** Append after `Modules/Pets/Pets.lua`: `Modules/Fishing/Data.lua`, `Modules/Fishing/Helpers.lua`,
  `Modules/Fishing/Key.lua`, `Modules/Fishing/Fishing.lua`.
- [ ] **Step 5: Docs.** README module list ("Fishing") and Credits ("Fishing channel spell IDs and the bobber object
  ID come from Angleur by LegolandoBloom; no code taken."). CHANGELOG Unreleased: "New Fishing module: one key to
  cast and to reel in, with auto loot while fishing (replaces Angleur's One Key)."
- [ ] **Step 6: Tests.** From the AddOns folder: `for t in Tomte/tests/test_*.lua; do lua "$t"; done` → all pass.

### Task 6: Review and in-game checklist

- [ ] **Step 1:** One reviewer agent reads the branch diff against the spec and this plan, with Review focus first.
- [ ] **Step 2:** Fix findings, re-run all tests.
- [ ] **Step 3:** Give the user the spec's in-game checklist (8 steps), plus: "`/tomte fishing status` after each
  step; paste BugSack errors with locals. If the reel press does nothing, `/dump C_CVar.GetCVar("SoftTargetInteract")`
  while the bobber is out, and `/etrace` filtered to `UNIT_SPELLCAST_CHANNEL` to see the spell ID."
- [ ] **Step 4:** No commit until the user confirms in game; then commit and add the CHANGELOG line (already done).
