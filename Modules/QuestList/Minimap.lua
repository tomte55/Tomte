local addonName, ns = ...

-- Quest list: the active quest (ns.ActiveQuest_ID) on the minimap: a ring on its spot (on the edge while it's out of
-- view, a "?" once it's ready to hand in) and its area, drawn by our own QuestPOIFrames since the game only draws the
-- area of its own active quest (and making ours that one taints, see ns.ActiveQuest_Follow). Optionally the other
-- quests' spots too. Plain frames on the minimap, no mouse. Geometry in Core/MinimapData.lua. Started from QuestList.lua.

local RING = ns.Theme.MEDIA .. "Gather\\Ring" -- a thin white ring, tinted (also Gather's pins)
local TURN_IN = "Interface\\GossipFrame\\ActiveQuestIcon" -- the gold "?"
local ARROW = "Interface\\Minimap\\MinimapArrow" -- points up at rotation 0; tinted, it points at a quest out of view
local PIN = 18 -- pixels: the active quest's ring
local OTHER = 10 -- pixels: other quests' rings
local OTHER_ALPHA = 0.7
local STRIP_PX = 4 -- pixels per clip strip standing in for a round minimap (ns.Mini_Strips); 12 strips looked square
local AREA_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local AREA_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"
local AREA_FILL_ALPHA, AREA_BORDER_ALPHA = 128, 192 -- of 255, as the map's own (QuestBlobPinMixin:OnLoad)
local PICK = 1 -- seconds between reading the quests' spots
local MAP_ZONE = 3 -- Enum.UIMapType.Zone: quest areas are drawn on zone maps

local UI = ns.UI

local active = false
local holder, activePin
local others, othersUsed = {}, 0
local strips = {} -- clip frames, each { frame, blob }
local stripsFor -- "round:half" or "square:half": the shape the strips were laid out for
local points = {} -- [questID] = world point { x, y, continent } (Leveling's readers)
local axes, axesMap
local zoneMap, zoneW, zoneH -- the player's zone map and its size in yards
local blobQuest, blobMap, blobW -- what the area frames last drew, and how wide
local pickAt = 0
local round, rotate = true, false

local function DB()
	return ns.QuestList_DB()
end

local function Facing()
	local f = GetPlayerFacing()
	return f and ns.Readable(f) and f or nil
end

local function Quest()
	local id = ns.ActiveQuest_ID()
	return id and not ns.IsSecret(id) and id or nil
end

local function Ready(questID)
	return C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID) or C_QuestLog.IsComplete(questID)
end

-- Frames ------------------------------------------------------------------------------------------------------------

local function NewPin(size)
	local pin = CreateFrame("Frame", nil, holder)
	pin:SetSize(size, size)
	pin:EnableMouse(false)
	pin.ring = pin:CreateTexture(nil, "ARTWORK")
	pin.ring:SetAllPoints()
	pin.mark = pin:CreateTexture(nil, "OVERLAY")
	pin.mark:SetPoint("CENTER")
	pin.mark:SetSize(size * 0.9, size * 0.9)
	pin.mark:SetTexture(TURN_IN)
	pin.arrow = pin:CreateTexture(nil, "OVERLAY")
	pin.arrow:SetPoint("CENTER")
	pin.arrow:SetSize(size * 2.4, size * 2.4) -- the arrow only fills the middle of its texture
	pin.arrow:SetTexture(ARROW)
	pin.arrow:Hide()
	return pin
end

-- A ring, or the gold "?" for a quest ready to hand in.
local function Dress(pin, ready, role)
	pin.ring:SetTexture(RING)
	pin.ring:SetVertexColor(UI.Color(role))
	pin.ring:SetShown(not ready)
	pin.mark:SetShown(ready)
end

-- A strip is a scroll frame (it clips) whose scroll child holds the area: as you walk the area is scrolled, never moved,
-- the way the game's map pans its own quest area (a moved or scaled area frame drew in the wrong place, measured
-- 2026-11-15).
local function NewStrip()
	local clip = CreateFrame("ScrollFrame", nil, holder)
	clip:EnableMouse(false)
	local inner = CreateFrame("Frame", nil, clip)
	inner:SetSize(1, 1)
	clip:SetScrollChild(inner)
	local blob = CreateFrame("QuestPOIFrame", nil, inner)
	blob:SetAllPoints(inner)
	blob:EnableMouse(false)
	blob:SetFillTexture(AREA_FILL)
	blob:SetBorderTexture(AREA_BORDER)
	blob:SetFillAlpha(AREA_FILL_ALPHA)
	blob:SetBorderAlpha(AREA_BORDER_ALPHA)
	blob:SetBorderScalar(1.0)
	return { frame = clip, inner = inner, blob = blob }
end

-- The clip strips for the minimap's shape and size: one square, or bands STRIP_PX high down the circle.
local function LayStrips(half)
	local key = (round and "round:" or "square:") .. half
	if key == stripsFor then
		return
	end
	stripsFor = key
	local shape = round and ns.Mini_Strips(half, math.max(12, math.floor(2 * half / STRIP_PX)))
		or { { top = half, height = 2 * half, halfWidth = half } }
	for i, s in ipairs(shape) do
		local strip = strips[i] or NewStrip()
		strips[i] = strip
		strip.frame:ClearAllPoints()
		strip.frame:SetPoint("TOPLEFT", holder, "CENTER", -s.halfWidth, s.top)
		strip.frame:SetSize(math.max(s.halfWidth * 2, 0.01), s.height)
		strip.left, strip.top = -s.halfWidth, s.top
		strip.frame:Show()
	end
	for i = #shape + 1, #strips do
		strips[i].frame:Hide()
	end
	blobQuest = nil -- drawn again into the strips now shown
end

local function HideArea()
	for _, strip in ipairs(strips) do
		strip.blob:Hide()
	end
end

-- The area of questID on the player's zone map, the map's own size in yards scaled to minimap pixels (ppy) and placed
-- so the player's spot (px, py on the zone map) sits in the middle.
local function DrawArea(questID, px, py, ppy)
	if not (questID and zoneMap and px) or rotate or not DB().minimapArea then
		HideArea()
		return
	end
	-- Sized in pixels, never scaled. A new size (the minimap zoomed, another zone or quest) is drawn at once.
	local w, h = zoneW * ppy, zoneH * ppy
	local redraw = questID ~= blobQuest or zoneMap ~= blobMap or w ~= blobW
	blobQuest, blobMap, blobW = questID, zoneMap, w
	-- The area's top left sits at (-px * w, py * h) from the minimap's centre; each strip scrolls to show its part.
	for _, strip in ipairs(strips) do
		if strip.frame:IsShown() then
			if redraw then
				strip.inner:SetSize(w, h)
				strip.blob:SetMapID(zoneMap)
			end
			strip.frame:SetHorizontalScroll(px * w + strip.left)
			strip.frame:SetVerticalScroll(py * h - strip.top)
			strip.blob:Show()
			if redraw then
				-- The game fixes an area's shape where its frame is when drawn. Asking for the frame's edge first makes
				-- the game place it now, so it's drawn for its new size in this frame (drawn a frame later, it flashed
				-- on every zoom; drawn before the frame was placed, it landed in the old spot).
				strip.blob:GetLeft()
				strip.blob:DrawNone()
				strip.blob:DrawBlob(questID, true)
			end
		end
	end
end

-- Reading -----------------------------------------------------------------------------------------------------------

local function Pick()
	pickAt = GetTime() + PICK
	round = ns.MinimapShape() == "ROUND"
	rotate = C_CVar.GetCVarBool("rotateMinimap")
	local _, map = ns.QuestListRead_Zone()
	if map ~= zoneMap then
		zoneMap, zoneW, zoneH = map, nil, nil
		local info = map and C_Map.GetMapInfo(map)
		if info and info.mapType == MAP_ZONE then
			zoneW, zoneH = C_Map.GetMapWorldSize(map)
		end
		if not (zoneW and zoneW > 0) then
			zoneMap = nil
		end
	end
	local best = C_Map.GetBestMapForUnit("player")
	best = best and ns.Readable(best) and best or nil
	points = best and ns.LevelingRead_QuestPoints(best) or {}
	local quest = Quest()
	if quest and not points[quest] then
		points[quest] = ns.LevelingRead_HandPoint(quest) or nil
	end
	if best ~= axesMap then
		-- A cave or building map may have no world position: the zone's axes then.
		axesMap, axes = best, best and ns.QuestListRead_Axes(best) or zoneMap and ns.QuestListRead_Axes(zoneMap) or nil
	end
end

-- Drawing -----------------------------------------------------------------------------------------------------------

local function HideAll()
	if activePin then
		activePin:Hide()
	end
	for i = 1, othersUsed do
		others[i]:Hide()
	end
	othersUsed = 0
	HideArea()
end

local function Update()
	if GetTime() >= pickAt then
		Pick()
	end
	local radius = C_Minimap.GetViewRadius()
	local you = ns.LevelingRead_You()
	if not (you and axes and radius and radius > 0) then
		HideAll()
		return
	end
	local half = Minimap:GetWidth() / 2
	local ppy = half / radius -- pixels per yard
	local facing = rotate and Facing() or nil
	local quest = Quest()
	local db = DB()

	-- The area, on the player's zone map.
	LayStrips(half)
	local pos = zoneMap and C_Map.GetPlayerMapPosition(zoneMap, "player")
	local px, py
	if pos then
		px, py = pos:GetXY()
		if not (ns.Readable(px) and ns.Readable(py)) then
			px, py = nil, nil
		end
	end
	DrawArea(quest, px, py, ppy)

	-- The pins.
	local function Spot(point)
		if point.continent ~= you.continent then
			return nil
		end
		local e, n = ns.Mini_WorldOffset(point.x - you.x, point.y - you.y, axes)
		e, n = ns.Mini_Turn(e, n, facing)
		return e * ppy, n * ppy
	end
	local used = 0
	if db.minimapOthers then
		local edge = half - OTHER / 2
		for id, point in pairs(points) do
			if id ~= quest then
				local x, y = Spot(point)
				if x and ns.Mini_Inside(x, y, edge, round) then
					used = used + 1
					local pin = others[used] or NewPin(OTHER)
					others[used] = pin
					Dress(pin, Ready(id), "frame")
					pin:SetAlpha(OTHER_ALPHA)
					pin:SetPoint("CENTER", holder, "CENTER", x, y)
					pin:Show()
				end
			end
		end
	end
	for i = used + 1, othersUsed do
		others[i]:Hide()
	end
	othersUsed = used

	local point = quest and points[quest]
	local x, y
	if point then
		x, y = Spot(point)
	end
	if not x then
		if activePin then
			activePin:Hide()
		end
		return
	end
	activePin = activePin or NewPin(PIN)
	activePin:SetFrameLevel(holder:GetFrameLevel() + 3)
	local inner = half - PIN / 2
	if ns.Mini_Inside(x, y, inner, round) then
		Dress(activePin, Ready(quest), "accent")
		activePin.arrow:Hide()
	else
		-- Out of view: an arrow on the edge pointing at it.
		local angle = math.atan2(-x, y) -- counterclockwise from up, as SetRotation turns
		x, y = ns.Mini_Clamp(x, y, inner, round)
		activePin.ring:Hide()
		activePin.mark:Hide()
		activePin.arrow:SetRotation(angle)
		activePin.arrow:SetVertexColor(UI.Color("accent"))
		activePin.arrow:Show()
	end
	activePin:SetPoint("CENTER", holder, "CENTER", x, y)
	activePin:Show()
end

-- Every frame: the minimap's terrain moves every frame, and markers moved less often visibly lagged it (jitter,
-- measured 2026-11-15). Update reads one position and moves a handful of frames.
local function OnUpdate()
	Update()
end

-- On and off --------------------------------------------------------------------------------------------------------

local function Apply()
	local on = active and Minimap and DB().minimapMark
	if not on then
		if holder then
			HideAll()
			holder:Hide()
		end
		return
	end
	if not holder then
		holder = CreateFrame("Frame", nil, Minimap)
		holder:SetAllPoints(Minimap)
		holder:EnableMouse(false)
		holder:SetScript("OnUpdate", ns.Perf_Wrap(OnUpdate, "OnUpdate"))
	end
	holder:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	pickAt, blobQuest, stripsFor = 0, nil, nil
	holder:Show()
end

ns.ActiveQuest_OnChange(function()
	if active then
		pickAt, blobQuest = 0, nil
	end
end)

-- The quest log changed: spots are read again and the area drawn again (a finished quest's area changes).
function ns.QuestListMini_QuestsChanged()
	pickAt, blobQuest = 0, nil
end

function ns.QuestListMini_Start()
	active = true
	Apply()
end

function ns.QuestListMini_Stop()
	active = false
	Apply()
end

-- A setting changed.
function ns.QuestListMini_Refresh()
	Apply()
end
