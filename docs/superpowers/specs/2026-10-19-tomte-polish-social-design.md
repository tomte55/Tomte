# Polish B: quieter defaults, per-character whispers, social presets and chat fixes

Date: 2026-10-19. Status: agreed with the user, ready for a plan
(`docs/superpowers/plans/2026-10-19-tomte-polish-social.md`).

Part of the 2026-10-19 audit follow-up. Six plans run side by side; this is plan **B** (defaults, the social and chat
modules, the first-run presets, docs). Plan **A** (Core/Panel) goes first and provides `ns.Print_Combat`, a central
"module is off" check for commands and bindings, and `ns.MapTabs_Open`. This plan touches Core and Panel only where
listed below (a migration, one Core helper moved in, the preset table and the preset picker's layout).

## Goal

Tomte is shared with friends who never chose its settings. A few modules are louder than a stranger expects (Friend
sharing talks to Battle.net friends in the background, Mentions flashes the taskbar and chimes, Group Alerts rings three
times on the Master channel). The whisper inbox mixes every character's conversations and counts them all as unread
on whoever you're playing. A handful of small bugs and loose ends came up in the same audit.

## What the player notices

### New defaults, for new installs only

| Module | Before | New install | Existing install |
| --- | --- | --- | --- |
| Friend sharing | on | **off** | unchanged (on unless they turned it off) |
| Mentions | toast + taskbar flash + chime | toast only (flash off, sound Off) | unchanged |
| Group Alerts | bell on Master, 3 repeats | bell **once**, on the **Effects** channel | unchanged: Master, their repeats |

Group Alerts gets a new setting, **Sound channel** (Effects / Master), so the old behavior is one click away.
Tooltip: "Effects follows your sound effects volume and is silent with effects muted. Master is heard even with sound
effects off."

### Whisper inbox per character

- Still one inbox for the account. Every whisper with a character (not Battle.net) is a conversation of the character
  you were on: whispering Kesha from Aldric and from Mira gives two conversations.
- The unread badge on a conversation, the Home "Whisper inbox" count, the "While you were away" recap and the reply key
  binding only count the character you're on.
- Conversations of your other characters are listed with "on Aldric" after the name, show no unread badge, and can be
  read, pinned, copied and deleted. Invite, Add friend and the chat line are not offered for them; in place of the
  chat line: "Log in on Aldric to answer." The header's status line starts with "On Aldric · ".
- Battle.net whispers reach your account, not a character: they stay one conversation per BattleTag, shown and counted
  on every character, as now.
- "Mark all read" and right-clicking the recap mark the current character's conversations (and untagged ones) read.

### Setup presets

- Presets no longer touch Whispers, Mentions, Friends Online and Group Alerts: picking Minimal, Collector or Crafter
  leaves them as they are (a new install has them on). Everything also leaves them as they are.
- Crafter also turns on Trade Filter and Chat Tabs.
- New preset **Social**: "Whispers, mentions, friends, group alerts and chat." Turns on Whispers, Mentions, Friends
  Online, Group Alerts, Friend sharing, Trade Filter, Chat Tabs, Channel Tags, Chat Copy and Recent, plus the helpers
  every other preset has (Waypoints, Smart Mount, Teleports). Friend sharing is in it because the card lists it and the
  player picks it on purpose; drop it from the list if the user prefers.
- The picker shows five cards: the four named presets in two columns, Everything as a short card across the bottom.
  Its footnote adds: "Whispers, Mentions, Friends Online and Group Alerts stay as they are unless a preset names them."

### Smaller fixes

1. **Mentions and accented capitals.** "Ásgeir" in chat matches the keyword "ásgeir" (and the other way round), as do
   Latin-1, Latin Extended-A and Cyrillic letters (friends may play other client languages; ruRU is one). Same for Trade
   Filter keywords and highlighting, and Friends Online's watch list.
2. **Trade Filter pause** lasts until you log out. Chosen over a login reminder: the pause is for one shopping trip, a
   reminder at every login is noise, and a friend who forgets it would otherwise have unfiltered Trade chat for good.
   A `/reload` keeps it (the game says whether an entering-world is a login). Tooltip: "Show everything until you log
   out, for when you're shopping. ..."
3. **Chat Tabs** remembers its tab per character by GUID instead of "Name-Realm", so a rename or realm transfer doesn't
   lose track of the tab Tomte opened.
4. **Chat Copy** says "Turn it on in /tomte (Social & chat)." (the real group name, read from `ns.PANEL_GROUPS`).
5. **Mentions from a community channel**: clicking the toast opens the chat line for that channel when the community
   stream is in a chat window (it then has a channel number). When it isn't, the click prints "Mentions: that
   community channel isn't in any chat window, so there's no chat line to open. Answer in the Communities window."
   Tomte doesn't open Blizzard's Communities frame itself (an addon showing that panel risks taint).
6. **Format patterns move to Core.** `ns.Moments_FormatToPattern` (used by Friends Online, Session recap and Moments)
   becomes the Core helper `ns.FormatToPattern`, and its partner `ns.Moments_Match` becomes `ns.FormatMatch`, in
   `Core/Format.lua`. Nothing changes for the player.
7. **Recent's Include list** is built from the modules: each module that shows toasts or banners declares
   `toasts = true` (label = module name) or `toasts = "<label>"`. Friend sharing gets the checkbox it was missing.
   A test scans the source so a new toast owner without the field fails. Clear on the Home block asks first ("Clear
   the Recent list?"), like the page's Clear.
8. **Docs**: README rows for the changed modules, the Social preset, the whisper behavior; the CurseForge page gets
   "Chat & social" and "Class helpers" sections.

## Decisions

- **Detecting an existing install** for the new defaults: `Core.lua` merges `CORE_DEFAULTS` (which creates
  `db.enabled`) only *after* the migrations run, and every load before saved it. So inside a migration,
  `type(db.enabled) == "table"` means saved variables from an earlier version; a fresh install has no `enabled` there.
  `db.setup.state` isn't used: a player who installed after 1.5 and never finished the picker is still "pending".
- **What needs pinning.** `ns.MergeDefaults` writes every default into the saved table on every load, so an existing
  install already has `mentions.flash = true`, `mentions.sound = "chime"` and `alerts.repeats = 3` saved: changing those
  defaults reaches new installs only, with no migration. Two things are *not* saved yet and would silently change:
  `db.enabled.share` (nil unless the player toggled it, so it follows `enabledByDefault`) and the new
  `alerts.channel` (a new key gets its default on merge). Migration 11 pins those two: `enabled.share = true` when nil,
  `alerts.channel = "Master"` when the alerts table exists and has none.
- Running `/tomte setup` and picking Everything later clears `db.enabled`, so Friend sharing then follows its new
  default (off). That's the point of "as it comes"; the card says so.
- **Whisper conversation keys.** Character conversations are keyed `"Name-Realm@<your GUID>"` with
  `convo.with = "Name-Realm"`, `convo.char = <your GUID>`, `convo.charName = "Aldric"`. Battle.net ones stay
  `"bn:BattleTag"` with `with == key` and no `char`. Every place that used the key as the whisper target (reply, send,
  friend lookups, invite, add friend, copy) uses `ns.Social_With(convo)` instead.
- **Saved conversations from before** have no `char` and no `with`: they count as every character's (shown without
  "on ...", unread on everyone, replyable) until one of your characters whispers with that person again, which claims
  the conversation: it moves to the new key, gets tagged and keeps its messages. No migration needed: the shape only
  gains optional fields, and `ns.Social_With` falls back to `convo.key`.
- **Chat Tabs' old records** can't be rekeyed in `ns.MIGRATIONS` (a migration doesn't know GUIDs). Like Gear's
  `Gear_MigrateHinted`, it's a live fix-up in the module: the first lookup on a character moves its own
  "Name-Realm" record to its GUID (pure `ns.Chat_TabsRecord`, tested); other characters move when they log in.
- **Lower case.** `ns.Social_Lower` maps ASCII, Latin-1 (À-Þ except ×), Latin Extended-A (Ā-ž, except İ whose lower case
  changes length) and Cyrillic Ѐ-Я to lower case. Every mapped letter keeps its byte length, so Trade Filter's
  highlighting can still use positions from the lower-cased text to cut the original. Every `:lower()` on either side
  of a keyword or name comparison in Social/Chat pure code switches together.

## Data and migrations

- `ns.MIGRATIONS[11]` (plan A takes 10, plan E takes 12): pins `enabled.share` and `alerts.channel`
  for existing installs. Cases in `tests/test_migrations.lua`: fresh install untouched, existing install pinned, a
  player's own choice (share off, Effects channel) kept.
- `whispers.store.convos[key]` gains optional `with`, `char`, `charName`. Defaults comment updated.
- `chattabs.windows` keys become player GUIDs (old "Name-Realm" keys move lazily). Defaults comment updated; the header
  of `Core/Migrations.lua` lists this live fix-up next to the Gear and Session ones.
- `alerts.channel` new key, default `"SFX"`. `alerts.repeats` default 3 -> 0. `mentions.flash` true -> false,
  `mentions.sound` "chime" -> "off". `share` `enabledByDefault` true -> false.
- `recent.include` gains a key per toast-declaring module, added to `module.defaults.include` in Recent's `init`
  (after every module registered) and merged, so reset and profile export see them.

## Code touched

| File | Change |
| --- | --- |
| `Core/Format.lua` | gains `ns.FormatToPattern`, `ns.FormatMatch` (moved from Moments/Data.lua) |
| `Core/Migrations.lua` | migration 11; header lists the Chat Tabs fix-up |
| `Core/Setup.lua` | `SETUP_UNTOUCHED`, Social preset, Crafter additions, plan/apply/matches skip untouched modules |
| `Panel/Setup.lua` | five-card layout, footnote |
| `Modules/Moments/Data.lua`, `Modules/Recap/Data.lua`, `Modules/Social/Friends.lua` | call the Core helpers |
| `Modules/Social/Data.lua` | `Social_Lower`, `Social_ConvoKey`, `Social_With`, `Social_IsMine`; `AddMessage`, `Unread`, `MarkAllRead`, `ParseWords`, `FindMention`, `IsWatched`, `Inbox_CopyText` updated |
| `Modules/Social/Whispers.lua` | tagged keys, current-character counts, reply/send guards, `ns.Whispers_IsMine` |
| `Modules/Social/Inbox.lua`, `InboxWho.lua` | "on <Name>", no answer actions for other characters, target via `Social_With` |
| `Modules/Social/Mentions.lua` | new defaults, `Social_Lower` for the own name, community click |
| `Modules/Social/Alerts.lua`, `Toast.lua` | channel setting, `Social_PlaySound(choice, channel)`, new defaults |
| `Modules/Share/Share.lua` | `enabledByDefault = false`, `toasts` |
| `Modules/Chat/Data.lua` | `Social_Lower` in keywords and highlight, `Chat_TabsRecord` |
| `Modules/Chat/Filter.lua`, `Tabs.lua`, `Copy.lua` | pause per session, GUID records, group name |
| `Modules/Recent/Data.lua`, `Recent.lua` | `Recent_Owners`, Include built from modules, Home Clear confirm |
| 18 more module main files | one `toasts = ...` line each (list in the plan) |
| `tests/test_social.lua`, `test_chat.lua`, `test_format.lua`, `test_moments.lua`, `test_recap.lua`, `test_migrations.lua`, `test_setup.lua`, `test_recent.lua` | new and moved cases |
| `README.md`, `docs/curseforge/page.md`, `CHANGELOG.md` | player wording |

## Checked, not changed

- Recent's missing owners "wgq, key, teleports, way": those modules have an `OWNER` constant but never show a toast or
  banner (it names event owners, Edit Mode entries and the like). The only owner missing from the Include list was
  `share`. The list is still built from the modules so it can't fall behind again.
- Mentions' flash/sound and Group Alerts' repeats need no migration (see Decisions: the merge already saved them).
- `Modules/Social/Friends.lua`'s `:lower()` calls compare game names lowered the same way on both sides; they stay.
- Pet Health's README row belongs to another plan of this audit; this plan only adds `toasts = "Pet health (banners)"` to `PetHealth.lua`.
