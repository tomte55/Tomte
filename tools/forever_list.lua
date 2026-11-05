-- What World of Warcraft: Forever loads: tools/forever_build.lua builds the Forever TOC from Tomte.toc with this.
-- Regenerate after changing it or the TOC: lua Tomte/tools/forevertoc.lua (tests/test_forevertoc.lua checks).
-- keep: path prefixes (a folder with its slash, or one file); drop: prefixes taken out of what keep allowed;
-- extra: Forever-only files, each listed right after the retail file named in `after`.
return {
	-- warcraft.wiki.gg TOC_format: _Forever is the suffix, client 1.60.1 is Interface 16001.
	name = "Tomte_Forever.toc",
	interface = "16001",
	keep = {
		"Core/", "Themes/", "Cinematic/", "Panel/",
		-- The launch set (spec: "Launch set").
		"Modules/Cursor/", "Modules/Mail/", "Modules/Upkeep/", "Modules/Loot/", "Modules/Value/", "Modules/Flight/",
		"Modules/Fishing/", "Modules/Drawers/", "Modules/Nameplates/", "Modules/Chat/", "Modules/Social/",
		"Modules/Share/", "Modules/AFK/", "Modules/Games/", "Modules/Quests/", "Modules/Recent/", "Modules/Minimap/",
		"Modules/NextUp/",
		-- Migration 3 calls ns.Moments_MigrateAtMax (pure), and migrations run on a fresh TomteDB too.
		"Modules/Moments/Data.lua",
	},
	drop = {
		"Core/Journal.lua", -- mount and pet journals
		"Panel/Entries.lua", -- mounts, toys and pets as entries
		"Panel/ModelPreview.lua", -- retail model scene templates
	},
	extra = {},
}
