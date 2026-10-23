local addonName, ns = ...

-- Midnight (expansion 11): Resilient Seeds for Gathering's seed button (Modules/Gather/Seeds.lua). Herbalists plant
-- them in Rich Soil spots near water in the Midnight zones; each seed has its own plant spell.
-- Seed item and spell IDs: the client's ItemSparse and SpellName tables (wago.tools, build 12.1.5.70391); the item to
-- spell pairs and the zone map IDs as listed by Plumber (IDs are facts). Rich Soil spots are game objects the server
-- places, so no client table lists them: Tomte learns a spot's object ID the first time you plant a seed right after
-- pointing at one (saved in TomteDB.gather.soil); IDs confirmed in game can be added to soil below.

ns.Content_Register(11, "seeds", {
	items = { -- in the order the buttons show
		{ item = 237497, spell = 1223244 }, -- Resilient Seed (Plant Midnight Seed)
		{ item = 237498, spell = 1224738 }, -- Glowing Resilient Seed
		{ item = 237499, spell = 1224759 }, -- Wild Resilient Seed
		{ item = 237500, spell = 1224758 }, -- Primal Resilient Seed
	},
	maps = { -- uiMapIDs where Rich Soil grows
		[2395] = true, -- Eversong Woods
		[2413] = true, -- Harandar
		[2437] = true, -- Zul'Aman
		[2512] = true, -- The Coiled Isle
		[2536] = true, -- Atal'Aman
	},
	soil = {}, -- [Rich Soil game object ID] = true, confirmed in game
})
