# Tomte: Chat

Date: 2026-10-11. Designed with the user in conversation; the user then asked Claude to write the spec, plan and
build it without check-ins. Decisions the user made are marked (user); the rest are Claude's.

## Goal

Trade chat stops burying the rest of the chat window without leaving the channel: only messages that ask for
something you can do get through (user). Around that, the user wanted the module "fully featured" with a setting for
each part: an ignore list for sellers, a separate tab for the busy channels and shorter channel tags (user).

Success: in a capital, Tomten's main chat window shows "LF BS for crafting order" in Trade but none of the boosting
and WTS ads; the Trade tab shows everything; channel tags read `[2. T]` (or whatever style was picked).

## Research summary (wow-ui-source live, build 12.1.0)

- **Message filters still exist:** `ChatFrameUtil.AddMessageEventFilter(event, fn)` /
  `ChatFrameUtil.RemoveMessageEventFilter` (`Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua`). The callback gets
  `(chatFrame, event, ...)`; returning `true` discards the message, returning `false, ...newArgs` replaces the
  arguments. It runs once per chat frame that receives the event. During chat lockdown (instances, encounters, M+,
  PvP) the arguments are secret and Blizzard skips addon filters entirely: everything shows unfiltered.
- **Channel arguments:** `CHAT_MSG_CHANNEL` arg4 `channelName` ("2. Trade - City"), arg7 `zoneChannelID`,
  arg8 `channelIndex`, arg9 `channelBaseName`, arg11 `lineID`, arg12 `guid`. Zone channel IDs from the ChatChannels
  DB2 (wago.tools): General 1, Trade 2, LocalDefense 22, LookingForGroup 26, Trade (Services) 42.
  `C_ChatInfo.GetChannelShortcutForChannelID(id)` gives the localized shortcut a chat window subscribes with.
  `C_ChatInfo.GetChannelInfoFromIdentifier(localIndex)` returns `{ name, shortcut, localID, instanceID,
  zoneChannelID, channelType }`.
- **arg4 can't be rewritten by a filter:** the chat frame matches the message to its subscribed channels with
  `strlen(arg4) > strlen(channelName)` and `ResolvePrefixedChannelName(arg4)` requires a `"N. "` prefix. A shortened
  arg4 drops the message. So channel tags are shortened on the formatted line instead (below).
- **`AddMessage` can be wrapped:** each chat frame has `ChatFrameMixin:AddMessage`, which calls
  `ScrollingMessageFrameSecureMixin.AddMessage`; the secure mixin runs "as-if untainted" when called from addon code,
  so a wrapper that passes a secret line straight through keeps working during lockdown. The formatted line holds
  every tag as a link: `|Hchannel:channel:2|h[2. Trade - City]|h` for numbered channels and
  `|Hchannel:GUILD|h[Guild]|h` (from the `CHAT_GUILD_GET` family of globals) for guild, officer, party, raid and
  instance. Raid warnings have no link: `[Raid Warning] `. The localized bracket text is read from those `_GET`
  globals at runtime; they are never overwritten (that would taint Blizzard's formatter).
- **Chat windows:** `FCF_OpenNewWindow(name, noDefaultChannels)` returns the frame (nil when all 10 windows are in
  use); `frame:AddChannel(shortcut)`, `frame:RemoveChannel(shortcut)`, `frame.channelList`, `FCF_SetWindowName`,
  `FCF_Close(frame)`, `GetChatWindowInfo(i)` (name first, shown 7th). Window setup is saved by the game per character
  and outlives the addon.
- **Professions:** `GetProfessions()` → indices; `GetProfessionInfo(index)` → localized `name` (1st) and `skillLine`
  (7th, the base TradeSkillLine ID). `SKILL_LINES_CHANGED` fires when they change.

## Structure

A new **Chat** category with three modules, each with its own enable toggle and options page. All three are off by
default: each changes how chat looks in a way someone who didn't choose it would find surprising.

| File | Contents |
|---|---|
| `Modules/Chat/Data.lua` | Pure logic, unit-tested: abbreviation table, keyword building, match + ignore decision, link-safe highlight, tag formatting, custom label parsing. |
| `Modules/Chat/Filter.lua` | Module `tradefilter` ("Trade Filter"). |
| `Modules/Chat/Tabs.lua` | Module `chattabs` ("Chat Tabs"). |
| `Modules/Chat/Tags.lua` | Module `chattags` ("Channel Tags"). |
| `tests/test_chat.lua` | Tests for Data.lua. |

Loaded after `Modules/Social/*` (Data.lua reuses `ns.Social_ParseWords`, `ns.Social_PlainText`; Filter uses the
toast). Channel choices shared by Filter and Tabs live in Data.lua: `trade` 2, `services` 42, `general` 1,
`lfg` 26, `defense` 22.

## Module 1: Trade Filter

Hides messages in the chosen channels unless they contain a keyword (user).

**Keywords**
- *From professions* (user): for each of the character's two primary professions, the localized profession name plus
  fixed abbreviations by skill line (user asked for these):

  | skillLine | Profession | Abbreviations |
  |---|---|---|
  | 164 | Blacksmithing | bs, smith, blacksmith |
  | 165 | Leatherworking | lw, leatherworker |
  | 197 | Tailoring | tailor |
  | 755 | Jewelcrafting | jc, jewelcrafter |
  | 333 | Enchanting | ench, enchanter, chanter |
  | 171 | Alchemy | alch, alchy, alchemist |
  | 202 | Engineering | engi, engineer |
  | 773 | Inscription | scribe, insc |
  | 186 | Mining | miner, ore |
  | 182 | Herbalism | herb, herbs, herbalist |
  | 393 | Skinning | skinner |

  Rebuilt on activation and `SKILL_LINES_CHANGED`. Checkbox "Profession keywords", on.
- *Your own keywords:* comma-separated input, account-wide, kept through a settings reset (`keep`). Empty by default.
- Matching: `ns.Social_FindMention` rules (whole words, case-insensitive, link text included, color codes ignored).

**Ignore list:** a message that matches a keyword is still hidden when it also contains one of these words. Input,
default `WTS, selling, boost, carry`, kept through a reset; checkbox "Use the ignore list", on.

**Channels:** checkboxes Trade (on), Services (on), General (off), LookingForGroup (off). Identified by arg7
(zoneChannelID), so client language doesn't matter.

**Where:** dropdown "Filter in": "Every chat window" / "Every window except the Trade tab" (default: except the
Trade tab; with the Chat Tabs module off there is no Trade tab, so it filters everywhere).

**Shown messages:** the matched words get the theme's accent color, never inside a hyperlink (a color code inside
`|H...|h` breaks the link). Checkbox "Highlight matched words", on. The player's own messages always show,
unchanged.

**Toast (user):** checkbox "Toast on match", off. A Mentions-style card ("Trade - Thrall", the message), at most one
per sender per 5 minutes; click whispers the sender. Uses the shared toast rows (`ns.Toast_Options`) and digest.

**Pause:** checkbox "Pause the filter" (everything shows, nothing toasts), off.

**Counters:** `/tomte tradefilter stats` prints hidden/shown counts this session. A message counts once even though
the filter runs once per chat frame: dedupe by lineID (also used for the toast).

## Module 2: Chat Tabs

Moves busy channels into their own chat tab (user).

- **Tab name:** input, default "Trade". Renaming renames the window.
- **Channels:** checkboxes Trade (on), Services (on), General, LookingForGroup, LocalDefense (off).
- **Main window:** dropdown "In the main window": "Keep them (filtered by Trade Filter)" (default) / "Remove them".
- **Restore:** button "Restore my chat" (with confirm): closes the tab and puts back every channel Tomte removed from
  the main window. Turning the module off does the same.

Behaviour:
- Applied at `PLAYER_ENTERING_WORLD` (first time) and on every relevant setting change; deferred to
  `PLAYER_REGEN_ENABLED` in combat.
- Finding the tab: the window saved for this character (`db.windows[name-realm] = { index, name, created,
  added = { [zoneID] = name }, removed = { [zoneID] = name } }`): one Tomte opened is trusted by index even after a
  rename in Blizzard's menu, a borrowed one only while it keeps its name. Otherwise an open window with the tab's name
  is borrowed; otherwise `FCF_OpenNewWindow(name, true)` (`created`). No free window → a printed message.
- Syncing: chosen channels are added to the tab (recorded in `added`); unticked ones are removed only from a window
  Tomte created or channels Tomte added. With "Remove them", the main window (`DEFAULT_CHAT_FRAME`) unsubscribes from
  the chosen channels it had, recorded in `removed` under their saved name; with "Keep them" or a channel unticked,
  they go back. Channels are found by `frame.zoneChannelList` (as Blizzard does), name as fallback.
- Restore: closes the window only if Tomte created it, else removes only `added`; re-adds `removed`; works in combat
  (chat windows aren't protected). The button keeps the tab away until the module is turned on again or next login.
- `ns.ChatTabs_Frame()` returns the tab's chat frame while the module is active (used by Trade Filter's "except the
  Trade tab").

## Module 3: Channel Tags

Shortens the `[...]` tag in front of chat lines (user).

- **Style** dropdown for numbered channels:
  - `full` `[2. Trade - City]` (no change)
  - `name` `[2. Trade]` (default)
  - `numshort` `[2. T]`
  - `short` `[T]`
  - `number` `[2]`
- Short names by zone channel: General `Gen`, Trade `T`, Services `S`, LocalDefense `LD`, LookingForGroup `LFG`;
  other channels (custom, community) use their name without the zone part.
- **Custom labels:** input like `Trade=T, Services=Srv, Guild=Gu` overriding the short name, matched
  case-insensitively against the channel's shortcut or base name (or the guild/group tag text). In the `name` style a
  custom label replaces the name too.
- **Guild and group:** checkbox "Shorten guild, party and raid tags", on: Guild `G`, Officer `O`, Party `P`, Party
  Leader `PL`, Raid `R`, Raid Leader `RL`, Raid Warning `RW`, Instance `I`, Instance Leader `IL`.
- Implementation: `hooksecurefunc(frame, "AddMessage", ...)` on `ChatFrame1..MaxChatWindows` once (first
  activation); the post-hook rewrites the entry just stored with `frame:TransformMessages` (a secure barrier
  Blizzard offers addons), only for readable lines and only while the module is active. Replacing `frame.AddMessage`
  was rejected in review: it taints the rest of Blizzard's chat handler, which compares secret whisper senders.
- **Limit:** during chat lockdown (instances, encounters, M+, PvP) every line is secret and tags show in full; the
  checkbox tooltip says so.

## Testing

- `tests/test_chat.lua` (plain Lua): keyword building from professions + abbreviations, match/ignore decision,
  highlight outside links only, tag formatting for each style, custom labels, group tags, raid warning.
- In game (user): checklist in the final report.

## Out of scope

Chat history across reloads, URL copying, class-colored names (Blizzard has the option), per-character keyword lists.
