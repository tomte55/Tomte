local addonName, ns = ...

-- Holidays & events: reading the game. The calendar (world events now and in the next days), the Dungeon Finder
-- (holiday bosses and Timewalking) and the Darkmoon Faire profession quests, into plain tables for Data.lua.
--
-- Month offsets are relative to the calendar's selected month, which is November 2004 until something sets it.
-- Events_Request sets it to this month (as Blizzard's calendar does when it opens) unless Blizzard's calendar is
-- open, where the player may be browsing another month: then the reader works out the offset from that month.
-- C_Calendar.GetDayEvent is secret in chat messaging lockdown: nothing is read then.

local iconGroups = { { icon = ns.EVENTS_TIMEWALKING.icon, textures = ns.EVENTS_TW_TEXTURES } }
for _, group in ipairs(ns.EVENTS_WEEKLY_ICONS) do
	iconGroups[#iconGroups + 1] = group
end
ns.EVENTS_INDEX = ns.Events_Index(ns.EVENTS_DEFS, iconGroups)

local CACHE_SECONDS = 60
local DEFAULT_SOON_DAYS = 7 -- before Events_Init (and the module default)
local FILTER_CVARS = {
	{ cvar = "calendarShowHolidays", what = "Holidays" },
	{ cvar = "calendarShowDarkmoon", what = "Darkmoon Faire" },
	{ cvar = "calendarShowWeeklyHolidays", what = "Weekly events" },
}

local db
local state, stateAt

function ns.Events_Init(moduleDB)
	db = moduleDB
end

local Secret = ns.IsSecret

local function Lockdown()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function BlizzardCalendarShown()
	return CalendarFrame ~= nil and CalendarFrame:IsShown()
end

-- Asks the server for the calendar; CALENDAR_UPDATE_EVENT_LIST follows.
function ns.Events_Request()
	if not BlizzardCalendarShown() then
		local now = C_DateAndTime.GetCurrentCalendarTime()
		if now and now.month then
			C_Calendar.SetAbsMonth(now.month, now.year)
		end
	end
	C_Calendar.OpenCalendar()
end

-- Holiday rows for today .. today + days - 1, or nil in chat messaging lockdown.
function ns.Events_ReadRows(days)
	if Lockdown() then
		return nil
	end
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local selected = C_Calendar.GetMonthInfo(0)
	if not (now and now.monthDay and selected and selected.month) then
		return {}
	end
	local base = ns.Events_MonthOffset(selected, now)
	local rows = {}
	for _, d in ipairs(ns.Events_DayList(now, days)) do
		local off = base + d.offset
		local ok, count = pcall(C_Calendar.GetNumDayEvents, off, d.monthDay)
		for i = 1, ok and type(count) == "number" and count or 0 do
			local ev = C_Calendar.GetDayEvent(off, d.monthDay, i)
			if ev and not Secret(ev.eventID) and not Secret(ev.calendarType) and not Secret(ev.title)
				and ev.calendarType == "HOLIDAY" then
				-- GetHolidayInfo takes offsets 0 and 1 only (the localized description and the whole occurrence).
				local info = (off == 0 or off == 1) and C_Calendar.GetHolidayInfo(off, d.monthDay, i) or nil
				local texture = ev.iconTexture
				if Secret(texture) then
					texture = nil
				end
				rows[#rows + 1] = {
					eventID = ev.eventID, texture = texture or (info and info.texture), name = info and info.name or ev.title,
					description = info and info.description, startTime = info and info.startTime or ev.startTime,
					endTime = info and info.endTime or ev.endTime,
					day = { year = d.year, month = d.month, monthDay = d.monthDay },
				}
			end
		end
	end
	return rows
end

-- Random dungeons from the Dungeon Finder: { { id, name, isHoliday, isTimeWalker, forAll, forPlayer, doneToday } }.
function ns.Events_ReadDungeons()
	local list = {}
	for i = 1, (GetNumRandomDungeons and GetNumRandomDungeons() or 0) do
		local id, name = GetLFGRandomDungeonInfo(i)
		if id then
			-- GetLFGDungeonInfo: 15th return isHoliday, 18th isTimeWalker (as LFDFrame.lua reads them).
			local isHoliday = select(15, GetLFGDungeonInfo(id))
			local isTimeWalker = select(18, GetLFGDungeonInfo(id))
			local forAll, forPlayer = IsLFGDungeonJoinable(id)
			local doneToday = GetLFGDungeonRewards(id)
			list[#list + 1] = { id = id, name = name, isHoliday = isHoliday, isTimeWalker = isTimeWalker, forAll = forAll,
				forPlayer = forPlayer, doneToday = doneToday }
		end
	end
	return list
end

local function Filters()
	local hidden = {}
	for _, f in ipairs(FILTER_CVARS) do
		if C_CVar.GetCVar(f.cvar) ~= nil and not C_CVar.GetCVarBool(f.cvar) then
			hidden[#hidden + 1] = f.what
		end
	end
	return hidden
end

local function Build()
	local s = { list = {}, bosses = {}, timewalking = nil, hidden = Filters(), at = GetTime() }
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local soonDays = db and db.soonDays or DEFAULT_SOON_DAYS
	local rows = ns.Events_ReadRows(soonDays)
	if not rows then
		s.lockdown = true
		rows = {}
	end
	local list = now and now.monthDay and ns.Events_Collect(rows, now, soonDays * 1440, ns.EVENTS_INDEX) or {}
	local bosses, tw = ns.Events_SplitDungeons(ns.Events_ReadDungeons(), ns.EVENTS_INDEX.byLFG)
	local twEvent = tw and ns.Events_Timewalking(tw, C_DateAndTime.GetSecondsUntilWeeklyReset(), ns.EVENTS_TIMEWALKING)
	list = ns.Events_FoldTimewalking(list, twEvent, ns.EVENTS_TW_TEXTURES)
	s.all = list -- every event, whatever the "Other events" setting (Almost Done's holiday filter)
	if db and not db.other then
		list = { unpack(list) }
		for i = #list, 1, -1 do
			if not list[i].def then
				table.remove(list, i)
			end
		end
	end
	s.list, s.bosses, s.timewalking = list, bosses, tw
	return s
end

-- { list, all, bosses, timewalking, hidden (filter names), lockdown, at }; cached for a minute.
function ns.Events_Current(force)
	if force or not state or GetTime() - stateAt > CACHE_SECONDS then
		state = Build()
		stateAt = GetTime()
	end
	return state
end

function ns.Events_Invalidate()
	state = nil
end

-- The names a holiday goes by on this client: the calendar's, its achievement category's and its maps'.
function ns.Events_Names(ev, def)
	def = def or (ev and ev.def)
	local out = {}
	local function add(name)
		if type(name) == "string" and name ~= "" then
			out[#out + 1] = name
		end
	end
	add(ev and ev.name)
	if def and def.category then
		add((GetCategoryInfo(def.category)))
	end
	for _, mapID in ipairs(def and def.maps or {}) do
		local info = C_Map.GetMapInfo(mapID)
		add(info and info.name)
	end
	return out
end

-- The bosses an event owns ({ id, name, eligible, doneToday }).
function ns.Events_BossesFor(ev)
	local out = {}
	if not ev.def then
		return out
	end
	for _, b in ipairs(ns.Events_Current().bosses) do
		if b.owner == ev.def then
			out[#out + 1] = b
		end
	end
	return out
end

-- The character's professions (archaeology, fishing and cooking too): a list of skill lines and
-- [skillLine] = localized name.
local function SkillLines()
	local lines, names = {}, {}
	local p1, p2, arch, fish, cook = GetProfessions()
	for _, index in ipairs({ p1 or 0, p2 or 0, arch or 0, fish or 0, cook or 0 }) do
		if index > 0 then
			local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine then
				lines[#lines + 1] = skillLine
				names[skillLine] = name
			end
		end
	end
	return lines, names
end
ns.Events_SkillLines = SkillLines

local function QuestTitle(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if title and title ~= "" then
		return title
	end
	C_QuestLog.RequestLoadQuestByID(questID)
	return nil
end
ns.Events_QuestTitle = QuestTitle

function ns.Events_DarkmoonActive()
	for _, ev in ipairs(ns.Events_Current().list) do
		if ev.active and ev.def and ev.def.key == "darkmoon" then
			return ev
		end
	end
	return nil
end

-- nil when the faire isn't on. Otherwise { { skillLine, questID, done, profession, title } }, open ones first
-- (empty: no profession with a faire quest).
function ns.Events_DarkmoonNow()
	if not ns.Events_DarkmoonActive() then
		return nil
	end
	local lines, names = SkillLines()
	local rows = ns.Events_DarkmoonRows(lines, ns.EVENTS_DARKMOON_QUESTS, C_QuestLog.IsQuestFlaggedCompleted)
	for _, row in ipairs(rows) do
		row.profession = names[row.skillLine] or ""
		row.title = QuestTitle(row.questID)
	end
	return rows
end

-- Opens the Dungeon Finder, with the boss selected only when the opt-in selectInFinder setting is on. Never queues.
function ns.Events_OpenFinder(dungeonID)
	if InCombatLockdown() then
		ns.Print_Combat("open the Dungeon Finder")
		return
	end
	if PVEFrame_ShowFrame and LFDParentFrame then
		PVEFrame_ShowFrame("GroupFinderFrame", LFDParentFrame)
	elseif PVEFrame_ToggleFrame then
		PVEFrame_ToggleFrame("GroupFinderFrame", LFDParentFrame)
	else
		return
	end
	if dungeonID and db and db.selectInFinder then
		if LFDFrame_DisplayDungeonByID then
			LFDFrame_DisplayDungeonByID(dungeonID)
		elseif LFDQueueFrame_SetType then
			LFDQueueFrame_SetType(dungeonID)
		end
	end
end
