# Tomte

A World of Warcraft addon used by the user and a few friends. Shared through GitHub releases from a **public** repo
(tomte55/Tomte). English only, no CurseForge packaging.

## Environment

- Client: retail **12.1.0** (Midnight), build 69933. TOC `## Interface: 120100`.
- This repo **is** the live addon folder `Interface\AddOns\Tomte`; the repo root is the addon root.
- Every other folder in `Interface\AddOns` (DBM, Auctionator, Baganator, etc.) is a third-party CurseForge addon
  outside this repo. Never modify them. Reading them for reference is fine; never paste their code in (see Sharing).
- The user has BugSack + BugGrabber installed for Lua errors.

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

## Midnight (12.x) restrictions to keep in mind

- **Secret values**: many combat-related values are opaque to addons during tainted execution. Don't build
  logic that depends on combat info.
- `COMBAT_LOG_EVENT_UNFILTERED` cannot be registered by addons anymore.
- `C_RestrictedActions` can query whether addon restrictions are active.
- **Hardware events**: many actions (for example `C_AuctionHouse.PostCommodity`/`PostItem` and buying) require a
  real keyboard or mouse event and can't be called from `/run`. Automation means "one click/keypress per
  action" (button or keybind), never a fully automatic loop. Design around this from the start.
- Protected functions and frames can't be touched in combat (`InCombatLockdown()`).

## Conventions

- Lua files listed in `Tomte.toc`. Use XML only when templates really need it.
- TOC basics: `Interface`, `Title`, `Notes`, `Author`, `Version`, `IconTexture`/`IconAtlas`,
  `SavedVariables`, and `AddonCompartmentFunc` if it has a minimap/compartment entry.
- Use the addon namespace: `local addonName, ns = ...`. No globals except SavedVariables and anything the TOC
  needs to reference (e.g. the compartment function).
- Initialize SavedVariables on `ADDON_LOADED` (check `addonName`) and merge defaults so new keys appear.
- Use one event frame per addon that dispatches to handlers (`self[event](self, ...)`).
- Prefer `C_*` namespaced APIs over legacy globals when both exist.
- Slash commands: `/<shortname>`, with a `help` subcommand.
- Settings UI: use the native `Settings` API (`Settings.RegisterVerticalLayoutCategory` etc.) when an addon
  needs options. No Ace3 or other libraries unless clearly worth it.

## Sharing

- Friends may play other classes, specs and client languages. Don't hardcode the user's characters or specs, and
  match game text through Blizzard's localized globals or IDs, not English strings.
- Defaults must be safe for someone who didn't choose them (e.g. nothing spends guild or other shared resources).
- Optional addons (Baganator, Syndicator, Auctionator, TSM, Mount Journal Enhanced) are always checked before use.
- License is GPL-3.0. Game IDs are facts and fine to take from other addons; code, curated lists and layouts are
  not, unless the source's license allows it. Credit any source in a comment and in README's Credits.

## Git and releases

- Commit after each working step the user has confirmed in game, and add a line for it under **Unreleased** in
  `CHANGELOG.md` (player-facing wording).
- Commits use the noreply email set in this repo's git config.
- Release only when the user asks: follow "Releasing" in README.md (changelog section, TOC version, tag, push).
  The workflow in `.github/workflows/release.yml` builds and publishes the zip.
