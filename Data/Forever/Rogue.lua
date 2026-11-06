local addonName, ns = ...

-- World of Warcraft: Forever: Rogue Poisons' poisons (see Core/Content.lua; read in Modules/Rogue/Forever.lua). There
-- poisons are bag items used on a weapon, not spells. Each family's items go from the lowest rank to the highest, the
-- families in the order they're offered. Item IDs checked on wowhead.com/forever, ranks on warcraft.wiki.gg's
-- Rogue_abilities_(Forever), 2026-11-05.

ns.Content_Register(ns.CONTENT_FOREVER, "poisons", {
	{ key = "instant", items = { 6947, 6949, 6950, 8926, 8927, 8928 } },
	{ key = "deadly", items = { 2892, 2893, 8984, 8985 } },
	{ key = "wound", items = { 10918, 10920, 10921, 10922 } },
	{ key = "crippling", items = { 3775, 3776 } },
	{ key = "mindNumbing", items = { 5237, 6951, 9186 } },
})
