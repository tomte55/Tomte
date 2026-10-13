# Tomte

A World of Warcraft addon used by the user and a few friends. Shared through GitHub releases from a **public** repo
(tomte55/Tomte). English only, no CurseForge packaging.

## Environment

- Client: retail **12.1.0** (Midnight), build 69933. TOC `## Interface: 120100`.
- This repo **is** the live addon folder `Interface\AddOns\Tomte`; the repo root is the addon root.
- The git dir lives at `D:\git\Tomte.git` (`.git` here is a one-line `gitdir:` file). It was moved out of the WoW
  folder because Battle.net's updater tries to clear read-only flags on every file there and fails on git's
  read-only objects ("We tried to make a file writable but failed"). Never put a `.git` folder back under
  `D:\World of Warcraft`.
- Every other folder in `Interface\AddOns` (DBM, Auctionator, Baganator, etc.) is a third-party CurseForge addon
  outside this repo. Never modify them. Reading them for reference is fine; never paste their code in (see Sharing).
- The user has BugSack + BugGrabber installed for Lua errors.
- Files use CRLF line endings. Edit Lua with the Edit/Write tools only: sed, awk and heredocs here drop the CR and
  collapse double backslashes (texture paths).

## Working with the user

- The user knows Lua. Deliver working code without explaining Lua basics.
- Discuss features and ideas before building. The user decides scope.
- Claude can't run WoW. Testing is: user does `/reload` in game, then reports behavior or pastes the BugSack error
  (full stack trace + locals). When asking the user to test, say exactly what to do and what to look for.
- Debug output: use `/dump`, `/etrace` (event trace), `/fstack` (frame stack), `/tinspect`. Tell the user which one is useful.

## API documentation: verify, don't assume

- **Check warcraft.wiki.gg before using any API** (`https://warcraft.wiki.gg/wiki/API_<Name>`, e.g.
  `API_C_AuctionHouse.PostCommodity`; events at `https://warcraft.wiki.gg/wiki/<EVENT_NAME>`).
  Training data and old addon code are often outdated, especially after 12.0.0.
- Patch notes: `https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes` (and later patches).
- Blizzard's own UI source is the ground truth for how APIs are used: https://github.com/Gethe/wow-ui-source (live branch).
- No deprecated globals: use the `C_*` API (`C_SpellBook.IsSpellKnown`, not `IsPlayerSpell`;
  `C_SpecializationInfo.GetSpecialization`, not `GetSpecialization`; `ns.Coins`, not `GetCoinTextureString`).
  Nothing may error with `/console loadDeprecationFallbacks 0`.

## Midnight (12.x) restrictions to keep in mind

- **Secret values**: many combat-related values are opaque to addons during tainted execution. Don't build
  logic that depends on combat info. Test values with `ns.IsSecret(...)` before comparing or doing math on them.
- `COMBAT_LOG_EVENT_UNFILTERED` cannot be registered by addons anymore.
- `C_RestrictedActions` can query whether addon restrictions are active.
- **Hardware events**: many actions (for example `C_AuctionHouse.PostCommodity`/`PostItem` and buying) require a
  real keyboard or mouse event and can't be called from `/run`. Automation means "one click/keypress per
  action" (button or keybind), never a fully automatic loop. Design around this from the start.
- Protected functions and frames can't be touched in combat (`InCombatLockdown()`). Create secure frames out of
  combat (lazily, on first need), hide them on `PLAYER_REGEN_DISABLED`.
- Don't "simplify" secure buttons, `InCombatLockdown()` guards, taint workarounds, secret-value checks or `C_Timer`
  deferrals that have a comment giving the reason. They were measured in game.

## Code structure

The codebase was brought to one shape in the 2026-10-11 health pass. New code follows the same shape, so the
codebase doesn't need another full pass. When in doubt, copy the nearest existing module (`Modules/Rogue` is a
small complete one: pure rules, UI, events, Edit Mode, options, commands, key binding, test).

### Layout and load order

```
Core/       registry, events, formatting, migrations, saved variables, /tomte, shared services (load first)
Themes/     one file per theme (right after Core/Theme.lua)
Data/       hand-kept data per expansion (Data/WarWithin/, Data/Midnight/, Data/Older/), via ns.Content_Register
Cinematic/  the cinematic engine, SceneKit, banners
Panel/      the Tomte window, settings rendering, widgets, Home
Modules/    one folder per module group; each folder may hold several modules (Social, Chat)
tests/      plain-Lua unit tests of the pure files
tools/      dev scripts (Python, Lua) that generate data, art and Core/BugFiles.lua
docs/       dated design specs and plans (docs/superpowers/specs, docs/superpowers/plans)
```

The TOC is the load order. Inside a module folder the order is fixed: **pure files first** (`Data.lua`, then other
pure files), then readers/collectors, then UI files, then **the module's main file last** (the one that calls
`ns.RegisterModule`). A file may only capture `ns.X` at file load if `ns.X` comes from a file earlier in the TOC;
otherwise look it up at call time.

### File roles and names

| Name | Role |
| --- | --- |
| `Data.lua`, `*Data.lua`, `Model.lua`, `Rules.lua` | Pure logic: no WoW API, no frames, unit-tested. Constants, rules, sorting, text building. |
| `<Module>.lua` (e.g. `Rogue.lua`) | Main file: wires events, owns `db`, registers the module (defaults, options, commands, home entries). |
| `Collect.lua`, `Scan.lua`, `Read.lua`, `Detect.lua`, `Track.lua` | Read the game into plain tables for the pure files and the UI. |
| `Page.lua`, `*Page.lua` | A page in the Tomte window (a `home` entry of kind `page`). |
| `Tab.lua`, `*Tab.lua`, `MapTab.lua` | A tab on a page, or a world map side-panel tab (`ns.MapTabs_Add`). |
| `HomeSection.lua` | A Home section (`home` entry of kind `section`). |
| `Scene.lua` | A cinematic scene (Cinematic/Engine.lua). |
| `Tooltip.lua`, `Card.lua`, `Menu.lua`, `Dock.lua` ... | One UI piece each, named for what the player sees. |

- Split by responsibility. When a file grows past about 900 lines, split it before adding more, as a pure move
  (verbatim blocks, `local` captures at the top of the new file, new `ns.*` exports only where needed), in its own
  commit, before the behavior change.
- Generated files (`Modules/Travel/Network*.lua`, `Modules/Holidays/Generated.lua`, `Core/BugFiles.lua`, theme art)
  are never edited by hand: change the tool in `tools/` and regenerate.

### Every Lua file

1. First line: `local addonName, ns = ...`.
2. Then a header comment: `-- <Feature>: what this file holds` and, where useful, where the rest lives
   ("Pure rules in Data.lua", "registered in Flight.lua"). Pure files say so: `-- <Feature>: pure logic (no WoW
   API calls; unit-tested in tests/test_<name>.lua).`
3. Then file-level constants in `UPPER_CASE` with a comment for any number that isn't obvious (units, why that value),
   then `local UI = ns.UI` and local captures of `ns.*` helpers and APIs.
4. Long files use section rulers: `-- Buttons -----...` padded to the 120-column line.

Style: tabs for indentation, lines wrapped at about 120 columns (long player-facing strings may run over), double
quotes, `local function` for everything private.
Comments say why or what a value means, in plain English; no commented-out code, no TODOs left in, no comment that
just restates the code. Fix comments that point at moved or renamed code in the same change.

### Names and globals

- Only globals: `TomteDB` (SavedVariables), `Tomte_OnAddonCompartmentClick`, frame names that `Bindings.xml`,
  `CLICK` bindings or `UISpecialFrames` need (prefix `Tomte`), and `BINDING_NAME_*` strings. Everything else is
  `local` or on `ns`.
- Cross-file functions: `ns.<Prefix>_<Name>` where the prefix is the module or service (`ns.Rogue_PoisonProblems`,
  `ns.Recent_Note`, `ns.Toast_Show`, `ns.Content_Get`). Cross-file constants: `ns.<PREFIX>_<NAME>`
  (`ns.ROGUE_LETHAL`). Unprefixed `ns.Name` is reserved for Core-wide helpers (`ns.Print`, `ns.Gold`, `ns.IsSecret`).
- Before writing a helper, look for an existing one (below). If two modules need the same thing, move it into Core,
  Panel or SceneKit instead of copying it.

### Shared pieces to reuse (don't reimplement)

- **Module registry** (`Core/Modules.lua`): `ns.RegisterModule`, home entries (kinds `page`, `map`, `quick`, `around`,
  `section`, `next`; documented above `ns.HomeCall`), `ns.HomeCall` for calling into other modules safely.
- **Events** (`Core/Events.lua`): `ns.NewEvents()` bus, owners, `Watch`/`Unwatch`/`TryWatch`.
- **Formatting** (`Core/Format.lua`): `ns.Thousands`, `ns.Gold`, `ns.Price`, `ns.SignedGold`, `ns.Coins`, `ns.Ago`,
  `ns.Clock`. Never format money or counts by hand.
- **Core** (`Core/Core.lua`): `ns.Print`, `ns.IsSecret`, `ns.Readable`, `ns.Smoothstep`, `ns.WeekStart`,
  `ns.SafeTrack`, `ns.TrackPin`.
- **Content per expansion** (`Core/Content.lua`): `ns.ContentExpansion`, `ns.Content_Get`, `ns.Content_AddCheck`.
  Expansion-specific IDs go in `Data/<Expansion>/` through `ns.Content_Register`, never hardcoded in a module; a
  character follows its own expansion.
- **Services**: `ns.Check_Report` / `ns.Check_OnEnterWorld` (readiness checks), `ns.EditMode_Register` (any movable
  on-screen widget), `ns.Journal_Scan` (budgeted mount/pet journal reads), `ns.Session_Note` (session recap),
  `ns.Toast_Show` / `ns.Banner_Show` (both feed Recent automatically), `ns.Dialog_Show`, `ns.MapTabs_Add`,
  `ns.ModelPreview_*`, `ns.Entry_Link` / `ns.Entry_Open` / `ns.Entry_Model`.
- **UI** (`Panel/Widgets.lua`, `ns.UI`): `UI.Text`, `UI.Panel`, `UI.Surface`, `UI.Border`, `UI.Button`,
  `UI.Checkbox`, `UI.Slider`, `UI.Dropdown`, `UI.Scroll`, `UI.Dialog`, `UI.Hairline`, `UI.TipLine`, `UI.Debounce`,
  `UI.ClassColored`; `UI.Switch` and `UI.Segmented` in `Panel/Controls.lua`. Cinematic text and layout:
  `Cinematic/SceneKit.lua`.

### Events

- One event frame per module. A module spread over several files creates one `ns.NewEvents()` bus in its first file
  that needs it and exports it as `ns.<Module>_Events`; each file is an owner, attaches handlers once at file load
  (`events:On(owner, EVENT, fn)`) and watches/unwatches from its Start/Stop. A single-file module may keep a plain
  local frame with method dispatch (`function events:EVENT(...)`), as `Modules/Rogue/Rogue.lua` does.
- Register events only while the module is active: `toggle(true)` starts, `toggle(false)` stops and undoes
  everything (events, tickers, hooks' effects, shown frames, CVars it changed). A module must be fully off when
  disabled, and turning it on again mid-session must work.
- `hooksecurefunc` can't be undone: a hook must do nothing while its module is off (check `module.active`, or a
  flag the module's Stop clears).
- No `OnUpdate` running while nothing is shown; prefer events, then `C_Timer`, then a ticker that's cancelled on stop.

### Saved variables

- One table, `TomteDB`; each module gets `TomteDB[module.key]` as `db` through `init`. Never read another module's
  db directly: ask it through an `ns.<Prefix>_*` function.
- Every saved key has a default in `module.defaults` (merged on load) with a comment for any non-obvious shape
  (`chars = {}, -- [player GUID] = { ... }`). Per-character data is keyed by GUID.
- Keys are never renamed, removed or reshaped except by a new migration appended to `ns.MIGRATIONS`
  (`Core/Migrations.lua`): only add to the end, cope with missing tables, add a case in `tests/test_migrations.lua`.
- `module.keep` lists collected data whose default isn't a collection (kept by Reset); `module.noShare` and
  `module.shareMaps` decide what a profile export carries (`Core/Profile.lua`).

### Settings and commands

- Settings are a module's `options` schema, rendered by `Panel/Options.lua` as cards (each `header` starts one,
  dealt into two columns on a wide window). Row types: `header`, `checkbox` (drawn as a switch),
  `slider` (`min`, `max`, `step`, `format`), `dropdown` (segmented buttons when ≤ 3 short choices),
  `button` (`text`, `onClick`, optional `confirm`), `input`. `key` is a dotted path into the module's db
  (`"check.onEnter"`), `onChange` applies it live, `shown()` hides a row, `parent = "<checkbox key>"` indents and
  dims a row while that checkbox is off, `tooltip` explains anything not obvious. No settings UI built by hand.
- Each module names its settings group in `category`: `tomte`, `week`, `gear`, `professions`, `collections`,
  `travel`, `social`, `ambience` or `class` (`ns.PANEL_GROUPS` in `Panel/Layout.lua`), and has an `icon` (a file ID
  checked to exist) and a one-sentence `summary` for the top of its settings page.
- Labels and tooltips are player wording: short, sentence case, no internals.
- Defaults are safe for a friend who didn't choose them; noisy or invasive modules are `enabledByDefault = false`.
- Commands: `commands = { { "name", "help text", fn(arg, rawArg) } }`, reached as `/tomte <key> <name>` and listed by
  `/tomte help` automatically. Debug commands that explain a decision (`why`, `scan`, `list`) are welcome.
- Key bindings: a `<Binding>` in `Bindings.xml` (category `Tomte`) plus its `BINDING_NAME_*` string.

### UI and theme

- Colors and fonts come from the theme by role (`Core/Theme.lua`, `ns.UI.Color("accent")`,
  `UI.Text(parent, size, "textMuted", "number")`, `UI.Wrap(text, role)` for inline color, `UI.Panel(frame)` for any
  standalone frame). Never a numeric color, a `|cff` literal or a font path elsewhere, and never read theme colors
  at file load (a theme switch must reach them): `tests/test_theme.lua` scans for all of this.
- Color roles: `bg`, `bgTop`, `bgBottom`, `surface`, `hover`, `text`, `heading`, `textMuted`, `textFaint`, `accent`,
  `accentDeep`, `frame`, `frameDark`, `rule`, `contour`, `success`, `warning`, `danger`. Font roles: title, label
  (small UI labels, defaults to title), body, number, chat.
- Each theme is one file in `Themes/` calling `ns.Theme.Register` (fields documented there); its art and fonts are
  generated by `tools/theme_art.py` (Cartographer) or `tools/themes/<key>.py`. New `.ttf`/`.tga` files need a full
  client restart, not just `/reload`.
- Settings live in Tomte's own window (`Panel/`). The game's Settings panel only has a canvas category
  (`Settings.RegisterCanvasLayoutCategory` in `Panel/Panel.lua`) with a button that opens the Tomte window.
- Hook Blizzard frames rather than replacing them, and never move or hide them in a way that outlives the module.
  Cinematics never lock controls: any key or click ends them.
- No Ace3 or other libraries unless clearly worth it.

### Errors

- Module code is called through `xpcall` with `ns.errorHandler` (BugSack shows it). Don't swallow errors with a bare
  `pcall` around our own code; `pcall` is for calls that can legitimately fail (an API missing on this client or
  erroring on odd input, another addon's API), and the failure is handled.
- Optional addons (the TOC's OptionalDeps) are always checked before use (`C_AddOns.IsAddOnLoaded`), and listed in
  the module's `uses` / `conflicts` so its settings page says so.

## Tests

- Every pure file has a test file `tests/test_<name>.lua` that loads it with `loadfile(...)("Tomte", ns)` and uses
  `tests/harness.lua` (`test`, `eq`, `near`, `H.done()`). New rules and every bug fixed in pure logic get a test.
- Push logic out of UI and event files into the pure file whenever it can be tested without the game.
- Run all tests from the `AddOns` folder before saying something is done:
  `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done` (CI uses Lua 5.1).
- After any TOC change: `lua Tomte/tools/bugfiles.lua` (else `test_bugreport` fails).
- After a split or a new file: `luac -l <file> | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` must list only WoW API and Lua
  globals, never a name that should have been a local or `ns.*`.
- Everything else is tested in game by the user (see "Working with the user").

## Checklists

**New module**
1. Discuss scope with the user; for anything bigger than a small module, write a dated spec in
   `docs/superpowers/specs/`.
2. Folder `Modules/<Name>/` with a pure `Data.lua`, UI/reader files, and a main `<Name>.lua` that registers the
   module (`key`, `name`, `category`, `icon`, `summary`, `description`, `enabledByDefault`, `defaults`, `init`,
   `toggle`, `options`,
   and as needed `commands`, `home`, `blocked`, `uses`, `minimapButton`, `keep`).
3. TOC lines in load order (see Layout), `OptionalDeps` if it uses a new addon, `lua Tomte/tools/bugfiles.lua`.
4. `tests/test_<name>.lua` for the pure file; all tests green.
5. README: a row in the module table (player wording), its commands under Commands, the folder in Layout, a Credits
   line for any source. CHANGELOG **Unreleased**: "New module, <Name>: ...".

**Changing a module**
- Keep the file roles: rules into the pure file (with a test), UI into the UI file.
- Settings shape changed: migration. New setting: default + options row.
- README row and commands still true? CHANGELOG line once the user confirmed it in game.

**New dev-only file** (tool, doc, test data): add it to `.gitattributes` with `export-ignore` if it's outside
`tests/`, `tools/` and `docs/`.

## Sharing

- Friends may play other classes, specs and client languages. Don't hardcode the user's characters or specs, and
  match game text through Blizzard's localized globals or IDs, not English strings.
- Defaults must be safe for someone who didn't choose them (e.g. nothing spends guild or other shared resources).
- Optional addons (the TOC's OptionalDeps: Baganator, Syndicator, Auctionator, TSM, Mount Journal Enhanced,
  AlmostCompletedAchievements, WaypointUI, DialogueUI) are always checked before use.
- License is GPL-3.0. Game IDs are facts and fine to take from other addons; code, curated lists and layouts are
  not, unless the source's license allows it. Credit any source in a comment and in README's Credits.

## Git and releases

- Repo: https://github.com/tomte55/Tomte (public; renamed from `wow-addons` on 2026-10-08, when the old monorepo
  was rewritten so this folder is the root). Friends download from https://github.com/tomte55/Tomte/releases/latest.
- Start Claude from `Interface\AddOns\Tomte` (this folder), so this file and the project memory load.
- Commit after each working step the user has confirmed in game, and add a line for it under **Unreleased** in
  `CHANGELOG.md` in player-facing wording (what a friend notices, not internals). Pure refactors get no
  CHANGELOG line.
- Commit messages: `<Module>: what changed` in plain words (`Smart Mount: flying mount on the water surface where
  you can fly`). Pure moves and refactors say so (`Split X into A and B (pure moves)`) and never carry a behavior
  change.
- Commits use the GitHub noreply email set in this repo's git config; never the user's personal email. The repo is
  public, so nothing private goes into commits, docs or code comments.
- Versions follow semver: patch for fixes, minor for new features or modules, major for changes that reset or
  break settings.

### Releasing (only when the user asks)

1. In `CHANGELOG.md`, move the **Unreleased** lines into a new `## vX.Y.Z - YYYY-MM-DD` section right below it
   (leave an empty **Unreleased** heading).
2. Set `## Version: X.Y.Z` in `Tomte.toc`.
3. Run the unit tests (see Tests), commit (`Tomte vX.Y.Z`), then `git tag -a vX.Y.Z -m "Tomte vX.Y.Z"`
   and `git push origin main vX.Y.Z`.
4. Watch the run (`gh run list --workflow release.yml`) and check the release has `Tomte-vX.Y.Z.zip`
   (`gh release view vX.Y.Z`). Give the user the release link.

`.github/workflows/release.yml` runs on `v*` tags. It runs the unit tests with Lua 5.1, fails if the tag doesn't
match the TOC version or `CHANGELOG.md` has no `## vX.Y.Z` section, builds the zip with
`git archive --prefix=Tomte/` and publishes the release with that changelog section as its notes.
`.gitattributes` (`export-ignore`) keeps `tests/`, `tools/`, `docs/`, `CLAUDE.md`, `.github/` and `Media/Logo.svg` out of
the zip: add any new dev-only file there. If a run fails, fix it, delete the tag locally and on GitHub
(`git tag -d vX.Y.Z`, `git push origin :refs/tags/vX.Y.Z`) and tag again.
