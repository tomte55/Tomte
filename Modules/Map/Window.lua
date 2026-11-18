local addonName, ns = ...

-- Tomte map: the window. A movable, resizable Tomte window (Esc closes it) with the view: a scroll frame holding the
-- canvas (scaled by fit * zoom, scrolled so its point u, v is at the view's centre) and the pin layer over it. Wheel zooms toward the
-- cursor, drag pans, right-click zooms out, Ctrl-click places a map pin. The side panel (Side.lua) sits right of the
-- view. Nothing here touches Blizzard's world map. Maths in Data.lua, art in Art.lua, pins in Pins.lua, registered in
-- Map.lua.

local TITLE_H = 36
-- The Forever theme: the frame other windows have (the metal strip, the round badge, the red close button), the
-- coordinates and buttons on a row under the strip, as the Character window's level line.
local FOREVER_STRIP_H = 21 -- the metal title strip, where the rock starts (Panel/ForeverArt.lua)
local FOREVER_ROW_H = 30 -- the row under it
local FOREVER_BADGE_ROOM = 64 -- the row's text starts past the round badge
local FOREVER_BAR_LEVEL = 14 -- the title's frame level above the window: over the frame's metal (ForeverArt.lua)
local BADGE_ICON = "Interface\\QuestFrame\\UI-QuestLog-BookIcon" -- the game's map (WorldMapFrame's portrait)
-- The town markers' and Find me buttons on the map's top-right corner: the minimap's tracking button (MiniMapTracking,
-- Camelot), its art at the same offsets.
local TRACK_SIZE = 32
local TRACK_GAP = 0 -- pixels between the two (their rings' art has room round it)
local TRACK_ICON = "Interface\\Minimap\\Tracking\\None"
local FIND_ICON = "Interface\\Minimap\\MinimapArrow" -- you, as the map and minimap draw you
local FIND_ARROW = 26 -- pixels: the arrow's art has room round it, so it's drawn larger than an icon
local FIND_TURN = -math.pi / 4 -- pointing up and to the right
-- Where the arrow's middle goes: the ring's centre, nudged up and right, as the art's arrow sits low and left of its
-- texture's middle once turned (seen in game).
local FIND_CENTER_X, FIND_CENTER_Y = 17, -15
local TRACK_BG = "Interface\\Minimap\\UI-Minimap-Background"
local TRACK_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local TRACK_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local TRACK_INSET = 2 -- pixels in from the map's corner
local TRACKING_ART = "Interface\\Minimap\\Tracking\\"
local DUNGEON_ICON = "Interface\\Minimap\\Dungeon"
-- The quest log button on the map's bottom-right corner: the game map's side panel toggle (WorldMapSidePanelToggle).
local LOG_SIZE = 32
local LOG_SHOW, LOG_SHOW_DOWN = "QuestCollapse-Show-Up", "QuestCollapse-Show-Down"
local LOG_HIDE, LOG_HIDE_DOWN = "QuestCollapse-Hide-Up", "QuestCollapse-Hide-Down"
local LOG_SHADOW = "MapCornerShadow-Right"
local LOG_HIGHLIGHT = "Interface\\Buttons\\UI-Common-MouseHilight"
local PAD = 12
local MIN_W, MIN_H = 640, 360
local SIDE_GAP = 10 -- pixels between the view and the side panel (each sits in its own well)
local WELL_OUT = 4 -- pixels a well reaches past what it frames
local SIDE_TIME = 0.2 -- seconds the side panel takes to open or close
local MIN_ZOOM, MAX_ZOOM = 1, 64 -- 1: the whole world fits; 64: closer than a zone fills the window
local FADE_BAND = 1.3 -- each level fades in from its start / this to its start * this (Data.lua, Map_LevelAlphas)
local WHEEL_STEP = 1.25 -- zoom per wheel notch
local EASE = 14 -- zoom easing speed (per second, in log space)
local MARGIN = 0.35 -- art is shown this much beyond the view, so it's there before it scrolls in
local CLICK_MOVE = 4 -- pixels: a press that moves less than this is a click, not a drag
local TICK = 0.1 -- seconds between moving you and your party
local FIND_SHARE = 0.85 -- finding you zooms until your zone fills this much of the view

local UI = ns.UI

local db
local frame, view, canvas, layer, zoneText, coordText, side, sideClip, logButton
local sideWidth = 0 -- the side panel's width (Side.lua)
local sideOpen = 0 -- 0..1: how far it's open (it slides)
local sideWanted = false -- shown now: the saved choice (db.sideShown), or opened with the quest log key for once
local W, H, fit = 1, 1, 1
local titleH = TITLE_H -- the view's top: TITLE_H, or the Forever frame's strip and row
local state = { u = 0.5, v = 0.5, zoom = 1 }
local target -- { zoom, sx, sy }: an easing zoom toward a point
local glide -- { flight (Data.lua, Map_Flight), from = { u, v, zoom }, t }: the view flying somewhere
local aim -- { cx, cy, zoom, box }: a glide asked for before the view had its size (the window's first show)
local pinCursor = false -- the map pin cursor is up (Ctrl held over the view)
local drag -- { x, y, moved }
local dirty = true
local drawnScale, areaDirty
local viewBoxKept = {} -- Apply's view box, filled again each layout (every frame the view moves: no garbage)
local ticker
local lastCursorX, lastCursorY
local pingWhenLanded = false -- Find me: rings pulse out from you once the flight there ends

-- Geometry ------------------------------------------------------------------------------------------------------------

local function ViewSize()
	return view:GetWidth(), view:GetHeight()
end

-- The width the side panel takes from the view now.
local function SideTaken()
	return sideOpen * (sideWidth + SIDE_GAP)
end

-- The canvas's base scale, from the view as if the side panel were closed: opening it doesn't zoom the map.
local function Fit(vw, vh)
	return ns.Map_Fit(vw + SideTaken(), vh, W, H)
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

-- Where the continents' and the zones' art starts: the "Detail" settings (Map.lua; defaults 1.2 and 5, where a
-- typical zone is a couple of hundred pixels wide).
local function Level()
	return ns.Map_Level(state.zoom, db.continentZoom, db.zoneZoom)
end

local function Apply()
	dirty = false
	local vw, vh = ViewSize()
	if vw <= 0 or vh <= 0 then
		return
	end
	fit = Fit(vw, vh)
	if aim then
		local a = aim
		aim = nil
		ns.MapWindow_Aim(a.cx, a.cy, a.box, a.zoom)
	end
	ns.Map_Clamp(state, MIN_ZOOM, MAX_ZOOM, vw, vh, fit, W, H)
	local scale = fit * state.zoom
	canvas:SetScale(scale)
	-- Panned by scrolling, as the game's map (MapCanvasScrollControllerMixin:SetNormalizedHorizontalScroll): the quest
	-- area keeps its place while scrolled, but not when its frame is moved.
	view:SetHorizontalScroll(state.u * W - vw / 2 / scale)
	view:SetVerticalScroll(state.v * H - vh / 2 / scale)
	if scale ~= drawnScale then
		-- The game fixes a quest area's shape where its frame is when drawn, so a zoom draws it again
		-- (as QuestBlobPinMixin:OnCanvasScaleChanged), in this same frame (ns.MapArea_Redraw).
		drawnScale, areaDirty = scale, true
	end
	local viewBox = ns.Map_ViewBox(state, vw, vh, fit, W, H, MARGIN, viewBoxKept)
	if ns.MapSide_WantsMap() then
		ns.MapSide_Viewing(ns.MapWindow_CenterMap())
	end
	ns.MapArt_Update(viewBox, ns.Map_LevelAlphas(state.zoom, db.continentZoom, db.zoneZoom, FADE_BAND))
	ns.MapMini_Update(viewBox, state.zoom)
	ns.MapPins_Layout(ToView, Level(), state.zoom)
	if areaDirty then
		areaDirty = false
		ns.MapArea_Redraw()
	end
end

-- Area.lua placed the quest area (during Apply): it's drawn when Apply ends.
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

-- Ctrl-click: a map pin there, as on the game's map. The map under the cursor may not take one (a sub-zone, a city's
-- inside): then the maps above it, up to the continent. Ctrl-click on the pin takes it away (Pins.lua).
local function PinAt(sx, sy)
	local info = MapAt(sx, sy)
	local cx, cy = ns.Map_At(state, sx, sy, fit, W, H)
	local mapID, seen = info and info.mapID, {}
	while mapID and not seen[mapID] do
		seen[mapID] = true
		local box = ns.MapArt_Box(mapID)
		local x, y
		if box then
			x, y = ns.Map_FromBox(box, cx, cy)
		end
		if x and C_Map.CanSetUserWaypointOnMap(mapID) then
			-- Through Waypoints when it's there: it names the pin after the place.
			if ns.Way_SetPoint then
				ns.Way_SetPoint(mapID, x, y, info.name)
			else
				ns.TrackPin(mapID, x, y)
			end
			return
		end
		local map = C_Map.GetMapInfo(mapID)
		mapID = map and map.parentMapID
	end
	ns.Print("can't place a map pin there.")
end

-- Moving the view -----------------------------------------------------------------------------------------------------

local function ZoomTo(zoom, sx, sy)
	glide, pingWhenLanded = nil, false
	target = { zoom = math.min(math.max(zoom, MIN_ZOOM), MAX_ZOOM), sx = sx or 0, sy = sy or 0 }
end

-- The map at the view's centre: the world at world zoom, else the continent there, or at zone zoom the zone there.
function ns.MapWindow_CenterMap()
	if not frame then
		return nil
	end
	local level = Level()
	if level == "world" then
		return ns.MapArt_WorldID()
	end
	local cx, cy = state.u * W, state.v * H
	for _, c in ipairs(ns.MapArt_Continents()) do
		local x, y = ns.Map_FromBox(c.box, cx, cy)
		if x then
			if level == "zone" then
				local info = C_Map.GetMapInfoAtPosition(c.mapID, x, y)
				return info and info.mapID or c.mapID
			end
			return c.mapID
		end
	end
	return ns.MapArt_WorldID()
end

-- The view flies to canvas point cx, cy (Data.lua, Map_Flight: out only as far as needed to see both places, then
-- in), ending zoomed in until box (a map's canvas box) fills most of the view, or at zoom when given. Before the view
-- has its size (the window only just shown) it waits for the next layout.
function ns.MapWindow_Aim(cx, cy, box, zoom)
	local vw, vh = ViewSize()
	target, pingWhenLanded = nil, false -- a new flight: Find me sets it again after this
	if not (vw > 0 and vh > 0) then
		aim, glide = { cx = cx, cy = cy, box = box, zoom = zoom }, nil
		dirty = true
		return
	end
	local fitNow = Fit(vw, vh)
	if not zoom then
		zoom = box and ns.Map_ZoomFor(box, vw, vh, fitNow, FIND_SHARE) or state.zoom
	end
	-- Ends where Apply would let the view be (a spot near the world's edge).
	local to = ns.Map_Clamp({ u = cx / W, v = cy / H, zoom = zoom }, MIN_ZOOM, MAX_ZOOM, vw, vh, fitNow, W, H)
	glide = { flight = ns.Map_Flight(state, to, vw, vh, fitNow, W, H, MIN_ZOOM), t = 0,
		from = { u = state.u, v = state.v, zoom = state.zoom } }
	dirty = true
end

-- Where finding something ends: the same zoom every time, a little past where zone maps come in (zones differ in size,
-- so fitting the zone to the view ended nearer for some quests than for others).
local FIND_ZOOM_SHARE = 1.6
local function FindZoom()
	return db.zoneZoom * FIND_ZOOM_SHARE
end

-- The side panel picked a quest: the view glides to its spot, zoomed in to the find zoom (never out). False when it
-- has no spot on the map.
function ns.MapWindow_GoToQuest(questID)
	local mapID, x, y = ns.MapPins_QuestSpot(questID)
	local cx, cy
	if mapID then
		cx, cy = ns.MapArt_ToCanvas(mapID, x, y)
	end
	if not (frame and cx) then
		return false
	end
	ns.MapWindow_Aim(cx, cy, nil, math.max(state.zoom, FindZoom()))
	return true
end

-- Centres on you, zoomed in until your zone fills most of the view (never out). False without a position. fly: the view
-- flies there as finding a quest does, and rings pulse out from you once it's there (the Find me button); without it,
-- it's there at once (opening the map).
function ns.MapWindow_FindMe(fly)
	if not frame then
		return false
	end
	for _, c in ipairs(ns.MapArt_Continents()) do
		local pos = C_Map.GetPlayerMapPosition(c.mapID, "player")
		if pos then
			local x, y = pos:GetXY()
			if ns.Readable(x) and ns.Readable(y) and not (x == 0 and y == 0) then
				local cx, cy = ns.Map_InBox(c.box, x, y)
				local zoneID = C_Map.GetBestMapForUnit("player")
				local box = zoneID and ns.Readable(zoneID) and ns.MapArt_Box(zoneID)
				local vw, vh = ViewSize()
				local zoom = state.zoom
				if box and vw > 0 then
					zoom = math.max(state.zoom, ns.Map_ZoomFor(box, vw, vh, Fit(vw, vh), FIND_SHARE))
				end
				if fly then
					ns.MapWindow_Aim(cx, cy, nil, zoom)
					pingWhenLanded = true
					return true
				end
				state.u, state.v, state.zoom = cx / W, cy / H, zoom
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
	if glide then
		-- One move: out and back in as it goes across (Data.lua, Map_FlightAt).
		glide.t = glide.t + elapsed
		local p = math.min(1, glide.t / glide.flight.time)
		state.u, state.v, state.zoom = ns.Map_FlightAt(glide.from, glide.flight, p)
		if p >= 1 then
			glide = nil
			if pingWhenLanded then
				pingWhenLanded = false
				ns.MapPins_PingPlayer()
			end
		end
		dirty = true
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
	-- Ctrl over the map: the game's map pin cursor, as its own map shows (WaypointLocationDataProviderMixin).
	local over = view:IsMouseOver()
	if over and IsControlKeyDown() and not drag then
		SetCursor("MAP_PIN_CURSOR")
		pinCursor = true
	elseif pinCursor then
		ResetCursor()
		pinCursor = false
	end
	-- The title: the place under the cursor, when it moved (where you are when it's off the map: ShowHere).
	if over then
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

-- The title while the cursor is off the map: where you are, and your spot there.
local function ShowHere()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and ns.Readable(mapID) and C_Map.GetMapInfo(mapID)
	zoneText:SetText(info and info.name or WORLD_MAP or "Map")
	local pos = info and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if pos then
		x, y = pos:GetXY()
	end
	if x and ns.Readable(x) and ns.Readable(y) and not (x == 0 and y == 0) then
		coordText:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
	else
		coordText:SetText("")
	end
end

-- Town markers: the button and its menu, as the minimap's tracking button ---------------------------------------------

local function Marked()
	dirty = true
	if ns.Panel_Refresh then
		ns.Panel_Refresh() -- the map's settings page shows the same choices
	end
end

-- As the minimap's tracking menu: a checkbox per kind, its icon at the right; it opens leftward, over the map.
local function TrackMenu(owner)
	UI.ContextMenu(owner, function(_, root)
		root:CreateButton("Uncheck all", function()
			for _, kind in ipairs(ns.MAP_TOWN_KINDS) do
				db.town[kind.key] = false
			end
			db.taxis, db.dungeons = false, false
			Marked()
		end)
		for _, kind in ipairs(ns.MAP_TOWN_KINDS) do
			root:CreateCheckbox(_G[kind.global] or kind.name, function()
				return db.town[kind.key]
			end, function()
				db.town[kind.key] = not db.town[kind.key]
				Marked()
			end):SetIcon(TRACKING_ART .. kind.icon)
		end
		root:CreateCheckbox(MINIMAP_TRACKING_FLIGHTMASTER or "Flight Master", function()
			return db.taxis
		end, function()
			db.taxis = not db.taxis
			Marked()
		end):SetIcon(TRACKING_ART .. "FlightMaster")
		root:CreateCheckbox("Dungeon entrances", function()
			return db.dungeons
		end, function()
			db.dungeons = not db.dungeons
			Marked()
		end):SetIcon(DUNGEON_ICON)
	end, "LEFT")
end

-- A round button in the minimap tracking button's art, with icon in its ring; tip: name and what it does.
local function RoundButton(icon, name, tip, onClick)
	local b = CreateFrame("Button", nil, frame)
	b:SetSize(TRACK_SIZE, TRACK_SIZE)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(25, 25)
	bg:SetPoint("TOPLEFT", 2, -4)
	bg:SetTexture(TRACK_BG)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(20, 20)
	b.icon:SetPoint("TOPLEFT", 6, -6)
	b.icon:SetTexture(icon)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")
	border:SetTexture(TRACK_BORDER)
	b:SetHighlightTexture(TRACK_HIGHLIGHT, "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self)
		GameTooltip:Hide()
		onClick(self)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		UI.TipLine(name, "heading")
		UI.TipLine(tip, "textMuted", true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- The quest log button: the game map's side panel toggle, its arrow pointing the way the panel will go.
local function LogButton()
	local b = CreateFrame("Button", nil, frame)
	b:SetSize(LOG_SIZE, LOG_SIZE)
	local shadow = b:CreateTexture(nil, "BACKGROUND")
	shadow:SetAtlas(LOG_SHADOW, true)
	shadow:SetPoint("BOTTOMRIGHT", 2, -1)
	local light = b:CreateTexture(nil, "HIGHLIGHT")
	light:SetTexture(LOG_HIGHLIGHT)
	light:SetBlendMode("ADD")
	light:SetSize(48, 48)
	light:SetPoint("CENTER")
	b:SetScript("OnClick", function()
		-- The button is your choice, kept: the map key opens the map this way from now on.
		sideWanted = not sideWanted
		db.sideShown = sideWanted
		ns.MapWindow_LayoutSide()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		UI.TipLine(QUEST_LOG or "Quest log", "heading")
		UI.TipLine("Show or hide your quests beside the map. The map key opens it the way you leave it.", "textMuted",
			true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- The quest log button's arrow points the way the panel moves: right (into the window's edge) while it shows, left
-- (out from it) while it's hidden. The game's map has it the other way round (seen in game).
local function SyncLogButton()
	if logButton then
		logButton:SetNormalAtlas(sideWanted and LOG_SHOW or LOG_HIDE)
		logButton:SetPushedAtlas(sideWanted and LOG_SHOW_DOWN or LOG_HIDE_DOWN)
	end
end

-- Mouse ---------------------------------------------------------------------------------------------------------------

local function OnMouseDown(_, button)
	if button == "LeftButton" then
		local sx, sy = Cursor()
		drag = { x = sx, y = sy, moved = false }
		glide, pingWhenLanded = nil, false
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
		PinAt(sx, sy)
	end
end

local function OnMouseWheel(_, delta)
	local sx, sy = Cursor()
	local base = target and target.zoom or state.zoom
	ZoomTo(base * WHEEL_STEP ^ delta, sx, sy)
end

-- Building ------------------------------------------------------------------------------------------------------------

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

	local forever = ns.Theme.panel == "forever"
	titleH = forever and FOREVER_STRIP_H + FOREVER_ROW_H or TITLE_H
	frame = UI.Dialog("TomteMapFrame", MIN_W, MIN_H, forever and { look = { portrait = true } } or nil) -- Esc closes it
	frame:SetFrameStrata("HIGH")
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_W, MIN_H)
	frame:HookScript("OnDragStop", SaveFrame)
	UI.ResizeGrip(frame, function()
		SaveFrame()
		dirty = true
	end)

	-- The title is the place: the one under the cursor, else where you are, its coordinates beside it (on Forever,
	-- centered on the frame's strip, the coordinates on the row under it).
	local close
	if forever then
		UI.Forever_Badge(frame, BADGE_ICON, nil, nil, nil, true)
		local bar = CreateFrame("Frame", nil, frame)
		bar:SetAllPoints()
		bar:SetFrameLevel(frame:GetFrameLevel() + FOREVER_BAR_LEVEL)
		zoneText = UI.Text(bar, 13, "heading", "title")
		zoneText:SetPoint("TOP", frame, "TOP", 0, -5)
		coordText = UI.Text(bar, 12, "textMuted", "number")
		coordText:SetPoint("LEFT", frame, "TOPLEFT", FOREVER_BADGE_ROOM, -(FOREVER_STRIP_H + FOREVER_ROW_H / 2))
		close = UI.Button(bar, 20, "x")
		close:SetSize(28, 28) -- UIPanelCloseButtonDefaultAnchorsMixin (Camelot), as the Tomte window's
		close:SetPoint("TOPRIGHT", 0, 3)
	else
		zoneText = UI.Text(frame, 17, "heading", "title")
		zoneText:SetPoint("TOPLEFT", PAD + 6, -8)
		coordText = UI.Text(frame, 12, "textMuted", "number")
		coordText:SetPoint("BOTTOMLEFT", zoneText, "BOTTOMRIGHT", 10, 1)
		close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	zoneText:SetWordWrap(false)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	-- A scroll frame with the canvas as its scroll child, as the game's map (see Apply).
	view = CreateFrame("ScrollFrame", nil, frame)
	-- The map sits in a sunken well, as the game's own windows frame their content (Forever theme; a rule elsewhere).
	local well = ns.Theme.panel == "forever" and UI.Forever_Well and UI.Forever_Well(frame)
	if not well then
		well = CreateFrame("Frame", nil, frame)
		UI.Border(well, "frame", 0.6)
	end
	well:SetFrameLevel(frame:GetFrameLevel()) -- under the map
	well:SetPoint("TOPLEFT", view, "TOPLEFT", -WELL_OUT, WELL_OUT)
	well:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", WELL_OUT, -WELL_OUT)
	-- The side panel rides the view's right edge inside a frame that clips it at the window's edge, so panel and map move
	-- as one while it slides.
	sideClip = CreateFrame("Frame", nil, frame)
	sideClip:SetClipsChildren(true)
	sideClip:SetFrameLevel(view:GetFrameLevel() + 60)
	side, sideWidth = ns.MapSide_Build(sideClip, db)
	side:SetPoint("TOPLEFT")
	side:SetPoint("BOTTOMLEFT")
	sideWanted = db.sideShown
	sideOpen = sideWanted and 1 or 0
	ns.MapWindow_LayoutSide(true)
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
	-- On the map's corners, as the game's map has its buttons: town markers and Find me top right, the quest log
	-- bottom right. They ride the view's edge as the side panel slides.
	local track = RoundButton(TRACK_ICON, "Town markers", "Choose what the map shows: mailboxes, bankers, inns, "
		.. "trainers and more. They show once you're zoomed in on a zone.", TrackMenu)
	track:SetPoint("TOPRIGHT", view, "TOPRIGHT", -TRACK_INSET, -TRACK_INSET)
	track:SetFrameLevel(view:GetFrameLevel() + 50)
	local find = RoundButton(FIND_ICON, "Find me", "Go to where you are, zoomed in on your zone.", function()
		if not ns.MapWindow_FindMe(true) then
			ns.Print("the map can't show where you are here.")
		end
	end)
	find:SetPoint("RIGHT", track, "LEFT", -TRACK_GAP, 0)
	find.icon:ClearAllPoints()
	find.icon:SetPoint("CENTER", find, "TOPLEFT", FIND_CENTER_X, FIND_CENTER_Y)
	find.icon:SetSize(FIND_ARROW, FIND_ARROW)
	find.icon:SetRotation(FIND_TURN)
	find:SetFrameLevel(view:GetFrameLevel() + 50)
	logButton = LogButton()
	logButton:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -TRACK_INSET, TRACK_INSET)
	logButton:SetFrameLevel(view:GetFrameLevel() + 50)
	SyncLogButton()

	ns.MapArt_Init(canvas, W, H, worldID)
	ns.MapMini_Init(canvas, db)
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
		ShowHere()
	end)

	frame:HookScript("OnShow", function()
		ns.Map_Shown(true)
		ns.MapPins_Read()
		ns.MapQuests_Refresh() -- the quest list drew before the quests' spots were read (its find buttons)
		ShowHere()
		-- After the first layout (the arrow is made and placed there).
		C_Timer.After(0, ns.MapPins_PingPlayer)
		dirty = true
		ticker = C_Timer.NewTicker(TICK, function()
			if not dirty then
				ns.MapPins_Tick(ToView)
			end
			if not view:IsMouseOver() then
				ShowHere()
			end
		end)
	end)
	frame:HookScript("OnHide", function()
		drag, target, aim, glide, pingWhenLanded = nil, nil, nil, nil, false
		if pinCursor then
			ResetCursor()
			pinCursor = false
		end
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		ns.Map_Shown(false) -- art loading pauses by itself: its loader is on the hidden canvas
		ns.MapPins_Focus(nil) -- a spot shown from elsewhere lasts while the window is open
	end)
	PlaceFrame()
	return true
end

-- The side panel open this far (0..1): the view's right edge moves with it, and the view keeps what's at its left
-- edge where it is (the map doesn't move under you as the panel opens). The panel slides in on that edge.
local function SetSideOpen(open, keepLeft)
	local before = SideTaken()
	sideOpen = open
	local taken = SideTaken()
	if keepLeft then
		local vw, vh = ViewSize()
		local scale = vw > 0 and Fit(vw, vh) * state.zoom or 0
		if scale > 0 then
			state.u = state.u - (taken - before) / (2 * scale * W)
		end
	end
	view:ClearAllPoints()
	view:SetPoint("TOPLEFT", PAD, -titleH)
	view:SetPoint("BOTTOMRIGHT", -PAD - taken, PAD)
	sideClip:ClearAllPoints()
	sideClip:SetPoint("TOPLEFT", view, "TOPRIGHT", SIDE_GAP, 0)
	sideClip:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	sideClip:SetShown(open > 0)
	side:SetShown(open > 0)
	dirty = true
end

-- The side panel opens or closes as sideWanted says (now: no slide, when the window is built).
function ns.MapWindow_LayoutSide(now)
	if not side then
		return
	end
	SyncLogButton()
	local from, to = sideOpen, sideWanted and 1 or 0
	if now or not frame:IsVisible() then
		UI.TweenStop(side, "open")
		SetSideOpen(to, false)
		return
	end
	UI.Tween(side, "open", SIDE_TIME, function(t)
		SetSideOpen(from + (to - from) * t, true)
	end, nil, UI.EaseOut)
end

-- For other modules (the Dungeon journal's "Show on map"): opens the map on spot x, y (0..1) of mapID, flying there
-- (out to an overview, across, then in until that map fills most of the view), and marks it with a pulsing ring (its label on
-- hover) for a few seconds (Pins.lua, FOCUS_LASTS). Called from a click. False while the Tomte map is off or when the
-- world map doesn't place mapID.
function ns.MapWindow_ShowSpot(mapID, x, y, label)
	if not (ns.Map_IsOn() and mapID and x and y) then
		return false
	end
	if not frame and not Build() then
		return false
	end
	local cx, cy = ns.MapArt_ToCanvas(mapID, x, y)
	if not cx then
		return false
	end
	if not frame:IsShown() then
		-- Not through Toggle (no finding you first): it opens on the whole world and flies from there.
		state.zoom = MIN_ZOOM
		frame:Show()
	end
	ns.MapWindow_Aim(cx, cy, nil, FindZoom())
	ns.MapPins_Focus(mapID, x, y, label)
	return true
end

-- The side panel's find button: flies to the quest the way "Show on map" does and rings its pin. False without a spot.
function ns.MapWindow_FindQuest(questID, label)
	local mapID, x, y = ns.MapPins_QuestSpot(questID)
	local cx, cy
	if mapID then
		cx, cy = ns.MapArt_ToCanvas(mapID, x, y)
	end
	if not (frame and cx) then
		return false
	end
	ns.MapWindow_Aim(cx, cy, nil, FindZoom())
	ns.MapPins_Focus(mapID, x, y, label)
	return true
end

-- From Map.lua --------------------------------------------------------------------------------------------------------

function ns.MapWindow_Init(moduleDB)
	db = moduleDB
end

-- The map key and the quest log key (as the game's M and L). withLog: the quest log key, which opens the map with its
-- quest list showing this time (a map already open gets it) without changing what the map key does; the map key opens
-- it as you last left the Quest log button.
function ns.MapWindow_Toggle(withLog)
	if frame and frame:IsShown() then
		if withLog and not sideWanted then
			db.side = "quests"
			sideWanted = true
			ns.MapWindow_LayoutSide()
			return
		end
		frame:Hide()
		return
	end
	if not frame and not Build() then
		ns.Print("the world map's art isn't available on this client.")
		return
	end
	sideWanted = withLog or db.sideShown
	if withLog then
		db.side = "quests"
	end
	ns.MapWindow_LayoutSide(true)
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
