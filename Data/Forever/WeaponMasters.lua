local addonName, ns = ...

-- World of Warcraft: Forever: the weapon masters, who teach weapon skills (see Core/Content.lua; read in
-- Modules/Gear/Forever.lua for Gear Check's "needs the ... skill" lines). skills: Enum.ItemWeaponSubclass IDs. Classic's
-- trainers and what they teach, not confirmed on Forever.

ns.Content_Register(ns.CONTENT_FOREVER, "weaponMasters", {
	{ name = "Hanashi", city = "Orgrimmar", faction = "Horde", skills = { 0, 1, 2, 10, 16 } },
	{ name = "Sayoc", city = "Orgrimmar", faction = "Horde", skills = { 0, 1, 2, 13, 15, 16 } },
	{ name = "Ansekhwa", city = "Thunder Bluff", faction = "Horde", skills = { 3, 4, 5, 10 } },
	{ name = "Archibald", city = "Undercity", faction = "Horde", skills = { 6, 7, 8, 15, 18 } },
	{ name = "Woo Ping", city = "Stormwind", faction = "Alliance", skills = { 6, 7, 8, 10, 15, 18 } },
	{ name = "Buliwyf Stonehand", city = "Ironforge", faction = "Alliance", skills = { 0, 1, 3, 4, 5, 13 } },
	{ name = "Bixi Wobblebonk", city = "Ironforge", faction = "Alliance", skills = { 15, 16, 18 } },
	{ name = "Ilyenia Moonfire", city = "Darnassus", faction = "Alliance", skills = { 2, 10, 13, 15, 16 } },
})
