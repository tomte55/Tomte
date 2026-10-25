local addonName, ns = ...

-- Midnight (expansion 11): Tooltip extras data. Same fields and sources as Data/WarWithin/Tips.lua (repSpells from
-- wago.tools SpellEffect, build 12.1.5; the other IDs and vendor positions from Plumber by Peterodox, IDs only,
-- checked 2026-10-23). Untested in game until a friend in Midnight content checks it.

ns.Content_Register(11, "tips", {
	keys = {
		[254250] = { currency = 3028, count = 1 }, -- Bountiful Coffer (delves): Restored Coffer Key
	},
	repSpells = {
		[1258623] = 2744, -- Chunk of Companion Experience
		[1258625] = 2744, -- Chunk of Companion Experience
		[1258626] = 2744, -- Chunk of Companion Experience
		[1258805] = 2744, -- Chunk of Companion Experience
		[1258939] = 2744, -- Assassin's Subtle Tea
		[1258942] = 2744, -- Potent Assassin's Subtle Tea
		[1261503] = 2744, -- Companion Experience
		[1277957] = 2744, -- Companion Experience
	},
	vendors = {
		[264882] = { npc = 259722, name = "Andra", map = 2393, x = 0.418, y = 0.666, named = true }, -- Finery Funds
		-- Dark Particle
		[267051] = { npc = 255473, name = "Maren Silverwing", map = 2393, x = 0.48, y = 0.492, named = true },
		-- Vile Essence
		[259361] = { name = "Abandoned Ritual Skull", map = 2437, x = 0.444, y = 0.436, note = "in a cave" },
		-- Void-Tainted Remains
		[245937] = { npc = 245976, name = "Deminos Darktrance", map = 2444, x = 0.388, y = 0.816, named = true },
		-- Ethereal Energy
		[248944] = { npc = 249098, name = "Balaak the Twice-Exiled", map = 2444, x = 0.536, y = 0.52, named = true },
		-- Chiming Void Curio
		[249367] = { npc = 254436, name = "Kirana", map = 2424, x = 0.556, y = 0.878, named = true },
	},
	choices = {
		-- Latent Arcana
		[890] = { item = 242241 },
		[896] = { item = 242241 },
		[897] = { item = 242241 },
		[905] = { item = 242241 },
		[910] = { item = 242241 },
	},
	reagentQuantity = {
		[1283168] = { [268650] = 5 }, -- Ascendant Voidcore
	},
	-- Item via wago.tools ItemEffect and ItemXItemEffect (spell 1261503), build 12.1.5, 2026-10-25.
	samples = {
		rep = 257382, -- Companion Experience
	},
})
