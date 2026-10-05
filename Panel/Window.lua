local addonName, ns = ...

-- "Tomte window": settings for the Tomte window itself. Always on (no enable checkbox).

ns.RegisterModule({
	key = "window",
	name = "Tomte window",
	category = "General",
	description = "How this window looks and where it opens.",
	alwaysOn = true,
	defaults = {
		opacity = 0.96,
		resume = 5,
	},
	options = {
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
	},
})
