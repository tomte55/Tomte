# Tomte: Friend-facing extras

Date: 2026-10-10. The user asked for the research and a finished design, to review before anything is built. Claude
made the decisions below; the questions still open for the user are at the end.

## Goal

Friends install Tomte from the release page and get 28 modules switched on at once. Three small features make that
nicer:

1. **First-run picker.** On a friend's first login with Tomte, a themed window asks what they want: Collector,
   Crafter, Minimal or Everything, or "Choose myself". Reachable later with `/tomte setup`.
2. **Bug report.** `/tomte bug` opens a box with everything the user needs to fix a bug (versions, character, which
   modules are on, relevant addons, Tomte's last Lua errors), selected and ready for Ctrl+C. Nothing is sent
   anywhere.
3. **Settings profiles.** Export your Tomte settings as a string; import a friend's string with a preview of what
   changes, a confirm and an undo.

Success: a friend installs Tomte, picks "Crafter" and gets only the crafting modules; when something breaks they type
`/tomte bug` and paste the box to the user; the user sends a settings string and the friend's Tomte looks the same.

## Research summary

### APIs verified

Checked on 2026-10-10 against warcraft.wiki.gg and Blizzard's UI source (Gethe/wow-ui-source, `live`, which is
12.1.0.69933):

| API | Where checked | Finding |
|---|---|---|
| `C_EncodingUtil.SerializeCBOR(value [, options])` → `string` | wiki `API_C_EncodingUtil.SerializeCBOR`; `Blizzard_APIDocumentationGenerated/EncodingUtilDocumentation.lua` | Added in 11.1.5 (wiki `Patch_11.1.5/API_changes`). Option `ignoreSerializationErrors`. Errors on functions/userdata/threads, recursive tables, depth > 100. `SecretArguments = AllowedWhenUntainted`. |
| `C_EncodingUtil.DeserializeCBOR(source)` → `value?` | same | Subset of CBOR, no tags, no indefinite lengths, depth ≤ 100. Behavior on malformed input is not documented, so Tomte calls it in `pcall`. Returns only data (tables, strings, numbers, booleans): it cannot carry code. |
| `C_EncodingUtil.CompressString(source [, method [, level]])` / `DecompressString(source [, method])` | same | `Enum.CompressionMethod` Deflate 0 / Zlib 1 / Gzip 2. `MayReturnNothing = true`: nil on bad input. Tomte uses Deflate. |
| `C_EncodingUtil.EncodeBase64(source [, variant])` / `DecodeBase64(source [, variant])` | same | `Enum.Base64Variant` Standard 0 / StandardUrlSafe 1. `MayReturnNothing = true`. |
| `seterrorhandler` / `geterrorhandler` | wiki `API_seterrorhandler`; `Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua` | Still exist. Blizzard sets its own `HandleLuaError` and lets others hook in only through `AddLuaErrorHandler`, which asserts `issecure()`: addons can't use it. BugGrabber replaces `seterrorhandler` with a no-op once it loads. |
| `ScriptErrorsFrame.errorData` | `Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.lua` + `.toc` | Loaded for everyone (`DefaultState: enabled`). Registers itself with `AddLuaErrorHandler` and keeps every error of the session in `self.errorData` = `{ count, message, messageType, time, stack, locals }`, even when the `scriptErrors` CVar hides the window. Not filled when BugGrabber is installed (BugGrabber takes the handler). Messages can be secret when thrown from tainted code with secrets. |
| `C_AddOns.GetAddOnInfo(name|index)` | wiki | Returns `name, title, notes, loadable, reason, security`; `updateAvailable` was removed in 11.2.5. `C_AddOns.GetNumAddOns`, `IsAddOnLoaded` and `GetAddOnMetadata(name, "Version")` are already used by Tomte. |
| `C_SpecializationInfo.GetSpecialization()` | wiki | Index of the current spec (11.2.0+). Tomte already uses it with `GetSpecializationInfo`. |
| `GetBuildInfo()` | wiki | `version, build, date, interfaceVersion, localizedVersion, buildInfo`. |
| `C_UI.Reload()` | already used by Tomte's Reset buttons | Needs a hardware event: called from a button click only. |

### BugGrabber (read, not copied)

The installed `!BugGrabber` (v12.1.0, All Rights Reserved, so no code is taken) exposes a read-only global
`BugGrabber` with:

- `BugGrabber:GetDB()`: the list of error objects, oldest first, kept across sessions (up to 500). Each is
  `{ message, stack, locals, time, counter, session }`.
- `BugGrabber:GetSessionId()`: the current session number.
- `EventRegistry` event `"BugGrabber.BugGrabbed"` (not needed here).
- Blocked protected calls are stored as messages like `[ADDON_ACTION_BLOCKED] AddOn 'Tomte' tried to call the
  protected function 'X'.` (this text is localized in BugGrabber).
- BugSack shortens paths for display; the raw message starts with the file path, for example
  `Interface/AddOns/Tomte/Core/Core.lua:12: attempt to index ...`. Long paths can be shortened by Lua to
  `...<end of path>` (the chunk name limit), so "Tomte/" isn't always in the text.

### Encoding: C_EncodingUtil, not a hand-written serializer

- The native functions exist in 12.1, are documented, and need no parser code in Tomte. A hand-written parser is
  where an import bug or a crash on bad input would live.
- Deflate + Base64 makes the string short enough for a Discord or whisper paste.
- The cost: the unit tests can't run C_EncodingUtil. So the encoding sits in a thin adapter with a `codec`
  argument; tests pass a fake codec and check everything around it, and a hidden `/tomte profile selftest` runs a
  real round trip in game.

## 1. First-run picker

### Who sees it

- **New install** (no `TomteDB` when Tomte loads): `TomteDB.setup.state = "pending"`. The picker shows after login.
- **Existing users** (updating from 1.4.x): they never see the picker by surprise. Their modules are already set the
  way they chose, and a window offering to switch modules off would be a trap. Settings migration 2 marks them
  `state = "done"` and sets a one-time `note`: at their next login one chat line says
  "Tomte 1.5: new `/tomte setup` (presets), `/tomte bug` (bug report) and settings sharing in Tomte window settings."
  The changelog says the same.
- Detection: `Core.lua` remembers `TomteDB == nil` before anything else runs. Migrations also run on a fresh install
  (on the empty table), so migration 2 only touches a db whose `setup.state` isn't set yet.

### When it shows

- At `PLAYER_ENTERING_WORLD`, 3 seconds after loading in, while `state == "pending"`.
- Not in combat: it waits for `PLAYER_REGEN_ENABLED`. Not over a cinematic: it waits while `ns.AnyCinematicState()`
  is set (checked again every few seconds).
- A `/reload` before choosing shows it again. Esc or the close button counts as "Skip": defaults stay, state becomes
  `done`, and chat says "Change it any time with /tomte setup."
- `/tomte setup` opens it any time (out of combat), with the current state shown on each preset ("matches your
  setup now" when it does).

### The window

- A standalone frame with `UI.Panel`, DIALOG strata, centered, movable, Esc closes it. Theme roles only.
- Title "Welcome to Tomte", one line: "Pick what you want. You can change every module later."
- Four preset cards in a 2×2 grid. Each card: name, one line of what it's for, and "Turns on:" with the module names
  (muted, small, wrapping). Click selects (accent border).
- Buttons: **Use this** (applies the selected preset), **Choose myself** (keeps the defaults, marks done, opens the
  Tomte window on its settings list), **Skip**.
- Footnote: "Hunter Pets, Pet Health and Rogue Poisons only wake up on that class."
- Applying calls `ns.SetModuleEnabled(key, on)` for every module that has a choice. Modules start and stop at once;
  no reload needed. Settings inside modules don't change. A toast or chat line confirms: "Tomte: Crafter set up –
  11 modules on. /tomte setup to change."

### Presets

From the real module keys (28 registered; `window` is always on). "Base" is in every preset: it's cheap and
never noisy, and the class modules only run for their class.

| Preset | For | On (besides base) |
|---|---|---|
| Base (all presets) | | `minimap`, `vendor`, `dura`, `hunter`, `pet`, `rogue` |
| **Minimal** | "Just the helpers, nothing pops up." | `way`, `mount`, `tp`, `gear` |
| **Collector** | "Mounts, pets, achievements and the places to get them." | `way`, `mount`, `tp`, `flight`, `collect`, `ach`, `pets`, `wq`, `moments`, `next`, `recent` |
| **Crafter** | "Professions, alts and gold." | `way`, `mount`, `tp`, `gear`, `alts`, `value`, `weekly`, `next`, `recent` |
| **Everything** | "All of Tomte, as it comes." | every module (each module's `enabledByDefault`) |

Modules not in a preset are switched off: `afk`, `recap`, `moments` (except Collector), `whispers`, `mentions`,
`friends`, `alerts`, `flight` (except Collector) and so on. "Everything" clears `db.enabled`, so every module
follows its default again.

- A module added in a later Tomte version isn't in any preset list, so it follows its own `enabledByDefault`. See
  open question 2.
- `TomteDB.setup.preset` remembers the last preset applied (for the "matches" mark and the bug report).
- A test checks that every preset key is a registered module key, so a renamed module breaks the test, not the
  picker.

## 2. Bug report (`/tomte bug`)

### What's in the box

Plain text, English, one block, newest information first. No character name, realm, BattleTag or gold: the text
may end up in a public GitHub issue.

```
Tomte bug report
Tomte 1.5.0 | WoW 12.1.0.69933 (120100) | enUS | theme cartographer
Character: level 80 Hunter (Marksmanship, spec 254) | content The War Within
Setup: preset Collector
Modules on (14): pets, minimap, next, ...
Modules off (13): afk, recap, ...
Blocked (2): rogue (not a Rogue), ach (AlmostCompletedAchievements is enabled)
Uses: Baganator 1.2.3, Syndicator 1.2.3, Auctionator not loaded, TradeSkillMaster not loaded, ...
Error catcher: BugSack (BugGrabber v12.1.0)
Other addons (31): DBM-Core, Details, ...

Errors from Tomte (newest first, 2 of 2):
1) x3, 2026-10-10 21:14, this session
Interface/AddOns/Tomte/Modules/Alts/Send.lua:212: attempt to index a nil value
<stack, first 12 lines>
```

- **Uses** lists every addon named in any module's `uses` / `conflicts`, plus BugSack/BugGrabber, TomTom and the
  TOC's `OptionalDeps`, with its TOC version or "not loaded".
- **Other addons** is every other loaded non-Blizzard addon by folder name (no versions). It helps spot clashes
  (ElvUI, other map addons) and contains nothing private.
- **Errors:** at most 3, each with count, time, whether it's from this session, message and the first 12 stack
  lines. Locals are left out by default (they can hold whisper text and names); `/tomte bug full` adds them, plus the
  settings string from part 3. The hint says to read it before posting.

### Where the errors come from

In this order; the first source that exists is used, then deduplicated by message:

1. **BugGrabber loaded** (`BugGrabber` global with `GetDB`): its list, filtered to Tomte, newest first. It keeps errors
   across sessions, so nothing else is needed.
2. **No BugGrabber:** `ScriptErrorsFrame.errorData` (this session) plus `TomteDB.bugs` (earlier sessions, below).
3. Neither: "No error list available. Install BugSack to catch errors." The report still has everything else.

Every field read from these lists is checked with `issecretvalue` (and `type(...) == "string"`) before any string
operation. A secret message is reported as "(hidden by the game: secret value)".

### Which errors are Tomte's

`ns.Bug_IsTomte(message, stack)` is true when:

- the message or stack contains `AddOns/Tomte/` (either slash), or
- a path at the start of the message, or of a stack line, was shortened to `...<tail>` and `<tail>` is the end of one
  of Tomte's own files, or
- the message is a blocked call naming `'Tomte'` (`AddOn 'Tomte'`; BugGrabber's localized text keeps the quotes and
  the name).

Tomte's file list (`ns.BUG_FILES`, in `Core/BugFiles.lua`) is generated from the TOC; a test fails when the TOC lists
a Lua file that isn't in it, with the line to add. An error whose message points elsewhere but whose stack goes
through Tomte (a hook, a tooltip) counts too, marked "(Tomte in the stack)".

### Ring buffer: yes, small, only without BugGrabber

`ScriptErrorsFrame.errorData` lives only until the next reload, and friends often report a bug the day after. So at
`PLAYER_LOGOUT` (which also fires on `/reload`), when BugGrabber isn't loaded, Tomte copies its own errors from
`ScriptErrorsFrame.errorData` into `TomteDB.bugs`: at most 5, newest first, deduplicated by message (counts added),
message cut to 500 characters, stack to 12 lines, no locals, with the Tomte version. With BugGrabber nothing is
saved; it already keeps them. `/tomte bug clear` empties the list. It is never exported and never reset.

### Not chosen

- **Our own `seterrorhandler` wrapper** (chaining to the previous handler): it would put Tomte's tainted code in the
  path of every Lua error in the UI, including Blizzard's secure code, which is exactly what Midnight's secret-value
  rules punish. BugGrabber also turns `seterrorhandler` into a no-op, so it wouldn't work for the users who have it.
- **`AddLuaErrorHandler`:** asserts `issecure()`, not for addons.
- **Sending the report** anywhere (mail, chat, addon message): never. The user copies it.

## 3. Settings profiles

### What counts as a setting

The same line "Reset settings" already draws (`Core/Modules.lua`), so export, import and reset agree:

- Per module: every value under `module.defaults`, reached through tables that aren't collections, except the keys
  in `module.keep`. That leaves out everything Tomte collected or the user built: `alts.chars`, `alts.recipes`,
  `alts.list`, `recap.history`, `whispers.store`, `hunter.seen`, `hunter.chars`, `flight.routes/hops/paces/stats/
  calibration`, `weekly.chars/quests`, `pets.teams/learned/levelQueue`, `gear.weights/hinted`, `ach.cache/pins/
  ignored`, `mount.zones`, `tp.favorites`, `recent.entries/seenAt` and so on.
- `keep` keys are personal text: `alts.sendRules` (your alts' names), `friends.watch` (people), `mentions.keywords`
  (often your name). Not shared, which is right.
- Also left out, as state of one screen or one character rather than taste:
  - any table with a `point` key (a frame's position: `flight.frame`, `pet.frame`, `rogue.frame`);
  - any key named `collapsed` or `view` at any depth (which tab or section was open);
  - `module.noShare` paths: `alts.filterChar`, `alts.filterFor` (character GUIDs), `gear.sheetOpen`,
    `moments.previewKind`.
- Plus `module.shareMaps` for settings that live in a map with an empty default: Next up's `sources` (boolean) and
  `priority` (number). Keys must match `^[%w_%-]+$`.
- Core: which modules are on (`ns.ModuleEnabled` for every module that isn't `alwaysOn`). Not `panel`, `toast`,
  `cinematic`, `schema`, `setup`, `bugs` or the session.
- The theme is part of the `window` module's defaults, so it travels.

`ns.Profile_Schema(module)` turns this into a flat map `path → type` with `.` between levels (`tracker.scale` →
"number"). A test checks that no default key anywhere contains a `.`.

### The string

```
Tomte1:<Base64(Deflate(CBOR(payload)))>
payload = { v = 1, from = "1.5.0", enabled = { [key] = bool }, settings = { [moduleKey] = { [path] = value } } }
```

- The prefix tells Tomte strings from WeakAuras and others ("That's not a Tomte settings string.") and carries the
  format version.
- Export writes every shareable value, not only the changed ones, so importing makes you match the friend. The
  preview only lists what differs from yours.
- Nothing about the character or account is in it.

### Import: defensive by design

Steps, each with a plain error message:

1. Trim spaces and line breaks; refuse over 20,000 characters ("too long to be a Tomte string").
2. Check the `Tomte<n>:` prefix. `n` higher than 1: "Made by a newer Tomte. Update first."
3. `DecodeBase64` → `DecompressString` (nil = "damaged string, copy it again"); refuse a result over 256 KB.
4. `pcall(DeserializeCBOR)`; the result must be a table with `v == 1`.
5. Validate against the current schema (`ns.Profile_Check`, pure):
   - unknown module keys and unknown paths are skipped and counted ("3 settings this Tomte doesn't know");
   - the value's type must equal the schema type;
   - numbers must be finite (no NaN or infinity); a slider option clamps them to its `min`/`max`;
   - a dropdown option's value must be one of its `choices` (function choices are called, in `pcall`);
   - strings at most 200 characters and no `|` (no UI escape codes);
   - `enabled` entries must be booleans for registered, not-always-on modules;
   - at most 2,000 entries are read; the rest are ignored.
6. Never `loadstring`, never a function call on imported data. The data only ever becomes a value written at a
   path that exists in the defaults.

### Preview, confirm, undo

- **Export** (Tomte window settings, or `/tomte profile export`): the shared copy dialog with the string selected,
  hint "Ctrl+C, then paste it to a friend. It has your settings, not your data."
- **Import** (button, or `/tomte profile import`): the shared dialog in edit mode with a **Check** button. Check runs
  steps 1–5 and opens the preview:
  - grouped by module, a checkbox per group (all ticked), rows "Label: yours → theirs" (label from the option's
    `label` when the path is an option key, the path otherwise); "Modules on/off" is its own group;
  - a summary: "18 changes in 6 modules. 3 settings skipped.";
  - nothing to change: "Your settings already match.";
  - **Import and reload** applies the ticked groups and reloads the UI (the click is the hardware event; the theme
    and modules' closures need the reload, as with Reset). Blocked in combat.
- **Undo:** before applying, Tomte saves an export of your current settings in `TomteDB.profileBackup` (one, with the
  time). "Undo last import" (button when a backup exists) imports it through the same path.

## Where it lives

| File | Contents |
|---|---|
| `Core/Setup.lua` | Pure: presets, `ns.Setup_Presets()`, `ns.Setup_Plan(presetKey, modules)`, `ns.Setup_Matches(...)`. |
| `Core/Profile.lua` | Pure: schema, collect, check, apply, encode/decode with an injected codec. |
| `Core/BugReport.lua` | Pure: `ns.Bug_IsTomte`, error normalizing, merging, ring buffer, report text from a plain info table. |
| `Core/BugFiles.lua` | Data: Tomte's Lua files (from the TOC), checked by a test. |
| `Panel/Dialog.lua` | The shared text dialog, moved out of `Modules/Pets/Card.lua` (`ns.Dialog_Show(spec)`); Pets uses it. |
| `Panel/Setup.lua` | The picker window. |
| `Panel/Share.lua` | Export, import, preview, undo; the `C_EncodingUtil` codec. |
| `Panel/Bug.lua` | Reads the game state for the report and the error sources; `PLAYER_LOGOUT` ring buffer. |
| `Core/Core.lua` | Fresh-install flag, migration 2, `setup`/`bugs`/`profileBackup` core defaults, the note, slash commands. |
| `Panel/Window.lua` | A "Setup and sharing" header with buttons: Run setup again, Export settings, Import settings, Undo last import, Bug report. |

## Settings

No new options. The new core keys:

```
setup = { state = nil | "pending" | "done", preset = nil | key, note = nil | true }
bugs = {}               -- ring buffer, at most 5 (only filled without BugGrabber)
profileBackup = nil | { at = time, text = "Tomte1:..." }
```

`ResetAllSettings` keeps all three (it only rebuilds `enabled`, `panel`, `toast`).

## Commands

- `/tomte setup`: the picker.
- `/tomte bug`, `/tomte bug full` (adds locals and the settings string), `/tomte bug clear`; hidden
  `/tomte bug selftest` (raises a Lua error from a Tomte file, to test the catching).
- `/tomte profile export`, `/tomte profile import`, `/tomte profile undo`; hidden `/tomte profile selftest` (a real
  round trip of your own settings, prints ok or the failing step).
- All listed in `/tomte help`.

## Error handling

- Every pure function returns `nil, reason` instead of raising; the UI shows the reason.
- The picker never applies in combat (`InCombatLockdown()`), and neither does import.
- The bug report never fails as a whole: each part is built in `pcall`; a failing part becomes "(could not read:
  <err>)".

## Testing

- **Unit tests** (plain Lua 5.1):
  - `tests/test_setup.lua`: preset keys exist, plan per preset (on/off/cleared), Everything clears, matching,
    class modules in every preset.
  - `tests/test_profile.lua`: schema rules (collections, keep, `point`, `collapsed`/`view`, `noShare`, `shareMaps`,
    no dots), collect, check (types, unknown keys, NaN, clamps, choices, `|`, long strings, `v`, entry cap), apply,
    round trip with a fake codec, prefix errors.
  - `tests/test_bugreport.lua`: `Bug_IsTomte` (full paths, backslashes, `...` tails, blocked calls, other addons,
    `TomteFoo/` not matching), merge and dedupe, ring buffer cap, report text, BugFiles matches the TOC.
- **In game** (user):
  - delete `TomteDB` (or a fresh WoW account folder) → picker shows; pick Crafter; Recap and Moments are off;
  - `/reload` as an existing user → no picker, one chat line once;
  - `/tomte bug` with BugSack and an error caused on purpose (`/tomte bug selftest` throws a Tomte error from a Tomte
    file, hidden command) → the error is in the box;
  - export, change a setting, import the string → preview shows that one change, reload, value back; Undo;
  - `/tomte profile selftest` prints ok.

## Out of scope / Later

- Sharing collected data with friends (crafting, flight times): the separate "Friend sharing" idea in
  `future-ideas.md`.
- Per-character profiles or several saved profiles. One backup only.
- Achievements' category and expansion filters (`ach.categories`, `ach.expansions`) are keyed by localized names, so
  they'd mismatch between client languages. Not shared for now.
- A "what's new" window for updates.

## Open questions for the user

1. **Existing users:** one chat line once after updating (decided above), or nothing at all, or the picker once?
2. **New modules later:** after a preset, a module added in a later version follows its own default (usually on).
   Fine, or should presets remember "off unless listed"?
3. **Preset contents:** are the four lists right? In particular: Social modules (Whispers, Mentions, Friends,
   Alerts) are only in Everything, and Minimal has no Moments or AFK screen.
4. **"Other addons" in the bug report:** the full list of loaded addon names, or only the ones Tomte knows about?
5. **Ring buffer** of 5 Tomte errors in `TomteDB` for friends without BugSack: keep it, or tell them to install
   BugSack?

## User decisions (2026-10-10)

- Existing users get nothing: no picker, no chat line. The migration only marks them as done.
- The rest of the open questions: Claude decides (the user delegated the build).
