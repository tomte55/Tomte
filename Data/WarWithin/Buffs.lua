local addonName, ns = ...

-- The War Within (expansion 10): Buff reminders' consumable auras (see Core/Content.lua; read in
-- Modules/Buffs/Read.lua). Each list holds spell IDs whose localized names are looked up on the player with
-- C_UnitAuras.GetAuraDataBySpellName, so one ID per buff name is enough: every food buff of the expansion is named
-- "Well Fed" or "Hearty Well Fed", and a flask's buff carries the flask's name. Spell IDs and names from the
-- SpellName table on wago.tools (build 12.1.5), checked 2026-10-20. Profession phials (Truesight, Bountiful
-- Seasons...) are left out on purpose: they're for gathering, not for a dungeon or raid.

ns.Content_Register(10, "buffs", {
	food = {
		461957, -- Well Fed
		462180, -- Hearty Well Fed (persists through death)
	},
	flask = {
		431971, -- Flask of Tempered Aggression
		431972, -- Flask of Tempered Swiftness
		431973, -- Flask of Tempered Versatility
		431974, -- Flask of Tempered Mastery
		432021, -- Flask of Alchemical Chaos
		432473, -- Flask of Saving Graces
	},
	rune = {
		453250, -- Crystallization (Crystallized Augment Rune)
		1242347, -- Soulgorged Augmentation (Soulgorged Augment Rune)
		1234969, -- Ethereal Augmentation (Ethereal Augment Rune, the permanent one)
	},
})
