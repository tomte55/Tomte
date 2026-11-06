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
		-- docs/superpowers/specs/2026-11-05-tomte-forever-all-modules.md: everything else that can work there.
		"Modules/Bags/", "Modules/Counts/", "Modules/Mount/", "Modules/Teleports/", "Modules/Alts/",
		"Modules/Achievements/", "Modules/Moments/", "Modules/Recap/", "Modules/DressUp/", "Modules/Showcase/",
		"Modules/Talents/", "Modules/Hunter/", "Modules/Rogue/", "Modules/Combat/", "Modules/Buffs/", "Modules/Gather/",
		"Modules/Graphics/", "Modules/Performance/",
		-- Waypoints without portal routes (Network*, Route, Router: retail's route tables).
		"Modules/Travel/Data.lua", "Modules/Travel/Target.lua", "Modules/Travel/Marker.lua",
		"Modules/Travel/MapPing.lua", "Modules/Travel/Guard.lua", "Modules/Travel/Waypoint.lua",
		-- Instances: the lockout banner (no difficulty flag, difficulty menu or Dungeon Finder there).
		"Modules/Instances/Data.lua", "Modules/Instances/Read.lua", "Modules/Instances/Instances.lua",
		-- Tooltip extras without the choice windows (no Forever data for them).
		"Modules/Tips/Data.lua", "Modules/Tips/Read.lua", "Modules/Tips/Scan.lua", "Modules/Tips/Tooltip.lua",
		"Modules/Tips/Tips.lua",
		-- Material uses, with Forever's own table (extra below) instead of retail's Generated.lua.
		"Modules/Materials/Data.lua", "Modules/Materials/Materials.lua",
		-- Gear Check's Forever version shares these with retail; the rest of its folder is retail's.
		"Modules/Gear/Rules.lua", "Modules/Gear/Rewards.lua", "Modules/Gear/RewardCard.lua", "Modules/Gear/Arrow.lua",
	},
	drop = {},
	extra = {
		-- The Forever theme (docs/superpowers/specs/2026-11-06-tomte-forever-theme-design.md): needs the game's art.
		{ after = "Themes/Cartographer.lua", files = { "Themes/Forever.lua" } },
		{ after = "Panel/Widgets.lua", files = { "Panel/ForeverArt.lua" } },
		{ after = "Panel/Rail.lua", files = { "Panel/ForeverTabs.lua" } },
		{ after = "Core/Content.lua", files = { "Data/Forever/Teleports.lua", "Data/Forever/Buffs.lua", "Data/Forever/Rogue.lua", "Data/Forever/Tools.lua", "Data/Forever/Fishing.lua" } },
		{ after = "Modules/Fishing/Helpers.lua", files = { "Modules/Fishing/Rod.lua" } },
		{ after = "Modules/Materials/Data.lua", files = { "Modules/Materials/GeneratedForever.lua" } },
		{ after = "Modules/Rogue/Lockpick.lua", files = { "Modules/Rogue/Forever.lua" } },
		-- ForeverItems.lua makes the event bus RewardCard.lua takes at file load; Forever.lua is the main file, so last.
		{ after = "Modules/Gear/Rewards.lua", files = { "Modules/Gear/ForeverRules.lua", "Modules/Gear/ForeverItems.lua" } },
		{ after = "Modules/Gear/RewardCard.lua", files = { "Modules/Gear/Forever.lua" } },
		-- Forever-only modules (docs/superpowers/specs/2026-11-05-tomte-forever-leveling.md), after Gear Check's weapon skills.
		{ after = "Modules/Upkeep/Durability.lua", files = {
			"Modules/Leveling/Data.lua", "Modules/Leveling/Read.lua", "Modules/Leveling/XPBar.lua",
			"Modules/Leveling/Page.lua", "Modules/Leveling/HomeSection.lua", "Modules/Leveling/Leveling.lua",
			"Modules/PetCare/Data.lua", "Modules/PetCare/PetCare.lua",
			-- docs/superpowers/specs/2026-11-06-tomte-forever-rest-and-chat-groups.md
			"Modules/Rest/Data.lua", "Modules/Rest/Rest.lua",
		} },
	},
}
