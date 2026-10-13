# Whisper window redesign

2026-10-13. Picked with the user from mockups (visual companion): chat bubbles (look A), plus three features:
right-click menu, who they are, unread marker. Resizable and better looking were the brief.

## What the player sees

- **Window**: resizable from a grip at the bottom right (min 520 x 340), size and place saved. Title bar as before
  (Whispers, Mark all read, close).
- **List** (fixed width, scrolls): each row has an avatar (class icon; Battle.net icon for a Battle.net friend not in
  WoW; a question mark when the class isn't known), an online dot (green online, grey offline, none when unknown),
  the name, a one-line preview and the age or an unread count badge. Pinned conversations first under PINNED, the
  rest under RECENT (no headings when nothing is pinned).
- **Right-click a conversation** (themed menu): Pin / Unpin, Invite to group (when they're online in WoW), Add friend
  (a character who isn't one), Copy conversation (the copy dialog), Delete (asks first). The "In instance"
  conversation has no menu (its messages are secret).
- **Header**: avatar, name, status line: "Online · Level 80 Paladin · Dornogal" for friends and guildmates, the
  character they're on for Battle.net friends in WoW, "Online in another game" / "On the Battle.net app" otherwise,
  "Offline", or "Not on your friends list". Buttons: Invite (when possible) and "···" (the same menu).
- **Messages**: bubbles. Theirs left on the card color, yours right in an accent tint, time under each, item and
  spell links clickable. Day dividers between days. A NEW divider where the unread messages began when you opened the
  conversation; the view opens there (else at the bottom). The "In instance" conversation keeps the plain line list.

## Data

- `convo.pinned = true` on a saved conversation (new optional field, no migration). Pinned conversations are never
  trimmed or pruned. Delete removes the conversation.
- `whispers.inbox = { point = { point, relPoint, x, y }, w, h }` (default `{}`): window size and place. A table with a
  `point` key is left out of settings strings (Core/Profile.lua).

## Code

- `Modules/Social/Data.lua` (pure, tests in `tests/test_social.lua`): `ns.Inbox_Order(list)` (pinned first, then as
  given; returns the list and the pinned count), `ns.Inbox_StatusText(who)`, `ns.Inbox_NewIndex(count, unread)`,
  `ns.Inbox_CopyText(convo, stamp)`; Trim and Prune skip pinned.
- `Modules/Social/InboxWho.lua`: reads friends (C_FriendList), Battle.net friends (C_BattleNet) and the guild roster
  into `who = { online, level, className, classFile, area, game, inviteName, friend }`; refreshed while the window is
  open (a 10 s ticker, cancelled when it closes).
- `Modules/Social/InboxMessages.lua`: the bubble pane (pooled bubbles in a UI.Scroll, re-laid on width change) and the
  plain line pane for secret messages.
- `Modules/Social/Inbox.lua`: window, list, header, menu, input. `UI.ResizeGrip(frame, onDone)` goes into
  `Panel/Controls.lua` and the Tomte window uses it too.
- `Modules/Social/Whispers.lua`: `ns.Whispers_SetPinned(key, on)`, `ns.Whispers_Delete(key)`, default `inbox = {}`.
