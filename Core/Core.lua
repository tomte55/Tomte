local addonName, ns = ...

-- Tomte core: saved variables, module start-up and /tomte. Modules register themselves at file load
-- (Modules.lua); everything is started here on ADDON_LOADED.

ns.PREFIX = "|cff66ccffTomte|r: "
-- Panel title bar and minimap button. The TOC's IconTexture is set separately (it can't read this).
ns.ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
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
	ns.db = TomteDB
	ns.Migration_Run(TomteDB) -- before modules get their db
	ns.InitModules(TomteDB)
	ns.Panel_Init()
end

-- Modules turned on at runtime (from the panel) can rely on the world being there after this.
function f:PLAYER_ENTERING_WORLD()
	ns.inWorld = true
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

local function PrintHelp()
	ns.Print("commands:")
	print("  /tomte - open the settings panel")
	print("  /tomte help - this list")
	for _, module in ipairs(ns.modules) do
		for _, cmd in ipairs(module.commands or {}) do
			print(("  /tomte %s %s - %s"):format(module.key, cmd[1], cmd[2]))
		end
	end
end

-- "preview mount" runs the "preview" command with "mount".
local function RunModuleCommand(module, text)
	local name, arg = text:match("^(%S*)%s*(.-)$")
	for _, cmd in ipairs(module.commands) do
		if cmd[1] == name then
			cmd[3](arg)
			return
		end
	end
	ns.Print(module.name .. " commands:")
	for _, cmd in ipairs(module.commands) do
		print(("  /tomte %s %s - %s"):format(module.key, cmd[1], cmd[2]))
	end
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
