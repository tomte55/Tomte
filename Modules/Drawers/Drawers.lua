local addonName, ns = ...

-- Drawers: your own flyouts. Up to four drawers, each a button on screen (placed with Blizzard's Edit Mode, with a
-- key binding) that opens a row of items, spells, mounts and toys to use with a click, in combat too. Registered
-- here; the on-screen drawers in Bar.lua, the editor in Editor.lua, entry reading in Read.lua, pure rules in
-- Data.lua.

local COUNT = ns.DRAWERS_COUNT
local SPREAD = 60 -- pixels between the drawers' default places, side by side below the middle of the screen

local module, db

local DIRECTION_TEXT = { UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" }

local function Refresh()
	ns.Drawers_Refresh()
end

local function DefaultX(i)
	return (i - (COUNT + 1) / 2) * SPREAD
end

-- The same place as the drawer's `frame` default below.
local function ResetPosition(i)
	local frame = db["d" .. i].frame
	frame.point, frame.relPoint, frame.x, frame.y = "CENTER", "CENTER", DefaultX(i), -200
	Refresh()
end

local function Scale(v)
	return ("%.1f"):format(v)
end

local function Directions()
	local choices = {}
	for i, dir in ipairs(ns.DRAWERS_DIRECTIONS) do
		choices[i] = { value = dir, text = DIRECTION_TEXT[dir] }
	end
	return choices
end

local defaults = {
	scale = 1,
	closeOnUse = true,
	showNames = false,
	entries = {}, -- [d<i>] = { { kind = "item" | "toy" | "spell" | "mount", id = number }, ... }, in order
}
for i = 1, COUNT do
	defaults["d" .. i] = {
		enabled = i == 1,
		name = "", -- blank: "Drawer <i>"
		direction = "UP", -- one of ns.DRAWERS_DIRECTIONS
		perLine = 8, -- buttons before a new line starts
		frame = { point = "CENTER", relPoint = "CENTER", x = DefaultX(i), y = -200 }, -- ResetPosition repeats it
	}
	defaults.entries["d" .. i] = {}
end

local options = {
	{ type = "header", label = "Drawers" },
	{ type = "checkbox", key = "closeOnUse", label = "Close after use", onChange = Refresh,
		tooltip = "A drawer closes once you've used something from it. Off: it stays open until you click its button again." },
	{ type = "checkbox", key = "showNames", label = "Names under the buttons", onChange = Refresh },
	{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
		onChange = Refresh },
}

for i = 1, COUNT do
	local key = "d" .. i
	local rows = {
		{ type = "header", label = "Drawer " .. i },
		{ type = "checkbox", key = key .. ".enabled", label = "Show this drawer", onChange = Refresh,
			tooltip = "Its button shows once it has something in it. Key Bindings > Tomte opens it with a key." },
		{ type = "button", label = function()
			local _, entries = ns.Drawers_Saved(db, i)
			return #entries == 1 and "1 entry" or (#entries .. " entries")
		end, text = "Edit", onClick = function()
			ns.Drawers_OpenEditor(i)
		end, tooltip = "Add items, spells, mounts and toys, put them in order or take them out. Right-clicking the drawer's button does the same." },
		{ type = "input", key = key .. ".name", label = "Name", placeholder = "Drawer " .. i, onChange = Refresh,
			parent = key .. ".enabled" },
		{ type = "dropdown", key = key .. ".direction", label = "Opens", choices = Directions, onChange = Refresh,
			parent = key .. ".enabled" },
		{ type = "slider", key = key .. ".perLine", label = "Buttons per line", min = 1, max = 12, step = 1,
			onChange = Refresh, parent = key .. ".enabled",
			tooltip = "More than this and the drawer starts another line beside the first." },
		{ type = "button", label = "Position", text = "Reset", onClick = function()
			ResetPosition(i)
		end, parent = key .. ".enabled",
			tooltip = "Move the button back below the middle of the screen. Blizzard's Edit Mode moves it too." },
	}
	for _, row in ipairs(rows) do
		options[#options + 1] = row
	end

	ns.EditMode_Register({
		name = "Drawer " .. i,
		frame = function()
			return ns.Drawers_Toggle(i)
		end,
		refresh = Refresh,
		saved = function()
			ns.Drawers_SavePosition(i)
		end,
	})
end

module = ns.RegisterModule({
	key = "drawers",
	name = "Drawers",
	category = "interface",
	icon = 133633, -- inv_misc_bag_08
	summary = "Your own flyouts of items, spells, mounts and toys, one click away.",
	description = "Up to four drawers: a button on screen that opens a row of the items, spells, mounts and toys you put in it. Click one to use it, in combat too. Each drawer has a key binding, and Blizzard's Edit Mode moves the buttons.",
	enabledByDefault = false,
	replaces = { { addon = "Plumber", why = "drawer macros (custom flyouts)" } },
	defaults = defaults,
	init = function(moduleDB)
		db = moduleDB
		ns.Drawers_BarSetup(db, module)
		ns.Drawers_EditorSetup(db, module)
	end,
	toggle = function(active)
		if active then
			ns.Drawers_BarStart()
		else
			ns.Drawers_BarStop()
		end
	end,
	commands = {
		{ "edit", "open the drawer editor (/tomte drawers edit 2 for drawer 2)", function(arg)
			local i = tonumber(arg)
			ns.Drawers_OpenEditor(i and i >= 1 and i <= COUNT and i or nil)
		end },
	},
	options = options,
})

for i = 1, COUNT do
	_G["BINDING_NAME_" .. ns.Drawers_Binding(i)] = "Open drawer " .. i
end
