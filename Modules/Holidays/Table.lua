local addonName, ns = ...

-- Holidays & events: facts, kept by hand (Generated.lua is the generated part). tools/events.py reads each entry's
-- `currencies` and `icons` from this file with a regex: keep every entry starting with `key = "..."`, both lists on
-- one `{ ... }` each with no nested braces, and the Darkmoon quest table after every holiday entry (the script stops
-- reading at its name, so don't write that name in a comment above it).
-- Holiday IDs and texture fileIDs (start, ongoing, end) from the client's Holidays table,
-- achievement categories from Achievement_Category (World Events, 155), LFG dungeons from LFGDungeons (wago.tools).
-- icon: a square icon fileID (wowdev community listfile) shown in rows and toasts; the calendar textures are banner
-- art (the ongoing one is a near-empty strip), so they only identify the holiday.
-- icons: cost-icon paths (lower case, no .blp) that holiday vendors' source text carries, language-free.
-- maps: uiMapIDs whose localized name counts as the holiday's name in source text.
-- extra: mounts and pets whose source text doesn't name the holiday (from tools/events.py's report).
-- Pilgrim's Bounty shares its textures with the old Harvest Festival, so it's matched by ID only.

ns.EVENTS_DEFS = {
	{ key = "darkmoon", ids = { 479 }, textures = { 235446, 235447, 235448 }, category = 15101, currencies = { 515 },
		icon = 134481, icons = { "interface\\icons\\inv_misc_ticket_darkmoon_01" }, maps = { 407 } },
	-- No cost icon for the Lunar Festival: its Coin of Ancestry icon (inv_misc_elvencoins) is also the cost icon of
	-- non-holiday vendors (Dornogal, Silvermoon). Its items name the festival anyway.
	{ key = "lunar", ids = { 327 }, textures = { 235469, 235470, 235471 }, category = 160, icon = 236704 },
	{ key = "love", ids = { 423 }, textures = { 235466, 235467, 235468 }, category = 187, icon = 236709,
		icons = { "interface\\icons\\inv_valentinescard01" }, lfg = { 288 } },
	{ key = "noblegarden", ids = { 181 }, textures = { 235475, 235476, 235477 }, category = 159, icon = 236570,
		icons = { "interface\\icons\\achievement_noblegarden_chocolate_egg" } },
	{ key = "childrens", ids = { 201 }, textures = { 235443, 235444, 235445 }, category = 163, icon = 236702 },
	{ key = "midsummer", ids = { 341 }, textures = { 235472, 235473, 235474 }, category = 161, icon = 135263,
		icons = { "interface\\icons\\inv_summerfest_fireflower" }, lfg = { 286 } },
	{ key = "pirates", ids = { 398 }, textures = { 235481 }, icon = 133168 },
	{ key = "brewfest", ids = { 372 }, textures = { 235440, 235441, 235442 }, category = 162, icon = 236701,
		lfg = { 287 } },
	{ key = "hallows", ids = { 324 }, textures = { 235460, 235461, 235462 }, category = 158, icon = 236546,
		icons = { "interface\\icons\\achievement_halloween_candy_01" }, lfg = { 285 },
		extra = { pet = { 3491 } } }, -- Lick King: "Drop: Headless Horseman"
	{ key = "dead", ids = { 409 }, textures = { 307364, 307365, 840589 }, icon = 237272 },
	{ key = "pilgrims", ids = { 404 }, textures = {}, category = 14981, icon = 236708 },
	{ key = "winterveil", ids = { 141 }, textures = { 235482, 235484, 235485 }, category = 156, icon = 236705 },
}

-- Timewalking gets new holiday IDs every season: it's found through the Dungeon Finder instead.
ns.EVENTS_TIMEWALKING = { key = "timewalking", category = 15454, currencies = { 1166 }, icon = 463446,
	icons = { "interface\\icons\\pvecurrency-justice" } }

-- Weekly bonus events have no entry above (nothing to collect): they only get an icon, by calendar texture
-- (interface/calendar/holidays/calendar_<name>start/ongoing/end in the community listfile).
ns.EVENTS_WEEKLY_ICONS = {
	{ icon = 6025441, textures = { 6033780, 6033781 } }, -- Delves: ui_delves
	{ icon = 236396, textures = { 1616334, 1617308, 4272905 } }, -- PvP Brawl: achievement_bg_winwsg
	{ icon = 236396, textures = { 1129669, 1129670, 1129671 } }, -- Battlegrounds
	{ icon = 236329, textures = { 1129678, 1129679, 1129680 } }, -- Arena skirmishes: achievement_arena_2v2_7
	{ icon = 643856, textures = { 1129675, 1129676, 1129677 } }, -- Pet battles: inv_pet_battlepettraining
	{ icon = 134269, textures = { 1467048, 1467049, 1467050 } }, -- World quests: inv_misc_map_01
	{ icon = 133594, textures = { 1129666, 1129667, 1129668 } }, -- Apexis: inv_misc_apexis_crystal
}

-- Darkmoon Faire profession quests, [TradeSkillLineID] = questID, all checked against warcraft.wiki.gg's quest pages
-- (/tomte events ids prints the names the game gives them).
ns.EVENTS_DARKMOON_QUESTS = {
	[171] = 29506, [794] = 29507, [164] = 29508, [185] = 29509, [333] = 29510, [202] = 29511, [356] = 29513,
	[182] = 29514, [773] = 29515, [755] = 29516, [165] = 29517, [186] = 29518, [393] = 29519, [197] = 29520,
}
