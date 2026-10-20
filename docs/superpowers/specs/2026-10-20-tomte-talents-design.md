# Talent check (`talents`): design

2026-10-20. Part of the addon round (`2026-10-20-tomte-addon-round-overview.md`, module 2). Inspired by
MKeysTalents. The user handed all decisions to Claude; every choice below not taken from the overview is
**Claude's call** and can be tweaked after testing.

## Intent

You keep several saved talent loadouts per spec (a Mythic+ build, a raid build, a delve build, an open world build)
and forget to switch. Talent check remembers which loadout you use where and, when you arrive somewhere with the wrong
one, offers a one-click switch.

## Goals

- Per character (GUID) and spec: one saved loadout per kind of place (open world, dungeon, raid, delve, PvP), plus
  optional per-instance overrides (a specific dungeon, raid or delve by instance ID) that win over the kind.
- On entering a dungeon, raid, delve or PvP instance, and at a ready check, out of combat: if the active loadout isn't
  the one for this place, a card "You're on A; for dungeons you use B" with **Switch to B** (one click) and **Not now**.
- When the player changes loadout by hand inside a place whose saved choice differs (or is empty), offer once:
  "Use A for dungeons from now on?" **For all dungeons** / **Only <instance>** / **No**.
- Nothing saved for a place: no nagging. The first check in a place with nothing saved quietly learns the current
  loadout for that kind (one chat line). *Claude's call:* "just learn" read as auto-learn; it can be turned off
  ("Learn on its own").
- Settings: everything saved for this character, per spec, each with a **Forget** button; plus "Forget all".
- `/tomte talents why` explains the current decision; `/tomte talents list` prints what's saved.

## Non-goals

- No talent editing, importing or exporting; no loadout creation. Only switching between saved loadouts.
- No automatic switching: one click per switch (a button is a hardware event; see API findings).
- No Starter Build handling: while the Starter Build is active the module neither nags nor learns (*Claude's call*;
  it's a leveling aid with its own Blizzard flow, and switching away from it has extra unflag steps in Blizzard's UI).
- No checks during a running Mythic+ key (talents are locked there).
- No other characters' loadouts in settings: the game only reads the logged-in character's configs.

## Defaults (Claude's call unless from the overview)

| Setting | Default | Why |
| --- | --- | --- |
| Module on | on | overview: on by default, quiet |
| Check when entering an instance | on | the point of the module |
| Check on ready checks | on | the moment it matters |
| Check after leaving an instance (open world) | on | gets you back to your world build; only after an instance, never at login or on every zone |
| Learn on its own | on | "nothing saved = just learn" |
| Offer to remember a hand switch | on | overview |
| Card position | top center, y -180 | out of the way of the default HUD; Edit Mode moves it |

## API findings (verified 2026-10-20)

Sources: Blizzard's generated docs
`Blizzard_APIDocumentationGenerated/ClassTalentsDocumentation.lua` and `SharedTraitsDocumentation.lua`, Blizzard's
own UI `Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua` (live branch of Gethe/wow-ui-source), and
warcraft.wiki.gg. The 12.0.0 API change list has no entries for `C_ClassTalents`, `C_Traits` or the trait events.

- [`C_ClassTalents.LoadConfig(configID, autoApply)`](https://warcraft.wiki.gg/wiki/API_C_ClassTalents.LoadConfig)
  -> `result` (`Enum.LoadConfigResult`: 0 Error, 1 NoChangesNecessary, 2 LoadInProgress, 3 Ready), `changeError`,
  `newLearnedNodeIDs`. Not protected, no `HasRestrictions` flag (unlike `SwitchToLoadoutByIndex/Name`, which are
  restricted), no hardware-event note; its only predicate is `SecretArguments = "AllowedWhenUntainted"` (no secret
  arguments from tainted code; ours are plain numbers). Combat and Mythic+ locks surface as `Error` with a
  `changeError` text, which we print as is. We still call it only from a button click and out of combat.
- LoadInProgress starts the "Changing talents" cast; wait for
  [`TRAIT_CONFIG_UPDATED`](https://warcraft.wiki.gg/wiki/TRAIT_CONFIG_UPDATED) (payload: the spec's base config ID,
  not the loadout's) or [`CONFIG_COMMIT_FAILED`](https://warcraft.wiki.gg/wiki/CONFIG_COMMIT_FAILED) (configID).
  Blizzard's frame does exactly this (`TalentFrameBaseMixin:OnEvent`).
- **The active loadout** is not `GetActiveConfigID()` (that is the spec's base config). The dropdown's selection is
  [`C_ClassTalents.GetLastSelectedSavedConfigID(specID)`](https://warcraft.wiki.gg/wiki/API_C_ClassTalents.GetLastSelectedSavedConfigID):
  whatever was last written with `UpdateLastSelectedSavedConfigID`; -2 (`Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID`)
  on the Starter Build; nil on the "Default loadout". `LoadConfig` does **not** write it: Blizzard's frame calls
  `C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)` after NoChangesNecessary and after the commit's
  `TRAIT_CONFIG_UPDATED` (`CheckUpdateLastSelectedConfigID`). We do the same, or the dropdown shows the old name.
- `C_ClassTalents.GetConfigIDsBySpecID(specID)` -> the spec's saved loadout IDs (the dropdown's list).
  [`C_Traits.GetConfigInfo(configID)`](https://warcraft.wiki.gg/wiki/API_C_Traits.GetConfigInfo) -> `{ ID, type, name,
  treeIDs, usesSharedActionBars }`.
- `C_ClassTalents.GetStarterBuildActive()` -> bool.
- [`SELECTED_LOADOUT_CHANGED`](https://warcraft.wiki.gg/wiki/SELECTED_LOADOUT_CHANGED) never fires (wiki, tested
  11.1.0). So a hand switch is seen by `hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", ...)` (the
  call Blizzard's dropdown makes, also for NoChangesNecessary switches that fire no trait event) plus
  `TRAIT_CONFIG_UPDATED`, both debounced, comparing the last-selected ID with the one seen before.
- `C_ClassTalents.CanChangeTalents()` is only true with staged changes (wiki), so it's no use as a pre-check.
- [`GetInstanceInfo()`](https://warcraft.wiki.gg/wiki/API_GetInstanceInfo): name, instanceType (`none`, `party`,
  `raid`, `pvp`, `arena`, `scenario`), difficultyID, ..., instanceID (8th). Delves via `ns.Check_ContentKind`.
- [`C_ChallengeMode.IsChallengeModeActive()`](https://warcraft.wiki.gg/wiki/API_C_ChallengeMode.IsChallengeModeActive):
  no check while a key runs.
- `PLAYER_SPECIALIZATION_CHANGED` (unit event), `READY_CHECK`, `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED`.

Risky / unverified in game: the `Ready` result with `autoApply = true` (Blizzard treats it as "staged, press Apply";
the wiki says "applied without a cast bar"). We wait up to 20 seconds for `TRAIT_CONFIG_UPDATED` and otherwise tell the
player to look at the talent window. No secret values are involved: talent configs are not combat data.

## Place

`ns.Talents_PlaceKind(instanceType, difficultyID)`: `none` -> world, `pvp`/`arena` -> pvp, otherwise
`ns.Check_ContentKind` (dungeon, raid, delve); other scenarios -> no place (no checks). Dungeons, raids and delves also
carry their instance ID and name for overrides.

## Rules (pure, `Modules/Talents/Data.lua`)

- Wanted loadout: this instance's override if its loadout still exists, else the kind's if it still exists.
- Decision: no place, Starter Build, a running key, or no saved loadouts -> nothing. Nothing wanted -> learn (if
  allowed and the active loadout is a real saved one). Active == wanted -> nothing. Else switch.
- Offer after a hand switch: in a place, not Starter Build, the new loadout is a saved one, differs from what the
  place wants, and wasn't declined this session for this place.
- "For all dungeons" also drops this instance's override (else the override would still win here).
- Deleted loadouts: the current spec's saved IDs that are no longer in `GetConfigIDsBySpecID` are forgotten quietly,
  but only when that list isn't empty (empty can mean "not loaded yet" at login).

## UI

- One card (`Modules/Talents/Card.lua`), themed panel, Edit Mode movable ("Talent check"): a small title "Talent
  check", one line of text, a muted detail line, up to three buttons. Hidden on `PLAYER_REGEN_DISABLED`, on leaving the
  place, and when the module turns off. Esc doesn't close it (it's not a window); **Not now**/**No** does.
- Chat: one line per learn, switch result and failure (`ns.Print`).

## Settings (`class` group)

Card **Checks**: entering an instance, ready checks, after leaving an instance. Card **Learning**: learn on its own,
offer to remember hand switches. Card **Saved loadouts**: one button row per saved entry ("Protection - Dungeons:
Mythic build" + Forget), a status row when nothing is saved, "Forget all for this character" (confirm).

## Commands

- `/tomte talents why`: place, spec, active loadout, what's saved and the decision with its reason.
- `/tomte talents list`: everything saved for this character, per spec.
- `/tomte talents check`: run the check now (shows the card if you're on the wrong loadout).

## Test plan (in game)

1. `/reload` with two saved loadouts A and B on your spec. Zone into a dungeon (or a delve) on A: after ~4 s chat
   says "Talent check: remembered A for dungeons." No card.
2. Inside, switch to B by hand in the talent window: a card asks "Use B for dungeons from now on?" with "For all
   dungeons", "Only <name>", "No". Press "For all dungeons".
3. Switch back to A by hand, leave, re-enter: card "You're on A; for dungeons you use B" -> press "Switch to B": the
   cast bar runs, chat says "Switched to B.", the talent dropdown shows B. Move during the cast once: chat says the
   switch didn't finish and the card comes back.
4. `/tomte talents why` and `/tomte talents list` print sensible lines. Settings > Class > Talent check lists the
   entries; Forget removes one.
5. Delete a loadout that's saved somewhere: `/tomte talents list` no longer shows it (after a check or `/reload`).
6. Ready check (party leader `/readycheck`) on the wrong loadout: the card shows. Enter combat while it's shown: it
   hides.
7. Turn the module off: card gone, no checks; on again works without `/reload`.
8. Check BugSack after each step.
