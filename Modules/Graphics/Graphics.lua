local addonName, ns = ...

-- Graphics presets: a graphics quality level and a frame rate cap per kind of place (open world, cities, dungeons
-- and delves, raids, PvP, AFK). Tomte keeps the player's own values the first time it changes a CVar and puts them
-- back when no preset applies, on logout and when the module turns off. A change the player makes by hand wins:
-- Tomte adopts it and stays out of that group until the situation changes. Pure rules in Data.lua.

local SETTLE = 2 -- seconds after the last zone, resting or AFK event before applying: one write per loading screen
local DETECT_DELAY = 0.5 -- seconds: Blizzard's quality slider writes ~14 CVars in a row, check once after them
local SLIDER_DELAY = 0.5 -- seconds after the last move of one of our sliders: no texture reload per step
local FPS_MAX, FPS_STEP = 200, 10 -- Blizzard's frame rate slider tops out at 200
local RAID_SETTINGS_CVAR = "RAIDsettingsEnabled" -- Blizzard's "Raid and Battleground" graphics switch
-- Settings order on the page (Data.lua's GRAPHICS_SITUATIONS is the priority order).
local PAGE_ORDER = { "world", "city", "dungeon", "raid", "pvp", "afk" }
-- Every default: nothing changes until the player picks a level or cap for a place.
local LEAVE_ALONE = 0
local UI = ns.UI

local GetCVar, SetCVar, GetCVarBool = C_CVar.GetCVar, C_CVar.SetCVar, C_CVar.GetCVarBool
local Plan, Decide, Situations = ns.Graphics_Plan, ns.Graphics_Decide, ns.Graphics_Situations
local RaidCVar = ns.Graphics_RaidCVar

local module, db
local ORDER = ns.Graphics_AllCVars()
local GROUP_OF = ns.Graphics_GroupOf()
local LOWER = {} -- [lowercased cvar] = true: CVAR_UPDATE's name may not keep the registered case
for cvar in pairs(GROUP_OF) do
	LOWER[cvar:lower()] = true
end
local LABELS = {}
for _, s in ipairs(ns.GRAPHICS_SITUATIONS) do
	LABELS[s.key] = s.label
end

-- [group] = situation key: the player changed that group by hand there; Tomte stays out until another situation
-- wins (Data.lua's Graphics_Decide). Session only: a new session starts from the presets again.
local paused = {}
local writing = false -- our own SetCVar calls: CVAR_UPDATE fires inside them (a synchronous event)
local pendingCombat = false
local lastAFK = false
local lastDecision = {}

-- Reading the game --------------------------------------------------------------------------------------------

-- The AFK flag is a secret value in chat lockdown (instances, encounters): keep the last readable one then.
local function ReadAFK()
	local afk = UnitIsAFK("player")
	if not ns.IsSecret(afk) then
		lastAFK = afk and true or false
	end
	return lastAFK
end

local function CurrentSituations()
	local _, instanceType, difficultyID = GetInstanceInfo()
	return Situations({ instanceType = instanceType, difficultyID = difficultyID, resting = IsResting(),
		afk = ReadAFK() })
end

-- [cvar] = value for every CVar Tomte may touch; nil for one this client doesn't have.
local function ReadCurrent()
	local current = {}
	for _, cvar in ipairs(ORDER) do
		current[cvar] = GetCVar(cvar)
	end
	return current
end

-- Wanted values -----------------------------------------------------------------------------------------------

-- The overall quality and every setting Blizzard's Graphics Quality slider moves with it, the way the slider does
-- it (Blizzard_SettingsDefinitions_Shared/Graphics.lua, OnGCChanged): GetGraphicsCVarValueForQualityLevel per
-- setting, raised to the setting's minimum. Without that function only the overall CVar is set.
local function AddQualitySet(wanted, value, raid)
	local base = ns.GRAPHICS_QUALITY_CVAR
	wanted[raid and RaidCVar(base) or base] = tostring(value)
	if not GetGraphicsCVarValueForQualityLevel then
		return
	end
	local density = C_VideoOptions.IsSpellVisualDensitySystemSupported()
	for _, sub in ipairs(ns.GRAPHICS_QUALITY_SUBS) do
		if density or not sub.spellDensity then
			local cvar = raid and RaidCVar(sub.cvar) or sub.cvar
			-- Undocumented API (used by Blizzard's settings): may error for a setting this client lacks.
			local ok, index = pcall(GetGraphicsCVarValueForQualityLevel, cvar, value, raid)
			if ok and type(index) == "number" then
				local min = (not raid and sub.min) or -1
				wanted[cvar] = tostring(math.max(min, index))
			end
		end
	end
end

local function Wanted(decision)
	local wanted = {}
	local quality = decision.quality and ns.Graphics_QualityValue(decision.quality.value)
	if quality then
		AddQualitySet(wanted, quality, false)
		-- With the Raid and Battleground switch on the game uses the raid copies in raids and battlegrounds, so
		-- they get the same level (and are restored the same way).
		if GetCVarBool(RAID_SETTINGS_CVAR) then
			AddQualitySet(wanted, quality, true)
		end
	end
	if decision.fps then
		wanted.useMaxFPS = "1"
		wanted.maxFPS = tostring(decision.fps.value)
	end
	return wanted
end

-- Writing -----------------------------------------------------------------------------------------------------

-- Brings the CVars to `wanted` (nothing else is restored) and records what they read back as afterwards: the game
-- may adjust a value, and a later difference from that is a change by someone else.
local function Apply(wanted)
	local writes = Plan(db.saved, wanted, ReadCurrent(), ORDER)
	writing = true
	for _, w in ipairs(writes) do
		SetCVar(w.cvar, w.value)
	end
	writing = false
	for _, cvar in ipairs(ORDER) do
		db.applied[cvar] = wanted[cvar] ~= nil and GetCVar(cvar) or nil
	end
	return #writes
end

-- The player's own values back for everything Tomte changed.
local function RestoreAll()
	return Apply({})
end

-- Someone (the player, the Settings panel, another addon) changed a CVar Tomte set: their value wins for that group.
-- quiet: adopt without the pause or the chat line. Used at the first check of a session (a difference then means the
-- last session ended without the logout restore: adopt and let the presets apply as usual) and right before a
-- restore (logout, turning off, "Restore my settings now").
local function Detect(quiet)
	local changed = ns.Graphics_ChangedGroups(db.applied, ReadCurrent(), GROUP_OF)
	local any = false
	for _, group in ipairs(ns.GRAPHICS_GROUPS) do
		if changed[group] then
			ns.Graphics_Adopt(db.saved, db.applied, group, GROUP_OF)
			if not quiet then
				paused[group] = ns.Graphics_Winner(CurrentSituations(), db, group) or false
			end
			any = true
		end
	end
	if any and not quiet then
		ns.Print("Graphics presets: you changed your graphics, so they stay as you set them until you go somewhere else.")
	end
end

local fresh = true -- no Update yet this session

local function Update()
	if not module.active then
		return
	end
	if InCombatLockdown() then
		pendingCombat = true -- a quality change can stall a frame: never mid-fight
		return
	end
	Detect(fresh)
	fresh = false
	lastDecision = Decide(CurrentSituations(), db, paused)
	Apply(Wanted(lastDecision))
end

local updateSoon = UI.Debounce(SETTLE, Update)
local applySoon = UI.Debounce(SLIDER_DELAY, Update)
-- Detect only reads CVars (no writes), so it runs in combat too: a change made in combat must not be overwritten
-- by a later restore.
local detectSoon = UI.Debounce(DETECT_DELAY, function()
	if module.active then
		Detect()
	end
end)

-- "Restore my settings now": the player's values back, and hands off until the situation changes.
local function Restore()
	if not ns.Module_RequireOn(module) then
		return
	end
	Detect(true) -- a hand change still inside the detect delay is the player's own value now
	local situations = CurrentSituations()
	for _, group in ipairs(ns.GRAPHICS_GROUPS) do
		paused[group] = ns.Graphics_Winner(situations, db, group) or false
	end
	RestoreAll()
	lastDecision = {}
	ns.Print("Graphics presets: your own graphics settings are back. Tomte leaves them alone until you go somewhere else.")
end

-- /tomte graphics why -----------------------------------------------------------------------------------------

local function GroupLine(group, decision, text)
	if decision then
		return LABELS[decision.situation] .. ": " .. text(decision.value)
	elseif paused[group] then
		return "kept as you set it in " .. (LABELS[paused[group]] or "this place") .. " (until you go somewhere else)"
	end
	return "leave alone (your own setting)"
end

local function Why()
	local names = {}
	for i, key in ipairs(CurrentSituations()) do
		names[i] = LABELS[key]
	end
	ns.Print("Graphics presets: here counts as " .. table.concat(names, ", ") .. ".")
	ns.Print("quality: " .. GroupLine("quality", lastDecision.quality, ns.Graphics_QualityText))
	ns.Print("frame rate cap: " .. GroupLine("fps", lastDecision.fps, ns.Graphics_FPSText))
	local quality = tonumber(GetCVar(ns.GRAPHICS_QUALITY_CVAR))
	local line = "graphics quality now: " .. (quality and ("level " .. (quality + 1)) or "?")
	local own = tonumber(db.saved[ns.GRAPHICS_QUALITY_CVAR])
	if own then
		line = line .. ", yours: level " .. (own + 1)
	end
	line = line .. (GetCVarBool(RAID_SETTINGS_CVAR) and " (raid and battleground copy follows)" or "")
	ns.Print(line)
	local fps = GetCVarBool("useMaxFPS") and (GetCVar("maxFPS") .. " fps") or "off"
	ns.Print("frame rate cap now: " .. fps .. (db.saved.maxFPS and " (Tomte's; yours comes back after)" or ""))
	if pendingCombat then
		ns.Print("waiting for combat to end before changing anything.")
	end
end

-- Events ------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

events.PLAYER_ENTERING_WORLD = updateSoon
events.ZONE_CHANGED_NEW_AREA = updateSoon
events.PLAYER_UPDATE_RESTING = updateSoon

function events:PLAYER_FLAGS_CHANGED(unit)
	if unit == "player" then
		updateSoon()
	end
end

function events:PLAYER_REGEN_ENABLED()
	if pendingCombat then
		pendingCombat = false
		Update()
	end
end

function events:CVAR_UPDATE(cvarName)
	if writing or type(cvarName) ~= "string" or ns.IsSecret(cvarName) or not LOWER[cvarName:lower()] then
		return
	end
	if next(db.applied) then
		detectSoon()
	end
end

-- Before the client saves the CVars to Config.wtf (also on /reload): the player's own values go there, so nothing
-- of Tomte's stays if it's removed. The next login applies the presets again.
-- Detect first, quietly: a hand change still inside the detect delay must not be undone by the restore.
function events:PLAYER_LOGOUT()
	Detect(true)
	RestoreAll()
end

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING", "PLAYER_FLAGS_CHANGED",
	"PLAYER_REGEN_ENABLED", "CVAR_UPDATE", "PLAYER_LOGOUT",
}

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	if ns.inWorld then -- turned on from the settings: the world is already there
		Update()
	end
end

-- Restores even in combat: the player turned the module off, and these CVars aren't protected.
local function Stop()
	events:UnregisterAllEvents()
	pendingCombat = false
	paused = {}
	lastDecision = {}
	Detect(true) -- a hand change still inside the detect delay stays
	RestoreAll()
end

-- Settings ----------------------------------------------------------------------------------------------------

local function Changed()
	-- A new choice for a place starts fresh there, even after a hand change.
	paused = {}
	applySoon()
end

local options = {
	{ type = "header", label = "Graphics quality" },
}
for _, key in ipairs(PAGE_ORDER) do
	options[#options + 1] = { type = "slider", key = "quality." .. key, label = LABELS[key], min = 0, max = 10,
		step = 1, format = ns.Graphics_SliderText, onChange = Changed,
		tooltip = "The overall Graphics Quality level (1-10, as in the game's Graphics settings) here. Off: your own setting." }
end
options[#options + 1] = { type = "header", label = "Frame rate cap" }
for _, key in ipairs(PAGE_ORDER) do
	options[#options + 1] = { type = "slider", key = "fps." .. key, label = LABELS[key], min = 0, max = FPS_MAX,
		step = FPS_STEP, format = ns.Graphics_SliderText, onChange = Changed,
		tooltip = "Limit the frame rate here, in frames per second (saves power and heat). Off: your own setting." }
end
options[#options + 1] = { type = "header", label = "Your settings" }
options[#options + 1] = { type = "button", label = "Restore my settings now", text = "Restore", onClick = Restore,
	tooltip = "Put your own graphics settings back now. Tomte leaves them alone until you go somewhere else." }
options[#options + 1] = { type = "button", label = "What's applied", text = "Show", onClick = Why,
	tooltip = "Say in chat which place this counts as and what Tomte has changed." }

module = ns.RegisterModule({
	key = "graphics",
	name = "Graphics presets",
	category = "tomte",
	icon = 136243, -- trade_engineering
	summary = "A graphics quality level and frame rate cap for each kind of place.",
	description = "Pick a graphics quality level and a frame rate cap for the open world, cities, dungeons and delves, raids, PvP and while AFK. Tomte switches as you go and puts your own settings back when you leave, when you change them yourself and when you turn this off.",
	enabledByDefault = false, -- changes the game's graphics settings
	defaults = {
		quality = { world = LEAVE_ALONE, city = LEAVE_ALONE, dungeon = LEAVE_ALONE, raid = LEAVE_ALONE,
			pvp = LEAVE_ALONE, afk = LEAVE_ALONE }, -- [situation] = 0 (leave alone) or level 1-10
		fps = { world = LEAVE_ALONE, city = LEAVE_ALONE, dungeon = LEAVE_ALONE, raid = LEAVE_ALONE,
			pvp = LEAVE_ALONE, afk = LEAVE_ALONE }, -- [situation] = 0 (leave alone) or a cap in fps
		saved = {}, -- [cvar] = the player's own value, while Tomte has changed that CVar
		applied = {}, -- [cvar] = what the CVar read back as after Tomte set it (a difference = a hand change)
	},
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
		{ "why", "which place this counts as and what's applied", Why },
		{ "restore", "put your own graphics settings back now", Restore },
	},
	options = options,
})
