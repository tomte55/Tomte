# Buff reminders (`buffs`)

2026-10-20. Module 5 of the addon round (`2026-10-20-tomte-addon-round-overview.md`). Inspired by BuffReminders and
Class Reminders. The user handed every decision to Claude; decisions marked **(Claude's call)** can be tweaked after
testing.

## Intent

Before a pull, show at a glance what you forgot: food, flask, augment rune, weapon oil or stone, and the group buff
your class brings when someone lacks it. Quiet everywhere else.

## Goals

- An icon strip (Edit Mode widget) with one icon per missing buff, tooltip naming it. Shown in dungeons, raids and
  delves and during a ready check anywhere, out of combat only.
- A buff check in chat on entering an instance and on ready checks, through the readiness-check service
  (`ns.Check_Report` / `ns.Check_OnEnterWorld`), the same as Rogue Poisons and Hunter Pets.
- Every check its own setting with a "Where" choice; `/tomte buffs why`, `/tomte buffs test`, `/tomte buffs check`.
- Safe in Midnight: nothing read in combat, nothing compared while auras are secret.

## Non-goals

- No click-to-use on the icons (no secure buttons) **(Claude's call)**: using a flask or food from a button needs a
  secure item button per consumable kind with a bag search, more surface than the reminder is worth. Can come later.
- No "running out soon" warnings for food or flask **(Claude's call)**: keeps it small; a pull rarely outlasts them.
- No self-buff or form checks (Lightning Shield, Devotion Aura, stances...) **(Claude's call)**: they're spec and
  talent dependent, the list would need upkeep, and Blizzard's own spell alerts cover several. Dropped to keep it small.
- No rogue poisons: Rogue Poisons covers them; the weapon check skips rogues.

## Defaults

Module on by default (read-only, only shows in instances). All five checks on; where they run **(Claude's call)**:

| Check | Where by default | Why |
| --- | --- | --- |
| Food buff | raids, dungeons, delves | cheap, always worth it |
| Flask | raids, dungeons | a flask for a delve is overkill |
| Augment rune | raids | runes are scarce; nagging in every dungeon would annoy |
| Weapon oil or stone | raids, dungeons | |
| Group buff | raids, dungeons, delves | free, and the group benefits |

- Consumable checks (food, flask, rune, weapon) only at the content's max level (`ns.ContentAtMax`) **(Claude's
  call)**: a levelling character in a dungeon isn't nagged.
- A ready check outside an instance runs every check that's on; inside one the place rule still holds.
- Buff check: on entering and on ready checks, chat only; banner off by default (the strip already shows it).
- Strip at the top middle of the screen (`TOP`, 0, -160), size 1.

## API findings (12.1.5)

- **Aura secrecy.** [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values): aura APIs produce secret values
  "when combat, encounter, challenge mode, or PvP match addon restrictions are in effect" (SecretWhenUnitAuraRestricted,
  12.0.0; SecretWhenAurasRestricted, 12.1.0). Under `RequiresNonSecretAura`, guarded calls "return no values" for a
  secret aura, so a nil result under restriction doesn't mean "missing". Out of combat, outside an encounter, Mythic+
  run and PvP match, reads are plain. Inside an active keystone the restriction holds even between pulls.
- [`C_Secrets.ShouldAurasBeSecret()`](https://warcraft.wiki.gg/wiki/API_C_Secrets.ShouldAurasBeSecret): "true if
  queries for aura data will generally produce secret values". Read.lua asks it first; when true every aura check is
  "unknown" (never "missing"), so nothing shows. Every value read is still tested with `ns.IsSecret`.
- [`C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)`](https://warcraft.wiki.gg/wiki/API_C_UnitAuras.GetAuraDataBySpellName):
  works for party and raid units; the name argument must not be secret (it's ours, from `C_Spell.GetSpellName`).
  Used for everything because buffs share names across many spell IDs (47 "Well Fed" and 48 "Hearty Well Fed" spells
  in Midnight alone; Blessing of the Bronze is a different spell per class, all named alike). Rogue Poisons uses the
  same call as its fallback.
- 12.1.0 [API changes](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes): full aura enumeration is the main
  casualty for addons (it errors under restriction, per addon authors); per-spell lookups keep working. No scan is
  used here.
- **Weapon enchants.** [`GetWeaponEnchantInfo`](https://warcraft.wiki.gg/wiki/API_GetWeaponEnchantInfo) is deprecated
  in 12.1.0 (fallback removed in 13.0). The replacement,
  [`C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)`](https://warcraft.wiki.gg/wiki/API_C_PaperDollInfo.GetTemporaryEnchantmentInfo),
  returns `{ enchantID, remainingTimeMs, chargesRemaining, hasExpirationTime }` or nothing; Blizzard's
  `Blizzard_BuffFrame/BuffFrame.lua` (live, 12.1.5.70448) uses it with `WEAPON_ENCHANT_CHANGED` and
  `WEAPON_SLOT_CHANGED`. Not an aura read, so it works in Mythic+ too. A slot counts only when its item's class is
  `Enum.ItemClass.Weapon` (`C_Item.GetItemInfoInstant`), so shields and off-hand frills are skipped. Class imbues
  (Windfury/Flametongue Weapon, Lightsmith rites) are temporary enchants and count.
- `C_SpellBook.IsSpellKnown(spellID)` decides whether you can cast your group buff.
- `READY_CHECK(initiator, timeLeft)` / `READY_CHECK_FINISHED` frame the ready-check window.

### Spell IDs (wago.tools SpellName, build 12.1.5)

Group buffs (`ns.BUFFS_GROUP`): Arcane Intellect 1459, Power Word: Fortitude 21562, Battle Shout 6673, Mark of the
Wild 1126, Skyfury 462854, Blessing of the Bronze 364342.

Consumables, matched by localized name (`Data/<Expansion>/Buffs.lua`, `ns.Content_Register(<exp>, "buffs", ...)`):

- War Within: food Well Fed 461957, Hearty Well Fed 462180; flasks 431971-431974 (Tempered Aggression, Swiftness,
  Versatility, Mastery), 432021 Alchemical Chaos, 432473 Saving Graces; runes 453250 Crystallization (Crystallized),
  1242347 Soulgorged Augmentation, 1234969 Ethereal Augmentation.
- Midnight: food 1232086, 1232076; flasks 1235057 Thalassian Resistance, 1235108 the Magisters, 1235110 the Blood
  Knights, 1235111 the Shattered Sun; runes 1264426 Void-Touched, 1295329 Tidesworn.
- Profession phials (Truesight, Bountiful Seasons, Haranir phials) left out: gathering buffs.

## Dropped and why

- **Group buff check in Mythic+, during a boss, in combat or in PvP:** aura reads are secret there; the checks say
  "unknown" and show nothing. The weapon check (not an aura) keeps working.
- **Group members out of range** (`UnitIsVisible` false): counted as "out of range", never as missing.
- **Icon-based "Well Fed" detection** (scan all buffs for the food icon): needs a full aura scan, which 12.1 restricts;
  the two names cover every food buff in both expansions.

## UI

`Strip.lua`: a plain (non-secure) frame `TomteBuffStrip` with up to five 34 px icons, a "Missing buffs" heading, a
border colored by theme role (danger for food/flask, warning for rune/weapon, accent for the group buff), a count on
the group buff when more than one is missing, and a tooltip: what it is and, for the group buff, who lacks it (class
colored, up to ten names). Hidden on `PLAYER_REGEN_DISABLED`, while dead, on a taxi, in a vehicle or pet battle.
Edit Mode shows a sample strip and moves it.

## Settings (category `class`)

- Reminder strip: Show missing buffs as icons; Size; Position Reset; Preview.
- What to check: per check a switch and a "Where" segmented choice (Raids / And dungeons / And delves).
- Buff check: When entering an instance; On ready checks; Banner and sound (off); Run (prints `why`).

## Commands

- `/tomte buffs why`: place, expansion, max level, whether the game hides auras, then each check with its state and
  reason and the buff names it looks for.
- `/tomte buffs test`: the sample strip for 15 seconds (again to hide).
- `/tomte buffs check`: the buff check in chat now.

## Test plan (in game)

1. `/reload`. `/tomte buffs test`: a strip of four sample icons at the top middle; hover shows a tooltip. Again hides it.
2. Open Edit Mode: the strip shows with a blue "Buff reminders" box; drag it, close Edit Mode, `/reload`: it stays.
3. Open world: `/tomte buffs why` says the strip only shows in instances; each check reads `notHere`.
4. Enter a follower dungeon or a delve at level 80 without food: after about 4 seconds chat says "No food buff" (and
   others), and the strip shows food (plus flask and weapon in a dungeon). Eat: the food icon goes away within a second.
5. Apply a weapon oil or whetstone: the weapon icon goes away. On a shield wearer only the main hand counts.
6. In a group as a mage/priest/warrior/druid/shaman/evoker, with someone lacking your buff: the group buff icon shows
   with the count and names; cast it: the icon goes away. Out of range members don't count.
7. Pull something: the strip hides at once and stays hidden in combat; it comes back after combat if still missing.
8. Ready check in the open world in a group: the strip shows for the ready check and hides when it ends.
9. Inside a started Mythic+ key: `/tomte buffs why` says the game hides buffs; nothing aura-based is flagged.
10. Turn the module off: strip gone, no chat on entering. Back on: works without a reload.
11. Rogue: no weapon check (`why` says Rogue Poisons covers it).
