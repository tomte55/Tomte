# Tomte: Next up

Date: 2026-10-06. **Draft**, waiting on the user's answers to the open questions at the end. One of five features
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

## Options (Tomte window category)

"Next up on Home" (on), and per-source checkboxes so a source the user doesn't care about can be turned off.

## Testing

- Plain Lua: `NextUp_Rank` (merge, ties, dismissed, limit), each module's pure candidate builder where one exists.
- In game: Home with vault ready / not, a low-durability character, in a zone with a worth-it WQ, a rare up.

## Open questions for the user

1. Placement: top of the right column (above Around you), or a strip under "This week" across the full width?
2. Is the score order above right for you? (Especially: rares above Concentration, achievements low.)
3. Should "Next up" also be a small toast-free list on the minimap button tooltip, or Home only?
4. "Not now" until next login, or until the candidate changes (e.g. a different rare)?
