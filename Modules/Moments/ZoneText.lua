local addonName, ns = ...

-- Moments: zone text in the theme. Blizzard's zone and subzone text (Blizzard_FrameXML ZoneText.lua) keeps
-- running, only its strings are made invisible; this card copies what it shows, every frame. So it appears whenever
-- Blizzard's would (and not while a toast holds it back), fades with Blizzard's times (on its own clock), and
-- goes when a discovery card hides Blizzard's frames (Banner_SuppressZoneText). Banners still wait for Blizzard's
-- frames, so they never land on top of it. A new place shows once it has held for a moment (walking along a border
-- flips the subzone back and forth), with a quick fade out and in.

local LINE_WIDTH = 260
local CARD_WIDTH = LINE_WIDTH + 200 -- the card and its text lines: room for long names beyond the line
local FROM_TOP = 128 -- px, where Blizzard's ZoneTextFrame sits
local BLIZZARD_STRINGS = { "ZoneTextString", "PVPInfoTextString", "SubZoneTextString", "PVPArenaTextString" }
local SETTLE = 0.4 -- seconds a new place must hold before the card shows it

local frame, block, swap
local enabled, hooked = false, false

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(CARD_WIDTH, 100)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -FROM_TOP)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(false)
	frame:Hide()
	block = CreateFrame("Frame", nil, frame) -- fades on its own for a change of place; frame follows Blizzard
	block:SetAllPoints()
	swap = ns.NewSwap(block)

	block.title = block:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(block.title, "title", 26)
	block.title:SetTextColor(ns.Theme.Color("heading"))
	block.title:SetShadowOffset(2, -2)
	block.title:SetShadowColor(0, 0, 0, 0.9)
	block.title:SetPoint("TOP")
	block.title:SetWidth(CARD_WIDTH)

	block.line = ns.SceneLine(block, LINE_WIDTH, 0.8)
	block.line:SetPoint("TOPLEFT", block.title, "BOTTOM", -LINE_WIDTH / 2, -6)
	block.diamond = block:CreateTexture(nil, "OVERLAY", nil, 1)
	block.diamond:SetColorTexture(ns.Theme.Color("frame"))
	block.diamond:SetSize(5, 5)
	block.diamond:SetRotation(math.pi / 4)
	block.diamond:SetPoint("CENTER", block.title, "BOTTOM", 0, -6)

	block.subtitle = block:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(block.subtitle, "body", 15)
	block.subtitle:SetTextColor(ns.Theme.Color("text"))
	block.subtitle:SetShadowOffset(1, -1)
	block.subtitle:SetShadowColor(0, 0, 0, 0.9)
	block.subtitle:SetPoint("TOP", block.title, "BOTTOM", 0, -14)
	block.subtitle:SetWidth(CARD_WIDTH)

	block.status = block:CreateFontString(nil, "OVERLAY")
	ns.Theme.SetFont(block.status, "label", 11)
	block.status:SetShadowOffset(1, -1)
	block.status:SetShadowColor(0, 0, 0, 0.9)
end

local function Text(fs)
	local text = fs and fs:GetText()
	return text ~= "" and text or nil
end

-- Blizzard's frames, read the way they're drawn: the zone frame shows the zone (and its PvP line), the subzone
-- frame the subzone (and the PvP line of a PvP subzone or combat zone).
local function Read()
	local zoneShown, subShown = ZoneTextFrame:IsShown(), SubZoneTextFrame:IsShown()
	local name = zoneShown and Text(ZoneTextString)
	local subName = subShown and Text(SubZoneTextString)
	local status = (zoneShown and Text(PVPInfoTextString)) or (subShown and Text(PVPArenaTextString))
	if not name then
		name, subName = subName, nil
	elseif subName == name then
		subName = nil
	end
	return name, subName, ns.Moments_ZoneStatus(status or nil)
end

local function Layout(name, subName, status)
	block.title:SetText(name)
	block.subtitle:SetText(subName or "")
	block.status:ClearAllPoints()
	block.status:SetPoint("TOP", subName and block.subtitle or block.title, "BOTTOM", 0, subName and -6 or -14)
	block.status:SetText(status and ns.Spaced(status) or "")
	if status then
		block.status:SetTextColor(ns.UI.RGBA(ns.Moments_ZonePvPRole((C_PvP.GetZonePVPInfo())), 1))
	end
end

-- Blizzard's fading frame (FadingFrame.lua) is over by itself, not hidden early by a discovery card.
local function RanOut(f)
	return not f.startTime or FadingFrame_GetRemainingTime(f) <= 0.1
end

-- The card fades on its own clock with Blizzard's times (the ZoneFadeInDuration, ZoneHoldDuration and
-- ZoneFadeOutDuration globals from its ZoneText.lua): Blizzard restarts its fade from 0 on every zone event,
-- even for the same text, and copying that made the card blink. A new place or a restart only tops it back up.
local alpha, holdLeft = 0, 0
local shownKey, pendingKey, pendingFor
local starts = {} -- [Blizzard frame] = its fade's startTime when we last looked
local function Reset()
	alpha, holdLeft = 0, 0
	shownKey, pendingKey = nil, nil
	wipe(starts)
	ns.ResetSwap(swap)
end

local function Close(self)
	Reset()
	self:SetAlpha(0)
	self:Hide()
end

local function OnUpdate(self, elapsed)
	local zone, sub = ZoneTextFrame, SubZoneTextFrame
	local blizzardShown = zone:IsShown() or sub:IsShown()
	if blizzardShown then
		local name, subName, status = Read()
		local key = name and (name .. "\n" .. (subName or "") .. "\n" .. (status or ""))
		if key ~= pendingKey then
			pendingKey, pendingFor = key, 0
		else
			pendingFor = pendingFor + elapsed
		end
		local restarted = false
		for _, f in ipairs({ zone, sub }) do
			if f:IsShown() and f.startTime ~= starts[f] then
				starts[f], restarted = f.startTime, true
			end
		end
		if key and key ~= shownKey and pendingFor >= SETTLE then
			if not shownKey then
				block:SetAlpha(1) -- first place: no cross-fade, the card fades in as a whole
				Layout(name, subName, status)
			else
				ns.StartSwap(swap, function()
					Layout(name, subName, status)
				end)
			end
			shownKey, holdLeft = key, ZoneHoldDuration
		elseif restarted and key == shownKey then
			holdLeft = ZoneHoldDuration
		end
	elseif not (RanOut(zone) and RanOut(sub)) then
		Close(self) -- hidden early (a discovery card names the place): go now
		return
	else
		pendingKey, holdLeft = nil, 0 -- ran out: finish our own fade
	end
	if not shownKey then
		if blizzardShown then
			self:SetAlpha(0) -- waiting for the place to settle
		else
			Close(self)
		end
		return
	end
	if holdLeft > 0 then
		alpha = math.min(1, alpha + elapsed / ZoneFadeInDuration)
		if alpha >= 1 then
			holdLeft = holdLeft - elapsed
		end
	else
		alpha = math.max(0, alpha - elapsed / ZoneFadeOutDuration)
		if alpha == 0 and not blizzardShown then
			Close(self)
			return
		end
	end
	ns.UpdateSwap(swap, elapsed)
	self:SetAlpha(alpha)
end

local function OnBlizzardShow()
	if enabled and frame then
		frame:Show()
	end
end

local function SetBlizzardVisible(visible)
	for _, key in ipairs(BLIZZARD_STRINGS) do
		local fs = _G[key]
		if fs then
			fs:SetAlpha(visible and 1 or 0)
		end
	end
end

-- On while Moments is on and its "Zone text" option is; called from Moments' toggle and the option.
function ns.Moments_ZoneText(on)
	on = on and true or false
	if not (ZoneTextFrame and SubZoneTextFrame) or on == enabled then
		return
	end
	enabled = on
	if on then
		if not frame then
			Build()
			frame:SetScript("OnUpdate", OnUpdate)
		end
		if not hooked then
			ZoneTextFrame:HookScript("OnShow", OnBlizzardShow)
			SubZoneTextFrame:HookScript("OnShow", OnBlizzardShow)
			hooked = true
		end
		SetBlizzardVisible(false)
		if ZoneTextFrame:IsShown() or SubZoneTextFrame:IsShown() then
			frame:Show()
		end
	else
		SetBlizzardVisible(true)
		if frame then
			Reset()
			frame:Hide()
		end
	end
end
