local addonName, ns = ...

-- Quest list: the game's objective tracker, muted while the list is on. It can't be hidden or moved for good: it's a
-- right-side managed frame, and the game's layout gives it its parent back (ManagedFrameContainerMixin:UpdateFrame) and
-- shows it again on every update (ObjectiveTrackerContainerMixin:Update), and its OnHide relays out the right side.
-- So it stays where the game keeps it, at alpha 0, and its click catchers (blocks, title buttons, item and POI buttons,
-- objective lines, header buttons) stop taking the mouse. EnableMouse runs no script and writes no field on Blizzard's
-- tables, and none of these frames is protected. Blocks handed out later are caught by the AddBlock hook and a sweep
-- after each tracker update. Everything comes back as it was when the list turns off. The same approach EllesmereUI's
-- quest tracker takes on Forever (its "custom tracker" mode); no code taken from it.

local muted = false
local hooked = false
local hookedModules = setmetatable({}, { __mode = "k" })
local mouseOff = setmetatable({}, { __mode = "k" }) -- [frame] = 1 (clicks were on), 2 (motion), 3 (both)
local sweepPending = false

local function MouseOff(f)
	if type(f) ~= "table" or not f.EnableMouse or mouseOff[f] then
		return
	end
	local mode
	if f.IsMouseClickEnabled and f.IsMouseMotionEnabled then
		mode = (f:IsMouseClickEnabled() and 1 or 0) + (f:IsMouseMotionEnabled() and 2 or 0)
	else
		mode = f:IsMouseEnabled() and 3 or 0
	end
	if mode == 0 then
		return -- never turn on later what the game left off
	end
	mouseOff[f] = mode
	f:EnableMouse(false)
end

local function BlockOff(block)
	if type(block) ~= "table" then
		return
	end
	MouseOff(block)
	MouseOff(block.HeaderButton)
	MouseOff(block.ItemButton)
	MouseOff(block.poiButton)
	if type(block.usedLines) == "table" then
		for _, line in pairs(block.usedLines) do
			MouseOff(line)
		end
	end
	if type(block.addedRegions) == "table" then
		for region in pairs(block.addedRegions) do
			if type(region) == "table" then
				MouseOff(region)
				MouseOff(region.Bar)
			end
		end
	end
end

-- The scenario and widget trackers share Blizzard's widget pools with the rest of the UI: only their headers.
local function SharesPool(module)
	return module == rawget(_G, "ScenarioObjectiveTracker") or module == rawget(_G, "UIWidgetObjectiveTracker")
end

local function ModuleOff(module)
	if module.Header then
		MouseOff(module.Header.MinimizeButton)
	end
	if SharesPool(module) or type(module.usedBlocks) ~= "table" then
		return
	end
	for _, byTemplate in pairs(module.usedBlocks) do
		if type(byTemplate) == "table" then
			for _, block in pairs(byTemplate) do
				BlockOff(block)
			end
		end
	end
end

local function HookModule(module)
	if hookedModules[module] or SharesPool(module) or not module.AddBlock then
		return
	end
	hookedModules[module] = true
	hooksecurefunc(module, "AddBlock", function(_, block)
		if muted then
			BlockOff(block)
		end
	end)
end

local function Sweep()
	sweepPending = false
	local otf = rawget(_G, "ObjectiveTrackerFrame")
	if not (muted and otf) then
		return
	end
	for _, module in ipairs(otf.modules or {}) do
		HookModule(module)
		ModuleOff(module)
	end
	local header = otf.Header or otf.HeaderMenu
	if header then
		MouseOff(header.MinimizeButton)
		MouseOff(header.FilterButton)
	end
end

local function SweepSoon()
	if muted and not sweepPending then
		sweepPending = true
		C_Timer.After(0, Sweep)
	end
end

local function Hook(otf)
	if hooked then
		return
	end
	hooked = true
	-- Edit Mode and the managed-frame fades set its alpha back.
	hooksecurefunc(otf, "SetAlpha", function(self, alpha)
		if muted and alpha ~= 0 then
			self:SetAlpha(0)
		end
	end)
	if otf.Update then
		hooksecurefunc(otf, "Update", SweepSoon)
	end
	if otf.AddModule then
		hooksecurefunc(otf, "AddModule", SweepSoon)
	end
end

-- on: invisible and click-through; off: as it was. Returns false when the tracker isn't loaded yet.
function ns.QuestListTracker_Mute(on)
	local otf = rawget(_G, "ObjectiveTrackerFrame")
	if not otf then
		return false
	end
	Hook(otf)
	if on and not muted then
		muted = true
		otf:SetAlpha(0)
		Sweep()
	elseif not on and muted then
		muted = false
		otf:SetAlpha(1)
		for f, mode in pairs(mouseOff) do
			mouseOff[f] = nil
			if mode == 3 or not f.SetMouseClickEnabled then
				f:EnableMouse(true)
			elseif mode == 1 then
				f:SetMouseClickEnabled(true)
			else
				f:SetMouseMotionEnabled(true)
			end
		end
	end
	return true
end

-- For /tomte questlist why.
function ns.QuestListTracker_State()
	local otf = rawget(_G, "ObjectiveTrackerFrame")
	if not otf then
		return "not loaded"
	end
	local n = 0
	for _ in pairs(mouseOff) do
		n = n + 1
	end
	return muted and ("muted, alpha %.2f, %d click catchers off"):format(otf:GetAlpha(), n) or "showing"
end
