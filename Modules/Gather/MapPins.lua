local addonName, ns = ...

-- Gathering node spots on the world map: a round icon on every mining and herbalism spot Gathering remembers
-- (Nodes.lua), with a tooltip, and a round button in the map's top-right column with a menu (which nodes to show,
-- remember spots, settings). Plain frames on the map canvas, not a map data provider or Blizzard's pin pools
-- (taint, see the World quests marker). Registered in Gather.lua.

local PIN_SIZE = 16 -- screen pixels at any zoom
local RING = 2 -- pixels of ring around the icon
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
local hooked = false
local button

local function ShowTooltip(pin)
	local spot = pin.spot
	local t = spot.objectID and db.nodeTypes[spot.objectID]
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(t and t.name or ns.GATHER_KIND_NAMES[spot.kind], UI.Color("heading"))
	UI.TipLine(ns.GATHER_KIND_NAMES[spot.kind] .. " node", "textMuted")
	local item = t and t.item and C_Item.GetItemNameByID(t.item)
	if item then
		UI.TipLine(item)
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

-- The kinds to show, or nil for all; false when pins are off.
local function Kinds()
	if not (module and module.active) or db.mapPins == "off" then
		return false
	end
	if db.mapPins == "all" then
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
	local size = PIN_SIZE / scale
	local ring = RING / scale
	for i = 1, used do
		local pin = pool[i]
		pin:SetSize(size, size)
		pin.icon:ClearAllPoints()
		pin.icon:SetPoint("TOPLEFT", ring, -ring)
		pin.icon:SetPoint("BOTTOMRIGHT", -ring, ring)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", pin.spot.x * w, -pin.spot.y * h)
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

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Gathering nodes")
		for _, choice in ipairs({ { "mine", "For your professions" }, { "all", "All" }, { "off", "Off" } }) do
			root:CreateRadio(choice[2], function()
				return db.mapPins == choice[1]
			end, function()
				SetPins(choice[1])
			end)
		end
		root:CreateDivider()
		root:CreateCheckbox("Remember node spots", function()
			return db.recordNodes
		end, function()
			db.recordNodes = not db.recordNodes
			ns.Share_Changed("nodes")
		end)
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
	local kinds = Kinds()
	local mapID = WorldMapFrame:GetMapID()
	if kinds == false or not mapID then
		return
	end
	local canvas = WorldMapFrame:GetCanvas()
	local level = WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel(LEVEL_TYPE)
	local r, g, b = UI.Color("frameDark")
	for _, spot in ipairs(ns.GatherNodes_List(db, mapID, kinds)) do
		used = used + 1
		local pin = pool[used]
		if not pin then
			pin = NewPin(canvas)
			pool[used] = pin
		end
		pin.spot = spot
		pin:SetFrameLevel(level)
		pin.ring:SetColorTexture(r, g, b, 0.9)
		pin.icon:SetTexture(Icon(spot))
		pin:Show()
	end
	Layout()
end

local function Resize()
	if used > 0 then
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
end
