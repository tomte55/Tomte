local addonName, ns = ...

-- Midnight (expansion 11): pet battle tamers. See Core/Content.lua; merged in Modules/Pets/Tamers.lua. Sources and
-- fields as in Data/WarWithin/Pets.lua. Midnight added no tamers in its own zones (Xu-Fu news 581, 2025-11-11: "No new
-- tamers will be added to the upcoming/revamped zones"; Xu-Fu's Midnight menu checked 2026-10-19): its pet battle
-- content is these Family Battler achievements for old-world tamers. The author doesn't own Midnight: shipped
-- untested for a Midnight owner.

local E = 11

ns.Content_Register(E, "petSections", {
	{ id = 114, name = "Eastern Kingdoms Family Battler", kind = "family" },
	{ id = 115, name = "Kalimdor Family Battler", kind = "family" },
	{ id = 116, name = "Northrend Family Battler", kind = "family" },
	{ id = 117, name = "Outland Family Battler", kind = "family" },
	{ id = 118, name = "Cataclysm Family Battler", kind = "family" },
})

ns.Content_Register(E, "petEncounters", {
	-- [Xu-Fu encounter id] = { section, name, npcs = { npcID, ... } }

	-- Eastern Kingdoms Family Battler
	[2090] = { section = 114, name = "Julia Stevens", npcs = { 64330 } },
	[2091] = { section = 114, name = "Old MacDonald", npcs = { 65648 } },
	[2092] = { section = 114, name = "Lindsay", npcs = { 65651 } },
	[2093] = { section = 114, name = "Eric Davidson", npcs = { 65655 } },
	[2094] = { section = 114, name = "Steven Lisbane", npcs = { 63194 } },
	[2095] = { section = 114, name = "Bill Buckler", npcs = { 65656 } },
	[2096] = { section = 114, name = "David Kosse", npcs = { 66478 } },
	[2097] = { section = 114, name = "Deiza Plaguehorn", npcs = { 66512 } },
	[2098] = { section = 114, name = "Kortas Darkhammer", npcs = { 66515 } },
	[2099] = { section = 114, name = "Durin Darkhammer", npcs = { 66520 } },
	[2100] = { section = 114, name = "Everessa", npcs = { 66518 } },
	[2101] = { section = 114, name = "Lydia Accoste", npcs = { 66522 } },

	-- Kalimdor Family Battler
	[2222] = { section = 115, name = "Zunta", npcs = { 66126 } },
	[2223] = { section = 115, name = "Dagra the Fierce", npcs = { 66135 } },
	[2224] = { section = 115, name = "Analynn", npcs = { 66136 } },
	[2225] = { section = 115, name = "Zonya the Sadist", npcs = { 66137 } },
	[2226] = { section = 115, name = "Merda Stronghoof", npcs = { 66372 } },
	[2227] = { section = 115, name = "Traitor Gluk", npcs = { 66352 } },
	[2228] = { section = 115, name = "Elena Flutterfly", npcs = { 66412 } },
	[2229] = { section = 115, name = "Cassandra Kaboom", npcs = { 66422 } },
	[2230] = { section = 115, name = "Grazzle the Great", npcs = { 66436 } },
	[2231] = { section = 115, name = "Zoltan", npcs = { 66442 } },
	[2232] = { section = 115, name = "Kela Grimtotem", npcs = { 66452 } },
	[2233] = { section = 115, name = "Stone Cold Trixxy", npcs = { 66466 } },

	-- Northrend Family Battler
	[2354] = { section = 116, name = "Gutretch", npcs = { 66639 } },
	[2355] = { section = 116, name = "Nearly Headless Jacob", npcs = { 66636 } },
	[2356] = { section = 116, name = "Major Payne", npcs = { 66675 } },
	[2357] = { section = 116, name = "Okrut Dragonwaste", npcs = { 66638 } },
	[2358] = { section = 116, name = "Beegle Blastfuse", npcs = { 66635 } },

	-- Outland Family Battler
	[2409] = { section = 117, name = "Nicki Tinytech", npcs = { 66550 } },
	[2410] = { section = 117, name = "Ras'an", npcs = { 66551 } },
	[2411] = { section = 117, name = "Narrok", npcs = { 66562 } },
	[2412] = { section = 117, name = "Morulu The Elder", npcs = { 66553 } },
	[2413] = { section = 117, name = "Bloodknight Antari", npcs = { 66557 } },

	-- Cataclysm Family Battler
	[2464] = { section = 118, name = "Brok", npcs = { 66819 } },
	[2465] = { section = 118, name = "Bordin Steadyfist", npcs = { 66815 } },
	[2466] = { section = 118, name = "Goz Banefury", npcs = { 66822 } },
	[2467] = { section = 118, name = "Obalis", npcs = { 66824 } },
})
