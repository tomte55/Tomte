local addonName, ns = ...

-- Nameplates: small additions to Blizzard's nameplates in the open world. A quest icon and progress on units your
-- quests need, the soft (Interact key) target's name with a cast bar, and Radiant Remnant counts on Hallowfall's
-- Keyflames. Rules in Data.lua, reads in Read.lua, badges in Badge.lua, the soft target in SoftTarget.lua.

-- The War Within: Keyflame plates count Radiant Remnants. The IDs live in Data.lua (unit-tested there), so they're
-- registered here rather than from Data/WarWithin/, which loads before the module's files. Merged over every
-- expansion in Badge.lua: a Keyflame counts wherever you meet it, whichever expansion your character follows.
ns.Content_Register(10, "plateWidgets", ns.Plates_ItemSets(ns.PLATES_KEYFLAME_SETS, ns.PLATES_RADIANT_REMNANT))

local module, db

local function Refresh()
	if module.active then
		ns.Plates_BadgesRefresh()
		ns.Plates_SoftRefresh()
	end
end

local function Why()
	for _, line in ipairs(ns.Plates_BadgesWhy("target")) do
		ns.Print(line)
	end
end

local function Scale(v)
	return ("%.1f"):format(v)
end

module = ns.RegisterModule({
	key = "plates",
	name = "Nameplates",
	category = "interface",
	icon = 236188, -- ability_hunter_markedfordeath
	summary = "Quest progress, the Interact target's name and Keyflame counts on Blizzard's nameplates.",
	description = "Adds to Blizzard's nameplates in the open world: a quest icon with your progress (3/8) on creatures your quests need, the name of what the Interact key would use under its icon with a cast bar while you gather or open it, and how many Radiant Remnants you carry on Hallowfall's Keyflames. Off in dungeons, raids and delves, where the game keeps addons away from nameplates.",
	enabledByDefault = false,
	replaces = {
		{ addon = "Plumber", why = "quest icons on nameplates, the soft target name and the Keyflame count" },
	},
	defaults = {
		quests = true,
		questProgress = true,
		questParty = false,
		softName = true,
		softCast = true,
		softNPC = false,
		keyflame = true,
		scale = 1,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			ns.Plates_BadgesStart(db)
			ns.Plates_SoftStart(db)
		else
			ns.Plates_BadgesStop()
			ns.Plates_SoftStop()
		end
	end,
	commands = {
		{ "why", "explain what your target's nameplate shows and why", Why },
	},
	options = {
		{ type = "header", label = "Quests" },
		{ type = "checkbox", key = "quests", label = "Quest icon on nameplates", onChange = Refresh,
			tooltip = "An icon beside the nameplate of a creature one of your quests still needs (to kill, loot or use)." },
		{ type = "checkbox", key = "questProgress", label = "Show progress", onChange = Refresh, parent = "quests",
			tooltip = "The count next to the icon, like 3/8 or 45%." },
		{ type = "checkbox", key = "questParty", label = "Group members' quests", onChange = Refresh,
			parent = "quests",
			tooltip = "Also mark creatures only someone in your group still needs, with a blue icon." },

		{ type = "header", label = "Interact target" },
		{ type = "checkbox", key = "softName", label = "Name under the Interact icon", onChange = Refresh,
			tooltip = "The name of the herb, ore, chest or object the Interact key would use, under the small icon the game shows over it. Needs the game's Interact Key with its target icons on (Options, Controls)." },
		{ type = "checkbox", key = "softCast", label = "Cast bar while you use it", onChange = Refresh,
			parent = "softName",
			tooltip = "A small bar under the name while you gather, open or use it. Out of combat only." },
		{ type = "checkbox", key = "softNPC", label = "Also for characters", onChange = Refresh, parent = "softName",
			tooltip = "Also name non-player characters the Interact key would talk to." },

		{ type = "header", label = "Hallowfall" },
		{ type = "checkbox", key = "keyflame", label = "Radiant Remnants on Keyflames", onChange = Refresh,
			tooltip = "Under a Keyflame's nameplate, how many Radiant Remnants you carry to light it." },

		{ type = "header", label = "Look" },
		{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
			onChange = Refresh },
	},
})
