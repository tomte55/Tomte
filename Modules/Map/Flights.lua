local addonName, ns = ...

-- Tomte map: flight mode. At a flight master the Tomte map opens with the places you can fly to as pins (hover: the
-- route and its time and cost; click: you fly), your quests on the same map, and the flight master nearest your
-- followed quest ringed. Blizzard's flight map still opens (the game opens and closes it) but is muted: invisible and
-- too small to click, never hidden from here (showing or hiding UI panels from addon code taints). Events come from
-- Map.lua, layout from Window.lua. See docs/superpowers/specs/2026-11-18-tomte-map-flights-design.md.

local PIN = 20 -- pixels, times the map's icon size setting
local NEAREST_RING = 1.7 -- the ring round the flight master nearest your quest, in pin widths
local UNREACHABLE_ALPHA = 0.35
local LINE_PX = 3
local LINE_ALPHA = 0.9
local LEVEL = 150 -- frame level over the pin layer: over the quests (Pins.lua, 10 and up), under the map pin (200)
local FRAME_PAD = 0.15 -- the flight pins framed with this share of their spread around them (Data.lua, Map_BoxAround)
local MUTE_SCALE = 0.001 -- Blizzard's muted flight map: too small to catch the mouse (at alpha 0 it still would)
local BLIZZARD_FRAMES = { "FlightMapFrame", "TaxiFrame" } -- Forever's flight map, and the older taxi window
local RING = ns.Theme.MEDIA .. "Gather\\Ring"
local TAXI_FALLBACK = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"
local ATLAS = { current = "Taxi_Frame_Green", reachable = "Taxi_Frame_Gray", hover = "Taxi_Frame_Yellow" }
-- Where this client lacks those atlases: the taxi window's icons (TaxiFrame.lua's TaxiButtonTypes); a hovered one turns
-- green, its route drawn too.
local FILES = { current = TAXI_FALLBACK, reachable = "Interface\\TaxiFrame\\UI-Taxi-Icon-White",
	hover = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" }

local UI = ns.UI

local layer, db
local taxiOpen = false -- a flight master's taxi map is open
local flightMode = false -- and the Tomte map shows it
local openedWindow = false -- flight mode opened the window (so it closes it again)
local nodes = {} -- { slot, name, state, cx, cy }, this flight master's
local bySlot = {} -- [slot] = node
local reachable = {} -- the nodes you can fly to, for the nearest to your quest
local pins, lines = {}, {}
local linesUsed = 0
local hoveredSlot
local nearestSlot
local lastToViewAll
local muted = {} -- [Blizzard frame] = { alpha, scale } while muted
local hooked = {} -- [Blizzard frame] = true once its OnShow is hooked

-- TaxiNodeGetType's answers. A distant node (another region's) gets no pin, as on the game's taxi window, but routes
-- through it still draw.
local KIND = { CURRENT = "current", REACHABLE = "reachable", UNREACHABLE = "unreachable", DISTANT = "distant" }
local unmatched = {} -- this flight master's node names with no flight master of that name on the map (for "why")

-- Blizzard's flight map ------------------------------------------------------------------------------------------------

local function Mute(f)
	if muted[f] or not f:IsShown() then
		return
	end
	muted[f] = { f:GetAlpha(), f:GetScale() }
	f:SetAlpha(0)
	f:SetScale(MUTE_SCALE)
end

local function Unmute()
	for f, was in pairs(muted) do
		f:SetAlpha(was[1])
		f:SetScale(was[2])
		muted[f] = nil
	end
end

-- Hooks can't be undone: they mute only while flight mode is on.
local function HookAndMute()
	for _, name in ipairs(BLIZZARD_FRAMES) do
		local f = _G[name]
		if f then
			if not hooked[f] then
				hooked[f] = true
				f:HookScript("OnShow", function(self)
					if flightMode then
						Mute(self)
					end
				end)
			end
			if flightMode then
				Mute(f)
			end
		end
	end
end

-- Pins and lines -------------------------------------------------------------------------------------------------------

local DrawRoute

local function PinTip(pin)
	local node = pin.node
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	UI.TipLine(node.name or "", "heading")
	if node.key == "current" then
		UI.TipLine(TAXINODEYOUAREHERE or "You are here", "text")
	elseif node.key == "reachable" then
		local cost = TaxiNodeCost(node.slot)
		if cost and cost > 0 then
			UI.TipLine(ns.Price(cost), "text")
		end
		local time = ns.Flight_TimeText and ns.Flight_TimeText(node.slot)
		if time then
			UI.TipLine(time, "textMuted")
		end
		if node.slot == nearestSlot and pin.ringNote then
			UI.TipLine(pin.ringNote, "accent")
		end
		UI.TipLine("Click: fly there", "textMuted")
	else
		UI.TipLine(TAXI_PATH_UNREACHABLE or "No flight path there from here", "danger")
	end
	GameTooltip:Show()
end

-- The flight map's atlas, else the taxi window's own icon (Forever's TaxiFrame: TaxiButtonTypes).
local function Look(pin, atlasKey)
	if pin.look == atlasKey then
		return
	end
	pin.look = atlasKey
	if not pin.icon:SetAtlas(ATLAS[atlasKey]) then
		pin.icon:SetTexture(FILES[atlasKey] or TAXI_FALLBACK)
	end
end

local function NewPin()
	local pin = CreateFrame("Button", nil, layer)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin.ring = pin:CreateTexture(nil, "BACKGROUND")
	pin.ring:SetPoint("CENTER")
	pin.ring:SetTexture(RING)
	pin:RegisterForClicks("LeftButtonUp")
	pin:SetScript("OnEnter", function(self)
		if self.node.key == "reachable" then
			Look(self, "hover")
		end
		hoveredSlot = self.node.slot
		DrawRoute()
		PinTip(self)
	end)
	pin:SetScript("OnLeave", function(self)
		if self.node.key == "reachable" then
			Look(self, "reachable")
		end
		hoveredSlot = nil
		DrawRoute()
		GameTooltip_Hide()
	end)
	-- From a click only: the game's own flight pin does the same (FlightMap_FlightPointPinMixin:OnClick).
	pin:SetScript("OnClick", function(self)
		if taxiOpen and self.node.key == "reachable" then
			TakeTaxiNode(self.node.slot)
		end
	end)
	return pin
end

local function Line(i)
	local line = lines[i]
	if not line then
		line = layer:CreateLine(nil, "OVERLAY")
		lines[i] = line
	end
	return line
end

local function HideLines()
	for i = 1, linesUsed do
		lines[i]:Hide()
	end
	linesUsed = 0
end

-- The hovered destination's route, hop by hop, as lines (from where they are on the view, also off its edge).
DrawRoute = function()
	HideLines()
	local slot = hoveredSlot
	local node = slot and bySlot[slot]
	if not (flightMode and node and node.key == "reachable" and lastToViewAll) then
		return
	end
	for hop = 1, GetNumRoutes(slot) or 0 do
		local a, b = bySlot[TaxiGetNodeSlot(slot, hop, true)], bySlot[TaxiGetNodeSlot(slot, hop, false)]
		if a and b then
			local x1, y1 = lastToViewAll(a.cx, a.cy)
			local x2, y2 = lastToViewAll(b.cx, b.cy)
			linesUsed = linesUsed + 1
			local line = Line(linesUsed)
			line:SetThickness(LINE_PX)
			line:SetColorTexture(UI.Color("accent"))
			line:SetAlpha(LINE_ALPHA)
			line:SetStartPoint("CENTER", layer, x1, -y1)
			line:SetEndPoint("CENTER", layer, x2, -y2)
			line:Show()
		end
	end
end

local function HidePins()
	for _, pin in ipairs(pins) do
		pin:Hide()
	end
	HideLines()
end

-- The flight master to ring, and its tooltip line: where a Waypoints route flies next (ForeverRouter.lua), else the
-- one nearest your followed quest's spot (on the Tomte map's canvas); nil for none.
local function NearestToQuest()
	local fly = ns.WayRouter_FlyTo and ns.WayRouter_FlyTo()
	if fly then
		for _, node in ipairs(reachable) do
			if node.name == fly.name then
				return node.slot, fly.note
			end
		end
	end
	local quest = ns.ActiveQuest_ID()
	if not quest or ns.IsSecret(quest) then
		return nil
	end
	local mapID, x, y = ns.MapPins_QuestSpot(quest)
	local cx, cy
	if mapID then
		cx, cy = ns.MapArt_ToCanvas(mapID, x, y)
	end
	if not cx then
		return nil
	end
	local i = ns.Map_Nearest(reachable, cx, cy)
	local title = C_QuestLog.GetTitleForQuestID(quest)
	return i and reachable[i].slot, title and ("Nearest to %s"):format(title)
end

-- Reading ----------------------------------------------------------------------------------------------------------------

local function Pos(v)
	if type(v) ~= "table" then
		return nil
	end
	if type(v.GetXY) == "function" then
		return v:GetXY()
	end
	return v.x, v.y
end

-- Every flight master on the continents' maps by name, on the canvas: read once (they don't move). Forever's taxi
-- window gives positions on its own taxi picture, not the world map, so a node is placed where the map's flight master
-- of the same name is.
local canvasByName

local function CanvasByName()
	if canvasByName then
		return canvasByName
	end
	canvasByName = {}
	for _, c in ipairs(ns.MapArt_Continents()) do
		for _, info in ipairs(C_TaxiMap.GetTaxiNodesForMap(c.mapID) or {}) do
			local x, y = Pos(info.position)
			local cx, cy
			if x and info.name and not canvasByName[info.name] then
				cx, cy = ns.MapArt_ToCanvas(c.mapID, x, y)
			end
			if cx then
				canvasByName[info.name] = { cx, cy }
			end
		end
	end
	return canvasByName
end

-- The open flight master's nodes, through the taxi window's own API (Forever's is the older TaxiFrame:
-- NumTaxiNodes and friends, Blizzard_UIPanels_Game/Shared/TaxiFrame.lua).
local function ReadNodes()
	wipe(nodes)
	wipe(bySlot)
	wipe(reachable)
	wipe(unmatched)
	local byName = CanvasByName()
	for slot = 1, NumTaxiNodes() or 0 do
		local key = KIND[TaxiNodeGetType(slot) or ""]
		local name = TaxiNodeName(slot)
		local spot = name and byName[name]
		if key and spot then
			local node = { slot = slot, name = name, key = key, cx = spot[1], cy = spot[2] }
			nodes[#nodes + 1] = node
			bySlot[slot] = node
			if key == "reachable" then
				reachable[#reachable + 1] = node
			end
		elseif key and key ~= "distant" then
			unmatched[#unmatched + 1] = name or ("#" .. slot)
		end
	end
end

-- The places to frame: where you are and where you fly next (Data.lua, Map_FlightFrame).
local function FrameBox()
	local fly = ns.WayRouter_FlyTo and ns.WayRouter_FlyTo()
	return ns.Map_BoxAround(ns.Map_FlightFrame(nodes, fly and fly.name), FRAME_PAD)
end

-- From Map.lua and Window.lua ------------------------------------------------------------------------------------------

-- Map.lua's init gives the settings; Window.lua's build the pin layer.
function ns.MapFlights_Init(pinLayer, moduleDB)
	layer, db = pinLayer or layer, moduleDB or db
	ns.MapRoute_Init(pinLayer)
end

function ns.MapFlights_Active()
	return flightMode
end

-- A flight master's taxi map opened (Map.lua, while the module is on).
function ns.MapFlights_Opened()
	taxiOpen = true
	if not (db and db.flights and ns.MapWindow_Ready()) then
		return
	end
	ReadNodes()
	local box = FrameBox()
	if not box then
		return -- this flight master's map isn't on the Tomte map's canvas: the game's flight map as usual
	end
	flightMode = true
	HookAndMute()
	-- The first time, the game loads its flight map in this same event; one frame later it's surely there.
	C_Timer.After(0, function()
		if flightMode then
			HookAndMute()
		end
	end)
	openedWindow = ns.MapWindow_OpenFlights(box)
	ns.MapWindow_Relayout()
end

-- Flight mode ends; the window closes if flight mode opened it.
local function EndFlightMode()
	if not flightMode then
		return
	end
	flightMode = false
	hoveredSlot = nil
	Unmute()
	HidePins()
	if openedWindow then
		openedWindow = false
		ns.MapWindow_Hide()
	end
	ns.MapWindow_Relayout()
end

-- The flight master's taxi map closed (walked away, flew, Esc on the game's muted window).
function ns.MapFlights_Closed()
	taxiOpen = false
	EndFlightMode()
end

-- The module or the setting turned off: the game's flight map back as normal, the flight master left open.
function ns.MapFlights_Stop()
	openedWindow = false
	EndFlightMode()
end

-- Window.lua: the Tomte map window hid while in flight mode (closed by you): the flight master's map closes too.
function ns.MapFlights_WindowHidden()
	if flightMode and taxiOpen then
		openedWindow = false
		CloseTaxiMap()
	end
end

-- /tomte map flights: what flight mode read at the last flight master, and why it's on or off.
function ns.MapFlights_Why()
	ns.Print(("flight master open: %s, flight mode: %s, setting: %s"):format(tostring(taxiOpen),
		tostring(flightMode), tostring(db and db.flights)))
	local counts = {}
	for _, node in ipairs(nodes) do
		counts[node.key] = (counts[node.key] or 0) + 1
	end
	ns.Print(("nodes placed: %d (current %d, reachable %d, unreachable %d, distant %d); taxi window lists %s"):format(
		#nodes, counts.current or 0, counts.reachable or 0, counts.unreachable or 0, counts.distant or 0,
		taxiOpen and tostring(NumTaxiNodes()) or "-"))
	if #unmatched > 0 then
		ns.Print("no flight master of that name on the map: " .. table.concat(unmatched, ", "))
	end
end

-- Window.lua, every layout: the flight pins placed. toView: on the view or nil; toViewAll: anywhere (route lines).
function ns.MapFlights_Layout(toView, toViewAll)
	lastToViewAll = toViewAll
	ns.MapRoute_Layout(toViewAll) -- a Waypoints route's line (RouteLine.lua), flight mode or not
	if not flightMode then
		HidePins()
		return
	end
	local ringNote
	nearestSlot, ringNote = NearestToQuest()
	local size = PIN * (db.pinScale or 1)
	for i, node in ipairs(nodes) do
		local pin = pins[i] or NewPin()
		pins[i] = pin
		pin.node, pin.ringNote = node, ringNote
		local x, y = toView(node.cx, node.cy)
		if x and node.key ~= "distant" then
			pin:SetSize(size, size)
			pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL)
			Look(pin, node.key == "current" and "current" or (node.slot == hoveredSlot and "hover" or "reachable"))
			pin:SetAlpha(node.key == "unreachable" and UNREACHABLE_ALPHA or 1)
			pin.ring:SetShown(node.slot == nearestSlot)
			pin.ring:SetSize(size * NEAREST_RING, size * NEAREST_RING)
			pin.ring:SetVertexColor(UI.Color("accent"))
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", layer, "CENTER", x, -y)
			pin:Show()
		else
			pin:Hide()
		end
	end
	for i = #nodes + 1, #pins do
		pins[i]:Hide()
	end
	DrawRoute()
end
