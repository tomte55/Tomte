local addonName, ns = ...

-- Performance measuring: pure logic (no WoW API calls; unit-tested in tests/test_perfdata.lua). Which file a stack
-- line points at, which group (module folder) that file belongs to, and how one timed call adds to the totals. The
-- clock and the hooks are in Perf.lua; the page and its rules in Modules/Performance.

ns.PERF_SLOW_MS = 5 -- a call this long is worth a look
ns.PERF_HITCH_MS = 16 -- a call this long costs a frame at 60 fps
ns.PERF_HITCHES_KEPT = 30
ns.PERF_LOGIN_SECONDS = 20 -- after the first loading screen, calls also count as "login"

-- Folders outside Modules/ that get a group of their own, by the name a player would know them.
local FOLDER_GROUPS = { Core = "Core", Panel = "Window", Cinematic = "Cinematics", Themes = "Themes", Data = "Data" }

-- The Tomte file a debugstack line points at, without ".lua": "Modules/Bags/Read", "Core/Core". nil when the line
-- names no file. Only Tomte's own code asks, so the line is always one of ours. The client may shorten long chunk
-- names from the left ("...odules/Bags/Read.lua"), so only the last folder and the file are read: a folder that
-- isn't one of the top ones is a module folder.
function ns.Perf_SourceOf(line)
	if type(line) ~= "string" then
		return nil
	end
	local folder, file
	for f, name in line:gmatch("([%w_]+)[/\\]([%w_]+)%.lua") do
		folder, file = f, name
	end
	if not folder then
		return nil
	end
	if FOLDER_GROUPS[folder] then
		return folder .. "/" .. file
	end
	return "Modules/" .. folder .. "/" .. file
end

-- The group a source counts under ("Bags", "Core", "Window") and the file inside it ("Read"). nil source: "Other".
function ns.Perf_GroupOf(source)
	if not source then
		return "Other", "?"
	end
	local folder, file = source:match("^Modules/([^/]+)/(.+)$")
	if folder then
		return folder, file
	end
	local top, rest = source:match("^([^/]+)/(.+)$")
	if top then
		return FOLDER_GROUPS[top] or top, rest
	end
	return "Other", source
end

local function NewStat()
	return { calls = 0, total = 0, peak = 0, slow = 0, hitches = 0, kb = 0, login = 0, by = {} }
end
ns.Perf_NewStat = NewStat

-- One timed call into stats[group]: ms it took, kb it allocated (negative when a GC step ran: counts as 0), sub (a
-- bus owner or a file) and what (an event or a script), login while the login window is open. Returns the group's
-- stat. A table per group, sub and what, created on first use: nothing is allocated for a call after that.
function ns.Perf_Add(stats, group, sub, what, ms, kb, login)
	local s = stats[group]
	if not s then
		s = NewStat()
		stats[group] = s
	end
	s.calls = s.calls + 1
	s.total = s.total + ms
	if kb > 0 then
		s.kb = s.kb + kb
	end
	if login then
		s.login = s.login + ms
	end
	if ms > s.peak then
		s.peak, s.peakSub, s.peakWhat = ms, sub, what
	end
	if ms >= ns.PERF_SLOW_MS then
		s.slow = s.slow + 1
	end
	if ms >= ns.PERF_HITCH_MS then
		s.hitches = s.hitches + 1
	end
	local bySub = s.by[sub]
	if not bySub then
		bySub = {}
		s.by[sub] = bySub
	end
	local w = bySub[what]
	if not w then
		w = { calls = 0, total = 0, peak = 0, kb = 0 }
		bySub[what] = w
	end
	w.calls = w.calls + 1
	w.total = w.total + ms
	if kb > 0 then
		w.kb = w.kb + kb
	end
	if ms > w.peak then
		w.peak = ms
	end
	return s
end

-- Keeps the newest `limit` hitches, newest first.
function ns.Perf_PushHitch(list, hitch, limit)
	table.insert(list, 1, hitch)
	for i = #list, limit + 1, -1 do
		list[i] = nil
	end
end
