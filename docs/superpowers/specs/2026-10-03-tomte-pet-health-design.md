# Tomte: Pet Health (first Combat module)

## Goal

BM hunter loses track of pet health: the Blizzard pet frame is small and far from where the eyes are in
combat. Four needs: see it at a glance, get warned before the pet dies, know when Mend Pet is worth pressing,
and be reminded when the pet is dead or missing.

## Midnight constraints (verified in game, 2026-10-03)

- `UnitHealth("pet")` is **secret in combat**; `UnitHealthMax("pet")` is not.
- `C_UnitAuras.GetAuraDataBySpellName("pet", "Mend Pet", "HELPFUL")` returned readable data (expirationTime
  not secret). Still guarded: if it comes back secret we show "Mending" without a timer.
- So no threshold logic in combat. Instead, curves the game evaluates for us:
  `UnitHealthPercent("pet", true, curve)` -> secret result that `SetStatusBarColor` / `SetAlpha` /
  `SetFormattedText` accept (all `AllowedWhenTainted`). Percent input is 0..1 (`CurveConstants.ScaleTo100`).
- `UnitIsDead` is not secret. Spell cooldown via `C_Spell.GetSpellCooldownDuration` ->
  `Cooldown:SetCooldownFromDurationObject`.
- Consequence: the low-health warning is visual only (no sound). Sounds only for non-secret events (pet died,
  no pet at pull, pet dead after combat).

## What it shows

Movable block under the character (default `CENTER` 0, -170):

- Pet name above the bar; bar 220x16, value eased (`ExponentialEaseOut`); percent text inside (option).
- Color curve: green above threshold+15%, orange at the threshold, red at half the threshold.
- Warning glow: red border + halo whose alpha comes from an alpha curve: 0 above the threshold, 0.45 just
  below, 1 at half the threshold; a looping pulse inside it.
- Gold tick on the bar at the threshold ("heal below this line").
- Row of 30px spell icons under the bar: Mend Pet and Exhilaration (heals the pet to full). Each shows its
  cooldown as a dark swipe with outlined seconds; "Mend Pet 6s" in green and a gold border while the buff is on
  the pet. Only spells the character knows.
- Dead pet: grey bar, skull, "DEAD". No pet in combat (spec wants one): "NO PET".
- Visibility: "Always when I have a pet" or "In combat, or when hurt" (default). Dead / missing pet always
  shown. Hidden in vehicles and pet battles. Unlocked: always shown as a preview to drag.

## Reminders (banner + raid-warning sound, owner "pet")

- Pet died (any time) -> "<name> died" / "Revive Pet".
- Entering combat without a pet -> "No pet!" / "Call Pet".
- Leaving combat with a dead pet -> "<name> is dead" / "Revive Pet".
- Only for specs that want a pet (BM, SV; MM if the option is on), never while mounted, on a taxi, in a vehicle,
  in a pet battle, or while the player is dead. Same reminder at most once per 10 s.

## Structure (expandable)

- `Modules/Combat/Data.lua` - pure logic, unit-tested: class profiles, wants-pet, visibility, reminder rules,
  curve point lists.
- `Modules/Combat/UnitBar.lua` - generic widget: unit health bar with color/alpha curves, threshold tick,
  dead/missing state, optional spell icon (buff timer + cooldown). Knows nothing about hunters.
- `Modules/Combat/PetHealth.lua` - the module: profile for the player's class, events, reminders, options.

A new class = a new entry in the profile table (unit, heal spell, revive/call spells, specs that want a pet).
A future "own health" or "focus target" bar reuses `UnitBar`.

## Options (Tomte panel, category "Combat", module key `pet`)

Lock bar (+ `/tomte pet lock|unlock`), scale, warning threshold (20-70 %, default 40), show percent, visibility,
Marksmanship uses a pet, the three reminders, reminder sound. Position saved per account (like the flight bar).

## Testing

`lua Tomte/tests/test_combat.lua` for Data.lua. In game: pet bar position/visibility, glow on a dummy, Mend
Pet timer, dismiss pet + pull for the "No pet" reminder, let the pet die.
