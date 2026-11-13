local addonName, ns = ...

-- DPS meter: a small meter with the top few damage dealers of the fight and your own place. Main file: db, events,
-- when it shows, options, Edit Mode. The game counts the damage (C_DamageMeter, read in Read.lua); rules in Data.lua,
-- the window in Window.lua. Blizzard's own meter window and its settings are left alone.

local ICON = 236188 -- ability_hunter_markedfordeath
local REDRAW = 0.5 -- seconds: the game's session updates come many times a second in combat
local FADE_SECONDS = 0.6
-- The default spot for each direction it grows: above the bottom-right action bars, its fixed edge where it starts.
local DEFAULT_POINT = {
	up = { "BOTTOMRIGHT", "BOTTOMRIGHT", -330, 220 },
	down = { "TOPRIGHT", "BOTTOMRIGHT", -330, 300 },
}
-- The settings the window draws with (Window.lua's style), read from db or, for the settings preview, its getter.
local STYLE_KEYS = { "lines", "ranks", "number", "classNames", "barColor", "barAlpha", "background", "bgAlpha", "width",
	"rowHeight", "textSize" }

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
	local p = db.frame.point or DEFAULT_POINT[db.grow] or DEFAULT_POINT.up
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- Saves where the meter is by the edge it grows from (its bottom-left growing up, its top-left growing down), so new
-- lines push the other edge and the saved one stays put.
local function SavePoint()
	if db.grow ~= "up" then
		db.frame.point = UI.TopLeftPoint(frame)
		return
	end
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if left and bottom then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
		db.frame.point = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
	end
end

local function Style(get)
	local style = {}
	for _, key in ipairs(STYLE_KEYS) do
		style[key] = get(key)
	end
	return style
end

local function FromDB(key)
	return db[key]
end

local function Shows()
	if ns.EditMode_Active() then
		return true
	end
	return ns.Meter_Shows({
		grouped = IsInGroup(), solo = db.solo, inCombat = inCombat,
		endedAgo = endedAt and GetTime() - endedAt or nil, linger = db.linger,
		instancesOnly = db.instancesOnly, inInstance = IsInInstance(),
	})
end

local function Draw()
	if not frame then
		frame = ns.MeterUI_New(UIParent)
		frame:Hide()
		Place()
	end
	frame:SetScale(db.scale)
	local ranking = ns.MeterRead_Ranking(db.counts == "session", db.kind == "healing")
	-- The made-up sample only in Edit Mode, so the meter has something to move; a fight starts with no lines.
	if #ranking.sources == 0 and ns.EditMode_Active() then
		ranking = nil
	end
	ns.MeterUI_Draw(frame, ranking, Style(FromDB))
	-- A spot saved while it grew the other way: kept where it is on screen, saved by the edge it now grows from.
	if not ns.Meter_PointFits(db.frame.point, db.grow) then
		SavePoint()
	end
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
	saved = SavePoint,
	module = "meter",
	options = { "lines", "grow", "width", "scale" },
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
	return ns.MeterUI_Preview(host, Style(get), get("scale") or 1)
end

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

local function Pixels(v)
	return ("%d"):format(v)
end

local function ResetSpot()
	db.frame.point = nil
	if frame then
		Place()
	end
end

-- A new direction keeps the meter where it is on screen (saved by its other edge); the default spot has one each.
local function GrowChanged()
	if frame and db.frame.point then
		SavePoint()
	elseif frame then
		Place()
	end
	Redraw()
end

local function Choices(...)
	local list = {}
	for i = 1, select("#", ...), 2 do
		local value, text = select(i, ...)
		list[#list + 1] = { value = value, text = text }
	end
	return function()
		return list
	end
end

module = ns.RegisterModule({
	key = "meter",
	name = "DPS meter",
	category = "class",
	icon = ICON,
	summary = "A small meter with the top damage dealers of the fight and your own place.",
	description = "A few thin lines with the damage per second of the top damage dealers in the fight, and yours below "
		.. "them when you're further down; healing instead if you like. Shows in a group from the start of a fight "
		.. "until a few seconds after it, then fades. The game counts the damage itself; Blizzard's own meter window "
		.. "can stay off.",
	enabledByDefault = false,
	alongside = { { addon = "MelloUI", why = "its own damage meter shows the same numbers beside your frames: keep the one you like" } },
	defaults = {
		lines = 3, -- top places shown; your own line comes on top of these when you're further down
		solo = false,
		linger = 10, -- seconds it stays after a fight
		counts = "fight", -- "fight" | "session" (every fight since the game's meter was reset)
		kind = "damage", -- "damage" | "healing"
		number = "rate", -- "rate" (per second) | "total" | "both"
		ranks = true, -- the place number at the start of each line
		classNames = true,
		barColor = "class", -- "class" | "theme" (the theme's accent)
		barAlpha = 0.4, -- the bars sit behind the text, so they're a tint by default
		background = true,
		bgAlpha = 0.5,
		width = 170,
		rowHeight = 15,
		textSize = 11,
		grow = "up", -- "up" (its bottom edge stays put) | "down" (its top edge stays put)
		instancesOnly = false,
		scale = 1,
		frame = {}, -- point: the meter's spot, saved by the edge it grows from (SavePoint); nil for the default
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
		{ "why", "say why the DPS meter shows or not", function()
			local ok, why = ns.MeterRead_Available()
			ns.Print(("on: %s, damage meter: %s%s"):format(tostring(active), tostring(ok),
				why and (" (" .. why .. ")") or ""))
			ns.Print(("grouped: %s, solo setting: %s, in combat: %s, Edit Mode: %s, fight ended %s s ago"):format(
				tostring(IsInGroup()), tostring(db.solo), tostring(inCombat), tostring(ns.EditMode_Active()),
				endedAt and ("%.0f"):format(GetTime() - endedAt) or "-"))
			ns.Print(("shows: %s, frame: %s, shown: %s, alpha: %s"):format(tostring(Shows()),
				frame and "made" or "none", tostring(frame and frame:IsShown()),
				frame and ("%.2f"):format(frame:GetAlpha()) or "-"))
			-- pcall: this command is for finding out why the read fails, so it reports the error instead of raising it.
			local read, result = pcall(ns.MeterRead_Ranking, db.counts == "session", db.kind == "healing")
			ns.Print(read and ("ranking read: %d sources"):format(#result.sources)
				or ("ranking read failed: " .. tostring(result)))
		end },
		{ "reset", "put the DPS meter back in its default spot", ResetSpot },
	},
	options = {
		{ type = "header", label = "Meter" },
		{ type = "dropdown", key = "kind", label = "Shows", onChange = Redraw,
			choices = Choices("damage", "Damage", "healing", "Healing") },
		{ type = "dropdown", key = "counts", label = "Counts", onChange = Redraw,
			choices = Choices("fight", "This fight", "session", "Whole session"),
			tooltip = "Whole session: every fight since the game's meter was last reset." },
		{ type = "dropdown", key = "number", label = "Number", onChange = Redraw, preview = Preview,
			choices = Choices("rate", "Per second", "total", "Total", "both", "Both"),
			tooltip = "Both: the amount per second, with the total beside it." },
		{ type = "slider", key = "lines", label = "Places shown", min = 3, max = 10, step = 1, onChange = Redraw,
			preview = Preview, tooltip = "The top places. Yours shows under them when you're further down." },
		{ type = "checkbox", key = "ranks", label = "Place numbers", onChange = Redraw, preview = Preview },
		{ type = "header", label = "Look" },
		{ type = "checkbox", key = "classNames", label = "Names in class colors", onChange = Redraw, preview = Preview },
		{ type = "dropdown", key = "barColor", label = "Bar color", onChange = Redraw, preview = Preview,
			choices = Choices("class", "Class", "theme", "Theme") },
		{ type = "slider", key = "barAlpha", label = "Bar opacity", min = 0.1, max = 1, step = 0.05, format = Percent,
			onChange = Redraw, preview = Preview },
		{ type = "checkbox", key = "background", label = "Background", onChange = Redraw, preview = Preview,
			tooltip = "A dark backing behind the lines, so they read on bright ground." },
		{ type = "slider", key = "bgAlpha", label = "Background opacity", min = 0.1, max = 1, step = 0.05,
			format = Percent, parent = "background", onChange = Redraw, preview = Preview },
		{ type = "slider", key = "width", label = "Width", min = 120, max = 320, step = 10, format = Pixels,
			onChange = Redraw, preview = Preview },
		{ type = "slider", key = "rowHeight", label = "Line height", min = 12, max = 26, step = 1, format = Pixels,
			onChange = Redraw, preview = Preview },
		{ type = "slider", key = "textSize", label = "Text size", min = 8, max = 16, step = 1, format = Pixels,
			onChange = Redraw, preview = Preview },
		{ type = "slider", key = "scale", label = "Size", min = 0.7, max = 1.5, step = 0.05, format = Percent,
			onChange = function()
				if frame then
					frame:SetScale(db.scale)
				end
			end, preview = Preview, tooltip = "The whole meter, bigger or smaller." },
		{ type = "dropdown", key = "grow", label = "Grows", onChange = GrowChanged,
			choices = Choices("up", "Up", "down", "Down"),
			tooltip = "Up: the bottom edge stays put and more lines push the top up. Down: the other way round." },
		{ type = "button", label = "Position", text = "Reset", onClick = ResetSpot,
			tooltip = "Move it back to its default spot. Blizzard's Edit Mode moves it too." },
		{ type = "header", label = "When it shows" },
		{ type = "checkbox", key = "solo", label = "Also when you're on your own", onChange = Apply },
		{ type = "checkbox", key = "instancesOnly", label = "Only in dungeons and raids", onChange = Apply },
		{ type = "slider", key = "linger", label = "Stays after a fight", min = 3, max = 60, step = 1,
			format = function(v)
				return ("%d s"):format(v)
			end, tooltip = "Then it fades out until the next fight." },
	},
})
