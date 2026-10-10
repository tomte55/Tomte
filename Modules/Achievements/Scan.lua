local addonName, ns = ...

-- Almost Done: finding near-complete achievements. A full scan rides the shared achievement walk (Walk.lua)
-- and keeps a record for each incomplete achievement with progress. The watch set (records close to the
-- threshold, and pins) is recalculated on criteria events, which is where milestones come from. The watch set
-- is cached per character, so the list shows right away after a login.

local GetAchievementInfo = GetAchievementInfo
local GetAchievementNumCriteria = GetAchievementNumCriteria
local GetAchievementCriteriaInfo = GetAchievementCriteriaInfo
local GetCategoryInfo = GetCategoryInfo
local GetCategoryNumAchievements = GetCategoryNumAchievements

local BUDGET_MS = 4 -- work per frame
local WATCH_MARGIN = 20 -- percent below the threshold that's still watched
local DEBOUNCE = 1 -- seconds after the last CRITERIA_UPDATE
local MIN_GAP = 5 -- seconds between re-reads of the watched achievements (CRITERIA_UPDATE fires all the time)
local SAVE_GAP = 60 -- seconds between cache saves from live updates (and at logout)
local CRITERIA_TYPE_ACHIEVEMENT = 8
local SKIPPED_TOP = { [81] = true, [15234] = true } -- Feats of Strength, Legacy: can't be done

local records = {} -- [id] = record
local watch = {} -- [id] = true
local fired = {} -- [id] = { almost = true, lastStep = true }, this session
local metaLinks = {} -- [child id] = { meta id, ... }
local catInfo = {} -- [categoryID] = { name, topID, top, expansion }
local scan -- running scan state
local ready = false -- a full scan finished this session; live updates wait for it (login bursts, stale cache)
local onChanged = function() end
local debounceTimer
local saveTimer

ns.AchWalk_SetSkipped(function(categoryID)
	return SKIPPED_TOP[ns.Ach_CategoryInfo(categoryID).topID] == true
end)

-- Reading -------------------------------------------------------------------------------------------------

local function Settings()
	return ns.achDB
end

function ns.Ach_CategoryInfo(categoryID)
	local info = catInfo[categoryID]
	if info then
		return info
	end
	local name, parent = GetCategoryInfo(categoryID)
	local chain, ids, topID, top = { name or "" }, { categoryID }, categoryID, name
	local guard = 0
	while parent and parent > 0 and guard < 10 do
		local parentName, nextParent = GetCategoryInfo(parent)
		if not parentName then
			break
		end
		chain[#chain + 1] = parentName
		ids[#ids + 1] = parent
		topID, top = parent, parentName
		parent, guard = nextParent, guard + 1
	end
	info = { name = name, topID = topID, top = top, expansion = ns.Ach_ExpansionFromChain(chain, ids) }
	catInfo[categoryID] = info
	return info
end

-- Criteria of an achievement: { name, completed, quantity, required, type, asset }.
function ns.Ach_ReadCriteria(id)
	local list = {}
	for i = 1, GetAchievementNumCriteria(id) or 0 do
		local name, criteriaType, completed, quantity, required, _, _, asset = GetAchievementCriteriaInfo(id, i)
		list[#list + 1] = { name = name or "", completed = completed and true or false, quantity = quantity or 0,
			required = required or 0, type = criteriaType, asset = asset }
	end
	return list
end

-- Done for the scope setting: account = completed on the account, character = earned by this character.
local function IsDone(completed, wasEarnedByMe)
	if Settings().scope == "character" then
		return wasEarnedByMe and true or false
	end
	return completed and true or false
end

local function CritNames(criteria)
	local names = {}
	for i, c in ipairs(criteria) do
		names[i] = c.name
	end
	return names
end

-- A live read of one achievement: { id, name, icon, points, description, completed, percent, done, total, last,
-- reward, criteria }. percent is nil when it has no criteria.
function ns.Ach_ReadAchievement(id)
	local _, name, points, completed, _, _, _, description, _, icon, rewardText, _, wasEarnedByMe = GetAchievementInfo(id)
	if not name then
		return nil
	end
	local criteria = ns.Ach_ReadCriteria(id)
	local percent, done, total, last, have, need = ns.Ach_Percent(criteria)
	return { id = id, name = name, icon = icon, points = points, description = description,
		completed = IsDone(completed, wasEarnedByMe), percent = percent, done = done, total = total, last = last,
		have = have, need = need, reward = rewardText or "", criteria = criteria }
end

local function AddMetaLinks(links, metaID, criteria)
	for _, c in ipairs(criteria) do
		if c.type == CRITERIA_TYPE_ACHIEVEMENT and c.asset and c.asset > 0 then
			local parents = links[c.asset]
			if not parents then
				parents = {}
				links[c.asset] = parents
			end
			local known = false
			for _, p in ipairs(parents) do
				known = known or p == metaID
			end
			if not known then
				parents[#parents + 1] = metaID
			end
		end
	end
end

-- Record for an incomplete achievement in a category, or nil when it's done, has no criteria, or has no
-- progress (pins are kept at any percent). Meta links found in its criteria go into links.
local function BuildRecord(id, categoryID, pinned, links)
	local _, name, points, completed, _, _, _, _, _, icon, rewardText, _, wasEarnedByMe = GetAchievementInfo(id)
	if not name or IsDone(completed, wasEarnedByMe) then
		return nil, nil
	end
	local criteria = ns.Ach_ReadCriteria(id)
	AddMetaLinks(links, id, criteria)
	local percent, done, total, last, have, need = ns.Ach_Percent(criteria)
	if not percent or (percent <= 0 and not pinned) then
		return nil, criteria
	end
	local cat = ns.Ach_CategoryInfo(categoryID)
	return {
		id = id, name = name, icon = icon, points = points, category = categoryID, catName = cat.name, top = cat.top,
		topID = cat.topID, expansion = cat.expansion or ns.Ach_MetaExpansion(id), percent = percent, done = done,
		total = total, last = last, have = have, need = need, reward = rewardText or "",
	}, criteria
end

local function WatchFloor()
	return Settings().threshold - WATCH_MARGIN
end

local function SetWatched(record, criteria)
	watch[record.id] = true
	record.critNames = CritNames(criteria)
end

-- Pins that can't show: done for the scope (an alt finished it, "Completed means" changed), or, after a full scan
-- (strict), loaded but without a record (no criteria). A pin whose data isn't loaded yet is kept.
local function PrunePins(strict)
	local drop = {}
	for id in pairs(ns.Ach_PinSet()) do
		if not records[id] then
			local _, name, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(id)
			if name and (strict or IsDone(completed, wasEarnedByMe)) then
				drop[#drop + 1] = id
			end
		end
	end
	if #drop > 0 then
		ns.Ach_DropPins(drop)
	end
end

-- Full scan -------------------------------------------------------------------------------------------------

local function Finish()
	local result = scan
	scan = nil
	records, metaLinks = result.records, result.metaLinks
	ready = true
	wipe(watch)
	local pins = ns.Ach_PinSet()
	local floor = WatchFloor()
	for id, record in pairs(records) do
		if record.percent >= floor or pins[id] then
			watch[id] = true
		else
			record.critNames = nil
		end
	end
	ns.Ach_FillMetaExpansions(records)
	-- Pins made while scanning, in categories already passed.
	for id in pairs(pins) do
		if not records[id] then
			local categoryID = GetAchievementCategory(id)
			if categoryID then
				local record, criteria = BuildRecord(id, categoryID, true, metaLinks)
				if record then
					records[id] = record
					SetWatched(record, criteria)
				end
			end
		end
	end
	PrunePins(true)
	ns.Ach_SaveCache()
	onChanged(nil, nil)
end

-- One achievement of the walk (Walk.lua; Feats of Strength and Legacy are skipped there).
local function Visit(id, categoryID)
	local record, criteria = BuildRecord(id, categoryID, scan.pins[id], scan.metaLinks)
	if record then
		record.critNames = CritNames(criteria)
		scan.records[id] = record
	end
end

local function CategoryDone()
	scan.pins = ns.Ach_PinSet()
	ns.AchDock_ScanStatus()
end

function ns.Ach_StartScan()
	if saveTimer then -- the records about to be replaced may be for another scope; Finish saves the new ones
		saveTimer:Cancel()
		saveTimer = nil
	end
	ns.Ach_ClearQueue()
	scan = { records = {}, metaLinks = {}, pins = ns.Ach_PinSet() }
	ns.AchWalk_Join("ach", { visit = Visit, category = CategoryDone, finish = Finish })
	onChanged(nil, nil)
end

function ns.Ach_StopScan()
	ns.Ach_FlushCache()
	scan = nil
	ns.AchWalk_Leave("ach")
	ns.Ach_ClearQueue()
	if debounceTimer then
		debounceTimer:Cancel()
		debounceTimer = nil
	end
end

-- 0-1 while scanning, nil otherwise.
function ns.Ach_ScanProgress()
	if not scan then
		return nil
	end
	return ns.AchWalk_Progress("ach") or 0
end

function ns.Ach_Records()
	return records
end

function ns.Ach_IsWatched(id)
	return watch[id] == true
end

function ns.Ach_MetaLinks()
	return metaLinks
end

function ns.Ach_SetChangedCallback(fn)
	onChanged = fn
end

-- Live updates -----------------------------------------------------------------------------------------------

local function StateOf(record)
	return record and { percent = record.percent, done = record.done, total = record.total } or nil
end

-- Re-reads one achievement. Returns changed, milestone kind (or nil).
local function Recalculate(id, pins)
	local old = records[id]
	local categoryID = old and old.category or GetAchievementCategory(id)
	if not categoryID or SKIPPED_TOP[ns.Ach_CategoryInfo(categoryID).topID] then
		return false
	end
	local record, criteria = BuildRecord(id, categoryID, pins[id], metaLinks)
	if not record then
		if old then
			records[id], watch[id] = nil, nil
			return true
		end
		return false
	end
	-- No milestone for a record seen for the first time: it was never below the threshold this session.
	local before = StateOf(old)
	records[id] = record
	if record.percent >= WatchFloor() or pins[id] then
		SetWatched(record, criteria)
	else
		watch[id] = nil
	end
	local changed = not old or old.percent ~= record.percent or old.done ~= record.done or old.have ~= record.have
	if not changed then
		return false
	end
	local kinds = fired[id] or {}
	fired[id] = kinds
	local kind = ns.Ach_Milestone(before, StateOf(record), Settings().threshold, pins[id], kinds)
	if kind then
		kinds[kind] = true
	end
	return true, kind
end

-- Recalculation runs a few milliseconds per frame (a criteria burst can touch hundreds of watched achievements);
-- the dock, tracker and toasts hear about it once the queue is empty.
local queue = { ids = {}, queued = {}, changed = {}, milestones = {} }
local recalculator = CreateFrame("Frame")
recalculator:Hide()

recalculator:SetScript("OnUpdate", function(self)
	local deadline = debugprofilestop() + BUDGET_MS
	local pins = ns.Ach_PinSet()
	while #queue.ids > 0 and debugprofilestop() < deadline do
		local id = table.remove(queue.ids)
		queue.queued[id] = nil
		local didChange, kind = Recalculate(id, pins)
		if didChange then
			queue.changed[id] = true
			if kind and records[id] then
				queue.milestones[#queue.milestones + 1] = { kind = kind, record = records[id] }
			end
		end
	end
	if #queue.ids > 0 then
		return
	end
	self:Hide()
	local changed, milestones = queue.changed, queue.milestones
	queue.changed, queue.milestones = {}, {}
	if next(changed) then
		ns.Ach_SaveCacheSoon()
		onChanged(changed, milestones)
	end
end)

local function ClearQueue()
	wipe(queue.ids)
	wipe(queue.queued)
	queue.changed, queue.milestones = {}, {}
	recalculator:Hide()
end

ns.Ach_ClearQueue = ClearQueue

local function RecalculateMany(ids)
	for _, id in ipairs(ids) do
		if not queue.queued[id] then
			queue.queued[id] = true
			queue.ids[#queue.ids + 1] = id
		end
	end
	recalculator:Show()
end

local function WatchedIDs()
	local ids = {}
	for id in pairs(watch) do
		ids[#ids + 1] = id
	end
	for id in pairs(ns.Ach_PinSet()) do
		if not watch[id] then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- One re-read pending at a time: a steady stream of updates can't keep pushing it back.
local lastRecalc = 0
function ns.Ach_OnCriteriaUpdate()
	if debounceTimer then
		return
	end
	local wait = math.max(DEBOUNCE, MIN_GAP - (GetTime() - lastRecalc))
	debounceTimer = C_Timer.NewTimer(wait, function()
		debounceTimer = nil
		if InCombatLockdown() then
			ns.Ach_OnCriteriaUpdate() -- after the fight
			return
		end
		if ready and not scan then
			lastRecalc = GetTime()
			RecalculateMany(WatchedIDs())
		end
	end)
end

function ns.Ach_OnCriteriaEarned(id)
	if id and ready and not scan then
		RecalculateMany({ id })
	end
end

-- The next step of a series shows up in the same category, and its metas move on.
function ns.Ach_OnAchievementEarned(id)
	if scan or not ready or not id then
		return
	end
	local ids = { id }
	local categoryID = GetAchievementCategory(id)
	if categoryID then
		for i = 1, GetCategoryNumAchievements(categoryID) or 0 do
			local other = GetAchievementInfo(categoryID, i)
			if other and other ~= id then
				ids[#ids + 1] = other
			end
		end
	end
	for _, parent in ipairs(metaLinks[id] or {}) do
		ids[#ids + 1] = parent
	end
	RecalculateMany(ids)
end

-- Threshold changed: what's watched follows it. Newly watched records are re-read (a few per frame) for their
-- criteria names, which search and the profession filter use.
function ns.Ach_RebuildWatch()
	local pins = ns.Ach_PinSet()
	local floor = WatchFloor()
	local fresh = {}
	for id, record in pairs(records) do
		if record.percent >= floor or pins[id] then
			watch[id] = true
			if not record.critNames then
				fresh[#fresh + 1] = id
			end
		else
			watch[id] = nil
			record.critNames = nil
		end
	end
	if #fresh > 0 and ready and not scan then
		RecalculateMany(fresh)
	end
end

-- Cache ------------------------------------------------------------------------------------------------------

local CACHED_FIELDS = { "id", "name", "icon", "points", "category", "catName", "top", "topID", "expansion", "percent",
	"done", "total", "last", "have", "need", "reward", "critNames" }

function ns.Ach_SaveCache()
	local guid = UnitGUID("player")
	if not guid then
		return
	end
	local list = {}
	for id in pairs(watch) do
		local record = records[id]
		if record then
			local copy = {}
			for _, field in ipairs(CACHED_FIELDS) do
				copy[field] = record[field]
			end
			list[#list + 1] = copy
		end
	end
	Settings().cache[guid] = { at = time(), scope = Settings().scope, records = list }
	if saveTimer then
		saveTimer:Cancel()
		saveTimer = nil
	end
end

-- Live updates save at most once a minute; PLAYER_LOGOUT and turning the module off flush a pending save.
function ns.Ach_SaveCacheSoon()
	if saveTimer then
		return
	end
	saveTimer = C_Timer.NewTimer(SAVE_GAP, function()
		saveTimer = nil
		ns.Ach_SaveCache()
	end)
end

function ns.Ach_FlushCache()
	if saveTimer then
		ns.Ach_SaveCache()
	end
end

function ns.Ach_LoadCache()
	local entry = Settings().cache[UnitGUID("player") or ""]
	if not (entry and entry.scope == Settings().scope) then
		return false
	end
	wipe(records)
	wipe(watch)
	for _, record in ipairs(entry.records or {}) do
		-- Caches from before topID was saved.
		if not record.topID and record.category then
			record.topID = ns.Ach_CategoryInfo(record.category).topID
		end
		records[record.id] = record
		watch[record.id] = true
	end
	PrunePins(false)
	onChanged(nil, nil)
	return true
end
