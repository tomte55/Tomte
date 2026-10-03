local addonName, ns = ...

-- RPG-style "Entering <zone>" text during cinematic flights: a spaced label, the zone name in large
-- gold Morpheus, and a thin gold line with a small diamond. It drifts up slightly while fading in,
-- holds, then fades out. (WoW's own zone text is part of the hidden UI.)

local GOLD = { 1, 0.82, 0.45 }
local FROM_TOP = 0.24 -- of screen height, center of the text block
local FADE_IN, HOLD, FADE_OUT = 1.0, 3.0, 1.2
local DRIFT = 10 -- units it rises while fading in
local LINE_WIDTH = 380

local holder -- follows the letterbox content alpha
local block -- animated alpha + drift
local label, name
local t -- animation time, nil when hidden

local function Smooth(p)
	return p * p * (3 - 2 * p)
end

local function GoldLine(parent, width)
	local half = width / 2
	local left = parent:CreateTexture(nil, "OVERLAY")
	left:SetColorTexture(1, 1, 1, 1)
	left:SetSize(half, 1)
	left:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.9))
	local right = parent:CreateTexture(nil, "OVERLAY")
	right:SetColorTexture(1, 1, 1, 1)
	right:SetSize(half, 1)
	right:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.9), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))
	right:SetPoint("LEFT", left, "RIGHT")
	return left
end

local function Spaced(text)
	return (text:upper():gsub(".", "%0 "):sub(1, -2))
end

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

function ns.ZoneText_Create(letterbox)
	holder = CreateFrame("Frame", nil, letterbox)
	holder:SetAllPoints(letterbox)
	holder:SetFrameLevel(letterbox:GetFrameLevel() + 12)
	holder:Hide()

	block = CreateFrame("Frame", nil, holder)
	block:SetSize(LINE_WIDTH, 90)

	name = block:CreateFontString(nil, "OVERLAY")
	name:SetFont("Fonts\\MORPHEUS.TTF", 42, "")
	name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	name:SetShadowOffset(2, -2)
	name:SetShadowColor(0, 0, 0, 0.9)
	name:SetPoint("CENTER", 0, 0)

	label = block:CreateFontString(nil, "OVERLAY")
	label:SetFont(STANDARD_TEXT_FONT, 12, "")
	label:SetTextColor(0.85, 0.85, 0.85)
	label:SetShadowOffset(1, -1)
	label:SetShadowColor(0, 0, 0, 0.9)
	label:SetPoint("BOTTOM", name, "TOP", 0, 6)
	label:SetText(Spaced("Entering"))

	local line = GoldLine(block, LINE_WIDTH)
	line:SetPoint("TOPLEFT", name, "BOTTOM", -LINE_WIDTH / 2, -8)
	local diamond = block:CreateTexture(nil, "OVERLAY", nil, 1)
	diamond:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	diamond:SetSize(6, 6)
	diamond:SetRotation(math.pi / 4)
	diamond:SetPoint("CENTER", name, "BOTTOM", 0, -8)

	holder:SetScript("OnUpdate", OnUpdate)
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
