# Friend sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battle.net friends running Tomte pool and relay their recorded flight times over hidden Battle.net game data.

**Architecture:** A new module `share` (`Modules/Share/`) owns the transport (pure wire format and reassembly in
`Protocol.lua`, friend roster in `Roster.lua`, sending/receiving/events in `Share.lua`) and a Friends page
(`Page.lua`). Data sets plug in through `ns.Share_Register`; the Flight module registers the first one, with its pure
export/import/revision in `Modules/Flight/ShareData.lua`.

**Tech Stack:** WoW 12.1 Lua (5.1), `C_BattleNet.SendGameData` / `BN_CHAT_MSG_ADDON`, plain-Lua unit tests.

**Spec:** `docs/superpowers/specs/2026-10-13-tomte-friend-sharing-design.md`

## Global Constraints

- Prefix `Tomte`, registered with `C_ChatInfo.RegisterAddonMessagePrefix`; protocol version `1`, first field.
- Field separator `^` (not `|`, WoW's escape character; deviation from the spec's notation, recorded there).
- Chunk 2000 bytes, one message per 1 s (ChatThrottleLib holds Battle.net data to 255 B "for traffic
  fairness"; the hard limit is 4078 B). Throttle/lockdown results retry later; `TargetOffline` drops that friend's
  queue. Nothing sent in combat.
- Import rules: seconds 1–3600, route 2–30 nodes, hop exactly 2, node IDs positive integers, at most 20000 entries,
  any bad entry rejects the payload. Fill gaps only.
- Module `share`, "Friend sharing", category Social, off by default; `toast = false` by default.
- CRLF files, tabs, double quotes, header comments as in CLAUDE.md; Edit/Write tools only.

## Review Focus

- A friend online on a Classic client or another region: never treated as a peer (roster filters by client and
  project; messages from IDs not on the roster are dropped).
- Out-of-order or duplicated chunks, or a transfer that never completes: reassembly by index, duplicates ignored,
  stale partials dropped (protocol test).
- Own legacy data with odd keys: export only writes entries that pass the import rules, so a friend never rejects
  our whole payload (flight share test).
- Two installs keep re-requesting each other forever: revision is over keys only and import fills gaps only, so
  one exchange each way converges (flight share test "converge").
- Module turned off mid-transfer: Stop cancels the queue, timers and partials; hooks/registrations check
  `module.active`.

---

### Task 1: Wire format (`Modules/Share/Protocol.lua`)

**Files:** Create `Modules/Share/Protocol.lua`, `tests/test_share_protocol.lua`.

**Interfaces (produces):**
- `ns.Share_BuildHello(version, sets) -> text` — `sets` = array of `{ key, rev }`.
- `ns.Share_BuildRequest(key) -> text`
- `ns.Share_BuildData(key, rev, payload) -> { text, ... }` (at least one message, also for an empty payload)
- `ns.Share_Parse(text) -> msg | nil, reason` — `msg.type` "H" (`version`, `sets` = `{ [key] = rev }`),
  "R" (`set`), "D" (`set`, `rev`, `index`, `count`, `chunk`).
- `ns.Share_Receive(inbox, from, msg, now) -> payload | nil` (inbox = plain table), `ns.Share_Prune(inbox, now)`.

- [ ] Write the tests (round trips; wrong version/type/garbage rejected; chunks ≤ 2000 B payload; out-of-order
  and duplicate reassembly; newer rev restarts; stale partial dropped; count cap).
- [ ] Run `lua Tomte/tests/test_share_protocol.lua`: fails (file missing).
- [ ] Implement `Protocol.lua` (code as built in the repo).
- [ ] Run the test: passes.

### Task 2: Flight data set (`Modules/Flight/ShareData.lua`)

**Files:** Create `Modules/Flight/ShareData.lua`, `tests/test_flight_share.lua`.

**Interfaces (produces):**
- `ns.FlightShare_Export(db) -> payload` — `h<a>><b>=<s>;` and `r<id>>...=<s>;`, sorted, valid entries only.
- `ns.FlightShare_Revision(db) -> number` — djb2 (mod 2^31) of the sorted valid keys.
- `ns.FlightShare_Import(db, payload) -> added | nil, reason`

- [ ] Tests: deterministic export; round trip; fill gaps only; each rejection rule; invalid own entries left
  out of export and revision; revision equal for same keys/different seconds; converge in one exchange each way;
  relay A→B→C.
- [ ] Run: fails. Implement. Run: passes.

### Task 3: Roster, transport and module (`Roster.lua`, `Share.lua`)

**Files:** Create `Modules/Share/Roster.lua`, `Modules/Share/Share.lua`.

**Interfaces:**
- Roster produces `ns.Share_RosterGet(gameAccountID) -> { tag, character } | nil`, `ns.Share_RosterIDs() -> { id, ... }`,
  `ns.Share_RosterDirty()`.
- Share produces `ns.Share_Register(set)`, `ns.Share_Changed(key)`, `ns.Share_Friends() -> sorted rows`,
  `ns.Share_SetBlocked(tag, on)`, `ns.Share_Forget(tag)`, `ns.Share_Sync()`.
- Set fields: `key`, `label`, `count(n) -> "34 flight times"`, `export()`, `revision()`, `import(payload)`.

- [ ] Roster: walk `BNGetNumFriends` / `C_BattleNet.GetFriendAccountInfo` / `GetFriendNumGameAccounts` /
  `GetFriendGameAccountInfo`; keep online `BNET_CLIENT_WOW` accounts of this project; lazy rebuild when dirty.
- [ ] Share: queue with 1 s pacing and result handling, hello/request/data handlers, 60 s hello reply window,
  debounced `Share_Changed` (10 s), start hello after 5 s, friend-online hello after 2 s, combat pause, log of
  last 20 lines per friend, toast (off by default), commands `list`, `sync`, `why`, options, `noShare = { "friends" }`.
- [ ] `luac -l` global check on both files.

### Task 4: Friends page (`Modules/Share/Page.lua`)

**Files:** Create `Modules/Share/Page.lua`; home entry in `Share.lua`.

- [ ] Rows: short BattleTag name (heading), muted line "Character · Tomte x · synced 2d ago · gave you 34 flight
  times", Block checkbox, Forget button; empty state text. Refresh on show and after any received message.

### Task 5: Flight hooks, TOC, docs

**Files:** Modify `Modules/Flight/Flight.lua` (register set in `init`, `Share_Changed` after a recorded flight
and in `ResetTimes`), `Tomte.toc`, `.gitattributes` (nothing new outside tests/tools/docs), `README.md`,
`CHANGELOG.md` (only after the user confirms in game), run `lua Tomte/tools/bugfiles.lua`.

- [ ] TOC: `Modules/Flight/ShareData.lua` after `Modules/Flight/Data.lua`; `Modules/Share/Protocol.lua`,
  `Roster.lua`, `Page.lua`, `Share.lua` at the end.
- [ ] README module row, commands, layout; spec "as built" notes (separator, chunk size, pacing).
- [ ] All tests green: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`.
- [ ] No commit of the feature before the user's in-game check (project rule); the plan doc may be committed.
