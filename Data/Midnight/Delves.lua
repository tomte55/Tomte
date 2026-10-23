local addonName, ns = ...

-- Midnight (expansion 11): Delves data. See Core/Content.lua. Map IDs from RareScanner and Plumber, currency and
-- faction IDs from Plumber (GPLv3; IDs only, checked 2026-10-10: ExpansionLandingPage/Retail/MID_Activity.lua,
-- ResourceList.lua, FactionUtil.lua). The author doesn't own Midnight: a friend checks these with /tomte data.
-- No bountiful POI list: Midnight's bountiful entrances are found by their atlas.

ns.Content_Register(11, "delves", {
	continent = 2537, -- Quel'Thalas
	zones = { 2395, 2437, 2413, 2405, 2393 }, -- Eversong Woods, Zul'Aman, Harandar, Voidstorm, Silvermoon City
	keyCurrency = 3028, -- Restored Coffer Key
	shards = { currency = 3310 }, -- Coffer Key Shard (weekly cap from the currency)
	shardsPerKey = 100,
	companionFaction = 2744, -- Valeera Sanguinar
	vaultTopTier = 8,
	-- Gilded Stash: the widget whose spell display holds this week's "n/of" (only filled in Midnight's open world).
	-- Spell and widget IDs from Plumber (IDs only, checked 2026-10-23: ExpansionLandingPage/Retail/MID_Activity.lua).
	stash = { spell = 1216211, widgets = { 7591 } },
})
