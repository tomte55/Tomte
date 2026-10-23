local addonName, ns = ...

-- Housing decor: a click on Blizzard's "decor acquired" alert (HousingItemEarnedAlertFrameSystem in
-- AlertFrameSystems.lua) previews that decor in Blizzard's housing model preview (HousingFramesUtil
-- .PreviewHousingDecorID). The alert only carries the decor's name: the ID comes from the decor that just reached your
-- chest (HOUSE_DECOR_ADDED_TO_CHEST, named by C_HousingDecor.GetDecorName), else from the catalog Tomte read.
-- Name lookup in EditorData.lua; registered in Decor.lua.

local RECENT_MAX = 20 -- names kept from decor that reached the chest this session
local UI = ns.UI

local OWNER = "alert"
local events = ns.Decor_Events

local db
local active = false
local hookedSystem = false
local hookedFrames = {}
local recent, recentOrder = {}, {} -- [name] = decorID; names in arrival order

local function Remember(decorID)
	if type(decorID) ~= "number" or not C_HousingDecor.GetDecorName then
		return
	end
	local ok, name = pcall(C_HousingDecor.GetDecorName, decorID)
	if not ok or type(name) ~= "string" or name == "" or recent[name] then
		return
	end
	recent[name] = decorID
	recentOrder[#recentOrder + 1] = name
	if #recentOrder > RECENT_MAX then
		recent[table.remove(recentOrder, 1)] = nil
	end
end

events:On(OWNER, "HOUSE_DECOR_ADDED_TO_CHEST", function(_, _, decorID)
	Remember(decorID)
end)

local function Preview(name)
	local decorID = ns.DecorEditor_FindByName(name, recent, ns.DecorCatalog_Entries())
	if not decorID then
		ns.Print(("can't find %s in the housing catalog yet."):format(name or "that decor"))
		return
	end
	if InCombatLockdown() then
		ns.Print("the decor preview opens out of combat.")
		return
	end
	if HousingFramesUtil and HousingFramesUtil.PreviewHousingDecorID then
		HousingFramesUtil.PreviewHousingDecorID(decorID)
	end
end

-- Left-click previews; Blizzard's own click handling (right-click dismisses) runs first and stays as it is.
local function OnAlertClick(frame, button)
	if not (active and db.alertPreview) or button ~= "LeftButton" then
		return
	end
	local label = frame.DecorName
	Preview(label and label:GetText())
end

local function OnAlertEnter(frame)
	if active and db.alertPreview then
		GameTooltip:SetOwner(frame, "ANCHOR_TOP")
		UI.TipLine("Click to preview this decor.", "text")
		GameTooltip:Show()
	end
end

-- Only our own hint: the hook stays after the setting is turned off.
local function OnAlertLeave(frame)
	if GameTooltip:GetOwner() == frame then
		GameTooltip:Hide()
	end
end

-- Each alert frame is hooked once, when the system first sets it up (frames are reused). Hooks can't be undone:
-- they check the setting.
local function OnSetUp(frame)
	if not (active and db.alertPreview) or hookedFrames[frame] then
		return
	end
	hookedFrames[frame] = true
	frame:HookScript("OnClick", OnAlertClick)
	frame:HookScript("OnEnter", OnAlertEnter)
	frame:HookScript("OnLeave", OnAlertLeave)
end

local function HookSystem()
	local system = HousingItemEarnedAlertFrameSystem
	if hookedSystem or not (system and system.setUpFunction) then
		return
	end
	hookedSystem = true
	hooksecurefunc(system, "setUpFunction", OnSetUp)
end

-- Called by Decor.lua -------------------------------------------------------------------------------------------------

function ns.DecorAlert_Init(moduleDB)
	db = moduleDB
end

function ns.DecorAlert_Start()
	active = true
	if db.alertPreview then
		events:TryWatch(OWNER, "HOUSE_DECOR_ADDED_TO_CHEST")
		HookSystem()
	end
end

function ns.DecorAlert_Stop()
	active = false
	events:UnwatchAll(OWNER)
end

function ns.DecorAlert_Apply()
	if active then
		ns.DecorAlert_Stop()
		ns.DecorAlert_Start()
	end
end
