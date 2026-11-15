local addonName, ns = ...

-- Tomte map: the side panel right of the view. Your quests (QuestTab.lua) and, while the Teleports module is on, its
-- tab, borrowed from the world map's side panel (ns.MapTabs_Borrow in Panel/MapTabs.lua): it lists what goes to the
-- part of the world this map is looking at and marks a destination here. Built and placed by Window.lua; the choice
-- of tab and whether the panel shows are saved (db.side, db.sideShown).

local WIDTH = 290
local TAB_H = 24
local HEAD_H = 26 -- the heading over the quests when they're the only tab
local INSET = 8 -- pixels: the panel's content inside its well
local TP_KEY = "tp" -- Modules/Teleports/MapTab.lua

local UI = ns.UI

local db, side, tabs, body, quests, heading, count
local borrowed -- the Teleports panel while it's here
local viewed -- the map the view looks at (Window.lua tells it)
local Pick

-- What the Teleports tab sees of this map.
local host = {
	mapID = function()
		return viewed
	end,
	showSpot = function(mapID, x, y)
		ns.MapPins_Spot(mapID, x, y)
	end,
	hideSpot = function()
		ns.MapPins_Spot(nil)
	end,
	-- Taken back (the world map picked it, or Teleports was turned off): the quests show instead.
	taken = function()
		borrowed = nil
		ns.MapPins_Spot(nil)
		if side and side:IsShown() then
			Pick("quests")
		end
	end,
}

local function HasTeleports()
	return ns.MapTabs_IsShown ~= nil and ns.MapTabs_IsShown(TP_KEY)
end

local function GiveBack()
	if borrowed then
		borrowed = nil
		ns.MapTabs_Return(TP_KEY)
		ns.MapPins_Spot(nil)
	end
end

function Pick(which)
	if which == "tp" and not HasTeleports() then
		which = "quests"
	end
	db.side = which
	if which == "tp" then
		viewed = ns.MapWindow_CenterMap() -- what the tab lists as it opens
		borrowed = borrowed or ns.MapTabs_Borrow(TP_KEY, body, host)
		if not borrowed then
			which, db.side = "quests", "quests"
		end
	else
		GiveBack()
	end
	quests:SetShown(which == "quests")
	-- One tab: a heading instead of a lone tab button. Two: the tabs.
	local multi = HasTeleports()
	tabs:SetShown(multi)
	heading:SetShown(not multi)
	count:SetShown(not multi)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", INSET, -(INSET + (multi and TAB_H + 8 or HEAD_H)))
	body:SetPoint("BOTTOMRIGHT", -INSET / 2, INSET / 2)
	tabs:Refresh()
end

-- From Window.lua -------------------------------------------------------------------------------------------------------

function ns.MapSide_Build(parent, moduleDB)
	db = moduleDB
	side = CreateFrame("Frame", nil, parent)
	side:SetWidth(WIDTH)
	side:Hide() -- Window.lua shows it, which picks the saved tab (OnShow)
	-- Its own well, as the map's (Window.lua).
	local well = ns.Theme.panel == "forever" and UI.Forever_Well and UI.Forever_Well(side)
	if not well then
		well = CreateFrame("Frame", nil, side)
		UI.Border(well, "frame", 0.6)
	end
	well:SetAllPoints(side)
	heading = UI.Text(side, 14, "heading", "title")
	heading:SetPoint("TOPLEFT", INSET + 4, -(INSET + 4))
	heading:SetText(QUESTS_LABEL or "Quests")
	count = UI.Text(side, 12, "textMuted", "number")
	count:SetPoint("BOTTOMLEFT", heading, "BOTTOMRIGHT", 8, 1)
	tabs = UI.Segmented(side)
	tabs:SetPoint("TOPLEFT", INSET, -INSET)
	tabs.choices = function()
		local list = { { value = "quests", text = QUESTS_LABEL or "Quests" } }
		if HasTeleports() then
			list[2] = { value = "tp", text = "Teleports" }
		end
		return list
	end
	tabs.getValue = function()
		return db.side
	end
	tabs.setValue = function(value)
		Pick(value)
	end
	body = CreateFrame("Frame", nil, side)
	body:SetPoint("TOPLEFT", INSET, -(INSET + HEAD_H))
	body:SetPoint("BOTTOMRIGHT", -INSET / 2, INSET / 2)
	quests = ns.MapQuests_Build(body)
	side:SetScript("OnShow", function()
		Pick(db.side)
	end)
	side:SetScript("OnHide", GiveBack)
	return side, WIDTH
end

-- The view moved: the map it looks at now (a zone, a continent or the world). The Teleports tab follows it.
function ns.MapSide_Viewing(mapID)
	if mapID ~= viewed then
		viewed = mapID
		if borrowed then
			ns.MapTabs_MapChanged(TP_KEY)
		end
	end
end

-- QuestTab.lua: how many quests are in your log (beside the heading).
function ns.MapSide_Count(n)
	if count then
		count:SetText(n > 0 and tostring(n) or "")
	end
end

-- Whether the side panel wants to know which map the view looks at (only the Teleports tab asks).
function ns.MapSide_WantsMap()
	return borrowed ~= nil
end
