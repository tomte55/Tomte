# Tomte: Fishing

Date: 2026-10-10. Research and a design to review before anything is built. The user picks which Angleur features
come over; Claude's recommendations are marked. Open questions are at the end.

## Goal

Replace the addon Angleur. The user mostly uses Angleur's one key: press it to cast, press it again when the bobber
splashes to reel in and loot. The module keeps that and adds a few small helpers, without the rest of Angleur's
settings.

Success: the user disables Angleur, binds one key in Key Bindings > Tomte > Fishing, and fishes the way they do now,
with one press to cast and one press to reel in.

## What Angleur does

Angleur 2.9.78 (the installed copy), every feature in plain words. **v1** = recommended for Tomte's first
version, **Later** = could come later, **Skip** = not needed in Tomte.

| # | Feature | What it is and why a fisher wants it | Tomte |
|---|---|---|---|
| 1 | **One Key** | One key casts Fishing. While the bobber is out, the same key reels in and loots it. No clicking the bobber. | **v1** (the core) |
| 2 | Double Click | Instead of a key: double right-click anywhere on the world to cast, and again to reel in. | Skip |
| 3 | Recast Key | A second key that casts again while the bobber is out, to throw away a bad cast. | Later |
| 4 | Sleep / Wake | Turns Angleur's key off and on (right-click its icon, `/angsleep`), because Angleur takes over the key even away from water. | Skip: Tomte's key is its own binding, so there's nothing to give back |
| 5 | Visual button | A small icon on screen that shows what your next key press will do (cast, reel, raft...). | **v1**, optional, off by default |
| 6 | Ultra Focus: Audio | While the bobber is out: music and ambience muted, sound effects turned up, so the splash is easy to hear. Put back after. Optionally keeps sound on while WoW is in the background. | **v1**, optional "Louder splash", off by default |
| 7 | Ultra Focus: Temp. Auto Loot | Turns auto loot on while fishing and back off after, so the catch goes straight to your bags. | **v1**, on by default |
| 8 | Recast Reminder | Plays a sound when a cast runs out (22 s) with no catch, so you notice you have to cast again. | Later |
| 9 | Raft | When you're swimming, the key uses a fishing raft toy (Anglers Fishing Raft, Tuskarr Dinghy, Gnarlwood Waveboard, Personal Fishing Barge), and renews it before it runs out. Lets you fish from open water. "Random raft" option. | **v1**, optional, off by default |
| 10 | Oversized Bobber | The key uses the Reusable Oversized Bobber toy when its buff is gone, so the bobber is bigger and easier to see. | **v1**, optional, off by default |
| 11 | Crate of Bobbers | The key keeps a cosmetic bobber toy applied (duck, murloc head...). Looks only. | Later |
| 12 | Extra Toys | Three slots for any toy; the key uses it whenever its buff is gone. | Later |
| 13 | Extra Items / Macros | Three slots (six with a plugin) for items or macros (fishing hat, lure, food); the key uses them when off cooldown and their buff is gone, or on a timer you set. | Later (this is where lures and hats would go) |
| 14 | Fishing gear set | Creates an "Angleur" equipment set, equips it when Angleur wakes and swaps your gear back when it sleeps; shows a button to get your weapons back in combat. | Skip for v1: on retail the rod sits in the profession tool slot and needs no swapping |
| 15 | Loot Protection | While the loot window is open, the key does nothing, so a double press or lag can't recast and lose the loot. | **v1**, on |
| 16 | Dismount With Key | Off: the key does nothing while mounted. On: the key dismounts you and casts. | **v1**: "nothing while mounted" built in; dismounting is an option, off |
| 17 | Release When Swimming | While swimming the key only uses a raft, or does nothing. | **v1**, built in |
| 18 | Soft Interact handling | Turns on the game's "interact with what's in front of you" targeting while fishing and puts your setting back after. This is what makes the reel press work. Also works around Plater, which turns it off. | **v1** (part of the core) |
| 19 | Disable Soft Icon | Hides the hook icon over the bobber (and over every other object). | Skip: it's a game option already |
| 20 | Special fishing spots | Ice-fishing holes, Nazjatar's compressed ocean and the oceanic vortex: the key interacts with them instead of casting. | Later |
| 21 | Void Finder (Midnight) | A separate key that targets a nearby Void Pool and puts a skull on it, with a sound and a scan animation. | Later (Midnight content) |
| 22 | Patient Chest alert (Midnight) | A big alert and sound when the "Patiently Rewarded" treasure spawns while you fish. | Later (Midnight content) |
| 23 | Fishing For Attention | Cancels the "Fishing For Attention" buff (the "Dressed in Fishing Equipment" look) when Angleur goes to sleep. | Skip |
| 24 | Shell | Config panel with tutorial, minimap button, compartment entry, slash commands, login messages, debug mode, a credits tab. | Skip: Tomte's own options and commands |
| 25 | Plugins | Separate addons: Angleur_Underlight (Underlight Angler handling) and Angleur_NicheOptions (more slots). | Skip |

The user's saved Angleur settings show One Key with Angleur's defaults (loot protection on, soft interact restored
after fishing, release when swimming) and nothing else turned on. v1 covers all of that.

## Research summary

How Angleur does it (read from its source, not copied):

- The key is an **override binding** owned by Angleur's frame. Out of combat, every 0.3 s and on events, it points the
  key at `SetOverrideBindingSpell(..., "Fishing")` to cast, or `SetOverrideBinding(..., "INTERACTTARGET")` while the
  fishing channel runs, or at a secure macro button for rafts and toys.
- **It never changes the binding while the key is held** (its comment: that caused a "raft jump" bug).
- While the channel runs it sets `SoftTargetInteract = 3`, `SoftTargetInteractRange = 15`,
  `SoftTargetInteractRangeIsHard = 0`, and restores the old values when the channel stops and at logout.
- Override bindings are cleared on `PLAYER_REGEN_DISABLED`. In 12.x it also stands down while an addon restriction
  (combat, encounter, Mythic+, PvP match) is active.
- Fishing channel spell IDs and the bobber's game-object ID (35591) are game facts and are taken from its tables,
  credited. Angleur is **All Rights Reserved**: no code, curated lists or layouts are taken.

API, checked against wow-ui-source live and warcraft.wiki.gg:

- **There is no secure action for "interact".** `SecureTemplates.lua` has no `interact` type and there's no slash
  command. The `INTERACTTARGET` binding runs `C_PlayerInteractionManager.InteractUnit("anyinteract")`, which is
  restricted. So the reel press must be a **key binding** pointed at `INTERACTTARGET`; a mouse click on an addon
  button can't reel in. This is also what Angleur does, and it's one real key press per action.
- `SetOverrideBinding(owner, isPriority, key, command)`: `#nocombat`, wiped by `/reload`. Clearing it in a
  `PLAYER_REGEN_DISABLED` handler works (that handler runs before lockdown; Tomte already relies on this).
- **CVars:** `SoftTargetInteract` (default 1 = gamepad only; 0 off, 1 gamepad, 2 mouse/keyboard, 3 always) and
  `SoftTargetInteractRange` (default 10) are **secure** CVars: only out of combat. Blizzard's own "Enable Interact
  Key" option writes `SoftTargetInteract` = 3 or 1. `SoftTargetInteractRangeIsHard` (default 0), `autoLootDefault`
  (default 0), `Sound_SFXVolume`, `Sound_MusicVolume`, `Sound_AmbienceVolume`, `Sound_EnableSoundWhenGameIsInBG`
  are not secure.
- `UNIT_SPELLCAST_CHANNEL_START/STOP (unit, castGUID, spellID, ...)`: secret when spell casts are restricted, so
  guarded with `issecretvalue`. `PLAYER_SOFT_INTERACT_CHANGED (oldTarget, newTarget)`: GUIDs, secret when unit
  identity is restricted.
- `LOOT_OPENED (autoLoot, isFromItem)`, `LOOT_READY (autoloot)`, `LOOT_CLOSED`; `IsFishingLoot()` is still in 12.1.
- `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.X)` (Combat, Encounter, ChallengeMode,
  PvPMatch, Map, Chat) and `ADDON_RESTRICTION_STATE_CHANGED (type, state)` are new in 12.0.0.
- Secure button types include `toy` (`UseToy(id)`) and `macro`. Memory: `type=spell` didn't summon mounts but a
  `/cast` macro did, so Tomte uses macros and tests `type=toy` in game.
- IDs (wowhead tooltips): Fishing 131474 (the spell you cast), 131476 (the 22 s channel); Reusable Oversized Bobber
  toy 202207 (1 h buff, aura 397827, 15 min cooldown); rafts: Anglers Fishing Raft 85500 (aura 124036), Tuskarr
  Dinghy 198428 (383268), Gnarlwood Waveboard 166461 (288758), Personal Fishing Barge 235801 (1218420).

## Design

Module key `fishing`, name "Fishing", category "General", enabled by default. It does nothing until the player binds
the key or turns on the button, so the default is safe for friends who never fish.

### 1. The key

- **Binding:** `CLICK TomteFishing:LeftButton`, "Fishing (cast / reel in)", in Bindings.xml. The key is set only in
  WoW's Key Bindings menu (Tomte > Fishing), like the Pet Battles key. It's a normal binding the player gives to
  Tomte, so Tomte never takes over a key the player uses for something else.
- **`TomteFishing`** is a `SecureActionButtonTemplate` button, registered for `AnyDown`, `useOnKeyDown = true`. Its
  `PreClick` (out of combat) picks the action and sets a macro, the Smart Mount pattern:
  1. Loot window open (loot protection) → empty macro.
  2. Dead, in a vehicle, on a taxi, in a pet battle → empty macro.
  3. Mounted → empty macro, unless "Dismount with the key" is on (then `/dismount` + cast, never while flying).
  4. Swimming: a raft if "Use a raft" is on and you own one → the raft toy; otherwise empty.
  5. "Keep the Oversized Bobber up" is on, you own it, its buff is gone and it's off cooldown → the toy.
  6. A raft is up with less than 60 s left (and rafts are on) → renew it.
  7. Otherwise → `/cast <Fishing>` (name from `C_SpellBook`/`C_Spell.GetSpellName(131474)`, falling back to the
     localized global `PROFESSIONS_FISHING`). Fishing not learned → a message and an empty macro.
  The rules live in a pure function (`Fishing_NextAction`) so they are unit-tested.
- **Reel in:** on `UNIT_SPELLCAST_CHANNEL_START` for a fishing spell (player, not secret, out of combat and not
  restricted), Tomte sets a priority override binding on every key bound to `TomteFishing` → `INTERACTTARGET`. On
  `UNIT_SPELLCAST_CHANNEL_STOP` it clears them. Both changes wait until those keys are released (a short `OnUpdate`
  polling `IsKeyDown`), since the cast press is still held when the channel starts.
- **Combat and restrictions:** `PLAYER_REGEN_DISABLED` clears the override and sets the button's macro to empty, so
  in combat the key does nothing (clicking the bobber with the mouse still works). After combat
  (`PLAYER_REGEN_ENABLED`) the state is checked again. While `IsAddOnRestrictionActive` is true for Combat,
  Encounter, ChallengeMode or PvPMatch, nothing is changed.
- **Reload mid-cast:** override bindings are gone after `/reload`; at `PLAYER_ENTERING_WORLD` Tomte reads
  `UnitChannelInfo("player")` and sets the reel binding again if a fishing channel is running.
- **Which spell counts as fishing:** a set of retail fishing channel IDs (from Angleur's table, credited), plus any
  channel whose name equals the Fishing spell's name, so a new variant still works in English and every locale.

### 2. Soft interact (needed for the reel)

- When a fishing channel starts, Tomte sets `SoftTargetInteract` to 3 and `SoftTargetInteractRange` to at least 15,
  and `SoftTargetInteractRangeIsHard` to 0. When the channel stops (or when combat starts or the module turns off),
  it puts the old values back.
- **Safe backups:** the old values are saved in `TomteDB.fishing.restore` before anything is changed. On login, a
  backup left from a crash or a disconnect is restored. A value is only put back when it still equals what Tomte set,
  so a change the player made meanwhile wins (the same rule as the cinematic music backup).
- Secure CVars change only out of combat; a restore that falls in combat waits for `PLAYER_REGEN_ENABLED`.
- Players who already use the Interact Key (value 3) see no change.

### 3. Helpers during a cast

All use the same backup and restore as part 2, set at channel start and restored at channel stop.

- **Auto loot while fishing** (on by default): `autoLootDefault` = 1. If it's already on, nothing changes.
  Safe: it only loots what you fished.
- **Louder splash** (off by default): music and ambience to 0, sound effects to a chosen level (slider, default
  100%). Sub-option "Also in the background" (off): `Sound_EnableSoundWhenGameIsInBG` = 1. Off by default because
  muting someone's music unasked is a surprise.
- **Loot protection** (on): from `LOOT_OPENED`/`LOOT_READY` until `LOOT_CLOSED`, or 3 s at most, the key's `PreClick`
  sets an empty macro.

### 4. Toys (one press each)

- **Use a raft** (off): option with a dropdown of owned rafts ("Random" included). Only used while swimming, and
  renewed when under 60 s are left. Out of water nothing happens.
- **Keep the Oversized Bobber up** (off): uses it when its buff is gone and it's off cooldown.
- Each one replaces one cast press; the next press casts. Never automatic.
- Disabled (greyed, with "You don't own one") when the player owns none. Ownership: `PlayerHasToy(itemID)`.
- Secure button `type = "toy"`, `toy = itemID`; if that fails in game, `/use <toy name>` from
  `C_ToyBox.GetToyInfo`.

### 5. Fishing button (optional)

- Option "Show the fishing button" (off). A 40 px icon in its own `SecureFrameTemplate` holder (`TomteFishingBar`),
  placed with Edit Mode ("Fishing button"). It's `TomteFishing` itself, so a click does what the key does.
- The icon shows the next action (Fishing, raft, bobber), and while the bobber is out "Press <key> to reel in" (a click
  can't reel in, see Research). A small label under it: "Cast", "Reel in: <key>", "Looting", "No key bound".
- Hidden in combat is not needed (it does nothing then); it stays as it is.

### 6. Status and commands

- `/tomte fishing` opens the module's options; `/tomte fishing status` prints the key, the soft interact values, the
  helpers in use and any pending restore; `help`.
- The options page shows "Key: <key>" or "No key: Key Bindings > Tomte > Fishing".
- First channel without a bound key and without the button: nothing happens, so no chat spam.

### Boundary with Gathering sessions

The Gathering sessions spec (`2026-10-10-tomte-gathering-design.md`, written in parallel) may count fishing loot.
The Fishing module is only the action and its helpers. It keeps no loot stats. It offers two small read-only calls
other modules can use:

- `ns.Fishing_IsFishing()`: true while a fishing channel runs.
- `ns.Fishing_LastCast()`: the time of the last fishing channel stop.

Gathering can also use `IsFishingLoot()` at `LOOT_OPENED` on its own, so it doesn't depend on this module being on.

## Data (`TomteDB.fishing`)

```
autoLoot = true
loud = { on = false, sfx = 1.0, background = false }
lootProtect = true
dismount = false
raft = { on = false, pick = 0 }              -- 0 = random owned raft, else the item ID
bobber = false                               -- Reusable Oversized Bobber
button = { shown = false, frame = {...}, scale = 1 }
restore = {}                                 -- [cvar] = { old = "x", set = "y" }; a collection (survives Reset)
```

## Files

| File | Contents |
|---|---|
| `Modules/Fishing/Data.lua` | Pure: IDs, `IsFishingSpell`, `ObjectID(guid)`, `NextAction`, `PickRaft`, `CVarPlan`, backup and restore rules, macro text. |
| `Modules/Fishing/Helpers.lua` | CVar set and restore (soft interact, auto loot, louder splash) with the saved backup. |
| `Modules/Fishing/Key.lua` | `TomteFishing` button, PreClick, reel override with key-release wait, loot protection, combat, the optional button and its Edit Mode entry. |
| `Modules/Fishing/Fishing.lua` | `RegisterModule`, events, options, commands, `uses`/`conflicts`. |

- **uses/conflicts:** conflicts with Angleur ("both bind a fishing key; Angleur's priority override wins on its own
  key. Turn one off."). Tomte prints that once when both are loaded and a Tomte key is bound.
- **Look:** theme roles only (`UI.Text`, `UI.Color`), no `|cff`, no font paths.
- **Credits:** README: "Fishing channel spell IDs and the bobber object ID come from Angleur (LegolandoBloom); no code
  taken."

## Error handling

- Every binding and secure-attribute change checks `InCombatLockdown()` and the restriction state first.
- Every event argument that can be secret (`spellID`, GUIDs) is checked with `issecretvalue` and ignored when secret.
- `CHANNEL_STOP` without a matching `START` (reload, zone change) still clears and restores.
- The override is cleared on `PLAYER_LEAVING_WORLD`, module off, and when the player unbinds the key
  (`UPDATE_BINDINGS`).
- Toy data that isn't loaded yet (`C_ToyBox.GetToyInfo` nil) means "not owned" for this press.

## Testing

- **Unit tests** (`tests/test_fishing.lua`, plain Lua 5.1): `IsFishingSpell` by ID and by name, nil input;
  `ObjectID` on game-object, creature and junk GUIDs; `NextAction` for every rule and its order; `PickRaft` with
  random and a chosen raft that's no longer owned; `CVarPlan` for each option mix; restore only when the value is
  still Tomte's; macro text.
- **In game** (user):
  1. Disable Angleur, bind the key, `/reload`. Cast at water, press again on the splash: you reel in and loot.
  2. Hold the key down while casting: no double action, and the reel press still works.
  3. Let a cast run out: the next press casts again.
  4. Press twice fast while looting: no recast until the loot is done.
  5. Get attacked mid-cast: in combat the key does nothing; afterwards it casts again. `/tomte fishing status` shows
     no pending restore.
  6. Check Options > Controls > "Enable Interact Key" and auto loot are as before after fishing.
  7. Mounted on the ground, flying, swimming: the key does nothing (or the raft, if turned on).
  8. With an NPC targeted near the water: the reel press still loots the bobber (note it if it talks to the NPC).

## Later (not in this design)

- Recast key and recast reminder sound.
- Crate of Bobbers, extra toys, and items/macros slots (lures, fishing hats, food) with a "keep up" rule.
- Special fishing spots (ice holes, compressed ocean, vortex) and Midnight's Void Finder and Patient Chest alert.
- A "fishing mode" that lends a normal key (for example a mouse button) to fishing until toggled off, for players who
  don't want a dedicated key.

## Open questions for the user

1. **Louder splash** off by default (Angleur's was off and you never turned it on). Want it on for you?
2. **Raft and Oversized Bobber**: worth having in v1, or move them to Later and keep v1 to the key alone?
3. **Fishing button on screen**: off by default. You had Angleur's icon showing; do you want Tomte's?
4. **Recast reminder** (a sound when a cast ran out with no catch): v1 or Later?

## User decisions (2026-10-10)

- All optional v1 features are built, each with its own setting: Louder splash, the on-screen button, Raft, Oversized Bobber, Dismount with key. Defaults stay as in this spec (safe for friends); the user turns on what they want.
- The rest of the open questions: Claude decides.
