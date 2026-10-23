local addonName, ns = ...

-- Cursor highlight: a ring in the theme's accent color around the mouse cursor, shown when you shake the mouse
-- (to find the cursor), and optionally always in combat or always, with an optional short trail of fading dots.
-- Pure rules (shake detection, the ring's size and fade, the trail) in Data.lua.

-- Polling. The cursor has no "moved" event, so a small driver frame samples GetCursorPosition. It's an OnUpdate
-- rather than a C_Timer ticker because the driver is a child of UIParent: whenever UIParent is hidden (cinematics,
-- movies, Alt+Z) the game stops calling it, so there's no work at all then, and the same script draws the ring at
-- frame rate while it's shown. While the ring is hidden the script returns right away except SAMPLE_RATE times a
-- second, when it reads the cursor once for shake detection. The driver only exists while the module is on.
local SAMPLE_RATE = 30 -- shake samples per second, shown or not (Data.lua's thresholds assume this spacing)
local SAMPLE_INTERVAL = 1 / SAMPLE_RATE
local TEST_SECONDS = 4
local HALO_SCALE = 1.6 -- the soft glow behind the ring, times the ring's size
local HALO_ALPHA = 0.35 -- the glow's opacity relative to the ring
local TRAIL_DOTS = 8
local TRAIL_GAP = 12 -- UI units the cursor moves before the next dot
local TRAIL_LIFE = 0.35 -- seconds a dot lasts
local TRAIL_SIZE = 14 -- a fresh dot's size in UI units; it shrinks to 40% as it fades
local TRAIL_ALPHA = 0.7 -- a fresh dot's opacity relative to the ring
-- The minimap's player ping ring (interface/minimap/ui-minimap-ping-expand.blp), desaturated and tinted.
local RING_TEXTURE = 237609
local UI = ns.UI

local module, db
local driver, holder, ring, halo
local dots = {}
local samples, trail = {}, {}
local shake -- { began, last } while a shake look is playing
local shown, inCombat, testUntil = false, false, nil
local sinceSample = 0

local function CursorXY()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

-- Drawing ------------------------------------------------------------------------------------------------------

local function CreateHolder()
	-- Covers the screen so the ring and dots can be placed by cursor position; never takes the mouse, so clicks
	-- go through to whatever is underneath.
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("TOOLTIP")
	holder:EnableMouse(false)
	holder:Hide()

	halo = holder:CreateTexture(nil, "ARTWORK")
	halo:SetTexture(ns.Theme.MEDIA .. "Theme\\Glow")
	halo:SetBlendMode("ADD")

	ring = holder:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(RING_TEXTURE)
	ring:SetDesaturated(true) -- grey first, so the theme tint shows as itself and not mixed with the ring's own color
	ring:SetBlendMode("ADD")

	for i = 1, TRAIL_DOTS do
		local dot = holder:CreateTexture(nil, "ARTWORK", nil, 1)
		dot:SetTexture(ns.Theme.MEDIA .. "Theme\\Glow")
		dot:SetBlendMode("ADD")
		dot:Hide()
		dots[i] = dot
	end
end

-- Read from the theme when the ring appears and on each sample while it's shown, so a theme switch reaches it.
local function ApplyColors()
	local r, g, b = UI.RGB("accent")
	ring:SetVertexColor(r, g, b)
	halo:SetVertexColor(r, g, b)
	for _, dot in ipairs(dots) do
		dot:SetVertexColor(r, g, b)
	end
end

local function HideRing()
	if shown then
		holder:Hide()
		shown = false
	end
	wipe(trail)
	for _, dot in ipairs(dots) do
		dot:Hide()
	end
end

local function DrawTrail(now, x, y, alpha)
	if not db.trail then
		return
	end
	ns.Cursor_TrailAdd(trail, now, x, y, TRAIL_GAP, TRAIL_DOTS)
	local fade = ns.Cursor_TrailFade(trail, now, TRAIL_LIFE)
	for i, dot in ipairs(dots) do
		local f, p = fade[i], trail[i]
		if f and f > 0 then
			local size = TRAIL_SIZE * (0.4 + 0.6 * f)
			dot:SetSize(size, size)
			dot:SetPoint("CENTER", holder, "BOTTOMLEFT", p.x, p.y)
			dot:SetAlpha(f * alpha * TRAIL_ALPHA)
			dot:Show()
		else
			dot:Hide()
		end
	end
end

local function Draw(now, x, y, scale, alpha)
	if alpha <= 0 then
		if shown then
			HideRing()
		end
		return
	end
	if not holder then
		CreateHolder()
	end
	if not shown then
		ApplyColors()
		holder:Show()
		shown = true
	end
	alpha = alpha * db.opacity
	local size = db.size * scale
	ring:SetSize(size, size)
	ring:SetPoint("CENTER", holder, "BOTTOMLEFT", x, y)
	ring:SetAlpha(alpha)
	halo:SetSize(size * HALO_SCALE, size * HALO_SCALE)
	halo:SetPoint("CENTER", holder, "BOTTOMLEFT", x, y)
	halo:SetAlpha(alpha * HALO_ALPHA)
	DrawTrail(now, x, y, alpha)
end

-- Driver -------------------------------------------------------------------------------------------------------

local function Steady(now)
	return db.always or (db.combat and inCombat) or (testUntil ~= nil and now < testUntil)
end

local function OnUpdate(_, elapsed)
	sinceSample = sinceSample + elapsed
	local sample = sinceSample >= SAMPLE_INTERVAL
	if not (sample or shown) then
		return
	end
	local now = GetTime()
	local x, y = CursorXY()
	if sample then
		sinceSample = 0
		if shown then
			ApplyColors() -- a ring that stays up (Always, in combat) still follows a theme switch
		end
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
	local scale, alpha = ns.Cursor_Look({
		steady = Steady(now),
		shake = shake,
		hidden = db.hideMouselook and IsMouselooking(),
	}, now)
	Draw(now, x, y, scale, alpha)
end

-- Settings changed: the next frame or sample picks up modes; size and color need the ring redrawn.
local function Refresh()
	if not module.active then
		return
	end
	if shown then
		ApplyColors()
	end
	if not db.trail then
		wipe(trail)
		for _, dot in ipairs(dots) do
			dot:Hide()
		end
	end
end

local function Test()
	if not module.active then
		ns.Print("Cursor highlight is off. Turn it on in the Tomte window first.")
		return
	end
	testUntil = GetTime() + TEST_SECONDS
	if shown then
		ApplyColors()
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
	wipe(samples)
	shake, testUntil, inCombat = nil, nil, false
end

local function Pixels(v)
	return v .. " px"
end

local function Percent(v)
	return math.floor(v * 100 + 0.5) .. "%"
end

module = ns.RegisterModule({
	key = "cursor",
	name = "Cursor highlight",
	category = "interface",
	icon = 135934, -- spell_holy_mindvision
	summary = "A ring around the mouse cursor when you shake the mouse, so you find it at once.",
	description = "Shake the mouse and a ring in the theme's color pops up around the cursor, then fades once the mouse is still. It can also stay on in combat or all the time, with a short trail behind the cursor.",
	enabledByDefault = false,
	defaults = {
		shake = true,
		combat = false,
		always = false,
		hideMouselook = true,
		size = 64, -- UI units across at normal size; a shake pops it bigger for a moment
		opacity = 0.8,
		trail = false,
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
			tooltip = "The cursor is hidden while you hold a mouse button to turn the camera, so the ring hides too." },
		{ type = "button", label = "Preview", text = "Show", onClick = Test,
			tooltip = "Show the ring around the cursor for a few seconds." },

		{ type = "header", label = "Look" },
		{ type = "slider", key = "size", label = "Size", min = 32, max = 160, step = 8, format = Pixels,
			onChange = Refresh },
		{ type = "slider", key = "opacity", label = "Opacity", min = 0.2, max = 1, step = 0.05, format = Percent,
			onChange = Refresh },
		{ type = "checkbox", key = "trail", label = "Trail", onChange = Refresh,
			tooltip = "A few fading dots behind the cursor while the ring is shown." },
	},
})
