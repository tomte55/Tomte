local addonName, ns = ...

-- Session history for the Sessions page, pure logic (unit-tested with plain Lua). A finished session is copied into
-- db.history (account-wide, newest first) when the next one starts. The copy keeps a session's shape, so the recap
-- card can show it like the last session. Only the newest few keep their whole log and loot; older ones keep their
-- highlights and counts.

local FULL = 5 -- newest copies that keep the whole log and the loot list
local MIN_SECONDS = 120 -- shorter sessions (a reload, a quick swap) aren't kept
local KEEP_HIGHLIGHTS = 8

ns.RECAP_HISTORY_MIN = MIN_SECONDS

-- The copy kept for a finished session, or nil when it's too short. extra = { zone, lootValue, lootBy }.
function ns.Recap_Compact(session, extra)
	local endAt = session.seen or session.start
	if not session.start or endAt - session.start < MIN_SECONDS then
		return nil
	end
	local log = {}
	for i, e in ipairs(session.log or {}) do
		log[i] = e
	end
	return {
		guid = session.guid, name = session.name, class = session.class,
		start = session.start, seen = endAt,
		money = session.money, moneyNow = session.moneyNow,
		level = session.level, levelNow = session.levelNow, xpFraction = session.xpFraction, xpNow = session.xpNow,
		gold = session.gold, log = log, loot = session.loot,
		counts = ns.Recap_Counts(session.log or {}),
		zone = extra and extra.zone, lootValue = extra and extra.lootValue, lootBy = extra and extra.lootBy,
	}
end

-- Adds a copy to the front of history and prunes it. opts = { by = "count" | "days", count, days }.
-- count is per character.
function ns.Recap_Archive(history, copy, opts, now)
	table.insert(history, 1, copy)
	local perChar = {}
	for i = #history, 1, -1 do
		local h = history[i]
		local tooOld = opts.by == "days" and now - (h.seen or h.start) > (opts.days or 28) * 86400
		if tooOld then
			table.remove(history, i)
		end
	end
	for i = 1, #history do
		local h = history[i]
		perChar[h.guid] = (perChar[h.guid] or 0) + 1
		h.over = opts.by ~= "days" and perChar[h.guid] > (opts.count or 30) or nil
	end
	for i = #history, 1, -1 do
		if history[i].over then
			table.remove(history, i)
		else
			history[i].over = nil
		end
	end
	-- Older copies drop the full log and the loot list.
	for i = FULL + 1, #history do
		local h = history[i]
		if not h.trimmed then
			local shown = ns.Recap_Highlights(h.log or {}, KEEP_HIGHLIGHTS)
			h.log, h.loot, h.trimmed = shown, nil, true
		end
	end
	return history
end

-- Sessions to show: scope "char" (guid only) or "all"; since (server time) or nil for all.
function ns.Recap_HistoryFilter(history, scope, guid, since)
	local out = {}
	for _, h in ipairs(history) do
		if (scope ~= "char" or h.guid == guid) and (not since or h.start >= since) then
			out[#out + 1] = h
		end
	end
	return out
end

local function Duration(h)
	return math.max((h.seen or h.start) - h.start, 1)
end

-- One session's numbers: duration, net gold, gold per hour, loot value.
function ns.Recap_HistoryNumbers(h)
	local duration = Duration(h)
	local net = (h.moneyNow or h.money or 0) - (h.money or 0)
	return {
		duration = duration,
		net = net,
		perHour = math.floor(net * 3600 / duration),
		value = h.lootValue,
		valuePerHour = h.lootValue and math.floor(h.lootValue * 3600 / duration) or nil,
	}
end

-- Totals over a list: count, duration, net, value, perHour.
function ns.Recap_HistoryTotals(list)
	local t = { count = #list, duration = 0, net = 0, value = 0 }
	for _, h in ipairs(list) do
		local n = ns.Recap_HistoryNumbers(h)
		t.duration = t.duration + n.duration
		t.net = t.net + n.net
		t.value = t.value + (n.value or 0)
	end
	t.perHour = t.duration > 0 and math.floor(t.net * 3600 / t.duration) or 0
	return t
end

-- Play nights: sessions (newest first) less than `gap` seconds apart, any character, grouped.
-- Returns { { first = start of the oldest, last = end of the newest, sessions = { ... } } }, newest first.
function ns.Recap_HistoryNights(list, gap)
	local nights = {}
	local current
	for _, h in ipairs(list) do
		local endAt = h.seen or h.start
		if current and current.first - endAt < gap then
			current.sessions[#current.sessions + 1] = h
			current.first = math.min(current.first, h.start)
		else
			current = { first = h.start, last = endAt, sessions = { h } }
			nights[#nights + 1] = current
		end
	end
	return nights
end
