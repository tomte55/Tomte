local addonName, ns = ...

-- Midnight (expansion 11): Buff reminders' consumable auras (see Core/Content.lua; read in
-- Modules/Buffs/Read.lua). Same shape as Data/WarWithin/Buffs.lua: one spell ID per buff name, matched on the
-- player by localized name. Spell IDs and names from the SpellName table on wago.tools (build 12.1.5), checked
-- 2026-10-20; the augment rune buffs by name (Void-Touched, Tidesworn) because their items weren't in the data.
-- Untested in game: the user doesn't own Midnight yet.

ns.Content_Register(11, "buffs", {
	food = {
		1232086, -- Well Fed
		1232076, -- Hearty Well Fed (persists through death)
	},
	flask = {
		1235057, -- Flask of Thalassian Resistance
		1235108, -- Flask of the Magisters
		1235110, -- Flask of the Blood Knights
		1235111, -- Flask of the Shattered Sun
	},
	rune = {
		1264426, -- Void-Touched (Void-Touched Augment Rune)
		1295329, -- Tidesworn Augment Rune (China only)
	},
})
