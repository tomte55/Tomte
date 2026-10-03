local addonName, ns = ...

-- Coverage on the flight master map: a strip at the top with timed / total flight masters for the map on
-- screen and the zone the player is in, and an orange dot on every flight master without a recorded time
-- (its tooltip says so too). Refreshed each time the map opens, one frame after Blizzard places the pins.

local ORANGE = { 1, 0.55, 0.25 }
local STRIP_PAD = 12

local strip
local timed = {} -- [nodeID] = true, from the last refresh (pin tooltips read it)

local function CreateStrip()
	local UI = ns.UI
	strip = CreateFrame("Frame", nil, FlightMapFrame)
	strip:SetHeight(24)
	strip:SetPoint("TOP", FlightMapFrame.ScrollContainer, "TOP", 0, -8)
	strip:SetFrameLevel(FlightMapFrame.ScrollContainer:GetFrameLevel() + 1000) -- above the pins
	local bg = strip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	UI.Border(strip, UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.35)
	strip.text = UI.Text(strip, 12, UI.WHITE)
	strip.text:SetPoint("CENTER", 0, 0)
end

local function Line(name, nodes)
	local n, total = ns.Coverage_Count(nodes, timed)
	return ("|cffffd173%s|r  %d / %d"):format(name, n, total)
end

local function Dot(pin)
	local dot = pin:CreateTexture(nil, "OVERLAY", nil, 7)
	dot:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
	dot:SetSize(7, 7)
	dot:SetPoint("CENTER", pin, "TOPRIGHT", -2, -2)
	local mask = pin:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(dot)
	dot:AddMaskTexture(mask)
	pin.tomteDot = dot
	return dot
end

local function UpdatePins(active)
	for pin in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
		local data = pin.taxiNodeData
		local show = active and data ~= nil and not data.isMapLayerTransition and not timed[data.nodeID]
		if show or pin.tomteDot then
			(pin.tomteDot or Dot(pin)):SetShown(show)
		end
	end
end

local function Refresh()
	if not FlightMapFrame:IsShown() then
		return
	end
	local active = ns.flightModule.active
	if active then
		timed = ns.Coverage_Timed(ns.flightDB)
		if not strip then
			CreateStrip()
		end
		local parts = {}
		local mapID = FlightMapFrame:GetMapID()
		local info = mapID and C_Map.GetMapInfo(mapID)
		if info then
			parts[1] = Line(info.name, ns.Atlas_MapNodes(mapID))
		end
		local here = ns.Atlas_PlayerZone()
		if here and here.mapID ~= mapID then
			parts[#parts + 1] = Line(here.name, ns.Atlas_MapNodes(here.mapID))
		end
		strip.text:SetText("Flight masters timed:   " .. table.concat(parts, "      "))
		strip:SetWidth(strip.text:GetStringWidth() + 2 * STRIP_PAD)
		strip:Show()
	elseif strip then
		strip:Hide()
	end
	UpdatePins(active)
end

function ns.MapCoverage_IsTimed(nodeID)
	return timed[nodeID] == true
end

function ns.MapCoverage_Hook()
	FlightMapFrame:HookScript("OnShow", function()
		C_Timer.After(0, Refresh)
	end)
end

ns.ORANGE = ORANGE
