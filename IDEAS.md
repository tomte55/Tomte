# Tomte ideas

Feature ideas captured for later. Newest first. Status: New, Discussing, Planned, In Progress, Built, Parked, Rejected.

---

## Delves: alert when a Mislaid Curiosity spawns

**Date:** 2026-10-15
**Status:** Rejected (2026-10-15: the game only reports the bags while a L00T RAID-R reveal is active, see Notes;
built, tested and removed)

**Description:**
Inside delves, "bags" spawn that you can open for companion curios. Detect them and alert the player to go pick
them up. In game they're called **Mislaid Curiosities**, and depending on the delve they look like a bag, a
mushroom, a vase or a void container. Opening one gives companion XP, Resonance Crystals and sometimes a curio.

**Use Cases:**
- A player running a delve who would otherwise walk past a bag and miss the companion XP or a curio.
- Friends levelling a companion or hunting for specific curios.

**Benefits:**
- Fewer missed bags, so the companion levels faster and curios come sooner.
- Fits the existing Delves module, which already shows the companion's level, role and curios.

**Complexity:** Low if the bags are vignettes, otherwise High or not possible.
- A container on the ground isn't a unit, so nameplates and targeting can't see it. The clean route is
  vignettes (`C_VignetteInfo.GetVignettes` / `GetVignetteInfo`, `VIGNETTES_UPDATED`,
  `VIGNETTE_MINIMAP_UPDATED`).
- `Modules/Collect/Catalog.lua` (`ns.Collect_ApplyVignettes`) and `Modules/Collect/Collect.lua` already read
  vignettes for rares and can serve as the pattern.
- Plan if they are vignettes: in the Delves module, watch vignette events only while inside a delve. On a new
  Mislaid Curiosity, matched by `vignetteID` (never the English name, so other client languages work), show
  `ns.Toast_Show` with a sound and remember the GUID so each bag alerts once. A map pin is optional.
- The vignette IDs go in `Data/<Expansion>/Delves.lua` through `ns.Content_Register`.
- If they aren't vignettes, all that's left is counting bags as you loot them, which doesn't help you find them.

**Notes:**
- Step one: the user checks in game whether the bags are vignettes. In a delve, with a bag spawned or in view:
  ```
  /run for _,g in ipairs(C_VignetteInfo.GetVignettes()) do local i=C_VignetteInfo.GetVignetteInfo(g) if i then print(i.name, i.vignetteID, i.atlasName, i.onMinimap, i.onWorldMap) end end
  ```
  A line with "Mislaid Curiosity" (or similar) means it's buildable. Note the `vignetteID` and check whether
  every container style shares one ID or each has its own.
- 2026-10-15 in-game check (a Midnight delve with Valeera, the Labyrinth doors): **they are vignettes.**
  `Mislaid Curiosity 6699 VignetteLoot onMinimap=true onWorldMap=false`, three bags at once, all vignetteID 6699
  with their own GUIDs. Still unknown: whether War Within delves and the other container styles use 6699 too.
  Since each bag is listed before you reach it, a Tomte map pin is possible; the minimap already shows its own
  `VignetteLoot` icon.
- 2026-10-15 second check: the bags are only vignettes while revealed. The first dump was taken after a friend
  used a L00T RAID-R Mini (item 244193); without it `/tomte delves vignettes` listed only Brann and the exit.
  RareScanner says the same (alerts need the L00T RAID-R curio). Built as: alert + pins while revealed, and a
  reminder on entering a delve when a Mini is in your bags.
- Open questions: toast plus sound only, or a minimap/world map marker too? On by default or a Delves setting?
  Is a per-run count of bags opened useful? (The CurseForge addon "Mislaid Curiosity Counter" does that count.)
- Sources: https://warcraft.wiki.gg/wiki/Mislaid_Curiosities, https://warcraft.wiki.gg/wiki/Curio
