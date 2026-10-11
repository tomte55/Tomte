# Tomte Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Chat" category with three modules: Trade Filter (keyword allowlist for trade channels), Chat Tabs (busy
channels in their own tab) and Channel Tags (shorter `[...]` tags).

**Architecture:** Pure, unit-tested logic in `Modules/Chat/Data.lua`; one file per module registering with
`ns.RegisterModule`. Trade Filter uses `ChatFrameUtil.AddMessageEventFilter`; Channel Tags wraps each chat frame's
`AddMessage`; Chat Tabs drives Blizzard's FCF window functions.

**Tech Stack:** WoW retail 12.1 Lua, plain Lua 5.1 for tests.

**Spec:** `docs/superpowers/specs/2026-10-11-tomte-chat-design.md`

## Global Constraints

- No numeric colors, `|cff` literals or font paths outside the theme: colors via `ns.UI.Wrap(text, "accent")`.
- No globals; `local addonName, ns = ...`.
- All three modules `enabledByDefault = false`.
- Channels identified by zone channel ID: trade 2, services 42, general 1, lfg 26, defense 22.
- Secret values: anything read from chat events is checked with `canaccessvalue`/`canaccessallvalues` (guarded for
  nil) before use; secret lines pass through untouched.
- No commit before the user confirms in game (project rule); CHANGELOG line under Unreleased is added with the work.

## Review Focus

1. Keyword list empty (no professions, nothing typed) → every message in filtered channels is hidden; the user must be
   told (print on activation, tooltip). Test: `Chat_BuildKeywords({}, true, "")` returns `{}`.
2. Item links in a matching message → highlight never lands inside `|H...|h...|h`. Test: link containing the keyword.
3. A filter runs once per chat frame → counters and toasts must not double. Dedupe by lineID (in Filter.lua; manual).
4. Channel line without `"N. "` prefix or unknown link type → tag left unchanged. Test: unknown target.
5. Chat Tabs adopting the wrong window (index 1/2, or the user's own window with another name) → only indices above
   the reserved windows, name must match exactly. Manual check in game.

---

### Task 1: Data.lua (pure logic) with tests

**Files:**
- Create: `Modules/Chat/Data.lua`
- Test: `tests/test_chat.lua`

**Interfaces (Produces):**
- `ns.CHAT_CHANNELS` = ordered `{ key, id, label, short }`; `ns.CHAT_CHANNEL_BY_ID[id]` = entry.
- `ns.CHAT_PROF_ABBREVIATIONS[skillLine]` = `{ "bs", ... }`.
- `ns.Chat_BuildKeywords(profs, useProfs, extraText)` → lowercase deduped list; `profs` = `{ { name, skillLine } }`.
- `ns.Chat_Decide(text, keywords, ignoreWords)` → `true` (show) / `false` (hide).
- `ns.Chat_Highlight(text, words, wrap)` → text with every whole-word match outside links/escapes passed through
  `wrap(word)`.
- `ns.Chat_ParseLabels(text)` → `{ [lowercase key] = label }` from `"Trade=T, Guild=Gu"`.
- `ns.Chat_ChannelTag(style, number, name, shortcut, zoneID, labels)` → tag text without brackets.
- `ns.Chat_GroupTags(getGlobal)` → `{ [localized tag text] = abbreviation }`, `raidWarningText`.
- `ns.Chat_ShortenLine(line, ctx)` with `ctx = { style, labels, group, groupTags, raidWarning, channelInfo(number) →
  shortcut, zoneID }`.
- Consumes: `ns.Social_ParseWords`, `ns.Social_FindMention`, `ns.Social_PlainText` (Modules/Social/Data.lua).

- [ ] Step 1: write `tests/test_chat.lua` (loads Social/Data.lua then Chat/Data.lua) covering: keywords from
  professions incl. abbreviations and dedupe; useProfs=false; empty input → `{}`; Decide show/hide/ignore; highlight
  plain word, case kept, whole words only, not inside an item link, color codes untouched; ParseLabels; ChannelTag
  for all five styles + custom label + unknown channel; GroupTags from fake globals; ShortenLine for a numbered
  channel, guild tag, group off, raid warning, unknown target, line without tag.
- [ ] Step 2: run `lua Tomte/tests/test_chat.lua` from the AddOns folder → fails (file missing).
- [ ] Step 3: implement Data.lua.
- [ ] Step 4: run → all ok.

### Task 2: Trade Filter module

**Files:** Create `Modules/Chat/Filter.lua`; modify `Tomte.toc` (after `Modules/Social/Alerts.lua`:
`Modules/Chat/Data.lua`, `Modules/Chat/Tabs.lua`, `Modules/Chat/Filter.lua`, `Modules/Chat/Tags.lua`).

**Interfaces:** Consumes Task 1 and `ns.ChatTabs_Frame()` (Task 3, may be nil), `ns.Toast_Show`,
`ns.Toast_Options`, `ns.Toast_SetDigest`, `ns.Toast_Clear`, `ns.Toast_ChatColor`, `ns.Social_Digest`,
`ns.Social_NameList`.

Behaviour per spec "Module 1". Key points:
- defaults `{ profKeywords = true, keywords = "", useIgnore = true, ignore = "WTS, selling, boost, carry",
  channels = { trade = true, services = true, general = false, lfg = false }, where = "exceptTab",
  highlight = true, toast = false, holdInCombat = true, paused = false }`, `keep = { "keywords", "ignore" }`.
- Filter `function(chatFrame, event, text, ...)`: zoneID = `select(6, ...)`, lineID `select(10, ...)`, guid
  `select(11, ...)`; return `true` to hide, `false, newText, ...` to highlight, `false` otherwise.
- Keywords rebuilt on activation, `PLAYER_ENTERING_WORLD`, `SKILL_LINES_CHANGED`, option changes. Print a warning
  once per activation when the list is empty.
- Commands: `stats`, `keywords`.

### Task 3: Chat Tabs module

**Files:** Create `Modules/Chat/Tabs.lua`.

**Produces:** `ns.ChatTabs_Frame()` → chat frame or nil.

Behaviour per spec "Module 2": defaults `{ tabName = "Trade", channels = { trade = true, services = true,
general = false, lfg = false, defense = false }, mainWindow = "keep", windows = {} }`; per-character state in
`windows[name-realm] = { index, removed = {} }`; Apply deferred out of combat; Restore on button and on toggle(false).
Window helpers: `FCF_IsChatWindowIndexActive`, `FCF_GetChatFrameByID`, `GetChatWindowInfo`,
`C_ChatInfo.GetNumReservedChatWindows`, `Constants.ChatFrameConstants.MaxChatWindows`, `FCF_OpenNewWindow(name,
true)`, `FCF_SetWindowName`, `FCF_Close`, `frame:AddChannel/RemoveChannel`, `frame.channelList`.

### Task 4: Channel Tags module

**Files:** Create `Modules/Chat/Tags.lua`.

Behaviour per spec "Module 3": defaults `{ style = "name", labels = "", group = true }`, `keep = { "labels" }`;
wraps `AddMessage` on `ChatFrame1..MaxChatWindows` once; `ctx.channelInfo` from
`C_ChatInfo.GetChannelInfoFromIdentifier(number)`; group tags rebuilt from `_G["CHAT_<X>_GET"]` on activation.

### Task 5: Wiring and docs

- [ ] `lua Tomte/tools/bugfiles.lua` to regenerate `Core/BugFiles.lua`.
- [ ] Run every test: `for t in Tomte/tests/test_*.lua; do lua "$t"; done` → no FAIL.
- [ ] README module list gets the three modules; CHANGELOG Unreleased gets player-facing lines.
- [ ] `luac -p` every new file.
