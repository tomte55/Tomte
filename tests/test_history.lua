-- Run from the AddOns folder: lua Tomte/tests/test_history.lua
local ns = {}
assert(loadfile("Tomte/Core/SessionData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Recap/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Recap/History.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local DAY = 86400
local NOW = 1800000000

local function Session(guid, start, minutes, net)
	return { guid = guid, name = guid, start = start, seen = start + minutes * 60, money = 1000, moneyNow = 1000 + (net or 0),
		level = 80, levelNow = 80, gold = { ["in"] = {}, out = {} },
		log = { { kind = "loot", title = "a", quality = 4, at = start + 10 }, { kind = "rare", title = "r", at = start + 20 } } }
end

test("compact skips short sessions and keeps the shape", function()
	eq(ns.Recap_Compact(Session("A", NOW, 1)), nil, "1 minute")
	local c = ns.Recap_Compact(Session("A", NOW, 30, 500), { zone = "Hallowfall", lootValue = 900 })
	eq(c.zone, "Hallowfall")
	eq(c.lootValue, 900)
	eq(#c.log, 2)
	eq(c.counts.rare, 1)
end)

test("archive keeps newest first, caps per character and trims old logs", function()
	local history = {}
	for i = 1, 12 do
		ns.Recap_Archive(history, ns.Recap_Compact(Session("A", NOW + i * 3600, 30)), { by = "count", count = 10 }, NOW)
	end
	ns.Recap_Archive(history, ns.Recap_Compact(Session("B", NOW + 20 * 3600, 30)), { by = "count", count = 10 }, NOW)
	eq(#history, 11)
	eq(history[1].guid, "B")
	eq(history[2].start, NOW + 12 * 3600)
	eq(history[2].trimmed, nil, "newest keep their log")
	eq(history[8].trimmed, true, "older are trimmed")
	eq(history[8].loot, nil)
	assert(#history[8].log <= 8)
end)

test("trimmed copies keep the real number of other highlights", function()
	local history = {}
	for i = 1, 7 do
		local session = Session("A", NOW + i * 3600, 30)
		if i == 1 then
			for k = 1, 20 do
				session.log[#session.log + 1] = { kind = "loot", title = "l" .. k, quality = 3, at = NOW + 100 + k }
			end
			session.log.dropped = 10 -- the live log already let ten go
		end
		ns.Recap_Archive(history, ns.Recap_Compact(session), { by = "count", count = 30 }, NOW)
	end
	local oldest = history[#history]
	eq(oldest.trimmed, true)
	eq(#oldest.log, 8)
	local shown, more = ns.Recap_Highlights(oldest.log, 5)
	eq(#shown, 5)
	eq(more, 22 + 10 - 5, "all entries plus dropped, minus shown")
	-- Copies saved before this kept no total: still work.
	local _, oldMore = ns.Recap_Highlights({ { kind = "rare" }, { kind = "loot" } }, 1)
	eq(oldMore, 1)
end)

test("archive by days drops old sessions", function()
	local history = {}
	ns.Recap_Archive(history, ns.Recap_Compact(Session("A", NOW - 40 * DAY, 30)), { by = "days", days = 28 }, NOW)
	ns.Recap_Archive(history, ns.Recap_Compact(Session("A", NOW - DAY, 30)), { by = "days", days = 28 }, NOW)
	eq(#history, 1)
	eq(history[1].start, NOW - DAY)
end)

test("filter, numbers and totals", function()
	local history = { ns.Recap_Compact(Session("A", NOW, 60, 3600 * 10000)), ns.Recap_Compact(Session("B", NOW - DAY, 30, -10000)) }
	eq(#ns.Recap_HistoryFilter(history, "char", "A"), 1)
	eq(#ns.Recap_HistoryFilter(history, "all", "A", NOW - 10), 1)
	local n = ns.Recap_HistoryNumbers(history[1])
	eq(n.duration, 3600)
	eq(n.perHour, 3600 * 10000)
	local t = ns.Recap_HistoryTotals(history)
	eq(t.count, 2)
	eq(t.net, 3600 * 10000 - 10000)
	eq(t.duration, 5400)
end)

test("nights group sessions less than the gap apart", function()
	local list = {
		ns.Recap_Compact(Session("A", NOW + 7200, 30)), -- 2:00-2:30
		ns.Recap_Compact(Session("B", NOW + 3000, 60)), -- 0:50-1:50
		ns.Recap_Compact(Session("A", NOW - DAY, 30)),
	}
	local nights = ns.Recap_HistoryNights(list, 3600)
	eq(#nights, 2)
	eq(#nights[1].sessions, 2)
	eq(nights[1].first, NOW + 3000)
	eq(nights[1].last, NOW + 7200 + 1800)
end)

test("zone time", function()
	local s = { zones = {} }
	ns.Session_ZoneTick(s, "Dornogal", 0)
	ns.Session_ZoneTick(s, "Hallowfall", 100)
	ns.Session_ZoneTick(s, "Dornogal", 400)
	eq(s.zones.Dornogal, 100)
	eq(s.zones.Hallowfall, 300)
	eq(ns.Session_TopZone(s, 500), "Hallowfall")
	eq(ns.Session_TopZone(s, 1000), "Dornogal", "current zone counted to the end")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
