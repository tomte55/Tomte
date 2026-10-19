local addonName, ns = ...

-- "Tomte window": settings for the Tomte window itself and its Home screen. Always on (no enable checkbox).

local function Redraw()
	ns.Panel_Refresh()
end

-- Setup and sharing (Panel/Setup.lua, Panel/Share.lua, Panel/Bug.lua): last on the page, above the Reset rows.
local SHARE = {
	{ type = "header", label = "Setup and sharing" },
	{ type = "button", label = "Pick a preset (Collector, Crafter, Minimal, Everything)", text = "Run setup",
		onClick = function()
			ns.SetupUI_Show()
		end,
		tooltip = "Turns modules on or off to fit how you play. Settings inside modules stay." },
	{ type = "button", label = "Your settings as a string for a friend", text = "Export",
		onClick = function()
			ns.ShareUI_Export()
		end,
		tooltip = "Settings only: no characters, history, flight times or lists." },
	{ type = "button", label = "Use a friend's settings", text = "Import",
		onClick = function()
			ns.ShareUI_Import()
		end,
		tooltip = "Paste their string, see what changes, then confirm. Your UI reloads." },
	{ type = "button", label = "Back to your settings from before the last import", text = "Undo import",
		shown = function()
			return ns.ShareUI_HasBackup()
		end,
		onClick = function()
			ns.ShareUI_Undo()
		end,
		tooltip = "Shows what changes back, then reloads your UI." },
	{ type = "button", label = "Something broke? A report to copy and send", text = "Bug report",
		onClick = function()
			ns.BugUI_Show()
		end,
		tooltip = "Versions, modules, other addons and Tomte's last errors. Sent nowhere by itself." },
}

local module

-- "Around you shows": one switch per "around" block of every module (on or off), added on ADDON_LOADED (init), when
-- every module has registered; Setup and sharing after them. A block never touched starts ticked.
local function AddRows(db)
	if module.rowsAdded then
		return
	end
	module.rowsAdded = true
	for _, choice in ipairs(ns.Home_AroundChoices()) do
		module.defaults.around[choice.key] = true -- what Reset puts back
		if db.around[choice.key] == nil then
			db.around[choice.key] = true
		end
		module.options[#module.options + 1] = { type = "checkbox", key = "around." .. choice.key, label = choice.name,
			onChange = Redraw, tooltip = "This block in Home's \"Around you\" column (it still needs its module on)." }
	end
	for _, spec in ipairs(SHARE) do
		module.options[#module.options + 1] = spec
	end
end

module = ns.RegisterModule({
	key = "window",
	name = "Tomte window",
	category = "tomte",
	icon = 134063, -- inv_misc_gear_01
	summary = "Pick a theme and choose what the rail and Home show.",
	description = "How this window looks, where it opens, and what the rail and Home show.",
	alwaysOn = true,
	init = AddRows,
	defaults = {
		theme = ns.Theme.DEFAULT, -- read by Core.lua on ADDON_LOADED, before anything draws
		opacity = 0.96,
		resume = 5,
		pills = true, -- counts on the rail
		around = {}, -- [home entry key] = false hides that "Around you" block (one true per block, set in AddRows)
	},
	options = {
		{ type = "header", label = "Look" },
		{ type = "dropdown", key = "theme", label = "Theme", onChange = Redraw, choices = ns.Theme.Choices,
			tooltip = "How every Tomte window, widget and toast looks. Takes effect after a reload." },
		{ type = "button", label = "The new theme shows after a reload", text = "Reload now",
			shown = function()
				return ns.ChoiceOrDefault(ns.db.window.theme, ns.Theme.Choices(), ns.Theme.DEFAULT) ~= ns.Theme.name
			end,
			onClick = function()
				if InCombatLockdown() then
					ns.Print_Combat("reload to switch themes")
					return
				end
				C_UI.Reload() -- needs a hardware event: this click is one
			end,
			tooltip = "Reloads your UI so Tomte draws with the theme picked above." },
		{ type = "header", label = "Window" },
		{ type = "slider", key = "opacity", label = "Background opacity", min = 0.5, max = 1, step = 0.02,
			shown = function()
				return ns.Theme.panel == "art" and ns.Theme.art.opacity -- Blizzard default always looks like a tooltip
			end,
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
