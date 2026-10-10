local addonName, ns = ...

-- Almost Done module: near-complete achievements in a list docked to the Achievements window (Dock.lua), a Top 5
-- tracker (Tracker.lua) and toasts at milestones (almost done, one step left, progress on a pinned one).
-- Scanning in Scan.lua, rewards in Rewards.lua, metas in Metas.lua, pure logic in Data.lua. Replaces
-- AlmostCompletedAchievements.

local OWNER = "ach"
local MAX_PINS = 5
local SCAN_DELAY = 5 -- seconds after the first loading screen
local HOLIDAY_TTL = 300 -- seconds the calendar's holiday list is reused
local ACCENTS = {
	almost = { 1, 0.82, 0.45 },
	lastStep = { 0.5, 0.88, 0.5 },
	pinned = { 0.55, 0.78, 1 },
}
local LABELS = { almost = "Almost done", lastStep = "One step left", pinned = "Pinned" }
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "CRITERIA_UPDATE", "CRITERIA_EARNED", "ACHIEVEMENT_EARNED", "NEW_MOUNT_ADDED",
	"NEW_PET_ADDED", "NEW_TOY_ADDED", "TRANSMOG_COLLECTION_UPDATED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"CALENDAR_UPDATE_EVENT_LIST", "SKILL_LINES_CHANGED", "PLAYER_LOGOUT",
}

local module, db
local scheduled = false
local holidays, holidaysAt = nil, 0
local professions

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

-- Pins and ignores --------------------------------------------------------------------------------------------

local function Pins()
	local guid = UnitGUID("player") or "?"
	db.pins[guid] = db.pins[guid] or {}
	return db.pins[guid]
end

function ns.Ach_Pins()
	return Pins()
end

-- Read-only: built once and reused until the pins change (the list asks once per row).
local pinSet
function ns.Ach_PinSet()
	if not pinSet then
		pinSet = {}
		for _, id in ipairs(Pins()) do
			pinSet[id] = true
		end
	end
	return pinSet
end

local function RemovePin(id)
	local pins = Pins()
	for i = #pins, 1, -1 do
		if pins[i] == id then
			table.remove(pins, i)
		end
	end
	pinSet = nil
end

function ns.Ach_IsPinned(id)
	return ns.Ach_PinSet()[id] == true
end

local function Changed()
	ns.AchDock_Refresh()
	ns.AchTracker_Refresh()
end

function ns.Ach_Pin(id)
	local pins = Pins()
	if ns.Ach_IsPinned(id) then
		return
	end
	if #pins >= MAX_PINS then
		ns.Print(("you can pin %d achievements. Unpin one first."):format(MAX_PINS))
		return
	end
	pins[#pins + 1] = id
	pinSet = nil
	ns.Ach_OnCriteriaEarned(id) -- builds its record at any percent and watches it
	Changed()
end

function ns.Ach_Unpin(id)
	RemovePin(id)
	Changed()
end

-- Pins that can't show (done for the scope): they'd still count toward the limit with nothing to unpin.
function ns.Ach_DropPins(ids)
	for _, id in ipairs(ids) do
		RemovePin(id)
	end
end

function ns.Ach_IsIgnored(id)
	return db.ignored[id] == true
end

function ns.Ach_SetIgnored(id, ignored)
	db.ignored[id] = ignored and true or nil
	Changed()
end

-- Filter context ----------------------------------------------------------------------------------------------

local function Professions()
	if professions then
		return professions
	end
	professions = {}
	for _, index in pairs({ GetProfessions() }) do
		local name = index and GetProfessionInfo(index)
		if name then
			professions[#professions + 1] = name
		end
	end
	return professions
end

-- Lower-case holiday titles from yesterday to tomorrow (this month only: the calendar is opened on this month).
local function Holidays()
	if holidays and GetTime() - holidaysAt < HOLIDAY_TTL then
		return holidays
	end
	holidays, holidaysAt = {}, GetTime()
	local now = C_DateAndTime.GetCurrentCalendarTime()
	if not (now and now.monthDay) then
		return holidays
	end
	for day = math.max(now.monthDay - 1, 1), now.monthDay + 1 do
		-- pcall: the day after the last of the month isn't a valid day.
		local ok, count = pcall(C_Calendar.GetNumDayEvents, 0, day)
		for i = 1, ok and count or 0 do
			local info = C_Calendar.GetHolidayInfo(0, day, i)
			if info and info.name then
				holidays[#holidays + 1] = info.name:lower()
			end
		end
	end
	return holidays
end

local function Context(searchText)
	return {
		pinned = ns.Ach_PinSet(), ignored = db.ignored, professions = Professions(), holidays = Holidays(),
		searchText = (searchText or ""):lower(), rewardInfo = ns.Ach_RewardInfo,
	}
end

-- The dock's list: filtered and sorted by the sort setting.
function ns.Ach_List(searchText)
	local ctx = Context(searchText)
	local list = {}
	for _, record in pairs(ns.Ach_Records()) do
		if ns.Ach_Passes(record, db, ctx) then
			list[#list + 1] = record
		end
	end
	ns.Ach_Sort(list, db.sort)
	return list
end

-- The tracker's rows: pins, then the highest percent.
function ns.Ach_Top(n)
	local ctx = Context("")
	ctx.pinned = {} -- pins come first anyway; the fill follows the filters
	local list = {}
	for _, record in pairs(ns.Ach_Records()) do
		if ns.Ach_Passes(record, db, ctx) then
			list[#list + 1] = record
		end
	end
	ns.Ach_Sort(list, "percent")
	return ns.Ach_TopN(list, Pins(), ns.Ach_Records(), n)
end

function ns.Ach_Settings()
	return db
end

-- Every top category and expansion the records have, for the filter menu.
function ns.Ach_FilterChoices()
	local tops, seen = {}, {}
	for _, record in pairs(ns.Ach_Records()) do
		local top = record.top or ns.ACH_OTHER
		if not seen[top] then
			seen[top] = true
			tops[#tops + 1] = top
		end
	end
	table.sort(tops)
	local expansions = {}
	for i, e in ipairs(ns.ACH_EXPANSIONS) do
		expansions[i] = e
	end
	expansions[#expansions + 1] = ns.ACH_OTHER
	return tops, expansions
end

function ns.Ach_Open(id)
	if InCombatLockdown() and not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
		ns.Print("the Achievements window opens after combat.")
		return
	end
	if ShowAchievementFrameForAchievement then
		ShowAchievementFrameForAchievement(id)
	elseif OpenAchievementFrameToAchievement then
		OpenAchievementFrameToAchievement(id)
	end
end

function ns.Ach_Link(id)
	local link = GetAchievementLink(id)
	-- ChatEdit_InsertLink moved to ChatFrameUtil in recent clients; use whichever exists.
	local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if link and insert then
		insert(link)
	end
end

-- Toasts ------------------------------------------------------------------------------------------------------

local ProgressText = ns.Ach_ProgressText

local function ToastText(kind, record)
	if kind == "lastStep" then
		return record.last and ("Left: " .. record.last) or ProgressText(record)
	end
	local text = ProgressText(record)
	if kind == "almost" and record.reward ~= "" then
		text = text .. "\n" .. record.reward
	end
	return text
end

-- sample: a test toast (no click action, kept out of Recent).
local function ShowToast(kind, record, sample)
	local accent = ACCENTS[kind]
	ns.Toast_Show({
		owner = OWNER, label = LABELS[kind], accent = accent, title = record.name, text = ToastText(kind, record),
		icon = record.icon, mergeKey = "ach:" .. record.id, holdInCombat = true, hold = 8, test = sample or nil,
		onClick = not sample and function()
			ns.Ach_Open(record.id)
		end or nil,
	})
end

local function OnChanged(changed, milestones)
	ns.AchDock_Refresh()
	ns.AchTracker_Refresh(changed)
	for _, m in ipairs(milestones or {}) do
		if db.toasts[m.kind] then
			ShowToast(m.kind, m.record)
		end
	end
end

-- Events ------------------------------------------------------------------------------------------------------

local function StartUp()
	if scheduled then
		return
	end
	scheduled = true
	ns.Ach_LoadCache()
	ns.AchTracker_Apply(InCombatLockdown())
	C_Calendar.OpenCalendar()
	C_Timer.After(SCAN_DELAY, function()
		if module.active then
			ns.Ach_StartScan()
		end
	end)
end

function events:PLAYER_ENTERING_WORLD()
	StartUp()
end

events.CRITERIA_UPDATE = function()
	ns.Ach_OnCriteriaUpdate()
end

function events:CRITERIA_EARNED(id)
	ns.Ach_OnCriteriaEarned(id)
end

function events:ACHIEVEMENT_EARNED(id)
	if ns.Ach_IsPinned(id) then
		RemovePin(id)
	end
	ns.Ach_OnAchievementEarned(id)
	Changed()
end

local function RewardsChanged()
	ns.Ach_RewardsChanged()
	ns.AchDock_Refresh()
end
events.NEW_MOUNT_ADDED = RewardsChanged
events.NEW_PET_ADDED = RewardsChanged
events.NEW_TOY_ADDED = RewardsChanged
events.TRANSMOG_COLLECTION_UPDATED = RewardsChanged

function events:PLAYER_REGEN_DISABLED()
	ns.AchTracker_Apply(true)
end

function events:PLAYER_REGEN_ENABLED()
	ns.AchTracker_Apply(false)
end

function events:CALENDAR_UPDATE_EVENT_LIST()
	holidays = nil
end

function events:SKILL_LINES_CHANGED()
	professions = nil
end

function events:PLAYER_LOGOUT()
	ns.Ach_FlushCache()
end

-- Commands and options ----------------------------------------------------------------------------------------

local function RequireActive()
	if not module.active then
		ns.Print("Almost Done is off.")
		return false
	end
	return true
end

local function Rescan()
	if RequireActive() then
		ns.Ach_StartScan()
		ns.Print("scanning achievements...")
	end
end

local function Test()
	if not RequireActive() then
		return
	end
	local list = ns.Ach_List("")
	local record = list[1] or { id = 6, name = "Level 10", icon = 236376, percent = 85, done = 4, total = 5,
		last = "Reach level 10", reward = "Title Reward: the Patient" }
	ShowToast("almost", record, true)
	ShowToast("lastStep", setmetatable({ id = -1 }, { __index = record }), true)
	ShowToast("pinned", setmetatable({ id = -2 }, { __index = record }), true)
end

local function ThresholdChanged()
	ns.Ach_RebuildWatch()
	Changed()
end

-- Next up: the names of where you are (zone up to continent), to put "Treasures of the Isle of Dorn" first in
-- Dornogal. Achievements have no zone of their own; the name is the best hint there is.
local function HereNames()
	local names = {}
	local mapID = C_Map.GetBestMapForUnit("player")
	for _ = 1, 6 do
		local info = mapID and C_Map.GetMapInfo(mapID)
		if not info or info.mapType < Enum.UIMapType.Continent then
			break
		end
		if info.name and #info.name >= 4 then
			names[#names + 1] = info.name
		end
		mapID = info.parentMapID
	end
	return names
end

local function NamedAfter(name, places)
	for _, place in ipairs(places) do
		if name and name:find(place, 1, true) then
			return true
		end
	end
	return false
end

module = ns.RegisterModule({
	key = "ach",
	conflicts = { { addon = "AlmostCompletedAchievements", why = "Almost Done stays off while it's enabled" } },
	name = "Almost Done",
	category = "Achievements",
	description = "Near-complete achievements in a list next to the Achievements window, with rewards (owned ones greyed out), a meta browser, a Top 5 tracker and toasts when something is almost done.",
	enabledByDefault = true,
	defaults = {
		threshold = 80, sort = "percent", reward = "any", scope = "account", showIgnored = false,
		categories = {}, -- [top category name] = false when hidden
		expansions = {}, -- [expansion or "Other"] = false when hidden
		professions = "mine", events = "running",
		ignored = {}, -- [achievementID] = true, account-wide
		pins = {}, -- [player GUID] = { achievementID, ... }
		cache = {}, -- [player GUID] = { at, scope, records }
		dock = { open = true },
		tracker = { shown = true, locked = false, hideInCombat = true, scale = 1 },
		toasts = { almost = true, lastStep = true, pinned = true },
		preview = true,
	},
	home = {
		{ kind = "next", key = "nextach", name = "Achievements one step from done", score = 65,
			description = "Achievements with one step left, and your pinned ones (from Almost Done's list and filters). "
				.. "The ones named after where you are come first.",
			candidates = function()
				local list = {}
				local here = HereNames()
				for _, r in ipairs(ns.Ach_Top(40)) do
					local oneLeft = r.total and r.total >= 2 and r.total - r.done == 1
					if oneLeft or r.pinned then
						local near = NamedAfter(r.name, here)
						local id = r.id
						list[#list + 1] = {
							key = "ach:" .. id, state = r.done,
							text = r.name,
							why = oneLeft and (r.last and ("One step left: " .. r.last) or "One step left.")
								or ("Pinned, " .. ns.Ach_ProgressText(r, ", ")),
							right = ("%d/%d"):format(r.have or r.done, r.need or r.total), icon = r.icon,
							bonus = (near and 6 or 0) + (r.pinned and 2 or 0) + (oneLeft and 1 or 0),
							onClick = function()
								ns.Ach_Open(id)
							end, hint = "Click to open it",
						}
					end
				end
				return list
			end },
	},
	init = function(saved)
		db = saved
		ns.achDB = saved
		ns.Ach_SetChangedCallback(OnChanged)
	end,
	blocked = function()
		if C_AddOns.IsAddOnLoaded("AlmostCompletedAchievements") then
			return "The AlmostCompletedAchievements addon is still enabled. Disable it and /reload to switch over."
		end
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			ns.AchDock_Init()
			if ns.inWorld then
				StartUp()
			end
		else
			events:UnregisterAllEvents()
			scheduled = false
			ns.Ach_StopScan()
			ns.AchTracker_Apply()
			ns.AchDock_Refresh()
			ns.Toast_Clear(OWNER)
		end
	end,
	commands = {
		{ "scan", "scan all achievements again", Rescan },
		{ "tracker", "show or hide the Top 5 tracker", function()
			if RequireActive() then
				db.tracker.shown = not db.tracker.shown
				ns.AchTracker_Apply()
			end
		end },
		{ "lock", "lock the tracker", function()
			if RequireActive() then
				db.tracker.locked = true
				ns.AchTracker_Apply()
			end
		end },
		{ "unlock", "move the tracker", function()
			if RequireActive() then
				db.tracker.locked = false
				db.tracker.shown = true
				ns.AchTracker_Apply()
				ns.Print("drag the tracker, then /tomte ach lock.")
			end
		end },
		{ "test", "show sample toasts", Test },
	},
	options = {
		{ type = "header", label = "List" },
		{ type = "slider", key = "threshold", label = "Almost done at", min = 50, max = 100, step = 5,
			format = function(v)
				return v .. "%"
			end, onChange = ThresholdChanged,
			tooltip = "Achievements at or above this share of their criteria are listed and tracked." },
		{ type = "checkbox", key = "dock.open", label = "Open with the Achievements window", onChange = function()
			ns.AchDock_Refresh()
		end, tooltip = "Show the list next to the Achievements window. Off: a small tab on its edge opens it." },
		{ type = "checkbox", key = "preview", label = "Reward preview", onChange = function()
			ns.AchDock_Refresh()
		end, tooltip = "Show a model of mount, pet and appearance rewards under the list." },

		{ type = "header", label = "Tracker" },
		{ type = "checkbox", key = "tracker.shown", label = "Show the Top 5 tracker", onChange = function()
			ns.AchTracker_Apply()
		end, tooltip = "Pinned achievements first, then the closest ones." },
		{ type = "checkbox", key = "tracker.locked", label = "Locked", onChange = function()
			ns.AchTracker_Apply()
		end, tooltip = "Unlock to drag the tracker. Blizzard's Edit Mode moves it too." },
		{ type = "checkbox", key = "tracker.hideInCombat", label = "Hide in combat", onChange = function()
			ns.AchTracker_Apply()
		end },
		{ type = "slider", key = "tracker.scale", label = "Scale", min = 0.8, max = 1.4, step = 0.05,
			format = function(v)
				return ("%.2f"):format(v)
			end, onChange = function()
				ns.AchTracker_Apply()
			end },

		{ type = "header", label = "Toasts" },
		{ type = "checkbox", key = "toasts.almost", label = "Almost done",
			tooltip = "When an achievement reaches the threshold." },
		{ type = "checkbox", key = "toasts.lastStep", label = "One step left",
			tooltip = "When only one criterion is left." },
		{ type = "checkbox", key = "toasts.pinned", label = "Progress on pinned achievements",
			tooltip = "Every step on an achievement you pinned." },
		{ type = "button", label = "Sample toasts", text = "Show", onClick = Test },

		{ type = "header", label = "Data" },
		{ type = "button", label = "Scan all achievements again", text = "Rescan", onClick = Rescan },
		{ type = "button", label = function()
			local n = 0
			for _ in pairs(db and db.ignored or {}) do
				n = n + 1
			end
			return ("Ignored achievements: %d"):format(n)
		end, text = "Clear", confirm = "Show every ignored achievement again?", onClick = function()
			wipe(db.ignored)
			Changed()
		end },
	},
})
ns.achModule = module
