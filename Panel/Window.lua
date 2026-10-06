local addonName, ns = ...

-- "Tomte window": settings for the Tomte window itself and its Home screen. Always on (no enable checkbox).

local function Redraw()
	ns.Panel_Refresh()
end

-- "Around you shows": one checkbox per block, by its home entry key (Core/Modules.lua filters HomeEntries).
local AROUND = {
	{ "collectaround", "Collect here" },
	{ "wqaround", "World quests" },
	{ "teleportsaround", "Teleports" },
	{ "flightaround", "Flight masters" },
	{ "mountaround", "Mount favorites" },
}

local module = ns.RegisterModule({
	key = "window",
	name = "Tomte window",
	category = "General",
	description = "How this window looks, where it opens, and what the rail and Home show.",
	alwaysOn = true,
	defaults = {
		opacity = 0.96,
		resume = 5,
		pills = true, -- counts on the rail
		around = {}, -- [home entry key] = false hides that "Around you" block (filled from AROUND below)
	},
	options = {
		{ type = "header", label = "Window" },
		{ type = "slider", key = "opacity", label = "Background opacity", min = 0.5, max = 1, step = 0.02,
			format = function(value)
				return ("%d%%"):format(math.floor(value * 100 + 0.5))
			end,
			onChange = function()
				ns.Panel_ApplyLook()
			end,
			tooltip = "Lower lets the game show through the window; 100% is solid." },
		{ type = "slider", key = "resume", label = "Reopen where I left off for", min = 0, max = 30, step = 1,
			format = function(value)
				return value == 0 and "never" or ("%d min"):format(value)
			end,
			tooltip = "Opening Tomte within this long after closing it goes back to the page you were on. After that, "
				.. "or at 0, it opens on Home." },
		{ type = "checkbox", key = "pills", label = "Counts on the rail", onChange = Redraw,
			tooltip = "A small count beside a page in the list on the left when it has something for you: crafting "
				.. "list steps for this character (Alts), vault rewards and full Concentration (Weekly board)." },
		{ type = "header", label = "Around you shows" },
	},
})

for _, block in ipairs(AROUND) do
	module.defaults.around[block[1]] = true
	module.options[#module.options + 1] = { type = "checkbox", key = "around." .. block[1], label = block[2],
		onChange = Redraw, tooltip = "This block in Home's \"Around you\" column (it still needs its module on)." }
end
