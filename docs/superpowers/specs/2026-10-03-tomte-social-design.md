# Tomte: Social modules (Whispers, Mentions, Friends Online, Group Alerts)

Problem (user): whispers are easy to miss. They're one line in a chat that's always busy. The user liked every
idea from the brainstorm and handed all design decisions to Claude ("build it all, I leave the decisions up to
you"). The decisions are recorded here. API facts were checked against wow-ui-source 12.1.0.69933 and
warcraft.wiki.gg.

## Facts that shaped the design

- **Chat lockdown.** In dungeons, raids, encounters, M+ and PvP, the `text`, `playerName`, `guid` and
  `bnSenderID` of every `CHAT_MSG_*` event (and `CHAT_MSG_SYSTEM`) are secret values. They can be shown
  (`FontString:SetText`, `format` and concatenation take secrets), but they can't be compared, measured,
  used as keys or saved.
- **Blizzard's own flashing.** Blizzard already flashes the taskbar icon (`FlashClientIcon`) for whispers,
  party invites, LFG proposals and ready checks, but not for summons or name mentions. Flashing is only
  added where it's missing.
- **Blizzard's whisper sound.** `TELL_MESSAGE` plays on the effects channel, so it's silent with effects
  muted. Our extra sounds play on the Master channel. Nothing is heard while WoW is in the background
  unless `Sound_EnableSoundWhenGameIsInBG` is on (Group Alerts has a button for it).
- **Window focus.** There's no API to tell whether the game window has focus, so nothing depends on it.
- **No "read" API.** Whispers count as read once you answer them (`*_INFORM`), open them in the inbox,
  click their toast, or right-click the toast or badge.

## Shared parts (Modules/Social)

- **Data.lua** holds the pure logic, unit-tested in `tests/test_social.lua`: conversations (50 messages
  each, 30 conversations, unread ones never dropped), unread totals, name lists, whole-word mention
  matching (UTF-8 aware, ignores colour codes and link internals), watch-list matching and online diffs.
- **Toast.lua** is a stack of cards at one movable spot. The default is the left side above the chat, and
  the position is saved in `TomteDB.toast.point`.
  - Each card has a spaced label in an accent colour, a title (name), up to 3 lines of text and an accent bar.
  - Cards slide in, stay 7–18s (longer for longer text), and pause while hovered. Left-click runs the
    card's action; right-click dismisses it.
  - A card with the same merge key takes the next message (shows "x3").
  - At most 4 cards are on screen; more wait their turn. Pinned cards (the unread badge) sit on top and
    never time out.
  - Cards are held back while a cinematic hides the UI. Cards marked `holdInCombat` are also held in
    combat. When released, an owner with a digest builder gets a single "While you were busy" card.
  - Every social module's options include "Move toasts" (unlock handle) and "Reset position".
- **Inbox.lua** is the whisper window in the panel's dark/gold style. Conversations are on the left (newest
  first, a gold dot for unread). The open conversation is on the right, both directions, with day
  separators and clickable links. Buttons: Reply, Mark all read. Esc closes it.
- The **panel** gained an `input` option type (a text box, saved on Enter or when it loses focus).

## Whispers (key `whispers`)

- **Toast per whisper.** Pink for whispers, blue for Battle.net, light blue labelled "Game Master" for GM
  or DEV flags. The class icon and colour come from the sender's GUID.
  - Left-click marks the whisper read and opens the chat box to that person: `ChatFrameUtil.SendTell` for
    characters, `SendBNetTell` for Battle.net.
  - For Battle.net, the reply uses this session's `|K` name, or looks the friend up by BattleTag for
    conversations saved in earlier sessions.
- **Unread badge.** "N whispers, from A, B and C". Click opens the inbox, right-click marks all read.
- **Hold during combat** (on by default). Whispers that arrive in combat, or while a cinematic is up,
  show afterwards as one card, or as their own card when there's only one.
- **Extra sound** (off by default). Choices: Whisper, Chime, Bell, Invite or Alarm, on the Master channel.
- **History.** Saved in `whispers.store`, shared by the whole account. Conversations are keyed by
  `Name-Realm`, or by `bn:BattleTag` for Battle.net. Read conversations older than 14 days (adjustable)
  are pruned at login. "Keep history between sessions" can be turned off.
- **Whispers in lockdown.**
  - They still get a toast, with the secret name and text as they are: no class colour, no merging and a
    fixed card height.
  - They go into an "In instance" conversation that's kept only for the session and never saved. They
    count towards the badge.
  - Reply uses Blizzard's own last tell target (`ChatFrameUtil.ReplyTell`, wrapped in pcall).
  - Answering anyone while in lockdown clears the "In instance" unread count.
- **Keybinds** (`Bindings.xml`, its own "Tomte" section in Keybindings):
  - "Reply to newest unread whisper"
  - "Open whisper inbox"
  - Both go through one global, `Tomte_Binding(name)`.
- **Commands:** `/tomte whispers inbox`, `/tomte whispers preview`.

## Mentions (key `mentions`)

- **What triggers it.** Your character's name (option) and/or keywords (comma-separated), as whole
  words, case-insensitive.
- **Where.** Guild and officer (on), party, raid and instance (on), say and yell (off), channels and
  communities (off). Your own messages are ignored.
- **The toast.** "MENTION - GUILD", the sender in class colour and the message. Click opens the chat box in
  that channel (`/g`, `/p`, `/raid`, `/i`, `/s`, `/y`, `/<n>`).
- **Alerts.** Flashes the taskbar (Blizzard doesn't for this). Chime sound by default. Held in combat by
  default, with a digest afterwards.
- **Not in lockdown.** Chat text is secret there and can't be searched, so mentions aren't matched. The
  tooltip says so.

## Friends Online (key `friends`)

- **At login** (not on reload), after 8s, one card:
  - friends in WoW, with their character (Battle.net and character friends, de-duplicated)
  - how many friends are in other games or the app
  - how many guildmates are online (`GetNumGuildMembers()` second return, minus yourself)
  - Click opens the friends list.
- **Coming online.** "Toast when": Off, Watch list only (default), or All friends.
  - Character friends come from a diff of the online set on `FRIENDLIST_UPDATE`.
  - Battle.net friends come from `BN_FRIEND_ACCOUNT_ONLINE`, read 2s later so the game info is filled
    in. The app/companion is ignored.
  - Watched guildmates come from `CHAT_MSG_SYSTEM` matching `ERR_FRIEND_ONLINE_SS`. That event is only
    registered while the watch list isn't empty, and doesn't work in lockdown.
  - Nothing fires in the first 15s after login (the summary covers that), and the same person is never
    announced twice within 60s.
- **Watch list.** Character names, guildmates or BattleTags (the number is optional). Watched people also
  flash the taskbar.
- Click a toast to whisper that person.

## Group Alerts (key `alerts`)

- **Covers:** party invite, LFG proposal, PvP queue ready, ready check, summon. Each can be turned on or off.
- **Sound.** A sound on the Master channel (Bell by default) that repeats every 5s, up to 3 times, while
  the popup still waits for an answer.
  - Party invite: the `PARTY_INVITE` popup or `LFGInvitePopup` is up.
  - LFG proposal: `GetLFGProposal()` says it exists and isn't answered yet.
  - PvP: a battlefield has status "confirm".
  - Ready check: `ReadyCheckFrame` is shown.
  - Summon: `C_SummonInfo.GetSummonConfirmTimeLeft() > 0`.
- **Flash.** Summons also flash the taskbar.
- "Sound in background" button turns on `Sound_EnableSoundWhenGameIsInBG`. "Test" plays the sound and flashes.

## Left out

- **Flashing for whispers:** Blizzard already does it.
- **Toasts for invites and summons:** Blizzard's popups already sit in the middle of the screen. The
  missing piece was the sound.
- **Sending replies from the inbox's own edit box:** reply opens Blizzard's chat box instead, which
  handles lockdown, slash commands and BN targets.

## Testing

- `lua Tomte/tests/test_social.lua` covers the pure logic.
- In game (user): the previews (`/tomte whispers preview`, `/tomte mentions preview`,
  `/tomte friends preview`, `/tomte alerts test`), a real whisper from an alt or friend, the inbox, the
  keybinds, and a whisper inside a dungeon. The CVar `addonChatRestrictionsForced` forces lockdown for
  testing.
