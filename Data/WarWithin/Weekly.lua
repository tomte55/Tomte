local addonName, ns = ...

-- The War Within (expansion 10): Weekly data. See Core/Content.lua. IDs from Plumber (GPLv3; IDs only, checked
-- 2026-10-08) and WeeklyKnowledge (profession knowledge, checked 2026-10-04) unless noted.

local E = 10

-- Raids tab fallback (the Encounter Journal's tier is read first): journal instance IDs, newest first.
ns.Content_Register(E, "raids", { 1302, 1296, 1273 }) -- Manaforge Omega, Liberation of Undermine, Nerub-ar Palace

-- Activities tab: what never shows in the quest log. Coffer Key flags 91175-91178, Coffer Key Shard flags
-- 84736-84739, "The Key to Success" 84370 (account-wide), Worldsoul weekly quest line 5572.
ns.Content_Register(E, "activities", {
	{ group = "Delves", entries = {
		{ label = "The Key to Success", quest = 84370, account = true },
		{ label = "Restored Coffer Keys", flags = { 91175, 91176, 91177, 91178 } },
		{ label = "Coffer Key Shards", flags = { 84736, 84737, 84738, 84739 } },
	} },
	{ group = "Dornogal", entries = {
		{ label = "Worldsoul weekly", questLine = 5572 },
	} },
})

-- Activities tab Resources list (shown when discovered), after the crests.
ns.Content_Register(E, "resources", { 3269, 3028, 3149, 2815, 3218, 3226, 3090, 3056, 2803, 2123, 2797 })

-- Factions tab: sub-factions under their renown faction. unlock = an account quest that has to be done first.
ns.Content_Register(E, "subfactions", {
	[2653] = { -- Cartels of Undermine
		{ id = 2669, icon = 6439629, unlock = 86961 }, -- Darkfuse Solutions, after "Diversified Investments"
		{ id = 2673, icon = 6439627 }, -- Bilgewater
		{ id = 2677, icon = 6439630 }, -- Steamwheedle
		{ id = 2675, icon = 6439628 }, -- Blackwater
		{ id = 2671, icon = 6439631 }, -- Venture Company
	},
	[2600] = { -- The Severed Threads
		{ id = 2601, display = 116208 }, -- The Weaver
		{ id = 2605, display = 114775 }, -- The General
		{ id = 2607, display = 114268 }, -- The Vizier
	},
})

-- Crest sets, newest first, each lowest tier first. Season 3 Ethereal crests (Weathered 3284, Carved 3286, Runed
-- 3288, Gilded 3290; names checked on Wowhead 2026-10-09). Before 2026-10-09 every account listed Midnight's
-- Mistcrests, which a War Within account never discovers, so no crests showed.
ns.Content_Register(E, "crests", {
	{ label = "Ethereal crests", ids = { 3284, 3286, 3288, 3290 } },
})

-- Base skill line (GetProfessionInfo) -> this expansion's skill line, its weekly knowledge quests and what each is
-- worth. trainerPts / treasurePts (each) / bigPts are knowledge points (drops and treatises give 1). at = { x, y, who }
-- for a trainer quest that isn't from the Artisan's Consortium.
ns.Content_Register(E, "profs", {
	[171] = { name = "Alchemy", child = 2871, trainer = { 84133 }, trainerPts = 2, treatise = 83725,
		treasures = { 83253, 83255 }, treasurePts = 2 },
	[164] = { name = "Blacksmithing", child = 2872, trainer = { 84127 }, trainerPts = 2, treatise = 83726,
		treasures = { 83256, 83257 }, treasurePts = 1 },
	[333] = { name = "Enchanting", child = 2874, trainer = { 84084, 84085, 84086 }, trainerPts = 3,
		at = { 52.8, 71.2, "your Enchanting trainer" }, treatise = 83727, treasures = { 83258, 83259 }, treasurePts = 1,
		drops = { 84290, 84291, 84292, 84293, 84294 }, bigDrop = 84295, bigPts = 4, from = "disenchanting" },
	[202] = { name = "Engineering", child = 2875, trainer = { 84128 }, trainerPts = 1, treatise = 83728,
		treasures = { 83260, 83261 }, treasurePts = 1 },
	[182] = { name = "Herbalism", child = 2877, gathering = true, trainer = { 82916, 82958, 82962, 82965, 82970 },
		trainerPts = 3, at = { 44.8, 69.4, "your Herbalism trainer" }, treatise = 83729,
		drops = { 81416, 81417, 81418, 81419, 81420 }, bigDrop = 81421, bigPts = 4, from = "picking herbs" },
	[773] = { name = "Inscription", child = 2878, trainer = { 84129 }, trainerPts = 2, treatise = 83730,
		treasures = { 83262, 83264 }, treasurePts = 2 },
	[755] = { name = "Jewelcrafting", child = 2879, trainer = { 84130 }, trainerPts = 2, treatise = 83731,
		treasures = { 83265, 83266 }, treasurePts = 2 },
	[165] = { name = "Leatherworking", child = 2880, trainer = { 84131 }, trainerPts = 2, treatise = 83732,
		treasures = { 83267, 83268 }, treasurePts = 1 },
	[186] = { name = "Mining", child = 2881, gathering = true, trainer = { 83102, 83103, 83104, 83105, 83106 },
		trainerPts = 3, at = { 52.6, 52.6, "your Mining trainer" }, treatise = 83733,
		drops = { 83050, 83051, 83052, 83053, 83054 }, bigDrop = 83049, bigPts = 3, from = "mining" },
	[393] = { name = "Skinning", child = 2882, gathering = true, trainer = { 82992, 82993, 83097, 83098, 83100 },
		trainerPts = 3, at = { 54.4, 57.6, "your Skinning trainer" }, treatise = 83734,
		drops = { 81459, 81460, 81461, 81462, 81463 }, bigDrop = 81464, bigPts = 2, from = "skinning" },
	[197] = { name = "Tailoring", child = 2883, trainer = { 84132 }, trainerPts = 2, treatise = 83735,
		treasures = { 83269, 83270 }, treasurePts = 1 },
})

-- Where the profession weeklies happen (map IDs from WeeklyKnowledge; coordinates in percent).
ns.Content_Register(E, "profPlaces", { city = "Dornogal", map = 2339, zone = "Khaz Algar",
	treatise = "Algari Treatise on %s", consortium = { 59.2, 55.6, "Kala Clayhoof at the Artisan's Consortium" },
	orders = { 58.0, 56.4 } })
