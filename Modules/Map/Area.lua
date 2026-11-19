local addonName, ns = ...

-- Tomte map: the active quest's area, drawn on its zone as the game's map does. Placed during each layout
-- (ns.MapArea_Draw, from Pins.lua) and drawn again after every zoom (ns.MapArea_Redraw, from Window.lua).

local AREA_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local AREA_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"
-- Of 255, fill and border: over the ground pictures as light as the minimap's (Modules/QuestList/Minimap.lua), which
-- lets the terrain show; over the zone maps' bright parchment the game's own (QuestBlobPinMixin:OnLoad), or it's hard
-- to see. Between the two as the ground pictures fade in.
local AREA_LIGHT, AREA_STRONG = { 56, 128 }, { 128, 192 }

local db
local blobQuest

-- The active quest's area --------------------------------------------------------------------------------------------

-- One area frame, laid out the way the game's map does it: a direct child of the canvas, the size of the map it
-- draws (QuestBlobDataProviderMixin), drawn again after every zoom (ns.MapArea_Redraw). Drawn once and then
-- scaled or moved, it landed in the wrong place and drifted with the zoom (measured 2026-11-15).
local blob
local blobZone

local function AreaFrame(canvas)
	if not blob then
		blob = CreateFrame("QuestPOIFrame", nil, canvas)
		blob:EnableMouse(false)
		blob:SetFillTexture(AREA_FILL)
		blob:SetBorderTexture(AREA_BORDER)
		blob:SetBorderScalar(1.0)
	end
	return blob
end

-- The zone whose map lists the quest: the smallest one, so a neighbour that also lists it doesn't win.
local function QuestZone(quest)
	local best
	for _, z in ipairs(ns.MapArt_Zones()) do
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(z.mapID) or {}) do
			if info.questID == quest then
				if not best or z.box.w * z.box.h < best.box.w * best.box.h then
					best = z
				end
				break
			end
		end
	end
	return best
end

-- The active quest's area, on its own zone while that zone's art shows.
local function DrawAreas(force)
	local quest = db.questArea and ns.ActiveQuest_ID() or nil
	if quest and ns.IsSecret(quest) then
		quest = nil
	end
	-- A finished quest's objective area is done with, as on the world map (Modules/QuestList/Map.lua): its pin is the
	-- hand-in now.
	if quest and (C_QuestLog.ReadyForTurnIn(quest) or C_QuestLog.IsComplete(quest)) then
		quest = nil
	end
	if force or quest ~= blobQuest then
		blobQuest = quest
		blobZone = quest and QuestZone(quest) or nil
		if blob then
			blob.drawn = nil
		end
	end
	local zone = blobZone
	if not (zone and zone.visible and zone.frame) then
		if blob then
			blob:Hide()
		end
		return
	end
	local canvas = zone.frame:GetParent()
	local frame = AreaFrame(canvas)
	if frame.drawn ~= quest or frame.zone ~= zone then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", zone.box.l, -zone.box.t)
		frame:SetSize(zone.box.w, zone.box.h)
		frame:SetFrameLevel(canvas:GetFrameLevel() + 30) -- over the zones' art and the minimap tiles (Mini.lua, 20)
		frame:SetMapID(zone.mapID)
		frame:DrawNone()
		frame.drawn, frame.zone = quest, zone
		ns.MapWindow_AreaDirty() -- drawn once the layout is done (ns.MapArea_Redraw)
	end
	frame:Show()
end

-- Window.lua, after the canvas was placed or scaled: the area drawn for where it now is. Asking for the frame's edge
-- first makes the game place it now, so it's drawn for its new spot in this same frame (drawn before that it landed
-- where the frame was; drawn a frame later it shook during a zoom, measured 2026-11-15).
function ns.MapArea_Redraw()
	if blob and blob:IsShown() and blob.drawn then
		local ground = ns.MapMini_Showing()
		blob:SetFillAlpha(math.floor(AREA_STRONG[1] + (AREA_LIGHT[1] - AREA_STRONG[1]) * ground + 0.5))
		blob:SetBorderAlpha(math.floor(AREA_STRONG[2] + (AREA_LIGHT[2] - AREA_STRONG[2]) * ground + 0.5))
		blob:GetLeft()
		blob:DrawNone()
		blob:DrawBlob(blob.drawn, true)
	end
end

-- From Pins.lua -------------------------------------------------------------------------------------------------------

function ns.MapArea_Init(moduleDB)
	db = moduleDB
end

-- Each layout: the area placed for the active quest.
function ns.MapArea_Draw(force)
	DrawAreas(force)
end

-- The quest log or the active quest changed: the area's zone is looked up again.
function ns.MapArea_Forget()
	blobQuest = nil
end

ns.MapArea_QuestZone = QuestZone

-- Fade.lua: the area frame (nil until first drawn), faded as one picture while the map fades.
function ns.MapArea_Frame()
	return blob
end
