# Tomte: future ideas

Ideas the user wants kept for later, not designed or scheduled yet. Each needs a design pass with the user before
building. Parked items inside a module's own spec stay there ("Later" / "Out of scope" sections); this file is for
ideas that don't belong to one existing spec.

## Events & holidays (2026-10-06)

Designed: see `2026-10-10-tomte-holidays-design.md` (plan: `../plans/2026-10-10-tomte-holidays.md`).

## Collection goals (2026-10-06)

Pin a mount, pet, toy or achievement as a goal (from Collect here, Almost Done or the journals). Home lists the
goals with progress, currency have/need summed across alts (Alts + Syndicator), and a waypoint or teleport to the
source (Waypoints, Teleports). Ties the collecting modules together into a "working toward" view.

- Open questions: where goals are pinned from (a star in each journal, like Smart Mount's zone favorites?), how a
  vendor source's cost is known (source text vs. a hand-made table), and whether Almost Done's pins become goals.

## Friend sharing (2026-10-10)

Designed (flight times as the first data set): see `2026-10-13-tomte-friend-sharing-design.md`. The other data
sets below are still ideas.

Friends run Tomte too, so installs could share data with each other. The user wants it later and wants to talk it
through more first; these are the notes from the first discussion.

**How it travels.** Hidden addon data, never a chat message: players see nothing, friends without Tomte drop it
silently. Received through `BN_CHAT_MSG_ADDON` / `CHAT_MSG_ADDON` (the mechanism DBM and WeakAuras use).

| Channel | Reaches | Size | Notes (warcraft.wiki.gg, 2026-10-10) |
|---|---|---|---|
| `C_BattleNet.SendGameData` | Battle.net friends in WoW, cross-realm | ~4 KB | Replaces `BNSendGameData` (deprecated in 12.0.0) |
| `C_ChatInfo.SendAddonMessage` | Party/raid, guild, whisper (same/connected realm) | 255 B | 10 burst then 1/s per prefix; `AddOnMessageLockdown` can block it in instances |

**Flow.** Hello at login and when a friend comes online ("Tomte vX, shares: crafting, flights"); each data set has
a version, newer ones are requested and sent in paced chunks; received data is kept in `TomteDB` with a "last seen"
date so it shows while the friend is offline. Every message carries a protocol version; unknown ones are ignored.

**What could be shared.**
- Crafting: profession + known recipe IDs per character (~1–2 KB) → "Kalle can make this" in the Crafting tab,
  recipe tooltips and Next up. Suggested first, on its own, to prove the backbone.
- Flight times: route pairs + seconds, filling the Coverage map (your own times win).
- Group check on ready check (party channel): pet / poisons / durability badge per Tomte user; skipped in combat or
  when blocked.
- Strategies and crafting lists: only on an explicit "Send to <friend>", received as a toast with Accept/Decline.

**Safety.** Opt-in, off by default, per friend and per data type. Nothing leaves the game; nothing is pushed without
a click. Size guess: 400–600 lines for protocol, chunking and settings, then one adapter per feature.

**Open for the next talk:** which friends/data first, how stale data is shown, whether guild sharing is wanted at all.

**Wanted next (2026-10-13).** Picked by the user after the flight times build; test flights in game first, since
everything here rides the same hello/request/chunk flow. Not designed yet, discuss each before building.
1. Update notice: the hello already carries the friend's Tomte version; when a friend runs a newer one, say once
   "Kalle runs Tomte vX, you have vY" with the releases link. No new data set.
2. Gathering nodes (data set): pool recorded node positions like flight legs, fill gaps, merge duplicates.
   (1 and 2 built 2026-10-13: `2026-10-13-tomte-sharing-update-nodes-design.md`.)
3. Crafting (data set): profession + known recipe IDs per character → "Kalle can craft this" on recipe/item
   tooltips, the Crafting tab and Next up.
4. Collections "who needs this" (data set): friends' missing mounts/pets/toys → a tradable pet or unbound mount
   item you loot says "Kalle doesn't have this" in its tooltip.
5. Send a waypoint (push): "Send to <friend>" on a map pin or waypoint; the friend gets a toast with
   Accept/Decline and Accept sets it in Waypoints (portal route included).
6. Send a shopping/crafting list (push): "can you make these?" lands as a list in the friend's Crafting tab, after
   Accept.

Passed on: friend zone/level on the page rows, weekly status sharing, live friend positions on the world map (no
coordinates in instances, constant traffic), guild/party channels, group check on ready check (secret values).
