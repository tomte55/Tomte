local addonName, ns = ...

-- Cursor highlight: a sharp ring (or thick ring, soft glow, crosshair) around the mouse cursor, shown when you shake
-- the mouse (to find the cursor), and optionally always in combat or always, with an optional pulse; and a trail
-- behind the cursor (flat shapes or a spell effect), with the ring, whenever the mouse moves or in combat.
-- Pure rules (shake detection, the ring's size and fade, the trail's points, colors) in Data.lua; the trail is
-- drawn by Trail.lua. The art comes from tools/cursor_art.py.

-- Polling. The cursor has no "moved" event, so a small driver frame samples GetCursorPosition. It's an OnUpdate
-- rather than a C_Timer ticker because the driver is a child of UIParent: whenever UIParent is hidden (cinematics,
-- movies, Alt+Z) the game stops calling it, so there's no work at all then, and the same script draws the ring and
-- the trail at frame rate while they're shown. While nothing is shown the script returns right away except
-- SAMPLE_RATE times a second, when it reads the cursor once for shake detection and to see whether a waiting trail
-- should start. The driver only exists while the module is on.
local SAMPLE_RATE = 30 -- shake samples per second, shown or not (Data.lua's thresholds assume this spacing)
local SAMPLE_INTERVAL = 1 / SAMPLE_RATE
local TEST_SECONDS = 4
local HALO_SCALE = 1.6 -- the soft glow behind the ring, times the ring's size
local HALO_ALPHA = 0.35 -- the glow's opacity relative to the ring
local RING_LEVEL = 10 -- frame level in the TOOLTIP strata: above the trail (Trail.lua)
local ART = ns.Theme.MEDIA .. "Cursor\\"
local UI = ns.UI

local module, db
local driver, holder, ring, halo
local samples = {}
local shake -- { began, last } while a shake look is playing
local shown, inCombat, testUntil = false, false, nil
local trailBusy = false -- the trail drew something on the last look: keep looking every frame
local sinceSample = 0
local lookState, gateState = {}, {} -- reused every frame
-- Colors for ns.Cursor_Color: the theme accent (read on each sample so a theme switch reaches it), the class color
-- and the custom color (the saved table itself).
local palette = { accent = {} }

local function CursorXY()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

local function ReadPalette()
	local accent = palette.accent
	accent[1], accent[2], accent[3] = UI.RGB("accent")
	palette.custom = db.customColor
end

-- Drawing ------------------------------------------------------------------------------------------------------

local function CreateHolder()
	-- Covers the screen so the ring can be placed by cursor position; never takes the mouse, so clicks go through
	-- to whatever is underneath.
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("TOOLTIP")
	holder:SetFrameLevel(RING_LEVEL)
	holder:EnableMouse(false)
	holder:Hide()

	halo = holder:CreateTexture(nil, "ARTWORK")
	halo:SetTexture(ns.Theme.MEDIA .. "Theme\\Glow")
	halo:SetBlendMode("ADD")

	ring = holder:CreateTexture(nil, "OVERLAY")
	ring:SetBlendMode("ADD")
end

local function ApplyShape()
	local shape = ns.Cursor_Find(ns.CURSOR_RING_SHAPES, db.shape)
	ring:SetTexture(ART .. shape.art)
	halo:SetShown(shape.halo)
end

local function HideRing()
	if shown then
		holder:Hide()
		shown = false
	end
end

local function DrawRing(now, x, y, scale, alpha)
	if alpha <= 0 then
		HideRing()
		return
	end
	if not holder then
		CreateHolder()
	end
	if not shown then
		ApplyShape()
		holder:Show()
		shown = true
	end
	if db.pulse then
		local s, a = ns.Cursor_Pulse(now)
		scale, alpha = scale * s, alpha * a
	end
	local r, g, b = ns.Cursor_Color(db.color, palette, now)
	ring:SetVertexColor(r, g, b)
	halo:SetVertexColor(r, g, b)
	alpha = alpha * db.opacity
	local size = db.size * scale
	ring:SetSize(size, size)
	ring:SetPoint("CENTER", holder, "BOTTOMLEFT", x, y)
	ring:SetAlpha(alpha)
	halo:SetSize(size * HALO_SCALE, size * HALO_SCALE)
	halo:SetPoint("CENTER", holder, "BOTTOMLEFT", x, y)
	halo:SetAlpha(alpha * HALO_ALPHA)
end

-- Driver -------------------------------------------------------------------------------------------------------

local function Steady(now)
	return db.always or (db.combat and inCombat) or (testUntil ~= nil and now < testUntil)
end

local function OnUpdate(_, elapsed)
	sinceSample = sinceSample + elapsed
	local sample = sinceSample >= SAMPLE_INTERVAL
	if not (sample or shown or trailBusy) then
		return
	end
	local now = GetTime()
	local x, y = CursorXY()
	if sample then
		sinceSample = 0
		ReadPalette() -- a ring or trail that stays up still follows a theme switch
		ns.Cursor_AddSample(samples, now, x, y, ns.CURSOR_SHAKE_WINDOW)
		if db.shake and ns.Cursor_IsShake(samples) then
			if shake then
				shake.last = now
			else
				shake = { began = now, last = now }
			end
		end
	end
	if shake and ns.Cursor_ShakeOver(shake.last, now) then
		shake = nil
	end
	if testUntil and now >= testUntil then
		testUntil = nil
	end
	local hidden = db.hideMouselook and IsMouselooking()
	lookState.steady, lookState.shake, lookState.hidden = Steady(now), shake, hidden
	local scale, alpha = ns.Cursor_Look(lookState, now)
	DrawRing(now, x, y, scale, alpha)
	gateState.ringAlpha, gateState.combat, gateState.hidden = alpha, inCombat, hidden
	trailBusy = ns.Cursor_TrailUpdate(db, palette, now, x, y,
		ns.Cursor_TrailGate(db.trail, db.trailWhen, gateState))
end

-- Settings changed: the next frame or sample picks up modes, sizes and colors; the shape and the trail start over.
local function Refresh()
	if not module.active then
		return
	end
	ReadPalette()
	if shown then
		ApplyShape()
	end
	ns.Cursor_TrailClear()
	trailBusy = false
end

local function Test()
	if not module.active then
		ns.Print("Cursor highlight is off. Turn it on in the Tomte window first.")
		return
	end
	testUntil = GetTime() + TEST_SECONDS
end

-- Blizzard's color picker for the custom color; the ring shows while you pick (each change keeps it up a while).
local function PickColor()
	local saved = db.customColor
	local had = saved.r ~= nil
	local r, g, b
	if had then
		r, g, b = saved.r, saved.g, saved.b
	else
		r, g, b = UI.RGB("accent")
	end
	local function Set(nr, ng, nb)
		saved.r, saved.g, saved.b = nr, ng, nb
		if module.active then
			testUntil = GetTime() + TEST_SECONDS
		end
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		hasOpacity = false,
		swatchFunc = function()
			Set(ColorPickerFrame:GetColorRGB())
		end,
		cancelFunc = function()
			if had then
				Set(ColorPickerFrame:GetPreviousValues())
			else
				wipe(saved)
			end
		end,
	})
	if module.active then
		testUntil = GetTime() + TEST_SECONDS
	end
end

-- Events -------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:PLAYER_REGEN_DISABLED()
	inCombat = true
end

function events:PLAYER_REGEN_ENABLED()
	inCombat = false
end

local function Start()
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	inCombat = InCombatLockdown()
	local _, classFile = UnitClass("player")
	local color = classFile and C_ClassColor.GetClassColor(classFile)
	palette.class = color and { color:GetRGB() } or nil
	ReadPalette()
	if not driver then
		driver = CreateFrame("Frame", nil, UIParent)
	end
	sinceSample = 0
	driver:SetScript("OnUpdate", OnUpdate)
	driver:Show()
end

local function Stop()
	events:UnregisterAllEvents()
	if driver then
		driver:SetScript("OnUpdate", nil)
		driver:Hide()
	end
	if holder then
		HideRing()
	end
	ns.Cursor_TrailClear()
	wipe(samples)
	shake, testUntil, inCombat, trailBusy = nil, nil, false, false
end

-- Options ------------------------------------------------------------------------------------------------------

local function Pixels(v)
	return v .. " px"
end

local function Percent(v)
	return math.floor(v * 100 + 0.5) .. "%"
end

local function Seconds(v)
	return ("%.2f s"):format(v)
end

local function FlatTrail()
	return db.trailStyle ~= "effect"
end

module = ns.RegisterModule({
	key = "cursor",
	name = "Cursor highlight",
	category = "interface",
	icon = 135934, -- spell_holy_mindvision
	summary = "A crisp ring around the mouse cursor when you shake the mouse, and a trail behind it if you like.",
	description = "Shake the mouse and a sharp ring pops up around the cursor, then fades once the mouse is still. It can also stay on in combat or all the time, gently pulse, and come as a thick ring, a soft glow or a crosshair. The trail behind the cursor can be glow dots, rings, stars, sparkles, a ribbon or a spell effect, in the theme's color, your class color, a color you pick or a rainbow.",
	enabledByDefault = false,
	defaults = {
		shake = true,
		combat = false,
		always = false,
		hideMouselook = true,
		size = 64, -- UI units across at normal size; a shake pops it bigger for a moment
		opacity = 0.8,
		shape = "ring", -- key in ns.CURSOR_RING_SHAPES
		pulse = false,
		color = "theme", -- "theme" (accent), "class", "custom" or "rainbow"; ring and flat trail alike
		customColor = {}, -- { r, g, b } from the color picker; empty until picked (shows the accent)
		trail = false,
		trailWhen = "ring", -- "ring" (while the ring shows), "moving" (whenever the mouse moves) or "combat"
		trailStyle = "shapes", -- "shapes" (flat, ns.CURSOR_TRAIL_SHAPES) or "effect" (ns.CURSOR_EFFECTS)
		trailShape = "dots",
		trailEffect = "arcane",
		trailLife = 0.35, -- seconds a point lasts
		trailGap = 12, -- UI units the cursor moves before the next point
		trailSize = 14, -- a fresh point's size in UI units (also scales the spell effect)
		trailTaper = 0.6, -- share of the size lost toward the tail: 0.6 shrinks the oldest points to 40%
		trailOpacity = 0.55,
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
		{ "test", "show the ring around the cursor for a few seconds", Test },
	},
	options = {
		{ type = "header", label = "When to show it" },
		{ type = "checkbox", key = "shake", label = "When you shake the mouse", onChange = Refresh,
			tooltip = "Move the mouse quickly back and forth: the ring pops up big around the cursor, shrinks and fades about a second after you stop." },
		{ type = "checkbox", key = "combat", label = "Always in combat", onChange = Refresh },
		{ type = "checkbox", key = "always", label = "Always", onChange = Refresh },
		{ type = "checkbox", key = "hideMouselook", label = "Hide while turning the camera", onChange = Refresh,
			tooltip = "The cursor is hidden while you hold a mouse button to turn the camera, so the ring and trail hide too." },
		{ type = "button", label = "Preview", text = "Show", onClick = Test,
			tooltip = "Show the ring around the cursor for a few seconds." },

		{ type = "header", label = "Ring" },
		{ type = "dropdown", key = "shape", label = "Shape", onChange = Refresh,
			choices = function()
				return ns.Cursor_Choices(ns.CURSOR_RING_SHAPES)
			end,
			tooltip = "If the ring shows as a green square, restart the game once: new art only loads on a full restart, not a reload." },
		{ type = "slider", key = "size", label = "Size", min = 32, max = 160, step = 8, format = Pixels,
			onChange = Refresh },
		{ type = "slider", key = "opacity", label = "Opacity", min = 0.2, max = 1, step = 0.05, format = Percent,
			onChange = Refresh },
		{ type = "checkbox", key = "pulse", label = "Pulse", onChange = Refresh,
			tooltip = "The ring gently grows and dims while it's shown." },

		{ type = "header", label = "Color" },
		{ type = "dropdown", key = "color", label = "Color", onChange = Refresh,
			choices = function()
				return { { value = "theme", text = "Theme" }, { value = "class", text = "Class color" },
					{ value = "custom", text = "Your own" }, { value = "rainbow", text = "Rainbow" } }
			end,
			tooltip = "For the ring and the trail's shapes. Rainbow runs through the colors over time and along the trail. Spell effects keep their own colors." },
		{ type = "button", label = "Your color", text = "Pick", onClick = PickColor,
			shown = function()
				return db.color == "custom"
			end,
			tooltip = "Opens the color picker; the ring shows while you pick." },

		{ type = "header", label = "Trail" },
		{ type = "checkbox", key = "trail", label = "Trail", onChange = Refresh,
			tooltip = "Shapes or a spell effect following the cursor. It fades out as soon as the mouse is still." },
		{ type = "dropdown", key = "trailWhen", label = "Show it", parent = "trail", onChange = Refresh,
			choices = function()
				return { { value = "ring", text = "With the ring" }, { value = "moving", text = "Always" },
					{ value = "combat", text = "In combat" } }
			end,
			tooltip = "With the ring: only while the ring is shown. Always and In combat: whenever the mouse moves." },
		{ type = "dropdown", key = "trailStyle", label = "Kind", parent = "trail", onChange = Refresh,
			choices = function()
				return { { value = "shapes", text = "Shapes" }, { value = "effect", text = "Spell effect" } }
			end },
		{ type = "dropdown", key = "trailShape", label = "Shape", parent = "trail", onChange = Refresh,
			choices = function()
				return ns.Cursor_Choices(ns.CURSOR_TRAIL_SHAPES)
			end,
			shown = FlatTrail },
		{ type = "dropdown", key = "trailEffect", label = "Effect", parent = "trail", onChange = Refresh,
			choices = function()
				return ns.Cursor_Choices(ns.CURSOR_EFFECTS)
			end,
			shown = function()
				return not FlatTrail()
			end,
			tooltip = "A Blizzard spell effect sits on the cursor and leaves its sparks behind as you move." },
		{ type = "slider", key = "trailSize", label = "Size", parent = "trail", min = 6, max = 40, step = 1,
			format = Pixels, onChange = Refresh, tooltip = "The size of the newest point, or of the spell effect." },
		{ type = "slider", key = "trailOpacity", label = "Opacity", parent = "trail", min = 0.1, max = 1, step = 0.05,
			format = Percent, onChange = Refresh },
		{ type = "slider", key = "trailLife", label = "Length", parent = "trail", min = 0.15, max = 1.2, step = 0.05,
			format = Seconds, onChange = Refresh, shown = FlatTrail,
			tooltip = "How long each point stays before it's gone: a longer trail." },
		{ type = "slider", key = "trailGap", label = "Spacing", parent = "trail", min = 3, max = 30, step = 1,
			format = Pixels, onChange = Refresh, shown = FlatTrail,
			tooltip = "How far the cursor moves before the next point: lower is a denser trail. The ribbon looks smoothest low." },
		{ type = "slider", key = "trailTaper", label = "Taper", parent = "trail", min = 0, max = 1, step = 0.05,
			format = Percent, onChange = Refresh, shown = FlatTrail,
			tooltip = "How much the trail shrinks toward its tail." },
	},
})
