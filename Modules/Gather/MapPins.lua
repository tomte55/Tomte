local addonName, ns = ...

-- Gathering node spots on the world map: a round icon on every mining and herbalism spot Gathering remembers
-- (Nodes.lua), with a tooltip, and a round button in the map's top-right column with a menu (which nodes and node
-- types to show, remember spots, forget this map's spots, settings). Plain frames on the map canvas, not a map data provider or Blizzard's pin pools
-- (taint, see the World quests marker). Also the map's gathering route (Follow.lua) as lines under the pins, the spot
-- being followed drawn bigger, and spots gathered a moment ago dimmed. Registered in Gather.lua.

local PIN_SIZE = 16 -- screen pixels at any zoom
local RING = 2 -- pixels of ring around the icon
local LINE = 2 -- route line thickness in screen pixels
local LINE_ALPHA = 0.75
local FOLLOWED = 1.5 -- the followed spot's size against a normal pin
local RECENT_ALPHA = 0.45 -- a spot gathered in the last few minutes
local UNDIM_CHECK = 30 -- seconds between redraws while dimmed spots show (Refresh does nothing once the map is shut)
-- The map's own frame level for dig sites: above the map art, fog and quest areas, under quests and points of interest.
local LEVEL_TYPE = "PIN_FRAME_LEVEL_DIG_SITE"
-- Map buttons stack down the map's top-right corner, 32 px apart (Blizzard's filter and pin buttons first). Other
-- addons (RareScanner, Krowi's) stack theirs with Krowi_WorldMapButtons; when it's loaded ours joins that column.
local STACK_LIB = "Krowi_WorldMapButtons-1.4"
local BLIZZARD_BUTTONS = 2 -- the map's filter and map pin buttons, when no addon stacks buttons
local BUTTON_ICON = "Interface\\Icons\\Trade_Mining"

local UI = ns.UI

local db, module
local pool, used = {}, 0
local lines, linesUsed, lineFrame = {}, 0, nil
local undim -- timer that redraws while dimmed spots are on the map, so they light up again
local hooked = false
local button

-- The name of the ore or herb a node type drops (the same for its quality ranks), or nil while the item isn't loaded
-- (asked for, so it's there next time).
local function ItemName(t)
	if not (t and t.item) then
		return nil
	end
	local name = C_Item.GetItemNameByID(t.item)
	if not name then
		C_Item.RequestLoadItemDataByID(t.item)
	end
	return name
end

-- What a spot is called: the ore or herb, not the node type, since variants (Lush, Rich, Crystallized ...) spawn at
-- random on the same spots. Also for the route's card (Follow.lua).
function ns.GatherPins_NodeName(t, kind)
	return ItemName(t) or (t and t.name) or (ns.GATHER_KIND_NAMES[kind] .. " node")
end

local function ShowTooltip(pin)
	local spot = pin.spot
	local t = spot.objectID and db.nodeTypes[spot.objectID]
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.GatherPins_NodeName(t, spot.kind), UI.Color("heading"))
	UI.TipLine(ns.GATHER_KIND_NAMES[spot.kind] .. " node", "textMuted")
	local age = ns.Gather_SpotAge(WorldMapFrame:GetMapID(), spot.pos)
	if age then
		UI.TipLine("Gathered " .. ns.AgoText(age), "textMuted")
	end
	if pin.followed then
		UI.TipLine("Next on your gathering route", "accent")
	end
	GameTooltip:Show()
end

local function NewPin(canvas)
	local pin = CreateFrame("Frame", nil, canvas)
	pin:EnableMouse(true)
	pin:SetMouseClickEnabled(false) -- clicks go on to the map (zoom, waypoints); only hovering is ours
	pin.ring = pin:CreateTexture(nil, "ARTWORK")
	pin.ring:SetAllPoints()
	UI.CircleMask(pin.ring, pin)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.CircleMask(pin.icon, pin)
	pin:SetScript("OnEnter", ShowTooltip)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	return pin
end

local function HideAll()
	for i = 1, used do
		pool[i]:Hide()
	end
	used = 0
end

-- The kinds to show, or nil for all; false when pins are off. mode: "mine", "all" or "off", default the setting.
-- Also for the minimap (MinimapPins.lua) and routes (Follow.lua).
function ns.GatherPins_Kinds(mode)
	mode = mode or db.mapPins
	if not (module and module.active) or mode == "off" then
		return false
	end
	if mode == "all" then
		return nil
	end
	local kinds = {}
	for _, p in ipairs(ns.GatherDetect_Profs()) do
		kinds[p.kind] = true
	end
	return kinds
end

local function Icon(spot)
	local t = spot.objectID and db.nodeTypes[spot.objectID]
	return t and t.item and C_Item.GetItemIconByID(t.item) or ns.GATHER_KIND_ICONS[spot.kind]
end

-- Size and place the pins in use for the canvas's current size and zoom.
local function Layout()
	local canvas = WorldMapFrame:GetCanvas()
	local scale = WorldMapFrame.ScrollContainer:GetCanvasScale()
	local w, h = canvas:GetWidth(), canvas:GetHeight()
	local ring = RING / scale
	for i = 1, used do
		local pin = pool[i]
		local size = PIN_SIZE / scale * (pin.followed and FOLLOWED or 1)
		pin:SetSize(size, size)
		pin.icon:ClearAllPoints()
		pin.icon:SetPoint("TOPLEFT", ring, -ring)
		pin.icon:SetPoint("BOTTOMRIGHT", -ring, ring)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", pin.spot.x * w, -pin.spot.y * h)
	end
	for i = 1, linesUsed do
		local line = lines[i]
		line:SetThickness(LINE / scale)
		line:SetStartPoint("TOPLEFT", canvas, line.a.x * w, -line.a.y * h)
		line:SetEndPoint("TOPLEFT", canvas, line.b.x * w, -line.b.y * h)
	end
end

-- Route lines --------------------------------------------------------------------------------------------------------

local function HideLines()
	for i = 1, linesUsed do
		lines[i]:Hide()
	end
	linesUsed = 0
end

-- The map's loop as lines from spot to spot, under the pins.
local function DrawRoute(canvas, mapID, level)
	if not db.mapRoute then
		return
	end
	local route, spots = ns.GatherRoute_For(mapID)
	if not route or #route.order < 3 then
		return
	end
	if not lineFrame then
		lineFrame = CreateFrame("Frame", nil, canvas)
		lineFrame:SetAllPoints(canvas)
	end
	lineFrame:SetFrameLevel(math.max(level - 1, 1))
	local r, g, b = UI.Color("accent")
	local order = route.order
	for i = 1, #order do
		linesUsed = linesUsed + 1
		local line = lines[linesUsed]
		if not line then
			line = lineFrame:CreateLine(nil, "ARTWORK")
			lines[linesUsed] = line
		end
		line.a, line.b = spots[order[i]], spots[order[i % #order + 1]]
		line:SetColorTexture(r, g, b, LINE_ALPHA)
		line:Show()
	end
end

-- Map button --------------------------------------------------------------------------------------------------------

local function UpdateButton()
	if not button then
		return
	end
	button:SetShown(module.active and db.mapButton)
	button.icon:SetDesaturated(db.mapPins == "off")
end

local function SetPins(mode)
	db.mapPins = mode
	ns.GatherPins_Refresh()
end

-- A group's spots show while any of its node types isn't hidden (a variant first seen after hiding the rest).
local function GroupShown(group)
	for _, id in ipairs(group.ids) do
		if not db.hiddenTypes[id] then
			return true
		end
	end
	return false
end

-- "Ores and herbs on this map" submenu: a checkbox per ore or herb with spots on this map (the shown kinds only; a
-- node's random variants count as it), and Show all. Ticking hides or shows every node type in the group.
local function TypesMenu(root, mapID)
	local kinds = ns.GatherPins_Kinds()
	local types = kinds ~= false and mapID and ns.GatherNodes_Types(db, mapID, kinds) or {}
	if #types == 0 then
		return
	end
	local groups = ns.GatherNodes_Groups(types, ItemName)
	local sub = root:CreateButton("Ores and herbs on this map")
	local anyHidden = false
	for _, group in ipairs(groups) do
		anyHidden = anyHidden or not GroupShown(group)
		sub:CreateCheckbox(("%s (%d)"):format(group.name, group.count), function()
			return GroupShown(group)
		end, function()
			local hide = GroupShown(group) or nil
			for _, id in ipairs(group.ids) do
				db.hiddenTypes[id] = hide
			end
			ns.Gather_PinsChanged()
		end)
	end
	if anyHidden then
		sub:CreateDivider()
		sub:CreateButton("Show all", function()
			for _, t in ipairs(types) do
				db.hiddenTypes[t.objectID] = nil
			end
			ns.Gather_PinsChanged()
		end)
	end
end

local function ForgetMap(mapID)
	local here = ns.GatherNodes_Counts(db, mapID)
	local n = (here.mining or 0) + (here.herbalism or 0)
	if n == 0 then
		return
	end
	local info = C_Map.GetMapInfo(mapID)
	local name = info and info.name or "this map"
	ns.Confirm_Show(("Forget the %s node spots in %s?\n\nOther maps keep theirs. With Friend sharing on, spots a friend "
		.. "has here come back when they next share."):format(ns.Thousands(n), name), function()
		local followMap = ns.GatherFollow_Spot()
		if followMap == mapID then
			ns.GatherFollow_Stop("user")
		end
		ns.GatherNodes_Forget(db, mapID)
		ns.Gather_NodesChanged(mapID)
	end)
end

local function OpenMenu(owner)
	local mapID = WorldMapFrame:GetMapID()
	UI.ContextMenu(owner, function(_, root)
		root:CreateTitle("Gathering nodes")
		for _, choice in ipairs({ { "mine", "For your professions" }, { "all", "All" }, { "off", "Off" } }) do
			root:CreateRadio(choice[2], function()
				return db.mapPins == choice[1]
			end, function()
				SetPins(choice[1])
			end)
		end
		TypesMenu(root, mapID)
		root:CreateDivider()
		root:CreateCheckbox("Show the route", function()
			return db.mapRoute
		end, function()
			db.mapRoute = not db.mapRoute
			ns.GatherPins_Refresh()
		end)
		if ns.GatherFollow_Active() then
			root:CreateButton("Stop following the route", function()
				ns.GatherFollow_Stop("user")
			end)
		else
			root:CreateButton("Follow the route in your zone", ns.GatherFollow_Start)
		end
		root:CreateCheckbox("Remember node spots", function()
			return db.recordNodes
		end, function()
			db.recordNodes = not db.recordNodes
			ns.Share_Changed("nodes")
		end)
		local here = mapID and ns.GatherNodes_Counts(db, mapID)
		if here and ((here.mining or 0) + (here.herbalism or 0)) > 0 then
			root:CreateButton("Forget node spots on this map", function()
				ForgetMap(mapID)
			end)
		end
		root:CreateButton("Gathering page", ns.Gather_Open)
		root:CreateButton("Settings", function()
			ns.Panel_OpenModule("gather")
		end)
	end)
end

local function ButtonTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Gathering nodes", UI.Color("heading"))
	local here = ns.GatherNodes_Counts(db, WorldMapFrame:GetMapID())
	local n = (here.mining or 0) + (here.herbalism or 0)
	UI.TipLine(n == 1 and "1 node spot on this map" or (ns.Thousands(n) .. " node spots on this map"), "textMuted")
	local route = ns.GatherRoute_For(WorldMapFrame:GetMapID())
	if route then
		UI.TipLine("Route: " .. ns.GatherRoute_Text(route), "textMuted")
	end
	if ns.GatherFollow_Active() then
		UI.TipLine("Following the route", "accent")
	end
	UI.TipLine("Left-click: what to show. Right-click: show or hide them.", "textFaint")
	GameTooltip:Show()
end

-- Right-click: pins off, or back on to how they were.
local function QuickToggle()
	if db.mapPins == "off" then
		SetPins(db.mapPinsOn or "mine")
	else
		db.mapPinsOn = db.mapPins
		SetPins("off")
	end
end

-- Blizzard's round map button look: a dark disc, the icon and the gold tracking ring (Interface\Minimap art).
local function Dress(b)
	b:SetSize(32, 32)
	b:SetFrameStrata("HIGH") -- the strata of Blizzard's map buttons
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(25, 25)
	bg:SetPoint("TOPLEFT", 2, -4)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(BUTTON_ICON)
	b.icon:SetSize(20, 20)
	b.icon:SetPoint("TOPLEFT", 7, -6)
	UI.CircleMask(b.icon, b)
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(54, 54)
	ring:SetPoint("TOPLEFT")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			QuickToggle()
			ButtonTooltip(self)
		else
			GameTooltip:Hide()
			OpenMenu(self)
		end
	end)
	b:SetScript("OnEnter", ButtonTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnMouseDown", function()
		b.icon:SetPoint("TOPLEFT", 8, -7)
	end)
	b:SetScript("OnMouseUp", function()
		b.icon:SetPoint("TOPLEFT", 7, -6)
	end)
end

-- Built on the first map open, after the other addons added theirs, so it lands at the bottom of the column.
local function CreateButton()
	local lib = LibStub and LibStub(STACK_LIB, true)
	if lib then
		local ok, b = pcall(lib.Add, lib, nil, "BUTTON")
		if ok and b then
			button = b
			button.Refresh = UpdateButton -- the library calls it on every map change
		end
	end
	if not button then
		button = CreateFrame("Button", nil, WorldMapFrame)
		button:SetPoint("TOPRIGHT", WorldMapFrame:GetCanvasContainer(), "TOPRIGHT", -4, -2 - 32 * BLIZZARD_BUTTONS)
	end
	Dress(button)
	UpdateButton()
end

-- Pins ----------------------------------------------------------------------------------------------------------------

function ns.GatherPins_Refresh()
	if not (hooked and WorldMapFrame:IsShown()) then
		return
	end
	if not button and module.active and db.mapButton then
		CreateButton()
	end
	UpdateButton()
	HideAll()
	HideLines()
	local kinds = ns.GatherPins_Kinds()
	local mapID = WorldMapFrame:GetMapID()
	if kinds == false or not mapID then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	local level = WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel(LEVEL_TYPE)
	local followMap, followPos = ns.GatherFollow_Spot()
	DrawRoute(canvas, mapID, level)
	local anyRecent = false
	for _, spot in ipairs(ns.GatherNodes_List(db, mapID, kinds, db.hiddenTypes)) do
		used = used + 1
		local pin = pool[used]
		if not pin then
			pin = NewPin(canvas)
			pool[used] = pin
		end
		pin.spot = spot
		pin.followed = followMap == mapID and followPos == spot.pos
		local recent = ns.GatherRoute_IsRecent(mapID, spot.pos)
		pin:SetFrameLevel(pin.followed and level + 1 or level)
		local r, g, b = UI.Color(pin.followed and "accent" or "frameDark")
		pin.ring:SetColorTexture(r, g, b, 0.9)
		pin.icon:SetTexture(Icon(spot))
		pin.icon:SetDesaturated(recent)
		pin:SetAlpha(recent and not pin.followed and RECENT_ALPHA or 1)
		pin:Show()
		anyRecent = anyRecent or recent
	end
	Layout()
	if anyRecent and not undim then
		undim = C_Timer.NewTimer(UNDIM_CHECK, function()
			undim = nil
			ns.GatherPins_Refresh()
		end)
	end
end

local function Resize()
	if used > 0 or linesUsed > 0 then
		Layout()
	end
end

-- Hooks the world map once (hooksecurefunc can't be undone: Refresh shows nothing while Gathering or the pins are off).
function ns.GatherPins_Init(saved, owner)
	db, module = saved, owner
	if hooked or not WorldMapFrame then
		return
	end
	hooked = true
	WorldMapFrame:HookScript("OnShow", ns.GatherPins_Refresh)
	hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.GatherPins_Refresh)
	hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Resize)
	hooksecurefunc(WorldMapFrame, "OnCanvasSizeChanged", Resize)
end

-- Off: no pins left on the map (the module or the setting was switched off).
function ns.GatherPins_Clear()
	HideAll()
	HideLines()
end
