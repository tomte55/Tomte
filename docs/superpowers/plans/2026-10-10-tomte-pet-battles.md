# Pet Battles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tomte module `pets` that helps the player win pet battles: matchup advice in battle, tamer recognition with
Xu-Fu links, imported strategies (team load, steps, a one-key script runner), healing and a leveling slot.

**Architecture:** Pure logic (type chart, scoring, team picking, Rematch strings, the script interpreter) sits in
files with no WoW calls, unit-tested with plain Lua. Game readers and UI sit in separate files. They call the pure
functions with plain tables, and the interpreter reads the battle through an `api` adapter object.

**Tech stack:** WoW retail 12.1 Lua (5.1), Tomte's `ns.UI` toolkit and theme roles, `ns.RegisterModule`, Edit Mode
registration, Bindings.xml.

**Spec:** `docs/superpowers/specs/2026-10-10-tomte-pet-battles-design.md`.

**Execution:** the user delegated the whole build ("plan it and build it, come back when it is all done"), so Claude
implements natively, then one reviewer agent checks the branch. Work stays on branch `pets`, uncommitted, until the
user has checked it in game (CLAUDE.md).

## Global constraints

- Lua 5.1 syntax (CI runs 5.1): no `goto`, no `//`, no integer-only operators, no `utf8`.
- No numeric RGB in `SetTextColor`, `SetVertexColor`, `SetColorTexture` or `CreateColor`; colors come from theme roles
  (`UI.Color(role)`). No `|cff` literals, no font paths. The `tests/test_theme.lua` source scan enforces this; a line can
  opt out only with `-- theme: <reason>`.
- One event frame per file, dispatching with `self[event](self, ...)`.
- Globals: only `Tomte_*` functions and the named frames `TomtePetNext` and `TomtePetHeal`.
- Defaults are safe: nothing changes the team unless asked (auto-load off, leveling off); no key is bound by default.
- Secure buttons are created out of combat, never anchored to normal frames, and hidden on `PLAYER_REGEN_DISABLED`.
- No Xu-Fu strategy text anywhere in the repo (tests use made-up strings).
- Pet battle actions run only from a click or key handler; nothing acts on its own.

## Review focus

1. **Duplicate species in a team** (two Anomalus): Load team must pick two different pets, and say so when only one is
   owned. → Data test "picks distinct pets".
2. **Rematch strings whose name or notes contain `:`**, quotes, `[url]` tags, HTML entities, or no `N:` part. → Strings
   tests.
3. **A script whose pet or ability selector doesn't resolve** (`self(#3)` with a two-pet team, an ability not on the
   bar) must give a false condition, not a Lua error. → Script test "nil selectors".
4. **`PET_BATTLE_CLOSE` firing twice**, and a `/reload` mid-battle: after-battle work runs once; round counters
   survive the reload. → Battle.lua guards (reviewed by reading; can't be unit-tested).
5. **A player with no battle pets, or a locked journal** (another client logged in): readiness, Load and the leveling
   refill say why and do nothing. → Data test "empty owned".

---

### Task 1: Tamer table

**Files:** create `Modules/Pets/Tamers.lua` (from the research agent's generated table, names as fields).

**Produces:**
- `ns.PETS_SECTIONS = { { id, name, expansion }... }`, newest first.
- `ns.PETS_ENCOUNTERS = { [xufuID] = { section, name, npcs = {...} } }`.

- [ ] Generate the file from the scratchpad table: comment names become `name = "..."` fields.
- [ ] Spot-check 5 entries against Xu-Fu (done by the agent) and that Collector Dyna 223446 maps to 1589 and 1601.

### Task 2: Pure data (`Modules/Pets/Data.lua`)

**Produces** (all pure):
- `ns.Pets_TypeChart(modifier, n)`: `chart[atk][def]` = modifier(atk, def) for 1..n.
- `ns.Pets_Strong(chart, defType)`: attack types >1 against `defType`, sorted.
- `ns.Pets_Matchup(chart, pet, enemy)`: returns `score, info`.
  - `pet = { type, dead, abilities = { { type, noHints, usable } } }`; `enemy = { type, abilities = { { type, noHints } } }`.
  - `info = { strong = n, weak = n, resists = n, weakTo = n }`.
- `ns.Pets_Best(chart, allies, enemy, opts)`: `opts = { active, leveling }`. Returns `bestIndex, scores`. Dead pets
  and the leveling pet are skipped; ties keep the active pet.
- `ns.Pets_SwapAdvice(chart, allies, enemy, opts)`: returns `{ index, info }` when the best pet beats the active one by
  at least 2 points (`ns.PETS_SWAP_MARGIN`), else nil.
- `ns.Pets_IndexEncounters(encounters)`: returns `npc → { xufuID... }` (sorted).
- `ns.Pets_Signature(speciesList)`: sorted species joined by `,`.
- `ns.Pets_PickTeam(team, owned, current, opts)`: returns `picks, missing`.
  - `owned = { { guid, species, level, rarity, health, maxHealth, type, abilities = {6 ids} } }`;
    `current = { [slot] = guid }`; `opts = { leveling = guid|nil }`.
  - `picks[slot] = { guid, abilities = { id|nil x3 } }`, or `{ keep = true }`.
  - `missing = { { slot, species } }`.
  - Order: level 25 first, then rarity, then health ratio, then "already in this slot". Never a dead pet, never the
    same guid twice. Tags: species, `leveling`, `random` (type, 0 = any), `ignore`.
- `ns.Pets_Readiness(loadout, opts)`: returns problems `{ kind = "empty"|"dead"|"hurt"|"low", slot }`. `low` means
  level < `opts.minLevel` (default 25); `opts.leveling` marks the slot that is allowed to be low.
- `ns.Pets_NextLeveling(queue, owned)`: returns `guid|nil, cleanedQueue` (drops 25s and pets you no longer own).
- `ns.Pets_ParseAuthor(notes)`: the text after "Strategy added by ", or nil.
- `ns.Pets_CleanNotes(notes)`: strips `[url=...]x[/url]` → `x`, `[b]`, `[i]` and `[u]` tags, and HTML entities.

**Tests:** `tests/test_pets.lua`:
- chart from a stub modifier (the 10-type table);
- `Strong`;
- matchup scoring: strong, weak, `noHints`, resists;
- `Best` skips dead and leveling pets and keeps the active pet on a tie;
- swap margin;
- `IndexEncounters`;
- `Signature` order;
- `PickTeam`: level, rarity, dead, distinct pets for a duplicate species, missing, random and leveling tags, ties
  keep the slot;
- `Readiness`, including an empty loadout;
- `NextLeveling` pruning;
- author and notes cleaning.

### Task 3: Rematch strings (`Modules/Pets/Strings.lua`)

**Produces:**
- `ns.Pets_Base32(s)`: number, or nil.
- `ns.Pets_ParseTag(tag)`, which returns one of:
  - `{ kind = "species", species, abilities = {d1, d2, d3}, breed }`;
  - `{ kind = "leveling" }`, `{ kind = "random", type }`, `{ kind = "ignore" }`;
  - nil.
- `ns.Pets_ParseTeam(line)`: returns `team | nil, err`. `team = { name, npcs = {...}, pets = { tag x3 }, prefs = {
  minHP, maxHP, minLevel }?, notes, script? }`.
  - Notes: everything after the first `:N:` (or a trailing `:N:`); literal `\n` becomes a newline.
  - Script: between the BEGIN and END markers (to the last END). HTML entities are unescaped, `&amp;` last.
- `ns.Pets_ParseImport(text)`: returns `teams, skipped`. One team per line; group headers `__...__` are skipped
  silently; other bad lines count as skipped.
- `ns.PETS_BREEDS[3..12]` = `"B/B"`, `"P/P"`, `"S/S"`, `"H/H"`, `"H/P"`, `"P/S"`, `"H/S"`, `"P/B"`, `"S/B"`, `"H/B"`.

**Tests:**
- base 32 (`6Q6M` = 223446, `2OQ` = 2842);
- tags (`12102OQ`, `ZL`, `ZR0`, `ZR8`, `ZI`, junk);
- made-up team strings: name with quotes, notes with `:` and `\n`, a `P:::::25::` part, a script block, entities,
  no N part, several NPC ids;
- import of two lines plus a header plus junk.

### Task 4: Script interpreter (`Modules/Pets/Script.lua`)

Implements the reference (scratchpad `pbs/reference.md`, summarized in the spec).

**Produces:**
- `ns.PetScript_Build(code)`: returns `script | nil, err`, where `err` is the line number and text.
- `ns.PetScript_Next(script, api)`: returns `action | nil`.
  - Actions: `{ kind = "ability", slot }`, `{ kind = "change", pet }`, `{ kind = "skip" }`, `{ kind = "trap" }`,
    `{ kind = "quit" }`, `{ kind = "test", text }`.
  - It never acts itself. The caller performs the action, so the same call serves as the preview.
- `api` (methods, owner 1 = ally, 2 = enemy):
  - Pets: `NumPets(o)`, `Active(o)`, `Health(o,i)`, `MaxHealth(o,i)`, `Speed(o,i)`, `Power(o,i)`, `Level(o,i)`,
    `Type(o,i)`, `Quality(o,i)` (0-based), `Species(o,i)`, `Name(o,i)`.
  - Abilities: `Ability(o,i,slot)` returns `id, name, type, noHints`; `AbilityState(o,i,slot)` returns `usable, cd,
    lockdown`.
  - Auras and weather: `Auras(o,i)` and `PadAuras(o)` return `{ { id, name, turns } }`; `Weather()` returns `id, name,
    turns`.
  - Rules and turn state: `Modifier(atk, def)`, `CanSwapOut()`, `PetSelect()`, `CanSwapIn(i)`, `CanSkip()`,
    `Trap()` returns `usable, err`, `Round(o|nil)`, `Played(o,i)`, `Collected(o,i)` returns `owned, max, obtainable`.
  - Names: `TypeOf(name)` and `QualityOf(name)` return a number, for localized names.
- Grammar: lines, `--` comments, a leading `/`, `[cond & cond]`, `if/endif/ei`, `!`, operators by type, `~` lists,
  `Name:id`, `#n`, owner(pet).
- Conditions: everything in reference §4. A nil pet or ability is false (`ability.duration` = huge, `aura.duration` = 0).

**Tests:**
- build errors (unknown command, `else`, unpaired `if`, bad operator, end-of-line comment);
- first-match-wins with fall-through on cooldown;
- `if` block fall-through;
- `change(next)` wrapping and dead pets;
- forced swap (`PetSelect`);
- `standby` / `catch` availability;
- `test` stops;
- conditions: hp, hpp, `hp.full`, `can_explode`, `hp.low`, aura exists/duration, pad aura, weather, ability
  usable/duration/strong/weak/type, speed fast/slow, type by name, quality, round with and without owner, played,
  exists, active, `is`, id, collected;
- `~` lists;
- nil selectors;
- a 20-line made-up script in the shape of the real ones.

### Task 5: Journal reader and actions (`Modules/Pets/Journal.lua`)

**Produces:**
- `ns.PetsJournal_Owned()`: the cached owned list (Task 2 shape plus `name`, `icon`). Rebuilt after
  `PET_JOURNAL_LIST_UPDATE` (marked dirty).
- `ns.PetsJournal_Loadout()`: `{ [slot] = { guid, species, name, icon, level, health, maxHealth, type } | nil }`.
- `ns.PetsJournal_CanChange()`: `true`, or `false, reason` (in battle, in combat, journal locked).
- `ns.PetsJournal_LoadTeam(team, opts)`: returns `ok, missing, reason`. It uses `Pets_PickTeam` and calls
  `SetPetLoadOutInfo` / `SetAbility`.
- `ns.PetsJournal_RefillLeveling(db)`: returns the name of the pet now loaded, or nil.
- The secure heal button `TomtePetHeal` (holder `TomtePetHealHolder`):
  - `ns.PetsHeal_Show(x, y)` (UIParent coords, BOTTOMLEFT of the button), `ns.PetsHeal_Hide()`,
    `ns.PetsHeal_Refresh()`.
  - Macro: `/cast <Revive name>` when ready, else `/use item:86143` when you own bandages.

### Task 6: Battle reader, advisor and runner (`Modules/Pets/Battle.lua`)

**Produces:**
- The NPC capture (`GOSSIP_SHOW`, `PLAYER_TARGET_CHANGED`): `ns.PetsBattle_LastNPC()` returns `npc|nil` (fresh within
  60 s).
- `ns.PetsBattle_API`: the live `api` for Script.lua. Round and played state live in `db.cache` and survive a reload.
- Battle context at `PET_BATTLE_OPENING_START`: `{ npc, wild, pvp, team }`. It learns `db.learned[npc]`.
- The advisor widget (Edit Mode "Pet battle helper"), with these parts:
  - enemy row, hint lines, ally row with the best mark and swap line;
  - leveling swap line;
  - catch hint;
  - steps panel with round number and author credit;
  - the Next move button `TomtePetNext` (icon, key text) and the guide button.
- Override key: set at opening, cleared at close, never in combat, skipped when Pet Battle Scripts is loaded.
- After battle: once per battle (guard flag, delayed 0.5 s, not in battle), leveling refill, then the heal button
  when pets are hurt.

### Task 7: Tamer card and popups (`Modules/Pets/Card.lua`)

**Produces:**
- `ns.PetsPopup_Show({ title, text, multiline, readOnly, onSave(text) -> err|nil })`: one shared edit dialog, used
  for copying URLs and editing scripts.
- `ns.PetsCard_Show(npc)` / `ns.PetsCard_Hide()`. Shown on `GOSSIP_SHOW` for a known NPC, hidden on `GOSSIP_CLOSED`.
  - It has a name, the team (with a dropdown when there are several), readiness lines, the Load team and Guide /
    Wowhead buttons, and the heal button placed below it.
- `ns.Pets_XufuURL(id)`, `ns.Pets_WowheadURL(npc)`.

### Task 8: Window page (`Modules/Pets/Page.lua`)

**Produces:** `ns.PetsPage = { title = "Pet Battles", Create, Refresh }` with four views behind buttons (as in
BoardPage):
- **Tamers:** sections with headers; a row shows the name, team count and learned families; click to copy the Xu-Fu
  link.
- **Teams:** import box and button; team rows show the pet icons and owned or missing state, with Load, Active,
  Script and Delete. Hovering a row shows its notes.
- **Leveling:** the queue (up, down, remove) and the add list (search, owned pets under 25).
- **Type chart:** the 10×10 grid, plus a line per family.

### Task 9: Module (`Modules/Pets/Pets.lua`), TOC, bindings, docs

- `RegisterModule`:
  - key `pets`, category "General", enabled by default;
  - defaults as in the spec plus `cache`;
  - options and commands (`open`, `import`, `chart`, `next`);
  - Home page entry;
  - `uses` Pet Battle Scripts and Rematch.
- TOC: add the 8 files after `Modules/Value/Value.lua`, in the order Tamers, Data, Strings, Script, Journal, Battle,
  Card, Page, Pets.
- Bindings.xml: `CLICK TomtePetNext:LeftButton` and `CLICK TomtePetHeal:LeftButton`, with `BINDING_NAME_*` labels.
- README module list and Credits (Xu-Fu: links only; Pet Battle Scripts language: MIT, own implementation; Rematch
  string format), and a CHANGELOG Unreleased line.
- Run all tests: `for t in Tomte/tests/test_*.lua; do lua "$t"; done` from AddOns, including the theme scan.

### Task 10: Review

- One reviewer agent reads the whole branch diff against the spec and this plan. Fix its findings, re-run the tests,
  and write the in-game test checklist for the user.
