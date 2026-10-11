local addonName, ns = ...

-- World quest routes, shared by the World quests map tab and the Gold world quests window: one route at a time that
-- tracks its stops one by one (ns.WQ_Track, so Waypoints shows them), nearest first from where you stand
-- (RouteOrder.lua). Handing in the tracked stop tracks the next one still up. Owners pass a provider that reads the
-- quests still up for their route, so a stop that expired or was done elsewhere is skipped.

local NEXT_DELAY = 1 -- seconds after a turn-in before the next stop is tracked (the map updates first)

local events = ns.NewEvents()
local OWNER = "route"
local route -- { ids, owner, label, provider, earned }
local listeners = {}

-- fn() runs whenever the route starts, moves on or ends (owners redraw their stop numbers).
function ns.WQRoute_Listen(fn)
	listeners[#listeners + 1] = fn
end

local function Changed()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

function ns.WQRoute_Active()
	return route ~= nil
end

function ns.WQRoute_Owner()
	return route and route.owner
end

-- The quest's stop number, nil when it isn't on the route.
function ns.WQRoute_Index(questID)
	if not route then
		return nil
	end
	for i, id in ipairs(route.ids) do
		if id == questID then
			return i
		end
	end
	return nil
end

-- Spots ------------------------------------------------------------------------------------------------------------

local function World(mapID, x, y)
	local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not (cont and pos) then
		return nil
	end
	local wx, wy = pos:GetXY()
	return { cont = cont, x = wx, y = wy }
end

-- Stops for the quests the game gives a spot for, and where you stand (nil when unknown).
local function Stops(quests)
	local stops = {}
	for _, q in ipairs(quests) do
		local x, y = C_TaskQuest.GetQuestLocation(q.id, q.zoneID)
		local w = x and y and (x > 0 or y > 0) and World(q.zoneID, x, y)
		if w then
			stops[#stops + 1] = { id = q.id, cont = w.cont, x = w.x, y = w.y,
				weight = (q.money or 0) > 0 and q.money or 1 }
		end
	end
	local start
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		local px, py = pos:GetXY()
		if px and py and not ns.IsSecret(px, py) then
			start = World(mapID, px, py)
		end
	end
	return stops, start
end

-- Running ----------------------------------------------------------------------------------------------------------

local function Finish(text)
	route = nil
	events:Unwatch(OWNER, "QUEST_TURNED_IN")
	if text then
		ns.Print(text)
	end
	Changed()
end

-- Drops the stops that are gone and tracks the first one left (announce: says which in chat).
local function TrackNext(announce)
	if not route then
		return
	end
	local up = {}
	for _, q in ipairs(route.provider() or {}) do
		up[q.id] = q
	end
	local ids = {}
	for _, id in ipairs(route.ids) do
		if up[id] then
			ids[#ids + 1] = id
		end
	end
	route.ids = ids
	if #ids == 0 then
		Finish(route.earned > 0 and ("route done: %s from it."):format(ns.Gold(route.earned)) or "route done.")
		return
	end
	local q = up[ids[1]]
	ns.WQ_Track(q)
	if announce then
		local gold = (q.money or 0) > 0 and (", " .. ns.WQ_FormatGold(q.money)) or ""
		ns.Print(("next: %s (%s%s), %d left."):format(q.title, q.zone or "?", gold, #ids))
	end
	Changed()
end

-- quests: the quest records to route through (World quests' records: id, zoneID, zone, title, money). provider() ->
-- the records still up for this route. owner: who started it ("wq" | "wgq"); label: what it routes ("gold world
-- quests", a zone's name). Returns true when it started.
function ns.WQRoute_Start(quests, provider, owner, label)
	if #quests == 0 then
		ns.Print("nothing to route" .. (label and (" in " .. label) or "") .. ".")
		return false
	end
	local stops, start = Stops(quests)
	if #stops == 0 then
		ns.Print("the game gives no spots for these quests yet. Try again in a moment.")
		return false
	end
	route = { ids = ns.WQ_RouteOrder(stops, start), owner = owner, label = label, provider = provider, earned = 0 }
	events:Watch(OWNER, "QUEST_TURNED_IN")
	local skipped = #quests - #stops
	ns.Print(("route through %s: %d stops%s. Hand one in and the next one is tracked."):format(label or "world quests",
		#route.ids, skipped > 0 and (" (%d without a spot left out)"):format(skipped) or ""))
	TrackNext(true)
	return true
end

-- owner: only stop a route this owner started (a module turning off); nil stops any. silent: no chat line.
function ns.WQRoute_Stop(owner, silent)
	if route and (not owner or route.owner == owner) then
		Finish(not silent and "route stopped." or nil)
	end
end

events:On(OWNER, "QUEST_TURNED_IN", function(_, questID, _, money)
	local index = ns.WQRoute_Index(questID)
	if index then
		table.remove(route.ids, index) -- even if the map still lists it for a moment
		route.earned = route.earned + (money or 0)
		C_Timer.After(NEXT_DELAY, function()
			TrackNext(true)
		end)
	end
end)
