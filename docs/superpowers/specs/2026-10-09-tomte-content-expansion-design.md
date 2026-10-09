# Tomte: follow the character's content expansion

Date: 2026-10-09. Decided by Claude after the user delegated the design ("you decide, you know what's best"), with
these user choices from the discussion: hybrid data (game APIs first, small hand-kept tables otherwise), follow the
character's level band, and a War Within set of Gear Check weights next to Midnight's.

## Goal

Tomte works whatever expansion a player owns and whatever content a character is in: the author (War Within only,
level 80), a friend who owns Midnight, and that friend's alts still in War Within content. No tab is silently empty
or shows another expansion's data.

## Content expansion

`ns.ContentExpansion(level)` in `Core/Content.lua`: `min(GetExpansionForLevel(level) or owned, owned)` with
`owned = GetExpansionLevel()`. This is the rule Blizzard's Group Finder and Encounter Journal use
(`LFGListUtil_GetCurrentExpansion`, `EJSuggestTab_GetPlayerTierIndex`). Per the wiki, levels 71-80 are The War
Within (10) and 81-90 Midnight (11). `ns.ContentMaxLevel(expansion)` = `GetMaxLevelForExpansionLevel(expansion)`.
Timerunning is not handled (today's behavior stays).

Every expansion-dependent read uses it instead of `GetExpansionLevel()`. Saved per-character snapshots store the
expansion they were taken for, so alt rows use the alt's data.

The weekly snapshot (Weekly, Alts' max-level views, World quests) is taken when the character is at its content
expansion's max level: a Midnight owner's 80 alt gets a War Within snapshot; 81-89 get none (as below 80 today).

## Data: one folder per expansion

```
Data/WarWithin/Weekly.lua   Data/WarWithin/Gear.lua
Data/Midnight/Weekly.lua    Data/Midnight/Gear.lua
```

Each file registers tables with `ns.Content_Register(expansion, key, table)`; modules read them with
`ns.Content_Get(expansion, key)` (nil when that expansion has none). Keys:

| Key | Used by | Notes |
| --- | --- | --- |
| `raids` | Weekly Raids | Journal instance IDs, fallback only: the Encounter Journal tier (expansion + 1) is read first |
| `activities` | Weekly Activities | Delve keys, weekly quest lines (hand-kept quest IDs) |
| `resources` | Weekly Activities | Currency IDs |
| `subfactions` | Weekly Factions | Renown itself comes from `C_MajorFactions.GetMajorFactionIDs(expansion)` |
| `crests` | Weekly | Lists of crest sets, newest first; the first set the player has any of is shown |
| `profs` | Weekly, Alts | Profession knowledge (moved from Weekly/Data.lua) |
| `gear` | Gear Check | Stat weights for every spec, gems, season, label (moved from Gear/Scales.lua) |

Midnight IDs come from Plumber (GPLv3, IDs are facts; credited) and WeeklyKnowledge; the author can't see Midnight
content, so they're checked by a friend with `/tomte data`.

Adding an expansion = adding a folder and its TOC lines.

## Missing data

- A tab whose table is missing for the character's expansion shows one grey line: "No <tab> data for <expansion>
  yet." instead of being empty.
- Gear Check without weights for the expansion uses the neutral fallback weights it already has and the "import
  your own" hint.

## /tomte data

A self-check a friend can run and paste: level, owned expansion, content expansion, its max level, the season ID;
for each key whether it exists for that expansion; and whether its IDs resolve in game (currency names, raid names
via the journal, faction names, quest titles where cached). Modules add their checks with `ns.Content_AddCheck`.

## Encounter Journal

Raids are read once per session out of combat: remember `EJ_GetCurrentTier()`, `EJ_SelectTier(expansion + 1)`, list
`EJ_GetInstanceByIndex(i, true)`, restore the tier. Not while the Encounter Journal is shown (read later). Bosses as
today. Any failure falls back to the `raids` table.

## Testing

Pure logic (resolver with stubbed globals, Content_Get, crest-set pick, empty-state models) gets unit tests. In
game: the author's War Within 80 must look exactly as before (Weekly, Raids, Activities, Factions, Gear Check), and
`/tomte data` must show expansion 10 with every key present.

## Out of scope

Expansions before The War Within, Timerunning, history for unowned expansions.
