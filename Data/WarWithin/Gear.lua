local addonName, ns = ...

-- The War Within (expansion 10): Gear Check's built-in set (Modules/Gear/Scales.lua says how sets are read and shaped).
--
-- Weights: every spec is guide priority. mythicsim.com only started publishing in Midnight, so there are no
-- sims for War Within. Source: the Icy Veins PvE stat priority pages for The War Within 11.2 / 11.2.5 / 11.2.7
-- (Season 3), read from Wayback Machine snapshots of https://www.icy-veins.com/wow/<spec>-pve-<role>-stat-priority
-- taken between 2025-08-15 and 2025-12-14 (snapshot date per spec below; the pages' "Last updated" dates run from
-- Aug 4 to Nov 30, 2025). Same ladder as the Midnight healers: main 1, then 0.70 / 0.60 / 0.50 / 0.40 by position.
-- Stats the guide gives as equal ("=", "/", "or", approximately equal) share the higher value and the next stat
-- drops to its own position's value. Where a page lists more than one priority, the set takes the first: single
-- target / raid, the first hero talent the page lists, and for tanks the general (defensive) list. Item level and
-- stat breakpoints are left out; a guide that ranks the main stat below secondaries (Destruction, Enhancement,
-- Havoc, Feral) still gets main = 1 like every set.
-- season: C_SeasonInfo.GetCurrentDisplaySeasonID() for War Within Season 3 (DisplaySeason ID 30, Manaforge Omega,
-- in the DisplaySeason table on wago.tools). War Within's last season, so the set is final.

ns.Content_Register(10, "gear", {
	season = 30, -- War Within S3
	final = true, -- no newer War Within season will come
	seasonName = "War Within S3",
	specs = {
		-- Warrior
		[71] = { -- Arms (snapshot 2025-11-27)
			label = "guide priority, War Within S3",
			weights = { STR = 1, CRIT = 0.70, HASTE = 0.60, MASTERY = 0.50, VERS = 0.40 },
		},
		[72] = { -- Fury (snapshot 2025-09-05)
			label = "guide priority, War Within S3",
			weights = { STR = 1, MASTERY = 0.70, HASTE = 0.60, VERS = 0.50, CRIT = 0.40 },
		},
		[73] = { -- Protection Warrior (snapshot 2025-10-06)
			label = "guide priority, War Within S3",
			weights = { STR = 1, HASTE = 0.70, CRIT = 0.60, VERS = 0.60, MASTERY = 0.40 },
		},
		-- Paladin
		[65] = { -- Holy Paladin, raiding (snapshot 2025-09-18)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, MASTERY = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		[66] = { -- Protection Paladin (snapshot 2025-09-13)
			label = "guide priority, War Within S3",
			weights = { STR = 1, HASTE = 0.70, MASTERY = 0.60, VERS = 0.50, CRIT = 0.50 },
		},
		[70] = { -- Retribution (snapshot 2025-09-08)
			label = "guide priority, War Within S3",
			weights = { STR = 1, MASTERY = 0.70, CRIT = 0.70, HASTE = 0.50, VERS = 0.40 },
		},
		-- Hunter
		[253] = { -- Beast Mastery, Pack Leader single target (snapshot 2025-09-03)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, HASTE = 0.70, MASTERY = 0.60, CRIT = 0.60, VERS = 0.40 },
		},
		[254] = { -- Marksmanship, Dark Ranger single target (snapshot 2025-11-08)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, CRIT = 0.70, MASTERY = 0.60, VERS = 0.50, HASTE = 0.40 },
		},
		[255] = { -- Survival, Pack Leader single target (snapshot 2025-09-16)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, MASTERY = 0.70, HASTE = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		-- Rogue
		[259] = { -- Assassination (snapshot 2025-09-06)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, CRIT = 0.70, MASTERY = 0.60, HASTE = 0.50, VERS = 0.40 },
		},
		[260] = { -- Outlaw (snapshot 2025-10-27)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, VERS = 0.70, HASTE = 0.60, CRIT = 0.50, MASTERY = 0.40 },
		},
		[261] = { -- Subtlety (snapshot 2025-09-06)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, MASTERY = 0.70, VERS = 0.60, CRIT = 0.50, HASTE = 0.40 },
		},
		-- Priest
		[256] = { -- Discipline, Voidweaver (snapshot 2025-10-10)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, MASTERY = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		[257] = { -- Holy Priest, raids (snapshot 2025-09-16)
			label = "guide priority, War Within S3",
			weights = { INT = 1, CRIT = 0.70, MASTERY = 0.70, VERS = 0.50, HASTE = 0.40 },
		},
		[258] = { -- Shadow, single target (snapshot 2025-09-19)
			label = "guide priority, War Within S3",
			weights = { INT = 1, MASTERY = 0.70, HASTE = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		-- Death Knight
		[250] = { -- Blood, Deathbringer (snapshot 2025-08-15)
			label = "guide priority, War Within S3",
			weights = { STR = 1, CRIT = 0.70, VERS = 0.70, MASTERY = 0.70, HASTE = 0.40 },
		},
		[251] = { -- Frost Death Knight (snapshot 2025-10-05)
			label = "guide priority, War Within S3",
			weights = { STR = 1, MASTERY = 0.70, CRIT = 0.60, HASTE = 0.50, VERS = 0.40 },
		},
		[252] = { -- Unholy (snapshot 2025-09-09)
			label = "guide priority, War Within S3",
			weights = { STR = 1, HASTE = 0.70, MASTERY = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		-- Shaman
		[262] = { -- Elemental: the page gives a single-target spread instead of a list, Mastery 40%, Haste 25%,
			-- Versatility 25%, Crit 10% (snapshot 2025-09-10)
			label = "guide priority, War Within S3",
			weights = { INT = 1, MASTERY = 0.70, HASTE = 0.60, VERS = 0.60, CRIT = 0.40 },
		},
		[263] = { -- Enhancement, Stormbringer (snapshot 2025-10-06)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, HASTE = 0.70, MASTERY = 0.60, CRIT = 0.50, VERS = 0.40 },
		},
		[264] = { -- Restoration Shaman, general healing (snapshot 2025-09-15)
			label = "guide priority, War Within S3",
			weights = { INT = 1, CRIT = 0.70, VERS = 0.60, HASTE = 0.50, MASTERY = 0.50 },
		},
		-- Mage
		[62] = { -- Arcane (snapshot 2025-09-18)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, VERS = 0.60, MASTERY = 0.50, CRIT = 0.40 },
		},
		[63] = { -- Fire (snapshot 2025-09-01)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, MASTERY = 0.60, VERS = 0.50, CRIT = 0.40 },
		},
		[64] = { -- Frost Mage (snapshot 2025-11-12)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, CRIT = 0.60, MASTERY = 0.50, VERS = 0.40 },
		},
		-- Warlock
		[265] = { -- Affliction (snapshot 2025-12-14)
			label = "guide priority, War Within S3",
			weights = { INT = 1, MASTERY = 0.70, CRIT = 0.70, HASTE = 0.50, VERS = 0.40 },
		},
		[266] = { -- Demonology (snapshot 2025-09-13)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, CRIT = 0.70, MASTERY = 0.50, VERS = 0.40 },
		},
		[267] = { -- Destruction (snapshot 2025-09-18)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, CRIT = 0.70, MASTERY = 0.50, VERS = 0.40 },
		},
		-- Monk
		[268] = { -- Brewmaster, defensive (snapshot 2025-11-07)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, VERS = 0.70, MASTERY = 0.70, CRIT = 0.70, HASTE = 0.40 },
		},
		[269] = { -- Windwalker (snapshot 2025-09-03)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, MASTERY = 0.70, HASTE = 0.70, VERS = 0.50, CRIT = 0.50 },
		},
		[270] = { -- Mistweaver, raiding (snapshot 2025-10-05)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, CRIT = 0.60, VERS = 0.50, MASTERY = 0.40 },
		},
		-- Druid
		[102] = { -- Balance (snapshot 2025-10-07)
			label = "guide priority, War Within S3",
			weights = { INT = 1, MASTERY = 0.70, HASTE = 0.60, VERS = 0.50, CRIT = 0.40 },
		},
		[103] = { -- Feral, single target (snapshot 2025-10-12)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, MASTERY = 0.70, CRIT = 0.70, HASTE = 0.50, VERS = 0.50 },
		},
		[104] = { -- Guardian, survivability (snapshot 2025-10-17)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, HASTE = 0.70, VERS = 0.60, MASTERY = 0.50, CRIT = 0.40 },
		},
		[105] = { -- Restoration Druid, raid healing (snapshot 2025-09-09)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, MASTERY = 0.70, VERS = 0.50, CRIT = 0.40 },
		},
		-- Demon Hunter
		[577] = { -- Havoc, Aldrachi Reaver (snapshot 2025-11-10)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, CRIT = 0.70, MASTERY = 0.60, HASTE = 0.50, VERS = 0.40 },
		},
		[581] = { -- Vengeance (snapshot 2025-09-10)
			label = "guide priority, War Within S3",
			weights = { AGI = 1, HASTE = 0.70, CRIT = 0.70, VERS = 0.50, MASTERY = 0.40 },
		},
		-- Evoker
		[1467] = { -- Devastation (snapshot 2025-12-11)
			label = "guide priority, War Within S3",
			weights = { INT = 1, HASTE = 0.70, CRIT = 0.60, MASTERY = 0.50, VERS = 0.40 },
		},
		[1468] = { -- Preservation, raiding (snapshot 2025-08-23)
			label = "guide priority, War Within S3",
			weights = { INT = 1, MASTERY = 0.70, CRIT = 0.60, HASTE = 0.50, VERS = 0.40 },
		},
		[1473] = { -- Augmentation, Chronowarden, without the Motes of Possibility Mastery bump (snapshot 2025-08-15)
			label = "guide priority, War Within S3",
			weights = { INT = 1, CRIT = 0.70, HASTE = 0.60, MASTERY = 0.50, VERS = 0.40 },
		},
	},
	-- Algari gems, rank 3 (max quality); item IDs from the ItemSparse table on wago.tools.
	-- Emerald = Haste, Onyx = Mastery, Ruby = Crit, Sapphire = Vers.
	gems = {
		213488, 213479, 213482, 213485, -- Emerald: Quick, Deadly, Masterful, Versatile
		213500, 213491, 213494, 213497, -- Onyx: Masterful, Deadly, Quick, Versatile
		213464, 213455, 213458, 213461, -- Ruby: Deadly, Quick, Masterful, Versatile
		213476, 213467, 213470, 213473, -- Sapphire: Versatile, Deadly, Quick, Masterful
	},
	-- Blasphemite diamonds (Unique-Equipped: Algari Diamond (1)), all three ranks. Main stat with an effect:
	-- never ranked, only pointed out when none is worn.
	diamonds = {
		213741, 213742, 213743, -- Culminating
		213738, 213739, 213740, -- Insightful
		213744, 213745, 213746, -- Elusive
	},
	diamondName = "Blasphemite",
})
