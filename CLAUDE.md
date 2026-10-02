# WoW Addons Monorepo

Personal World of Warcraft addons. Only the user (plus maybe a friend or two) uses them, so there's no publishing, no localization, and no CurseForge packaging.

## Environment

- Client: retail **12.1.0** (Midnight), build 69933. TOC `## Interface: 120100`.
- This directory is the live `Interface\AddOns` folder. The git repo here is a **monorepo**:
  `.gitignore` ignores everything and whitelists only our own addons. Every new addon folder
  **must be added to the whitelist in `.gitignore`**.
- All other folders (DBM, Auctionator, Baganator, etc.) are third-party CurseForge addons. Never modify them.
  Reading them for reference is fine.
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

- One folder per addon: `<AddonName>/<AddonName>.toc` plus Lua files. Use XML only when templates really need it.
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
- Keep addons small and self-contained. Shared code between our addons isn't needed yet. Don't add it speculatively.

## Git

- Commit after each working step the user has confirmed in game.
- Any remote must be a **private** GitHub repo.
