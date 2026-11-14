# Send Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send your Tomte settings to one player in a couple of clicks, by character (addon whisper) or to a Battle.net
friend (Friend sharing), with the receiver always seeing the existing import preview first.

**Architecture:** A pure wire file (`Core/ProfileWire.lua`) builds, parses and reassembles the messages of one
transfer. A game file (`Panel/ShareSend.lua`) runs both ends of a transfer over two routes: route A on
`C_ChatInfo.SendAddonMessage` WHISPER (prefix `TomteProfile`), route B through Friend sharing as a message-only set
`profile`. The receiver's preview is the one in `Panel/Share.lua`, opened from text.

**Tech Stack:** WoW Lua 5.1, Tomte's `ns` services, plain-Lua tests (`tests/harness.lua`).

**Spec:** `docs/superpowers/specs/2026-11-14-tomte-send-settings-design.md`

## Global Constraints

- The payload is exactly `ns.ShareUI_ExportText()`; nothing changes on the receiver before they click Import.
- Hidden everywhere when `ns.ShareUI_Available()` is false (no `C_EncodingUtil`).
- Route A: at most 255 bytes per message, prefix at most 16 characters; same or connected realms only.
- Route B: text of a Share `M` message at most `ns.SHARE_CHUNK` (2000) bytes, starting `<id>;`, no `^`.
- At most one offer prompt per sender per 10 minutes (`ASK_GAP = 600`); stale transfers dropped after 60 s.
- Receiving is not a module: it works with every module off. Setting `window.receiveSettings` (default `true`).
- Colors and fonts by theme role only; player wording in every line; CRLF; Edit/Write tools only.

## Review Focus

- Receiver in combat when the offer comes: the question waits for `PLAYER_REGEN_ENABLED`, then asks once.
- A second offer while one is open (other sender, or the same one again): answered `busy`, no second dialog.
- Chunks arriving out of order, duplicated, or a transfer that never finishes: reassembly copes, stale entry dropped
  (test in Task 1).
- Oversized or malformed data from someone else (n too large, total over `ns.PROFILE_MAX_TEXT`, bad numbers):
  rejected without error (test in Task 1).
- Sending to yourself, or a name with a realm suffix vs without: no self-send; replies go to the sender's full
  `Name-Realm`.

---

### Task 1: Wire format (pure)

**Files:**
- Create: `Core/ProfileWire.lua` (TOC: right after `Core/Profile.lua`)
- Test: `tests/test_profile_wire.lua`

**Interfaces:**
- Produces:
  - `ns.ProfileWire_Offer(tid, size) -> string` — `1:O:<tid>:<size>`
  - `ns.ProfileWire_Accept(tid) -> string` — `1:A:<tid>`
  - `ns.ProfileWire_No(tid, reason) -> string` — `1:N:<tid>:<reason>`, reason one of `declined`, `busy`, `off`
  - `ns.ProfileWire_Result(tid, outcome) -> string` — `1:R:<tid>:<outcome>`, outcome one of `shown`, `same`,
    `cancelled`, `bad`
  - `ns.ProfileWire_Data(tid, text, size) -> { string }` — `1:D:<tid>:<i>:<n>:<chunk>`; each whole message at
    most `size` bytes
  - `ns.ProfileWire_Parse(msg) -> { kind, tid, size?, reason?, outcome?, i?, n?, chunk? } | nil` — kinds `O A N R D`;
    nil for another version, unknown kind, bad numbers, `n` over `ns.PROFILEWIRE_MAX_CHUNKS`
  - `ns.ProfileWire_NewInbox() -> inbox`;
    `ns.ProfileWire_Add(inbox, key, part, now) -> text | nil, err` — part from Parse (kind D); returns the joined
    text once all n chunks are in; err `"too long"` when the joined length passes `ns.PROFILE_MAX_TEXT` (inbox entry
    dropped); entries older than `ns.PROFILEWIRE_STALE` (60) seconds are dropped on every Add
  - `ns.ProfileWire_MayAsk(lastAskedAt, now) -> bool` — true when lastAskedAt is nil or `now - lastAskedAt >= 600`
  - Constants: `ns.PROFILEWIRE_PREFIX = "TomteProfile"`, `ns.PROFILEWIRE_WHISPER = 255`,
    `ns.PROFILEWIRE_BNET = 1900`, `ns.PROFILEWIRE_MAX_CHUNKS = 200`, `ns.PROFILEWIRE_STALE = 60`

- [ ] **Step 1: Write `tests/test_profile_wire.lua`** loading `Core/Profile.lua` then `Core/ProfileWire.lua`, tests:
  - round trip of each builder through Parse (`Parse(Offer("ab12", 5000))` gives `kind "O", tid "ab12", size 5000`)
  - `Data("t", s, 255)` for a 3000-byte `s` (with `:` in it, like `Tomte1:abc`): every message `#m <= 255`,
    reassembled in reverse order equals `s`; duplicates don't break it
  - single short text gives one message; empty text gives one message with an empty chunk that reassembles to `""`
  - Parse rejects `2:O:x:1`, `1:Z:x`, `1:D:t:0:3:x`, `1:D:t:4:3:x`, `1:D:t:1:999:x`, `1:O:x:abc`, nil
  - Add: chunk at now=0, Add of another key at now=61 drops the first (completing it later yields nil)
  - Add returns nil, "too long" when n * chunk passes `ns.PROFILE_MAX_TEXT`
  - MayAsk(nil, 5) true; MayAsk(0, 599) false; MayAsk(0, 600) true
- [ ] **Step 2:** `lua Tomte/tests/test_profile_wire.lua` fails (file missing).
- [ ] **Step 3:** Implement `Core/ProfileWire.lua` (pure header comment; fields split on the first 5 `:` for D so
  the chunk keeps its own `:`).
- [ ] **Step 4:** Test passes.

### Task 2: Preview from text, and Friend sharing message-only sets

**Files:**
- Modify: `Panel/Share.lua` (ShowPreview gets an onClose; new export)
- Modify: `Modules/Share/Share.lua` (`messageOnly` sets)

**Interfaces:**
- Produces: `ns.ShareUI_PreviewText(text, title, onClose) -> true | nil, err` — runs `Check(text)`; on success opens
  the preview with that title; `onClose(imported)` runs once when the preview hides (`imported` true when Import
  was clicked, set before `C_UI.Reload`). err is Check's text (`"Your settings already match."` and others).
- Produces: `ns.Share_Register` accepts `messageOnly = true`: such a set needs only `key`, `label`, `message`,
  `refused`, optional `active`; `Shared(key)` is true for it without a `db.sets` entry; it is left out of hellos
  (`SharedSets`), never served by `OnRequest` and never imported.
- [ ] **Step 1:** Implement both; keep the paste import path unchanged (it passes no onClose).
- [ ] **Step 2:** All tests green.

### Task 3: Sending and receiving (`Panel/ShareSend.lua`)

**Files:**
- Create: `Panel/ShareSend.lua` (TOC: right after `Panel/Share.lua`)
- Modify: `Panel/Window.lua` (SHARE rows, default `receiveSettings = true`)
- Modify: `Core/Core.lua` (`/tomte profile send <name>` and its help line)
- Modify: `Modules/Share/Page.lua` (a "Send settings" button per friend row)

**Interfaces:**
- Consumes: Task 1 and Task 2 functions; `ns.Share_Send(tag, key, text)`, `ns.Share_Online(tag)`,
  `ns.Share_Register` (looked up at call time: Modules load after Panel); `ns.Confirm_Show`, `ns.Dialog_Show`,
  `ns.Print`, `ns.Print_Combat`.
- Produces: `ns.ShareSend_ToPlayer(name)` (route A), `ns.ShareSend_ToFriend(tag)` (route B),
  `ns.ShareSend_Ask()` (name box, prefilled with your target's full name when it's another player).

Behavior (the spec's "How it works"), with these fixed values:

- `tid`: 6 random base-36 characters. One outgoing transfer at a time ("Already sending your settings to Mira.").
- Sender waits `ANSWER_WAIT = 120` s for accept/no, then `DATA_WAIT = 60` s for the result; on timeout:
  "No answer from Mira: they may be offline, not run Tomte, or run an older Tomte."
- Route A pacing: one message every 0.1 s, throttle/lockdown/offline handled like `Modules/QuestList/Party.lua`
  (`TargetOffline` ends the transfer: "Mira is offline.").
- Route B: each wire message goes as `ns.Share_Send(tag, "profile", tid .. ";" .. wire)`; false ends the transfer
  ("Mira can't be reached through Friend sharing right now."); `refused` ends it ("Mira's Tomte doesn't take
  settings yet: they need to update.").
- Receiver: `CHAT_MSG_ADDON` filtered on the prefix and `WHISPER` (sender `Name-Realm`, shown with
  `Ambiguate(sender, "short")`); route B through the set's `message(tag, text)` (shown as the BattleTag's short name).
  Offer → No `off` when `receiveSettings` is false or sharing isn't available; No `busy` while another transfer is
  asked or open; No `declined` when MayAsk is false; in combat held until `PLAYER_REGEN_ENABLED`; otherwise
  `ns.Confirm_Show("<name> wants to send you their Tomte settings.\n\nYou'll see what changes before anything is
  imported.", accept, { yes = "See changes", no = "No thanks", noEnter = true, onNo = decline })`.
  Data complete → `ns.ShareUI_PreviewText(text, "<name>'s settings", onClose)`; answers R `shown` (or `same` /
  `bad` on err), then `cancelled` on close without import.
- Sender lines: "Sending your settings to Mira...", "Mira is looking at what changes.", "Mira already has these
  settings.", "Mira closed it without importing.", "Mira said no thanks.", "Mira is busy with another offer, try
  again in a moment.", "Mira doesn't take settings from players.".
- Right-click menus: `Menu.ModifyMenu` once at `PLAYER_LOGIN` on `MENU_UNIT_` + `PLAYER`, `PARTY`, `RAID_PLAYER`,
  `FRIEND`, `GUILD`, `CHAT_ROSTER`, `COMMUNITIES_WOW_MEMBER`, `COMMUNITIES_GUILD_MEMBER`, `BN_FRIEND`; entry
  "Send my Tomte settings" after a divider; skipped for yourself, without a name, or when unavailable.
  `BN_FRIEND`: route B when `ns.Share_Online(accountInfo.battleTag)`, else route A to
  `gameAccountInfo.characterName-realmName` when they're in WoW, else no entry.
- Window SHARE rows after "Use a friend's settings": button "Send your settings to a player" / "Send"
  (`ns.ShareSend_Ask`), checkbox `receiveSettings` "Let players send me their settings" (tooltip: "Someone can
  offer you their Tomte settings. You're asked first, and see what changes before anything is imported.").
- [ ] **Step 1:** Implement; TOC lines; `lua Tomte/tools/forevertoc.lua`; `lua Tomte/tools/bugfiles.lua`.
- [ ] **Step 2:** All tests green; `luac -l` global check on the new files.

### Task 4: Docs

- [ ] README: Sharing settings line and `/tomte profile send <name>` under Commands.
- [ ] CHANGELOG line only after the user confirms in game.
