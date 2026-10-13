# Tomte: Friend sharing (flight times first)

Date: 2026-10-13. Status: design approved in chat, spec waiting for review.
Background: the first talk is in `future-ideas.md` ("Friend sharing (2026-10-10)").

## Goal

Friends who run Tomte pool their recorded flight times, so everyone's countdown bar and Coverage map fill in
faster than one player could manage alone. Friends are trusted: received times merge into your own data and are
passed on to your other friends (relay), so times spread through the whole network of Tomte users.

The transport is built as a backbone with pluggable data sets; flight times are the first and only data set in
this round. Crafting, group check and "Send to friend" stay in `future-ideas.md`.

## Decisions (from the talk)

| Question | Decision |
|---|---|
| First data set | Flight times (`hops` and `routes` of the Flight module) |
| Who | Battle.net friends online in retail WoW running Tomte. No guild, party or character-friend channel |
| Consent | New module, off by default. When on, shares with every such friend; a per-friend Block switch |
| Trust | Received times fill gaps in your own data; you relay everything you know |
| Your own times | Always win: flying a route records over whatever was there (`ns.RecordFlight` already does) |
| Toasts | "Flight times from Kalle: 34 new legs", off by default |
| Removing bad data | Flight's existing "Reset recorded flight times" clears everything; no per-friend undo (merged data can't be split again) |

## Module

- Key `share`, name "Friend sharing", category Social, `enabledByDefault = false`. (Key `friends` is taken by
  Friends Online in `Modules/Social/Friends.lua`.)
- Folder `Modules/Share/`, TOC order: `Protocol.lua` (pure), `Roster.lua`, `Page.lua`, `Share.lua` (main).
- The flight data set lives with Flight: `Modules/Flight/ShareData.lua` (pure export/import/merge/revision,
  unit-tested) and a few lines in `Flight.lua` that register it and announce changes.

### Data set interface

Registered by the owning module through `ns.Share_Register(set)`:

```lua
{
	key = "flight",            -- short, used on the wire
	label = "Flight times",    -- settings and page wording
	export = function() end,   -- -> payload string (everything you know, received data included)
	revision = function() end, -- -> number: hash of what export would send (see Revision)
	import = function(payload) end, -- -> added count, or nil + reason when the payload is invalid
}
```

`Modules/Share/` loads after `Modules/Flight/`, so Flight looks Share up at call time: its `init` calls
`ns.Share_Register` (all files are loaded by then), and after its data changes (a landing recorded a time, Reset)
it calls `ns.Share_Changed("flight")`. Both are defined by `Share.lua` at file load and do nothing while the
module is off, so Flight works the same with Friend sharing off.

## Protocol (`Modules/Share/Protocol.lua`, pure)

- Prefix `Tomte`, registered with `C_ChatInfo.RegisterAddonMessagePrefix` on module start. Sent with
  `C_BattleNet.SendGameData(gameAccountID, "Tomte", text)`, received on `BN_CHAT_MSG_ADDON`
  (`prefix, text, channel, senderID`, senderID = the sender's gameAccountID).
- Text messages, fields split by `|`, first field the protocol version (`1`). Unknown version, unknown type or a
  sender who isn't a current online Battle.net friend: dropped silently.

| Type | Fields | Meaning |
|---|---|---|
| `H` hello | `1\|H\|<tomte version>\|<set>=<rev>,<set>=<rev>` | What I have. A set I've switched off is left out |
| `R` request | `1\|R\|<set>` | Send me that set |
| `D` data | `1\|D\|<set>\|<rev>\|<i>\|<n>\|<chunk>` | Chunk i of n of the set's payload at that revision |

- Chunks: payload split into pieces so a whole message stays under 4078 bytes (the documented limit for
  Battle.net game data); chunk size 3800. Delivery order isn't guaranteed, so the receiver reassembles by index and
  imports once all n are there. A partial reassembly is dropped when a newer revision starts or after 60 s.
- Pacing: an outgoing queue sends at most one message every 0.5 s. A throttle result
  (`Enum.SendAddonMessageResult.AddonMessageThrottle` / `ChannelThrottle`) puts the message back and waits 2 s;
  `TargetOffline` drops everything queued for that friend; `AddOnMessageLockdown` waits and retries; other
  errors drop the message. Nothing is sent in combat: the queue pauses on `PLAYER_REGEN_DISABLED` and resumes on
  `PLAYER_REGEN_ENABLED`.
- The pure file holds: build/parse of each message type, chunking and reassembly, the hello set list. The
  sending, timers and events are in `Share.lua`.

## Flow

1. **Hello** to every online friend (see Roster) when: the module starts (after login, once the friend list
   is in), a friend comes online (`BN_FRIEND_ACCOUNT_ONLINE`, after a 2 s delay because the game info fills in
   later, as Friends Online learned), `/tomte share sync`, or `ns.Share_Changed` (debounced 10 s, so several
   updates send one hello).
2. **On a hello:** remember the friend's version and sets. For each set both sides share whose revision differs
   from mine, send `R`. If this is the first hello from this friend this session and I haven't sent them one,
   send a hello back (one reply per friend per session: no ping-pong).
3. **On a request:** queue the set's chunks to that friend (one transfer per friend and set at a time; a
   repeated request while it's queued is ignored).
4. **On complete data:** `set.import(payload)`. If it added anything: count it on the friend's row, toast if
   enabled, and `ns.Share_Changed` (so the new data reaches my other friends by my next hello).

It stops by itself: import only adds missing keys, so an exchange that brings nothing new changes no revision
and triggers no new hello.

## Roster (`Modules/Share/Roster.lua`)

- Walks `BNGetNumFriends()` / `C_BattleNet.GetFriendAccountInfo(i)` and every game account of each friend
  (`C_BattleNet.GetFriendNumGameAccounts`, `GetFriendGameAccountInfo`), keeping online accounts with
  `clientProgram == BNET_CLIENT_WOW` and `wowProjectID == WOW_PROJECT_ID`. Rebuilt on `BN_FRIEND_INFO_CHANGED`
  and `BN_FRIEND_ACCOUNT_ONLINE/OFFLINE`, read when a message arrives.
- Maps the session-only `gameAccountID` to the friend's **BattleTag**; everything saved is keyed by BattleTag.
- A message from a gameAccountID not on the current roster is dropped. Blocked friends get nothing and nothing
  from them is used.
- Your own other game accounts (multiboxing) don't appear in your Battle.net friend list, so they're never peers.

## Flight data set (`Modules/Flight/ShareData.lua`, pure)

- **Payload:** `h:<a>><b>=<s>;...` for hops and `r:<id>>...><id>=<s>;...` for routes, sorted by key
  (deterministic). Example: `h1234>5678=42;r1234>5678>9012=97;`.
- **Import:** parse everything first; the whole payload is rejected (reason returned) if any entry is malformed,
  a node ID isn't a positive integer, seconds aren't 1–3600, a route has fewer than 2 or more than 30 nodes, or
  there are more than 20000 entries. Then add only keys missing from `db.hops` / `db.routes`. Returns the count
  added.
- **Revision:** a 31-bit string hash (djb2, Lua 5.1-safe arithmetic) of the sorted key list (keys only, not
  seconds). Two installs have the same keys exactly when neither has anything new for the other, so differing
  seconds for the same leg never cause a re-sync.
- Not shared: `paces`, `calibration`, `stats` (about your own client and flying).
- **Size:** about 13 bytes per leg. 2000 legs ≈ 26 KB ≈ 7 chunks ≈ 4 s at the pacing above.

Everything else in Flight is unchanged: received times are ordinary times, so the countdown bar, cinematic and
Coverage use them as they are. Coverage now means "timed by you or your network".

## Saved variables (`TomteDB.share`)

```lua
defaults = {
	sets = { flight = true },  -- [set key] = shared (send and accept)
	toast = false,             -- toast when a friend's data adds something
	friends = {},              -- [BattleTag] = { blocked, character, version, seen, sets = { [key] = { rev, at, added } } }
}
```

`seen` and `at` are `time()` values; `added` is the running total of entries this friend gave you. Friends are kept
until "Forget" on the page. `module.noShare` covers `friends` (a profile export must not carry BattleTags).

## Friends page and settings

- **Page** (Tomte window, home entry kind `page`): one row per friend seen running Tomte: BattleTag name, last
  character, Tomte version, "synced 2 days ago" (`ns.Ago`), "gave you 34 flight legs", a Block checkbox and a
  Forget button. An empty state explains that friends need Tomte with Friend sharing on.
- **Settings:** module switch; "Share flight times" (`sets.flight`, tooltip: "Send the flight times you know
  to your Battle.net friends and add theirs to yours"); "Show a toast when friends send something new"
  (`toast`, off).
- **Commands** (`/tomte share ...`): `list` (friends, versions, last sync), `sync` (hello to everyone now),
  `why <name>` (last 20 messages exchanged with that friend and what was decided: sent, requested, ignored and
  why). The message log is in memory only.

## Off means off

`toggle(false)`: unregister events, cancel the queue, timers and partial reassemblies. The prefix registration
can't be undone and is harmless. `ns.Share_Changed` and `ns.Share_Register` do nothing while the module is off
(Flight still registers, Share only acts when active).

## Testing

**Unit tests (plain Lua):**
- `tests/test_share_protocol.lua`: build/parse round trip for H/R/D; unknown version and malformed messages
  rejected; chunking under the size limit; reassembly out of order; a newer revision drops the partial one.
- `tests/test_flight_share.lua`: export is deterministic; import round trip; fill-gaps-only (your value kept);
  every rejection rule; revision equal for same keys with different seconds, different for different keys;
  two simulated installs converge after one exchange each way and then have equal revisions (no further sync);
  relay: A→B→C carries A's legs to C.

**In game (user and a friend, both on the new build, both with Friend sharing on):**
1. `/reload`, `/tomte share list`: the friend appears with their Tomte version.
2. The friend with fewer flight times checks the Coverage map before and after `/tomte share sync`: more
   flight masters timed. `/tomte share why <name>` shows hello, request and data.
3. Fly a route only the other person has timed: the bar shows a countdown, not "unknown".
4. Block the friend, `/tomte share sync`: `why` shows nothing sent or accepted.
5. Turn the module off: `/etrace` shows no `BN_CHAT_MSG_ADDON` handling by Tomte and nothing is sent.

## Out of scope (this round)

Crafting, group check, "Send to friend", guild/party/character-friend channels, per-friend undo, marking which
times came from friends, sharing paces.
