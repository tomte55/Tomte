local addonName, ns = ...

-- World quest routes, shared by the World quests map tab and the Gold world quests window: one route at a time that
-- tracks its stops one by one (ns.WQ_Track, so Waypoints shows them), nearest first from where you stand
-- (RouteOrder.lua). The rules for what happens next are ns.WQRoute_Step (RouteOrder.lua, pure): a stop handed in,
-- expired or done elsewhere drops out and the next is tracked; tracking something else yourself pauses the route
-- until you resume it (the Route button) or track its stop again. Owners pass a provider that reads the quests still
-- up for their route.

local CHECK_DELAY = 1 -- seconds after a turn-in, a removed quest or a tracking change before the route looks (a
-- hand-in clears tracking a moment before QUEST_TURNED_IN; the map updates after it)
local CHECK_EVERY = 30 -- seconds between checks while a route runs: an expired world quest fires no event of its own
local ROUTE_EVENTS = { "QUEST_TURNED_IN", "QUEST_REMOVED", "SUPER_TRACKING_CHANGED" }

local events = ns.NewEvents()
local OWNER = "route"
local route -- { ids, current, paused, owner, label, provider, earned }
local ticker, checkTimer
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
	events:UnwatchAll(OWNER)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if checkTimer then
		checkTimer:Cancel()
		checkTimer = nil
	end
	if text then
		ns.Print(text)
	end
	Changed()
end

-- What the game super-tracks, as WQRoute_Step reads it: a quest ID, 0 for nothing, -1 for something that isn't a
-- quest, nil when it can't tell (our own track waits for the end of combat; dead, the corpse comes first).
local function Tracked()
	if ns.SafeTrack_Waiting() then
		return nil
	end
	local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	if kind == nil then
		return 0
	elseif kind == Enum.SuperTrackingType.Quest then
		return C_SuperTrack.GetSuperTrackedQuestID() or 0
	elseif kind == Enum.SuperTrackingType.Corpse then
		return nil
	end
	return -1
end

-- Reads what's up and what's tracked, and does what WQRoute_Step says.
local function Check()
	if not route then
		return
	end
	local up = {}
	for _, q in ipairs(route.provider() or {}) do
		up[q.id] = q
	end
	local before = #route.ids
	local ids, action = ns.WQRoute_Step(route, up, Tracked())
	route.ids = ids
	if action == "done" then
		Finish(route.earned > 0 and ("route done: %s from it."):format(ns.Gold(route.earned)) or "route done.")
		return
	elseif action == "track" then
		local q = up[ids[1]]
		route.current = q.id
		ns.WQ_Track(q)
		local gold = (q.money or 0) > 0 and (", " .. ns.WQ_FormatGold(q.money)) or ""
		ns.Print(("next: %s (%s%s), %d left."):format(q.title, q.zone or "?", gold, #ids))
	elseif action == "pause" then
		route.paused = true
		ns.Print("route paused: you changed what's tracked. Resume it with the Route button on the World quests "
			.. "map tab or the Gold world quests window.")
	elseif action == "resume" then
		route.paused = false
	end
	if action or #ids ~= before then
		Changed()
	end
end

local function CheckSoon()
	if route and not checkTimer then
		checkTimer = C_Timer.NewTimer(CHECK_DELAY, function()
			checkTimer = nil
			Check()
		end)
	end
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
	if route then
		Finish()
	end
	route = { ids = ns.WQ_RouteOrder(stops, start), owner = owner, label = label, provider = provider, earned = 0,
		paused = false }
	for _, event in ipairs(ROUTE_EVENTS) do
		events:Watch(OWNER, event)
	end
	ticker = C_Timer.NewTicker(CHECK_EVERY, function()
		-- Not while a check is due: a hand-in clears tracking a moment before QUEST_TURNED_IN takes the stop off.
		if not checkTimer then
			Check()
		end
	end)
	local skipped = #quests - #stops
	ns.Print(("route through %s: %d stops%s. Hand one in and the next one is tracked."):format(label or "world quests",
		#route.ids, skipped > 0 and (" (%d without a spot left out)"):format(skipped) or ""))
	Check()
	return true
end

-- owner: only stop a route this owner started (a module turning off); nil stops any. silent: no chat line.
function ns.WQRoute_Stop(owner, silent)
	if route and (not owner or route.owner == owner) then
		Finish(not silent and "route stopped." or nil)
	end
end

function ns.WQRoute_Paused()
	return route ~= nil and route.paused
end

-- Tracks the next stop still up again.
function ns.WQRoute_Resume()
	if route and route.paused then
		route.paused, route.current = false, nil
		Check()
	end
end

-- The Route buttons (World quests map tab, Gold world quests window): their label, and a click. start() starts the
-- owner's route.
function ns.WQRoute_ButtonText()
	if not route then
		return "Route"
	end
	return route.paused and "Resume route" or "Stop route"
end

function ns.WQRoute_Click(start)
	if route and route.paused and not IsShiftKeyDown() then
		ns.WQRoute_Resume()
	elseif route then
		ns.WQRoute_Stop()
	else
		start()
	end
end

events:On(OWNER, "QUEST_TURNED_IN", function(_, questID, _, money)
	local index = ns.WQRoute_Index(questID)
	if index then
		table.remove(route.ids, index) -- even if the map still lists it for a moment
		route.earned = route.earned + (money or 0)
		CheckSoon()
	end
end)

events:On(OWNER, "QUEST_REMOVED", function(_, questID)
	if ns.WQRoute_Index(questID) then
		CheckSoon()
	end
end)

events:On(OWNER, "SUPER_TRACKING_CHANGED", CheckSoon)
