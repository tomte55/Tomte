local addonName, ns = ...

-- Tomte core: saved variables, module start-up and /tomte. Modules register themselves at file load
-- (Modules.lua); everything is started here on ADDON_LOADED.

ns.PREFIX = "|cff66ccffTomte|r: "
ns.VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?" -- the TOC's ## Version
-- Panel title bar and minimap button. The TOC's IconTexture is set separately (it can't read this).
ns.ICON = "Interface\\AddOns\\Tomte\\Media\\Logo" -- Media/Logo.svg is the source
ns.ownFrames = {} -- our frames on WorldFrame that the cinematic must not hide (bar, letterbox)
ns.errorHandler = function(err)
	return geterrorhandler()(err)
end

local CORE_DEFAULTS = {
	enabled = {}, -- [moduleKey] = bool, only for modules the user has toggled
	panel = { collapsed = {} }, -- also layout = saved size and position, selected = module key
	cinematic = {}, -- engine-owned (musicVolumeBackup)
	toast = {}, -- social toasts: point = saved position
}

-- Settings migrations, in order, each run once per SavedVariables (TomteDB.schema, Modules.lua RunMigrations).
-- Only add to the end. Some modules still migrate their own keys on init: Session_Migrate (SessionData.lua),
-- Gear_MigrateHinted (Gear) and NextUp's placedUnderChars.
local MIGRATIONS = {
	-- 1: keys of removed features: the old panel's category filter, the old FlightTimer hand-over flag.
	function(db)
		if type(db.panel) == "table" then
			db.panel.category = nil
		end
		db.flightImported = nil
	end,
}

-- Settings back to defaults, keeping collected data (Modules.lua). The caller reloads the UI: modules keep
-- state in closures.
function ns.ResetAll()
	ns.ResetAllSettings(ns.db, CORE_DEFAULTS)
end

function ns.Print(msg)
	print(ns.PREFIX .. msg)
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

function f:ADDON_LOADED(name)
	if name ~= addonName then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	local db = TomteDB or {}
	ns.RunMigrations(db, MIGRATIONS)
	TomteDB = ns.MergeDefaults(CORE_DEFAULTS, db)
	ns.db = TomteDB
	ns.Session_Init(TomteDB) -- before the modules: their world handlers read the session
	ns.InitModules(TomteDB)
	ns.Panel_Init()
end

-- Modules turned on at runtime (from the panel) can rely on the world being there after this.
function f:PLAYER_ENTERING_WORLD()
	ns.inWorld = true
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

-- One help line: the command in the Tomte blue, the description in grey.
local function PrintCommand(command, description)
	print(("  |cff66ccff%s|r |cffaaaaaa- %s|r"):format(command, description))
end

local function PrintModuleCommands(module)
	for _, cmd in ipairs(module.commands or {}) do
		if not cmd.hidden then -- debug commands work but stay out of help
			PrintCommand(("/tomte %s %s"):format(module.key, cmd[1]), cmd[2])
		end
	end
	if module.fallbackCommand then
		local cmd = module.fallbackCommand
		PrintCommand(("/tomte %s %s"):format(module.key, cmd[1]), cmd[2])
	end
end

local function PrintHelp()
	ns.Print("commands:")
	PrintCommand("/tomte", "open Tomte (Home)")
	PrintCommand("/tomte help", "this list")
	PrintCommand("/tomte version", "which Tomte version you have (say it when you report a bug)")
	PrintCommand("/tomte data", "which expansion's content Tomte follows for you, and what it knows about it")
	for _, module in ipairs(ns.modules) do
		PrintModuleCommands(module)
	end
end

-- "preview mount" runs the "preview" command with "mount". Text that matches no command goes to the module's
-- fallbackCommand (if it has one and its pattern matches), with the whole text.
local function RunModuleCommand(module, text)
	local name, arg = text:match("^(%S*)%s*(.-)$")
	for _, cmd in ipairs(module.commands) do
		if cmd[1] == name then
			cmd[3](arg)
			return
		end
	end
	local fallback = module.fallbackCommand
	if fallback and text:match(fallback.pattern) then
		fallback[3](text)
		return
	end
	ns.Print(module.name .. " commands:")
	PrintModuleCommands(module)
end

-- Keybinds (Bindings.xml, Key Bindings > Tomte): the binding scripts need a global. Modules add their own
-- handlers to ns.bindings (they check that they're on); TOGGLE is the window's.
ns.bindings = {
	TOGGLE = function()
		ns.Panel_Toggle()
	end,
}
function Tomte_Binding(name)
	local handler = ns.bindings[name]
	if handler then
		handler()
	end
end
BINDING_NAME_TOMTE_TOGGLE = "Toggle Tomte"

SLASH_TOMTE1 = "/tomte"
SlashCmdList.TOMTE = function(msg)
	local word, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	word, rest = word:lower(), rest:lower()
	if word == "" then
		ns.Panel_Toggle()
	elseif word == "help" then
		PrintHelp()
	elseif word == "version" then
		ns.Print(("version %s, game %s (%s)."):format(ns.VERSION, GetBuildInfo(), select(2, GetBuildInfo())))
	elseif word == "data" then
		ns.Content_Report()
	else
		local module = ns.modulesByKey[word]
		if module and module.commands then
			RunModuleCommand(module, rest)
		else
			ns.Print("unknown command, see /tomte help.")
		end
	end
end
