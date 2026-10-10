local addonName, ns = ...

-- Recorded/estimated flight time on taxi map tooltips, and a note on flight masters without a recorded
-- time (see MapCoverage.lua). The hooks can't be removed, so they check whether the module is on.

local function AddTimeLine(slot)
	if not ns.flightModule.active then
		return
	end
	local route = ns.BuildRoute(slot)
	if not route then
		return
	end
	local t, isEstimate = ns.LookupTime(ns.flightDB, route.path, route)
	if not t then
		return
	end
	GameTooltip:AddLine((isEstimate and "~" or "") .. ns.FormatTime(t), 1, 1, 1)
	GameTooltip:Show()
end

local function OnPinEnter(pin)
	local data = pin.taxiNodeData
	if not data then
		return
	end
	if data.state == Enum.FlightPathState.Reachable then
		AddTimeLine(data.slotIndex)
	end
	if ns.flightModule.active and not data.isMapLayerTransition and not ns.MapCoverage_IsTimed(data.nodeID) then
		GameTooltip:AddLine("No recorded time to or from here", ns.UI.RGB("warning"))
		GameTooltip:Show()
	end
end

local flightMapHooked
function ns.HookFlightMap()
	if flightMapHooked then
		return
	end
	flightMapHooked = true
	ns.MapCoverage_Hook()
	-- Pins created from now on copy the hooked method into their OnEnter script.
	hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", OnPinEnter)
	-- Pins that already exist captured the original method; hook their script directly.
	if FlightMapFrame then
		for pin in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
			pin:HookScript("OnEnter", OnPinEnter)
		end
	end
end

function ns.HookTaxiFrame()
	if not TaxiNodeOnButtonEnter then
		return
	end
	hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
		local slot = button:GetID()
		if TaxiNodeGetType(slot) == "REACHABLE" then
			AddTimeLine(slot)
		end
	end)
end
