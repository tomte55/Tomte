local addonName, ns = ...

-- Tomte core: saved variables, module start-up and /tomte. Modules register themselves at file load
-- (Modules.lua); everything is started here on ADDON_LOADED.

ns.PREFIX = "|cff66ccffTomte|r: "
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
	TomteDB = ns.MergeDefaults(CORE_DEFAULTS, TomteDB or {})
	TomteDB.panel.category = nil -- the old panel's category filter
	TomteDB.flightImported = nil -- the old FlightTimer hand-over flag
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
		PrintCommand(("/tomte %s %s"):format(module.key, cmd[1]), cmd[2])
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

SLASH_TOMTE1 = "/tomte"
SlashCmdList.TOMTE = function(msg)
	local word, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	word, rest = word:lower(), rest:lower()
	if word == "" then
		ns.Panel_Toggle()
	elseif word == "help" then
		PrintHelp()
	else
		local module = ns.modulesByKey[word]
		if module and module.commands then
			RunModuleCommand(module, rest)
		else
			ns.Print("unknown command, see /tomte help.")
		end
	end
end
