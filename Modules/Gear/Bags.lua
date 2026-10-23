local addonName, ns = ...

-- Gear Check in Blizzard's bags: a thicker quality-colored border on rare and better items (off by default), and the
-- bag sort direction ("Clean Up Bags" left to right or right to left). Baganator's bags are left alone. Rules in
-- HelperData.lua; started and stopped by Gear.lua.

local THICKNESS = 2.5 -- border width in UI units (Blizzard's own quality border is about 1)
local DIMMED = 0.25 -- border alpha on items a bag search filters out
local GLOW_KEY = "TomteQualityGlow" -- field on Blizzard's item buttons holding our border textures

local events = ns.Gear_Events
local Glows = ns.GearHelpers_Glows
local SortRightToLeft = ns.GearHelpers_SortRightToLeft

local db
local hooked = {} -- [container frame] = true once its UpdateItems is hooked
local painted = {} -- [item button] = true once it has border textures

local function GlowOn()
	return ns.gearModule.active and db and db.qualityGlow
end

-- Quality border ----------------------------------------------------------------------------------------------------

local function Border(button)
	local edges = button[GLOW_KEY]
	if edges then
		return edges
	end
	edges = {}
	local sides = {
		{ "TOPLEFT", "TOPRIGHT", true },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false },
		{ "TOPRIGHT", "BOTTOMRIGHT", false },
	}
	for i, side in ipairs(sides) do
		local t = button:CreateTexture(nil, "OVERLAY", nil, 2)
		t:SetPoint(side[1])
		t:SetPoint(side[2])
		if side[3] then
			t:SetHeight(THICKNESS)
		else
			t:SetWidth(THICKNESS)
		end
		edges[i] = t
	end
	button[GLOW_KEY] = edges
	painted[button] = true
	return edges
end

local function HideBorder(button)
	for _, t in ipairs(button[GLOW_KEY] or {}) do
		t:Hide()
	end
end

local function Paint(button)
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	local quality = info and info.quality
	if not (GlowOn() and Glows(quality)) then
		HideBorder(button)
		return
	end
	local r, g, b = C_Item.GetItemQualityColor(quality)
	local alpha = info.isFiltered and DIMMED or 1
	for _, t in ipairs(Border(button)) do
		t:SetColorTexture(r, g, b, alpha)
		t:Show()
	end
end

-- Hook body: runs after Blizzard redrew a bag's items. Does nothing while the setting or the module is off (the hook
-- can't be removed), except hide borders it drew before.
local function PaintFrame(frame)
	if not GlowOn() and not next(painted) then
		return
	end
	for _, button in frame:EnumerateValidItems() do
		Paint(button)
	end
end

local function Hook(frame)
	if frame and not hooked[frame] and frame.UpdateItems then
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

-- Repaint the open bags after the setting changed (or hide every border when it's off).
local function RepaintAll()
	if not GlowOn() then
		for button in pairs(painted) do
			HideBorder(button)
		end
		return
	end
	HookAll()
	for frame in pairs(hooked) do
		if frame:IsShown() then
			PaintFrame(frame)
		end
	end
end

-- Sort direction ----------------------------------------------------------------------------------------------------

-- The game's own direction is saved before Tomte first changes it, and put back when the setting goes back to
-- "Don't change" or the module stops.
local function ApplySort()
	if not db then -- the setting changed while Gear Check has never started: nothing of ours to apply or undo
		return
	end
	local want
	if ns.gearModule.active then
		want = SortRightToLeft(db.bagSort)
	end
	local current = C_Container.GetSortBagsRightToLeft()
	if want == nil then
		if db.bagSortGame ~= "none" then
			C_Container.SetSortBagsRightToLeft(db.bagSortGame == "rtl")
			db.bagSortGame = "none"
		end
		return
	end
	if db.bagSortGame == "none" then
		db.bagSortGame = current and "rtl" or "ltr"
	end
	if current ~= want then
		C_Container.SetSortBagsRightToLeft(want)
	end
end

events:On("bags", "PLAYER_ENTERING_WORLD", function()
	ApplySort()
end)

---------------------------------------------------------------------------------------------------------------------

function ns.GearBags_Start(moduleDB)
	db = moduleDB
	events:Watch("bags", "PLAYER_ENTERING_WORLD")
	if ns.inWorld then
		ApplySort()
	end
	EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", RepaintAll)
end

function ns.GearBags_Stop()
	events:UnwatchAll("bags")
	RepaintAll()
	ApplySort()
end

-- Settings changed.
ns.GearBags_RepaintAll = RepaintAll
ns.GearBags_ApplySort = ApplySort
