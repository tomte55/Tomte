local addonName, ns = ...

-- Holidays & events module: the world events on now and starting soon, what's still missing from each holiday
-- (mounts, pets, toys, achievements), the daily holiday boss and the Darkmoon Faire profession quests. On Home (a
-- block in the right column), as an Events page, in Next up, in the Weekly board's "Still open" list and as a toast
-- when a holiday with things left starts. Reading in Calendar.lua and Catalog.lua, pure rules in Data.lua.

local UI = ns.UI
local OWNER = "events"
local START_DELAY = 5 -- seconds after the first loading screen before the calendar is asked for
local DEBOUNCE = 1 -- seconds of events gathered into one refresh
local TOASTED_DAYS = 60 -- days a toasted occurrence is remembered
local ENDING_MINUTES = 2 * 1440 -- Next up's "Holiday ending": ends within two days
local HEAD_H = 40
local ICON = "Interface\\Icons\\INV_Misc_Toy_10"
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "CALENDAR_UPDATE_EVENT_LIST", "LFG_UPDATE_RANDOM_INFO", "LFG_COMPLETION_REWARD",
	"QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED",
	"ACHIEVEMENT_EARNED", "PLAYER_REGEN_ENABLED",
}

local module, db
local started = false
local refreshTimer, resetTimer

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function OpenPage(key)
	if ns.EventsPage_Open then
		ns.EventsPage_Open(key)
	else
		ns.Panel_OpenPage("events")
	end
end

-- Missing counts for an event: { mounts, pets, toys, achievements } or nil (no table entry, or still reading).
local function Missing(ev)
	if not (ev and ev.def) then
		return nil
	end
	return ns.EventsCatalog_Missing(ev.def, db.show)
end
ns.Events_Missing = Missing

local function Counts(ev)
	local m = Missing(ev)
	return m and m.counts or nil
end

local function EndDate(ev)
	local t = ev.endTime
	if t and t.monthDay and FormatShortDate then
		return FormatShortDate(t.monthDay, t.month)
	end
	return "in " .. ns.Events_Duration(ev.endsIn)
end

-- The key a toast is remembered by: the occurrence. The finder's Timewalking has no start time: its week then.
local function OccurrenceKey(ev)
	if ev.endTime then
		return ev.key
	end
	return ev.key .. ":" .. math.floor((GetServerTime() + (ev.endsIn or 0) * 60) / 86400)
end

-- Toasts -----------------------------------------------------------------------------------------------------------

local function ShowStartToast(ev, counts, sample)
	ns.Toast_Show({
		owner = OWNER, label = "Holiday", accent = "accent", title = ev.name .. " has started",
		text = (ns.Events_CountsText(counts) or "") .. " · ends " .. EndDate(ev),
		icon = ev.texture or ICON, mergeKey = "events:" .. ev.key, holdInCombat = true, hold = 12,
		test = sample or nil,
		onClick = not sample and function()
			OpenPage(ev.key)
		end or nil,
	})
end

local function ShowHeadsUpToast(ev, counts)
	ns.Toast_Show({
		owner = OWNER, label = "Holiday tomorrow", accent = "accent", title = ev.name .. " " .. ns.Events_When(ev),
		text = ns.Events_CountsText(counts) or "", icon = ev.texture or ICON, mergeKey = "events:pre:" .. ev.key,
		holdInCombat = true, hold = 10,
		onClick = function()
			OpenPage(ev.key)
		end,
	})
end

local function MaybeToast()
	if not module.active then
		return
	end
	local cat = ns.EventsCatalog_State()
	if not cat.ready then
		return -- tried again when the read is done
	end
	for _, ev in ipairs(ns.Events_Current().list) do
		local counts = Counts(ev)
		if counts then
			local total = ns.Events_Total(counts)
			local key = OccurrenceKey(ev)
			local probe = { key = key, def = ev.def, active = ev.active, startsIn = ev.startsIn }
			if db.toasts.start and ns.Events_ShouldToast(probe, total, db.toasted) then
				db.toasted[key] = GetServerTime()
				ShowStartToast(ev, counts)
			elseif db.toasts.before and ns.Events_ShouldHeadsUp(probe, total, db.toasted) then
				db.toasted[ns.Events_HeadsUpKey(probe)] = GetServerTime()
				ShowHeadsUpToast(ev, counts)
			end
		end
	end
end

-- Refresh ----------------------------------------------------------------------------------------------------------

local function Targets()
	local targets = {}
	for _, ev in ipairs(ns.Events_Current().list) do
		if ev.def and not targets[ev.def.key] then
			targets[ev.def.key] = ns.Events_Signals(ev.def, ns.Events_Names(ev))
		end
	end
	return targets
end

local function Redraw()
	if ns.EventsPage_Refresh then
		ns.EventsPage_Refresh()
	end
	if ns.Panel_IsShown() then
		ns.Panel_Refresh()
	end
end

local function Refresh()
	if not module.active then
		return
	end
	ns.Events_Invalidate()
	-- In chat lockdown the calendar reads empty: keep the journal read instead of dropping it and starting over.
	if not ns.Events_Current().lockdown then
		ns.EventsCatalog_Start(Targets())
	end
	MaybeToast()
	Redraw()
end

local function RefreshSoon()
	if refreshTimer then
		refreshTimer:Cancel()
	end
	refreshTimer = C_Timer.NewTimer(DEBOUNCE, function()
		refreshTimer = nil
		Refresh()
	end)
end

-- The daily reset changes the bosses' "done today" and moves the window by a day.
local function ScheduleReset()
	if resetTimer then
		resetTimer:Cancel()
	end
	local seconds = C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
	if not seconds or seconds <= 0 then
		return
	end
	-- A few seconds past the reset, presumably so the server's data has rolled over when it's read.
	resetTimer = C_Timer.NewTimer(seconds + 5, function()
		resetTimer = nil
		if module.active then
			ns.Events_Request()
			RefreshSoon()
			ScheduleReset()
		end
	end)
end

local function Start()
	if started then
		return
	end
	started = true
	C_Timer.After(START_DELAY, function()
		if module.active then
			ns.Events_Request()
			Refresh()
		end
	end)
	ScheduleReset()
end

function events:PLAYER_ENTERING_WORLD()
	Start()
end

events.CALENDAR_UPDATE_EVENT_LIST = RefreshSoon
events.LFG_UPDATE_RANDOM_INFO = RefreshSoon
events.LFG_COMPLETION_REWARD = RefreshSoon
events.QUEST_TURNED_IN = RefreshSoon
events.NEW_TOY_ADDED = RefreshSoon
events.ACHIEVEMENT_EARNED = RefreshSoon

function events:QUEST_DATA_LOAD_RESULT(questID, success)
	if not success then
		return -- a redraw would ask for it again: a once-a-second loop for a quest that doesn't load
	end
	for _, q in pairs(ns.EVENTS_DARKMOON_QUESTS) do
		if q == questID then
			RefreshSoon()
			return
		end
	end
end

function events:NEW_MOUNT_ADDED()
	ns.EventsCatalog_Earned()
end
events.NEW_PET_ADDED = events.NEW_MOUNT_ADDED

-- Toasts held by combat show by themselves; this catches a start that was seen during combat.
function events:PLAYER_REGEN_ENABLED()
	MaybeToast()
end

-- Weekly board rows ------------------------------------------------------------------------------------------------

-- Rows for the Weekly board's "Still open" list: { text, right, done }.
function ns.Events_WeeklyRows()
	if not (module and module.active and db.weekly) then
		return {}
	end
	local rows = {}
	for _, r in ipairs(ns.Events_DarkmoonNow() or {}) do
		rows[#rows + 1] = { text = ("%s: %s"):format(r.profession, r.title or "Loading..."),
			right = r.done and "done" or "Darkmoon", done = r.done }
	end
	for _, b in ipairs(ns.Events_Current().bosses) do
		if b.eligible then
			rows[#rows + 1] = { text = b.name, right = b.doneToday and "done today" or "today", done = b.doneToday }
		end
	end
	return rows
end

-- Home block ------------------------------------------------------------------------------------------------------

local function RightText(ev)
	if not ev.active then
		return ns.Events_When(ev), "textFaint"
	end
	if ev.def then
		local counts = Counts(ev)
		if not counts then
			return "reading...", "textMuted"
		end
		local total = ns.Events_Total(counts)
		if total > 0 then
			return total .. " left", "accent"
		end
		return "all done", "textFaint"
	end
	return nil, nil -- the time left is next to the name
end

local TipLine = UI.TipLine

function ns.Events_Tooltip(owner, ev)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(ev.name or "", 1, 1, 1, 1, true)
	TipLine(ns.Events_When(ev), "heading")
	if ev.description and ev.description ~= "" then
		TipLine(ev.description, "textMuted", true)
	end
	local counts = Counts(ev)
	if counts then
		TipLine(ns.Events_CountsText(counts) or "Nothing left to collect", "text")
	elseif ev.def then
		TipLine("Reading your collections...", "textMuted")
	end
	for _, b in ipairs(ns.Events_BossesFor(ev)) do
		TipLine(("%s: %s"):format(b.name, not b.eligible and "not available on this character"
			or b.doneToday and "done today" or "not done today"), b.doneToday and "textMuted" or "text")
	end
	GameTooltip:Show()
end

local function CreateSection(frame, Kit)
	frame.heading = Kit.Heading(frame)
	frame.heading:SetPoint("TOPLEFT")
	frame.heading:SetPoint("TOPRIGHT")
	frame.rows = {}
	frame.Kit = Kit
end

local function RefreshSection(frame)
	local Kit = frame.Kit
	local list = ns.Events_Current().list
	if #list == 0 then
		Kit.HideFrom(frame.rows, 1)
		return 0
	end
	local active = 0
	for _, ev in ipairs(list) do
		if ev.active then
			active = active + 1
		end
	end
	frame.heading:Set("Events", active > 0 and (active .. " on now") or "soon", "Open", function()
		OpenPage()
	end)
	local n = math.min(#list, db.homeRows)
	for i = 1, n do
		local ev = list[i]
		local row = Kit.PoolRow(frame.rows, i, frame)
		local right, rightColor = RightText(ev)
		local text = ev.active and (ev.name .. "  " .. UI.Wrap(ns.Events_When(ev), "textMuted")) or ev.name
		row:Set(ev.texture or ICON, text, ev.active and "text" or "textMuted", right, rightColor)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(HEAD_H + (i - 1) * Kit.ROW_H))
		row:SetPoint("RIGHT")
		row.onClick = function()
			OpenPage(ev.key)
		end
		row.onEnter = function(self)
			ns.Events_Tooltip(self, ev)
		end
	end
	Kit.HideFrom(frame.rows, n + 1)
	return HEAD_H + n * Kit.ROW_H
end

-- Next up ---------------------------------------------------------------------------------------------------------

local function OwnerEvent(def)
	for _, ev in ipairs(ns.Events_Current().list) do
		if ev.def == def and ev.active then
			return ev
		end
	end
	return nil
end

local function Today()
	local t = C_DateAndTime.GetCurrentCalendarTime()
	return t and ("%d-%d-%d"):format(t.year, t.month, t.monthDay) or "today"
end

local function BossCandidates()
	local list = {}
	for _, b in ipairs(ns.Events_Current().bosses) do
		if b.eligible and not b.doneToday then
			local ev = b.owner and OwnerEvent(b.owner)
			local id = b.id
			list[#list + 1] = {
				key = "events:boss:" .. id, state = Today(), text = ("%s: not done today"):format(b.name),
				why = ev and ("%s daily boss, %s"):format(ev.name, ns.Events_When(ev)) or "Holiday daily boss",
				icon = ev and ev.texture or ICON,
				onClick = function()
					ns.Events_OpenFinder(id)
				end, hint = "Click to open the Dungeon Finder",
			}
		end
	end
	return list
end

local function EndingCandidates()
	local list = {}
	for _, ev in ipairs(ns.Events_Current().list) do
		if ev.active and ev.def and ev.endsIn <= ENDING_MINUTES then
			local counts = Counts(ev)
			local total = counts and ns.Events_Total(counts) or 0
			if total > 0 then
				local key = ev.key
				list[#list + 1] = {
					key = "events:end:" .. key, state = total,
					text = ("%s ends in %s"):format(ev.name, ns.Events_Duration(ev.endsIn)),
					why = ns.Events_CountsText(counts), icon = ev.texture or ICON,
					onClick = function()
						OpenPage(key)
					end, hint = "Click for the list",
				}
			end
		end
	end
	return list
end

local function DarkmoonCandidates()
	local rows = ns.Events_DarkmoonNow()
	if not rows then
		return {}
	end
	local open = {}
	for _, r in ipairs(rows) do
		if not r.done then
			open[#open + 1] = r.profession
		end
	end
	if #open == 0 then
		return {}
	end
	local ev = ns.Events_DarkmoonActive()
	return { {
		key = "events:dmf", state = #open,
		text = #open == 1 and "1 Darkmoon Faire profession quest" or (#open .. " Darkmoon Faire profession quests"),
		why = table.concat(open, ", "), icon = ev and ev.texture or ICON,
		onClick = function()
			OpenPage(ev and ev.key)
		end, hint = "Click for the list",
	} }
end

-- Commands --------------------------------------------------------------------------------------------------------

local function RequireActive()
	if not module.active then
		ns.Print("Holidays & events is off.")
		return false
	end
	return true
end

local function List()
	if not RequireActive() then
		return
	end
	local s = ns.Events_Current(true)
	if s.lockdown then
		ns.Print("the calendar can't be read right now (chat lockdown).")
	end
	if #s.list == 0 then
		ns.Print("no events now or in the next " .. db.soonDays .. " days.")
	end
	for _, ev in ipairs(s.list) do
		local counts = Counts(ev)
		local what = counts and (ns.Events_CountsText(counts) or "nothing left")
			or (ev.def and "still reading your collections" or "")
		ns.Print(("%s: %s%s"):format(ev.name, ns.Events_When(ev), what ~= "" and (", " .. what) or ""))
		for _, b in ipairs(ns.Events_BossesFor(ev)) do
			print(("  %s: %s"):format(b.name, not b.eligible and "not available on this character"
				or b.doneToday and "done today" or "not done today"))
		end
	end
	local dmf = ns.Events_DarkmoonNow()
	if dmf then
		if #dmf == 0 then
			print("  No profession quests for this character.")
		end
		for _, r in ipairs(dmf) do
			print(("  Darkmoon %s: %s (%s)"):format(r.profession, r.title or "Loading...", r.done and "done" or "open"))
		end
	end
	if #s.hidden > 0 then
		print("  Hidden by your calendar filter: " .. table.concat(s.hidden, ", "))
	end
end

local function Stamp(t)
	if not t then
		return "-"
	end
	return ("%d-%02d-%02d %02d:%02d"):format(t.year or 0, t.month or 0, t.monthDay or 0, t.hour or 0, t.minute or 0)
end

-- Raw calendar rows for today and the calendar filter CVars: shows whether a row's eventID is a holiday ID the
-- table knows and whether a filter hides rows.
local function CalendarDump()
	local rows = ns.Events_ReadRows(1)
	if not rows then
		ns.Print("chat lockdown: the calendar can't be read now.")
		return
	end
	local selected = C_Calendar.GetMonthInfo(0)
	ns.Print(("calendar month %d/%d, %d holiday rows today:"):format(selected.month or 0, selected.year or 0, #rows))
	for _, r in ipairs(rows) do
		local def = ns.Events_Lookup(ns.EVENTS_INDEX, r.eventID, r.texture)
		print(("  eventID %s, texture %s, %s, %s to %s%s"):format(tostring(r.eventID), tostring(r.texture),
			tostring(r.name), Stamp(r.startTime), Stamp(r.endTime), def and (" -> " .. def.key) or ""))
	end
	for _, cvar in ipairs({ "calendarShowHolidays", "calendarShowDarkmoon", "calendarShowWeeklyHolidays",
		"calendarShowBattlegrounds" }) do
		print(("  %s = %s"):format(cvar, tostring(C_CVar.GetCVar(cvar))))
	end
end

local function Ids()
	local _, names = ns.Events_SkillLines()
	local lines = {}
	for skillLine, questID in pairs(ns.EVENTS_DARKMOON_QUESTS) do
		lines[#lines + 1] = { skillLine = skillLine, questID = questID }
	end
	table.sort(lines, function(a, b)
		return a.questID < b.questID
	end)
	ns.Print("Darkmoon Faire profession quests:")
	for _, l in ipairs(lines) do
		print(("  %d  skill line %d%s: %s%s"):format(l.questID, l.skillLine, names[l.skillLine] and
			(" (" .. names[l.skillLine] .. ")") or "", ns.Events_QuestTitle(l.questID) or "loading, run again",
			C_QuestLog.IsQuestFlaggedCompleted(l.questID) and " - done" or ""))
	end
end

local function Test()
	if not RequireActive() then
		return
	end
	ShowStartToast({ key = "sample", name = "Hallow's End", texture = 235461, endsIn = 6 * 1440 },
		{ mounts = 1, pets = 2, toys = 3, achievements = 5 }, true)
end

local function OpenCalendar()
	if ToggleCalendar then
		ToggleCalendar()
	end
end
ns.Events_OpenCalendar = OpenCalendar

-- Module ----------------------------------------------------------------------------------------------------------

local function Summary()
	local list = ns.Events_Current().list
	local ev = list[1]
	if not ev then
		return "Nothing on"
	end
	return ("%s · %s"):format(ev.name, ev.active and ns.Events_Duration(ev.endsIn) or ns.Events_When(ev))
end

local function SettingChanged()
	Refresh()
end

module = ns.RegisterModule({
	key = "events",
	name = "Holidays & events",
	category = "Collections",
	description = "The world events on now and starting soon, what you're still missing from each holiday (mounts, battle pets, toys, achievements), the holiday's daily boss and the Darkmoon Faire profession quests. On Home, on an Events page, in Next up and as a toast when a holiday starts.",
	enabledByDefault = true,
	defaults = {
		home = true,
		homeRows = 4,
		soonDays = 7,
		other = true,
		show = { mounts = true, pets = true, toys = true, achievements = true },
		toasts = { start = true, before = false },
		weekly = true,
		selectInFinder = false, -- opt-in: selecting from addon code may taint the queue
		collapsed = {}, -- [eventKey .. kind] = true
		toasted = {}, -- [occurrence key] = server time; a collection, kept on reset
	},
	init = function(saved)
		db = saved
		ns.Events_Init(db)
		ns.EventsPage_Init(db)
		ns.Events_PruneToasted(db.toasted, GetServerTime(), TOASTED_DAYS * 86400)
		ns.EventsCatalog_SetChanged(function()
			MaybeToast()
			Redraw()
		end)
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			if ns.inWorld then
				Start()
			end
		else
			events:UnregisterAllEvents()
			started = false
			if refreshTimer then
				refreshTimer:Cancel()
				refreshTimer = nil
			end
			if resetTimer then
				resetTimer:Cancel()
				resetTimer = nil
			end
			ns.EventsCatalog_Stop()
			ns.Toast_Clear(OWNER)
		end
	end,
	home = {
		{ kind = "section", slot = "events", key = "eventssection", Create = CreateSection, Refresh = RefreshSection,
			shown = function()
				return db.home
			end },
		{ kind = "page", key = "events", order = 41, name = "Events", icon = ICON, page = ns.EventsPage,
			summary = Summary },
		{ kind = "next", key = "nextholidayboss", name = "Holiday daily boss", score = 70,
			description = "A holiday's daily boss you haven't done today (click to open the Dungeon Finder).",
			candidates = BossCandidates },
		{ kind = "next", key = "nextevent", name = "Holiday ending", score = 60,
			description = "A holiday that ends within two days while you still miss things from it.",
			candidates = EndingCandidates },
		{ kind = "next", key = "nextdarkmoon", name = "Darkmoon Faire profession quests", score = 50,
			description = "The faire's monthly profession quests you haven't done yet.",
			candidates = DarkmoonCandidates },
	},
	commands = {
		{ "", "open the Events page", function()
			OpenPage()
		end, hidden = true },
		{ "open", "open the Events page", function()
			OpenPage()
		end },
		{ "list", "what's on, what's left and the daily boss, printed", List },
		{ "calendar", "today's raw calendar rows and the calendar filters", CalendarDump },
		{ "ids", "the Darkmoon Faire quest IDs with the names the game gives", Ids },
		{ "test", "show a sample toast", Test },
	},
	options = {
		{ type = "header", label = "Home" },
		{ type = "checkbox", key = "home", label = "Show on Home", onChange = Redraw,
			tooltip = "A block in Home's right column: the events on now with what's left, then the ones starting soon." },
		{ type = "slider", key = "homeRows", label = "Rows on Home", min = 2, max = 8, step = 1, onChange = Redraw },
		{ type = "header", label = "Events" },
		{ type = "slider", key = "soonDays", label = "Starting within (days)", min = 1, max = 14, step = 1,
			onChange = SettingChanged },
		{ type = "checkbox", key = "other", label = "Other events", onChange = SettingChanged,
			tooltip = "Also list the calendar's other world events (weekly bonus events, anniversaries) with their time left." },
		{ type = "header", label = "What's left" },
		{ type = "checkbox", key = "show.mounts", label = "Mounts", onChange = SettingChanged },
		{ type = "checkbox", key = "show.pets", label = "Battle pets", onChange = SettingChanged },
		{ type = "checkbox", key = "show.toys", label = "Toys", onChange = SettingChanged },
		{ type = "checkbox", key = "show.achievements", label = "Achievements", onChange = SettingChanged },
		{ type = "header", label = "Toasts" },
		{ type = "checkbox", key = "toasts.start", label = "When a holiday starts",
			tooltip = "Once per holiday, when you still miss something from it." },
		{ type = "checkbox", key = "toasts.before", label = "A day before a holiday starts",
			tooltip = "A heads-up the day before, when you still miss something from it." },
		{ type = "button", label = "Sample toast", text = "Show", onClick = Test },
		{ type = "header", label = "Elsewhere" },
		{ type = "checkbox", key = "weekly", label = "Weekly board rows", onChange = Redraw,
			tooltip = "While the Darkmoon Faire is on, its profession quests in the Weekly board's \"Still open\" list on Home, and the holiday's daily boss." },
		{ type = "checkbox", key = "selectInFinder", label = "Select the boss in the Dungeon Finder",
			tooltip = "Clicking a daily boss opens the Dungeon Finder with the boss picked. Off by default: picking it from an addon may make queueing afterwards give an error, and off, the finder opens without picking." },
		{ type = "button", label = "Calendar", text = "Open", onClick = OpenCalendar },
	},
})
