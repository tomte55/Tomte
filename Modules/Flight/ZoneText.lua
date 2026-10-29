local addonName, ns = ...

-- RPG-style "Entering <zone>" text during cinematic flights: a spaced label, the zone name in large
-- title font, and a thin ruled line with a small diamond. It drifts up slightly while fading in,
-- holds, then fades out. (WoW's own zone text is part of the hidden UI.) Flight.lua shows it on
-- ZONE_CHANGED_NEW_AREA while the flight owns the cinematic; Scene.lua creates it and drives its alpha.

local UI = ns.UI
local FROM_TOP = 0.24 -- of screen height, center of the text block
local FADE_IN, HOLD, FADE_OUT = 1.0, 3.0, 1.2
local DRIFT = 10 -- units it rises while fading in
local LINE_WIDTH = 380

local holder -- follows the letterbox content alpha
local block -- animated alpha + drift
local label, name
local t -- animation time, nil when hidden

local Smooth = ns.Smoothstep

local function Place(offsetY)
	block:ClearAllPoints()
	local screenH = holder:GetHeight()
	block:SetPoint("CENTER", holder, "TOP", 0, -screenH * FROM_TOP + offsetY)
end

local function OnUpdate(self, dt)
	if not t then
		return
	end
	t = t + dt
	local alpha, drift
	if t < FADE_IN then
		local p = Smooth(t / FADE_IN)
		alpha, drift = p, -DRIFT * (1 - p)
	elseif t < FADE_IN + HOLD then
		alpha, drift = 1, 0
	elseif t < FADE_IN + HOLD + FADE_OUT then
		alpha, drift = 1 - Smooth((t - FADE_IN - HOLD) / FADE_OUT), 0
	else
		ns.ZoneText_Hide()
		return
	end
	block:SetAlpha(alpha)
	Place(drift)
end

-- parent: the flight scene's frame (Scene.lua's scene.Create).
function ns.ZoneText_Create(parent)
	holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	-- Above the scene's card, which Scene.lua puts at the letterbox's level + 10.
	holder:SetFrameLevel(parent:GetFrameLevel() + 12)
	holder:Hide()

	block = CreateFrame("Frame", nil, holder)
	block:SetSize(LINE_WIDTH, 90)

	name = block:CreateFontString(nil, "OVERLAY")
	UI.SetFont(name, "title", 36)
	UI.SetTextRole(name, "heading")
	name:SetShadowOffset(2, -2)
	name:SetShadowColor(0, 0, 0, 0.9)
	name:SetPoint("CENTER", 0, 0)

	label = block:CreateFontString(nil, "OVERLAY")
	UI.SetFont(label, "title", 12)
	UI.SetTextRole(label, "text")
	label:SetShadowOffset(1, -1)
	label:SetShadowColor(0, 0, 0, 0.9)
	label:SetPoint("BOTTOM", name, "TOP", 0, 6)
	label:SetText(ns.Spaced("Entering"))

	local line = ns.SceneLine(block, LINE_WIDTH, 0.9)
	line:SetPoint("TOPLEFT", name, "BOTTOM", -LINE_WIDTH / 2, -8)
	local diamond = block:CreateTexture(nil, "OVERLAY", nil, 1)
	diamond:SetColorTexture(UI.Color("frame"))
	diamond:SetSize(6, 6)
	diamond:SetRotation(math.pi / 4)
	diamond:SetPoint("CENTER", name, "BOTTOM", 0, -8)

	holder:SetScript("OnUpdate", ns.Perf_Wrap(OnUpdate, "OnUpdate"))
end

-- Show (or restart with a new name). Called while the cinematic letterbox is up.
function ns.ZoneText_Show(zone)
	holder:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	name:SetText(zone)
	if t and t < FADE_IN + HOLD then
		-- Already visible: keep it up and restart the hold with the new name.
		t = math.min(t, FADE_IN)
	else
		t = 0
		block:SetAlpha(0)
		Place(-DRIFT)
	end
	holder:Show()
end

function ns.ZoneText_Hide()
	t = nil
	holder:Hide()
end

-- Follows the band contents' alpha, so it fades out with them when the cinematic ends.
function ns.ZoneText_SetAlpha(alpha)
	holder:SetAlpha(alpha)
end
