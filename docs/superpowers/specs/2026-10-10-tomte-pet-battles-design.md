# Tomte: Pet Battles

Date: 2026-10-10. The user asked for the research and a finished design, to review before anything is built. Claude
made the decisions below; the questions still open for the user are at the end.

## Goal

The user feels they "never win" pet battles. The module helps in three ways:

1. **Know the matchup.** During a battle, show what the enemy pet is weak to and which of your pets fits best right
   now, using the game's own type data.
2. **Use the guides.** Recognize the tamer, link to its Xu-Fu's Pet Guides page, and let the user paste a strategy
   from that site. Tomte then loads the team with one click and shows the steps during the fight. In phase 2 it can
   also play the strategy's script, one key press per turn.
3. **Be ready.** Heal before a fight, warn when the team isn't ready, and keep a leveling pet in a chosen slot.

Success: the user can take a War Within tamer they've lost to, paste a Xu-Fu strategy, and win by following Tomte.

## Research summary

API, checked against wow-ui-source live at build 12.1.0 (69933) and warcraft.wiki.gg:

- **No pet battle or pet journal API returns secret values.** The full state of both teams can be read from
  `PET_BATTLE_OPENING_START` onward: species, family, health, power, speed, level, quality, abilities, cooldowns and
  auras. Exception: a PvP opponent's abilities.
- **Actions need a hardware event but are not protected:** `UseAbility`, `SkipTurn` and `UseTrap`. Assumed the same
  for `ChangePet` and `ForfeitGame`. Blizzard calls them from plain Lua `OnClick` handlers, so one key press or click
  per action from our own button or binding works. Pet Battle Scripts (maintained for 12.1) does the same. Automatic
  play with no press is impossible.
- **`C_PetBattles.GetAttackModifier(attackType, defenderType)`** returns 1.5, 1 or 0.667 and works outside battle.
  Tomte builds the 10×10 type chart from it at load instead of hardcoding it.
- **Collection:** `C_PetJournal.GetOwnedPetIDs()` ignores the journal's shared filters, so Tomte uses it with
  `GetPetInfoByPetID`/`GetPetStats` and never touches filters.
- **Loadout:** `SetPetLoadOutInfo(slot, petID)` and `SetAbility(slot, i, abilityID)` have no protection tag. They are
  disabled during a battle, and `IsJournalUnlocked()` must be true.
- **Healing:** Revive Battle Pets (spell 125439) and Battle Pet Bandage (item 86143) need a secure action button.
- **No battle API tells which NPC you're fighting,** and a tamer's team isn't visible before the fight. Tomte reads
  the NPC from `UnitGUID("npc")` at `GOSSIP_SHOW` or from the target (out of combat, guarded with `issecretvalue`).
- **Turn signal:** `PET_BATTLE_TURN_STARTED` doesn't exist. Tomte uses `PET_BATTLE_OPENING_DONE` and
  `PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE`, then checks `GetBattleState()`. A forced swap is `WaitingForFrontPets`
  together with `ShouldShowPetSelect()`.
- **Breed** isn't exposed. Working it out needs a base-stat table per species (see Later).

Guides and licenses:

| Source | What we may do |
|---|---|
| Xu-Fu's Pet Guides | Link to it; the user pastes strings they copied. **No bundled strategies, steps or scripts** (no license; the site expects credit to authors). |
| Rematch string format | Parse it (an interop format). Rematch's code is All Rights Reserved. Rematch is also broken on 12.1. |
| Pet Battle Scripts language | MIT. Tomte writes its own interpreter from the documented syntax (phase 2). |
| Wowhead | Link only. |
| PetTracker, PetMatch | All Rights Reserved; no code taken. |
| NPC, species, ability, achievement IDs | Facts; fine to use. |

- Xu-Fu encounter pages are `https://www.wow-petguide.com/Encounter/<id>`. The id is Xu-Fu's own number, not the NPC
  id, and one NPC can have several (Collector Dyna, NPC 223446, is 1589 for the world quest and 1601 for Family
  Battler). Tomte needs a small table: NPC id → Xu-Fu encounter id.
- Every Xu-Fu strategy page has a Rematch string with the team, the NPC id, the turn-by-turn notes and, when the
  author wrote one, a Pet Battle Script.

## Pieces

Module key `pets`, name "Pet Battles", category "General", enabled by default. Nothing runs outside pet battles and
the tamer card. Parts 1–6 are phase 1; part 7 is phase 2.

### 1. Battle advisor (on-screen, in battle)

- A widget that shows only during pet battles. It sits above Blizzard's ability bar by default and can be moved in
  Edit Mode (`ns.EditMode_Register`); it can be minimized like the other widgets.
- **Enemy row:** the three enemy pets, each with icon, family icon and a health bar. The active one is highlighted.
- **For the active enemy:**
  - *Hit it with:* the attack types that are strong against its family (from the type chart).
  - *Its attacks:* the types of its known abilities. Your pets whose family takes less damage from those are marked
    "resists".
- **Your row:** your three pets. Each gets a score against the active enemy:
  - +1 per available ability that is strong against the enemy's family, −1 per ability that is weak.
  - +1 if the pet's family resists most of the enemy's attacks, −1 if it is weak to them.
  - Dead pets and the leveling pet (see 6) are left out.
  - The best pet gets a "Best now" mark. When it isn't the active pet, the widget says "Swap to <name>?" with the
    reason ("strong vs Beast, resists Flying").
- This only advises. Clicking a pet does nothing, so it never clashes with Blizzard's swap UI.
- Blizzard already puts strong/weak arrows on your ability buttons, so Tomte doesn't repeat them.
- **PvP:** enemy abilities are unknown, so the "Its attacks" line is hidden.
- **Wild battles:** the same advice. If the enemy pet is rare (quality ≥ 3) and you don't own its species, it adds
  "Not in your collection – catch it?". The trap rules themselves are left to Blizzard.

### 2. Tamer recognition and guide links

- **Data/tamers.** `Modules/Pets/Tamers.lua` is a table of `npcID → { xufu = encounterID, achievement? }`. It covers
  War Within content (the 8 Khaz Algar world quests, the 4 Undermine fights, the Family Battler tamers) plus
  evergreen content new players hit (the pet battle dungeons, Celestial Tournament, master tamers). IDs are facts,
  checked one by one against the Xu-Fu pages during the build. Tamer names come from the game, not the table.
- **Which NPC you're fighting:**
  1. Remember `npcID` and the time on `GOSSIP_SHOW` (and `PLAYER_TARGET_CHANGED`) when the unit is a non-player and
     its GUID isn't secret.
  2. At `PET_BATTLE_OPENING_START` in an NPC battle (`IsPlayerNPC(Enemy)` and not wild), use that NPC if it was seen
     in the last 60 seconds.
  3. Learn the enemy species list for that NPC, saved in `db.learned`. When no fresh NPC is known, for example for
     tamers started from an item or a dungeon step, match the species list against what was learned.
- **Guide links.** Shown on the tamer card, the battle advisor and the page:
  - "Xu-Fu guide" when the table knows the NPC; "Wowhead" always.
  - WoW can't open a browser, so a click opens a small popup with the URL selected, ready for Ctrl+C. It uses the
    same edit-box pattern as Blizzard's "copy link" dialogs.

### 3. Strategies (paste from Xu-Fu)

- **Import:** on the page, an "Import strategy" box. The user pastes the string from a Xu-Fu strategy page (its
  "Rematch string" button) or any Rematch, PetMatch or Long Live Pets export in the same format. Several strings in
  one paste are all imported.
- **Parse** (pure, `Strings.lua`). Format:
  `Name:npcIDs(base32, comma separated):tag1:tag2:tag3[:P:prefs][:N:notes]`
  - A **pet tag** is three ability digits (0 any, 1 or 2) + breed (0 or 3–12) + speciesID in base 32.
  - Special tags: `ZL` leveling pet, `ZI` ignored slot, `ZR<type>` random pet of that family, `ZU` unknown.
  - **Notes** turn `\n` back into new lines. A `-----BEGIN PET BATTLE SCRIPT-----…-----END…` block is split off as
    the script.
  - Group headers (`__ Name … __`) and chat-split markers are skipped.
  - Lines Tomte can't read are listed back ("2 imported, 1 skipped: not a team string").
- **Stored** in `db.teams[id]`: `{ name, npcs = {npcID...}, pets = {tag...}, prefs?, notes, script?, imported =
  time }`. A string for an NPC that already has a team is added as a second team, not a replacement. The page lets
  the user rename, delete, pick the active team per NPC and re-paste.
- **Credit:** the page and the advisor say "Strategy from Xu-Fu's Pet Guides – credit to its author" on imported
  teams. The string itself has no author field, so Tomte can't name the author.

### 4. Tamer card and "Load team" (out of battle)

- When you talk to or target a tamer that Tomte knows, a small card appears next to the gossip window (or near the
  target frame when there's no gossip). It shows:
  - the tamer name, the team that will be used, and the Xu-Fu and Wowhead links;
  - a **readiness line**: "Ready", or what's wrong ("Iron Starlette is dead", "Slot 2 is level 17", "You don't own
    Anomalus");
  - buttons: **Load team** and **Heal** (see 5).
- With no saved team it says "No strategy saved – get one from Xu-Fu" plus the link. When the team was learned in an
  earlier fight it adds "Seen: <three family icons>", so the user knows what's coming.
- **Load team** (`Journal.lua`):
  - For each pet tag, pick the owned pet of that species: matching breed if the tag sets one (breed needs the Later
    data; until then breed is shown but not matched), then level 25, then highest quality, then most health, never
    a dead pet. Ties keep the pet already slotted.
  - Abilities: digit 1/2 in tier i picks `ids[i]` / `ids[i+3]` from `GetPetAbilityList(speciesID)`; 0 keeps the
    current ability.
  - `ZL` puts the leveling pet in (see 6); `ZR<type>` takes the best owned pet of that family; `ZI`/`ZU` leave the
    slot alone.
  - Missing species: the slot is left as it is and the card says which pet is missing. A full strategy needs all its
    pets, so the user picks another strategy on Xu-Fu (the substitutes are listed there).
  - Refuses with a message during a battle, in combat or when `IsJournalUnlocked()` is false.
  - "Auto-load team when talking to the tamer": an option, **off** by default so nothing changes your team unasked.

### 5. Healing

- A secure **Heal** button with the Revive Battle Pets icon and its cooldown. When the spell is on cooldown and you
  own Battle Pet Bandages, it uses a bandage instead and shows the count.
  - Created lazily out of combat as a `SecureActionButtonTemplate` in its own holder parented to UIParent. It is not
    anchored to the card, because secure frames can't anchor to normal frames (see memory); it is placed from the
    card's screen rect instead.
  - Hidden on `PLAYER_REGEN_DISABLED`.
  - Revive uses a `/cast` macro with `C_Spell.GetSpellName(125439)`. Both `type=spell` and macro are tried in
    testing; mounts needed the macro.
  - Bandage uses `type=item`, `item:86143`.
- It shows on the tamer card. After a battle where your pets got hurt, the same button shows by itself where the
  battle helper sits, until the pets are healed, 30 seconds pass or a battle starts. A toast can't carry a secure
  button.
- Binding: `CLICK TomtePetHeal:LeftButton` "Heal battle pets", in Bindings.xml.

### 6. Leveling slot

- Option "Leveling slot", **off** by default; pick slot 1, 2 or 3.
- **Queue** on the page: owned battle pets under 25, picked from a searchable list sorted by level. Rows can be
  reordered and removed.
- After every battle (`PET_BATTLE_CLOSE`, out of combat, journal unlocked): if the pet in the leveling slot is 25 or
  isn't the queue's pet, the next queued pet under 25 is loaded into that slot and the toast says so ("Mr. Wiggles
  hit 25 – next up: Snowy Owl").
- **In battle:** while the leveling pet is active and has acted once, the advisor says "Swap your leveling pet out".
  This is the carry trick: the pet gets XP if it was in the fight and is alive at the end.
- The leveling pet is never suggested as "Best now".

### 7. Script runner (phase 2)

- When the active team has a script, the advisor gets a **Next move** button showing the ability (or swap) the
  script picks this turn. Pressing it does that action. One press per action, never automatic.
- Key: an override binding set at `PET_BATTLE_OPENING_START` and cleared at `PET_BATTLE_CLOSE`, through
  `SetOverrideBindingClick` on the Next move button. The key is picked in options, **unset** by default, with a
  suggestion not to use 1–3 because Blizzard routes those to abilities. A Bindings.xml entry "Next pet battle move"
  works as well.
- **Interpreter** (`Script.lua`, pure, written by Tomte from the documented Pet Battle Scripts syntax):
  - Commands: `use`, `change`, `standby`, `catch`, `quit`, `test`, `if/else/endif`.
  - Conditions on `self`/`enemy`(`#n`): `hp`, `hpp`, `hp.full`, `dead`, `active`, `exists`, `type`, `speed`,
    `speed.fast`/`slow`, `aura(x).exists`/`duration`, `ability(x).usable`/`duration`/`strong`/`weak`; also `round`,
    `weather(x)`, `ally`/`enemy.round`.
  - Operators: `&` only (no `|`, no `else`; `ei` = `endif`); `!` prefixes yes/no conditions; `= == != > < >= <= ~ !~`.
  - Every press reads the whole script from the top: the first line whose condition holds and whose action can be
    done wins (Pet Battle Scripts' own rule, from its source).
  - A script line it can't read stops the runner for that fight with "Script uses something Tomte can't run yet:
    <line>". The steps (part 3) still show.
- **Delegation:** when Pet Battle Scripts is installed, Tomte doesn't bind its own key by default (it is listed under
  "uses/conflicts"), so two addons don't fight over the same key.

## Tomte window page "Pet Battles"

Home page entry (`kind = "page"`) with tabs:

- **Tamers:** War Within tamers first, then the rest, grouped by section. Each row shows the name, zone, whether
  there's a saved team, whether today's world quest is up (from the World Quests scan when that module is on), and
  the guide links. Clicking a row shows its teams.
- **Teams:** the import box; saved teams with their three pets (owned or missing, level), notes, rename, delete and
  set active.
- **Leveling:** the queue (part 6).
- **Type chart:** the 10×10 chart built from the game, plus one line per family: "strong vs / weak vs / takes less
  from". It's a reference for the "I don't know the types" problem.

The battle advisor's "Steps" panel: when a team with notes is active for this fight, the notes show under the advisor
(collapsible, the "chat" font role because the text was written by others) with the round number ("Round 3"). Steps
often say "Turn 1: …", so the round number lets the user follow along.

## Data (`TomteDB.pets`)

```
advisor = { shown = true, frame = {…}, collapsed = false, steps = true }
card = { shown = true, autoLoad = false }
heal = { after = true }
leveling = { on = false, slot = 1 }
levelQueue = {}                                        -- petGUIDs, a collection (survives Reset)
runner = { key = "" }                                  -- phase 2
teams = {}                                             -- id → team (collection, never reset)
active = {}                                            -- npcID → team id
learned = {}                                           -- npcID → { species = {…}, seen = time }
```

`teams`, `learned` and `levelQueue` are collections and survive "Reset settings".

## Files

TOC order, appended after the existing modules:

| File | Contents |
|---|---|
| `Modules/Pets/Data.lua` | Pure: type chart from a modifier function, matchup scores, "best now", team picking from candidate pets, leveling-queue rules, readiness. |
| `Modules/Pets/Strings.lua` | Pure: base 32, Rematch string parse, notes and script split. |
| `Modules/Pets/Tamers.lua` | NPC → Xu-Fu encounter table, sections. |
| `Modules/Pets/Script.lua` | Pure interpreter on a state table (phase 2). |
| `Modules/Pets/Journal.lua` | Reads owned pets, Load team, leveling refill, secure Heal button. |
| `Modules/Pets/Battle.lua` | Reads battle state into a plain table, the advisor widget and steps panel, NPC capture. |
| `Modules/Pets/Card.lua` | The tamer card and URL copy popup. |
| `Modules/Pets/Page.lua` | The window page. |
| `Modules/Pets/Pets.lua` | `RegisterModule`, events, options, commands, Home entry. |

- **Commands:** `/tomte pets` opens the page; `/tomte pets import` focuses the import box; `/tomte pets chart` opens
  the type chart; `help`.
- **Options:** advisor on/off, steps on/off, tamer card on/off, auto-load team, heal button after battles, leveling slot on/slot,
  Next move key (phase 2).
- **uses/conflicts:**
  - Pet Battle Scripts: the runner stands down.
  - Rematch: Tomte's auto-load is turned off when Rematch is on, since both would change the team on target.
- **Look:** written against the redesign end state: `UI.Panel`, `UI.Text` with color roles, family icons via
  Blizzard's `PET_TYPE_SUFFIX` (`Interface\PetBattles\PetIcon-<suffix>`), and no `|cff` literals. The build starts after the redesign branch lands.

## Error handling

- Every journal and loadout call checks `IsInBattle`, `InCombatLockdown` and `IsJournalUnlocked` first, and tells the
  user why it did nothing.
- Battle reads guard nil for missing slots (teams of fewer than 3) and PvP enemies' hidden abilities.
- NPC capture ignores secret GUIDs and anything older than 60 s.
- `PET_BATTLE_CLOSE` can fire twice; the after-battle work runs once per battle.
- `GetPetInfoTableBySpeciesID` is new in 12.1, so Tomte uses `GetPetInfoBySpeciesID` instead.

## Testing

- **Unit tests** (`tests/test_pets.lua`, plain Lua 5.1):
  - base 32;
  - Rematch strings: real examples, multi-line paste, notes with `\n`, script split, special tags, bad lines;
  - type chart from a stub modifier;
  - matchup scores and "best now", including dead and leveling pets;
  - team picking: breed, level, quality, dead, ties;
  - leveling refill;
  - phase 2: the interpreter on stub states, for each command and condition.
- **In game** (user):
  - a wild battle (advisor and swap hint);
  - talk to a Khaz Algar tamer (card, links, readiness);
  - import a Xu-Fu string, Load team, fight with the steps;
  - Heal button (spell and bandage);
  - a leveling-slot refill after a battle;
  - Edit Mode placement.

## Later (not in this design)

- **Breed display and breed matching:** needs a per-species base-stat table. BattlePetBreedID's data is MIT and the
  numbers are game facts, so it could be added with credit.
- **Counter team from learned enemies:** suggest your best three before a fight against a tamer you've already met,
  for tamers with no Xu-Fu import.
- **Squirt day / Pet Battle Bonus Week reminders.**
- **"Essential pets" checklist** against your collection.

## Open questions for the user

1. **Phase 2 (script runner):** build it in this round or later? It's the biggest piece (an interpreter), and it is
   what turns a pasted strategy into "press one key each turn".
2. **Auto-load team on tamer:** default off (decided above). Fine?
3. **Tamer table scope:** War Within plus the evergreen dungeons, Celestial Tournament and master tamers, or War
   Within only to start?

## Decisions after review (2026-10-10)

The user approved the design and asked for everything to be built in one go:

- The script runner (phase 2) is built now.
- Auto-load stays off by default.
- The tamer table covers every NPC battle section on Xu-Fu.

Changes made while planning:

- **Heal after a battle:** the Heal button shows by itself, not in a toast (see 5).
- **Script language:** taken from Pet Battle Scripts' source (axc450/pbs v1.13.2), where it differs from its wiki.
  - Ids are written `Name:123`.
  - There is no `|` or `else`.
  - `test()` stops the script.
  - `change(next)` is the next living pet that can swap in, wrapping 3 → 1.
  - A pet or ability that doesn't resolve makes its condition false; Pet Battle Scripts would raise a Lua error.
- **Tamer names:** the table carries English encounter names, because the game has no API for an NPC's name by id.
  The addon's UI is English anyway.
- **Credit:** Xu-Fu's notes start with "Strategy added by <author>", so Tomte names the author on the team and in the
  steps.
- **Test fixtures:** the unit tests use Tomte's own made-up strings in the real format. No Xu-Fu strategy text goes into
  the repo.
- **Next move key (user, 2026-10-10):** only in WoW's Key Bindings menu (Tomte > Next pet battle move). There is no
  key setting in Tomte and no override binding during battles, so nothing about Pet Battle Scripts' own key matters.
