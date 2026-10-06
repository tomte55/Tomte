# Tomte: Next up

Date: 2026-10-06. Agreed with the user: choices are settings with defaults rather than fixed decisions. One of five features
picked from the post-Home ideas (Next up, Recent feed, Sessions page, Gold & value, Send to alt).

## Goal

Home shows a lot, but the user still has to read every block to decide what to do. **Next up** is a short ranked
list (at most 5 rows) of the best things to do right now, each with a one-line reason and a click that starts it.
It only ranks data other modules already keep; it never scans on its own.

## Where it goes

A new Home slot at the top of the right column, above "Around you" (the "characters" column keeps its height).
Heading "Next up" (Morpheus, like the others), meta "n things". With nothing to suggest the heading shows
"Nothing pressing" in grey and the block takes one row.

Below max level (no Weekly view) the vault/knowledge sources drop out on their own; the rest still works.

## Module API

New Home entry kind `next`; any module can add one:

```lua
{ kind = "next", key = "weeklynext", candidates = function(now) return {
    { key = "vault:ready", score = 100, icon = ..., text = "Great Vault rewards waiting",
      why = "Open it before you queue", right = nil, onClick = fn, onEnter = fn } } end }
```

- `key` is stable across refreshes (used to dismiss).
- `score` 0-100; ties keep registration order.
- `text` is the action, `why` the reason (tooltip and grey second half of the row when it fits).
- Pure helper (unit-tested): `ns.NextUp_Rank(lists, dismissed, limit)` merges, drops dismissed keys, sorts, caps.

Candidates are collected in `ns.HomeCall` each time Home is shown, like summaries: cheap, existing state only.

## Sources and default scores

| Score | Module | Candidate | Click |
|---|---|---|---|
| 100 | Weekly | Great Vault rewards waiting (`vaultReady`) | opens the Weekly board |
| 95 | Collect | A rare that drops a missing mount/pet is up now (`Collect_ApplyVignettes`) | `Collect_Waypoint` |
| 90 | Durability | Lowest durability under the threshold (`Durability_Summary`) | none (tooltip: worst slot) |
| 85 | Weekly | Concentration full on a character (`Weekly_ConcNow`), current character first | Weekly board, professions view |
| 80 | World quests | A "Worth it" quest for a collectible or clean upgrade on this map (`WQ_Sections`, reason collectible/upgrade) | tracks it (WQ's `Track` gets exported) |
| 70 | Weekly | A vault track one activity from its next slot (`Weekly_VaultGoal`, e.g. dungeons 3/4) | Weekly board |
| 65 | Almost Done | A pinned achievement, or one with one step left (`Ach_Top`, `last ~= nil`) | `Ach_Open` |
| 50 | Weekly | An open knowledge source with a location (`Weekly_Knowledge`, `loc`) | `Weekly_SetWaypoint(loc)` |

Teleports are left out: using one needs a secure button, and a Home row isn't one.

## Interaction

- Left-click: the action. Then Tomte hides (like map entries) when the action opens something else or sets a
  waypoint.
- Right-click: "Not now", which hides that key until the next login (kept in memory only).
- Hover: tooltip with `why` and the module name.

## Options (module "Next up", category General)

| Setting | Choices | Default |
|---|---|---|
| Show on Home | on/off | on |
| Placement | Right column (above Around you) / Strip under This week | Right column |
| Rows | 3-8 | 5 |
| "Not now" lasts | Until next login / Until it changes (the candidate's key changes, e.g. another rare) | Until next login |
| Sources | a checkbox per source | all on |
| Source order | a priority slider (0-100) per source, prefilled with the scores above | the table |
| On the minimap button tooltip | on/off | off |

## Testing

- Plain Lua: `NextUp_Rank` (merge, ties, dismissed, limit), each module's pure candidate builder where one exists.
- In game: Home with vault ready / not, a low-durability character, in a zone with a worth-it WQ, a rare up.

## As built (2026-10-06)

Built in one go with the other four; not yet tested in game.

- Module `next` (Modules/NextUp). Each candidate type is its own source (own checkbox and priority slider):
  vault rewards (100), rare up (95), durability (90), Concentration (85), world quests (80), vault slot (70),
  achievements (65), knowledge (50) and one more, "Materials for your alts" (40, from Send to alt).
- Home: new section slot `next`; the right column stacks Next up and Recent's block above Around you. `Kit.Row`
  takes `onRightClick`. Panel gained `ns.Panel_Hide`, `ns.Panel_Refresh`, `ns.Panel_IsShown`.
- `/tomte next list` (with source and score) and `/tomte next reset`.
