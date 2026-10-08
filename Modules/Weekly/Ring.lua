local addonName, ns = ...

-- A progress ring around an emblem (Factions tab): a dim circle track, the progress as a Cooldown swipe of a filled
-- circle, an inner disc on top that leaves only a ring showing, the emblem (atlas, file or creature portrait) in the
-- middle, a level badge under it and an optional pulsing glow (a paragon reward waiting).
-- The swipe is set up like Plumber's faction rings (reverse, rotated 180 degrees so it starts and ends at the badge,
-- paused before SetCooldown); not yet measured in game.

local UI = ns.UI
local GOLD = UI.GOLD
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local BADGE_OFFSET = 0.06 -- the part of the ring hidden under the badge, at each end (Plumber's visualOffset)

local function Disc(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(CIRCLE)
	t:SetVertexColor(r, g, b, a)
	return t
end

function ns.WeeklyRing_Create(parent, size)
	local ring = CreateFrame("Button", nil, parent)
	ring:SetSize(size, size)
	local thick = math.max(math.floor(size * 0.08 + 0.5), 3)

	ring.selected = Disc(ring, "BACKGROUND", 1, 1, 1, 0.16)
	ring.selected:SetPoint("CENTER")
	ring.selected:SetSize(size + 10, size + 10)
	ring.selected:Hide()

	ring.glow = Disc(ring, "BACKGROUND", GOLD[1], GOLD[2], GOLD[3], 0.45)
	ring.glow:SetPoint("CENTER")
	ring.glow:SetSize(size * 1.3, size * 1.3)
	ring.glow:Hide()
	local pulse = ring.glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.25)
	fade:SetToAlpha(0.9)
	fade:SetDuration(0.9)
	ring.pulse = pulse

	ring.track = Disc(ring, "BORDER", 1, 1, 1, 0.12)
	ring.track:SetAllPoints()

	ring.cd = CreateFrame("Cooldown", nil, ring)
	ring.cd:SetAllPoints()
	ring.cd:SetSwipeTexture(CIRCLE)
	ring.cd:SetDrawEdge(false)
	ring.cd:SetDrawBling(false)
	ring.cd:SetHideCountdownNumbers(true)
	ring.cd:SetReverse(true)
	ring.cd:SetUseCircularEdge(true)
	if ring.cd.SetRotation then
		ring.cd:SetRotation(math.pi)
	end
	ring.cd:EnableMouse(false)

	ring.inner = CreateFrame("Frame", nil, ring)
	ring.inner:SetPoint("TOPLEFT", thick, -thick)
	ring.inner:SetPoint("BOTTOMRIGHT", -thick, thick)
	ring.inner:SetFrameLevel(ring.cd:GetFrameLevel() + 2)
	ring.disc = Disc(ring.inner, "BACKGROUND", 0.09, 0.09, 0.1, 1)
	ring.disc:SetAllPoints()
	ring.icon = ring.inner:CreateTexture(nil, "ARTWORK")
	ring.icon:SetPoint("CENTER")
	local inner = size - 2 * thick
	ring.icon:SetSize(inner * 0.86, inner * 0.86)
	ring.mask = ring.inner:CreateMaskTexture()
	ring.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	ring.mask:SetAllPoints(ring.icon)

	ring.badge = CreateFrame("Frame", nil, ring)
	ring.badge:SetFrameLevel(ring.inner:GetFrameLevel() + 2)
	ring.badge:SetSize(math.max(size * 0.32, 18), math.max(size * 0.22, 14))
	ring.badge:SetPoint("CENTER", ring, "BOTTOM", 0, thick / 2)
	local bbg = ring.badge:CreateTexture(nil, "BACKGROUND")
	bbg:SetAllPoints()
	bbg:SetColorTexture(0.07, 0.07, 0.08, 1)
	UI.Border(ring.badge, GOLD[1], GOLD[2], GOLD[3], 0.7)
	ring.badge.text = ring.badge:CreateFontString(nil, "OVERLAY")
	ring.badge.text:SetFont(ns.HomeKit.NARROW_FONT, math.max(math.floor(size * 0.16), 11), "")
	ring.badge.text:SetPoint("CENTER", 0, 0)
	ring.badge.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	function ring:SetProgress(frac)
		frac = math.min(math.max(frac or 0, 0), 1)
		self.frac = frac
		if frac <= 0 then
			self.cd:Hide()
			return
		end
		if frac < 1 and self.badge:IsShown() then
			frac = BADGE_OFFSET * (1 - frac) + (1 - BADGE_OFFSET) * frac
		end
		self.cd:Show()
		-- 100 "seconds" of which frac have passed, frozen (Plumber's RadialProgressBarMixin does the same).
		self.cd:Pause()
		self.cd:SetCooldown(GetTime() - 100 * frac, 100)
	end

	function ring:SetColor(r, g, b)
		self.cd:SetSwipeColor(r, g, b, 1)
	end

	local function ClearIcon(self)
		if self.masked then
			self.icon:RemoveMaskTexture(self.mask)
			self.masked = false
		end
		self.icon:SetTexCoord(0, 1, 0, 1)
	end

	local function Mask(self)
		self.icon:AddMaskTexture(self.mask)
		self.masked = true
	end

	function ring:SetAtlas(atlas)
		ClearIcon(self)
		self.icon:SetAtlas(atlas)
	end

	function ring:SetFile(fileID)
		ClearIcon(self)
		self.icon:SetTexture(fileID)
		Mask(self)
	end

	function ring:SetPortrait(displayID)
		ClearIcon(self)
		SetPortraitTextureFromCreatureDisplayID(self.icon, displayID)
		Mask(self)
	end

	function ring:SetBadge(text)
		self.badge:SetShown(text ~= nil)
		self.badge.text:SetText(text or "")
		self.badge:SetWidth(math.max(self.badge.text:GetUnboundedStringWidth() + 10, self.badge:GetHeight() + 4))
	end

	function ring:SetGlow(on)
		self.glow:SetShown(on)
		if on then
			if not self.pulse:IsPlaying() then -- a redraw mustn't restart it
				self.pulse:Play()
			end
		else
			self.pulse:Stop()
		end
	end

	function ring:SetSelected(on)
		self.selected:SetShown(on)
	end

	ring:SetColor(GOLD[1], GOLD[2], GOLD[3])
	ring:SetBadge(nil)
	ring:SetProgress(0)
	return ring
end
