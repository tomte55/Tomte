local addonName, ns = ...

-- Gear Check built-in data, refreshed by hand each season: stat weights for every spec of every class, and the
-- season's gem item IDs (their stats are read in game). Imported weights (/tomte gear import) always win over these.
--
-- Weights: DPS and tank specs are SimulationCraft single-target sims of the default profiles, SimC 1210-01 for
-- build 12.1.0.69933, published by mythicsim.com/stat-priority (generated 2026-10-04), normalized to main stat = 1
-- (tanks are damage sims). Healers and Augmentation have no usable sim: guide priority (Icy Veins + Method, patch
-- 12.1) on a fixed ladder, main 1 then 0.70 / 0.60 / 0.50 / 0.40, "equal" stats share a value. Their label starts
-- with "guide priority" (Gear_IsGuideLabel), which adds "import a sim for better" where the source is shown.
-- Spec IDs from warcraft.wiki.gg SpecializationID; /tomte gear specs checks them against the game.
-- season: C_SeasonInfo.GetCurrentDisplaySeasonID() for the season these are from (nil: unknown, no stale hint).
-- Shown in /tomte gear weights.

ns.Gear_Scales = {
	season = 37, -- Midnight S2
	seasonName = "Midnight S2",
	specs = {
		-- Warrior
		[71] = { -- Arms
			label = "sims, Midnight S2",
			weights = { STR = 1, CRIT = 0.81, MASTERY = 0.79, VERS = 0.78, HASTE = 0.77 },
		},
		[72] = { -- Fury
			label = "sims, Midnight S2",
			weights = { STR = 1, HASTE = 0.97, VERS = 0.79, MASTERY = 0.77, CRIT = 0.72 },
		},
		[73] = { -- Protection Warrior (damage sims)
			label = "sims, Midnight S2",
			weights = { STR = 1, CRIT = 0.71, VERS = 0.71, MASTERY = 0.67, HASTE = 0.56 },
		},
		-- Paladin
		[65] = { -- Holy Paladin
			label = "guide priority, Midnight S2",
			weights = { INT = 1, MASTERY = 0.70, HASTE = 0.60, CRIT = 0.60, VERS = 0.40 },
		},
		[66] = { -- Protection Paladin. Damage sims: all four secondaries are within a few percent, item level decides.
			label = "sims, Midnight S2",
			weights = { STR = 1, MASTERY = 0.63, CRIT = 0.63, HASTE = 0.63, VERS = 0.62 },
		},
		[70] = { -- Retribution
			label = "sims, Midnight S2",
			weights = { STR = 1, HASTE = 0.72, CRIT = 0.69, MASTERY = 0.64, VERS = 0.56 },
		},
		-- Hunter
		[253] = { -- Beast Mastery
			label = "sims, Midnight S2",
			weights = { AGI = 1, HASTE = 0.64, CRIT = 0.63, MASTERY = 0.51, VERS = 0.46 },
		},
		[254] = { -- Marksmanship
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.72, HASTE = 0.55, MASTERY = 0.51, VERS = 0.43 },
		},
		[255] = { -- Survival
			label = "sims, Midnight S2",
			weights = { AGI = 1, HASTE = 0.91, CRIT = 0.83, MASTERY = 0.62, VERS = 0.51 },
		},
		-- Rogue
		[259] = { -- Assassination
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.69, VERS = 0.68, MASTERY = 0.68, HASTE = 0.62 },
		},
		[260] = { -- Outlaw
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.73, VERS = 0.60, HASTE = 0.46, MASTERY = 0.43 },
		},
		[261] = { -- Subtlety
			label = "sims, Midnight S2",
			weights = { AGI = 1, VERS = 0.65, HASTE = 0.64, MASTERY = 0.64, CRIT = 0.55 },
		},
		-- Priest
		[256] = { -- Discipline
			label = "guide priority, Midnight S2",
			weights = { INT = 1, HASTE = 0.70, MASTERY = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		[257] = { -- Holy Priest (raid priority)
			label = "guide priority, Midnight S2",
			weights = { INT = 1, CRIT = 0.70, MASTERY = 0.60, VERS = 0.50, HASTE = 0.40 },
		},
		[258] = { -- Shadow
			label = "sims, Midnight S2",
			weights = { INT = 1, CRIT = 0.73, VERS = 0.63, MASTERY = 0.60, HASTE = 0.58 },
		},
		-- Death Knight
		[250] = { -- Blood (damage sims)
			label = "sims, Midnight S2",
			weights = { STR = 1, CRIT = 0.80, VERS = 0.76, MASTERY = 0.75, HASTE = 0.63 },
		},
		[251] = { -- Frost Death Knight
			label = "sims, Midnight S2",
			weights = { STR = 1, CRIT = 0.91, HASTE = 0.67, MASTERY = 0.61, VERS = 0.47 },
		},
		[252] = { -- Unholy
			label = "sims, Midnight S2",
			weights = { STR = 1, CRIT = 0.91, HASTE = 0.75, MASTERY = 0.62, VERS = 0.57 },
		},
		-- Shaman
		[262] = { -- Elemental
			label = "sims, Midnight S2",
			weights = { INT = 1, HASTE = 0.64, CRIT = 0.63, MASTERY = 0.62, VERS = 0.62 },
		},
		[263] = { -- Enhancement
			label = "sims, Midnight S2",
			weights = { AGI = 1, HASTE = 0.71, MASTERY = 0.70, CRIT = 0.65, VERS = 0.56 },
		},
		[264] = { -- Restoration Shaman
			label = "guide priority, Midnight S2",
			weights = { INT = 1, CRIT = 0.70, VERS = 0.60, HASTE = 0.50, MASTERY = 0.40 },
		},
		-- Mage
		[62] = { -- Arcane
			label = "sims, Midnight S2",
			weights = { INT = 1, MASTERY = 0.62, CRIT = 0.58, VERS = 0.57, HASTE = 0.56 },
		},
		[63] = { -- Fire
			label = "sims, Midnight S2",
			weights = { INT = 1, VERS = 0.56, MASTERY = 0.53, HASTE = 0.49, CRIT = 0.23 },
		},
		[64] = { -- Frost Mage
			label = "sims, Midnight S2",
			weights = { INT = 1, CRIT = 0.58, MASTERY = 0.57, HASTE = 0.55, VERS = 0.53 },
		},
		-- Warlock
		[265] = { -- Affliction
			label = "sims, Midnight S2",
			weights = { INT = 1, CRIT = 0.61, VERS = 0.57, HASTE = 0.54, MASTERY = 0.51 },
		},
		[266] = { -- Demonology
			label = "sims, Midnight S2",
			weights = { INT = 1, VERS = 0.58, CRIT = 0.58, MASTERY = 0.55, HASTE = 0.54 },
		},
		[267] = { -- Destruction
			label = "sims, Midnight S2",
			weights = { INT = 1, HASTE = 0.58, MASTERY = 0.58, CRIT = 0.56, VERS = 0.54 },
		},
		-- Monk
		[268] = { -- Brewmaster (damage sims; Haste's defensive value isn't in them)
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.73, VERS = 0.65, MASTERY = 0.53, HASTE = 0.26 },
		},
		[269] = { -- Windwalker
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.72, HASTE = 0.70, MASTERY = 0.63, VERS = 0.55 },
		},
		[270] = { -- Mistweaver
			label = "guide priority, Midnight S2",
			weights = { INT = 1, HASTE = 0.70, CRIT = 0.60, VERS = 0.50, MASTERY = 0.40 },
		},
		-- Druid
		[102] = { -- Balance
			label = "sims, Midnight S2",
			weights = { INT = 1, CRIT = 0.61, VERS = 0.57, HASTE = 0.54, MASTERY = 0.36 },
		},
		[103] = { -- Feral
			label = "sims, Midnight S2",
			weights = { AGI = 1, HASTE = 0.74, CRIT = 0.69, VERS = 0.62, MASTERY = 0.60 },
		},
		[104] = { -- Guardian (damage sims)
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.50, MASTERY = 0.49, VERS = 0.48, HASTE = 0.48 },
		},
		[105] = { -- Restoration Druid
			label = "guide priority, Midnight S2",
			weights = { INT = 1, HASTE = 0.70, MASTERY = 0.60, VERS = 0.50, CRIT = 0.40 },
		},
		-- Demon Hunter
		[577] = { -- Havoc
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.69, MASTERY = 0.65, HASTE = 0.57, VERS = 0.51 },
		},
		[581] = { -- Vengeance (damage sims)
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.72, MASTERY = 0.64, VERS = 0.63, HASTE = 0.56 },
		},
		[1480] = { -- Devourer
			label = "sims, Midnight S2",
			weights = { INT = 1, CRIT = 0.83, HASTE = 0.68, MASTERY = 0.60, VERS = 0.56 },
		},
		-- Evoker
		[1467] = { -- Devastation
			label = "sims, Midnight S2",
			weights = { INT = 1, HASTE = 0.55, VERS = 0.48, CRIT = 0.47, MASTERY = 0.40 },
		},
		[1468] = { -- Preservation
			label = "guide priority, Midnight S2",
			weights = { INT = 1, MASTERY = 0.70, CRIT = 0.60, HASTE = 0.50, VERS = 0.40 },
		},
		[1473] = { -- Augmentation: no usable damage sim, guide priority like the healers
			label = "guide priority, Midnight S2",
			weights = { INT = 1, MASTERY = 0.70, CRIT = 0.60, HASTE = 0.60, VERS = 0.40 },
		},
	},
	-- Flawless gems, rank 2 (max quality). Peridot = Haste, Amethyst = Mastery, Garnet = Crit, Lapis = Vers.
	gems = {
		240888, 240890, 240892, 240894, -- Peridot: Quick, Deadly, Masterful, Versatile
		240896, 240898, 240900, 240902, -- Amethyst: Masterful, Deadly, Quick, Versatile
		240904, 240906, 240908, 240910, -- Garnet: Deadly, Quick, Masterful, Versatile
		240912, 240914, 240916, 240918, -- Lapis: Versatile, Deadly, Quick, Masterful
	},
	-- Eversong Diamonds (Unique-Equipped: Thalassian Diamond (1)), both ranks. Main stat, most with an effect:
	-- never ranked, only pointed out when none is worn.
	diamonds = {
		240982, 240983, -- Indecipherable
		240966, 240967, -- Powerful
		240968, 240969, -- Telluric
		240970, 240971, -- Stoic
	},
	diamondName = "Eversong Diamond",
}
