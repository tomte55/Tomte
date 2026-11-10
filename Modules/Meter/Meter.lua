local addonName, ns = ...

-- DPS meter: a small meter with the top few damage dealers of the fight and your own place. Main file: db, events,
-- when it shows, options, Edit Mode. The game counts the damage (C_DamageMeter, read in Read.lua); rules in Data.lua,
-- the window in Window.lua. Blizzard's own meter window and its settings are left alone.

local ICON = 236188 -- ability_hunter_markedfordeath
local REDRAW = 0.5 -- seconds: the game's session updates come many times a second in combat
local FADE_SECONDS = 0.6
local DEFAULT_POINT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -330, 220 }

local UI = ns.UI

local module, db, frame
local active = false
local events = ns.NewEvents()
local OWNER = "meter"
local inCombat = false
local endedAt -- GetTime when your last fight ended
local redrawPending = false
local lingerTimer

local function Place()
	local p = db.frame.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function Shows()
	if ns.EditMode_Active() then
		return true
	end
	return ns.Meter_Shows({
		grouped = IsInGroup(), solo = db.solo, inCombat = inCombat,
		endedAgo = endedAt and GetTime() - endedAt or nil, linger = db.linger,
	})
end

local function Draw()
	if not frame then
		frame = ns.MeterUI_New(UIParent)
		frame:Hide()
		Place()
	end
	frame:SetScale(db.scale)
	ns.MeterUI_Draw(frame, ns.MeterRead_Ranking(db.counts == "session"), db.lines)
end

-- Shown or faded out, as Shows says; drawn fresh when it comes up.
local function Apply()
	if not active then
		if frame then
			frame:Hide()
		end
		return
	end
	if Shows() then
		Draw()
		if not frame:IsShown() then
			frame:SetAlpha(0)
			frame:Show()
		end
		UI.AlphaTo(frame, 1, FADE_SECONDS)
	elseif frame and frame:IsShown() then
		UI.AlphaTo(frame, 0, FADE_SECONDS, function()
			if not Shows() then
				frame:Hide()
			end
		end)
	end
end

local function RedrawSoon()
	if redrawPending or not (frame and frame:IsShown()) then
		return
	end
	redrawPending = true
	C_Timer.After(REDRAW, function()
		redrawPending = false
		if active and frame and frame:IsShown() then
			Draw()
		end
	end)
end

local function CombatStart()
	inCombat = true
	Apply()
end

local function CombatEnd()
	inCombat = false
	endedAt = GetTime()
	Apply()
	if lingerTimer then
		lingerTimer:Cancel()
	end
	lingerTimer = C_Timer.NewTimer(db.linger, function()
		lingerTimer = nil
		Apply()
	end)
end

local WATCHED = {
	PLAYER_REGEN_DISABLED = CombatStart,
	PLAYER_REGEN_ENABLED = CombatEnd,
	GROUP_ROSTER_UPDATE = Apply,
	DAMAGE_METER_COMBAT_SESSION_UPDATED = RedrawSoon,
	DAMAGE_METER_CURRENT_SESSION_UPDATED = RedrawSoon,
	DAMAGE_METER_RESET = RedrawSoon,
}
for event, fn in pairs(WATCHED) do
	events:On(OWNER, event, fn)
end

local function Start()
	active = true
	inCombat = InCombatLockdown()
	for event in pairs(WATCHED) do
		events:TryWatch(OWNER, event)
	end
	Apply()
end

local function Stop()
	active = false
	events:UnwatchAll(OWNER)
	if lingerTimer then
		lingerTimer:Cancel()
		lingerTimer = nil
	end
	endedAt = nil
	Apply()
end

ns.EditMode_Register({
	name = "DPS meter",
	frame = function()
		return frame
	end,
	refresh = function()
		Apply()
	end,
	saved = function()
		db.frame.point = UI.TopLeftPoint(frame)
	end,
	module = "meter",
	options = { "lines", "scale" },
	reset = function()
		db.frame.point = nil
		if frame then
			Place()
		end
	end,
})

-- Options ---------------------------------------------------------------------------------------------------------

local function Redraw()
	if frame and frame:IsShown() then
		Draw()
	end
end

local function Preview(host, get)
	return ns.MeterUI_Preview(host, get("lines") or 3, get("scale") or 1)
end

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

module = ns.RegisterModule({
	key = "meter",
	name = "DPS meter",
	category = "class",
	icon = ICON,
	summary = "A small meter with the top damage dealers of the fight and your own place.",
	description = "A few thin lines with the damage per second of the top damage dealers in the fight, and yours below "
		.. "them when you're further down. Shows in a group from the start of a fight until a few seconds after it, "
		.. "then fades. The game counts the damage itself; Blizzard's own meter window can stay off.",
	enabledByDefault = false,
	defaults = {
		lines = 3, -- top places shown; your own line comes on top of these when you're further down
		solo = false,
		linger = 10, -- seconds it stays after a fight
		counts = "fight", -- "fight" | "session" (every fight since the game's meter was reset)
		scale = 1,
		frame = {}, -- point: the meter's spot (UI.TopLeftPoint), nil for the default
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	blocked = function()
		local ok, why = ns.MeterRead_Available()
		if not ok then
			return why
		end
	end,
	toggle = function(on)
		if on then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "reset", "put the DPS meter back in its default spot", function()
			db.frame.point = nil
			if frame then
				Place()
			end
		end },
	},
	options = {
		{ type = "header", label = "Meter" },
		{ type = "slider", key = "lines", label = "Places shown", min = 3, max = 5, step = 1, onChange = Redraw,
			preview = Preview, tooltip = "The top places. Yours shows under them when you're further down." },
		{ type = "dropdown", key = "counts", label = "Counts", onChange = Redraw,
			choices = function()
				return { { value = "fight", text = "This fight" }, { value = "session", text = "Whole session" } }
			end, tooltip = "Whole session: every fight since the game's meter was last reset." },
		{ type = "slider", key = "scale", label = "Size", min = 0.7, max = 1.5, step = 0.05, format = Percent,
			onChange = function()
				if frame then
					frame:SetScale(db.scale)
				end
			end, preview = Preview },
		{ type = "button", label = "Position", text = "Reset", onClick = function()
			db.frame.point = nil
			if frame then
				Place()
			end
		end, tooltip = "Move it back to its default spot. Blizzard's Edit Mode moves it too." },
		{ type = "header", label = "When it shows" },
		{ type = "checkbox", key = "solo", label = "Also when you're on your own", onChange = Apply },
		{ type = "slider", key = "linger", label = "Stays after a fight", min = 3, max = 60, step = 1,
			format = function(v)
				return ("%d s"):format(v)
			end, tooltip = "Then it fades out until the next fight." },
	},
})
