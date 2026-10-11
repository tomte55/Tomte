local addonName, ns = ...

-- Holidays & events: facts, kept by hand (Generated.lua is the generated part). tools/events.py reads each entry's
-- `currencies` and `icons` from this file with a regex: keep every entry starting with `key = "..."`, both lists on
-- one `{ ... }` each with no nested braces, and the Darkmoon quest table after every holiday entry (the script stops
-- reading at its name, so don't write that name in a comment above it).
-- Holiday IDs and texture fileIDs (start, ongoing, end) from the client's Holidays table,
-- achievement categories from Achievement_Category (World Events, 155), LFG dungeons from LFGDungeons (wago.tools).
-- icons: cost-icon paths (lower case, no .blp) that holiday vendors' source text carries, language-free.
-- maps: uiMapIDs whose localized name counts as the holiday's name in source text.
-- extra: mounts and pets whose source text doesn't name the holiday (from tools/events.py's report).
-- Pilgrim's Bounty shares its textures with the old Harvest Festival, so it's matched by ID only.

ns.EVENTS_DEFS = {
	{ key = "darkmoon", ids = { 479 }, textures = { 235446, 235447, 235448 }, category = 15101, currencies = { 515 },
		icons = { "interface\\icons\\inv_misc_ticket_darkmoon_01" }, maps = { 407 } },
	-- No cost icon for the Lunar Festival: its Coin of Ancestry icon (inv_misc_elvencoins) is also the cost icon of
	-- non-holiday vendors (Dornogal, Silvermoon). Its items name the festival anyway.
	{ key = "lunar", ids = { 327 }, textures = { 235469, 235470, 235471 }, category = 160 },
	{ key = "love", ids = { 423 }, textures = { 235466, 235467, 235468 }, category = 187,
		icons = { "interface\\icons\\inv_valentinescard01" }, lfg = { 288 } },
	{ key = "noblegarden", ids = { 181 }, textures = { 235475, 235476, 235477 }, category = 159,
		icons = { "interface\\icons\\achievement_noblegarden_chocolate_egg" } },
	{ key = "childrens", ids = { 201 }, textures = { 235443, 235444, 235445 }, category = 163 },
	{ key = "midsummer", ids = { 341 }, textures = { 235472, 235473, 235474 }, category = 161,
		icons = { "interface\\icons\\inv_summerfest_fireflower" }, lfg = { 286 } },
	{ key = "pirates", ids = { 398 }, textures = { 235481 } },
	{ key = "brewfest", ids = { 372 }, textures = { 235440, 235441, 235442 }, category = 162, lfg = { 287 } },
	{ key = "hallows", ids = { 324 }, textures = { 235460, 235461, 235462 }, category = 158,
		icons = { "interface\\icons\\achievement_halloween_candy_01" }, lfg = { 285 },
		extra = { pet = { 3491 } } }, -- Lick King: "Drop: Headless Horseman"
	{ key = "dead", ids = { 409 }, textures = { 307364, 307365, 840589 } },
	{ key = "pilgrims", ids = { 404 }, textures = {}, category = 14981 },
	{ key = "winterveil", ids = { 141 }, textures = { 235482, 235484, 235485 }, category = 156 },
}

-- Timewalking gets new holiday IDs every season: it's found through the Dungeon Finder instead.
ns.EVENTS_TIMEWALKING = { key = "timewalking", category = 15454, currencies = { 1166 },
	icons = { "interface\\icons\\pvecurrency-justice" } }

-- Darkmoon Faire profession quests, [TradeSkillLineID] = questID, all checked against warcraft.wiki.gg's quest pages
-- (/tomte events ids prints the names the game gives them).
ns.EVENTS_DARKMOON_QUESTS = {
	[171] = 29506, [794] = 29507, [164] = 29508, [185] = 29509, [333] = 29510, [202] = 29511, [356] = 29513,
	[182] = 29514, [773] = 29515, [755] = 29516, [165] = 29517, [186] = 29518, [393] = 29519, [197] = 29520,
}
