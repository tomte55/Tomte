local addonName, ns = ...

-- Gear Check built-in data, refreshed by hand each season: stat weights for the specs we play, and the season's
-- gem item IDs (their stats are read in game). Imported weights (/tomte gear import) always win over these.
--
-- Weights: SimulationCraft single-target sims of the default profiles, build 12.1.0.69933, published by
-- mythicsim.com/stat-priority (2026-09-27), normalized to main stat = 1.
-- season: C_SeasonInfo.GetCurrentDisplaySeasonID() for the season these are from (nil: unknown, no stale hint).
-- Shown in /tomte gear weights.

ns.Gear_Scales = {
	season = 37, -- Midnight S2
	seasonName = "Midnight S2",
	specs = {
		[253] = { -- Beast Mastery
			label = "sims, Midnight S2",
			weights = { AGI = 1, HASTE = 0.63, CRIT = 0.63, MASTERY = 0.50, VERS = 0.45 },
		},
		[254] = { -- Marksmanship
			label = "sims, Midnight S2",
			weights = { AGI = 1, CRIT = 0.71, HASTE = 0.55, MASTERY = 0.51, VERS = 0.44 },
		},
		[66] = { -- Protection Paladin. Damage sims: all four secondaries are within a few percent, item level decides.
			label = "sims, Midnight S2",
			weights = { STR = 1, CRIT = 0.64, HASTE = 0.63, MASTERY = 0.63, VERS = 0.63 },
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
