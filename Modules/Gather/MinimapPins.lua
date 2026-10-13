local addonName, ns = ...

-- Gathering node spots on the minimap: a hollow ring on each spot of the player's map within the minimap's view,
-- turning with a rotating minimap, round or square. While following a route (Follow.lua) its legs are drawn too and
-- the followed spot sits on the edge when it's out of view. Geometry in MinimapData.lua (pure). Plain frames on the
-- minimap, no mouse (clicks and pings stay the minimap's). Registered in Gather.lua.

-- Hollow, and wider than Blizzard's node blip (about 14 pixels): the blip is drawn by the minimap itself, under any
-- frame on it, so a spawned node shows inside our ring instead of under it.
local RING = ns.Theme.MEDIA .. "Gather\\Ring"
local PIN = 20 -- pixels
local FOLLOWED_PIN = 22
local PIN_ALPHA = 0.8
local RECENT_ALPHA = 0.35 -- a spot gathered in the last few minutes
local LINE = 2 -- route line thickness in pixels
local LINE_ALPHA = 0.6
local PICK = 1 -- seconds between choosing the spots and legs near the player
local PICK_RANGE = 2 -- view radii around the player that are chosen (room for moving and zooming out until the next pick)

local UI = ns.UI

local db, module
local holder
local pins, pinsUsed = {}, 0
local lines, linesUsed = {}, 0
local followPin

local mapID, mapW, mapH -- the player's map and its size in yards
local spots = {} -- the player's map's spots (GatherNodes_List)
local near = {} -- spots within PICK_RANGE, with .recent set at the pick
local legs = {} -- route legs near the player: { a, b } spots of the followed route
local pickAt = 0
local round, rotate = true, false

local events = ns.Gather_Events

local function NewPin(size)
	local pin = CreateFrame("Frame", nil, holder)
	pin:SetSize(size, size)
	pin.ring = pin:CreateTexture(nil, "ARTWORK")
	pin.ring:SetAllPoints()
	pin.ring:SetTexture(RING)
	return pin
end

local function Dress(pin, spot, followed)
	pin.spot, pin.theme = spot, ns.Theme.name -- dressed again after a theme switch
	pin.ring:SetVertexColor(UI.Color(followed and "accent" or "frame"))
end

local function HideFrom(list, from, to)
	for i = from, to do
		list[i]:Hide()
	end
end

local function Facing()
	local f = GetPlayerFacing()
	return f and ns.Readable(f) and f or nil
end

-- Picking: once a second ------------------------------------------------------------------------------------------

local function Pick(px, py, radius)
	pickAt = GetTime() + PICK
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND" -- the LibDBIcon convention; Blizzard's is round
	round = shape == "ROUND"
	rotate = C_CVar.GetCVarBool("rotateMinimap")
	local range = radius * PICK_RANGE
	wipe(near)
	for _, spot in ipairs(spots) do
		local e, n = ns.GatherMini_Offset(spot.x, spot.y, px, py, mapW, mapH)
		if e * e + n * n <= range * range then
			spot.recent = ns.GatherRoute_IsRecent(mapID, spot.pos)
			near[#near + 1] = spot
		end
	end
	wipe(legs)
	local route, rspots, rmap, w, h = ns.GatherFollow_Route()
	local fx, fy
	if rmap then
		fx, fy = ns.Gather_PlayerPos(rmap)
	end
	if not fx then
		return
	end
	local order = route.order
	for i = 1, #order do
		local a, b = rspots[order[i]], rspots[order[i % #order + 1]]
		local ax, ay = ns.GatherMini_Offset(a.x, a.y, fx, fy, w, h)
		local bx, by = ns.GatherMini_Offset(b.x, b.y, fx, fy, w, h)
		if ns.GatherMini_Clip(ax, ay, bx, by, range, true) then
			legs[#legs + 1] = { a, b }
		end
	end
end

-- Every frame -----------------------------------------------------------------------------------------------------

local function Update()
	local radius = C_Minimap.GetViewRadius()
	local px, py = ns.Gather_PlayerPos(mapID)
	if not (px and radius and radius > 0) then
		HideFrom(pins, 1, pinsUsed)
		HideFrom(lines, 1, linesUsed)
		if followPin then
			followPin:Hide()
		end
		return
	end
	if GetTime() >= pickAt then
		Pick(px, py, radius)
	end
	local half = Minimap:GetWidth() / 2
	local scale = half / radius -- pixels per yard
	local facing = rotate and Facing() or nil
	local followMap, followPos = ns.GatherFollow_Spot()

	local used = 0
	local edge = half - PIN / 2
	for _, spot in ipairs(near) do
		if not (followMap == mapID and followPos == spot.pos) then
			local e, n = ns.GatherMini_Offset(spot.x, spot.y, px, py, mapW, mapH, facing)
			local x, y = e * scale, n * scale
			if ns.GatherMini_Inside(x, y, edge, round) then
				used = used + 1
				local pin = pins[used]
				if not pin then
					pin = NewPin(PIN)
					pins[used] = pin
				end
				if pin.spot ~= spot or pin.theme ~= ns.Theme.name then
					Dress(pin, spot, false)
				end
				pin:SetAlpha(spot.recent and RECENT_ALPHA or PIN_ALPHA)
				pin:SetPoint("CENTER", holder, "CENTER", x, y)
				pin:Show()
			end
		end
	end
	HideFrom(pins, used + 1, pinsUsed)
	pinsUsed = used

	-- The followed route: its legs, and the followed spot (on the edge when out of view).
	local _, _, rmap, w, h, spot = ns.GatherFollow_Route()
	local fx, fy
	if rmap then
		fx, fy = ns.Gather_PlayerPos(rmap)
	end
	used = 0
	if fx then
		local r, g, b = UI.Color("accent")
		for _, leg in ipairs(legs) do
			local ax, ay = ns.GatherMini_Offset(leg[1].x, leg[1].y, fx, fy, w, h, facing)
			local bx, by = ns.GatherMini_Offset(leg[2].x, leg[2].y, fx, fy, w, h, facing)
			local x1, y1, x2, y2 = ns.GatherMini_Clip(ax * scale, ay * scale, bx * scale, by * scale, half - 1, round)
			if x1 then
				used = used + 1
				local line = lines[used]
				if not line then
					line = holder:CreateLine(nil, "BORDER")
					line:SetThickness(LINE)
					lines[used] = line
				end
				line:SetColorTexture(r, g, b, LINE_ALPHA)
				line:SetStartPoint("CENTER", holder, x1, y1)
				line:SetEndPoint("CENTER", holder, x2, y2)
				line:Show()
			end
		end
		if not followPin then
			followPin = NewPin(FOLLOWED_PIN)
			followPin:SetFrameLevel(holder:GetFrameLevel() + 2)
		end
		if followPin.spot ~= spot or followPin.theme ~= ns.Theme.name then
			Dress(followPin, spot, true)
		end
		local e, n = ns.GatherMini_Offset(spot.x, spot.y, fx, fy, w, h, facing)
		local x, y = e * scale, n * scale
		local inner = half - FOLLOWED_PIN / 2
		if not ns.GatherMini_Inside(x, y, inner, round) then
			x, y = ns.GatherMini_Clamp(x, y, inner, round)
		end
		followPin:SetPoint("CENTER", holder, "CENTER", x, y)
		followPin:Show()
	elseif followPin then
		followPin:Hide()
	end
	HideFrom(lines, used + 1, linesUsed)
	linesUsed = used
end

-- Start, stop, refresh --------------------------------------------------------------------------------------------

local function HideAll()
	if holder then
		holder:Hide()
	end
end

-- Reads the player's map and its spots again, and runs the per-frame update only while there's something to draw.
function ns.GatherMini_Refresh()
	if not (module and module.active and db.minimapPins and Minimap) then
		HideAll()
		return
	end
	local kinds = ns.GatherPins_Kinds()
	local best = C_Map.GetBestMapForUnit("player")
	mapID = best and ns.Readable(best) and best or nil
	spots = (kinds ~= false and mapID) and ns.GatherNodes_List(db, mapID, kinds) or {}
	if mapID then
		mapW, mapH = C_Map.GetMapWorldSize(mapID)
	end
	pickAt = 0
	for _, pin in ipairs(pins) do
		pin.spot = nil
	end
	local following = ns.GatherFollow_Active()
	if not (mapID and mapW and mapW > 0 and (#spots > 0 or following)) then
		HideAll()
		return
	end
	if not holder then
		holder = CreateFrame("Frame", nil, Minimap)
		holder:SetAllPoints(Minimap)
		holder:SetScript("OnUpdate", Update)
	end
	holder:SetFrameLevel(Minimap:GetFrameLevel() + 3)
	holder:Show()
end

local function Changed()
	ns.GatherMini_Refresh()
end

local ZONE_EVENTS = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD" }
for _, event in ipairs(ZONE_EVENTS) do
	events:On("minimap", event, Changed)
end

function ns.GatherMini_Start()
	for _, event in ipairs(ZONE_EVENTS) do
		events:Watch("minimap", event)
	end
	ns.GatherMini_Refresh()
end

function ns.GatherMini_Stop()
	events:UnwatchAll("minimap")
	HideAll()
end

function ns.GatherMini_Init(saved, owner)
	db, module = saved, owner
end
