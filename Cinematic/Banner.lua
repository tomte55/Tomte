local addonName, ns = ...

-- Title-card banner over the normal UI (Moments, pet check): an optional icon, a spaced label, the title in
-- the theme's title font, a line with a small diamond and a subtitle. Drifts up while fading in, holds,
-- fades out. Click-through. Banners queue and wait while a cinematic hides the UI, and while Blizzard's own
-- center-screen text (zone text, event toasts, raid warnings, boss emotes) is up, so they never overlap it.
-- A moment that tells the same thing as Blizzard's zone text can hide that text instead.

local FROM_TOP = 0.2 -- of screen height, center of the block
local FADE_IN, FADE_OUT = 0.8, 1.0
local HOLD = 4.5
local GAP = 0.4 -- between queued banners
local DRIFT = 10
local LINE_WIDTH = 360
local ICON = 40
local MAX_QUEUE = 6
local MAX_CLEAR_WAIT = 8 -- seconds a banner waits for Blizzard's text to clear before it shows anyway
-- Blizzard frames in the banner's part of the screen. Each is shown only while it has something to show.
local BLIZZARD_FRAMES = { "ZoneTextFrame", "SubZoneTextFrame", "EventToastManagerFrame", "RaidWarningFrame", "RaidBossEmoteFrame" }
local ZONE_TEXT_FRAMES = { "ZoneTextFrame", "SubZoneTextFrame" }

local frame, block
local queue = {}
local current, t, wait = nil, nil, 0
local clearWait = 0 -- how long the next banner has waited for Blizzard's text
local suppressUntil = 0 -- Blizzard's zone text stays hidden until then

local function Smooth(p)
	return p * p * (3 - 2 * p)
end

local function ScreenBusy()
	for _, name in ipairs(BLIZZARD_FRAMES) do
		local f = _G[name]
		if f and f:IsVisible() and f:GetAlpha() > 0.05 then
			return true
		end
	end
	return false
end

local function Place(offsetY)
	block:ClearAllPoints()
	block:SetPoint("CENTER", frame, "TOP", 0, -frame:GetHeight() * FROM_TOP + offsetY)
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(false)
	frame:Hide()

	block = CreateFrame("Frame", nil, frame)
	block:SetSize(LINE_WIDTH, 100)

	block.title = block:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(block.title, "title", 28)
	block.title:SetTextColor(ns.Theme.Color("heading"))
	block.title:SetShadowOffset(2, -2)
	block.title:SetShadowColor(0, 0, 0, 0.9)
	block.title:SetPoint("CENTER")

	block.label = block:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(block.label, "body", 12)
	block.label:SetShadowOffset(1, -1)
	block.label:SetShadowColor(0, 0, 0, 0.9)
	block.label:SetPoint("BOTTOM", block.title, "TOP", 0, 6)

	block.icon = block:CreateTexture(nil, "OVERLAY")
	block.icon:SetSize(ICON, ICON)
	block.icon:SetPoint("BOTTOM", block.label, "TOP", 0, 8)
	block.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	block.iconBorder = block:CreateTexture(nil, "ARTWORK")
	local r, g, b = ns.Theme.Color("frame")
	block.iconBorder:SetColorTexture(r, g, b, 0.8)
	block.iconBorder:SetPoint("TOPLEFT", block.icon, -1, 1)
	block.iconBorder:SetPoint("BOTTOMRIGHT", block.icon, 1, -1)

	block.line = ns.SceneLine(block, LINE_WIDTH, 0.9)
	block.line:SetPoint("TOPLEFT", block.title, "BOTTOM", -LINE_WIDTH / 2, -8)
	block.diamond = block:CreateTexture(nil, "OVERLAY", nil, 1)
	block.diamond:SetColorTexture(ns.Theme.Color("frame"))
	block.diamond:SetSize(6, 6)
	block.diamond:SetRotation(math.pi / 4)
	block.diamond:SetPoint("CENTER", block.title, "BOTTOM", 0, -8)

	block.subtitle = block:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(block.subtitle, "body", 14)
	block.subtitle:SetTextColor(ns.Theme.Color("text"))
	block.subtitle:SetShadowOffset(1, -1)
	block.subtitle:SetShadowColor(0, 0, 0, 0.9)
	block.subtitle:SetPoint("TOP", block.title, "BOTTOM", 0, -18)
	block.subtitle:SetWidth(LINE_WIDTH + 140)
end

local function Start(spec)
	current, t = spec, 0
	-- accent: a color role, or an { r, g, b } that carries game meaning (quality glow); body text by default.
	block.label:SetTextColor(ns.UI.RGBA(spec.accent or "text", 1))
	block.label:SetText(ns.Spaced(spec.label or ""))
	block.title:SetText(spec.title or "")
	block.subtitle:SetText(spec.subtitle or "")
	block.icon:SetShown(spec.icon ~= nil)
	block.iconBorder:SetShown(spec.icon ~= nil)
	if spec.icon then
		block.icon:SetTexture(spec.icon)
	end
	block:SetAlpha(0)
	Place(-DRIFT)
end

local function OnUpdate(self, dt)
	if not current then
		wait = wait - dt
		if wait > 0 then
			return
		end
		if #queue == 0 then
			self:Hide()
			return
		end
		if ns.Cinematic.IsActive() or not UIParent:IsShown() then
			return -- the UI is hidden: keep them for afterwards
		end
		if ScreenBusy() and clearWait < MAX_CLEAR_WAIT then
			clearWait = clearWait + dt
			return
		end
		clearWait = 0
		Start(table.remove(queue, 1))
	end
	t = t + dt
	local hold = current.hold or HOLD
	if t < FADE_IN then
		local p = Smooth(t / FADE_IN)
		block:SetAlpha(p)
		Place(-DRIFT * (1 - p))
	elseif t < FADE_IN + hold then
		block:SetAlpha(1)
		Place(0)
	elseif t < FADE_IN + hold + FADE_OUT then
		block:SetAlpha(1 - Smooth((t - FADE_IN - hold) / FADE_OUT))
	else
		block:SetAlpha(0)
		current, t, wait = nil, nil, GAP
	end
end

function ns.Banner_Show(spec)
	if ns.Recent_Note then
		ns.Recent_Note(spec, true)
	end
	if not frame then
		Build()
		frame:SetScript("OnUpdate", OnUpdate)
	end
	if #queue >= MAX_QUEUE then
		table.remove(queue, 1)
	end
	queue[#queue + 1] = spec
	frame:Show()
end

-- Drop everything queued with this owner (a module turned off), and the one showing.
function ns.Banner_Clear(owner)
	for i = #queue, 1, -1 do
		if queue[i].owner == owner then
			table.remove(queue, i)
		end
	end
	if current and current.owner == owner then
		block:SetAlpha(0)
		current, t, wait = nil, nil, GAP
	end
end

local function HideIfSuppressed(self)
	if GetTime() < suppressUntil then
		self:Hide()
	end
end

-- Hide Blizzard's zone and subzone text for the next `seconds` (a moment shows the same thing). What's
-- on screen right now goes too: it appeared together with the event that made the moment.
local zoneTextHooked
function ns.Banner_SuppressZoneText(seconds)
	suppressUntil = math.max(suppressUntil, GetTime() + seconds)
	for _, name in ipairs(ZONE_TEXT_FRAMES) do
		local f = _G[name]
		if f then
			if not zoneTextHooked then
				f:HookScript("OnShow", HideIfSuppressed)
			end
			f:Hide()
		end
	end
	zoneTextHooked = true
end
