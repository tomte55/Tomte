local addonName, ns = ...

-- Performance: pure logic (no WoW API calls; unit-tested in tests/test_performance.lua). Blizzard's percentages,
-- number text, the verdict, the module table's rows and live rates, the share of Tomte's time Tomte measured, the
-- hitch warning's throttle, the readout line and the copy-paste report. Measuring is in Core/Perf.lua.

ns.PERF_LIGHT = 0.01 -- Tomte under 1% of the frame time: nothing to look at
ns.PERF_HEAVY = 0.05 -- over 5%: something to fix
local RATE_KEEP = 0.6 -- how much of the last rate a new sample keeps (smooths the 1 s samples)
local PARTS_SHOWN = 8

-- An addon's share of the frame as Blizzard's addon list works it out (AddonList:GetAddonMetricPercent): its time
-- against the game's own time plus its own, leaving the other addons out. 0..1, nil without numbers.
function ns.Perf_Percent(app, overall, addon)
	if type(app) ~= "number" or type(overall) ~= "number" or type(addon) ~= "number" then
		return nil
	end
	local total = app - overall + addon
	if total <= 0 then
		return nil
	end
	return addon / total
end

-- Blizzard's FormatProfilerPercent: "14%", "0.1%", "0.04%", "0%". nil -> "–".
function ns.Perf_PercentText(fraction)
	if not fraction then
		return "–"
	end
	local pct = fraction * 100
	if pct >= 1 then
		return ("%.0f%%"):format(pct)
	elseif pct >= 0.1 then
		return ("%.1f%%"):format(pct)
	elseif pct >= 0.01 then
		return ("%.2f%%"):format(pct)
	end
	return "0%"
end

function ns.Perf_MsText(ms)
	if not ms then
		return "–"
	elseif ms >= 1000 then
		return ("%.1f s"):format(ms / 1000)
	elseif ms >= 10 then
		return ("%d ms"):format(math.floor(ms + 0.5))
	elseif ms >= 1 then
		return ("%.1f ms"):format(ms)
	elseif ms >= 0.01 then
		return ("%.2f ms"):format(ms)
	end
	return "0 ms"
end

-- Busy time per second of play: "0.42 ms/s".
function ns.Perf_RateText(msPerSecond)
	if not msPerSecond then
		return "–"
	elseif msPerSecond >= 10 then
		return ("%d ms/s"):format(math.floor(msPerSecond + 0.5))
	elseif msPerSecond >= 0.01 then
		return ("%.2f ms/s"):format(msPerSecond)
	end
	return "0 ms/s"
end

function ns.Perf_KBText(kb)
	if not kb then
		return "–"
	elseif kb >= 1024 * 1024 then
		return ("%.2f GB"):format(kb / 1024 / 1024)
	elseif kb >= 1024 then
		return ("%.1f MB"):format(kb / 1024)
	end
	return ("%d KB"):format(math.floor(kb + 0.5))
end

-- How Tomte is doing at this share of the frame: a color role and a word.
function ns.Perf_Verdict(fraction)
	if not fraction then
		return "textMuted", "not measured yet"
	elseif fraction < ns.PERF_LIGHT then
		return "success", "light"
	elseif fraction < ns.PERF_HEAVY then
		return "warning", "noticeable"
	end
	return "danger", "heavy"
end

-- A module folder as a player reads it: "WorldQuests" -> "World Quests", "AFK" stays.
function ns.Perf_GroupName(group)
	return (group:gsub("(%l)(%u)", "%1 %2"))
end

-- Live rates (ms per second) per group from two samples dt seconds apart. prev: [group] = total at the last sample,
-- updated in place; rates: [group] = smoothed ms/s, updated in place. A group seen for the first time starts at its
-- rate since nothing (it was 0 at the last sample).
function ns.Perf_UpdateRates(stats, prev, rates, dt)
	if dt <= 0 then
		return rates
	end
	for group, s in pairs(stats) do
		local now = (s.total - (prev[group] or 0)) / dt
		if now < 0 then
			now = 0 -- the totals were reset
		end
		local old = rates[group]
		rates[group] = old and (old * RATE_KEEP + now * (1 - RATE_KEEP)) or now
		prev[group] = s.total
	end
	for group in pairs(rates) do
		if not stats[group] then
			rates[group], prev[group] = nil, nil
		end
	end
	return rates
end

local SORTS = {
	now = function(r)
		return r.now or 0
	end,
	total = function(r)
		return r.total
	end,
	peak = function(r)
		return r.peak
	end,
}
ns.PERF_SORTS = { { value = "now", text = "Now" }, { value = "total", text = "Session" },
	{ value = "peak", text = "Peak" } }

-- The module table: a row per group, highest first by sortKey ("now", "total" or "peak"), with share = the row's
-- sort value against the highest (0..1, for its bar).
function ns.Perf_ModuleRows(stats, rates, sortKey)
	local value = SORTS[sortKey] or SORTS.total
	local rows = {}
	for group, s in pairs(stats) do
		rows[#rows + 1] = {
			group = group,
			name = ns.Perf_GroupName(group),
			now = rates and rates[group],
			total = s.total,
			calls = s.calls,
			peak = s.peak,
			peakSub = s.peakSub,
			peakWhat = s.peakWhat,
			slow = s.slow,
			hitches = s.hitches,
			kb = s.kb,
			login = s.login,
		}
	end
	table.sort(rows, function(a, b)
		local x, y = value(a), value(b)
		if x ~= y then
			return x > y
		end
		return a.name < b.name
	end)
	local top = rows[1] and value(rows[1]) or 0
	for _, row in ipairs(rows) do
		row.share = top > 0 and value(row) / top or 0
	end
	return rows
end

-- Where a group's time goes: its biggest sub/what pairs by total, at most n (PARTS_SHOWN by default).
function ns.Perf_TopParts(stat, n)
	local parts = {}
	for sub, whats in pairs(stat.by) do
		for what, w in pairs(whats) do
			parts[#parts + 1] = { sub = sub, what = what, calls = w.calls, total = w.total, peak = w.peak, kb = w.kb }
		end
	end
	table.sort(parts, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.sub .. a.what < b.sub .. b.what
	end)
	for i = #parts, (n or PARTS_SHOWN) + 1, -1 do
		parts[i] = nil
	end
	return parts
end

-- "Read · BAG_UPDATE"; just the event when the file has the group's name (Rogue.lua in Rogue).
function ns.Perf_PartText(group, sub, what)
	if not sub or sub == group then
		return tostring(what)
	end
	return ("%s · %s"):format(tostring(sub), tostring(what))
end

-- The share of Tomte's time that Tomte measured itself (0..1, nil when it can't be told). Blizzard gives per-frame
-- averages, so its total over the session is its average times the frames seen: the time since load over the game's
-- average frame. Only meaningful when recording ran since the UI loaded.
function ns.Perf_Coverage(measuredMs, addonAvg, appAvg, elapsedMs)
	if not (measuredMs and addonAvg and appAvg and elapsedMs) or appAvg <= 0 or addonAvg <= 0 or elapsedMs <= 0 then
		return nil
	end
	local total = addonAvg * elapsedMs / appAvg
	return math.min(measuredMs / total, 1)
end

function ns.Perf_MeasuredTotal(stats)
	local total = 0
	for _, s in pairs(stats) do
		total = total + s.total
	end
	return total
end

-- Startup rows: { key, ms } per module, slowest first, from [module key] = ms.
function ns.Perf_StartupRows(startup)
	local rows, total = {}, 0
	for key, ms in pairs(startup) do
		rows[#rows + 1] = { key = key, ms = ms }
		total = total + ms
	end
	table.sort(rows, function(a, b)
		if a.ms ~= b.ms then
			return a.ms > b.ms
		end
		return a.key < b.key
	end)
	return rows, total
end

-- The login rows: { group, name, ms } per group that ran during the login window, slowest first.
function ns.Perf_LoginRows(stats)
	local rows, total = {}, 0
	for group, s in pairs(stats) do
		if s.login > 0 then
			rows[#rows + 1] = { group = group, name = ns.Perf_GroupName(group), ms = s.login }
			total = total + s.login
		end
	end
	table.sort(rows, function(a, b)
		if a.ms ~= b.ms then
			return a.ms > b.ms
		end
		return a.name < b.name
	end)
	return rows, total
end

-- The other addons, busiest now first: rows { name, recent, session, peak, mem } with recent and session as
-- Blizzard's fractions. game = { app = { recent, session }, overall = { ... } }.
function ns.Perf_AddonRows(game, addons)
	local rows = {}
	for _, a in ipairs(addons) do
		rows[#rows + 1] = {
			name = a.name,
			recent = ns.Perf_Percent(game.app.recent, game.overall.recent, a.recent),
			session = ns.Perf_Percent(game.app.session, game.overall.session, a.session),
			peak = a.peak,
			mem = a.mem,
		}
	end
	table.sort(rows, function(a, b)
		local x, y = a.recent or 0, b.recent or 0
		if x ~= y then
			return x > y
		end
		local p, q = a.session or 0, b.session or 0
		if p ~= q then
			return p > q
		end
		return a.name < b.name
	end)
	return rows
end

-- Hitch warning throttle: true (and noted in last) when key wasn't warned about in the last `gap` seconds.
function ns.Perf_ShouldWarn(last, key, now, gap)
	local at = last[key]
	if at and now - at < gap then
		return false
	end
	last[key] = now
	return true
end

function ns.Perf_WarnText(group, sub, what, ms)
	return ("%s took %s (%s). /tomte perf for more."):format(ns.Perf_GroupName(group), ns.Perf_MsText(ms),
		ns.Perf_PartText(group, sub, what))
end

-- The readout: "58 fps  18 ms  Tomte 0.1%".
function ns.Perf_ReadoutText(fps, latency, fraction)
	return ("%d fps   %d ms   Tomte %s"):format(math.floor((fps or 0) + 0.5), latency or 0,
		ns.Perf_PercentText(fraction))
end

-- The copy-paste report. r = { version, elapsed (s), fps, home, world, tomte = { recent, session, peak, mem,
-- over = { [5] = n, ... } } (fractions for recent and session), coverage, rows (Perf_ModuleRows), parts =
-- [group] = Perf_TopParts, hitches, startup (Perf_StartupRows), startupTotal, login, loginTotal, addons
-- (Perf_AddonRows), names = [module key] = name, now (GetTime) }.
function ns.Perf_Report(r)
	local out = {}
	local function Add(fmt, ...)
		out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
	end
	local t = r.tomte
	Add("Tomte %s performance report, %s into the session", r.version or "?", ns.Perf_DurationText(r.elapsed))
	Add("%d fps, latency %d ms home / %d ms world", math.floor((r.fps or 0) + 0.5), r.home or 0, r.world or 0)
	Add("Tomte (game's profiler): now %s, session %s, peak %s, memory %s", ns.Perf_PercentText(t.recent),
		ns.Perf_PercentText(t.session), ns.Perf_MsText(t.peak), ns.Perf_KBText(t.mem))
	if t.over then
		Add("Frames Tomte took over 5 / 10 / 50 / 100 ms: %d / %d / %d / %d", t.over[5] or 0, t.over[10] or 0,
			t.over[50] or 0, t.over[100] or 0)
	end
	Add("Measured by Tomte: %s", r.coverage and ("about " .. ns.Perf_PercentText(r.coverage) .. " of its time")
		or "since a reset or a mid-session start")
	Add("")
	Add("Modules (now, session, calls, peak, slow 5 ms+, memory made)")
	for _, row in ipairs(r.rows) do
		Add("  %s: %s, %s, %d, %s%s, %d, %s", row.name, ns.Perf_RateText(row.now), ns.Perf_MsText(row.total),
			row.calls, ns.Perf_MsText(row.peak),
			row.peakWhat and (" (" .. ns.Perf_PartText(row.group, row.peakSub, row.peakWhat) .. ")") or "",
			row.slow, ns.Perf_KBText(row.kb))
		for _, p in ipairs(r.parts[row.group] or {}) do
			Add("      %s: %s in %d calls, peak %s", ns.Perf_PartText(row.group, p.sub, p.what), ns.Perf_MsText(p.total),
				p.calls, ns.Perf_MsText(p.peak))
		end
	end
	Add("")
	Add("Hitches (%d ms+), newest first", ns.PERF_HITCH_MS)
	if #r.hitches == 0 then
		Add("  none")
	end
	for _, h in ipairs(r.hitches) do
		Add("  %s ago: %s, %s", ns.Perf_DurationText(r.now - h.at), ns.Perf_GroupName(h.group) .. " · "
			.. ns.Perf_PartText(h.group, h.sub, h.what), ns.Perf_MsText(h.ms))
	end
	Add("")
	Add("Startup (init and first start): %s", ns.Perf_MsText(r.startupTotal))
	for _, row in ipairs(r.startup) do
		Add("  %s: %s", r.names[row.key] or row.key, ns.Perf_MsText(row.ms))
	end
	Add("Login (first %d s in the world): %s", r.loginSeconds or 0, ns.Perf_MsText(r.loginTotal))
	for _, row in ipairs(r.login) do
		Add("  %s: %s", row.name, ns.Perf_MsText(row.ms))
	end
	Add("")
	Add("Addons (now, session, peak, memory)")
	for _, a in ipairs(r.addons) do
		Add("  %s: %s, %s, %s, %s", a.name, ns.Perf_PercentText(a.recent), ns.Perf_PercentText(a.session),
			ns.Perf_MsText(a.peak), ns.Perf_KBText(a.mem))
	end
	return table.concat(out, "\n")
end

-- "45 s", "12 min", "1 h 20 min".
function ns.Perf_DurationText(seconds)
	seconds = math.max(math.floor(seconds or 0), 0)
	if seconds < 60 then
		return seconds .. " s"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. " min"
	end
	return ("%d h %d min"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end
