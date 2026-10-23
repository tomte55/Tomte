local addonName, ns = ...

-- Prey module (Midnight): a page with the active hunt, this week's hunts and the targets defeated; a waypoint to the
-- active prey (page button, command, and Blizzard's hunt icon); difficulty labels on the Hunt Table. Only for
-- characters in an expansion with Prey data (Data/Midnight/Prey.lua). Reads in Read.lua, rules in Data.lua, the
-- table in HuntTable.lua, the page in Page.lua.

local ICON = 132212 -- ability_hunter_snipershot

local module, db

-- Read.lua and HuntTable.lua ask these at call time.
function ns.Prey_WidgetWaypoint()
	return module.active and db.widgetWaypoint == true
end

function ns.Prey_HuntTableOn()
	return module.active and db.huntTable == true
end

function ns.Prey_Changed()
	ns.PreyPage_Refresh()
end

local function Status()
	local s = ns.PreyRead_State()
	local a = s.active
	if a then
		ns.Print(("hunting %s (quest %d) in %s, %s."):format(a.title or "?", a.questID, a.mapName or "?",
			a.ready and "ready to turn in" or (ns.Prey_StateName(a.state) or "trail not shown")))
	else
		ns.Print("no prey hunt active.")
	end
	print(("  journey rank %s"):format(tostring(s.rank)))
	for _, row in ipairs(s.week) do
		print(("  %s: %s"):format(row.name, ns.Prey_WeekText(row)))
	end
	for _, row in ipairs(s.collection) do
		print(("  %s targets defeated: %d/%d (achievement %d)"):format(row.name, row.done, row.total, row.achievement))
	end
end

-- /tomte data: do the achievements and the journey resolve in game?
ns.Content_AddCheck("prey", function(expansion)
	local def = ns.Content_Get(expansion, "prey")
	if not def then
		return { "no prey data (Midnight only)" }
	end
	local lines = {}
	for _, d in ipairs(def.difficulties) do
		local _, name = GetAchievementInfo(d.achievement)
		local n = GetAchievementNumCriteria(d.achievement)
		lines[#lines + 1] = ("%s%s: achievement %d %s, %s criteria, %d quests"):format(
			(name and n == #d.quests) and "" or "!", d.name, d.achievement, name or "unknown", tostring(n), #d.quests)
	end
	local rank, journey = ns.PreyRead_Rank(def)
	lines[#lines + 1] = ("%sjourney %d: %s, rank %s"):format(rank and "" or "!", def.journey, journey or "?",
		tostring(rank))
	return lines
end)

module = ns.RegisterModule({
	key = "prey",
	name = "Prey",
	category = "quests",
	icon = ICON,
	summary = "Your prey hunt, this week's hunts and a waypoint to your target.",
	description = "For Midnight's Prey hunts: a page with your current target, its zone and how hot the trail is, "
		.. "how many hunts you've done this week per difficulty (and how many chests are left), and how many "
		.. "targets you've defeated for each difficulty's achievement. Set a waypoint to your prey from the page, "
		.. "with /tomte prey way, or by clicking Blizzard's hunt icon once the target is found. At the Hunt Table "
		.. "each target shows its difficulty, with a dot when you still need it for an achievement.",
	enabledByDefault = true,
	replaces = { { addon = "Plumber", why = "the Hunt Table difficulties and the prey waypoint" } },
	blocked = function()
		if not ns.Content_Get(ns.ContentExpansion(), "prey") then
			return "Only for characters in Midnight content."
		end
	end,
	defaults = {
		widgetWaypoint = true,
		huntTable = true,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			ns.PreyRead_Start()
			ns.PreyHunt_Start()
		else
			ns.PreyRead_Stop()
			ns.PreyHunt_Stop()
		end
	end,
	home = {
		{ kind = "page", key = "prey", order = 9, name = "Prey", icon = ICON, page = ns.PreyPage,
			summary = function()
				return ns.Prey_HomeText(ns.PreyRead_Active())
			end },
	},
	options = {
		{ type = "header", label = "Prey" },
		{ type = "checkbox", key = "widgetWaypoint", label = "Waypoint from the hunt icon",
			tooltip = "Clicking Blizzard's hunt icon once your target is found also sets a waypoint to it." },
		{ type = "checkbox", key = "huntTable", label = "Difficulties on the Hunt Table", onChange = function()
			ns.PreyHunt_Refresh()
		end, tooltip = "Each target on the Hunt Table shows its difficulty, with a dot when you still need it for an achievement. Its tooltip adds this week's count." },
	},
	commands = {
		{ "way", "set a waypoint to your prey", function()
			ns.Prey_SetWaypoint()
		end },
		{ "status", "your hunt, this week's hunts and targets defeated", Status },
		{ "open", "open the Prey page", function()
			ns.Panel_OpenPage("prey")
		end },
	},
})
