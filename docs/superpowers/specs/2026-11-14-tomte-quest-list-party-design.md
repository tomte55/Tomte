# Quest list: party progress and sharing (2026-11-14)

## Why

You group up with someone out questing, often a random player, sometimes a friend, and one of you is further along a
quest than the other. Today the user asks in chat "how far are you?" and stays to help until the other is done. The
Quest list should answer that question by itself while you play, and make sharing a quest or telling the party your
progress one click.

## Goals

- Under each objective in the Quest list: each party member's count for it ("Pala 9/15"), class-colored name.
- A quest you've finished but a party member hasn't keeps showing what they still need.
- Who in the party doesn't have a quest ("Pala doesn't have it"), so you know there's something to share.
- Right-click a quest: **Share with party** (Blizzard's own quest share, the normal accept window on their side).
- Right-click a quest: **Tell party my progress**: one line (or a few) in party chat, the quest link plus each
  objective's count. Manual only, never automatic (Questie posts automatically; that's what the user doesn't want).
- Full progress for party members who also run Tomte, sent between the two addons.

## Non-goals

- Nothing goes to chat without a click. Nothing is sent to anyone outside your party.
- No quest-chain view, no "stick together" nudges (Fellowstep's features), no quest database.
- A quest you've turned in leaves the list as before, party or not.

## Constraints

- The Quest list runs on World of Warcraft: Forever only for now, so this does too.
- Random players don't run Tomte. What the game gives without an addon on their side:
  - `C_QuestLog.IsUnitOnQuest(unit, questID)`: whether a party member has one of your quests.
  - A unit's tooltip data (`C_TooltipInfo.GetUnit`): for each quest the unit counts toward, a `QuestTitle` line, then
    per party member a `QuestPlayer` line (with the player's GUID) followed by that player's `QuestObjective` lines
    ("0/15 Venture Co. Logger slain", `completed`). This is what the game's own mob tooltip shows. So counts for
    objectives tied to a mob near you (nameplates, target, mouseover) can be read; objectives with no mob (talk to
    someone, use an object, explore) can't.
- Values may be secret: every tooltip and unit read checks `ns.IsSecret` and gives up quietly.

## Approach

Picked: party data in the Quest list module itself (no new module), from two sources:

1. **Tooltip reads** (everyone): while you're in a party and the list is on, the tooltip data of your target, the unit
   under the mouse and every nameplate is read every few seconds and when one shows up. Each party member's count for
   an objective you also have is kept until a newer read replaces it, and dropped when they leave the party or the
   game says they're no longer on the quest.
2. **Sync** (party members running Tomte): hidden addon messages to your party (prefix `TomteQuests`): a hello on
   joining, your quest states in full in reply to a hello, and changed quests after each quest log update. A synced
   member's data replaces the tooltip reads for them.

Considered and dropped: sync only (Fellowstep's way: useless with random players, the user's main case); a separate
party module (the data only means something next to the list's own objectives).

## Design

- Pure rules in `Modules/QuestList/PartyData.lua` (tested in `tests/test_questlistparty.lua`): reading tooltip lines
  into per-member counts matched to your objectives by label, the sync message format, which party lines each quest
  shows, and the chat text.
- `Modules/QuestList/Party.lua`: the reads, the member store, the sync queue, Share and Tell. It creates the module's
  event bus (`ns.QuestList_Events`), which QuestList.lua then uses.
- `List.lua` draws, under each objective you see, one line per party member with a count for it (name left, count
  right, green once done). An objective of yours that isn't drawn (quest done, or a finished objective hidden by the
  setting) still gets its party lines while a member hasn't finished it, with the objective's name in the line. Under
  the objectives, one faint line: who's on the quest without a count yet, who doesn't have it, who turned it in.
- Settings (new **Party** card): Party members' progress (on), Who doesn't have a quest (on, under it), Share progress
  with party members who run Tomte (on).
- `/tomte questlist party`: what was read for each party member, and whether they run Tomte.

### Sync format (version 1)

One message ≤ 255 bytes; the first character is the version (`1`), the second the kind:

- `1H`: hello: "send me your quests".
- `1S<entries>`: a full state starts: the receiver forgets what it had from this sender first.
- `1Q<entries>`: more quests (continuing a full state, or changed ones).
- `1G<id>,<id>`: quests gone from the log (abandoned). `1T<id>,<id>`: turned in.
- An entry is `<questID>:<complete 0|1>:<have>/<need>,<have>/<need>...`, entries joined by `|`. An objective without
  a count is `1/1` or `0/1`. Objectives are matched by position (the same quest has the same objectives on both
  sides).

## Left to the builder

Timings (read every 3 s, sync gap), the exact wording of lines, the preview sample.
