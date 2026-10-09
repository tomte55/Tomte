local addonName, ns = ...

-- Countdown bar while flying. Created the first time it is needed (a flight, or unlocking it to move it).

local WIDTH, HEIGHT = 240, 18
local COLOR_COUNTDOWN = { 0.2, 0.75, 0.25 }
local COLOR_RECORDING = { 0.75, 0.2, 0.1 }
local SWEEP_PERIOD = 2 -- seconds for the recording spark to cross the bar
local PREVIEW_SECONDS = 90
local PREVIEW_STOPS = { 0.35, 0.7 }
local TICK_AHEAD_ALPHA, TICK_PASSED_ALPHA = 0.9, 0.25

local bar
local active -- { destName, expected, isEstimate, start, stops, preview }

local function SavePosition()
	local point, _, relPoint, x, y = bar:GetPoint()
	local pos = ns.flightDB.frame
	pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
end

local function SetEta(text)
	if text ~= bar.etaText then
		bar.etaText = text
		bar.eta:SetText(text and ("lands " .. text) or "")
	end
end

local function LayoutTicks(stops)
	for _, tick in ipairs(bar.ticks) do
		tick:Hide()
	end
	if not stops then
		return
	end
	for i, fraction in ipairs(stops) do
		local tick = bar.ticks[i]
		if not tick then
			tick = bar:CreateTexture(nil, "OVERLAY")
			tick:SetColorTexture(1, 1, 1)
			tick:SetSize(2, HEIGHT)
			bar.ticks[i] = tick
		end
		-- The countdown fill shrinks right to left, so elapsed fraction f sits at (1 - f) of the width.
		tick:ClearAllPoints()
		tick:SetPoint("CENTER", bar, "LEFT", (1 - fraction) * WIDTH, 0)
		tick:SetAlpha(TICK_AHEAD_ALPHA)
		tick:Show()
	end
end

-- recording: no estimate at all (red sweep). learning: this exact route has no recorded time yet (REC dot),
-- which includes estimated countdowns.
local function SetMode(recording, learning)
	local c = recording and COLOR_RECORDING or COLOR_COUNTDOWN
	bar:SetStatusBarColor(c[1], c[2], c[3])
	bar.dot:SetShown(learning)
	bar.rec:SetShown(learning)
	bar.spark:SetShown(recording)
	bar.eta:SetShown(not recording)
	bar.name:ClearAllPoints()
	if learning then
		bar.pulse:Play()
		bar.name:SetPoint("LEFT", bar.rec, "RIGHT", 6, 0)
	else
		bar.pulse:Stop()
		bar.name:SetPoint("LEFT", bar, "LEFT", 6, 0)
	end
	bar.name:SetPoint("RIGHT", bar.time, "LEFT", -6, 0)
end

local function OnUpdate(self)
	if not active then
		return
	end
	local elapsed = GetTime() - active.start
	local text, fill, remaining = ns.TimerText(active.expected, active.isEstimate, elapsed)
	self.time:SetText(text)
	if active.expected then
		self:SetValue(fill)
		SetEta(remaining >= 0 and date("%H:%M", time() + math.floor(remaining + 0.5)) or nil)
		if active.stops then
			local progress = elapsed / active.expected
			for i, fraction in ipairs(active.stops) do
				self.ticks[i]:SetAlpha(progress >= fraction and TICK_PASSED_ALPHA or TICK_AHEAD_ALPHA)
			end
		end
	else
		self:SetValue(1)
		local frac = (elapsed % SWEEP_PERIOD) / SWEEP_PERIOD
		self.spark:SetPoint("CENTER", self, "LEFT", frac * self:GetWidth(), 0)
	end
end

local function ShowPreview()
	local text = ns.EditMode_Active() and "Flight Timer" or "Drag me, then /tomte flight lock"
	ns.Bar_Start(text, PREVIEW_SECONDS, false, GetTime(), PREVIEW_STOPS)
	active.preview = true
end

local function CreateFade(from, to, duration)
	local group = bar:CreateAnimationGroup()
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(from)
	alpha:SetToAlpha(to)
	alpha:SetDuration(duration)
	group:SetToFinalAlpha(true)
	return group
end

local function CreateBar()
	bar = CreateFrame("StatusBar", nil, UIParent)
	ns.ownFrames[bar] = true
	bar:SetSize(WIDTH, HEIGHT)
	bar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
	bar:SetMinMaxValues(0, 1)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	bar:SetScript("OnUpdate", OnUpdate)
	bar.ticks = {}

	local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -4, 4)
	border:SetPoint("BOTTOMRIGHT", 4, -4)
	border:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
	border:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	border:SetBackdropColor(0, 0, 0, 0.7)
	border:SetBackdropBorderColor(0.6, 0.6, 0.6)

	bar.spark = bar:CreateTexture(nil, "OVERLAY", nil, -1)
	bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	bar.spark:SetBlendMode("ADD")
	bar.spark:SetSize(24, HEIGHT * 2)

	bar.dot = bar:CreateTexture(nil, "OVERLAY")
	bar.dot:SetSize(10, 10)
	bar.dot:SetPoint("LEFT", bar, "LEFT", 5, 0)
	bar.dot:SetColorTexture(1, 0.15, 0.15)
	local mask = bar:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(bar.dot)
	bar.dot:AddMaskTexture(mask)

	bar.pulse = bar.dot:CreateAnimationGroup()
	bar.pulse:SetLooping("BOUNCE")
	local fade = bar.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.15)
	fade:SetDuration(0.6)

	bar.rec = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.rec:SetPoint("LEFT", bar.dot, "RIGHT", 3, 0)
	bar.rec:SetText("REC")
	bar.rec:SetTextColor(1, 0.35, 0.35)

	bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bar.time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

	bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.name:SetJustifyH("LEFT")
	bar.name:SetWordWrap(false)

	bar.eta = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.eta:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
	bar.eta:SetTextColor(0.8, 0.8, 0.8)

	bar.fadeIn = CreateFade(0, 1, 0.3)
	bar.fadeOut = CreateFade(1, 0, 0.4)
	bar.fadeOut:SetScript("OnFinished", function()
		bar:Hide()
		bar:SetAlpha(1)
	end)

	local pos = ns.flightDB.frame
	bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	bar:EnableMouse(not pos.locked)
	bar:Hide()
end

function ns.Bar_Start(destName, expected, isEstimate, startTime, stops)
	if not bar then
		CreateBar()
	end
	if expected and expected <= 0 then
		expected = nil
	end
	active = { destName = destName, expected = expected, isEstimate = isEstimate, start = startTime }
	active.stops = expected and stops or nil
	bar.name:SetText(destName)
	SetMode(expected == nil, expected == nil or isEstimate)
	LayoutTicks(active.stops)
	OnUpdate(bar)

	local visible = bar:IsShown() and not bar.fadeOut:IsPlaying()
	bar.fadeOut:Stop()
	if not visible then
		bar:SetAlpha(0)
		bar:Show()
		bar.fadeIn:Play()
	end
end

function ns.Bar_Stop()
	if not bar then
		return
	end
	active = nil
	bar.pulse:Stop()
	if ns.flightDB.frame.locked and not ns.EditMode_Active() then
		bar.fadeIn:Stop()
		bar.fadeOut:Play()
	else
		ShowPreview()
	end
end

-- Module turned off: gone at once, no unlocked-bar preview.
function ns.Bar_Hide()
	if not bar then
		return
	end
	active = nil
	bar.pulse:Stop()
	bar.fadeIn:Stop()
	bar.fadeOut:Stop()
	bar:Hide()
	bar:SetAlpha(1)
end

function ns.Bar_SetLocked(locked)
	ns.flightDB.frame.locked = locked
	if not bar then
		if locked then
			return
		end
		CreateBar()
	end
	bar:EnableMouse(not locked)
	if locked then
		if active and active.preview then
			ns.Bar_Stop()
		end
	elseif not active then
		ShowPreview()
	end
end

-- Edit Mode opened (on) or closed: the preview while it's open, unless a real flight is showing.
function ns.Bar_EditMode(on)
	if on then
		if not bar then
			CreateBar()
		end
		if not active or active.preview then
			ShowPreview()
		end
	elseif bar and active and active.preview then
		ns.Bar_Stop() -- fades out when locked, else back to the unlocked preview
	end
end

function ns.Bar_Frame()
	return bar
end

function ns.Bar_SavePosition()
	SavePosition()
end
