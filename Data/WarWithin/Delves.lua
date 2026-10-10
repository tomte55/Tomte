local addonName, ns = ...

-- The War Within (expansion 10): Delves data. See Core/Content.lua. Zone, POI, currency, item and faction IDs from
-- Plumber (GPLv3; IDs only, checked 2026-10-10: Modules/MapPin_Delves.lua, ExpansionLandingPage/Retail/
-- ResourceList.lua, TWW_Activity.lua). Bountiful entrances are separate POIs from the normal ones; the atlas
-- "delves-bountiful" is checked first, these IDs are the fallback, probed on their zone as Plumber does.

ns.Content_Register(10, "delves", {
	continent = 2274, -- Khaz Algar
	zones = { 2248, 2214, 2215, 2255, 2346, 2371 }, -- Isle of Dorn, Ringing Deeps, Hallowfall, Azj-Kahet, Undermine, K'aresh
	bountifulPOIs = { -- [bountiful POI] = its zone
		[7787] = 2248, [7779] = 2248, [7781] = 2248, -- Earthcrawl Mines, Fungal Folly, Kriegval's Rest
		[7788] = 2214, [7782] = 2214, [8181] = 2214, -- The Dread Pit, The Waterworks, Excavation Site 9
		[7780] = 2215, [7785] = 2215, [7789] = 2215, [7783] = 2215, -- Mycomancer Cavern, Nightfall Sanctum, Skittering Breach, The Sinkhole
		[7784] = 2255, [7790] = 2255, [7786] = 2255, -- Tak-Rethan Abyss, The Spiral Weave, The Underkeep
		[8246] = 2346, [8273] = 2371, -- Sidestreet Sluice, Archival Assault
	},
	keyCurrency = 3028, -- Restored Coffer Key
	shards = { items = { 245653, 236096 } }, -- Coffer Key Shard (season 3, earlier)
	shardsPerKey = 100,
	companionFaction = 2640, -- Brann Bronzebeard
	vaultTopTier = 8, -- fallback when the game has no season data
})
