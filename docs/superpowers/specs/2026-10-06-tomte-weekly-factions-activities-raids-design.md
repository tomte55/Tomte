# Tomte: Weekly board Factions, Activities and Raids

Date: 2026-10-06. Agreed with the user in chat, inspired by Plumber's Expansion Summary (Factions / Activities /
Raids) but drawn in Tomte's panel style (dark panel, gold hairlines, Morpheus headings, the Home kit).

## Placement

New tabs on the Weekly board: **This week · Factions · Activities · Raids · Characters · Professions**. Renown moves
out of This week's Progress column into Factions (Progress keeps crests and lockouts). Everything follows the
character's expansion (`GetExpansionLevel()`; the user plays The War Within content on a 12.1 client), so there is no
expansion dropdown.

## Factions

- A grid of faction emblems (Blizzard's `majorfactions_icons_<textureKit>512` atlases, a question mark when an atlas
  is missing). Each emblem sits in a **progress ring** (progress inside the current renown level; paragon progress
  once maxed) with a **level badge** under it. Sub-factions are small rings beside their parent: the Undermine
  cartels next to the Cartels of Undermine, Weaver / General / Vizier next to the Severed Threads (IDs and icons from
  Plumber's table; a short hand-kept table per expansion).
- A paragon reward waiting makes the emblem glow (`C_Reputation.GetFactionParagonInfo` 4th return).
- Hover: name, "Renown 7/25", progress "1,737 / 2,500", and the next level's rewards (icon + name).
- Click: selects the faction for the **detail panel**: on the left a big ring, the name, "Renown 7/25" and
  "763 until next level" (or paragon / max text); on the right the reward track by level (level number, reward icon
  and name), earned levels dimmed.
- The main factions come from `C_MajorFactions.GetMajorFactionIDs(expansion)` (unlocked, not hidden from the
  expansion page), read live when the tab shows (renown is account-wide).

## Activities

- Weekly quests Tomte learns from the quest log, now grouped by their quest log header (zone or faction), plus a
  short hand-kept War Within list for things never in the log: "The Key to Success" (account-wide weekly), Restored
  Coffer Keys 0/4, Coffer Key Shards 0/4 (flag quests), and the Worldsoul weekly (quest line 5572).
- A **Hide completed (N)** checkbox (saved). Groups with nothing open are left out while it's on.
- A **Resources** side list: crests first, then the expansion's currencies the character has discovered.

## Raids

- The expansion's raids (journal instance IDs, newest first), each a collapsible header with per-difficulty totals,
  each boss a row with four dots (LFR, Normal, Heroic, Mythic) filled when killed this week
  (`C_RaidLocks.IsEncounterComplete`). Refreshes on `UPDATE_INSTANCE_INFO` and `BOSS_KILL`.
- The Encounter Journal API changes global state; Tomte only reads it when the Raids tab is shown, once per session,
  restores the journal's difficulty and keeps Blizzard's journal from reacting meanwhile (as Plumber does).

## Code

New pure models with unit tests (factions, activities, raids), one view file per tab, a reusable ring widget. The This
week and Characters code stays, except Renown leaving This week.

## Testing

Plain Lua tests for the models; in game: each tab on a max-level character, a ring probe before building on it.
