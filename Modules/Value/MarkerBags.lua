local addonName, ns = ...

-- Gold & value, item markers in the game's own bags and in Baganator's (Tomte's own bags draw them in
-- Modules/Bags/Buttons.lua). The game's: after Blizzard redraws a bag's items (hooksecurefunc on UpdateItems, as
-- Gear/Bags.lua does), each button gets a marker in the corner the setting picks. The widgets live in a side table,
-- never as fields on Blizzard's buttons. Baganator's: a corner widget, its corner chosen in Baganator's own settings.
-- Markers from Markers.lua; started and stopped by Value.lua through ns.ValueMarkers_Toggle.

local DIMMED = 0.25 -- marker alpha on items a bag search filters out
local INSET = 2 -- from the button's edges
local BAGANATOR_ID = "tomte_marker"
-- A corner's x and y direction away from its edges.
local CORNER_DIRS = {
	TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 },
}

local db
local active = false
local hooked = {} -- [container frame] = true once its UpdateItems is hooked
local markers = {} -- [Blizzard's item button] = marker widget
local baganatorRegistered = false

local function On()
	return active and db.markers.blizzard and not (ns.Bags_Active and ns.Bags_Active())
end

local function BaganatorOn()
	return active and db.markers.baganator
end

-- The game's bags ---------------------------------------------------------------------------------------------------

local function Paint(button)
	local kind
	if On() then
		local marker = ns.Value_BagMarker(button:GetBagID(), button:GetID())
		kind = marker and marker.kind
	end
	local widget = markers[button]
	if not kind then
		if widget then
			widget:SetKind(nil)
		end
		return
	end
	if not widget then
		widget = ns.Value_MarkerWidget(button)
		markers[button] = widget
	end
	local corner = CORNER_DIRS[db.markers.corner] and db.markers.corner or "BOTTOMLEFT"
	local dir = CORNER_DIRS[corner]
	widget:ClearAllPoints()
	widget:SetPoint(corner, dir[1] * INSET, dir[2] * INSET)
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	widget:SetAlpha(info and info.isFiltered and DIMMED or 1)
	widget:SetKind(kind)
end

-- Hook body: runs after Blizzard redrew a bag's items. Does nothing while off (the hook can't be removed), except
-- hide markers it drew before.
local function PaintFrame(frame)
	if not On() and not next(markers) then
		return
	end
	for _, button in frame:EnumerateValidItems() do
		Paint(button)
	end
end

local function Hook(frame)
	if frame and not hooked[frame] and frame.UpdateItems and frame.EnumerateValidItems then
		hooked[frame] = true
		hooksecurefunc(frame, "UpdateItems", PaintFrame)
	end
end

local function HookAll()
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		Hook(frame)
	end
	Hook(ContainerFrameCombinedBags)
end

-- Baganator -----------------------------------------------------------------------------------------------------------

-- Once per session: Baganator can't take a widget back, so the callback checks that markers are on.
local function RegisterBaganator()
	if baganatorRegistered or not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
		return
	end
	baganatorRegistered = true
	Baganator.API.RegisterCornerWidget("Tomte item marker", BAGANATOR_ID, function(widget, details)
		local location = BaganatorOn() and details and details.itemLocation
		if not (location and location.IsBagAndSlot and location:IsBagAndSlot()) then
			return false
		end
		local marker = ns.Value_BagMarker(location:GetBagAndSlot())
		if not (marker and marker.kind) then
			return false
		end
		widget:SetKind(marker.kind)
		return true
	end, function(itemButton)
		return ns.Value_MarkerWidget(itemButton)
	end, { corner = "bottom_left", priority = 1 })
end

-- Settings and start/stop ---------------------------------------------------------------------------------------------

-- Every open bag drawn again: the markers or their settings changed.
function ns.ValueMarkerBags_Repaint()
	if On() then
		HookAll()
	end
	for frame in pairs(hooked) do
		if frame:IsShown() then
			PaintFrame(frame)
		end
	end
	if baganatorRegistered and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

function ns.ValueMarkerBags_Init(saved)
	db = saved
end

function ns.ValueMarkerBags_Toggle(on)
	active = on
	if on then
		-- The game's bag frames come with this addon (loaded at login on retail; ContinueOnAddOnLoaded runs at once
		-- when it already is).
		EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", HookAll)
		RegisterBaganator()
	end
	ns.ValueMarkerBags_Repaint()
end
