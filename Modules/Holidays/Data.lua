local addonName, ns = ...

-- Holidays & events: pure logic (unit-tested with plain Lua). Calendar times are realm-time CalendarTime tables;
-- they're compared as minutes on a proleptic Gregorian count, so no os/time call is needed.

local function DaysFromCivil(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function ns.Events_Minutes(t)
	return DaysFromCivil(t.year, t.month, t.monthDay) * 1440 + (t.hour or 0) * 60 + (t.minute or 0)
end

-- Months from the calendar's selected month to target ({ month, year } each).
function ns.Events_MonthOffset(selected, target)
	return (target.year - selected.year) * 12 + (target.month - selected.month)
end

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function ns.Events_MonthDays(year, month)
	if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
		return 29
	end
	return MONTH_DAYS[month]
end

-- The real dates from today on: { { offset (months from today's month), year, month, monthDay } }. Never a day 32.
function ns.Events_DayList(today, count)
	local out = {}
	local year, month, day, offset = today.year, today.month, today.monthDay, 0
	for _ = 1, count do
		if day > ns.Events_MonthDays(year, month) then
			day, offset = 1, offset + 1
			month = month + 1
			if month > 12 then
				month, year = 1, year + 1
			end
		end
		out[#out + 1] = { offset = offset, year = year, month = month, monthDay = day }
		day = day + 1
	end
	return out
end

-- { byID, byTexture, byLFG }. A texture two entries share is left out (false).
function ns.Events_Index(defs)
	local byID, byTexture, byLFG = {}, {}, {}
	for _, def in ipairs(defs) do
		for _, id in ipairs(def.ids or {}) do
			byID[id] = def
		end
		for _, tex in ipairs(def.textures or {}) do
			if byTexture[tex] == nil then
				byTexture[tex] = def
			elseif byTexture[tex] ~= def then
				byTexture[tex] = false
			end
		end
		for _, id in ipairs(def.lfg or {}) do
			byLFG[id] = def
		end
	end
	return { byID = byID, byTexture = byTexture, byLFG = byLFG }
end

function ns.Events_Lookup(index, eventID, texture)
	local def = eventID and index.byID[eventID]
	if def then
		return def
	end
	return texture and index.byTexture[texture] or nil
end

-- Active first by time left, then soon ones by start, then name.
function ns.Events_Sort(list)
	table.sort(list, function(a, b)
		if a.active ~= b.active then
			return a.active
		end
		local ka, kb = a.active and a.endsIn or a.startsIn, b.active and b.endsIn or b.startsIn
		if ka ~= kb then
			return ka < kb
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- rows: { { eventID, texture, name, description, startTime?, endTime?, day } } (day: the CalendarTime of the day the
-- row was read on). One event per occurrence: { key, def, name, description, texture, icon, active, startsIn, endsIn,
-- startTime, endTime }, minutes from now; icon is the table entry's (nil for unknown events). Ended ones and ones starting after the window are left out.
function ns.Events_Collect(rows, now, soonMinutes, index)
	local nowM = ns.Events_Minutes(now)
	local out, seen = {}, {}
	for _, r in ipairs(rows) do
		local def = ns.Events_Lookup(index, r.eventID, r.texture)
		local dayStart = ns.Events_Minutes({ year = r.day.year, month = r.day.month, monthDay = r.day.monthDay })
		local startM = r.startTime and ns.Events_Minutes(r.startTime) or dayStart
		local endM = r.endTime and ns.Events_Minutes(r.endTime) or (r.startTime and startM or dayStart) + 1440
		local key = (def and def.key or r.name or "?") .. ":" .. startM
		if not seen[key] and endM > nowM and startM - nowM <= soonMinutes then
			seen[key] = true
			out[#out + 1] = { key = key, def = def, name = r.name, description = r.description, texture = r.texture,
				icon = def and def.icon, active = startM <= nowM, startsIn = startM - nowM, endsIn = endM - nowM, startTime = r.startTime,
				endTime = r.endTime }
		end
	end
	return ns.Events_Sort(out)
end

-- The Dungeon Finder's Timewalking as an event: on now, until the weekly reset.
function ns.Events_Timewalking(dungeon, secondsToReset, def)
	return { key = "timewalking:" .. dungeon.id, def = def, name = dungeon.name, active = true, startsIn = 0,
		endsIn = math.floor((secondsToReset or 0) / 60), dungeonID = dungeon.id }
end

-- With the finder's Timewalking event: the calendar's own Timewalking row (no table entry, a Timewalking texture)
-- is dropped, the finder's added.
function ns.Events_FoldTimewalking(list, twEvent, twTextures)
	if not twEvent then
		return list
	end
	local tw = {}
	for _, t in ipairs(twTextures or {}) do
		tw[t] = true
	end
	local out = {}
	for _, ev in ipairs(list) do
		if ev.def or not (ev.texture and tw[ev.texture]) then
			out[#out + 1] = ev
		end
	end
	out[#out + 1] = twEvent
	return ns.Events_Sort(out)
end

function ns.Events_Duration(minutes)
	minutes = math.max(math.floor(minutes or 0), 1)
	if minutes >= 2 * 1440 then
		return math.floor(minutes / 1440) .. " days"
	elseif minutes >= 1440 then
		return "1 day"
	elseif minutes >= 60 then
		return math.floor(minutes / 60) .. " h"
	end
	return minutes .. " min"
end

function ns.Events_When(ev)
	if ev.active then
		return ns.Events_Duration(ev.endsIn) .. " left"
	end
	return "starts in " .. ns.Events_Duration(ev.startsIn)
end

-- What a holiday's source text can carry: names (localized, from the game), currency IDs, cost-icon paths and the
-- hand-placed extra IDs per kind.
function ns.Events_Signals(def, names)
	local s = { names = {}, currencies = {}, icons = {}, extra = {} }
	local seen = {}
	for _, n in ipairs(names or {}) do
		if type(n) == "string" and n ~= "" and not seen[n:lower()] then
			seen[n:lower()] = true
			s.names[#s.names + 1] = n:lower()
		end
	end
	for _, c in ipairs(def.currencies or {}) do
		s.currencies[c] = true
	end
	for _, i in ipairs(def.icons or {}) do
		s.icons[i:lower()] = true
	end
	for kind, ids in pairs(def.extra or {}) do
		s.extra[kind] = {}
		for _, id in ipairs(ids) do
			s.extra[kind][id] = true
		end
	end
	return s
end

function ns.Events_MatchSource(raw, signals)
	if type(raw) ~= "string" or raw == "" then
		return false
	end
	for id in raw:gmatch("|Hcurrency:(%d+)") do
		if signals.currencies[tonumber(id)] then
			return true
		end
	end
	for path in raw:gmatch("|T([^:|]+)") do
		local p = path:lower():gsub("%.blp$", "")
		if signals.icons[p] then
			return true
		end
	end
	local text = ns.Collect_Clean(raw):gsub("|n", "\n"):lower()
	return ns.Collect_LowerMentions(text, signals.names)
end

function ns.Events_MatchEntry(kind, id, raw, signals)
	if signals.extra[kind] and signals.extra[kind][id] then
		return true
	end
	return ns.Events_MatchSource(raw, signals)
end

local KINDS = {
	{ "mounts", "mount", "mounts" }, { "pets", "pet", "pets" }, { "toys", "toy", "toys" },
	{ "achievements", "achievement", "achievements" },
}

function ns.Events_Total(counts)
	local n = 0
	for _, k in ipairs(KINDS) do
		n = n + (counts[k[1]] or 0)
	end
	return n
end

-- "2 mounts, 5 pets, 3 toys and 12 achievements left", or nil when nothing is left.
function ns.Events_CountsText(counts)
	local parts = {}
	for _, k in ipairs(KINDS) do
		local n = counts[k[1]] or 0
		if n > 0 then
			parts[#parts + 1] = ("%d %s"):format(n, n == 1 and k[2] or k[3])
		end
	end
	if #parts == 0 then
		return nil
	elseif #parts == 1 then
		return parts[1] .. " left"
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts] .. " left"
end

-- skillLines: the character's professions; quests: [skillLine] = questID; isDone(questID). Open ones first.
function ns.Events_DarkmoonRows(skillLines, quests, isDone)
	local open, done = {}, {}
	for _, line in ipairs(skillLines) do
		local q = quests[line]
		if q then
			local row = { skillLine = line, questID = q, done = isDone(q) and true or false }
			table.insert(row.done and done or open, row)
		end
	end
	for _, row in ipairs(done) do
		open[#open + 1] = row
	end
	return open
end

-- dungeons: { { id, name, isHoliday, isTimeWalker, forAll, forPlayer, doneToday } }. Returns the holiday bosses
-- { { id, name, owner, eligible, doneToday } } and the first joinable Timewalking dungeon.
function ns.Events_SplitDungeons(dungeons, byLFG)
	local bosses, timewalking = {}, nil
	for _, d in ipairs(dungeons) do
		if d.forAll then
			if d.isTimeWalker then
				timewalking = timewalking or d
			elseif d.isHoliday then
				bosses[#bosses + 1] = { id = d.id, name = d.name, owner = byLFG[d.id], eligible = d.forPlayer and true or false,
					doneToday = d.doneToday and true or false }
			end
		end
	end
	return bosses, timewalking
end

function ns.Events_ShouldToast(ev, total, toasted)
	return ev.active and ev.def ~= nil and (total or 0) > 0 and not toasted[ev.key] or false
end

function ns.Events_HeadsUpKey(ev)
	return "pre:" .. ev.key
end

-- The day-before heads-up: a holiday with things left that starts within a day.
function ns.Events_ShouldHeadsUp(ev, total, toasted)
	return not ev.active and ev.def ~= nil and (ev.startsIn or 0) <= 1440 and (total or 0) > 0
		and not toasted[ns.Events_HeadsUpKey(ev)] or false
end

function ns.Events_PruneToasted(toasted, now, maxAge)
	for key, at in pairs(toasted) do
		if type(at) ~= "number" or now - at > maxAge then
			toasted[key] = nil
		end
	end
end

-- rows have `done`: open extras go after the last open row, done ones at the end.
function ns.Events_MergeTodo(rows, extra)
	local lastOpen = 0
	for i, r in ipairs(rows) do
		if not r.done then
			lastOpen = i
		end
	end
	for _, r in ipairs(extra) do
		if r.done then
			rows[#rows + 1] = r
		else
			lastOpen = lastOpen + 1
			table.insert(rows, lastOpen, r)
		end
	end
	return rows
end
