local addonName, ns = ...

-- The War Within (expansion 10): Gold world quests data (Modules/GoldQuests). See Core/Content.lua. Map IDs from
-- UiMap on wago.tools (build 69933). Special assignment and weekly quest IDs from WeeklyRewards by cybertk (MIT,
-- DB/TWW.lua, checked 2026-10-11); the 11.0 Khaz Algar special assignment quest IDs from Plumber (GPLv3, IDs only,
-- Modules/MapPin_TWW_Quest.lua).

local E = 10

-- Zones scanned for world quests. Child zones (City of Threads, Undermine, Tazavesh) are listed too: a parent's map
-- doesn't always return its children's quests.
ns.Content_Register(E, "goldZones", {
	2248, -- Isle of Dorn
	2214, -- The Ringing Deeps
	2346, -- Undermine
	2215, -- Hallowfall
	2255, -- Azj-Kahet
	2213, -- City of Threads
	2369, -- Siren Isle
	2371, -- K'aresh
	2472, -- Tazavesh
})

-- Special assignments: quest = the assignment, unlock = the placeholder quest shown while it's locked (its objective
-- counts the world quests still needed), zone = the map it's in. Entries without unlock are only shown while up or
-- after you turned them in this week; without zone the game says where.
ns.Content_Register(E, "assignments", {
	{ quest = 85487, unlock = 85489, zone = 2346 }, -- Boom! Headshot!
	{ quest = 85488, unlock = 85490, zone = 2346 }, -- Security Detail
	{ quest = 89293, unlock = 91193, zone = 2371 }, -- Overshadowed
	{ quest = 89294, unlock = 91203, zone = 2371 }, -- Aligned Views
	{ quest = 85113, zone = 2369 }, -- Storm's a Brewin
	{ quest = 82355 }, -- Cinderbee Surge
	{ quest = 81647 }, -- Titanic Resurgence
	{ quest = 81649 }, -- Titanic Resurgence
	{ quest = 81650 }, -- Titanic Resurgence
	{ quest = 81691 }, -- Shadows Below
	{ quest = 83229 }, -- When the Deeps Stir
	{ quest = 82852 }, -- Lynx Rescue
	{ quest = 82787 }, -- Rise of the Colossals
	{ quest = 82531 }, -- Bombs from Behind
	{ quest = 82414 }, -- A Pound of Cure
})

-- Weekly caches: key (saved), label (English fallback), quests (any of them done counts), title = a quest whose
-- name is the row's name (else the first quest's), item = the cache it gives (its name is the row's name).
ns.Content_Register(E, "caches", {
	{ key = "worldsoul", label = "The Call of the Worldsoul", title = 82449, quests = {
		82511, 82453, 82516, 82458, 82482, 82483, 82512, 82452, 82491, 82494, 82502, 82485, 82495, 82503, 82492, 82496,
		82504, 82488, 82498, 82506, 82490, 82499, 82507, 82489, 82493, 82501, 82486, 82500, 82508, 82487, 82497, 82505,
		82509, 82659, 82510, 87417, 87419, 87422, 87423, 87424, 89514, 91855,
	} },
	{ key = "archives", label = "Archives: Seeking History", quests = { 82679 } },
	{ key = "delves", label = "Delves: Worldwide Research", quests = { 82706 } },
	{ key = "light", label = "Spreading the Light", quests = { 76586 } },
	{ key = "pact", label = "Azj-Kahet pact weekly", quests = { 80670, 80671, 80672 } },
	{ key = "troupe", label = "The Theater Troupe", quests = { 83240 } },
	{ key = "machine", label = "Gearing Up for Trouble", quests = { 83333 } },
	{ key = "wax", label = "Rollin' Down in the Deeps", quests = { 82946 } },
	{ key = "surge", label = "Urge to Surge", quests = { 86775 } },
	{ key = "shipping", label = "Many Jobs, Handle It!", quests = { 85869 } },
	{ key = "scrap", label = "Reduce, Reuse, Resell", quests = { 85879 } },
	{ key = "nightfall", label = "The Flame Burns Eternal", quests = { 91173 } },
	{ key = "oasis", label = "Ecological Succession", quests = { 85460 } },
	{ key = "diving", label = "More Than Just a Phase", quests = { 91093 } },
})
