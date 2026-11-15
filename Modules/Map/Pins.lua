local addonName, ns = ...

-- Tomte map: everything on the art. You (an arrow turned your way) and your party, the quests in your log (the active
-- one larger, with its area drawn on its zone as the game's map does), flight masters, dungeon entrances and your map
-- pin. Pins sit on a layer over the view that isn't scaled, so they keep their size at any zoom; Window.lua tells them
-- where canvas points land (ns.MapPins_Layout). Art and canvas boxes in Art.lua.

local ARROW = "Interface\\Minimap\\MinimapArrow"
local RING = ns.Theme.MEDIA .. "Gather\\Ring" -- a thin white ring, tinted
local DOT = "Interface\\Buttons\\WHITE8X8"
local TURN_IN = "Interface\\GossipFrame\\ActiveQuestIcon" -- the gold "?"
local TAXI = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" -- if a node's atlas isn't on this client
local WAYPOINT_ATLAS = "Waypoint-MapPin-Tracked"
local SIZE = { arrow = 28, party = 10, quest = 18, active = 22, taxi = 16, dungeon = 20, waypoint = 22 } -- pixels
-- Quest pins in the game's own look (Blizzard_POIButton: POIButton.lua, POIButton.xml): a round button, the active
-- quest's one lit and glowing, an icon on it; its button art is 32 pixels on a 20-pixel button, the glow 50.
local QUEST_ATLAS = {
	button = "UI-QuestPoi-QuestNumber", activeButton = "UI-QuestPoi-QuestNumber-SuperTracked",
	glow = "UI-QuestPoi-OuterGlow", highlight = "UI-QuestPoi-InnerGlow",
	progress = "Quest-In-Progress-Icon-yellow", activeProgress = "Quest-In-Progress-Icon-Brown",
	ready = "UI-QuestIcon-TurnIn-Normal",
}
local QUEST_ART, QUEST_GLOW, QUEST_ICON = 32 / 20, 50 / 20, 0.8 -- sizes as shares of the pin
-- Frame levels over the pin layer: places, then quests (one level each, so overlapping ones always stack the same
-- way), then the map pin, your party and you.
local LEVEL = { taxi = 2, dungeon = 3, quest = 10, waypoint = 200, party = 210, arrow = 220 }
local AREA_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local AREA_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"
local AREA_FILL_ALPHA, AREA_BORDER_ALPHA = 128, 192 -- of 255, as the map's own (QuestBlobPinMixin:OnLoad)
local UNDISCOVERED_ALPHA = 0.4
local FACTION = { Neutral = 0, Horde = 1, Alliance = 2 } -- Enum.FlightPathFaction

local UI = ns.UI

local layer, db
local pools = {} -- [kind] = { used = n, list }
local quests = {} -- { questID, mapID, x, y, ready }
local taxis, dungeons = nil, nil -- read once (they don't change)
local waypoint -- { mapID, x, y }
local level = "world"
local blobQuest
local arrow
local party = {} -- unit tokens shown

-- Pins ------------------------------------------------------------------------------------------------------------------

local function Pool(kind)
	local pool = pools[kind]
	if not pool then
		pool = { used = 0, list = {} }
		pools[kind] = pool
	end
	return pool
end

local function Tooltip(pin)
	if not pin.tip then
		return
	end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	pin.tip(pin)
	GameTooltip:Show()
end

local function NewPin(kind)
	local pin = CreateFrame("Button", nil, layer)
	pin.kind = kind
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin.ring = pin:CreateTexture(nil, "OVERLAY")
	pin.ring:SetAllPoints()
	pin:RegisterForClicks("LeftButtonUp")
	pin:SetScript("OnEnter", Tooltip)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", function(self, button)
		if self.click then
			self.click(self, button)
		end
	end)
	return pin
end

local function Acquire(kind)
	local pool = Pool(kind)
	pool.used = pool.used + 1
	local pin = pool.list[pool.used]
	if not pin then
		pin = NewPin(kind)
		pool.list[pool.used] = pin
	end
	local size = SIZE[kind] * (db and db.pinScale or 1)
	pin:SetSize(size, size)
	pin.icon:SetVertexColor(1, 1, 1)
	pin.icon:SetTexCoord(0, 1, 0, 1)
	pin.ring:Hide()
	pin:SetAlpha(1)
	pin.tip, pin.click = nil, nil
	pin:Show()
	return pin
end

local function Release(kind)
	local pool = Pool(kind)
	for i = 1, pool.used do
		pool.list[i]:Hide()
	end
	pool.used = 0
end

local function Disc(pin, role)
	pin.icon:SetTexture(DOT)
	pin.icon:SetVertexColor(UI.Color(role))
	if not pin.mask then
		pin.mask = UI.CircleMask(pin.icon, pin)
	end
	pin.ring:SetTexture(RING)
	pin.ring:SetVertexColor(UI.Color("frameDark"))
	pin.ring:Show()
end

-- The game's quest button art on a pin (made once per pin); false when this client lacks it.
local questLook
local function QuestLook(pin, active, ready)
	if questLook == nil then
		questLook = C_Texture.GetAtlasInfo(QUEST_ATLAS.button) ~= nil
	end
	if not questLook then
		return false
	end
	if not pin.button then
		pin.glow = pin:CreateTexture(nil, "BACKGROUND")
		pin.glow:SetPoint("CENTER")
		pin.glow:SetAtlas(QUEST_ATLAS.glow)
		pin.glow:SetBlendMode("ADD")
		pin.button = pin:CreateTexture(nil, "BORDER")
		pin.button:SetPoint("CENTER")
		pin.mark = pin:CreateTexture(nil, "ARTWORK", nil, 1)
		pin.mark:SetPoint("CENTER")
		pin.lit = pin:CreateTexture(nil, "HIGHLIGHT")
		pin.lit:SetPoint("CENTER")
		pin.lit:SetAtlas(QUEST_ATLAS.highlight)
		pin.lit:SetBlendMode("ADD")
	end
	local size = pin:GetWidth()
	pin.glow:SetSize(size * QUEST_GLOW, size * QUEST_GLOW)
	pin.glow:SetShown(active)
	pin.button:SetSize(size * QUEST_ART, size * QUEST_ART)
	pin.button:SetAtlas(active and QUEST_ATLAS.activeButton or QUEST_ATLAS.button)
	pin.lit:SetSize(size * QUEST_ART, size * QUEST_ART)
	pin.mark:SetSize(size * QUEST_ICON, size * QUEST_ICON)
	pin.mark:SetAtlas(ready and QUEST_ATLAS.ready or active and QUEST_ATLAS.activeProgress or QUEST_ATLAS.progress)
	pin.icon:SetTexture(nil)
	return true
end

local function Icon(pin, atlas, texture)
	if pin.mask then
		pin.icon:RemoveMaskTexture(pin.mask)
		pin.mask = nil
	end
	if not (atlas and pin.icon:SetAtlas(atlas)) then
		pin.icon:SetTexture(texture)
	end
end

-- Reading ---------------------------------------------------------------------------------------------------------------

local function Pos(v)
	if not v then
		return nil
	end
	local x, y = v:GetXY()
	if ns.Readable(x) and ns.Readable(y) and not (x == 0 and y == 0) then
		return x, y
	end
end

-- The quests in your log with a spot on a continent (the continent maps list their zones' quests).
local function ReadQuests()
	wipe(quests)
	for _, c in ipairs(ns.MapArt_Continents()) do
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(c.mapID) or {}) do
			if info.questID and info.x and info.y and not ns.IsSecret(info.x, info.y) then
				quests[#quests + 1] = {
					questID = info.questID, mapID = c.mapID, x = info.x, y = info.y,
					ready = C_QuestLog.ReadyForTurnIn(info.questID) or C_QuestLog.IsComplete(info.questID),
				}
			end
		end
	end
end

local function PlayerFaction()
	local group = UnitFactionGroup("player")
	return FACTION[group]
end

local function ReadStatic()
	taxis, dungeons = {}, {}
	local mine = PlayerFaction()
	for _, c in ipairs(ns.MapArt_Continents()) do
		for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(c.mapID) or {}) do
			local x, y = Pos(node.position)
			if x and (not node.faction or node.faction == FACTION.Neutral or node.faction == mine) then
				taxis[#taxis + 1] = { mapID = c.mapID, x = x, y = y, name = node.name, atlas = node.atlasName,
					undiscovered = node.isUndiscovered }
			end
		end
	end
	local seen = {}
	for _, z in ipairs(ns.MapArt_Zones()) do
		for _, e in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(z.mapID) or {}) do
			local key = e.journalInstanceID or e.name
			local x, y = Pos(e.position)
			if x and not seen[key] then
				seen[key] = true
				dungeons[#dungeons + 1] = { mapID = z.mapID, x = x, y = y, name = e.name, atlas = e.atlasName,
					description = e.description }
			end
		end
	end
end

local function ReadWaypoint()
	local point = C_Map.GetUserWaypoint()
	local x, y
	if point then
		x, y = Pos(point.position)
	end
	waypoint = x and { mapID = point.uiMapID, x = x, y = y } or nil
end

-- Tooltips and clicks ---------------------------------------------------------------------------------------------------

local function QuestTip(pin)
	local id = pin.questID
	UI.TipLine(C_QuestLog.GetTitleForQuestID(id) or tostring(id), "heading")
	if pin.ready then
		UI.TipLine(QUEST_WATCH_QUEST_READY or "Ready to turn in", "success")
	else
		for _, o in ipairs(ns.QuestListRead_Objectives(id)) do
			UI.TipLine(ns.QuestList_ObjectiveText(o), o.finished and "textFaint" or "text")
		end
	end
	if ns.ActiveQuest_ID() ~= id then
		UI.TipLine("Click: make it your active quest", "textMuted")
	end
end

local function QuestClick(pin)
	ns.LevelingPage_MakeActive(pin.questID, function()
		ns.MapPins_Quests()
	end)
end

local function NameTip(pin)
	UI.TipLine(pin.name or "", "heading")
	if pin.note then
		UI.TipLine(pin.note, "textMuted", true)
	end
end

-- The active quest's area --------------------------------------------------------------------------------------------

-- One area frame, laid out the way the game's map does it: a direct child of the canvas, the size of the map it
-- draws (QuestBlobDataProviderMixin), drawn again after every zoom (ns.MapPins_RedrawArea). Drawn once and then
-- scaled or moved, it landed in the wrong place and drifted with the zoom (measured 2026-11-15).
local blob
local blobZone

local function AreaFrame(canvas)
	if not blob then
		blob = CreateFrame("QuestPOIFrame", nil, canvas)
		blob:EnableMouse(false)
		blob:SetFillTexture(AREA_FILL)
		blob:SetBorderTexture(AREA_BORDER)
		blob:SetFillAlpha(AREA_FILL_ALPHA)
		blob:SetBorderAlpha(AREA_BORDER_ALPHA)
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
		ns.MapWindow_AreaDirty() -- drawn once the layout is done (ns.MapPins_RedrawArea)
	end
	frame:Show()
end

-- Window.lua, after the canvas was placed or scaled: the area drawn for where it now is. Asking for the frame's edge
-- first makes the game place it now, so it's drawn for its new spot in this same frame (drawn before that it landed
-- where the frame was; drawn a frame later it shook during a zoom, measured 2026-11-15).
function ns.MapPins_RedrawArea()
	if blob and blob:IsShown() and blob.drawn then
		blob:GetLeft()
		blob:DrawNone()
		blob:DrawBlob(blob.drawn, true)
	end
end

-- Placing -------------------------------------------------------------------------------------------------------------

-- toView(cx, cy) -> x, y: pixels from the layer's centre (x right, y down), or nil for a point off the view.
local function Put(pin, mapID, x, y, toView)
	local cx, cy = ns.MapArt_ToCanvas(mapID, x, y)
	local vx, vy
	if cx then
		vx, vy = toView(cx, cy)
	end
	if not vx then
		pin:Hide()
		return
	end
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", layer, "CENTER", vx, -vy)
end

local function LayoutQuests(toView)
	Release("quest")
	Release("active")
	if not db.quests or level == "world" then
		return
	end
	local active = ns.ActiveQuest_ID()
	local order = ns.Map_DrawOrder(quests)
	for rank, i in ipairs(order) do
		local q = quests[i]
		local isActive = q.questID == active
		local pin = Acquire(isActive and "active" or "quest")
		if not QuestLook(pin, isActive, q.ready) then
			if q.ready then
				Icon(pin, nil, TURN_IN)
				if isActive then
					pin.ring:SetTexture(RING)
					pin.ring:SetVertexColor(UI.Color("accent"))
					pin.ring:Show()
				end
			else
				Disc(pin, isActive and "accent" or "warning")
			end
		end
		-- One level each, south on top; the active quest over all of them.
		pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.quest + (isActive and #quests + 1 or rank))
		pin.questID, pin.ready, pin.tip, pin.click = q.questID, q.ready, QuestTip, QuestClick
		Put(pin, q.mapID, q.x, q.y, toView)
	end
end

local function LayoutPlaces(toView)
	Release("taxi")
	Release("dungeon")
	if level == "world" then
		return
	end
	if db.taxis then
		for _, t in ipairs(taxis or {}) do
			local pin = Acquire("taxi")
			Icon(pin, t.atlas, TAXI)
			pin:SetAlpha(t.undiscovered and UNDISCOVERED_ALPHA or 1)
			pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.taxi)
			pin.name, pin.note, pin.tip = t.name, nil, NameTip
			Put(pin, t.mapID, t.x, t.y, toView)
		end
	end
	if db.dungeons then
		for _, d in ipairs(dungeons or {}) do
			local pin = Acquire("dungeon")
			Icon(pin, d.atlas, "Interface\\Minimap\\Dungeon")
			pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.dungeon)
			pin.name, pin.note, pin.tip = d.name, d.description, NameTip
			Put(pin, d.mapID, d.x, d.y, toView)
		end
	end
end

local function LayoutWaypoint(toView)
	Release("waypoint")
	if waypoint then
		local pin = Acquire("waypoint")
		Icon(pin, WAYPOINT_ATLAS, RING)
		pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.waypoint)
		pin.name, pin.note, pin.tip = MAP_PIN or "Map pin", nil, NameTip
		Put(pin, waypoint.mapID, waypoint.x, waypoint.y, toView)
	end
end

-- You and your group: read every tick (they move).
local function Where(unit)
	for _, c in ipairs(ns.MapArt_Continents()) do
		local x, y = Pos(C_Map.GetPlayerMapPosition(c.mapID, unit))
		if x then
			return c.mapID, x, y
		end
	end
end

local function LayoutUnits(toView)
	if not arrow then
		arrow = CreateFrame("Frame", nil, layer)
		arrow:EnableMouse(false)
		arrow.tex = arrow:CreateTexture(nil, "OVERLAY")
		arrow.tex:SetAllPoints()
		arrow.tex:SetTexture(ARROW)
	end
	arrow:SetSize(SIZE.arrow * db.pinScale, SIZE.arrow * db.pinScale)
	arrow:SetFrameLevel(layer:GetFrameLevel() + LEVEL.arrow)
	local mapID, x, y = Where("player")
	if mapID then
		arrow:Show()
		Put(arrow, mapID, x, y, toView)
		local facing = GetPlayerFacing()
		arrow.tex:SetRotation(facing and ns.Readable(facing) and facing or 0)
	else
		arrow:Hide()
	end
	Release("party")
	if not db.party then
		return
	end
	wipe(party)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			party[#party + 1] = "raid" .. i
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			party[#party + 1] = "party" .. i
		end
	end
	for _, unit in ipairs(party) do
		if not UnitIsUnit(unit, "player") then
			local m, ux, uy = Where(unit)
			if m then
				local pin = Acquire("party")
				pin.icon:SetTexture(DOT)
				if not pin.mask then
					pin.mask = UI.CircleMask(pin.icon, pin)
				end
				local color = C_ClassColor.GetClassColor(select(2, UnitClass(unit)) or "")
				if color then
					pin.icon:SetVertexColor(color.r, color.g, color.b)
				end
				pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.party)
				pin.name, pin.note, pin.tip = UnitName(unit), nil, NameTip
				Put(pin, m, ux, uy, toView)
			end
		end
	end
end

-- From the window ---------------------------------------------------------------------------------------------------------

function ns.MapPins_Init(pinLayer, moduleDB)
	layer, db = pinLayer, moduleDB
end

-- The view moved or zoomed: everything placed again.
function ns.MapPins_Layout(toView, artLevel)
	level = artLevel
	LayoutQuests(toView)
	LayoutPlaces(toView)
	LayoutWaypoint(toView)
	LayoutUnits(toView)
	DrawAreas(false)
end

-- Every tick while shown: you and your party.
function ns.MapPins_Tick(toView)
	LayoutUnits(toView)
end

-- The map opened: what changes is read again (flight masters and dungeons once a session).
function ns.MapPins_Read()
	if not taxis then
		ReadStatic()
	end
	ReadQuests()
	ReadWaypoint()
end

-- The quest log or the active quest changed.
function ns.MapPins_Quests()
	ReadQuests()
	blobQuest = nil
	if ns.MapWindow_Relayout then
		ns.MapWindow_Relayout()
	end
end

function ns.MapPins_Waypoint()
	ReadWaypoint()
	if ns.MapWindow_Relayout then
		ns.MapWindow_Relayout()
	end
end
