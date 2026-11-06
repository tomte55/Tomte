# Forever-only leveling tools (2026-11-05)

The user picked five ideas for World of Warcraft: Forever that retail can't have, and left the decisions to Claude. These
modules load only from `Tomte_Forever.toc` (`extra` in `tools/forever_list.lua`). Facts come from Blizzard's source for
Forever (`forever` branch of Gethe/wow-ui-source). Nothing has run in game when this is written.

## Leveling (`Modules/Leveling/`, key `leveling`, on by default)

One page in the Tomte window plus short toasts, so a level up tells you what's worth doing.

- **Trainer:** there's no API that lists spells away from a trainer, so each visit to your class trainer saves its list
  (name, rank, level, cost) per character. After a level up: "2 new at your class trainer". Until the first visit, the page
  says to visit once. It reads what the trainer's own filters show: with "not available yet" switched off there, only the
  spells you can learn now are saved. Trade and pet trainers are ignored (`C_Trainer.GetTrainerType`).
- **Old ranks on your bars:** every bar spell where `C_ActionBar.IsHighestSpellRank` is false, by name. Only named, never
  moved: placing actions is left to the player.
- **Talent points:** `C_ClassTalents.HasUnspentTalentPoints`, as Blizzard's micro button does.
- **Ammo:** `UnitUsesAmmo` and `C_PaperDollInfo.AmmoNeeded`, counted in the ammo slot. A toast when it drops below the
  setting. At a vendor selling the right kind for your weapon (bow, crossbow: arrows; gun: bullets), a button buys one
  purchase per click (buying needs a click). Measured on a Hunter: `UnitUsesAmmo` true, 773 in the ammo slot.
- **Reagents:** no hand-kept list: bar spells where `C_ActionBar.IsConsumableAction` is true, with
  `C_ActionBar.GetActionUseCount` as the casts left. Warnings only: no API says which item a spell needs, so no vendor
  button. Only spells on your bars are seen.
- **Quests:** the page sorts the log into ready to turn in, timed, worth doing now, hard or elite (a group helps), easy and
  grey, with `C_PlayerInfo.GetContentDifficultyQuestForPlayer` and `C_QuestLog.IsEliteQuest`, as Blizzard colors titles.
  It never abandons anything.
- **Weapon skills:** `C_SkillInfo` for the skill lines in Blizzard's own list, sorted by how far behind, worn weapons
  marked. Gear Check warns on a weapon whose skill is at least 10 behind, so it stops being a clean upgrade.

- **Layout (2026-11-06):** the user's first look called the page a wall of text. It now has an XP block on top (the bar also
  shows the XP in finished quests and rested XP), then what's waiting as icon rows with clean checks folded into one line,
  the trainer's next level and weapon skill bars on the left, and quests with level and XP on the right. On Home it takes
  the `week` slot, which Forever has free, until the level cap (`GameRulesUtil.GetEffectiveMaxLevelForPlayer`, as Blizzard's
  XP bar).

## Pet care (`Modules/PetCare/`, key `petcare`, Hunters only, on by default)

- A secure button, shown out of combat when the pet is below happy and food it eats is in your bags: `/cast Feed Pet` then
  `/use <bag> <slot>`. Moved with Edit Mode. Hidden in combat, as protected frames must be.
- **Which food:** the lowest item level that's at most 30 levels under the pet (the vanilla rule for food a pet can still
  benefit from; not confirmed on Forever), so the good food stays; else the highest there is.
- No food: one toast naming the pet's diet (`C_PetInfo.GetPetFoodTypes`).
- Tooltip and `/tomte petcare why`: happiness, damage, loyalty, training points.

## Left out on purpose

- Buying several ammo stacks at once, automatic trainer purchases: buying needs a real click per action.
- Moving spells on your bars: only named.
- A key binding for feeding: `Bindings.xml` is shared with retail, where it would be a dead key.
