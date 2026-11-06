local addonName, ns = ...

-- World of Warcraft: Forever: profession tools, which that game files under weapons or trade goods because it has no
-- profession equipment class (see Core/Content.lua; read in Modules/Bags/Read.lua, for the Profession equipment
-- category). Fishing poles are found by their weapon subclass instead. Item IDs checked on wowhead.com/forever,
-- 2026-11-06.

ns.Content_Register(ns.CONTENT_FOREVER, "professionTools", {
	[7005] = true, -- Skinning Knife
	[2901] = true, -- Mining Pick
	[5956] = true, -- Blacksmith Hammer
	[6219] = true, -- Arclight Spanner
	[10498] = true, -- Gyromatic Micro-Adjustor
	[9149] = true, -- Philosopher's Stone
	[6218] = true, -- Runed Copper Rod
	[6339] = true, -- Runed Silver Rod
	[11130] = true, -- Runed Golden Rod
	[11145] = true, -- Runed Truesilver Rod
	[16207] = true, -- Runed Arcanite Rod
})
