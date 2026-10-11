local addonName, ns = ...

-- Gold world quests: pure logic (no WoW API calls; tests/test_gold.lua). Scan.lua reads the game into plain records:
-- quests are World quests' records (Modules/WorldQuests/Data.lua), assignment facts and characters are below.

-- Gold quests -------------------------------------------------------------------------------------------------------

local function ByMoney(a, b)
	if a.money ~= b.money then
		return a.money > b.money
	end
	local sa, sb = a.seconds or math.huge, b.seconds or math.huge
	if sa ~= sb then
		return sa < sb
	end
	if a.title ~= b.title then
		return (a.title or "") < (b.title or "")
	end
	return a.id < b.id
end

-- The loaded quests that give gold, by zone: { count, total, zones = { { name, total, quests } } }, the richest zone
-- first and in each zone the richest quest first.
function ns.Gold_Group(quests)
	local group = { count = 0, total = 0, zones = {} }
	local byName = {}
	for _, q in ipairs(quests) do
		if q.loaded and (q.money or 0) > 0 then
			local name = q.zone or "?"
			local zone = byName[name]
			if not zone then
				zone = { name = name, total = 0, quests = {} }
				byName[name] = zone
				group.zones[#group.zones + 1] = zone
			end
			zone.quests[#zone.quests + 1] = q
			zone.total = zone.total + q.money
			group.count, group.total = group.count + 1, group.total + q.money
		end
	end
	for _, zone in ipairs(group.zones) do
		table.sort(zone.quests, ByMoney)
	end
	table.sort(group.zones, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.name < b.name
	end)
	return group
end

-- "14 quests · 3,250g", "1 quest · 250g", "no gold quests".
function ns.Gold_Summary(group)
	if group.count == 0 then
		return "no gold quests"
	end
	return ("%d %s · %s"):format(group.count, group.count == 1 and "quest" or "quests", ns.Gold(group.total))
end

-- The login line (after "Tomte: ").
function ns.Gold_LoginLine(group)
	if group.count == 0 then
		return "Gold world quests: none up right now."
	end
	return ("Gold world quests: %d up, %s. /tomte wgq opens the list."):format(group.count, ns.Gold(group.total))
end

-- Special assignments -----------------------------------------------------------------------------------------------

local STATE_RANK = { done = 3, up = 2, locked = 1 }

-- f: { hasUnlock, questDone, questLive (on the map, in the log or timed), unlockDone, unlockLive, turnedIn (this
-- week) }. "done" | "up" | "locked" | nil (not out this week). Without an unlock quest it only knows up, and done
-- from this week's turn-ins (old flags of rotating assignments never clear).
function ns.Gold_AssignmentState(f)
	if not f.hasUnlock then
		if f.turnedIn then
			return "done"
		end
		return f.questLive and "up" or nil
	end
	if f.questDone then
		return "done"
	end
	if f.questLive or f.unlockDone then
		return "up"
	end
	return f.unlockLive and "locked" or nil
end

-- rows: { { zone, state, live } } in data order (rows without a state are dropped). One per zone, as the game puts
-- out one assignment per zone a week: one live on the map now beats an old flag, then done > up > locked, then the
-- first. Zones keep the order they first appear in.
function ns.Gold_BestPerZone(rows)
	local best, order = {}, {}
	for _, row in ipairs(rows) do
		if row.state then
			local cur = best[row.zone]
			if not cur then
				order[#order + 1] = row.zone
				best[row.zone] = row
			elseif (row.live and not cur.live)
				or (row.live == cur.live and STATE_RANK[row.state] > STATE_RANK[cur.state]) then
				best[row.zone] = row
			end
		end
	end
	local list = {}
	for _, zone in ipairs(order) do
		list[#list + 1] = best[zone]
	end
	return list
end

-- Weekly caches and characters --------------------------------------------------------------------------------------

-- Any of the cache's quests flagged done (completed(id) -> bool) or in this week's turn-ins.
function ns.Gold_CacheDone(cache, completed, turnedIn)
	for _, id in ipairs(cache.quests) do
		if (turnedIn and turnedIn[id]) or (completed and completed(id)) then
			return true
		end
	end
	return false
end

-- A character record: { name, realm, class, level, expansion, nextReset, since, week = { [questID] = copper },
-- weekCopper, totalCopper, turnedIn = { [questID] = true }, caches = { [key] = true } }.
function ns.Gold_NewChar()
	return { week = {}, weekCopper = 0, totalCopper = 0, turnedIn = {}, caches = {} }
end

-- Clears the week once its reset has passed and sets the next one (untilReset: seconds, may be nil). True when it
-- cleared.
function ns.Gold_RollWeek(char, now, untilReset)
	local rolled = false
	if char.nextReset and now >= char.nextReset then
		char.week, char.weekCopper, char.turnedIn, char.caches = {}, 0, {}, {}
		char.since = now
		rolled = true
	end
	char.since = char.since or now
	if untilReset and untilReset > 0 then
		char.nextReset = now + untilReset
	end
	return rolled
end

-- Another character's week as of now: its numbers, or nothing once its reset has passed (it rolls when they log in).
function ns.Gold_CharWeek(char, now)
	if char.nextReset and now >= char.nextReset then
		return 0, {}
	end
	return char.weekCopper or 0, char.caches or {}
end

-- A world quest's gold turned in: counted once per quest per week. True when it counted.
function ns.Gold_AddEarned(char, questID, copper)
	if not copper or copper <= 0 or char.week[questID] then
		return false
	end
	char.week[questID] = copper
	char.weekCopper = (char.weekCopper or 0) + copper
	char.totalCopper = (char.totalCopper or 0) + copper
	return true
end

-- Characters for the Characters view: the current one first, then by gold this week, then name.
function ns.Gold_SortChars(chars, current, now)
	local list = {}
	for guid, char in pairs(chars) do
		list[#list + 1] = { guid = guid, char = char, week = (ns.Gold_CharWeek(char, now)) }
	end
	table.sort(list, function(a, b)
		if (a.guid == current) ~= (b.guid == current) then
			return a.guid == current
		end
		if a.week ~= b.week then
			return a.week > b.week
		end
		return (a.char.name or "") < (b.char.name or "")
	end)
	return list
end
