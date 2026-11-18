local addonName, ns = ...

-- Quest list: the quest Tomte follows (ns.ActiveQuest_Follow), shown on the world map the way the game shows its own
-- active quest: its area, a ring around its pin, and a bar on its row in the map's quest log. Making it the game's
-- active quest from addon code taints the map and the tracker (see ns.ActiveQuest_Follow in Core/Core.lua), so these
-- are Tomte's own frames: the area and the ring on the map canvas (as Waypoints' map ping, Modules/Travel/MapPing.lua),
-- the bar a child of the quest log row it marks. Blizzard's rows, pools and fields are only read. Nothing shows while
-- the followed quest is the game's active quest too: the game marks that one itself. Started from QuestList.lua.

local RING_SIZE = 40 -- pixels on screen: around a quest pin (the map's quest pins are about 24)
local RING_ALPHA_LOW, RING_ALPHA_HIGH = 0.45, 0.95 -- the ring breathes between these
local RING_BREATH = 1.2 -- seconds from one to the other
local RING_STRATA = "FULLSCREEN_DIALOG" -- above every map pin, as the map ping
local AREA_FILL_ALPHA, AREA_BORDER_ALPHA = 128, 192 -- of 255: the game's own quest area (QuestBlobPinMixin:OnLoad)
local BAR_W = 3
local BAND_ALPHA = 0.10
local RING_TEXTURE = ns.Theme.MEDIA .. "Gather\\Ring" -- a thin white ring, tinted (also the map ping's)
local AREA_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local AREA_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"

local UI = ns.UI

local active = false
local hooked = false
local holder, area, ringFrame -- on the map canvas
local marks = {} -- [quest log row] = our bar frame on it
local placedMap, placedScale, placedQuest, placedWidth

-- The quest to mark: Tomte's followed quest, when it isn't the game's active quest as well.
local function Quest()
	if not (active and ns.QuestList_DB().mapMark and ns.ActiveQuest_IsFollowed()) then
		return nil
	end
	local id = ns.ActiveQuest_ID()
	local game = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	if not id or ns.IsSecret(id, game) or id == game then
		return nil
	end
	return id
end

-- The map ------------------------------------------------------------------------------------------------------------

local Place

-- The frame level the map draws its own quest areas at: above the explored-area art (PIN_FRAME_LEVEL_MAP_EXPLORATION),
-- under the pins. At the canvas's own level our area only showed through where the map was still unexplored. Read
-- from the map's frame level table, never asked through its functions (a call into the map from here taints it).
local BLOB_LEVEL_FALLBACK = 2010 -- the map's levels count from 2000; the quest areas sit a few above (Forever 1.60.1)
local function QuestBlobLevel()
	local manager = WorldMapFrame.pinFrameLevelsManager
	local definition = manager and manager.definitions and manager.definitions.PIN_FRAME_LEVEL_QUEST_BLOB
	return type(definition) == "table" and type(definition.startLevel) == "number" and definition.startLevel
		or BLOB_LEVEL_FALLBACK
end

local function Build(canvas)
	holder = CreateFrame("Frame", nil, canvas)
	holder:SetAllPoints(canvas)
	holder:EnableMouse(false)
	-- The area: the same kind of frame the map draws its own quest areas with, under the pins.
	area = CreateFrame("QuestPOIFrame", nil, holder)
	area:SetAllPoints(canvas)
	area:EnableMouse(false)
	area:SetFrameLevel(QuestBlobLevel())
	area:SetFillTexture(AREA_FILL)
	area:SetBorderTexture(AREA_BORDER)
	area:SetFillAlpha(AREA_FILL_ALPHA)
	area:SetBorderAlpha(AREA_BORDER_ALPHA)
	area:SetBorderScalar(1.0)
	-- The ring: the same size on screen at any zoom (its scale is set when placed).
	ringFrame = CreateFrame("Frame", nil, holder)
	ringFrame:SetSize(RING_SIZE, RING_SIZE)
	ringFrame:EnableMouse(false)
	ringFrame:SetFrameStrata(RING_STRATA)
	ringFrame.ring = ringFrame:CreateTexture(nil, "OVERLAY")
	ringFrame.ring:SetTexture(RING_TEXTURE)
	ringFrame.ring:SetAllPoints()
	ringFrame.ring:SetSnapToPixelGrid(false)
	ringFrame.ring:SetTexelSnappingBias(0)
	local breathe = ringFrame:CreateAnimationGroup()
	breathe:SetLooping("BOUNCE")
	local fade = breathe:CreateAnimation("Alpha")
	fade:SetFromAlpha(RING_ALPHA_HIGH)
	fade:SetToAlpha(RING_ALPHA_LOW)
	fade:SetDuration(RING_BREATH)
	fade:SetSmoothing("IN_OUT")
	ringFrame.breathe = breathe
	ringFrame:Hide()
	-- Shown with the map (it's on the canvas): follows map changes, zoom and the followed quest while it shows.
	holder:SetScript("OnUpdate", function()
		local canvasNow = WorldMapFrame:GetCanvas()
		if WorldMapFrame:GetMapID() ~= placedMap or canvasNow:GetEffectiveScale() ~= placedScale
			or canvasNow:GetWidth() ~= placedWidth or Quest() ~= placedQuest then
			Place()
		end
	end)
end

-- The quest's pin on mapID: x, y (0..1), or nil when it has none there.
local function PinSpot(mapID, questID)
	for _, q in ipairs(C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(mapID) or {}) do
		if q.questID == questID and q.x and q.y and not ns.IsSecret(q.x, q.y) then
			return q.x, q.y
		end
	end
	return nil
end

Place = function()
	local canvas = WorldMapFrame:GetCanvas()
	local mapID = WorldMapFrame:GetMapID()
	local quest = Quest()
	placedMap, placedScale, placedWidth, placedQuest = mapID, canvas:GetEffectiveScale(), canvas:GetWidth(), quest
	area:DrawNone()
	ringFrame.breathe:Stop()
	ringFrame:Hide()
	if not (quest and mapID) then
		return
	end
	local info = C_Map.GetMapInfo(mapID)
	if not (info and MapUtil and MapUtil.ShouldMapTypeShowQuests and MapUtil.ShouldMapTypeShowQuests(info.mapType)) then
		return
	end
	-- A finished quest's objective area is done with (the game's own areas skip finished quests too); its ring still
	-- marks the pin, which is the hand-in now.
	if not (C_QuestLog.ReadyForTurnIn(quest) or C_QuestLog.IsComplete(quest)) then
		area:SetMapID(mapID)
		area:DrawBlob(quest, true)
	end
	local x, y = PinSpot(mapID, quest)
	if x then
		local scale = UIParent:GetEffectiveScale() / canvas:GetEffectiveScale()
		ringFrame:SetScale(scale)
		ringFrame:ClearAllPoints()
		ringFrame:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() / scale, -y * canvas:GetHeight() / scale)
		ringFrame.ring:SetVertexColor(UI.Color("accent"))
		ringFrame:Show()
		ringFrame.breathe:Play()
	end
end

-- The quest log ------------------------------------------------------------------------------------------------------

local function Mark(row)
	local m = marks[row]
	if not m then
		m = CreateFrame("Frame", nil, row)
		m:SetAllPoints(row)
		m:EnableMouse(false)
		m.band = m:CreateTexture(nil, "BACKGROUND")
		m.band:SetAllPoints()
		m.bar = m:CreateTexture(nil, "OVERLAY")
		m.bar:SetPoint("TOPLEFT", 0, -1)
		m.bar:SetPoint("BOTTOMLEFT", 0, 1)
		m.bar:SetWidth(BAR_W)
		marks[row] = m
	end
	m.band:SetColorTexture(UI.Color("accent"))
	m.band:SetAlpha(BAND_ALPHA)
	m.bar:SetColorTexture(UI.Color("accent"))
	return m
end

-- After the map's quest log built its rows (and whenever the followed quest changes): the bar on the followed quest's
-- row only. The rows are pooled, so a bar left on a row now showing another quest is hidden.
local function PlaceLogMark()
	for _, m in pairs(marks) do
		m:Hide()
	end
	local quest = Quest()
	local pool = quest and QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then
		return
	end
	for row in pool:EnumerateActive() do
		if row.questID == quest then
			Mark(row):Show()
			return
		end
	end
end

-- On and off ---------------------------------------------------------------------------------------------------------

local function Refresh()
	if holder and holder:IsVisible() then
		Place()
	end
	PlaceLogMark()
end

ns.ActiveQuest_OnChange(function()
	if active then
		Refresh()
	end
end)

function ns.QuestListMap_Start()
	active = true
	if not WorldMapFrame then
		return
	end
	if not holder then
		Build(WorldMapFrame:GetCanvas())
	end
	holder:Show()
	placedMap = nil -- placed again on the next frame the map shows
	if not hooked and QuestLogQuests_Update then
		hooked = true
		-- Can't be undone: does nothing while the Quest list is off (Quest() is nil then, and every bar hides).
		hooksecurefunc("QuestLogQuests_Update", PlaceLogMark)
	end
	PlaceLogMark()
end

function ns.QuestListMap_Stop()
	active = false
	if holder then
		area:DrawNone()
		ringFrame.breathe:Stop()
		ringFrame:Hide()
		holder:Hide()
	end
	PlaceLogMark()
end

-- The quest log changed (objectives done, a quest finished): the followed quest keeps its ID, so the area and the ring
-- are drawn again on the map's next frame (or when it next shows), not at every log update.
function ns.QuestListMap_QuestsChanged()
	placedMap = nil
end

-- A setting changed.
function ns.QuestListMap_Refresh()
	if active then
		placedMap = nil
		Refresh()
	end
end
