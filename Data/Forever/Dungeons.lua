local addonName, ns = ...

-- World of Warcraft: Forever: the dungeons Groups in chat looks for in messages (see Core/Content.lua; read in
-- Modules/ChatGroups/ChatGroups.lua). aliases: what players write, lowercase, whole words, in English whatever their client's
-- language. Plain "dm" counts as Deadmines, as Dire Maul is usually written with its wing. No everyday words ("gnome",
-- "temple"), which chat uses for other things. min, max: the levels Forever's group finder suggests (Classic's for the
-- Stockade, which it doesn't list); they feed the "near my level" filter, and tools/dungeonjournal.lua reads the Stockade's.

ns.Content_Register(ns.CONTENT_FOREVER, "dungeons", {
	{ key = "rfc", name = "Ragefire Chasm", min = 13, max = 18, aliases = { "rfc", "ragefire", "ragefire chasm" } },
	{ key = "wc", name = "Wailing Caverns", min = 15, max = 24, aliases = { "wc", "wailing", "wailing caverns" } },
	{ key = "vc", name = "Deadmines", min = 17, max = 26, aliases = { "vc", "dm", "deadmines", "deadmine", "van cleef", "vancleef" } },
	{ key = "sfk", name = "Shadowfang Keep", min = 20, max = 30, aliases = { "sfk", "shadowfang", "shadowfang keep" } },
	{ key = "bfd", name = "Blackfathom Deeps", min = 24, max = 32, aliases = { "bfd", "blackfathom", "blackfathom deeps" } },
	{ key = "stocks", name = "The Stockade", min = 24, max = 32, aliases = { "stocks", "stockade", "stockades" } },
	{ key = "gnomer", name = "Gnomeregan", min = 29, max = 38, aliases = { "gnomer", "gnomeregan" } },
	{ key = "rfk", name = "Razorfen Kraul", min = 29, max = 38, aliases = { "rfk", "kraul", "razorfen kraul" } },
	{ key = "sm", name = "Scarlet Monastery", min = 30, max = 46,
		aliases = { "sm", "scarlet", "scarlet monastery", "gy", "graveyard", "lib", "library", "arm", "armory", "cath", "cathedral" } },
	{ key = "rfd", name = "Razorfen Downs", min = 37, max = 46, aliases = { "rfd", "downs", "razorfen downs" } },
	{ key = "uld", name = "Uldaman", min = 41, max = 51, aliases = { "uld", "ulda", "uldaman" } },
	{ key = "zf", name = "Zul'Farrak", min = 44, max = 54, aliases = { "zf", "zul farrak", "zulfarrak", "farrak" } },
	{ key = "mara", name = "Maraudon", min = 46, max = 55, aliases = { "mara", "maraudon" } },
	{ key = "st", name = "Sunken Temple", min = 50, max = 60, aliases = { "st", "sunken temple", "atal hakkar" } },
	{ key = "brd", name = "Blackrock Depths", min = 52, max = 60, aliases = { "brd", "blackrock depths", "emp run", "arena run" } },
	{ key = "lbrs", name = "Lower Blackrock Spire", min = 55, max = 60, aliases = { "lbrs", "lower blackrock", "lower spire" } },
	{ key = "ubrs", name = "Upper Blackrock Spire", min = 59, max = 60, aliases = { "ubrs", "upper blackrock", "upper spire" } },
	{ key = "dire", name = "Dire Maul", min = 54, max = 60,
		aliases = { "dire maul", "diremaul", "dme", "dmw", "dmn", "dm east", "dm west", "dm north", "dm e", "dm w", "dm n", "tribute" } },
	{ key = "scholo", name = "Scholomance", min = 58, max = 60, aliases = { "scholo", "scholomance" } },
	{ key = "strat", name = "Stratholme", min = 58, max = 60, aliases = { "strat", "stratholme", "strath" } },
})
