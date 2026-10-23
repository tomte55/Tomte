local addonName, ns = ...

-- Waypoints: a ping on your arrow when the world map opens. Rings in the theme's accent spread out from where you
-- stand for about two seconds. Our own frame on the map canvas, placed the way the World quests hover marker is
-- (Modules/WorldQuests/Tab.lua); never Blizzard's player ping or pin pools, which addon code would taint. Shown only
-- while it plays. Turned on and off from Waypoint.lua (ns.WayPing_Toggle).

local RINGS = 3
local RING_DELAY = 0.35 -- seconds between one ring and the next
local RING_TIME = 1.2 -- seconds one ring takes to spread and fade (the last ends ~1.9 s after the map opens)
local RING_SIZE = 36 -- pixels on screen at the start
local RING_GROW = 3 -- a ring's size at the end, as a multiple of RING_SIZE
local RING_ALPHA = 0.9
local STRATA = "FULLSCREEN_DIALOG" -- above every map pin (RareScanner's are DIALOG)
local RING_TEXTURE = ns.Theme.MEDIA .. "Gather\\Ring" -- a thin white ring, tinted (also the minimap node pins')

local UI = ns.UI

local frame
local active, hooked = false, false

local function Build(canvas)
	frame = CreateFrame("Frame", nil, canvas)
	frame:EnableMouse(false)
	frame:SetSize(1, 1)
	frame.rings = {}
	for i = 1, RINGS do
		local ring = frame:CreateTexture(nil, "OVERLAY")
		ring:SetTexture(RING_TEXTURE)
		ring:SetSize(RING_SIZE, RING_SIZE)
		ring:SetPoint("CENTER")
		ring:SetSnapToPixelGrid(false)
		ring:SetTexelSnappingBias(0)
		ring:SetAlpha(0)
		local group = ring:CreateAnimationGroup()
		local grow = group:CreateAnimation("Scale")
		grow:SetScaleFrom(1, 1)
		grow:SetScaleTo(RING_GROW, RING_GROW)
		grow:SetDuration(RING_TIME)
		grow:SetSmoothing("OUT")
		local fade = group:CreateAnimation("Alpha")
		fade:SetFromAlpha(RING_ALPHA)
		fade:SetToAlpha(0)
		fade:SetDuration(RING_TIME)
		fade:SetSmoothing("IN")
		for _, anim in ipairs({ grow, fade }) do
			anim:SetStartDelay((i - 1) * RING_DELAY)
		end
		if i == RINGS then
			group:SetScript("OnFinished", function()
				frame:Hide()
			end)
		end
		ring.group = group
		frame.rings[i] = ring
	end
	frame:Hide()
end

-- Plays the ping on the open map where you stand, if you're on the map it shows (no position in an instance).
-- Returns true when it played.
local function Play()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then
		return false
	end
	local canvas = WorldMapFrame:GetCanvas()
	local mapID = WorldMapFrame:GetMapID()
	local pos = canvas and mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return false
	end
	local x, y = pos.x, pos.y
	if ns.IsSecret(x, y) or not x or x <= 0 or x >= 1 or y <= 0 or y >= 1 then
		return false
	end
	if not frame then
		Build(canvas)
	end
	-- The same size on screen at any zoom: offsets are in the frame's own (scaled) units.
	local scale = UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
	frame:SetScale(scale)
	frame:SetFrameStrata(STRATA)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() / scale, -y * canvas:GetHeight() / scale)
	frame:Show()
	for _, ring in ipairs(frame.rings) do
		ring:SetVertexColor(UI.Color("accent"))
		ring:SetAlpha(0)
		ring.group:Stop()
		ring.group:Play()
	end
	return true
end

local function OnMapShown()
	if not active then
		return
	end
	-- Next frame: the map has switched to your zone and sized its canvas by then.
	C_Timer.After(0, function()
		if active then
			Play()
		end
	end)
end

function ns.WayPing_Toggle(on)
	active = on and true or false
	if active and not hooked and WorldMapFrame then
		hooked = true
		WorldMapFrame:HookScript("OnShow", OnMapShown)
	end
	if not active and frame then
		for _, ring in ipairs(frame.rings) do
			ring.group:Stop()
		end
		frame:Hide()
	end
end

-- /tomte way ping: plays it on the map that's open now.
function ns.WayPing_Play()
	return Play()
end
