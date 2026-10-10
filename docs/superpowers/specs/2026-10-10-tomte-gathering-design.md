# Tomte: Gathering sessions

Date: 2026-10-10. The user asked for a design and plan, to review before anything is built. Claude made the
decisions below; the questions still open for the user are at the end.

## Goal

Track gathering runs. The user is a Miner and Blacksmith at level 80 in The War Within; friends may pick herbs, skin,
fish or play Midnight. While gathering, and afterwards, Tomte answers:

- How many nodes did I gather, and how fast (nodes per hour)?
- What did I get: items, amounts and quality ranks?
- What is it worth (Gold & value: Auctionator, TSM or vendor), and what is that per hour?
- Did anything rare drop? Did I gain skill or profession knowledge?
- Where did I gather (zones, as a list, no heat map)?

Success: the user mines for half an hour, sees a small tracker filling up while they go, gets an end-of-run toast, and
can compare runs and zones on a Gathering page later.

## Research summary

API, checked against wow-ui-source live (build 12.1.0.69933, `Blizzard_APIDocumentationGenerated` and
`Blizzard_UIPanels_Game/Mainline/LootFrame.lua`) and warcraft.wiki.gg on 2026-10-10:

| API | What we use | 12.x secrecy |
|---|---|---|
| `UNIT_SPELLCAST_SUCCEEDED` (unitTarget, castGUID, spellID, castBarID) | The cast that opened the node | `SecretWhenUnitSpellCastRestricted`: payload can be secret (combat, instances). Only `castBarID` is NeverSecret. |
| `UNIT_SPELLCAST_SENT` (unit, target, castGUID, spellID) | The node's name (`target`), for "Rich Bismuth ×4" | Same predicate; `target` is `ConditionalSecret`. |
| `LOOT_READY` (autoloot), `LOOT_OPENED` (autoLoot, isFromItem) | A loot window opened; `isFromItem` = a container, never a node | Not secret. |
| `LOOT_SLOT_CLEARED` (lootSlot) | A slot was actually looted (bags full leaves it) | Not secret. |
| `GetNumLootItems`, `GetLootSlotInfo` (texture, item, quantity, currencyID, itemQuality, …), `GetLootSlotLink`, `GetLootSlotType` | Items and amounts per slot | Used by Blizzard's LootFrame from plain Lua; no secret notes. Guarded anyway. |
| `GetLootSourceInfo(slot)` → guid, quantity, guid, quantity, … | Who the loot came from. Ore and herbs: `GameObject-…` GUID. Skinning: the `Creature-…` corpse. Containers: an `Item-…` GUID | No secret notes on the wiki. Guarded with `issecretvalue`, like Recap's rare check. |
| `IsFishingLoot()` | The window is a fishing catch | Used by Blizzard's LootFrame on 12.1. |
| `CHAT_MSG_LOOT` | Already parsed by Recap/Track for session loot value | Not marked `SecretInChatMessagingLockdown` (Track still checks). Gathering doesn't need it. |
| `CHAT_MSG_SKILL` | Not used | `SecretInChatMessagingLockdown`, and its text is English-shaped. Skill is read instead. |
| `GetProfessions`, `GetProfessionInfo(index)` (7th return = base skill line) | Which gathering professions the character has | Plain. |
| `C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)` → `ProfessionInfo { skillLevel, maxSkillLevel, … }` | Skill of the expansion's skill line (Mining 186 → Khaz Algar Mining 2881) | `SecretArguments = AllowedWhenUntainted`. |
| `C_ProfSpecs.GetCurrencyInfoForSkillLine(line)` → `{ numAvailable, currencyName }` | Unspent knowledge. No currency ID in 12.1, so gains are seen as increases of `numAvailable` | `AllowedWhenUntainted`. |
| `TRAIT_TREE_CURRENCY_INFO_UPDATED`, `SKILL_LINES_CHANGED` | When to re-read knowledge and skill | Already used by Alts. |
| `C_QuestLog.IsQuestFlaggedCompleted` | Weekly knowledge drops (the `drops` / `bigDrop` quest IDs in `Data/<Expansion>/Weekly.lua` `profs`) | Plain. |
| `C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemInfo)` → quality number | Quality rank of a gathered reagent (1–3 in The War Within; read, never assumed, so Midnight's ranks work too) | `AllowedWhenUntainted`. Present on 12.1 live even though the 12.0.0 change list shows a removal of `GetItemReagentQualityInfo` (it is back with an `ItemInfo` argument). |
| `C_Item.GetItemInfoInstant(link)` → classID, subClassID | Item type: Tradeskill (7) subclasses Metal & Stone 7, Herb 9, Leather 6, Elemental 10 (wiki ItemType) | Plain. |
| `C_Map.GetBestMapForUnit("player")`, `C_Map.GetMapInfo(id).name` | Zone per node, by map ID (language-free) | `AllowedWhenUntainted`; nil in some instances. |
| `ns.Value_ItemPrice(link)` | Price per item (Auctionator, TSM or vendor; bound items at vendor price) | Tomte. |

What this means:

- **No combat log.** `COMBAT_LOG_EVENT_UNFILTERED` can't be registered in 12.x, so detection is cast + loot window.
- **The loot window is the reliable signal.** It isn't secret, it says what dropped and from what (`GetLootSourceInfo`),
  and `LOOT_SLOT_CLEARED` says what really went into the bags.
- **The cast says which profession.** Spell IDs are game facts. GatherMate2's collector matches these anchor spells
  (by ID and by localized name, so all ranks and languages match): Mining 2575, 195122, 423341 (Khaz Algar Mining,
  Wowhead), 471013; Herb Gathering 2366; Fishing 7620, 131476. Skinning is 8613. Opening 3365 / 22810, Pick Lock
  1804, Survey 73979 and Logging 167895 / 1239682 (housing lumber) are **not** gathering. The per-expansion herbalism
  and skinning spells aren't confirmed, so Tomte also **learns** a cast spell from what it opened (see Detection).
- **The cast can be secret** (gathering with a mob on you, or in an instance). Then Tomte classifies the loot by its
  contents alone, and never errors.
- **Skill-ups and knowledge are read, not parsed from chat.** That works in every client language.

## Decisions

### Separate module, linked to the play session

A new module `gather` ("Gathering", category General, enabled by default), not a layer inside Recap:

- A **run** is not a play session. One session can hold several runs (mine, quest, mine again), and Recap can be off.
- It needs its own state (live run, learned spells, run history), its own widget and page.
- It still feeds the session: the live session gets `session.gather` (nodes, value, runs), the recap card shows a
  gathering line, and the Sessions page keeps it in each stored session (see Integration).

Nothing runs for a character without gathering professions except the loot-window check, which is cheap.

### What a gather is

Every loot window (`LOOT_READY`, once per window) is classified by `ns.Gather_Classify` (pure):

1. `isFromItem`, no slots, or a source GUID of type `Item` → not a gather.
2. `IsFishingLoot()` → **fishing**.
3. A player cast in the last 3 seconds (castGUID remembered from `UNIT_SPELLCAST_SUCCEEDED` for `player`, not secret)
   whose spell is a gathering spell (anchor ID, anchor name, or learned) → that kind, if the sources fit the kind
   (mining/herbalism: `GameObject`; skinning: `Creature`).
4. A known non-gathering spell (Opening, Pick Lock, Survey, Logging) → not a gather.
5. No readable cast (secret, or none): `GameObject` sources whose items are mostly ore/stone (subclass 7) → mining,
   mostly herbs (9) → herbalism. `Creature` sources never count without a cast (normal mob loot can hold leather).
6. Otherwise not a gather.

**Learning:** an unknown, readable cast spell that opened a `GameObject` window classified by rule 5, or a `Creature`
window with mostly leather (6), is stored in `db.spells[spellID] = kind` after 2 such windows. Learned spells show in
`/tomte gather why`. This covers Midnight and any rank Tomte doesn't ship.

**Nodes:** one loot window can hold several sources (area loot of skinned corpses). The window counts as one gather per
distinct source GUID. A rich vein mined three times is three gathers and one node; the tracker shows nodes, and the run
keeps both counts.

**Items:** read per slot at `LOOT_READY` (link, quantity, quality, rank, subclass), booked when that slot gets
`LOOT_SLOT_CLEARED`. Money and currencies are ignored (money is already in the session's gold). Each item is priced once
with `ns.Value_ItemPrice` when booked.

### When a run starts and ends

- **Start:** automatically on the first gather (option "Start runs by themselves", on). `/tomte gather start` or the
  tracker's Start starts one now, so the flight out counts.
- **End:**
  - idle timeout: no gather for 10 minutes (slider 3–30); the run ends at its **last gather**, so the idle tail
    doesn't lower the per-hour numbers;
  - `/tomte gather end` or the tracker's End button;
  - logging in another character, or a login more than the timeout after the last gather.
- **Survives `/reload`** and a quick relog: the live run is in `db.run` with `lastAt`.
- **Kept** when it has at least 5 nodes (setting 1–20) or was started by hand. Shorter ones are dropped; their items
  still count in the session's loot value through Recap as today.
- **Duration** = last gather − start, at least 60 seconds. Live: now − start, but at most last gather + 2 minutes.
- **Kinds:** a run can mix kinds (a Miner + Herbalist picks both). It counts per kind; its title uses the kind with the
  most nodes ("Mining run").

### Fishing boundary

The Fishing module (`2026-10-10-tomte-fishing-design.md`) is only the action and its helpers (one key, auto loot,
loot protection) and keeps no loot stats. Gathering owns the counting:

- Fishing catches are counted as kind `fishing` in runs, behind the option "Count fishing" (on). Gathering detects them
  itself with `IsFishingLoot()`, so it works with the Fishing module off or with another fishing addon.
- A run that is only fishing is a "Fishing run"; its "nodes" are catches (pools aren't told apart from open water).
- No calls into the Fishing module are needed. Its `ns.Fishing_IsFishing()` / `ns.Fishing_LastCast()` stay unused
  unless `IsFishingLoot()` turns out unreliable in testing.
- `ns.Gather_Current()` is public, so a later fishing view can show catch stats without counting twice.

### Rare finds

Kept in `run.finds` and shown on the tracker and page:

- any gathered item of item quality Rare (3) or better (for example Null Lotus);
- a weekly knowledge drop: one of the profession's `drops` / `bigDrop` quest IDs that flips to completed during the run.

No hand-made rare item list: the rule works for every profession and expansion. A find gets a small toast (option, on).
Epic or better items already reach the recap as notable loot through Recap/Track.

### Skill and knowledge

- **Skill:** for each gathering profession, read the content expansion's skill line (`profs[base].child` from
  `ns.Content_Get(expansion, "profs")`) with `GetProfessionInfoBySkillLineID`; fishing and any profession without a
  child line fall back to `GetProfessionInfo`'s rank. The first reading in a run is `from`; later ones move `to`.
  Shown as "Mining 87 → 93 (+6)".
- **Knowledge:** `numAvailable` from `GetCurrencyInfoForSkillLine(child)`, read at run start, after each gather and on
  `TRAIT_TREE_CURRENCY_INFO_UPDATED`. Only increases count (spending points mid-run is not a loss). Shown as
  "+3 knowledge", plus "drops 3/5 this week" from the quest flags.

### Zones

Each gather stores its map ID (`C_Map.GetBestMapForUnit`). A run keeps nodes and value per map ID; the page lists zones
by nodes per hour and gold per hour across runs (a run's time is split by its share of nodes). No map, no heat map.

## On-screen tracker

A small widget, Edit Mode name "Gathering run" (`ns.EditMode_Register`), shown only while a run is on (and in Edit
Mode). Hidden in pet battles and instances. Option "Show tracker" (on).

```
[icon] Mining run                    32:10   [–] [End]
42 nodes · 78/h          3,860g · 7,210g/h
Bismuth ◆◆      ×86      Ironclaw Ore ◆   ×31
Crystalline Powder ×12     (◆ = the game's rank icon)
Finds: <rare item> · drop 3/5
Mining 92 → 95 (+3) · +2 knowledge
```

- Value only when Gold & value is on; "no prices" otherwise.
- The three biggest items by value (by count without prices), with the game's rank atlas.
- Minimized: one line (kind icon, time, nodes, g/h).
- With no run on, the tracker is hidden; `/tomte gather start` starts one by hand.
- Item names in the sketch are examples; the finds line shows whatever the rules below found.

## Gathering page

Home rail page "Gathering" (`kind = "page"`), with buttons as in the Pets page:

- **Runs:** the live run on top, then past runs: when, character, kind, time, nodes, nodes/h, value, gold/h, main zone.
  Filters this character / all and this week / all time, with totals. Click a run for its detail (items with ranks and
  amounts, finds, skill, knowledge, zones, node types).
- **Items:** totals per item over the filtered runs, with ranks side by side ("Bismuth ◆ 120 · ◆◆ 86 · ◆◆◆ 9").
- **Zones:** per zone and kind: runs, nodes/h, gold/h.

Home summary line: "Last run: Mining, 32m, 7,210g/h", or "No runs yet".

## Integration

- **Recap card:** `Summarize` adds `gatherText` from `ns.Gather_SessionText(session)` when it exists
  ("gathered 42 nodes · 3,860g"), appended to the gold-sources line the way `lootText` is (`Recap/Scene.lua`). Nothing when Gathering is off or nothing was gathered.
- **Sessions page:** `Recap_Compact` keeps `session.gather`; the session tooltip adds a "Gathering" line.
- **Next up:** source "nextgather" ("Gathering knowledge drops", score 35): for each gathering profession with weekly
  drops left, "Mining: 2 knowledge drops left this week", click opens the Gathering page. Off when the character has no
  gathering profession or isn't at its content's max level.
- **Recent:** run-end and find toasts go into Recent like every toast.
- **Moments:** not used. A node isn't a milestone; a moment per run would get in the way. (Later: a moment when a
  gathering skill reaches max.)

## Settings (`TomteDB.gather`)

```
auto = true          -- start runs by themselves
idle = 600           -- seconds without a gather that end a run (180-1800)
minNodes = 5         -- smaller automatic runs aren't kept
fishing = true       -- count fishing catches
tracker = { shown = true, collapsed = false, point = nil }
toastEnd = true      -- run summary toast when a run ends
toastFind = true     -- toast for a rare find
keepCount = 50       -- runs kept per character
run = nil            -- the live run
runs = {}            -- history, newest first (collection)
spells = {}          -- learned spellID -> kind (collection)
pageScope = "all", pageRange = "all", pageKind = "all", pageView = "runs"
```

Defaults are safe: the module only reads and counts; it changes nothing in the game.

## Files

| File | Contents |
|---|---|
| `Modules/Gather/Data.lua` | Pure: spell table, GUID parsing, loot classification, learning, run model (add gather, finish, keep), numbers, archive, filters, item/zone totals, skill and knowledge deltas, session text. |
| `Modules/Gather/Detect.lua` | Events: casts, loot window, slot cleared, skill, knowledge, drops, zone. Calls `ns.Gather_OnGather(g)`. `/tomte gather why`. |
| `Modules/Gather/Tracker.lua` | The widget and Edit Mode registration. |
| `Modules/Gather/Page.lua` | The Gathering page. |
| `Modules/Gather/Gather.lua` | `RegisterModule`, run lifecycle (start, idle, end, reload, character switch), toasts, session link, Home and Next up entries, options and commands. |

Plus small edits in `Modules/Recap/Recap.lua`, `History.lua` and `SessionsPage.lua`.

Credits (README and a comment in Data.lua): the gathering spell IDs as listed in
[GatherMate2](https://github.com/Nevcairiel/GatherMate2)'s collector and on Wowhead. IDs only, no code.

Commands: `/tomte gather` opens the page; `start`, `end`, `why` (last loot window: sources, cast, kind and reason, plus
learned spells), `help`.

## Error handling

- Every payload, GUID, link and name is checked with `issecretvalue` before use; a secret one makes that piece unknown,
  never an error.
- `LOOT_READY` and `LOOT_OPENED` can both fire, and `LOOT_READY` twice: one window is handled once (keyed by the set of
  slot links and sources, cleared at `LOOT_CLOSED`).
- An item not cached yet: its link from the loot slot is enough for the ID and price; the name and rank are filled in
  later on display.
- The idle check runs on a 15-second ticker only while a run is on.
- The run is tied to the character GUID; a run of another character is finished, not continued.

## Testing

- **Unit tests** (`tests/test_gather.lua`, plain Lua 5.1): GUID parsing, classification rules 1–6 (with secret casts),
  learning after two windows and never from Opening, nodes vs gathers for area loot and rich veins, booking only cleared
  slots, run start/finish/keep, idle end at the last gather, duration floor and live cap, per-hour numbers, mixed kinds
  and the title, archive pruning per character, filters and totals, item totals by rank, zone stats with time split,
  skill and knowledge deltas (spending ignored), session text.
- **In game** (user): mine a few nodes in Khaz Algar (tracker, items with ranks, value), wait out the idle timeout (end
  toast, page), `/reload` mid-run, gather while a mob hits you, open a treasure chest (not counted), a quick fishing
  catch, the recap card's gathering line, `/tomte gather why`, Edit Mode placement.

## Out of scope / Later

- Node maps or heat maps (GatherMate2 does that; the user asked for a zone list).
- Logging (housing lumber) and archaeology.
- Herb/ore milling and prospecting value ("what this is worth after prospecting").
- A moment when a gathering skill reaches its max.
- Gathering stats (Finesse, Perception, Deftness) per run.
- Friends' runs through the friend-sharing idea.

## Open questions for the user

1. **Idle timeout:** 10 minutes by default. Shorter (5) for "a run = one loop", or longer?
2. **Minimum run:** automatic runs under 5 nodes aren't kept. Right number?
3. **Fishing:** count catches in Gathering (decided, on; the Fishing module keeps no stats). Agree, or should fishing
   runs stay out of Gathering?
4. **Next up source** for weekly knowledge drops: wanted, or is the Weekly board enough?
5. **Toasts:** a run-end summary toast and a toast per rare find, both on by default. Too much?

## User decisions (2026-10-10)

- 10-minute idle timeout and the 5-node minimum are fine for now (may be tweaked later, so keep them as named constants).
- Fishing counts as gathering (the "fishing" kind, on by default).
- The rest of the open questions: Claude decides.
