local addonName, ns = ...

-- The War Within (expansion 10): Tooltip extras data (see Core/Content.lua; read in Modules/Tips/Read.lua, which
-- merges every expansion's table because each kind is keyed by a game ID). Fields:
--   keys:            [item ID named like the chest or door] = { currency = ID | item = ID, count = how many }.
--                    The object on screen is matched by that item's (localized) name.
--   repSpells:       [use spell of an item] = faction ID, or a list for a token that raises several factions.
--   vendors:         [item ID] = { npc, name (English fallback), map, x, y (0..1), area, note, label, named }
--                    or { places = { ... } } for several vendors. named: the item's own text already names the
--                    vendor, so only the Ctrl-click hint is added.
--   choices:         [player choice ID] = { item = ID } | { currency = ID }, the token a choice window takes.
--   reagentQuantity: [recipe ID] = { [reagent item ID] = real count } where the recipe data says otherwise.
--   reagentSkip:     [item ID] = true, items whose use spell looks like a recipe but isn't one to show.
-- repSpells: wago.tools SpellEffect (Effect 103, "reputation"), joined with ItemEffect and ItemXItemEffect, build
-- 12.1.5, 2026-10-23, split by the item's expansion. The other IDs and vendor coordinates are from Plumber by
-- Peterodox (IDs and positions only, checked 2026-10-23: GameTooltip_Key.lua, GameTooltip_VendorLocation.lua,
-- GameTooltip_ItemReagents.lua, PlayerChoiceFrameToken.lua).

ns.Content_Register(10, "tips", {
	keys = {
		[228942] = { currency = 3028, count = 1 }, -- Bountiful Coffer (delves): Restored Coffer Key
	},
	repSpells = {
		[448393] = 2640, -- Companion Experience
		[461172] = 2640, -- Chunk of Companion Experience
		[461173] = 2640, -- Chunk of Companion Experience
		[461174] = 2640, -- Chunk of Companion Experience
		[464873] = 2640, -- Companion Experience
		[1217109] = 2640, -- Chunk of Companion Experience
		[1217110] = 2640, -- Chunk of Companion Experience
		[1217111] = 2640, -- Chunk of Companion Experience
		[1217548] = 2640, -- Chunk of Companion Experience
		[1228437] = 2640, -- Big Wheel of Cheese
		[1239894] = 2640, -- Lil Wheel of Cheese
	},
	vendors = {
		[225557] = { npc = 226205, name = "Cendvin", map = 2248, x = 0.744, y = 0.452 }, -- Sizzling Cinderpollen
		-- Odd Glob of Wax
		[212493] = { npc = 225166, name = "Middles", map = 2214, x = 0.4336, y = 0.352, named = true },
		[224642] = { npc = 216164, name = "Gnawbles", map = 2214, x = 0.436, y = 0.352 }, -- Firelight Ruby
		-- Radiant Emblem of Service
		[238920] = { area = 15335, name = "Morgaen's Tears", map = 2215, x = 0.282, y = 0.56 },
		[227673] = { npc = 226994, name = "Blair Bass", map = 2346, x = 0.342, y = 0.716 }, -- "Gold" Fish
		-- Gunk-Covered Thingy
		[233246] = { npc = 234776, name = "Angelo Rustbin", map = 2346, x = 0.258, y = 0.381, named = true },
		[234741] = { places = { -- Miscellaneous Mechanica
			{ npc = 228286, name = "Skedgit Cinderbangs", map = 2346, x = 0.432, y = 0.828, label = "Mounts" },
			{ npc = 236411, name = "Ditty Fuzeboy", map = 2346, x = 0.354, y = 0.412, label = "Pets" },
		} },
		[245510] = { npc = 245348, name = "Ba'choso", map = 2371, x = 0.42, y = 0.224 }, -- Loombeast Silk
		-- Class set curios
		-- Hungering Void Curio
		[237602] = { npc = 248304, name = "Acquirer Ba'theom", map = 2371, x = 0.42, y = 0.224, named = true },
		[228819] = { npc = 231824, name = "Kari Bridgeblaster", map = 2346, x = 0.439, y = 0.498, area = 15388,
			note = "upper floor" }, -- Excessively Bejeweled Curio
		-- Web-Wrapped Curio
		[225634] = { npc = 227003, name = "Kir'xal", map = 2216, x = 0.566, y = 0.458, named = true },
	},
	choices = {
		[838] = { item = 212493 }, -- Odd Glob of Wax
		[841] = { currency = 3090 }, -- Flame-Blessed Iron (Siren Isle command map)
		-- Radiant Echo
		[827] = { item = 246771 },
		[829] = { item = 246771 },
		[830] = { item = 246771 },
		[831] = { item = 246771 },
		[832] = { item = 246771 },
		[833] = { item = 246771 },
		[854] = { item = 246771 },
		[855] = { item = 246771 },
	},
	reagentQuantity = {
		[428667] = { [211297] = 2 }, -- Fractured Spark of Omens (season 1)
		[467635] = { [230905] = 2 }, -- Fractured Spark of Fortunes (season 2)
		[468717] = { [231757] = 2 }, -- Fractured Spark of Starlight (season 3)
	},
})
