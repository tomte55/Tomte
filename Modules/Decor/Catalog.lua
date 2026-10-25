local addonName, ns = ...

-- Housing decor: the catalog, read into plain tables for the page, Next up and the commands. One catalog searcher
-- (C_HousingCatalog.CreateCatalogSearcher, collected and uncollected, base variants only) lists every decor entry;
-- each entry's info (name, icon, model, owned counts, source text) is then read a few milliseconds per frame, so a
-- catalog of thousands never freezes the client. Every housing call is guarded: the API may be missing, the housing
-- service off, or an entry may error. Source text rules in Data.lua; started and stopped by Decor.lua.

local BUDGET_MS = 3 -- reading time per frame
local RETRY = 10 -- seconds to wait for search results before running the search again
local MAX_TRIES = 3 -- searches without results before giving up until the next rescan
local DECOR_TYPE = 1 -- Enum.HousingCatalogEntryType.Decor, when the enum is missing

local IsSecret = ns.IsSecret

local entries, byID, byItem = {}, {}, {} -- { id, itemID, name, icon, atlas, asset, sceneID, quality, owned, raw, ... }
local state = "idle" -- "idle" | "searching" | "reading" | "ready" | "unavailable"
local searcher -- kept while the module is on; its results callback starts each read
local reader -- hidden frame whose OnUpdate reads the entries, shown only while reading
local job -- { ids, i, entries, byID, byItem }
local tries, retryTimer = 0, nil
local onChanged = function() end

local function DecorType()
	return Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor or DECOR_TYPE
end

-- Whether this client can read the housing catalog at all, and why not.
function ns.DecorCatalog_Available()
	if not (C_HousingCatalog and C_HousingCatalog.CreateCatalogSearcher and C_HousingCatalog.GetCatalogEntryInfo) then
		return false, "This client has no housing catalog."
	end
	if C_Housing and C_Housing.IsHousingServiceEnabled then
		local ok, enabled = pcall(C_Housing.IsHousingServiceEnabled)
		if ok and enabled == false then
			return false, "Housing isn't available right now."
		end
	end
	return true
end

function ns.DecorCatalog_SetChanged(fn)
	onChanged = fn
end

-- A HousingCatalogEntryInfo as our plain entry, or nil when it isn't decor or can't be read.
local function MakeEntry(info)
	if type(info) ~= "table" or IsSecret(info.name) or type(info.name) ~= "string" or info.name == "" then
		return nil
	end
	if info.entryType ~= DecorType() or type(info.recordID) ~= "number" then
		return nil
	end
	local d = ns.Decor_Describe(type(info.sourceText) == "string" and info.sourceText or "")
	return {
		id = info.recordID, itemID = info.itemID, name = info.name, icon = info.iconTexture, atlas = info.iconAtlas,
		asset = info.asset, sceneID = info.uiModelSceneID, quality = info.quality, owned = ns.Decor_OwnedCount(info),
		raw = info.sourceText, source = d.source, line = d.line, vendor = d.vendor, zone = d.zone, zones = d.zones,
		cost = d.cost, vendors = d.vendors, categoryIDs = info.categoryIDs,
	}
end

-- One catalog read, errors from a bad entry treated as "nothing there".
local function ReadInfo(fn, ...)
	local ok, info = pcall(fn, ...)
	return ok and info or nil
end

local function Finish()
	entries, byID, byItem = job.entries, job.byID, job.byItem
	job = nil
	reader:Hide()
	state = "ready"
	onChanged()
end

local function OnUpdate()
	if not job then
		reader:Hide()
		return
	end
	local deadline = debugprofilestop() + BUDGET_MS
	while debugprofilestop() < deadline do
		local id = job.ids[job.i]
		if not id then
			Finish()
			return
		end
		job.i = job.i + 1
		local e = MakeEntry(ReadInfo(C_HousingCatalog.GetCatalogEntryInfo, id))
		if e and not job.byID[e.id] then
			job.entries[#job.entries + 1] = e
			job.byID[e.id] = e
			if e.itemID then
				job.byItem[e.itemID] = e
			end
		end
	end
end

local function CancelRetry()
	if retryTimer then
		retryTimer:Cancel()
		retryTimer = nil
	end
end

local function OnResults()
	if not searcher or state == "idle" then
		return
	end
	local ok, ids = pcall(searcher.GetCatalogSearchResults, searcher)
	if not ok or type(ids) ~= "table" then
		return
	end
	-- An empty answer right after login means the catalog isn't loaded yet (a real one holds thousands): the pending
	-- retry searches again. The last try's answer is taken as it is.
	if #ids == 0 and retryTimer and tries < MAX_TRIES then
		return
	end
	CancelRetry()
	reader = reader or CreateFrame("Frame")
	reader:SetScript("OnUpdate", OnUpdate)
	job = { ids = ids, i = 1, entries = {}, byID = {}, byItem = {} }
	state = "reading"
	reader:Show()
end

local function RunSearch()
	if not searcher then
		return
	end
	tries = tries + 1
	if state ~= "reading" then
		state = "searching"
	end
	pcall(searcher.RunSearch, searcher)
	-- The results callback can stay silent (seen right after login): search again a few times, then give up until
	-- the next scan, keeping the last finished read if there is one (else the page says the catalog can't be read).
	CancelRetry()
	retryTimer = C_Timer.NewTimer(RETRY, function()
		retryTimer = nil
		if state ~= "searching" then
			return
		end
		if tries < MAX_TRIES then
			RunSearch()
		else
			state = #entries > 0 and "ready" or "unavailable"
			onChanged()
		end
	end)
end

local function MakeSearcher()
	local ok, s = pcall(C_HousingCatalog.CreateCatalogSearcher)
	if not ok or not s then
		return nil
	end
	-- Each setter is optional: a client without one still searches with its default.
	local function Set(method, ...)
		if s[method] then
			pcall(s[method], s, ...)
		end
	end
	Set("SetAutoUpdateOnParamChanges", false)
	Set("SetCollected", true)
	Set("SetUncollected", true)
	Set("SetStoredOnly", false)
	Set("SetBaseVariantOnly", true)
	Set("SetFirstAcquisitionBonusOnly", false)
	Set("SetCustomizableOnly", false)
	Set("SetAllowedIndoors", true)
	Set("SetAllowedOutdoors", true)
	Set("SetSearchText", nil)
	Set("SetResultsUpdatedCallback", OnResults)
	return s
end

-- Reads the catalog (again). Quietly does nothing where housing isn't available.
function ns.DecorCatalog_Scan()
	if not ns.DecorCatalog_Available() then
		state = "unavailable"
		onChanged()
		return
	end
	searcher = searcher or MakeSearcher()
	if not searcher then
		state = "unavailable"
		onChanged()
		return
	end
	tries = 0
	RunSearch()
end

-- Reads one decor again after it was collected (HOUSE_DECOR_ADDED_TO_CHEST names it). true when it was known.
function ns.DecorCatalog_Update(decorID)
	local old = byID[decorID]
	if not old or not C_HousingCatalog.GetCatalogEntryInfoByRecordID then
		return false
	end
	local e = MakeEntry(ReadInfo(C_HousingCatalog.GetCatalogEntryInfoByRecordID, DecorType(), decorID))
	if not e then
		return false
	end
	-- In place (the lists hold this table), without keeping a field the new read no longer has.
	for k in pairs(old) do
		old[k] = nil
	end
	for k, v in pairs(e) do
		old[k] = v
	end
	onChanged()
	return true
end

function ns.DecorCatalog_Stop()
	CancelRetry()
	if searcher and searcher.SetResultsUpdatedCallback then
		pcall(searcher.SetResultsUpdatedCallback, searcher, function() end)
	end
	searcher, job = nil, nil
	if reader then
		reader:Hide()
	end
	entries, byID, byItem = {}, {}, {}
	state = "idle"
end

-- { state, progress (0..1 while reading), count, usable }. usable: there's a finished read to show (a new read
-- after a storage change keeps the last one until it's done).
function ns.DecorCatalog_State()
	local progress = state == "ready" and 1 or 0
	if job and #job.ids > 0 then
		progress = (job.i - 1) / #job.ids
	end
	return { state = state, progress = progress, count = #entries,
		usable = state == "ready" or (#entries > 0 and state ~= "idle" and state ~= "unavailable") }
end

-- For a progress line (UI.ProgressLine) while there's nothing to show yet: 0..1 while reading, true while waiting for
-- the game's search, nil once there's a read to show or the catalog can't be read.
function ns.DecorCatalog_Progress()
	local info = ns.DecorCatalog_State()
	if info.usable or info.state == "unavailable" then
		return nil
	end
	return info.state == "reading" and info.progress or true
end

function ns.DecorCatalog_Entries()
	return entries
end

function ns.DecorCatalog_ByID(id)
	return byID[id]
end

function ns.DecorCatalog_ByItem(itemID)
	return byItem[itemID]
end
