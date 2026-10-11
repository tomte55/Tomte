local addonName, ns = ...

-- Tomte core: saved variables, module start-up and /tomte. Modules register themselves at file load
-- (Modules.lua); everything is started here on ADDON_LOADED.

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
	cinematic = {}, -- engine-owned (musicVolumeBackup, pitchLimitBackup)
	toast = {}, -- social toasts: point = saved position
	setup = {}, -- first-run picker (Core/Setup.lua, Panel/Setup.lua): state = "pending" | "done", preset = last applied
	bugs = {}, -- Tomte's last Lua errors, only without BugGrabber (Panel/Bug.lua); never exported or reset
	-- profileBackup = { at, text }: settings from before the last import (Panel/Share.lua), no default
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
	-- 2: the first-run picker (1.5): saved variables from before it are an existing user's. No picker and no
	-- message for them; a fresh install was marked "pending" before the migrations ran.
	function(db)
		ns.Setup_Migrate(db)
	end,
	-- 3: Moments' "Cinematics only at max level" checkbox became the per-moment "Cinematic at max level" style.
	function(db)
		ns.Moments_MigrateAtMax(db.moments)
	end,
}

-- Settings back to defaults, keeping collected data (Modules.lua). The caller reloads the UI: modules keep
-- state in closures.
function ns.ResetAll()
	ns.ResetAllSettings(ns.db, CORE_DEFAULTS)
end

-- "Tomte: " in the accent color, built when used: the theme is only chosen on ADDON_LOADED.
function ns.Prefix()
	return ns.Theme.Wrap("Tomte", "accent") .. ": "
end

function ns.Print(msg)
	print(ns.Prefix() .. msg)
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Map pins and super-tracking (C_Map.SetUserWaypoint, C_SuperTrack.Set*). Their events fire inside the call, so
-- Blizzard's map refreshes its pins in our (tainted) code; in combat that hits a protected call
-- (Button:SetPassThroughButtons, ADDON_ACTION_BLOCKED). In combat fn waits for the end of it; only the latest
-- waits. Returns true when it ran now.
local afterCombat
function ns.SafeTrack(fn)
	if not InCombatLockdown() then
		fn()
		return true
	end
	afterCombat = fn
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	return false
end

-- A pin change is waiting for the end of combat (the map's pin isn't the one we placed yet).
function ns.SafeTrack_Waiting()
	return afterCombat ~= nil
end

function f:PLAYER_REGEN_ENABLED()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local fn = afterCombat
	afterCombat = nil
	if fn then
		fn()
	end
end

function f:ADDON_LOADED(name)
	if name ~= addonName then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	local fresh = TomteDB == nil
	local db = TomteDB or {}
	if fresh then
		ns.Setup_MarkFresh(db) -- before the migrations: migration 2 marks only older saved variables as done
	end
	-- First, before anything draws: the theme picked in Settings (Panel/Window.lua).
	ns.Theme.Apply(type(db.window) == "table" and db.window.theme or nil)
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

-- One help line: the command in the accent, the description muted.
local function PrintCommand(command, description)
	print(("  %s %s"):format(ns.Theme.Wrap(command, "accent"), ns.Theme.Wrap("- " .. description, "textMuted")))
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
	PrintCommand("/tomte version", "which Tomte version you have (/tomte bug makes a whole bug report)")
	PrintCommand("/tomte data", "which expansion's content Tomte follows for you, and what it knows about it")
	PrintCommand("/tomte setup", "pick what Tomte turns on: Collector, Crafter, Minimal or Everything")
	PrintCommand("/tomte bug", "a bug report to copy: versions, modules and Tomte's last errors ('full' adds error "
		.. "details and your settings, 'clear' empties Tomte's saved errors)")
	PrintCommand("/tomte profile", "share settings with a friend: export, import, undo")
	for _, module in ipairs(ns.modules) do
		PrintModuleCommands(module)
	end
end

-- "preview mount" runs the "preview" command with "mount". Text that matches no command goes to the module's
-- fallbackCommand (if it has one and its pattern matches), with the whole text.
-- Handlers get the text lowercased, then as typed (item links and names keep their case):
--   cmd[3](arg, rawArg)  fallback[3](text, rawText)
local function RunModuleCommand(module, text, rawText)
	rawText = rawText or text
	local name, arg = text:match("^(%S*)%s*(.-)$")
	local rawArg = rawText:match("^%S*%s*(.-)$")
	for _, cmd in ipairs(module.commands) do
		if cmd[1] == name then
			cmd[3](arg, rawArg)
			return
		end
	end
	local fallback = module.fallbackCommand
	if fallback and text:match(fallback.pattern) then
		fallback[3](text, rawText)
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
	local word, rawRest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	local rest
	word, rest = word:lower(), rawRest:lower()
	if word == "" then
		ns.Panel_Toggle()
	elseif word == "help" then
		PrintHelp()
	elseif word == "version" then
		ns.Print(("version %s, game %s (%s)."):format(ns.VERSION, GetBuildInfo(), select(2, GetBuildInfo())))
	elseif word == "data" then
		ns.Content_Report()
	elseif word == "setup" then
		ns.SetupUI_Show()
	elseif word == "bug" then
		if rest == "clear" then
			ns.BugUI_Clear()
		elseif rest == "selftest" then
			ns.BugUI_SelfTest()
		else
			ns.BugUI_Show(rest == "full" and "full" or nil)
		end
	elseif word == "profile" then
		if rest == "export" then
			ns.ShareUI_Export()
		elseif rest == "import" then
			ns.ShareUI_Import()
		elseif rest == "undo" then
			ns.ShareUI_Undo()
		elseif rest == "selftest" then
			ns.ShareUI_SelfTest()
		else
			ns.Print("settings profile commands:")
			PrintCommand("/tomte profile export", "your settings as a string to give a friend")
			PrintCommand("/tomte profile import", "paste a friend's string, see what changes, then import")
			PrintCommand("/tomte profile undo", "go back to your settings from before the last import")
		end
	else
		local module = ns.modulesByKey[word]
		if module and module.commands then
			RunModuleCommand(module, rest, rawRest)
		else
			ns.Print("unknown command, see /tomte help.")
		end
	end
end
