local addonName, ns = ...

-- Generic unit health bar for combat modules (Pet Health is the first user). Health is secret in combat
-- (Midnight), so nothing here reads it: the bar value goes straight into SetValue, and color, warning glow
-- and percent text come from curves the game evaluates (UnitHealthPercent with a curve). Out of the box:
-- name, bar, percent, a threshold tick, a pulsing red glow below the threshold, a dead/missing state, and an
-- row of spell icons under the bar (cooldown swipe and seconds, plus "<buff> 6s" while one spell's buff
-- is on the unit).

local WIDTH, HEIGHT = 220, 16
local ICON = 30
local ICON_GAP = 4
local UI = ns.UI
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function IsSecretTable(t)
	return issecrettable ~= nil and issecrettable(t)
end

-- 0..1 -> 0..100 for the percent text. Blizzard ships one; build our own if it's ever missing.
local scaleTo100
local function ScaleTo100()
	if not scaleTo100 then
		scaleTo100 = CurveConstants and CurveConstants.ScaleTo100
		if not scaleTo100 then
			scaleTo100 = C_CurveUtil.CreateCurve()
			scaleTo100:SetType(Enum.LuaCurveType.Linear)
			scaleTo100:AddPoint(0, 0)
			scaleTo100:AddPoint(1, 100)
		end
	end
	return scaleTo100
end

local function Edge(parent, layer, inset, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(r, g, b, a)
	t:SetPoint("TOPLEFT", -inset, inset)
	t:SetPoint("BOTTOMRIGHT", inset, -inset)
	return t
end

local UnitBar = {}

function UnitBar:SetThreshold(threshold)
	self.threshold = threshold
	self.colorCurve:ClearPoints()
	for _, p in ipairs(ns.PetBar_ColorPoints(threshold)) do
		self.colorCurve:AddPoint(p[1], CreateColor(p[2], p[3], p[4], 1))
	end
	self.alphaCurve:ClearPoints()
	for _, p in ipairs(ns.PetBar_AlphaPoints(threshold)) do
		self.alphaCurve:AddPoint(p[1], p[2])
	end
	self.tick:ClearAllPoints()
	self.tick:SetPoint("CENTER", self.bar, "LEFT", threshold * WIDTH, 0)
end

function UnitBar:SetShowPercent(show)
	self.showPercent = show
	self.percent:SetShown(show and not self.state)
end

-- state: nil (live health), "dead" or "missing". text replaces the percent ("DEAD", "NO PET").
local function SetState(self, state, text)
	self.state = state
	local dim = state ~= nil
	if dim then
		self.bar:SetMinMaxValues(0, 1)
		self.bar:SetValue(1)
		self.bar:SetStatusBarColor(UI.Color("textFaint"))
		self.glow:SetAlpha(0)
	end
	self.skull:SetShown(state == "dead")
	self.stateText:SetShown(dim)
	self.stateText:SetText(text or "")
	self.tick:SetShown(not dim)
	self.percent:SetShown(self.showPercent and not dim)
end

function UnitBar:ShowDead(name, text)
	self.name:SetText(name or "")
	SetState(self, "dead", text)
end

function UnitBar:ShowMissing(text)
	self.name:SetText("")
	SetState(self, "missing", text)
	self:ClearBuff()
end

-- Live health. Every value from the game may be secret: pass them on, never compare them.
function UnitBar:ShowUnit(unit)
	if self.state then
		SetState(self, nil)
	end
	self.name:SetText(UnitName(unit) or "")
	self.bar:SetMinMaxValues(0, UnitHealthMax(unit))
	self.bar:SetValue(UnitHealth(unit), SMOOTH)
	local color = UnitHealthPercent(unit, true, self.colorCurve)
	self.bar:SetStatusBarColor(color:GetRGB())
	self.glow:SetAlpha(UnitHealthPercent(unit, true, self.alphaCurve))
	self.percent:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, ScaleTo100()))
end

-- Fake health (0..1) for the unlocked preview: plain numbers, so the curves are evaluated here.
function UnitBar:ShowFake(name, fraction)
	if self.state then
		SetState(self, nil)
	end
	self.name:SetText(name)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(fraction)
	self.bar:SetStatusBarColor(self.colorCurve:Evaluate(fraction):GetRGB())
	self.glow:SetAlpha(self.alphaCurve:Evaluate(fraction))
	self.percent:SetFormattedText("%.0f%%", fraction * 100)
end

local function CreateIcon(self)
	local icon = CreateFrame("Frame", nil, self)
	icon:SetSize(ICON, ICON)
	icon.border = icon:CreateTexture(nil, "BACKGROUND")
	icon.border:SetPoint("TOPLEFT", -1, 1)
	icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
	icon.border:SetColorTexture(0, 0, 0, 1)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints()
	icon.cooldown:SetDrawEdge(false)
	icon.cooldown:SetSwipeColor(0, 0, 0, 0.8)
	icon.cooldown:SetHideCountdownNumbers(false)
	UI.SetFont(icon.cooldown:GetCountdownFontString(), "number", 15, "OUTLINE")
	return icon
end

-- The spells under the bar, left to right: { { id = spellID, buff = true }, ... } (empty hides the row).
-- Each shows its cooldown (swipe and seconds); the one with buff = true also gets its buff on the unit timed.
function UnitBar:SetSpells(spells)
	local ids = {}
	for i, spell in ipairs(spells) do
		ids[i] = spell.id
	end
	local key = table.concat(ids, ",")
	if key == self.spellKey then
		return
	end
	self.spellKey = key
	self.buffIcon, self.buffName = nil, nil
	local previous
	for i, spell in ipairs(spells) do
		local icon = self.icons[i] or CreateIcon(self)
		self.icons[i] = icon
		icon.spellID = spell.id
		icon.texture:SetTexture(C_Spell.GetSpellTexture(spell.id))
		icon:ClearAllPoints()
		if previous then
			icon:SetPoint("LEFT", previous, "RIGHT", ICON_GAP, 0)
		else
			icon:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 1, -ICON_GAP - 1)
		end
		icon:Show()
		if spell.buff and not self.buffIcon then
			self.buffIcon, self.buffName = icon, C_Spell.GetSpellName(spell.id)
		end
		previous = icon
	end
	for i = #spells + 1, #self.icons do
		self.icons[i]:Hide()
	end
	self.buffText:ClearAllPoints()
	if previous then
		self.buffText:SetPoint("LEFT", previous, "RIGHT", 8, 0)
	end
	self:ClearBuff()
	self:RefreshCooldown()
end

function UnitBar:RefreshCooldown()
	for _, icon in ipairs(self.icons) do
		if icon:IsShown() then
			local duration = C_Spell.GetSpellCooldownDuration(icon.spellID, true)
			if duration then
				icon.cooldown:SetCooldownFromDurationObject(duration)
			else
				icon.cooldown:Clear()
			end
		end
	end
end

function UnitBar:ClearBuff()
	self.buffUntil = nil
	self.buffText:SetText("")
	if self.buffIcon then
		self.buffIcon.border:SetColorTexture(0, 0, 0, 1)
	end
	self.buffTicker:Hide()
end

-- The buff spell's aura on the unit: accent icon border and "<name> 6s". If the aura comes back secret, just
-- the name.
function UnitBar:RefreshBuff(unit)
	if not self.buffName or self.state then
		self:ClearBuff()
		return
	end
	local aura = C_UnitAuras.GetAuraDataBySpellName(unit, self.buffName, "HELPFUL")
	if not aura then
		self:ClearBuff()
		return
	end
	self.buffIcon.border:SetColorTexture(UI.Color("accent"))
	if IsSecretTable(aura) or IsSecret(aura.expirationTime) then
		self.buffUntil = nil
		self.buffText:SetText(self.buffName)
		self.buffTicker:Hide()
		return
	end
	self.buffUntil = aura.expirationTime
	self.buffTicker:Show()
	self.buffTicker.elapsed = 1 -- update now
end

local function BuffTick(ticker, dt)
	ticker.elapsed = ticker.elapsed + dt
	if ticker.elapsed < 0.1 then
		return
	end
	ticker.elapsed = 0
	local self = ticker.owner
	local left = self.buffUntil and (self.buffUntil - GetTime()) or 0
	if left <= 0 then
		self:ClearBuff()
		return
	end
	self.buffText:SetFormattedText("%s %ds", self.buffName, math.ceil(left))
end

function UnitBar:SetLocked(locked)
	self:EnableMouse(not locked)
	self.moveHint:SetShown(not locked)
end

-- onMoved(point, relPoint, x, y) after a drag.
function ns.UnitBar_Create(onMoved)
	local f = CreateFrame("Frame", nil, UIParent)
	Mixin(f, UnitBar)
	f:SetSize(WIDTH, HEIGHT + ICON + 24)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		onMoved(point, relPoint, x, y)
	end)
	f:EnableMouse(false)

	-- Warning glow behind the bar: alpha from the curve on this frame, a looping pulse on the inner one.
	f.glow = CreateFrame("Frame", nil, f)
	f.glow:SetPoint("BOTTOMLEFT", 0, ICON + ICON_GAP + 2)
	f.glow:SetSize(WIDTH, HEIGHT)
	f.glow:SetAlpha(0)
	local pulse = CreateFrame("Frame", nil, f.glow)
	pulse:SetAllPoints()
	local gr, gg, gb = UI.Color("danger")
	Edge(pulse, "BACKGROUND", 9, gr, gg, gb, 0.18)
	Edge(pulse, "BACKGROUND", 5, gr, gg, gb, 0.35)
	Edge(pulse, "BORDER", 3, gr, gg, gb, 1)
	local anim = pulse:CreateAnimationGroup()
	anim:SetLooping("BOUNCE")
	local fade = anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.45)
	anim:Play()

	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetAllPoints(f.glow)
	bar:SetFrameLevel(f.glow:GetFrameLevel() + 2)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	Edge(bar, "BACKGROUND", 1, 0, 0, 0, 1)
	local bg = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetAllPoints()
	bg:SetColorTexture(UI.RGBA("bgBottom", 0.85))
	f.bar = bar

	f.tick = bar:CreateTexture(nil, "OVERLAY")
	f.tick:SetColorTexture(UI.RGBA("accent", 0.95))
	f.tick:SetSize(2, HEIGHT + 4)

	f.percent = bar:CreateFontString(nil, "OVERLAY")
	UI.SetFont(f.percent, "number", 11, "OUTLINE")
	f.percent:SetPoint("RIGHT", -5, 0)

	f.stateText = bar:CreateFontString(nil, "OVERLAY")
	UI.SetFont(f.stateText, "body", 11, "OUTLINE")
	UI.SetTextRole(f.stateText, "danger")
	f.stateText:SetPoint("CENTER")

	f.skull = bar:CreateTexture(nil, "OVERLAY")
	f.skull:SetTexture(SKULL)
	f.skull:SetSize(16, 16)
	f.skull:SetPoint("RIGHT", f.stateText, "LEFT", -3, 0)
	f.skull:Hide()

	f.name = f:CreateFontString(nil, "OVERLAY")
	UI.SetFont(f.name, "body", 12)
	f.name:SetShadowOffset(1, -1)
	UI.SetTextRole(f.name, "text")
	f.name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 1, 4)

	f.moveHint = f:CreateFontString(nil, "OVERLAY")
	UI.SetFont(f.moveHint, "body", 10)
	UI.SetTextRole(f.moveHint, "accent")
	f.moveHint:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)
	f.moveHint:SetText("drag to move")
	f.moveHint:Hide()

	f.icons = {}

	f.buffText = f:CreateFontString(nil, "OVERLAY")
	UI.SetFont(f.buffText, "body", 12)
	f.buffText:SetShadowOffset(1, -1)
	UI.SetTextRole(f.buffText, "success")

	f.buffTicker = CreateFrame("Frame", nil, f)
	f.buffTicker.owner = f
	f.buffTicker.elapsed = 0
	f.buffTicker:SetScript("OnUpdate", BuffTick)
	f.buffTicker:Hide()

	f.colorCurve = C_CurveUtil.CreateColorCurve()
	f.colorCurve:SetType(Enum.LuaCurveType.Linear)
	f.alphaCurve = C_CurveUtil.CreateCurve()
	f.alphaCurve:SetType(Enum.LuaCurveType.Linear)
	f.showPercent = true
	f:Hide()
	return f
end
