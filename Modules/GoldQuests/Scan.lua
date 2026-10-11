local addonName, ns = ...

-- Gold world quests: reading the game. ns.Gold_Read builds the window's model for the player's expansion
-- (Data/<Expansion>/Gold.lua): the world quests of its zones (World quests' scan and reward cache), the special
-- assignments and the weekly caches. Pure logic is Data.lua.

local IsDone = C_QuestLog.IsQuestFlaggedCompleted
local TimeLeft = C_TaskQuest.GetQuestTimeLeftSeconds
local CAPSTONE_ATLAS = "[Cc]apstone" -- locked special assignment POIs: worldquest-Capstone-questmarker-epic-Locked

local requested = {} -- [questID or "item:"..itemID] = true, asked once per session

local function QuestTitle(questID)
	local title = C_TaskQuest.GetQuestInfoByQuestID(questID)
	if not title or title == "" then
		title = C_QuestLog.GetTitleForQuestID(questID)
	end
	if title and title ~= "" then
		return title
	end
	if not requested[questID] then
		requested[questID] = true
		C_QuestLog.RequestLoadQuestByID(questID)
	end
	return nil
end
ns.Gold_QuestTitle = QuestTitle

local function ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if name and name ~= "" then
		return name
	end
	local key = "item:" .. itemID
	if not requested[key] then
		requested[key] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return nil
end

local function ZoneName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or nil
end

-- The zone the game files a quest under (a sub-area resolves to its zone), nil when it doesn't say.
local function QuestZone(questID)
	local zoneID = C_TaskQuest.GetQuestZoneID(questID)
	return zoneID and (ns.MapTabs_ResolveMap(zoneID)) or nil
end

local function Live(questID, seen)
	if not questID then
		return false
	end
	local seconds = TimeLeft(questID)
	return seen[questID] == true or C_QuestLog.IsOnQuest(questID) or C_TaskQuest.IsActive(questID) == true
		or (seconds ~= nil and seconds > 0)
end

-- fulfilled, required of a quest's first counted objective ("Complete 3 world quests in Harandar 1/3").
local function Progress(questID)
	for _, obj in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		if (obj.numRequired or 0) > 0 then
			return obj.numFulfilled or 0, obj.numRequired
		end
	end
	return nil
end

-- Special assignments ---------------------------------------------------------------------------------------------

local function DataAssignments(list, rows, seen, turnedIn, known)
	for _, entry in ipairs(list or {}) do
		known[entry.quest] = true
		local hasUnlock = entry.unlock ~= nil
		local questLive, unlockLive = Live(entry.quest, seen), Live(entry.unlock, seen)
		local state = ns.Gold_AssignmentState({
			hasUnlock = hasUnlock, questDone = IsDone(entry.quest), questLive = questLive,
			unlockDone = hasUnlock and IsDone(entry.unlock), unlockLive = unlockLive,
			turnedIn = turnedIn[entry.quest] == true,
		})
		if state then
			local zoneID = entry.zone or QuestZone(entry.quest)
			local row = {
				state = state, live = questLive or unlockLive, quest = entry.quest, unlock = entry.unlock, zoneID = zoneID,
				zone = ZoneName(zoneID) or "?", title = QuestTitle(entry.quest) or "Special assignment",
			}
			if state == "up" then
				row.seconds = TimeLeft(entry.quest)
			elseif state == "locked" then
				row.seconds = TimeLeft(entry.unlock)
				row.have, row.need = Progress(entry.unlock)
			end
			rows[#rows + 1] = row
		end
	end
end

-- Assignments the data doesn't know: world quests tagged Capstone are up; locked capstone POIs on the zone maps.
local function OtherAssignments(rows, quests, zones, known)
	for _, q in ipairs(quests) do
		if q.type == "capstone" and not known[q.id] then
			known[q.id] = true
			rows[#rows + 1] = { state = "up", live = true, quest = q.id, zoneID = q.zoneID, zone = q.zone or "?",
				title = q.title, seconds = q.seconds }
		end
	end
	local poiSeen = {}
	for _, zoneID in ipairs(zones) do
		for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(zoneID) or {}) do
			if not poiSeen[poiID] then
				local info = C_AreaPoiInfo.GetAreaPOIInfo(zoneID, poiID)
				if info and info.atlasName and info.atlasName:find(CAPSTONE_ATLAS) and info.atlasName:find("Locked") then
					poiSeen[poiID] = true
					local x, y = info.position and info.position:GetXY()
					rows[#rows + 1] = { state = "locked", live = true, poi = poiID, zoneID = zoneID,
						zone = ZoneName(zoneID) or "?", title = info.name, x = x, y = y }
				end
			end
		end
	end
end

-- Weekly caches ---------------------------------------------------------------------------------------------------

local function CacheLabel(cache)
	local name = cache.item and ItemName(cache.item)
	if not name and (cache.title or #cache.quests == 1) then
		name = QuestTitle(cache.title or cache.quests[1])
	end
	return name or cache.label
end

-- The quests of a cache done this week, by name (for its tooltip).
function ns.Gold_CacheDoneNames(cache, turnedIn)
	local names = {}
	for _, id in ipairs(cache.quests) do
		if turnedIn[id] or IsDone(id) then
			names[#names + 1] = QuestTitle(id) or ("Quest " .. id)
		end
	end
	return names
end

-- Model -----------------------------------------------------------------------------------------------------------

-- { expansion, quests, pending, group, assignments, caches } for an expansion; nil when Tomte has no zones for it.
-- char: this character's record (turned in this week; done caches are noted on it). Special assignments and caches
-- only for the player's own expansion (current).
function ns.Gold_Read(char, hidden, expansion, current)
	local zones = ns.Content_Get(expansion, "goldZones")
	if not zones then
		return nil
	end
	local quests, pending = ns.WQ_ForZones(zones)
	local seen = {}
	for _, q in ipairs(quests) do
		seen[q.id] = true
	end
	local turnedIn = char and char.turnedIn or {}
	local rows, known = {}, {}
	local caches = {}
	if current then
		DataAssignments(ns.Content_Get(expansion, "assignments"), rows, seen, turnedIn, known)
		OtherAssignments(rows, quests, zones, known)
	end
	for _, cache in ipairs(current and ns.Content_Get(expansion, "caches") or {}) do
		local done = ns.Gold_CacheDone(cache, IsDone, turnedIn)
		if done and char then
			char.caches[cache.key] = true
		end
		if not (hidden and hidden[cache.key]) then
			caches[#caches + 1] = { cache = cache, key = cache.key, label = CacheLabel(cache), done = done }
		end
	end
	return {
		expansion = expansion, quests = quests, pending = pending, group = ns.Gold_Group(quests),
		assignments = ns.Gold_BestPerZone(rows), caches = caches,
	}
end

-- A cache's name for the Characters view (another expansion's caches too).
ns.Gold_CacheLabel = CacheLabel
