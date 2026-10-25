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
	return edges
end

local function HideBorder(button)
	for _, t in ipairs(button[GLOW_KEY] or {}) do
		t:Hide()
	end
end

-- The border in quality's color: on a bag's item button, or on the settings preview's sample buttons.
local function ShowBorder(button, quality, alpha)
	local r, g, b = C_Item.GetItemQualityColor(quality)
	for _, t in ipairs(Border(button)) do
		t:SetColorTexture(r, g, b, alpha)
		t:Show()
	end
end

local function Paint(button)
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	local quality = info and info.quality
	if not (GlowOn() and Glows(quality)) then
		HideBorder(button)
		return
	end
	painted[button] = true
	ShowBorder(button, quality, info.isFiltered and DIMMED or 1)
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

-- Settings preview ---------------------------------------------------------------------------------------------------

local SAMPLE_SIZE = 37 -- an item button in Blizzard's bags
local SAMPLE_GAP = 5
-- Uncommon to legendary, so the preview also shows where the stronger border starts. Icons: module icons elsewhere
-- in Tomte, so known to exist.
local SAMPLES = {
	{ quality = 2, icon = 133071 }, { quality = 3, icon = 132624 }, { quality = 4, icon = 135030 },
	{ quality = 5, icon = 237429 },
}

-- A row of sample bag slots (Panel/Preview.lua): Blizzard's own item button with its quality border, plus ours when
-- the setting is on. Our own buttons, never Blizzard's bag buttons, so nothing goes into `painted`.
function ns.GearBags_DrawSample(host, get)
	host.slots = host.slots or {}
	for i, s in ipairs(SAMPLES) do
		local b = host.slots[i]
		if not b then
			b = CreateFrame("ItemButton", nil, host)
			b:SetSize(SAMPLE_SIZE, SAMPLE_SIZE)
			b:SetPoint("TOPLEFT", (i - 1) * (SAMPLE_SIZE + SAMPLE_GAP), 0)
			host.slots[i] = b
		end
		b:SetItemButtonTexture(s.icon)
		b:SetItemButtonQuality(s.quality)
		if get("qualityGlow") and Glows(s.quality) then
			ShowBorder(b, s.quality, 1)
		else
			HideBorder(b)
		end
	end
	return #SAMPLES * (SAMPLE_SIZE + SAMPLE_GAP) - SAMPLE_GAP, SAMPLE_SIZE
end

-- Settings changed.
ns.GearBags_RepaintAll = RepaintAll
ns.GearBags_ApplySort = ApplySort
