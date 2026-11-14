local addonName, ns = ...

-- Quest route, game side: turns your quests, their spots on the map and where they're handed in (Read.lua) into the
-- planner's input (RouteData.lua) and answers which quest to follow. Called by the Quest list's and Next quests'
-- follow; nothing runs on its own. See docs/superpowers/specs/2026-11-14-tomte-quest-route-design.md.

-- Hand-ins this close are one stop: one town's quest givers (Brill's stand about 140 yards apart: Deathguard Dillinger
-- at 58.2, 51.5 and Magistrate Sevren at 61.3, 50.8 in Tirisfal Glades, QuestieDB's Forever data).
local MERGE_YARDS = 150
-- A quest this close to one still too high for you is saved for the end of the route: the quest list's stop size, so
-- one place (Shadowvale's three quests at level 9) is done in one trip once you can do them all.
local LATER_YARDS = 300

local UI = ns.UI

-- quests: the quest rows to plan (each caller passes the ones it lists). points: Leveling's quest spots
-- (LevelingRead_QuestPoints). you: where you stand (LevelingRead_You). followedID: the quest followed now. Returns the
-- quest row to follow (the first stop's: its quest, or the first one handed in there) and the planned stops; nil and {}
-- without a position or anything to plan. Only your continent counts; a hand-in elsewhere is left out.
function ns.LevelingRoute_Pick(quests, points, you, grouped, followedID)
	if not you then
		return nil, {}
	end
	local input, byID, tooHigh = {}, {}, {}
	for _, q in ipairs(quests) do
		local p = points[q.questID]
		local point = p and p.continent == you.continent and p or nil
		if ns.Leveling_OnStop(q, grouped) then
			local hand = ns.LevelingRead_HandPoint(q.questID)
			if hand and hand.continent ~= you.continent then
				hand = nil
			end
			if point or (q.complete and hand) then
				input[#input + 1] = { questID = q.questID, complete = q.complete, point = point, hand = hand or nil }
				byID[q.questID] = q
			end
		elseif point and not grouped and not q.elite and not q.dungeon and ns.Leveling_QuestGroup(q) == "hard" then
			tooHigh[#tooHigh + 1] = point -- orange or red for now: doable a level or two on
		end
	end
	local later = ns.Route_SavedForLater(input, tooHigh, LATER_YARDS)
	for _, q in ipairs(input) do
		q.later = not q.complete and later[q.questID] or nil
	end
	local stops = ns.Route_Plan(you, input, followedID, MERGE_YARDS)
	for _, s in ipairs(stops) do
		s.later = s.kind == "do" and later[s.quests[1]] or nil
	end
	local first = stops[1]
	return first and byID[first.quests[1]] or nil, stops
end

-- The plan as chat lines, for the "why" commands: each stop in order with what's done there, and the total.
function ns.LevelingRoute_Print(you, stops)
	if #stops == 0 then
		print("  Route: nothing to plan here.")
		return
	end
	print(("  Route (%d yards):"):format(math.floor(ns.Route_Length(you, stops) + 0.5)))
	for i, s in ipairs(stops) do
		local titles = {}
		for k, id in ipairs(s.quests) do
			titles[k] = C_QuestLog.GetTitleForQuestID(id) or tostring(id)
		end
		print(("    %d. %s %s%s"):format(i, s.kind == "do" and "Do" or UI.Wrap("Hand in", "success"),
			table.concat(titles, ", "), s.later and UI.Wrap(" (saved for later: near a quest too high yet)", "textMuted")
			or ""))
	end
end
