# Friend crafting: see what friends can craft, ask them, and get it made (2026-11-07)

## Why

On World of Warcraft: Forever the user and a few friends level together and craft for each other. Alts already knows
which of your own characters can craft a recipe (Crafting tab) and walks you through moving materials between them
(Crafting list, mailbox panel). The same help is missing between friends: you can't see what a friend can craft, and
asking, sending materials and getting the item back is all done by hand in whispers and mail. The goal is that crafting
for each other and helping each other is easy.

Friend sharing (`Modules/Share/`) already exchanges data with Battle.net friends who run Tomte, in the background. It
becomes the transport. The user asked for Friend sharing to be **on by default**.

## Goals

1. **See friends' crafting.** On the Alts Crafting tab, friends' characters show up next to your own: who knows a
   recipe, searchable and filterable like your alts, marked as a friend's.
2. **A setting to show or hide friends' crafting** (the user's request), on the Crafting tab itself, beside
   "Materials on hand", and in the module's settings.
3. **Ask a friend for a craft** in one click from a recipe a friend knows: "Ask Kesha to craft this".
4. **Materials and the finished item move by mail with one click per step**, reusing the mailbox panel (`Send.lua`) and
   the Crafting list's guidance.
5. **Offline friends work:** their recipes stay visible (last known), and a request to an offline friend waits and is
   delivered the next time you're both online.
6. **Friend sharing on by default**, for new installs and for players who never touched the setting.

## Non-goals

- Strangers, guild members or public crafting orders. Only Battle.net friends who run Tomte.
- Friends of friends. A friend's recipes and requests are never passed on to your other friends (unlike flight times and
  gathering nodes, which are pooled).
- Sending a request inside an in-game mail's text (fragile, language-dependent). The waiting request covers the real cases.
- Payment, tips or gold tracking.
- Retail. Built so it doesn't break there (Alts and Friend sharing both run on retail), but designed and tested for
  Forever. Whether it shows on retail is the builder's call (see "Left to the builder").

## Anti-goals (a failure even if it works)

- Anything happening without a click: no automatic mail sending, no automatic crafting (hardware-event rules anyway).
- Requests that pop up and nag. A request appears as a quiet toast and a line in a list, never a modal dialog.
- Friends' rows crowding out your own alts: your own characters always come first.
- Sharing anything about a friend beyond what they themselves chose to share (Friend sharing's existing per-friend block
  and per-set switches apply).

## What the user decided

- Friends' crafting appears in the Alts **Crafting tab** with a toggle there.
- There's an easy way to **request** crafts, then **mail** and so on.
- Friend sharing is **on by default**.
- Offline friends: recipes stay visible with "last seen" and an online dot; a request to an offline friend waits in
  your Tomte, marked "waiting for <name>", and is sent automatically when you're both online. You can mail the
  materials at once (mail reaches offline characters).

## My calls (marked so the user can check them)

- **Only reachable characters are shown:** a friend's character appears only if it is on your realm (or a connected
  realm) and your faction, since mail and trade can't reach the others. *(my call)*
- **Materials:** by default the requester mails the materials. The request says "I'll mail the materials" or "use your
  own materials" (for cheap crafts). *(my call)*
- **Return path:** once the crafter has made it, their mailbox panel offers a one-click group "For Aldric: Light Leather
  Reagent Bag" (Attach, then Send), like "Gear for <name>" today. *(my call)*
- **Friend data isn't relayed.** A new kind of shared data, "from this friend only", sits beside the pooled sets.
  *(my call, follows from the non-goal)*
- **If Battle.net game data doesn't reach Forever friends** (never proven there; `Modules/Share/Roster.lua` matches friends
  by `WOW_PROJECT_ID`), the fallback transport is addon whispers (`C_ChatInfo.SendAddonMessage`, `WHISPER`) to the
  friend's character on your realm, found from the Battle.net friend list's game info. It needs both online, the same
  as Battle.net game data, so the waiting-request design stays as it is. Step one of the plan is the round-trip test
  that decides between the two. *(my call)*
- **Requests follow the `crafts` switch.** A request is sent and accepted only while the `crafts` set is on, on both
  sides; a blocked friend can't send requests and doesn't get yours. With `crafts` off, "Ask to craft" is hidden, and
  an incoming request is dropped and answered "not taking requests", so the asker's request shows as declined.
  *(my call)*

## How it works

### 1. Recipes as a per-friend data set

- A new Friend sharing data set, key `crafts`, registered by Alts like Flight registers `flight`
  (`ns.Share_Register`). Unlike pooled sets it is **per friend**: the import is stored under the sender's BattleTag,
  replacing what that friend sent before, and never re-exported. Friend sharing needs a flag for this on the set
  (for example `perFriend = true`): the hello still advertises a revision, a request still pulls it, but what's
  imported is the sender's own and isn't re-exported.
- **What's sent:** for each of the sender's characters that has scanned professions: name, realm, faction, class,
  level, and per profession: skill, max and the known recipe IDs. Each recipe also carries the item it makes, so the
  receiver can name and show it from item info even if none of their own characters knows the recipe (`recipes[id]`
  on the receiver may be missing).
- **Size:** the payload is compact text, chunked by the existing protocol (2,000 bytes per message, `MAX_CHUNKS`).
  A character with a few hundred recipes must fit; if the chunk limit is too low it is raised in Protocol.lua with a test.
- **Stored** in the Alts db (or Share's per-friend data, builder's call) as
  `friends[BattleTag] = { at, chars = { [name-realm] = { ... } } }`, with a default and a migration-free shape (new key).
- **When it's sent:** the revision changes when a recipe scan or skill change adds something (`ns.Share_Changed("crafts")`,
  debounced like the others).

### 2. Crafting tab

- A toggle "Friends' crafting" (beside "Materials on hand") and a matching settings row. On by default.
- With it on, the character filter lists your characters first, then each friend's reachable characters under the
  friend's name, and search results include friends' recipes.
- In "who knows this", a friend's character shows its name, the friend's name (BattleTag without the number),
  online dot or "last seen 2 days ago", and their skill.
- The recipe detail (right side) gets **"Ask <character> to craft"** for each friend's character that knows it.
- A friend's recipe the user doesn't know locally shows from its item (name, icon, tooltip); materials show if
  the recipe's details are available on this client, otherwise just "materials unknown".

### 3. Requests

- **New messages in the protocol** (a new letter, versioned so older Tomte ignores it, which `Share_Parse` already does
  for unknown kinds): request a craft, answer it (accepted, declined, done), cancel it. Each has an ID so a repeat or
  late message is harmless.
- **Asking:** choose amount and "I'll mail the materials" / "use your own materials". Saved at once as a request with
  state `waiting` (not delivered yet) or `sent`. Delivered when the friend is online; re-sent on each hello until the
  friend's Tomte confirms it (at most once per hello, no ping-pong).
- **The friend's side:** a toast "Aldric asks for 1 Light Leather Reagent Bag", and an entry in a **Requests** list
  (where it lives is the builder's call, see below) with Accept / Decline. Accepting adds it to their Crafting list
  (the existing tracked crafts), tagged as for Aldric, so the tracker and mailbox already guide them.
- **Your side:** the request shows in the same Requests list with its state (waiting, sent, accepted, made, mailed).
  If you chose to mail materials, your mailbox panel shows a group "For Kesha (craft request)" with exactly the
  recipe's materials times the amount, one click to Attach, one to Send.
- **Done:** when the crafter has the item in their bags, their mailbox panel shows "For Aldric: Light Leather Reagent
  Bag". Sending it marks the request done on both sides (a message, or when the item arrives).
- **Cancel / decline** clear it on both sides; materials already sent are the players' business (the request just says
  materials were sent).

### 4. Friend sharing on by default

- **Forever only** (the user's answer): `enabledByDefault = ns.FOREVER == true` for Friend sharing. Retail keeps the
  quieter default from migration 11. The `crafts` set is on by default with the others.
- **Existing Forever players get it switched on once** (the user's answer), including those whose first-run preset
  (Minimal, Collector, Crafter; `Core/Setup.lua` writes an explicit `false` for every module a preset doesn't list) turned
  it off. Tomte can't tell a preset's `false` from a hand-picked one, so a new migration in `Core/Migrations.lua` sets
  `share` on for every Forever profile, once, with a case in `tests/test_migrations.lua`. The user accepted that a player
  who switched it off by hand gets it on too. The migration must not touch retail profiles. The Forever client keeps its
  own SavedVariables, but the migration checks `ns.FOREVER` anyway.
- The Friend sharing settings page says plainly what's shared, including the new "Your characters' professions and
  recipes".

## Constraints

- CLAUDE.md applies throughout: pure files with tests (`Modules/Alts/*Data.lua`, `Modules/Share/Protocol.lua`), events
  only while active, hooks idle when off, theme colors by role, `ns.Confirm_Show` for questions, `UI.ContextMenu`,
  no settings UI by hand.
- Hardware events: mail sending is one click per step (Attach, then Send), as the mailbox panel works today.
- Battle.net game data only reaches friends online with Tomte; nothing assumes delivery.
- Nothing personal in public files: examples use Aldric, Kesha, Mira.
- Forever: the Alts recipe scan already runs there (`tools/forever_list.lua` includes Alts and Share). Battle.net game
  data on Forever must be checked in game early (the first build step should prove a message round-trip between two
  Forever clients).

## Left to the builder

- Where the Requests list lives: a section on the Crafting list tab, a fourth Alts tab, or the Friend sharing page.
  (Recommendation: a "Requests" section at the top of the Crafting list tab, since accepted requests become crafts there.)
- Whether friend crafting also shows on retail, or only on Forever (`ns.FOREVER`).
- Exact wire format of the `crafts` payload and request messages, within the protocol's rules.
- Whether per-friend data lives in Share's db or Alts' db.
- Whether "Where to get it" (Forever) also gets a "Your friend Kesha can craft this" line. A small follow-up, not this
  round.

## Testing

- Unit tests: the `crafts` export/import (round trip, size, per-friend replace, not re-exported), the request messages
  in `test_share_protocol.lua`, request state changes, reachable-character filtering, mailbox groups for requests.
- In game, with a friend: recipes appear on both sides; a request to an online friend and to an offline one; materials
  and the item mailed through the panel; cancel and decline; turning the toggle and Friend sharing off hides and stops
  everything.
