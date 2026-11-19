local addonName, ns = ...

-- Quest list: pure logic (no WoW API calls; unit-tested in tests/test_questlist.lua). Which quests the list shows,
-- grouped into sections (Next quests' stops, zones, one plain list, and the folded "Hidden" line), their order, how many
-- of each section show, and objective lines read into a label and a count. Drawn by List.lua, read by Read.lua,
-- started from QuestList.lua. See docs/superpowers/specs/2026-11-10-tomte-quest-list-design.md.

local IDLE_SECONDS = 30 * 60 -- a quest with no progress for this long folds itself (auto-fold setting)
local HERE_YARDS = 50 -- a stop this close is "Right here": a direction means nothing when you're standing in it
-- The eight compass points, counterclockwise from east, as stop names in your own zone.
local POINTS = { "East", "Northeast", "North", "Northwest", "West", "Southwest", "South", "Southeast" }

-- Order ---------------------------------------------------------------------------------------------------------------

-- Turn-ins first (when turnInsFirst), then timed quests (shortest timer first), then the lowest level, the most XP,
-- the title.
local function Sorter(turnInsFirst)
	return function(a, b)
		if turnInsFirst and (a.complete and true or false) ~= (b.complete and true or false) then
			return a.complete and true or false
		end
		if (a.timeLeft ~= nil) ~= (b.timeLeft ~= nil) then
			return a.timeLeft ~= nil
		end
		if a.timeLeft and b.timeLeft and a.timeLeft ~= b.timeLeft then
			return a.timeLeft < b.timeLeft
		end
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) < (b.level or 0)
		end
		if (a.xp or 0) ~= (b.xp or 0) then
			return (a.xp or 0) > (b.xp or 0)
		end
		if (a.title or "") ~= (b.title or "") then
			return (a.title or "") < (b.title or "")
		end
		return (a.questID or 0) < (b.questID or 0)
	end
end
ns.QuestList_Sorter = Sorter

-- The active quest first, then the section's own order: the quest you picked (on the map, say) is the one you see.
local function ActiveFirst(sort)
	return function(a, b)
		if (a.active and true or false) ~= (b.active and true or false) then
			return a.active and true or false
		end
		return sort(a, b)
	end
end

-- Other quests: the nearest first (q.yards, set by the caller), those without a distance last, then the usual order.
local function ByDistance(sort)
	return function(a, b)
		if (a.yards ~= nil) ~= (b.yards ~= nil) then
			return a.yards ~= nil
		end
		if a.yards and b.yards and math.floor(a.yards) ~= math.floor(b.yards) then
			return a.yards < b.yards
		end
		return sort(a, b)
	end
end

-- In "tracked" mode a quest shows when the game tracks it or it's the active one.
local function Tracked(q)
	return q.watched or q.active
end

-- Sections ------------------------------------------------------------------------------------------------------------

local function LowestID(quests)
	local low
	for _, q in ipairs(quests) do
		if not low or q.questID < low then
			low = q.questID
		end
	end
	return low or 0
end

-- Sections by quest-log zone, in order: here first (opts.zone), then by name.
local function ZoneSections(quests, here)
	local byZone, list = {}, {}
	for _, q in ipairs(quests) do
		local zone = q.zone or "Other"
		local s = byZone[zone]
		if not s then
			s = { key = "zone:" .. zone, kind = "zone", zone = zone, title = zone, quests = {} }
			byZone[zone] = s
			list[#list + 1] = s
		end
		s.quests[#s.quests + 1] = q
	end
	table.sort(list, function(a, b)
		if (a.zone == here) ~= (b.zone == here) then
			return a.zone == here
		end
		return a.zone < b.zone
	end)
	return list
end

-- quests: quest log rows (LevelingRead_Quests: questID, title, level, xp, complete, timeLeft, zone, watched, active).
-- stops: Leveling_NextStops' result for the same quests ({ { quests, zone, distance } }), used when grouping by stop.
-- opts:
--   show: "all" | "tracked"; hidden: { [questID] = true }, quests hidden from the list (they go to the folded Hidden
--   line, whatever the game tracks); groupBy: "stop" | "zone" | "list"; zone: the zone you're in (by name);
--   turnInsFirst: bool; open: how many sections show open; perSection: quests shown before "+N more";
--   stops: how many of the nearest stops get a group of their own (the rest join Other quests);
--   instance: the dungeon or raid you're in, by name, or nil: its quests (filed under it in the log, or tagged with
--   it) get the first group, open, since inside there are no positions to make stops from;
--   folded: { [section key] = true | false } the player's own choice, which wins over open;
--   expanded: { [section key] = true } "+N more" clicked.
-- The active quest comes first in its section, and its section opens unless the player folded it.
-- Returns sections, top to bottom: { key, kind ("instance" | "stop" | "zone" | "list" | "other" | "hidden"), title,
-- distance (stops),
-- quests (all of the section's, in order), shown (how many of them show), more (how many don't), open }.
function ns.QuestList_Sections(quests, stops, opts)
	local sort = Sorter(opts.turnInsFirst)
	local visible, hidden, hiddenSet = {}, {}, opts.hidden or {}
	for _, q in ipairs(quests) do
		if hiddenSet[q.questID] then
			hidden[#hidden + 1] = q
		elseif opts.show == "all" or Tracked(q) then
			visible[q.questID] = q
		end
	end
	local sections = {}
	if opts.instance then
		local list = {}
		for _, q in ipairs(quests) do
			if visible[q.questID] and (q.zone == opts.instance or q.dungeon == opts.instance) then
				list[#list + 1] = q
				visible[q.questID] = nil
			end
		end
		if #list > 0 then
			sections[1] = { key = "instance", kind = "instance", title = opts.instance, quests = list }
		end
	end
	local instanceGroups = #sections
	if opts.groupBy == "stop" then
		-- The nearest stops get a group each; quests at farther stops, and those no stop took (hard, grey, no map spot),
		-- share one Other quests group, so a log spread over many places stays a short list.
		local placed = {}
		for _, stop in ipairs(stops or {}) do
			if #sections - instanceGroups >= (opts.stops or math.huge) then
				break
			end
			local list = {}
			for _, q in ipairs(stop.quests) do
				if visible[q.questID] and not placed[q.questID] then
					placed[q.questID] = true
					list[#list + 1] = visible[q.questID]
				end
			end
			if #list > 0 then
				sections[#sections + 1] = { key = "stop:" .. LowestID(list), kind = "stop", title = stop.zone or "Nearby",
					distance = stop.distance, quests = list }
			end
		end
		local rest = {}
		for _, q in ipairs(quests) do
			if visible[q.questID] and not placed[q.questID] then
				rest[#rest + 1] = q
			end
		end
		if #rest > 0 then
			sections[#sections + 1] = { key = "other", kind = "other", title = "Other quests", quests = rest }
		end
	elseif opts.groupBy == "zone" then
		local list = {}
		for _, q in ipairs(quests) do
			if visible[q.questID] then
				list[#list + 1] = q
			end
		end
		for _, s in ipairs(ZoneSections(list, opts.zone)) do
			sections[#sections + 1] = s
		end
	else
		local list = {}
		for _, q in ipairs(quests) do
			if visible[q.questID] then
				list[#list + 1] = q
			end
		end
		if #list > 0 then
			sections[#sections + 1] = { key = "list", kind = "list", title = "Quests", quests = list }
		end
	end
	if #hidden > 0 then
		sections[#sections + 1] = { key = "hidden", kind = "hidden", title = "Hidden", quests = hidden }
	end
	local folded, expanded = opts.folded or {}, opts.expanded or {}
	local opened = 0
	for _, s in ipairs(sections) do
		table.sort(s.quests, ActiveFirst(s.kind == "other" and ByDistance(sort) or sort))
		local hasActive = s.quests[1] ~= nil and s.quests[1].active
		local open
		if folded[s.key] ~= nil then
			open = not folded[s.key]
		elseif hasActive and s.kind ~= "hidden" then
			open = true -- the active quest's group shows it
		elseif s.kind == "hidden" or s.kind == "other" then
			open = false
		elseif s.kind == "list" or s.kind == "instance" then
			open = true
		else
			-- Stops come nearest first, so the first few open; zones left over from stops are far away and fold.
			open = (s.kind == "stop" or opts.groupBy == "zone") and opened < (opts.open or 1)
		end
		if open and s.kind ~= "hidden" and s.kind ~= "instance" then
			opened = opened + 1
		end
		s.open = open
		local limit = expanded[s.key] and #s.quests or (opts.perSection or #s.quests)
		s.shown = open and math.min(#s.quests, limit) or 0
		s.more = open and (#s.quests - s.shown) or 0
	end
	return sections
end

-- The quest whose item the quest item button holds: the followed quest (followedID) when it has a usable item, else
-- the first quest with one in the order the list shows them (nearest stop first). Hidden quests never. A done quest's
-- item counts only when the game keeps showing it (itemWhenDone), as the game's own tracker does.
function ns.QuestList_ItemQuest(sections, followedID)
	local first
	for _, s in ipairs(sections) do
		if s.kind ~= "hidden" then
			for _, q in ipairs(s.quests) do
				if q.itemLink and (not q.complete or q.itemWhenDone) then
					if q.questID == followedID then
						return q
					end
					first = first or q
				end
			end
		end
	end
	return first
end

-- Whether a quest's own distance is worth a line: not when it's what its stop's header already says (the stop's only
-- quest, or its nearest, at the same rounded distance). Quests in zone and list sections always show theirs.
function ns.QuestList_ShowQuestDistance(section, q)
	if not q.yards then
		return false
	end
	if section.kind ~= "stop" or not section.distance then
		return true
	end
	if #section.quests <= 1 then
		return false
	end
	local function Tens(y)
		return math.floor((y + 5) / 10)
	end
	return Tens(q.yards) ~= Tens(section.distance)
end

-- A stop's name in your own zone: which way it lies from you. dEast, dNorth: how far it is east and north of you (any
-- unit), yards: its distance. "Right here" up close.
function ns.QuestList_Compass(dEast, dNorth, yards)
	if yards and yards < HERE_YARDS then
		return "Right here"
	end
	local angle = (math.atan2 or math.atan)(dNorth, dEast) -- counterclockwise from east (Lua 5.4 has only atan)
	local slice = math.floor(angle / (math.pi / 4) + 0.5) % 8
	return POINTS[slice + 1]
end

-- Objectives ----------------------------------------------------------------------------------------------------------

-- An objective as the game writes it ("0/6 Grimtotem Brute slain", or "Grimtotem Brute slain: 0/6") read into
-- { label, have, need, finished }: label without the count. have and need come from the objective's own numbers when
-- it has them (C_QuestLog.GetQuestObjectives: numFulfilled, numRequired), else from the text; nil for one with no count
-- ("Find the note"). o: { text, finished, numFulfilled, numRequired }.
function ns.QuestList_Objective(o)
	local text = o.text or ""
	local label, have, need
	local h, n, rest = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.+)$")
	if h then
		label, have, need = rest, tonumber(h), tonumber(n)
	else
		local front, h2, n2 = text:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
		if h2 then
			label, have, need = front, tonumber(h2), tonumber(n2)
		else
			label = text
		end
	end
	if type(o.numRequired) == "number" and o.numRequired > 0 then
		have, need = o.numFulfilled or have or 0, o.numRequired
	end
	if need and need <= 0 then
		have, need = nil, nil
	end
	return { label = label, have = have, need = need, finished = o.finished and true or false }
end

-- The objective as one line of text: "0/6 Grimtotem Brute slain", or the label alone without a count.
function ns.QuestList_ObjectiveText(obj)
	if obj.need then
		return ("%d/%d %s"):format(obj.have or 0, obj.need, obj.label)
	end
	return obj.label
end

-- How full its bar is (0..1), or nil for an objective with no count or a count of one (a bar says nothing there).
function ns.QuestList_ObjectiveShare(obj)
	if not obj.need or obj.need <= 1 then
		return nil
	end
	return math.min(math.max((obj.have or 0) / obj.need, 0), 1)
end

-- Folding -------------------------------------------------------------------------------------------------------------

-- Whether a quest shows only its title. manual: the player's own fold (true / false), or nil. autoFold: the setting.
-- lastChange: when its objectives last moved (seconds, nil = not seen move); now: the clock.
function ns.QuestList_QuestFolded(manual, autoFold, lastChange, now)
	if manual ~= nil then
		return manual
	end
	return autoFold and lastChange ~= nil and now - lastChange >= IDLE_SECONDS or false
end

-- "18", "18+" for an elite quest, "?" without a level.
function ns.QuestList_LevelText(level, elite)
	return ("%s%s"):format(level and tostring(level) or "?", elite and "+" or "")
end

-- A quest level's color role against yours, as the game colors quest levels: red 5+ above you, orange 3-4 above,
-- yellow within 2, green below that, grey once it's more than greenRange below (the game's GetQuestGreenRange; 8 when
-- not known). Theme roles: danger, warning, heading, success, textMuted.
function ns.QuestList_DifficultyRole(questLevel, playerLevel, greenRange)
	if not (questLevel and playerLevel) or questLevel <= 0 then
		return "textMuted"
	end
	local diff = questLevel - playerLevel
	if diff >= 5 then
		return "danger"
	elseif diff >= 3 then
		return "warning"
	elseif diff >= -2 then
		return "heading"
	elseif -diff <= (greenRange or 8) then
		return "success"
	end
	return "textMuted"
end

-- A quest's state in a few words: "Ready to turn in", "2 of 3 done", or nil with nothing to count. objectives: as
-- QuestList_Objective makes them. complete: the game says it can be handed in.
function ns.QuestList_ProgressText(objectives, complete)
	if complete then
		return "Ready to turn in"
	end
	local done = 0
	for _, obj in ipairs(objectives or {}) do
		if obj.finished then
			done = done + 1
		end
	end
	if #(objectives or {}) < 2 then
		return nil
	end
	return ("%d of %d done"):format(done, #objectives)
end

-- The section header's right side: "3 quests" (or "1 quest").
function ns.QuestList_CountText(n)
	return n == 1 and "1 quest" or ("%d quests"):format(n)
end

-- Flight hint ---------------------------------------------------------------------------------------------------------

-- Whether flying to a stop beats going there on foot or mount, as a rough guess: walk to a flight master you know, fly
-- straight to another you know, walk on from there. Which flight masters connect isn't known away from one (only the
-- flight map says), so the straight line stands in for the route, made longer by FLIGHT_DETOUR.
local FLIGHT_DETOUR = 1.3 -- flight paths bend round mountains and through other flight masters
local FLIGHT_OVERHEAD = 30 -- seconds: talking to the flight master, takeoff and landing
local HINT_MIN_SAVED = 120 -- seconds a flight saves before it's worth a hint
-- And the flight takes at most this share of the walk. 2/3 left out Ratchet to Splintertree Post for a 9 minute walk
-- (7 minutes by flight, measured 2026-11-19), a flight worth naming.
local HINT_MAX_SHARE = 0.8

-- you, target: { x, y } in world yards on one continent. nodes: the flight masters you know there, { { x, y, name } }.
-- ground, flight: yards per second on the ground (running or mounted) and on a flight. Returns
-- { from, to (nodes), walk, fly (seconds) } for the quickest flight that is worth it, or nil; and the quickest flight
-- even when it isn't (for the "why" command).
function ns.QuestList_FlightHint(you, target, nodes, ground, flight)
	if not (you and target and nodes and ground and flight) or ground <= 0 or flight <= 0 then
		return nil
	end
	local function D(a, b)
		local dx, dy = a.x - b.x, a.y - b.y
		return math.sqrt(dx * dx + dy * dy)
	end
	local walk = D(you, target) / ground
	-- Each flight master's walk from you and to the target, once, then the best pair.
	local toFrom, toTarget = {}, {}
	for i, n in ipairs(nodes) do
		toFrom[i], toTarget[i] = D(you, n) / ground, D(n, target) / ground
	end
	local best
	for i, a in ipairs(nodes) do
		if toFrom[i] < walk then
			for j, b in ipairs(nodes) do
				if i ~= j and toTarget[j] < walk then
					local fly = toFrom[i] + D(a, b) * FLIGHT_DETOUR / flight + FLIGHT_OVERHEAD + toTarget[j]
					if not best or fly < best.fly then
						best = { from = a, to = b, walk = walk, fly = fly }
					end
				end
			end
		end
	end
	if best and walk - best.fly >= HINT_MIN_SAVED and best.fly <= walk * HINT_MAX_SHARE then
		return best, best
	end
	return nil, best
end

-- A rough time: "~4 min", "~1 h 10 min"; under a minute "<1 min".
function ns.QuestList_RoughTime(seconds)
	local minutes = math.floor(seconds / 60 + 0.5)
	if minutes < 1 then
		return "<1 min"
	elseif minutes < 60 then
		return ("~%d min"):format(minutes)
	end
	return ("~%d h %d min"):format(math.floor(minutes / 60), minutes % 60)
end
