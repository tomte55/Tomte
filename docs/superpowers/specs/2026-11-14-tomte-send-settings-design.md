# Send settings to a player (design)

Date: 2026-11-14

## Why

The user made a new friend in game who installed Tomte and finds it a lot to get into. The easiest start for him is
the user's own setup. Today that means `/tomte profile export`, copying a long string, whispering it (chat cuts it
up, the friend needs Chat Copy or similar to get it out) and `/tomte profile import`. Sending should be one click on
the sender's side and one "see what changes" on the receiver's side.

## Goals

- Send your Tomte settings to one player in a couple of clicks, without copying or pasting.
- Two routes, both built now:
  - **A. Character:** any player you can whisper (your own or a connected realm), online. No Battle.net
    friendship and no Friend sharing needed on either side.
  - **B. Battle.net friend:** through Friend sharing's existing connection, so it works across realms and regions'
    realm groups.
- The receiver always sees the existing import preview (Panel/Share.lua) before anything changes, and Undo works
  as it does today.
- The sender learns what happened: sent, received, declined, imported, or no answer.

## Non-goals

- No continuous sync. Nothing is ever applied without the receiver clicking Import.
- No sending of data (characters, flight times, lists): the payload is exactly the profile string
  (`ns.ShareUI_ExportText`), which already leaves those out.
- No group-wide broadcast (send to party/guild). One player at a time.

## Anti-goals

- A stranger can pop dialogs on someone's screen at will (spam).
- A send changes anything before the receiver confirms, or works in combat.
- Receiving depends on a module that's off by default (Friend sharing is off on retail).

## How it works

### Sender

- Right-click a player (chat name, target/party/raid frame, friends list): **"Send my Tomte settings"**, added with
  `Menu.ModifyMenu` the way `Modules/Chat/Tabs.lua` extends menus. A Battle.net friend's menu entry uses route B
  when that friend shows up in Friend sharing, otherwise route A to the character they're on (if reachable).
- Tomte settings ("Tomte" group in `Panel/Window.lua`): a **"Send to a player"** button next to Export, asking for a
  character name (prefilled with your target when it's a player).
- Friend sharing page (`Modules/Share/Page.lua`): a **"Send settings"** button on each friend row (route B).
- Command: `/tomte profile send <name>` (route A; listed by the profile help).
- Feedback in chat and as a toast: "Sending your settings to Aldric...", then "Aldric got your settings",
  "Aldric said no thanks", or after a timeout "No answer from Aldric: they may be offline, not run Tomte, or run an
  older Tomte."

### Receiver

- Receiving is part of profiles (Core/Panel), always listening, not a module. It needs no hardware event and sends
  nothing unless asked.
- An offer arrives first (small, no payload). The receiver gets `ns.Confirm_Show`: "Aldric wants to send you their
  Tomte settings. See what changes?" Only on **Yes** is the payload requested and sent; then the existing preview
  (`ShowPreview`) opens with the title "Aldric's settings". **No** answers "declined".
- In combat the offer waits until `PLAYER_REGEN_ENABLED`, then asks.
- One open offer at a time; a second offer while one is open is answered "busy".

### Spam guard (builder's defaults, marked as Claude's call)

- At most one offer prompt per sender per 10 minutes; repeats in between are answered "declined" silently.
- A setting in the Tomte group, **"Let players send me their settings"** (default on: the receiver is exactly the
  new player who hasn't found any settings yet). Off: offers are answered "declined" without a prompt.
- Payload size capped by `ns.PROFILE_MAX_DATA` (Core/Profile.lua) and a chunk count cap; stale transfers dropped
  after 60 seconds, like `Modules/Share/Protocol.lua`.

## Wire format

- Route A: `C_ChatInfo.SendAddonMessage` on `WHISPER`, a new prefix `TomteProfile`. 255 bytes per message
  (warcraft.wiki.gg API_C_ChatInfo.SendAddonMessage); whispers aren't throttled outside instances, but pace and
  handle `AddonMessageThrottle` / `AddOnMessageLockdown` / `TargetOffline` the way `Modules/QuestList/Party.lua`
  does. Only same or connected realms.
- Route B: Friend sharing's channel (`C_BattleNet.SendGameData`), as a direct, never-relayed exchange. Friend
  sharing's `M` messages are one message only, so the payload needs chunking: either a new message kind in
  Protocol.lua or chunks carried over `ns.Share_Send`. Builder's choice; older Tomte must keep ignoring it.
- Messages for both routes: offer, accept, decline/busy, data chunk i of n, done (imported or cancelled after the
  preview, so the sender hears the outcome). Built and parsed in a new pure file with a unit test
  (`tests/test_profile_wire.lua`), with a protocol version first so later changes can be told apart.

## Constraints

- Not on clients without `C_EncodingUtil` (`ns.ShareUI_Available()`): menu entry and buttons hidden there.
- Forever: route A should work (`SendAddonMessage` exists); route B follows Friend sharing there.
- Trial and Veteran accounts can't send addon messages from 12.1.7 (wiki): the sender sees the send failure.
- No taint: menu entries only call our own code; nothing opens Blizzard panels from code.
- Panel loads before Modules: Panel code reaches `ns.Share_*` at call time only.

## Approaches considered

1. **Character addon whisper (A)**: reaches anyone on your realm group, no setup on the receiver. Picked.
2. **Friend sharing / Battle.net (B)**: cross-realm, but needs Battle.net friendship and Friend sharing on both
   sides. Picked as well, alongside A.
3. **A new Friend sharing data set**: rejected: sets are pooled, merged without asking and relayed, which is wrong
   for personal settings.

The user chose to build A and B together.

## Left to the builder

- File names (a pure wire file, a game-side send/receive file next to `Panel/Share.lua`) and TOC placement.
- The exact menu tags to extend (verify in wow-ui-source live branch).
- Route B's chunking mechanism (see Wire format).
- README (profile commands), CHANGELOG under Unreleased once confirmed in game.
