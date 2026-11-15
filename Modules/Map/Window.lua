local addonName, ns = ...

-- Tomte map: the window. A movable, resizable Tomte window (Esc closes it) with the view: a scroll frame holding the
-- canvas (scaled by fit * zoom, scrolled so its point u, v is at the view's centre) and the pin layer over it. Wheel zooms toward the
-- cursor, drag pans, right-click zooms out, Ctrl-click places a map pin. Nothing here touches Blizzard's world map.
-- Maths in Data.lua, art in Art.lua, pins in Pins.lua, registered in Map.lua.

local TITLE_H = 30
local PAD = 8
local MIN_W, MIN_H = 420, 320
local MIN_ZOOM, MAX_ZOOM = 1, 64 -- 1: the whole world fits; 64: closer than a zone fills the window
local CONTINENT_ZOOM = 1.6 -- the continents' own art from here (the world map's picture below)
local ZONE_ZOOM = 3.5 -- zone art from here: a typical zone is a couple of hundred pixels wide by then
local FADE_BAND = 1.3 -- each level fades in from its start / this to its start * this (Data.lua, Map_LevelAlphas)
local WHEEL_STEP = 1.25 -- zoom per wheel notch
local EASE = 14 -- zoom easing speed (per second, in log space)
local MARGIN = 0.35 -- art is shown this much beyond the view, so it's there before it scrolls in
local CLICK_MOVE = 4 -- pixels: a press that moves less than this is a click, not a drag
local TICK = 0.1 -- seconds between moving you and your party
local FIND_SHARE = 0.85 -- finding you zooms until your zone fills this much of the view

local UI = ns.UI

local db
local frame, view, canvas, layer, zoneText, coordText
local W, H, fit = 1, 1, 1
local state = { u = 0.5, v = 0.5, zoom = 1 }
local target -- { zoom, sx, sy }: an easing zoom toward a point
local drag -- { x, y, moved }
local dirty = true
local drawnScale, areaDirty
local ticker
local lastCursorX, lastCursorY

-- Geometry --------------------------------------------------------------------------------------------------------------

local function ViewSize()
	return view:GetWidth(), view:GetHeight()
end

-- Cursor offset from the view's centre in view pixels (x right, y down).
local function Cursor()
	local x, y = GetCursorPosition()
	local scale = view:GetEffectiveScale()
	local cx, cy = view:GetCenter()
	return x / scale - cx, cy - y / scale
end

local function ToView(cx, cy)
	local x, y = ns.Map_ToView(state, cx, cy, fit, W, H)
	local vw, vh = ViewSize()
	if math.abs(x) > vw / 2 + 40 or math.abs(y) > vh / 2 + 40 then
		return nil
	end
	return x, y
end

local function Level()
	return ns.Map_Level(state.zoom, CONTINENT_ZOOM, ZONE_ZOOM)
end

local function Apply()
	dirty = false
	local vw, vh = ViewSize()
	if vw <= 0 or vh <= 0 then
		return
	end
	fit = ns.Map_Fit(vw, vh, W, H)
	ns.Map_Clamp(state, MIN_ZOOM, MAX_ZOOM, vw, vh, fit, W, H)
	local scale = fit * state.zoom
	canvas:SetScale(scale)
	-- Panned by scrolling, as the game's map (MapCanvasScrollControllerMixin:SetNormalizedHorizontalScroll): the quest
	-- area keeps its place while scrolled, but not when its frame is moved.
	view:SetHorizontalScroll(state.u * W - vw / 2 / scale)
	view:SetVerticalScroll(state.v * H - vh / 2 / scale)
	if scale ~= drawnScale then
		-- The game fixes a quest area's shape where its frame is when drawn, so a zoom draws it again
		-- (as QuestBlobPinMixin:OnCanvasScaleChanged), in this same frame (ns.MapPins_RedrawArea).
		drawnScale, areaDirty = scale, true
	end
	local viewBox = ns.Map_ViewBox(state, vw, vh, fit, W, H, MARGIN)
	ns.MapArt_Update(viewBox, ns.Map_LevelAlphas(state.zoom, CONTINENT_ZOOM, ZONE_ZOOM, FADE_BAND))
	ns.MapMini_Update(viewBox, state.zoom)
	ns.MapPins_Layout(ToView, Level())
	if areaDirty then
		areaDirty = false
		ns.MapPins_RedrawArea()
	end
end

-- Pins.lua placed the quest area (during Apply): it's drawn when Apply ends.
function ns.MapWindow_AreaDirty()
	areaDirty = true
end

function ns.MapWindow_Relayout()
	if frame and frame:IsShown() then
		dirty = true
	end
end

-- The zone (or continent) under view offset sx, sy: info (C_Map.GetMapInfo shape) and the spot x, y on it.
local function MapAt(sx, sy)
	local cx, cy = ns.Map_At(state, sx, sy, fit, W, H)
	for _, c in ipairs(ns.MapArt_Continents()) do
		local x, y = ns.Map_FromBox(c.box, cx, cy)
		if x then
			local info = C_Map.GetMapInfoAtPosition(c.mapID, x, y)
			local box = info and ns.MapArt_Box(info.mapID)
			local zx, zy
			if box then
				zx, zy = ns.Map_FromBox(box, cx, cy)
			end
			if zx then
				return info, zx, zy
			end
			return C_Map.GetMapInfo(c.mapID), x, y
		end
	end
end

-- Moving the view -------------------------------------------------------------------------------------------------------

local function ZoomTo(zoom, sx, sy)
	target = { zoom = math.min(math.max(zoom, MIN_ZOOM), MAX_ZOOM), sx = sx or 0, sy = sy or 0 }
end

-- Centres on you, zoomed in until your zone fills most of the view (never out). False without a position.
function ns.MapWindow_FindMe()
	if not frame then
		return false
	end
	for _, c in ipairs(ns.MapArt_Continents()) do
		local pos = C_Map.GetPlayerMapPosition(c.mapID, "player")
		if pos then
			local x, y = pos:GetXY()
			if ns.Readable(x) and ns.Readable(y) and not (x == 0 and y == 0) then
				local cx, cy = ns.Map_InBox(c.box, x, y)
				state.u, state.v = cx / W, cy / H
				local zoneID = C_Map.GetBestMapForUnit("player")
				local box = zoneID and ns.Readable(zoneID) and ns.MapArt_Box(zoneID)
				local vw, vh = ViewSize()
				if box and vw > 0 then
					state.zoom = math.max(state.zoom, ns.Map_ZoomFor(box, vw, vh, ns.Map_Fit(vw, vh, W, H), FIND_SHARE))
				end
				target = nil
				dirty = true
				return true
			end
		end
	end
	return false
end

local function OnUpdate(_, elapsed)
	if drag then
		local sx, sy = Cursor()
		local dx, dy = sx - drag.x, sy - drag.y
		if drag.moved or math.abs(dx) + math.abs(dy) >= CLICK_MOVE then
			drag.moved = true
			ns.Map_Pan(state, dx, dy, fit, W, H)
			drag.x, drag.y = sx, sy
			target = nil
			dirty = true
		end
	end
	if target then
		local from, to = math.log(state.zoom), math.log(target.zoom)
		local step = from + (to - from) * math.min(1, elapsed * EASE)
		if math.abs(to - step) < 0.002 then
			step = to
		end
		ns.Map_ZoomAbout(state, target.sx, target.sy, math.exp(step), fit, W, H)
		if step == to then
			target = nil
		end
		dirty = true
	end
	if dirty then
		Apply()
	end
	-- The zone under the cursor, when it moved.
	if view:IsMouseOver() then
		local x, y = GetCursorPosition()
		if x ~= lastCursorX or y ~= lastCursorY then
			lastCursorX, lastCursorY = x, y
			local info, mx, my = MapAt(Cursor())
			if info then
				zoneText:SetText(info.name or "")
				coordText:SetFormattedText("%.1f, %.1f", mx * 100, my * 100)
			else
				zoneText:SetText("")
				coordText:SetText("")
			end
		end
	end
end

-- Mouse -----------------------------------------------------------------------------------------------------------------

local function OnMouseDown(_, button)
	if button == "LeftButton" then
		local sx, sy = Cursor()
		drag = { x = sx, y = sy, moved = false }
	end
end

local function OnMouseUp(_, button)
	local wasDrag = drag and drag.moved
	drag = nil
	if wasDrag then
		return
	end
	local sx, sy = Cursor()
	if button == "RightButton" then
		ZoomTo(state.zoom / (WHEEL_STEP * WHEEL_STEP), sx, sy)
	elseif button == "LeftButton" and IsControlKeyDown() then
		local info, x, y = MapAt(sx, sy)
		if info and ns.Way_SetPoint then
			if ns.Way_SetPoint(info.mapID, x, y, info.name) == nil then
				ns.Print("can't place a map pin there.")
			end
		end
	end
end

local function OnMouseWheel(_, delta)
	local sx, sy = Cursor()
	local base = target and target.zoom or state.zoom
	ZoomTo(base * WHEEL_STEP ^ delta, sx, sy)
end

-- Building ----------------------------------------------------------------------------------------------------------------

local function SaveFrame()
	local point, _, relPoint, x, y = frame:GetPoint()
	db.window = { w = frame:GetWidth(), h = frame:GetHeight(), point = point, relPoint = relPoint, x = x, y = y }
end

local function PlaceFrame()
	local s = db.window
	frame:ClearAllPoints()
	if s and s.point then
		frame:SetSize(math.max(s.w or 0, MIN_W), math.max(s.h or 0, MIN_H))
		frame:SetPoint(s.point, UIParent, s.relPoint or s.point, s.x or 0, s.y or 0)
	else
		frame:SetSize(math.floor(UIParent:GetWidth() * 0.6), math.floor(UIParent:GetHeight() * 0.65))
		frame:SetPoint("CENTER")
	end
end

local function Build()
	local worldID = ns.Map_WorldID()
	local layers = worldID and C_Map.GetMapArtLayers(worldID)
	if not (layers and layers[1]) then
		return false
	end
	W, H = layers[1].layerWidth, layers[1].layerHeight

	frame = UI.Dialog("TomteMapFrame", MIN_W, MIN_H) -- Escape closes it
	frame:SetFrameStrata("HIGH")
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_W, MIN_H)
	frame:HookScript("OnDragStop", SaveFrame)
	UI.ResizeGrip(frame, function()
		SaveFrame()
		dirty = true
	end)

	local title = UI.Text(frame, 14, "heading", "title")
	title:SetPoint("TOPLEFT", PAD + 4, -9)
	title:SetText(WORLD_MAP or "Map")
	zoneText = UI.Text(frame, 13, "text")
	zoneText:SetPoint("LEFT", title, "RIGHT", 16, 0)
	coordText = UI.Text(frame, 12, "textMuted", "number")
	coordText:SetPoint("LEFT", zoneText, "RIGHT", 10, 0)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	local find = UI.Button(frame, 70, "Find me")
	find:SetPoint("RIGHT", close, "LEFT", -6, 0)
	find:SetScript("OnClick", function()
		if not ns.MapWindow_FindMe() then
			ns.Print("the map can't show where you are here.")
		end
	end)

	-- A scroll frame with the canvas as its scroll child, as the game's map (see Apply).
	view = CreateFrame("ScrollFrame", nil, frame)
	view:SetPoint("TOPLEFT", PAD, -TITLE_H)
	view:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	local sea = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
	sea:SetAllPoints(view)
	sea:SetColorTexture(UI.Color("bgBottom"))

	canvas = CreateFrame("Frame", nil, view)
	canvas:SetSize(W, H)
	canvas:EnableMouse(false)
	view:SetScrollChild(canvas)

	-- The pins: not scaled, clipped to the view, above every art frame (Art.lua stacks zones a few levels up).
	layer = CreateFrame("Frame", nil, frame)
	layer:SetAllPoints(view)
	layer:SetClipsChildren(true)
	layer:SetFrameLevel(view:GetFrameLevel() + 40)

	ns.MapArt_Init(canvas, W, H, worldID)
	ns.MapMini_Init(canvas)
	ns.MapPins_Init(layer, db)

	view:SetScript("OnMouseDown", OnMouseDown)
	view:SetScript("OnMouseUp", OnMouseUp)
	view:SetScript("OnMouseWheel", OnMouseWheel)
	view:SetScript("OnSizeChanged", function()
		dirty = true
	end)
	view:SetScript("OnUpdate", ns.Perf_Wrap(OnUpdate, "OnUpdate"))
	view:SetScript("OnLeave", function()
		lastCursorX = nil
	end)

	frame:HookScript("OnShow", function()
		ns.Map_Shown(true)
		ns.MapPins_Read()
		dirty = true
		ticker = C_Timer.NewTicker(TICK, function()
			if not dirty then
				ns.MapPins_Tick(ToView)
			end
		end)
	end)
	frame:HookScript("OnHide", function()
		drag, target = nil, nil
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		ns.Map_Shown(false) -- art loading pauses by itself: its loader is on the hidden canvas
	end)
	PlaceFrame()
	return true
end

-- From Map.lua ------------------------------------------------------------------------------------------------------------

function ns.MapWindow_Init(moduleDB)
	db = moduleDB
end

function ns.MapWindow_Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
		return
	end
	if not frame and not Build() then
		ns.Print("the world map's art isn't available on this client.")
		return
	end
	frame:Show()
	if not ns.MapWindow_FindMe() then
		dirty = true
	end
end

function ns.MapWindow_Hide()
	if frame then
		frame:Hide()
	end
end

function ns.MapWindow_ResetFrame()
	db.window = nil
	if frame then
		PlaceFrame()
		dirty = true
	end
end

-- For /tomte map why.
function ns.MapWindow_State()
	return state, Level(), W, H, fit
end
