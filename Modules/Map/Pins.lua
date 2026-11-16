local addonName, ns = ...

-- Tomte map: everything on the art. You (an arrow turned your way) and your party, the quests in your log (the active
-- one larger, with its area drawn on its zone as the game's map does), flight masters, dungeon entrances (a click opens
-- the Dungeon journal), town markers (mailboxes, bankers ...: Data/Forever/Townsfolk.lua, picked in the map's
-- tracking menu; those of a kind close together share one pin) and your map pin. Pins sit on a layer over the view
-- that isn't scaled, so they keep their size at any zoom; Window.lua tells them where canvas points land
-- (ns.MapPins_Layout). Art and canvas boxes in Art.lua.

local ARROW = "Interface\\Minimap\\MinimapArrow"
local RING = ns.Theme.MEDIA .. "Gather\\Ring" -- a thin white ring, tinted
local DOT = "Interface\\Buttons\\WHITE8X8"
local TURN_IN = "Interface\\GossipFrame\\ActiveQuestIcon" -- the gold "?"
local TAXI = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" -- if a node's atlas isn't on this client
local WAYPOINT_ATLAS = "Waypoint-MapPin-Tracked"
local SIZE = { arrow = 34, party = 10, quest = 18, active = 22, taxi = 16, dungeon = 20, waypoint = 22, -- pixels
	town = 14 }
-- Frame levels over the pin layer: places, then quests (one level each, so overlapping ones always stack the same
-- way), then the map pin, your party and you.
local LEVEL = { town = 1, taxi = 2, dungeon = 3, quest = 10, waypoint = 200, spot = 205, focus = 207, party = 210,
	arrow = 220 }
local FOCUS_SIZE, FOCUS_PULSE = 26, 1.2 -- pixels, and seconds per pulse of the ring round a spot shown from elsewhere
-- That ring stays this many seconds (the flight there takes one or two), then fades out over FOCUS_FADE.
local FOCUS_LASTS, FOCUS_FADE = 7, 0.8
-- When the map opens, rings pulse out from you a few times so the eye finds you (as the game's map shows you).
local PING_TIMES, PING_SECONDS, PING_FROM, PING_TO = 3, 0.9, 0.6, 2.6 -- pulses, seconds each, ring size in arrows
local HOVER_SCALE = 1.5 -- a quest pin while its row in the side panel is under the mouse
local FAN_GAP = 0.85 -- quest pins closer than this many of their widths gather and ring out (Data.lua, Map_Clusters)
local FAN_EASE = 0.35 -- share of the way a pin moves toward its place in its ring each layout (no jumps as groups form)
local AREA_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local AREA_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"
-- Of 255, fill and border: over the ground pictures as light as the minimap's (Modules/QuestList/Minimap.lua), which
-- lets the terrain show; over the zone maps' bright parchment the game's own (QuestBlobPinMixin:OnLoad), or it's hard
-- to see. Between the two as the ground pictures fade in.
local AREA_LIGHT, AREA_STRONG = { 56, 128 }, { 128, 192 }
local UNDISCOVERED_ALPHA = 0.4
local FACTION = { Neutral = 0, Horde = 1, Alliance = 2 } -- Enum.FlightPathFaction
local SIDE = { Horde = "H", Alliance = "A" } -- Townsfolk.lua's sides
-- Town markers of a kind closer than this many of their widths become one pin, its tooltip listing them all.
local TOWN_GAP = 1.1
local TRACKING = "Interface\\Minimap\\Tracking\\"

local UI = ns.UI

local layer, db
local pools = {} -- [kind] = { used = n, list }
local quests = {} -- { questID, mapID, x, y, ready }
local taxis, dungeons = nil, nil -- read once (they don't change)
local towns = {} -- [kind] = Map_TownRows' rows with cx, cy (canvas) added: read the first time a kind is shown
local townSpots = {} -- this layout's town spots on the view, { x, y, row }, kept between layouts (no garbage)
local waypoint -- { mapID, x, y }
local spot -- { mapID, x, y }: a place a side panel row points at (a teleport's destination)
local focus -- { mapID, x, y, label }: a place another module asked the map to show (ns.MapWindow_ShowSpot)
local focusPin -- its own frame, not pooled: pooled pins hide and show on every layout, which would restart the pulse
local hovered -- questID whose row in the side panel is under the mouse
local order = {} -- the quests' drawing order (Data.lua, Map_DrawOrder), made when they're read
local level = "world"
local zoomGrow, questGrow = 1, 1 -- pins grow as you zoom in close (Data.lua, Map_PinGrow); quest buttons less
local GROW, QUEST_GROW = 1.6, 1.3 -- the most they grow
local blobQuest
local arrow
local party = {} -- unit tokens shown

-- Pins ----------------------------------------------------------------------------------------------------------------

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
	local grow = (kind == "quest" or kind == "active") and questGrow or zoomGrow
	local size = SIZE[kind] * (db and db.pinScale or 1) * grow
	pin:SetSize(size, size)
	pin.ring:Hide()
	pin:SetAlpha(1)
	pin.tip, pin.click, pin.hint = nil, nil, nil
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
	pin.iconKey = nil
	pin.icon:SetTexture(DOT)
	pin.icon:SetVertexColor(UI.Color(role))
	if not pin.mask then
		pin.mask = UI.CircleMask(pin.icon, pin)
	end
	pin.ring:SetTexture(RING)
	pin.ring:SetVertexColor(UI.Color("frameDark"))
	pin.ring:Show()
end

-- The game's quest button art on a pin (Core/QuestPin.lua); false when this client lacks it.
local function QuestLook(pin, active, ready)
	if not ns.QuestPin_Look(pin, pin:GetWidth(), active, ready) then
		return false
	end
	if pin.iconKey ~= false then
		pin.iconKey = false
		pin.icon:SetTexture(nil)
	end
	return true
end

-- A pin's icon: atlas, or texture where this client lacks it. Set again only when it changed (pins are placed again
-- every frame the view moves, and setting an atlas isn't free).
local function Icon(pin, atlas, texture)
	local key = (atlas or "") .. "|" .. tostring(texture)
	if pin.iconKey == key then
		return
	end
	pin.iconKey = key
	if pin.mask then
		pin.icon:RemoveMaskTexture(pin.mask)
		pin.mask = nil
	end
	pin.icon:SetTexCoord(0, 1, 0, 1)
	if not (atlas and pin.icon:SetAtlas(atlas)) then
		pin.icon:SetTexture(texture)
	end
end

-- Reading -------------------------------------------------------------------------------------------------------------

-- A position from the API: a Vector2D, or on Forever sometimes a plain { x, y } without its methods (a map pin's and
-- some places' positions errored on GetXY, 2026-11-15).
local function Pos(v)
	if type(v) ~= "table" then
		return nil
	end
	local x, y
	if type(v.GetXY) == "function" then
		x, y = v:GetXY()
	else
		x, y = v.x, v.y
	end
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
	order = ns.Map_DrawOrder(quests)
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
			local key = e.name
			local x, y = Pos(e.position)
			if x and not seen[key] then
				seen[key] = true
				dungeons[#dungeons + 1] = { mapID = z.mapID, x = x, y = y, name = e.name, atlas = e.atlasName,
					description = e.description }
			end
		end
	end
	-- The game lists no entrances on Forever's zone maps (measured 2026-11-15): the Dungeon journal's data has them
	-- (Data/Forever/DungeonJournal.lua, door = { map, x, y in percent }).
	for _, d in ipairs(ns.Content_Get(ns.CONTENT_FOREVER, "dungeonJournal") or {}) do
		local door = d.door
		if door and not seen[d.name] and ns.MapArt_Box(door.map) then
			seen[d.name] = true
			local levels = d.min and (d.max and ("Level %d-%d"):format(d.min, d.max) or ("Level %d+"):format(d.min))
			dungeons[#dungeons + 1] = { mapID = door.map, x = door.x / 100, y = door.y / 100, name = d.name,
				description = levels, id = d.id }
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

-- Tooltips and clicks -------------------------------------------------------------------------------------------------

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

-- Ctrl-click on your map pin: gone, with its tracking (ns.ClearOwnPin), or the Quest list's follow went on stepping
-- aside for a pin no longer there (measured 2026-11-15).
local function RemovePin()
	if IsControlKeyDown() then
		ns.ClearOwnPin()
	end
end

local function NameTip(pin)
	UI.TipLine(pin.name or "", "heading")
	if pin.note then
		UI.TipLine(pin.note, "textMuted", true)
	end
	if pin.hint then
		UI.TipLine(pin.hint, "textMuted")
	end
end

-- A dungeon entrance from the Dungeon journal's data: a click opens it there.
local function DungeonClick(pin)
	ns.DJ_Open(pin.instanceID)
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
		local ground = ns.MapMini_Showing()
		blob:SetFillAlpha(math.floor(AREA_STRONG[1] + (AREA_LIGHT[1] - AREA_STRONG[1]) * ground + 0.5))
		blob:SetBorderAlpha(math.floor(AREA_STRONG[2] + (AREA_LIGHT[2] - AREA_STRONG[2]) * ground + 0.5))
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

local onView = {} -- this layout's quest pins on the view: { pin, x, y, key }, then tx, ty (Map_Clusters)
local shownAt = {} -- [questID] = { x, y }: where each pin is drawn from its spot now (eased toward its ring place)

local function LayoutQuests(toView)
	Release("quest")
	Release("active")
	if not db.quests or level == "world" then
		return
	end
	local active = ns.ActiveQuest_ID()
	local gap = SIZE.quest * (db.pinScale or 1) * questGrow * FAN_GAP
	wipe(onView)
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
		-- One level each, south on top; the active quest over all of them, the one hovered in the side panel over that.
		local top = q.questID == hovered
		if top then
			local size = pin:GetWidth() * HOVER_SCALE
			pin:SetSize(size, size)
			QuestLook(pin, isActive, q.ready)
		end
		pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.quest + (top and #quests + 2 or isActive and #quests + 1 or rank))
		pin.questID, pin.ready, pin.tip, pin.click = q.questID, q.ready, QuestTip, QuestClick
		local cx, cy = ns.MapArt_ToCanvas(q.mapID, q.x, q.y)
		local vx, vy
		if cx then
			vx, vy = toView(cx, cy)
		end
		if vx then
			onView[#onView + 1] = { pin = pin, x = vx, y = vy, key = q.questID }
		else
			pin:Hide()
		end
	end
	-- Pins that overlap ring out round their middle; each eases there, so groups forming as you zoom don't jump.
	ns.Map_Clusters(onView, gap)
	local moving = false
	for _, s in ipairs(onView) do
		local want = shownAt[s.key]
		local dx, dy = s.tx - s.x, s.ty - s.y
		if not want then
			want = { x = dx, y = dy }
			shownAt[s.key] = want
		else
			want.x = want.x + (dx - want.x) * FAN_EASE
			want.y = want.y + (dy - want.y) * FAN_EASE
			if math.abs(dx - want.x) + math.abs(dy - want.y) > 0.5 then
				moving = true
			else
				want.x, want.y = dx, dy
			end
		end
		s.pin:ClearAllPoints()
		s.pin:SetPoint("CENTER", layer, "CENTER", s.x + want.x, -(s.y + want.y))
	end
	if moving and ns.MapWindow_Relayout then
		ns.MapWindow_Relayout()
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
			if d.id and ns.DJ_Open then
				pin.instanceID, pin.click = d.id, DungeonClick
				pin.hint = "Click: open it in the Dungeon journal"
			end
			Put(pin, d.mapID, d.x, d.y, toView)
		end
	end
end

-- Town markers --------------------------------------------------------------------------------------------------------

-- One kind's rows for you: your side, your class's trainers, with their canvas spots (they never move).
local function TownRows(kind)
	local rows = towns[kind]
	if rows then
		return rows
	end
	local data = ns.Content_Get(ns.CONTENT_FOREVER, "townsfolk") or {}
	rows = {}
	local side, class = SIDE[UnitFactionGroup("player") or ""], select(2, UnitClass("player"))
	for _, r in ipairs(ns.Map_TownRows(data[kind], side, class)) do
		r.cx, r.cy = ns.MapArt_ToCanvas(r.mapID, r.x, r.y)
		if r.cx then
			rows[#rows + 1] = r
		end
	end
	towns[kind] = rows
	return rows
end

-- One marker: its name and what it is. A group: what they are, then each one's name and title (mailboxes have none:
-- their count).
local function TownTip(pin)
	local list = pin.rows
	if #list == 1 then
		local r = list[1]
		UI.TipLine(r.name or pin.kindName, "heading")
		if r.name then
			UI.TipLine(r.title or pin.kindName, "textMuted")
		end
		return
	end
	UI.TipLine(pin.kindName, "heading")
	local named = 0
	for _, r in ipairs(list) do
		if r.name then
			named = named + 1
			local lr, lg, lb = UI.Color("text")
			local rr, rg, rb = UI.Color("textMuted")
			GameTooltip:AddDoubleLine(r.name, r.title or "", lr, lg, lb, rr, rg, rb)
		end
	end
	if named == 0 then
		UI.TipLine(("%d here"):format(#list), "textMuted")
	end
end

-- Only at the zones' level: zoomed out they'd bury the continents. Only spots on the view are looked at (there are
-- hundreds), and those of a kind close together on the view share one pin (Data.lua, Map_Group).
local function LayoutTowns(toView)
	Release("town")
	if level ~= "zone" or not db.town then
		return
	end
	local gap = SIZE.town * (db.pinScale or 1) * zoomGrow * TOWN_GAP
	for _, kind in ipairs(ns.MAP_TOWN_KINDS) do
		if db.town[kind.key] then
			local n = 0
			for _, r in ipairs(TownRows(kind.key)) do
				local vx, vy = toView(r.cx, r.cy)
				if vx then
					n = n + 1
					local s = townSpots[n] or {}
					townSpots[n] = s
					s.x, s.y, s.row = vx, vy, r
				end
			end
			local kindName = _G[kind.global] or kind.name
			for _, g in ipairs(ns.Map_Group(townSpots, n, gap)) do
				local pin = Acquire("town")
				Icon(pin, nil, TRACKING .. kind.icon)
				pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.town)
				pin.rows = pin.rows or {}
				wipe(pin.rows)
				for i, m in ipairs(g.members) do
					pin.rows[i] = townSpots[m].row
				end
				pin.kindName, pin.tip = kindName, TownTip
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", layer, "CENTER", g.x, -g.y)
			end
		end
	end
end

local function LayoutWaypoint(toView)
	Release("waypoint")
	if waypoint then
		local pin = Acquire("waypoint")
		Icon(pin, WAYPOINT_ATLAS, RING)
		pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.waypoint)
		pin.name, pin.note, pin.tip = MAP_PIN or "Map pin", "Ctrl-click to remove it", NameTip
		pin.click = RemovePin
		Put(pin, waypoint.mapID, waypoint.x, waypoint.y, toView)
	end
	Release("spot")
	if spot then
		local pin = Acquire("spot")
		pin:EnableMouse(false)
		Icon(pin, WAYPOINT_ATLAS, RING)
		pin.icon:SetVertexColor(UI.Color("accent"))
		pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.spot)
		Put(pin, spot.mapID, spot.x, spot.y, toView)
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

-- The focus: the map pin's art in the accent colour, a ring pulsing out of it, its label on hover.
local function FocusPin()
	if focusPin then
		return focusPin
	end
	local pin = CreateFrame("Frame", nil, layer)
	pin:SetSize(FOCUS_SIZE, FOCUS_SIZE)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	if not pin.icon:SetAtlas(WAYPOINT_ATLAS) then
		pin.icon:SetTexture(RING)
	end
	pin.icon:SetVertexColor(UI.Color("accent"))
	pin.halo = pin:CreateTexture(nil, "ARTWORK")
	pin.halo:SetPoint("CENTER")
	pin.halo:SetSize(FOCUS_SIZE * 1.4, FOCUS_SIZE * 1.4)
	pin.halo:SetTexture(RING)
	pin.halo:SetVertexColor(UI.Color("accent"))
	local pulse = pin.halo:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local grow = pulse:CreateAnimation("Scale")
	grow:SetScaleFrom(0.6, 0.6)
	grow:SetScaleTo(1.8, 1.8)
	grow:SetDuration(FOCUS_PULSE)
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(FOCUS_PULSE)
	pin.pulse = pulse
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", function(self)
		if self.label then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			UI.TipLine(self.label, "heading")
			GameTooltip:Show()
		end
	end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnShow", function(self)
		self.pulse:Play()
	end)
	focusPin = pin
	return pin
end

local function LayoutFocus(toView)
	if not focus then
		if focusPin then
			focusPin:Hide()
		end
		return
	end
	local pin = FocusPin()
	pin.label = focus.label
	pin:SetFrameLevel(layer:GetFrameLevel() + LEVEL.focus)
	pin:Show()
	Put(pin, focus.mapID, focus.x, focus.y, toView)
end

local function LayoutUnits(toView)
	if not arrow then
		arrow = CreateFrame("Frame", nil, layer)
		arrow:EnableMouse(false)
		arrow.tex = arrow:CreateTexture(nil, "OVERLAY")
		arrow.tex:SetAllPoints()
		arrow.tex:SetTexture(ARROW)
		-- The ping: a ring round you, grown and faded out a few times (ns.MapPins_PingPlayer).
		arrow.ring = arrow:CreateTexture(nil, "ARTWORK")
		arrow.ring:SetPoint("CENTER")
		arrow.ring:SetTexture(RING)
		arrow.ring:SetVertexColor(UI.Color("accent"))
		arrow.ring:SetAlpha(0)
		local ping = arrow.ring:CreateAnimationGroup()
		local grow = ping:CreateAnimation("Scale")
		grow:SetScaleFrom(PING_FROM, PING_FROM)
		grow:SetScaleTo(PING_TO, PING_TO)
		grow:SetDuration(PING_SECONDS)
		grow:SetSmoothing("OUT")
		local fade = ping:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(PING_SECONDS)
		fade:SetSmoothing("IN")
		ping:SetLooping("REPEAT")
		ping:SetScript("OnLoop", function(self)
			self.left = (self.left or 1) - 1
			if self.left <= 0 then
				self:Stop()
			end
		end)
		arrow.ping = ping
	end
	arrow.ring:SetSize(SIZE.arrow * db.pinScale, SIZE.arrow * db.pinScale)
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
				pin.iconKey = nil
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

-- From the window -----------------------------------------------------------------------------------------------------

function ns.MapPins_Init(pinLayer, moduleDB)
	layer, db = pinLayer, moduleDB
end

-- The view moved or zoomed: everything placed again.
function ns.MapPins_Layout(toView, artLevel, zoom)
	level = artLevel
	zoomGrow, questGrow = ns.Map_PinGrow(zoom or 1, GROW), ns.Map_PinGrow(zoom or 1, QUEST_GROW)
	LayoutQuests(toView)
	LayoutPlaces(toView)
	LayoutTowns(toView)
	LayoutWaypoint(toView)
	LayoutFocus(toView)
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

-- Window.lua, as the map opens: rings pulse out from you.
function ns.MapPins_PingPlayer()
	if arrow and arrow.ping then
		arrow.ping:Stop()
		arrow.ping.left = PING_TIMES
		arrow.ping:Play()
	end
end

-- The side panel: the spot a quest pin sits on (mapID, x, y), or nil when it has none on the map.
function ns.MapPins_QuestSpot(questID)
	for _, q in ipairs(quests) do
		if q.questID == questID then
			return q.mapID, q.x, q.y
		end
	end
end

-- The zone a quest belongs to (its region in Art.lua), for zooming to it.
function ns.MapPins_QuestZone(questID)
	return QuestZone(questID)
end

-- The side panel: the quest whose row is under the mouse (its pin grows and comes to the top), or nil.
function ns.MapPins_Hover(questID)
	if hovered ~= questID then
		hovered = questID
		if ns.MapWindow_Relayout then
			ns.MapWindow_Relayout()
		end
	end
end

-- A place another module asked the map to show (mapID, x, y on it, a label for its tooltip), or nil to take it away.
-- Its ring fades out after FOCUS_LASTS seconds.
local focusTimer

local function FocusGone()
	focus = nil
	if focusPin then
		focusPin:Hide()
		focusPin:SetAlpha(1)
	end
	if ns.MapWindow_Relayout then
		ns.MapWindow_Relayout()
	end
end

function ns.MapPins_Focus(mapID, x, y, label)
	if focusTimer then
		focusTimer:Cancel()
		focusTimer = nil
	end
	if focusPin then
		UI.TweenStop(focusPin, "fade")
		focusPin:SetAlpha(1)
	end
	focus = mapID and { mapID = mapID, x = x, y = y, label = label } or nil
	if focus then
		-- It has done its job once the eye has found it: it fades out by itself.
		focusTimer = C_Timer.NewTimer(FOCUS_LASTS, function()
			focusTimer = nil
			if not (focusPin and focusPin:IsShown()) then
				FocusGone()
				return
			end
			UI.Tween(focusPin, "fade", FOCUS_FADE, function(t)
				focusPin:SetAlpha(1 - t)
			end, FocusGone)
		end)
	end
	if ns.MapWindow_Relayout then
		ns.MapWindow_Relayout()
	end
end

-- A side panel row's place on the map (mapID, x, y on it), or nil to take it away.
function ns.MapPins_Spot(mapID, x, y)
	spot = mapID and { mapID = mapID, x = x, y = y } or nil
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
