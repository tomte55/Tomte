local addonName, ns = ...

-- Midnight (expansion 11): Gold world quests data (Modules/GoldQuests). See Core/Content.lua and the War Within file
-- for the fields. Zones as GoldWQ scans them (map IDs checked against UiMap on wago.tools, build 69933); special
-- assignment and weekly quest IDs from WeeklyRewards by cybertk (MIT, DB/Midnight.lua, checked 2026-10-11); cache
-- item IDs from GoldWQ (IDs only). The author doesn't own Midnight: a friend checks these in game.

local E = 11

ns.Content_Register(E, "goldZones", {
	2395, -- Eversong Woods
	2393, -- Silvermoon City
	2437, -- Zul'Aman
	2413, -- Harandar
	2405, -- Voidstorm
	2512, -- The Coiled Isle
})

ns.Content_Register(E, "assignments", {
	{ quest = 92145, unlock = 92848, zone = 2395 }, -- The Grand Magister's Drink
	{ quest = 92139, unlock = 95435, zone = 2395 }, -- Shade and Claw
	{ quest = 91390, unlock = 94865, zone = 2437 }, -- What Remains of a Temple Broken
	{ quest = 91796, unlock = 94866, zone = 2437 }, -- Ours Once More!
	{ quest = 92063, unlock = 94390, zone = 2413 }, -- A Hunter's Regret
	{ quest = 93013, unlock = 94391, zone = 2413 }, -- Push Back the Light
	{ quest = 93438, unlock = 94743, zone = 2405 }, -- Precision Excision
	{ quest = 93244, unlock = 94795, zone = 2405 }, -- Agents of the Shield
	{ quest = 95918, unlock = 96307, zone = 2512 }, -- Wraith Wrath
	{ quest = 95921, unlock = 96492, zone = 2512 }, -- Demand and Supply
	{ quest = 95922, unlock = 96029, zone = 2512 }, -- Face the Swarm
})

ns.Content_Register(E, "caches", {
	{ key = "unity", label = "Unity Against the Void", item = 279527, quests = { 93744 } }, -- Apex Cache, every 2 weeks
	{ key = "trailing", label = "Trailing Xal'atath", quests = { 98172 } }, -- every 2 weeks
	{ key = "abundance", label = "Abundant Offerings", item = 279523, quests = { 89507 } },
	{ key = "legends", label = "Echoes Rekindled", item = 279525, quests = {
		92713, 92716, 92719, 92720, 92721, 92722, 92724, 92725,
	} },
	{ key = "soiree", label = "Fortify the Runestones", item = 279522, quests = { 90573, 90574, 90575, 90576 } },
	{ key = "stormarion", label = "Stormarion Assault", item = 279526, quests = { 90962 } },
	{ key = "surge", label = "Turn Back the Surge", item = 275911, quests = { 96995 } },
})
