local addonName, ns = ...

-- Hidden settings: switches and sliders for the game's settings that Blizzard's own Settings panel leaves out on this
-- client, and a list of every game setting that isn't at the game's default (handy after another addon changed
-- things). Tomte keeps the value from before its first change and puts it back when the module turns off; a change
-- made elsewhere afterwards wins. Pure rules and the list in Data.lua.

local NOT_DEFAULT = "  (not default)" -- after a row's label while the game's value isn't its default
local DIALOG_W, DIALOG_H = 520, 420
local UI = ns.UI

local GetCVar, SetCVar, GetCVarDefault = C_CVar.GetCVar, C_CVar.SetCVar, C_CVar.GetCVarDefault
local Same, Available = ns.Hidden_Same, ns.Hidden_Available
local SETTINGS = ns.HIDDEN_SETTINGS

local module, db
local pending -- a function waiting for combat to end: CVar writes are refused for some settings in combat

local events = CreateFrame("Frame")

local function Exists(cvar)
	return GetCVar(cvar) ~= nil
end

local function IsShown(entry)
	return Available(entry, ns.FOREVER, Exists)
end

local function Shown()
	local list = {}
	for _, entry in ipairs(SETTINGS) do
		if IsShown(entry) then
			list[#list + 1] = entry
		end
	end
	return list
end

-- Runs fn now, or once combat ends.
local function OutOfCombat(fn)
	if not InCombatLockdown() then
		fn()
		return
	end
	pending = fn
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

events:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local fn = pending
	pending = nil
	if fn then
		fn()
	end
end)

-- Writing -----------------------------------------------------------------------------------------------------------

-- Writes value and remembers what the game read it back as (a later difference is someone else's change).
local function Write(cvar, value)
	SetCVar(cvar, value)
	if db.set[cvar] ~= nil then
		db.applied[cvar] = GetCVar(cvar)
	end
end

local function Current()
	local current = {}
	for cvar in pairs(db.set) do
		current[cvar] = GetCVar(cvar)
	end
	for cvar in pairs(db.saved) do
		current[cvar] = GetCVar(cvar)
	end
	return current
end

local function NameOf(cvar)
	for _, entry in ipairs(SETTINGS) do
		if entry.cvar == cvar then
			return entry.label
		end
	end
	return cvar
end

local function Start()
	OutOfCombat(function()
		if not module.active then
			return
		end
		local writes, adopted = ns.Hidden_StartPlan(db, Current())
		for _, w in ipairs(writes) do
			Write(w.cvar, w.value)
		end
		for _, cvar in ipairs(adopted) do
			ns.Print(("%s was changed outside Tomte; keeping the new value."):format(NameOf(cvar)))
		end
	end)
end

local function Stop()
	OutOfCombat(function()
		if module.active then
			return -- turned on again before combat ended
		end
		for _, w in ipairs(ns.Hidden_StopPlan(db, Current())) do
			SetCVar(w.cvar, w.value)
		end
	end)
end

-- The player picked value for entry's CVar on the page.
local function Choose(entry, value)
	if InCombatLockdown() then
		ns.Print_Combat("change game settings")
		return
	end
	local cvar = entry.cvar
	if ns.Hidden_Choose(db, cvar, value, GetCVar(cvar)) and module.active then
		Write(cvar, value)
	end
end

-- Buttons -----------------------------------------------------------------------------------------------------------

local function Forget(cvar)
	db.set[cvar], db.saved[cvar], db.applied[cvar] = nil, nil, nil
end

-- Every setting on the page back to the game's default.
local function ResetPage()
	if InCombatLockdown() then
		ns.Print_Combat("change game settings")
		return
	end
	local count = 0
	for _, entry in ipairs(Shown()) do
		local default = GetCVarDefault(entry.cvar)
		if default ~= nil and not Same(GetCVar(entry.cvar), default) then
			SetCVar(entry.cvar, default)
			count = count + 1
		end
		Forget(entry.cvar)
	end
	ns.Print(count == 0 and "every hidden setting was already at the game's default."
		or ("%d hidden settings back to the game's defaults."):format(count))
end

-- What Tomte changed back to how it was before.
local function Undo()
	if InCombatLockdown() then
		ns.Print_Combat("change game settings")
		return
	end
	local writes = ns.Hidden_StopPlan(db, Current())
	for _, w in ipairs(writes) do
		SetCVar(w.cvar, w.value)
	end
	wipe(db.set)
	wipe(db.saved)
	wipe(db.applied)
	ns.Print(#writes == 0 and "nothing to undo." or ("%d settings back to how they were."):format(#writes))
end

-- The report's rows: every game setting the client lists (ConsoleGetAllCommands), or the page's own list.
local HEADINGS = { [1] = "Graphics", [3] = "Combat", [4] = "Game", [7] = "Sound" } -- Enum.ConsoleCategory values
local SKIP_CATEGORY = { [0] = true, [6] = true, [8] = true, [9] = true } -- Debug, Net, Gm, Reveal

local function HeadingOf(category)
	return HEADINGS[category] or "Other"
end

local function ReportRows()
	local rows = {}
	local commands = ConsoleGetAllCommands and ConsoleGetAllCommands()
	if commands then
		for _, c in ipairs(commands) do
			if c.commandType == Enum.ConsoleCommandType.Cvar and not SKIP_CATEGORY[c.category]
				and not c.command:find("^CACHE%-") then
				local value, default, _, _, locked, _, readOnly = C_CVar.GetCVarInfo(c.command)
				if not (locked or readOnly) then
					rows[#rows + 1] = { name = c.command, value = value, default = default, category = c.category }
				end
			end
		end
	else
		for _, entry in ipairs(Shown()) do
			rows[#rows + 1] = { name = entry.cvar, value = GetCVar(entry.cvar), default = GetCVarDefault(entry.cvar),
				category = 4 }
		end
	end
	return rows
end

local function ShowChanged()
	local text, count = ns.Hidden_DiffText(ReportRows(), HeadingOf)
	ns.Dialog_Show({
		title = ("Not at the game's default (%d)"):format(count),
		hint = "Put one back with /console <name> <default>. Many are yours on purpose (graphics, sound, key "
			.. "settings).",
		text = count == 0 and "Every game setting is at its default." or text,
		readOnly = true,
		width = DIALOG_W,
		height = DIALOG_H,
	})
end

-- Settings rows ---------------------------------------------------------------------------------------------------

local function ShownText(entry, value)
	if value == nil then
		return "?"
	end
	if entry.kind == "switch" then
		return ns.Hidden_SwitchOn(entry, value) and "on" or "off"
	end
	return (entry.format or "%s"):format(tonumber(value) or value)
end

local function Row(entry)
	local cvar = entry.cvar
	local spec = {
		label = function()
			local now, default = GetCVar(cvar), GetCVarDefault(cvar)
			if now ~= nil and default ~= nil and not Same(now, default) then
				return entry.label .. UI.Wrap(NOT_DEFAULT, "textFaint")
			end
			return entry.label
		end,
		tooltip = function()
			local lines = entry.tooltip and (entry.tooltip .. "\n\n") or ""
			return lines .. ("Game default: %s. Now: %s."):format(ShownText(entry, GetCVarDefault(cvar)),
				ShownText(entry, GetCVar(cvar)))
		end,
		shown = function()
			return IsShown(entry)
		end,
		search = entry.label .. " " .. (entry.tooltip or "") .. " " .. cvar, -- label and tooltip are functions
	}
	if entry.kind == "switch" then
		spec.type = "checkbox"
		spec.get = function()
			return ns.Hidden_SwitchOn(entry, GetCVar(cvar))
		end
		spec.set = function(on)
			Choose(entry, ns.Hidden_SwitchValue(entry, on))
		end
	else
		spec.type = "slider"
		spec.min, spec.max, spec.step = entry.min, entry.max, entry.step
		spec.format = function(v)
			return (entry.format or "%s"):format(v)
		end
		spec.get = function()
			return tonumber(GetCVar(cvar)) or entry.min
		end
		spec.set = function(v)
			Choose(entry, ns.Hidden_SliderValue(entry, v))
		end
	end
	return spec
end

local options = {}
for _, entry in ipairs(SETTINGS) do
	if entry.group then
		options[#options + 1] = { type = "header", label = entry.group }
	else
		options[#options + 1] = Row(entry)
	end
end
options[#options + 1] = { type = "header", label = "Put back" }
options[#options + 1] = { type = "button", label = "Everything not at the game's default", text = "Show",
	onClick = ShowChanged,
	tooltip = "A list of every game setting that isn't at its default, from any addon or by hand. Nothing changes." }
options[#options + 1] = { type = "button", label = "This page to the game's defaults", text = "Reset",
	onClick = ResetPage, confirm = "Put every setting on this page back to the game's default?" }
options[#options + 1] = { type = "button", label = "Undo Tomte's changes", text = "Undo", onClick = Undo,
	confirm = "Put every setting Tomte changed here back to how it was before?",
	tooltip = "Only what you changed on this page. Turning Hidden settings off does the same, until you turn it on "
		.. "again." }

module = ns.RegisterModule({
	key = "hidden",
	name = "Hidden settings",
	category = "interface",
	icon = 134237, -- inv_misc_key_03
	summary = "Game settings that aren't in the game's own Settings, and a list of what isn't at its default.",
	description = "Switches and sliders for settings the game has but doesn't show in its Settings panel, such as "
		.. "how far the camera zooms out, class-colored names in chat and the spell queue window. Each row says when "
		.. "it isn't at the game's default, and \"Show\" lists every game setting that isn't, for example after "
		.. "another addon changed them. Turning this off puts back what you changed here.",
	enabledByDefault = true, -- changes nothing until the player flips a row
	defaults = {
		set = {}, -- [cvar] = the value the player picked here
		saved = {}, -- [cvar] = its value before Tomte first changed it (put back when the module turns off)
		applied = {}, -- [cvar] = what it read back as after Tomte set it (a difference = changed elsewhere)
	},
	noShare = { "saved", "applied" }, -- this computer's values, not settings
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "changed", "list every game setting that isn't at its default", ShowChanged },
		{ "undo", "put back what you changed on the Hidden settings page", Undo },
	},
	options = options,
})
