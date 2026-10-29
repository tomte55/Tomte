-- Run from the AddOns folder: lua Tomte/tests/test_performance.lua
local ns = {}
assert(loadfile("Tomte/Core/PerfData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Performance/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

test("Blizzard's share: the addon against the game plus itself", function()
	-- The game 10 ms a frame, all addons 2 ms of it, this one 1 ms: 1 / (10 - 2 + 1).
	near(ns.Perf_Percent(10, 2, 1), 1 / 9)
	eq(ns.Perf_Percent(nil, 2, 1), nil)
	eq(ns.Perf_Percent(0, 0, 0), nil)
end)

test("percent text as Blizzard writes it", function()
	eq(ns.Perf_PercentText(0.14), "14%")
	eq(ns.Perf_PercentText(0.001), "0.1%")
	eq(ns.Perf_PercentText(0.0004), "0.04%")
	eq(ns.Perf_PercentText(0.00001), "0%")
	eq(ns.Perf_PercentText(nil), "–")
end)

test("ms, rate and memory text", function()
	eq(ns.Perf_MsText(1234), "1.2 s")
	eq(ns.Perf_MsText(34.4), "34 ms")
	eq(ns.Perf_MsText(4.25), "4.2 ms")
	eq(ns.Perf_MsText(0.123), "0.12 ms")
	eq(ns.Perf_MsText(0.001), "0 ms")
	eq(ns.Perf_RateText(0.42), "0.42 ms/s")
	eq(ns.Perf_RateText(nil), "–")
	eq(ns.Perf_KBText(512), "512 KB")
	eq(ns.Perf_KBText(54886), "53.6 MB")
end)

test("verdict at 1% and 5%", function()
	eq((ns.Perf_Verdict(0.001)), "success")
	eq((ns.Perf_Verdict(0.02)), "warning")
	eq((ns.Perf_Verdict(0.14)), "danger")
	eq((ns.Perf_Verdict(nil)), "textMuted")
end)

test("group names get spaces", function()
	eq(ns.Perf_GroupName("WorldQuests"), "World Quests")
	eq(ns.Perf_GroupName("AFK"), "AFK")
	eq(ns.Perf_GroupName("Bags"), "Bags")
end)

test("rates: ms per second, smoothed, gone groups dropped", function()
	local stats, prev, rates = { Bags = { total = 10 } }, {}, {}
	ns.Perf_UpdateRates(stats, prev, rates, 1)
	near(rates.Bags, 10, "first sample: from nothing")
	stats.Bags.total = 12
	ns.Perf_UpdateRates(stats, prev, rates, 1)
	near(rates.Bags, 10 * 0.6 + 2 * 0.4)
	stats.Bags.total = 0 -- reset
	ns.Perf_UpdateRates(stats, prev, rates, 1)
	near(rates.Bags, (10 * 0.6 + 2 * 0.4) * 0.6)
	ns.Perf_UpdateRates({}, prev, rates, 1)
	eq(rates.Bags, nil)
	eq(prev.Bags, nil)
end)

local function Stats()
	local stats = {}
	ns.Perf_Add(stats, "Bags", "Read", "BAG_UPDATE", 30, 100, true)
	ns.Perf_Add(stats, "Bags", "View", "OnUpdate", 1, 0, false)
	ns.Perf_Add(stats, "Gather", "detect", "UNIT_SPELLCAST_SENT", 2, 0, false)
	ns.Perf_Add(stats, "Gather", "detect", "LOOT_OPENED", 8, 0, false)
	ns.Perf_Add(stats, "Gather", "detect", "LOOT_OPENED", 8, 0, false)
	return stats
end

test("module rows sort by the chosen value, with shares", function()
	local rows = ns.Perf_ModuleRows(Stats(), { Bags = 0.1, Gather = 0.5 }, "total")
	eq(rows[1].group, "Bags")
	near(rows[1].share, 1)
	near(rows[2].share, 18 / 31)
	rows = ns.Perf_ModuleRows(Stats(), { Bags = 0.1, Gather = 0.5 }, "now")
	eq(rows[1].group, "Gather")
	eq(rows[1].peakWhat, "LOOT_OPENED")
	rows = ns.Perf_ModuleRows(Stats(), nil, "nonsense")
	eq(rows[1].group, "Bags", "unknown sort falls back to session")
end)

test("top parts by total, cut to n", function()
	local stats = Stats()
	local parts = ns.Perf_TopParts(stats.Gather)
	eq(#parts, 2)
	eq(parts[1].what, "LOOT_OPENED")
	eq(parts[1].calls, 2)
	near(parts[1].total, 16)
	eq(#ns.Perf_TopParts(stats.Gather, 1), 1)
end)

test("part text leaves out a file named like its group", function()
	eq(ns.Perf_PartText("Bags", "Read", "BAG_UPDATE"), "Read · BAG_UPDATE")
	eq(ns.Perf_PartText("Rogue", "Rogue", "UNIT_AURA"), "UNIT_AURA")
	-- A table sub (an event owner that isn't a name) must not break the report.
	eq(type(ns.Perf_PartText("Bags", {}, "BAG_UPDATE")), "string")
end)

test("coverage: measured against Blizzard's average times the frames seen", function()
	-- 60 s at a 16 ms frame = 3750 frames; Tomte 0.2 ms a frame = 750 ms; 600 measured = 80%.
	near(ns.Perf_Coverage(600, 0.2, 16, 60000), 0.8)
	near(ns.Perf_Coverage(2000, 0.2, 16, 60000), 1, "never above all")
	eq(ns.Perf_Coverage(600, 0, 16, 60000), nil)
	eq(ns.Perf_Coverage(600, nil, 16, 60000), nil)
	near(ns.Perf_MeasuredTotal(Stats()), 49)
end)

test("startup and login rows, slowest first, with totals", function()
	local rows, total = ns.Perf_StartupRows({ bags = 12, gather = 30, rogue = 1 })
	eq(rows[1].key, "gather")
	near(total, 43)
	local login, loginTotal = ns.Perf_LoginRows(Stats())
	eq(#login, 1, "only groups that ran while logging in")
	eq(login[1].group, "Bags")
	near(loginTotal, 30)
end)

test("addon rows: busiest now first, as Blizzard's fractions", function()
	local game = { app = { recent = 10, session = 10 }, overall = { recent = 2, session = 2 } }
	local rows = ns.Perf_AddonRows(game, {
		{ name = "Tomte", recent = 0.5, session = 1, peak = 40, mem = 50000 },
		{ name = "RareScanner", recent = 1, session = 0.5, peak = 10, mem = 54000 },
	})
	eq(rows[1].name, "RareScanner")
	near(rows[1].recent, 1 / 9)
	near(rows[2].session, 1 / 9)
end)

test("hitch warnings at most once a gap per key", function()
	local last = {}
	eq(ns.Perf_ShouldWarn(last, "a", 100, 60), true)
	eq(ns.Perf_ShouldWarn(last, "a", 130, 60), false)
	eq(ns.Perf_ShouldWarn(last, "b", 130, 60), true)
	eq(ns.Perf_ShouldWarn(last, "a", 161, 60), true)
end)

test("readout and warning text", function()
	eq(ns.Perf_ReadoutText(57.6, 18, 0.001), "58 fps   18 ms   Tomte 0.1%")
	eq(ns.Perf_WarnText("Bags", "Read", "BAG_UPDATE", 34), "Bags took 34 ms (Read · BAG_UPDATE). /tomte perf for more.")
	eq(ns.Perf_DurationText(42), "42 s")
	eq(ns.Perf_DurationText(720), "12 min")
	eq(ns.Perf_DurationText(4800), "1 h 20 min")
end)

test("the report names modules, parts, hitches, startup and addons", function()
	local stats = Stats()
	local rows = ns.Perf_ModuleRows(stats, nil, "total")
	local parts = {}
	for _, row in ipairs(rows) do
		parts[row.group] = ns.Perf_TopParts(stats[row.group], 5)
	end
	local startup, startupTotal = ns.Perf_StartupRows({ bags = 12 })
	local login, loginTotal = ns.Perf_LoginRows(stats)
	local text = ns.Perf_Report({
		version = "1.26.0", elapsed = 600, now = 1000, fps = 60, home = 18, world = 20,
		tomte = { recent = 0.001, session = 0.002, peak = 45, mem = 54886, over = { [5] = 3, [10] = 2, [50] = 1 } },
		coverage = 0.9, rows = rows, parts = parts,
		hitches = { { at = 940, group = "Bags", sub = "Read", what = "BAG_UPDATE", ms = 30 } },
		startup = startup, startupTotal = startupTotal, login = login, loginTotal = loginTotal, loginSeconds = 20,
		addons = { { name = "Tomte", recent = 0.001, session = 0.002, peak = 45, mem = 54886 } },
		names = { bags = "Bags" },
	})
	assert(text:find("Tomte 1.26.0 performance report, 10 min into the session", 1, true), text)
	assert(text:find("Frames Tomte took over 5 / 10 / 50 / 100 ms: 3 / 2 / 1 / 0", 1, true), text)
	assert(text:find("about 90% of its time", 1, true), text)
	assert(text:find("  Bags: –, 31 ms, 2, 30 ms (Read · BAG_UPDATE), 1, 100 KB", 1, true), text)
	assert(text:find("      Read · BAG_UPDATE: 30 ms in 1 calls, peak 30 ms", 1, true), text)
	assert(text:find("  1 min ago: Bags · Read · BAG_UPDATE, 30 ms", 1, true), text)
	assert(text:find("Login (first 20 s in the world): 30 ms", 1, true), text)
	assert(text:find("  Tomte: 0.1%, 0.2%, 45 ms, 53.6 MB", 1, true), text)
end)

test("ReadoutLines: the numbers, the three busiest modules now and the last hitch", function()
	local rows = {
		{ name = "Window", now = 2.5 }, { name = "Cursor", now = 0.8 }, { name = "Recap", now = 0.05 },
		{ name = "Bags", now = 0.03 }, { name = "Mail", now = 0 },
	}
	local lines = ns.Perf_ReadoutLines({ fps = 59.6, home = 18, world = 20, now = 0.002, session = 0.05, peak = 39,
		all = 0.01, mem = 54886 }, rows, { at = 880, group = "Core", sub = "Journal", what = "OnUpdate", ms = 39 }, 1000)
	local function Find(left)
		for _, l in ipairs(lines) do
			if l.left == left then
				return l
			end
		end
	end
	eq(Find("Frame rate").right, "60 fps")
	eq(Find("Latency").right, "18 ms home, 20 ms world")
	eq(Find("Tomte now").role, "success")
	eq(Find("Window").right, "2.50 ms/s")
	eq(Find("Recap") ~= nil, true)
	eq(Find("Bags"), nil, "only three")
	eq(Find("Core · Journal · OnUpdate").right, "39 ms, 2 min ago")
	local quiet = ns.Perf_ReadoutLines({}, { { name = "Mail", now = 0 } }, nil, 0)
	eq(quiet[#quiet].left, "Nothing busy right now")
end)

H.done()
