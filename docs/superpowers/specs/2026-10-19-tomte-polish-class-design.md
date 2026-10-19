# Class helpers polish (Pet Health for Warlocks and Unholy Death Knights, Hunter tooltips, Rogue Poisons)

2026-10-19. Part C of the polish pass after the audit (Plan A, Core/Panel, goes first). The user picked the scope of
item 1: Pet Health gets Warlock and Unholy Death Knight profiles. The user plays neither class, so these profiles ship
marked untested until a friend with a Warlock or an Unholy Death Knight has tried them.

## What the player sees

- **Pet Health, Warlocks** (all three specs): the pet bar follows the demon like it follows a hunter's pet: color,
  warning glow, the "heal below this line" tick, and "NO PET" in combat when no demon is out. The icon row under the
  bar has Fel Domination's cooldown (when talented). Reminders name the demon you summoned last this session
  ("No pet - Summon Felhunter"); before any summon, the first summon spell you know (Felguard for Demonology, then
  Felhunter, Voidwalker, Sayaad, Imp). With Grimoire of Sacrifice on, no "NO PET" bar and no "pulled without a pet"
  reminder.
- **Pet Health, Unholy Death Knights**: the same bar for the ghoul. The icon row has Dark Transformation with its buff
  on the ghoul timed ("Dark Transformation 12s"), as Mend Pet is for hunters. Reminders name Raise Dead. Blood and
  Frost Death Knights never see the bar or a reminder (their Raise Dead ghoul is temporary); they can still unlock and
  move the bar.
- **Pet Health, other classes**: the module's page says "Only for Hunters, Warlocks and Unholy Death Knights." (was
  "No pet profile for your class yet.").
- **Pet Health settings**: "Marksmanship uses a pet" only shows for hunters. The "Warning below" tooltip no longer
  names Mend Pet ("The tick on the bar marks it."). Summary: "A pet health bar for Hunters, Warlocks and Unholy Death
  Knights that warns you when your pet needs healing."
- **Hunter Pets, beast tooltips**: before Tomte has ever read your pets, the line under a tameable beast says "Visit a
  stable master to check" (muted) instead of a green "new family". With only the active pets read (no stabled list
  yet), a family you don't have out says "not in your active pets" (muted). "new family" (green) only shows once the
  stabled list was read.
- **Rogue Poisons**: no visible change; the buttons stop rebuilding on every aura change out of combat (a burst of
  aura events now costs one rebuild, 0.2 s later).

## Spells (verified 2026-10-19)

Sources: warcraft.wiki.gg ability pages (patch history up to 12.0.0 and the 2026-08-25 hotfixes) and wowhead spell
pages with 12.1.5 data. Spec IDs are the game's fixed specialization IDs.

| What | Spell ID | Notes |
| --- | --- | --- |
| Health Funnel | 755 | **Removed in 12.0.0** (wiki patch history). Not used: warlocks have no pet heal in Midnight. |
| Fel Domination | 333889 | Retail ID (18708 is Classic). Class talent, 3 min. Icon row, cooldown only. |
| Grimoire of Sacrifice (talent) | 108503 | Affliction and Destruction, still in 12.0.0 (moved rows). |
| Grimoire of Sacrifice (buff on player) | 196099 | Wowhead: the buff, present in 12.1.5. Pet Health treats it as "no pet wanted". |
| Summon Felguard | 30146 | Demonology talent since 12.0.0. |
| Summon Felhunter | 691 | 12.x hotfix 2026-08-25 on the page. |
| Summon Voidwalker | 697 | In the wiki's current permanent-minion list. |
| Summon Sayaad | 366222 | 12.0.1 Incubus appearance; current. |
| Summon Imp | 688 | In the wiki's current permanent-minion list. |
| Raise Dead (Unholy, permanent ghoul) | 46584 | 30 s cooldown; 12.0.0 made it a level 10 Unholy ability. 46585 is the 2-minute temporary ghoul for all specs, not used. |
| Dark Transformation | 63560 | Unholy, buff on the ghoul (15 s since the Midnight pre-patch). |
| Specs | 265 / 266 / 267 Affliction / Demonology / Destruction; 252 Unholy (250 Blood, 251 Frost) | |

Open questions for the friend test (not answerable without the class):
- Whether a dead demon or ghoul stays as a dead `pet` unit (hunter pets do) or vanishes. If it vanishes, the "died"
  reminder never fires for them and the "pulled without a pet" reminder covers it; that's acceptable, but the friend
  test records which it is.
- Whether `C_UnitAuras.GetAuraDataBySpellName("pet", "Dark Transformation")` finds the buff on the ghoul.

## Data

No saved-variable change, no migration. `lastSummon` (the summon spell cast last) and `sacrificed` (Grimoire of
Sacrifice on) are session locals in `PetHealth.lua`.

Profile shape in `Modules/Combat/Data.lua` (pure):

```
CLASS = {
	unit = "pet",
	spells = { { id, buff = true|nil } },  -- icon row, filtered by IsSpellKnown at run time
	revive = { spellIDs },  -- named in the "pet is dead" reminder: the last summon cast if listed, else the first known
	call = { spellIDs },    -- the same for "no pet"
	wantsPet = { [specID] = true | "option" },
	specs = { [specID] = true } | nil,  -- nil: every spec; else the bar and reminders only for these specs
	sacrifice = spellID | nil,  -- a player aura that means "no pet wanted" (Grimoire of Sacrifice)
}
```

`revive` and `call` become lists (were single IDs); the hunter profile becomes `{ 982 }` and `{ 883 }`.

## Code

- `Modules/Combat/Data.lua` (pure, `tests/test_combat.lua`): WARLOCK and DEATHKNIGHT profiles (comment: untested in
  game as of 2026-10-19), `ns.PetBar_ForSpec(profile, specID)`, `ns.PetBar_WantsPet(profile, specID, optionOn,
  sacrificed)` (new fourth argument), `ns.PetBar_SummonSpell(list, last, isKnown)`, `ns.PetBar_IsSummon(profile,
  spellID)`, `ns.PetBar_HasOption(profile)`; `ns.PetBar_Visible` hides for `s.offSpec` (after the unlocked check).
- `Modules/Combat/PetHealth.lua`: reads Grimoire of Sacrifice out of combat only (aura reads can be secret in
  combat; the cached value holds through the fight), remembers the last summon from `UNIT_SPELLCAST_SUCCEEDED`
  (spell ID checked with `ns.IsSecret`), names the reminder spell through `ns.PetBar_SummonSpell`, registers player
  `UNIT_AURA` only for a profile with `sacrifice`. Summary, description, blocked text, marksman row `shown`, threshold
  tooltip.
- `Modules/Hunter/Data.lua` (pure, `tests/test_hunter.lua`): `ns.Hunter_TameNote(snapshot, count, same)` ->
  `"same" | "owned" | "unread" | "notActive" | "new"`. `Modules/Hunter/Tooltips.lua` maps it to text and color.
- `Modules/Rogue/Rogue.lua`: `UNIT_AURA` goes through `UI.Debounce(AURA_DELAY, Refresh)`; every other event still
  calls `Refresh` directly. `Refresh` keeps its `InCombatLockdown()` guard (a deferred call that lands in combat does
  nothing; `PLAYER_REGEN_ENABLED` refreshes after the fight).
- README Pet Health row, CHANGELOG.

## Checked, not changed

- **Deprecated spec globals (audit item 2)**: no file calls the global `GetSpecialization`, `GetSpecializationInfo`
  or `IsPlayerSpell`. `Modules/Gear/Context.lua:7-8`, `Modules/Rogue/Rogue.lua:19-20`,
  `Modules/Hunter/Checks.lua:11-12` and `Modules/Combat/PetHealth.lua:11-12` capture
  `C_SpecializationInfo.GetSpecialization` / `.GetSpecializationInfo` into locals of the same name, which the audit
  read as the globals. `Modules/Gear/Weights.lua:231` passes a seventh `classID` argument: valid, added to
  `C_SpecializationInfo.GetSpecializationInfo` in 12.0.0 (warcraft.wiki.gg). Nothing to change; the final
  verification greps for the bare globals again.
- **Core/Check.lua pet check (audit item 5)**: `Core/Check.lua` holds no pet rules. `ns.Check_Report` is generic
  and `ns.Check_OnEnterWorld` only reads the content kind (moved to Core by Plan A). The pet check itself is Hunter
  Pets' (`Modules/Hunter/Checks.lua`), blocked for other classes, and its rules are hunter-only (pet spec Ferocity /
  Cunning / Tenacity, Growl, passive). Warlocks and Unholy Death Knights already get Pet Health's "pulled without a
  pet" reminder. A pre-instance pet check for them would be a new feature: raise it with the user, not part of this.
- `ns.Hunter_ContentKind` is Plan A's (moved to Core, as `ns.Check_ContentKind`); this plan doesn't touch its
  callers.
