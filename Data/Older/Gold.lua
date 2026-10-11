local addonName, ns = ...

-- Older expansions with world quests (Legion to Dragonflight): only the zones the Gold world quests window scans when
-- picked in its expansion menu (Modules/GoldQuests). No special assignments or weekly caches. Map IDs from UiMap on
-- wago.tools (build 69933).

ns.Content_Register(6, "goldZones", { -- Legion
	630, -- Azsuna
	641, -- Val'sharah
	650, -- Highmountain
	634, -- Stormheim
	680, -- Suramar
	646, -- Broken Shore
	790, -- Eye of Azshara
	830, -- Krokuun
	885, -- Antoran Wastes
	882, -- Eredath
})

ns.Content_Register(7, "goldZones", { -- Battle for Azeroth
	895, -- Tiragarde Sound
	896, -- Drustvar
	942, -- Stormsong Valley
	1462, -- Mechagon Island
	862, -- Zuldazar
	863, -- Nazmir
	864, -- Vol'dun
	1355, -- Nazjatar
	1527, -- Uldum (N'Zoth assaults)
	1530, -- Vale of Eternal Blossoms (N'Zoth assaults)
})

ns.Content_Register(8, "goldZones", { -- Shadowlands
	1533, -- Bastion
	1536, -- Maldraxxus
	1565, -- Ardenweald
	1525, -- Revendreth
	1543, -- The Maw
	1961, -- Korthia
	1970, -- Zereth Mortis
})

ns.Content_Register(9, "goldZones", { -- Dragonflight
	2022, -- The Waking Shores
	2023, -- Ohn'ahran Plains
	2024, -- The Azure Span
	2025, -- Thaldraszus
	2151, -- The Forbidden Reach
	2133, -- Zaralek Cavern
	2200, -- Emerald Dream
})
