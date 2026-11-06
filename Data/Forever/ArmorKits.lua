local addonName, ns = ...

-- World of Warcraft: Forever: armor kits, best first (see Core/Content.lua; read in Modules/Leveling/Read.lua). A kit shares its
-- slot on an item with enchants and replaces what's there. Item IDs checked on wowhead.com/forever, 2026-11-06. The Core kit
-- gives defense where the others give stamina and armor, which not everyone wants, so it comes last.

ns.Content_Register(ns.CONTENT_FOREVER, "armorKits", {
	15564, -- Rugged Armor Kit, level 40
	8173, -- Thick Armor Kit, level 30
	4265, -- Heavy Armor Kit, level 20
	2313, -- Medium Armor Kit, level 5
	2304, -- Light Armor Kit
	18251, -- Core Armor Kit, level 50
})
