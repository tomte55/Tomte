local addonName, ns = ...

-- Prey: pure logic (no WoW API calls; unit-tested in tests/test_prey.lua). The hunt data per expansion (`prey` in
-- Data/Midnight/Prey.lua) turned into a quest lookup, this week's hunts per difficulty, the achievement collection
-- and the lines the page and the Hunt Table tooltip show. Read.lua reads the game, registered in Prey.lua.

-- Enum.PreyHuntProgressState (Cold 0, Warm 1, Hot 2, Final 3) as the player reads it.
local STATE_NAMES = { [0] = "Cold trail", [1] = "Warm trail", [2] = "Hot trail", [3] = "Found" }

-- [questID] = { difficulty (index into def.difficulties), achievement, criteria }.
function ns.Prey_Index(def)
	local index = {}
	if not def then
		return index
	end
	for i, d in ipairs(def.difficulties or {}) do
		for n, quest in ipairs(d.quests or {}) do
			index[quest] = { difficulty = i, achievement = d.achievement, criteria = d.firstCriteria + n - 1 }
		end
	end
	for _, e in ipairs(def.extra or {}) do
		index[e.quest] = { difficulty = e.difficulty, achievement = e.achievement, criteria = e.criteria, extra = true }
	end
	return index
end

-- The difficulties open at this journey rank (nil: not known, Normal only), as indexes.
function ns.Prey_Unlocked(def, rank)
	local list = {}
	for i, d in ipairs(def and def.difficulties or {}) do
		if (rank or 0) >= (d.rank or 0) then
			list[#list + 1] = i
		end
	end
	return list
end

-- This week per open difficulty: { index, name, done, max, chestsLeft }. isDone(questID) -> bool (the hunt quests
-- are weekly, so their completed flag is this week's).
function ns.Prey_Week(def, rank, isDone)
	local rows = {}
	if not def then
		return rows
	end
	local extraOf = {}
	for _, e in ipairs(def.extra or {}) do
		extraOf[e.difficulty] = extraOf[e.difficulty] or {}
		table.insert(extraOf[e.difficulty], e.quest)
	end
	for _, i in ipairs(ns.Prey_Unlocked(def, rank)) do
		local d = def.difficulties[i]
		local done = 0
		for _, quest in ipairs(d.quests or {}) do
			if isDone(quest) then
				done = done + 1
			end
		end
		for _, quest in ipairs(extraOf[i] or {}) do
			if isDone(quest) then
				done = done + 1
			end
		end
		local max = def.perWeek or 4
		rows[#rows + 1] = { index = i, name = d.name, done = done, max = max,
			chestsLeft = math.max((def.chestsPerWeek or 0) - done, 0) }
	end
	return rows
end

-- "1/4 this week · 1 chest left", "4/4 this week".
function ns.Prey_WeekText(row)
	local text = ("%d/%d this week"):format(math.min(row.done, row.max), row.max)
	if row.done >= row.max then
		return text
	end
	if row.chestsLeft > 0 then
		return text .. (" · %d %s left"):format(row.chestsLeft, row.chestsLeft == 1 and "chest" or "chests")
	end
	return text .. " · sacks only"
end

-- The achievement collection per difficulty: { name, done, total }. criteriaDone(achievement, criteria) -> bool.
function ns.Prey_Collection(def, criteriaDone)
	local rows = {}
	for _, d in ipairs(def and def.difficulties or {}) do
		local done = 0
		for n in ipairs(d.quests or {}) do
			if criteriaDone(d.achievement, d.firstCriteria + n - 1) then
				done = done + 1
			end
		end
		rows[#rows + 1] = { name = d.name, done = done, total = #(d.quests or {}), achievement = d.achievement }
	end
	return rows
end

function ns.Prey_StateName(state)
	return state and STATE_NAMES[state] or nil
end

-- The point of a quest in C_QuestLog.GetQuestsOnMap's list ({ questID, x, y }): x, y (0..1) or nil.
function ns.Prey_FindOnMap(list, questID)
	for _, q in ipairs(list or {}) do
		if q.questID == questID and q.x and q.y and (q.x > 0 or q.y > 0) then
			return q.x, q.y
		end
	end
	return nil
end

-- Tooltip lines for a hunt on the Hunt Table: { text, role }. entry: Prey_Index's; week: Prey_Week's row for its
-- difficulty (nil when that difficulty isn't open yet); needed: the target is still missing from its achievement.
function ns.Prey_PinLines(def, entry, week, needed)
	local d = def.difficulties[entry.difficulty]
	local lines = { { text = ("Difficulty: %s"):format(d and d.name or "?"), role = "heading" } }
	if week then
		lines[#lines + 1] = { text = ("%s: %s"):format(week.name, ns.Prey_WeekText(week)), role = "textMuted" }
	elseif d then
		lines[#lines + 1] = { text = ("%s hunts open at journey rank %d"):format(d.name, d.rank or 0), role = "warning" }
	end
	if needed then
		lines[#lines + 1] = { text = "Not yet defeated for its achievement", role = "accent" }
	end
	return lines
end

-- The rail tooltip: what the active hunt is doing, or how to start one.
function ns.Prey_HomeText(active)
	if not active then
		return "No hunt. Pick a target at the Hunt Table."
	end
	local state = ns.Prey_StateName(active.state)
	return state and ("%s: %s"):format(active.title or "Prey", state) or (active.title or "Prey hunt active")
end
