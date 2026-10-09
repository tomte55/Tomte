local addonName, ns = ...

-- Midnight (expansion 11): Weekly data. See Core/Content.lua. IDs from Plumber (GPLv3; IDs only, checked 2026-10-09:
-- ExpansionLandingPage/EncounterData.lua, Retail/MID_Activity.lua, Retail/ResourceList.lua, FactionUtil.lua,
-- Shared/SharedData.lua) and WeeklyKnowledge (profession knowledge, checked 2026-10-04). The author doesn't own
-- Midnight: a friend checks these with /tomte data.

local E = 11

-- Raids tab fallback (the Encounter Journal's tier is read first): journal instance IDs, newest first.
ns.Content_Register(E, "raids", {
	1317, -- The Tidebound Grotto
	1320, -- The Venomous Abyss
	1305, -- Sporefall
	1314, -- The Dreamrift
	1307, -- The Voidspire
	1308, -- March on Quel'Danas
})

-- Activities tab: what never shows in the quest log. "A Gnawing Void of Curiosity" 93784 (account-wide delve
-- weekly), Trovehunter's Bounty used this week 86371. Faction weeklies show up as learned quests by themselves.
ns.Content_Register(E, "activities", {
	{ group = "Delves", entries = {
		{ label = "A Gnawing Void of Curiosity", quest = 93784, account = true },
		{ label = "Trovehunter's Bounty", quest = 86371 },
	} },
})

-- Activities tab Resources list (shown when discovered), after the crests. Catalyst charges: 3378 in 12.0, 3465 in
-- 12.1 (only the discovered one shows).
ns.Content_Register(E, "resources", { 3418, 3465, 3378, 3448, 3028, 3310, 3316, 3363, 3405, 3546, 3392, 2803, 3379,
	3376, 3377, 2123, 2797 })

-- Factions tab: sub-factions under their renown faction.
ns.Content_Register(E, "subfactions", {
	[2710] = { -- Silvermoon Court
		{ id = 2711, display = 69626 }, -- Magisters
		{ id = 2712, display = 113966 }, -- Blood Knights
		{ id = 2713, display = 140633 }, -- Farstriders
		{ id = 2714, display = 140691 }, -- Shades of the Row
	},
	[2772] = { -- Zul'jarra's Forces
		{ id = 2773, display = 145432 }, -- Tokka
	},
})

-- Crest sets, newest first, each lowest tier first (Adventurer, Veteran, Champion, Hero, Myth; names checked on
-- Wowhead 2026-10-09). The first set the character has any of is shown.
ns.Content_Register(E, "crests", {
	{ label = "Mistcrests", ids = { 3442, 3443, 3444, 3445, 3446 } }, -- 12.1 (season 2)
	{ label = "Dawncrests", ids = { 3383, 3341, 3343, 3345, 3347 } }, -- 12.0 (season 1)
})

-- Profession knowledge: see Data/WarWithin/Weekly.lua for the fields.
ns.Content_Register(E, "profs", {
	[171] = { name = "Alchemy", child = 2906, trainer = { 93690 }, trainerPts = 1, treatise = 95127,
		treasures = { 93528, 93529 }, treasurePts = 1 },
	[164] = { name = "Blacksmithing", child = 2907, trainer = { 93691 }, trainerPts = 2, treatise = 95128,
		treasures = { 93530, 93531 }, treasurePts = 2 },
	[333] = { name = "Enchanting", child = 2909, trainer = { 93697, 93698, 93699 }, trainerPts = 3,
		at = { 47.8, 53.8, "Dolothos, the Enchanting trainer" }, treatise = 95129, treasures = { 93532, 93533 },
		treasurePts = 2, drops = { 95048, 95049, 95050, 95051, 95052 }, bigDrop = 95053, bigPts = 4,
		from = "disenchanting" },
	[202] = { name = "Engineering", child = 2910, trainer = { 93692 }, trainerPts = 1, treatise = 95138,
		treasures = { 93534, 93535 }, treasurePts = 1 },
	[182] = { name = "Herbalism", child = 2912, gathering = true, trainer = { 93700, 93701, 93702, 93703, 93704 },
		trainerPts = 3, at = { 48.2, 51.6, "Botanist Nathera, the Herbalism trainer" }, treatise = 95130,
		drops = { 81425, 81426, 81427, 81428, 81429 }, bigDrop = 81430, bigPts = 4, from = "picking herbs" },
	[773] = { name = "Inscription", child = 2913, trainer = { 93693 }, trainerPts = 4, treatise = 95131,
		treasures = { 93536, 93537 }, treasurePts = 2 },
	[755] = { name = "Jewelcrafting", child = 2914, trainer = { 93694 }, trainerPts = 3, treatise = 95133,
		treasures = { 93538, 93539 }, treasurePts = 2 },
	[165] = { name = "Leatherworking", child = 2915, trainer = { 93695 }, trainerPts = 2, treatise = 95134,
		treasures = { 93540, 93541 }, treasurePts = 2 },
	[186] = { name = "Mining", child = 2916, gathering = true, trainer = { 93705, 93706, 93707, 93708, 93709 },
		trainerPts = 3, at = { 42.6, 52.8, "Belil, the Mining trainer" }, treatise = 95135,
		drops = { 88673, 88674, 88675, 88676, 88677 }, bigDrop = 88678, bigPts = 3, from = "mining" },
	[393] = { name = "Skinning", child = 2917, gathering = true, trainer = { 93710, 93711, 93712, 93713, 93714 },
		trainerPts = 3, at = { 43.2, 55.6, "Tyn, the Skinning trainer" }, treatise = 95136,
		drops = { 88534, 88549, 88537, 88536, 88530 }, bigDrop = 88529, bigPts = 3, from = "skinning" },
	[197] = { name = "Tailoring", child = 2918, trainer = { 93696 }, trainerPts = 2, treatise = 95137,
		treasures = { 93542, 93543 }, treasurePts = 2 },
})

ns.Content_Register(E, "profPlaces", { city = "Silvermoon City", map = 2393, zone = "Midnight's zones",
	treatise = "Thalassian Treatise on %s", consortium = { 45.0, 55.2, "the Artisan's Consortium" },
	orders = { 45.0, 55.6 } })
