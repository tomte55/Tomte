-- Run from the AddOns folder: lua Tomte/tests/test_perfdata.lua
local ns = {}
assert(loadfile("Tomte/Core/PerfData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

test("source of a stack line, full or shortened", function()
	eq(ns.Perf_SourceOf('[string "@Interface/AddOns/Tomte/Modules/Bags/Read.lua"]:12: in main chunk'),
		"Modules/Bags/Read")
	eq(ns.Perf_SourceOf("Interface\\AddOns\\Tomte\\Core\\Core.lua:131: in main chunk"), "Core/Core")
	eq(ns.Perf_SourceOf("...odules/Gather/Detect.lua:27: in main chunk"), "Modules/Gather/Detect")
	eq(ns.Perf_SourceOf("Interface/AddOns/Tomte/Panel/Window.lua:5: in function <...>"), "Panel/Window")
	eq(ns.Perf_SourceOf("[C]: in function `xpcall'"), nil)
	eq(ns.Perf_SourceOf(nil), nil)
end)

test("group and file of a source", function()
	local g, f = ns.Perf_GroupOf("Modules/Bags/Read")
	eq(g, "Bags")
	eq(f, "Read")
	g, f = ns.Perf_GroupOf("Panel/Window")
	eq(g, "Window")
	eq(f, "Window")
	g = ns.Perf_GroupOf("Cinematic/Engine")
	eq(g, "Cinematics")
	g, f = ns.Perf_GroupOf(nil)
	eq(g, "Other")
	eq(f, "?")
end)

test("a call adds to its group, sub and what", function()
	local stats = {}
	ns.Perf_Add(stats, "Bags", "Read", "BAG_UPDATE", 2, 10, true)
	ns.Perf_Add(stats, "Bags", "Read", "BAG_UPDATE", 7, -3, false)
	local s = ns.Perf_Add(stats, "Bags", "View", "OnUpdate", 20, 1, false)
	eq(s.calls, 3)
	near(s.total, 29)
	near(s.kb, 11, "a GC step (negative) counts as nothing")
	near(s.login, 2)
	near(s.peak, 20)
	eq(s.peakSub, "View")
	eq(s.peakWhat, "OnUpdate")
	eq(s.slow, 2, "5 ms and up")
	eq(s.hitches, 1, "16 ms and up")
	local w = s.by.Read.BAG_UPDATE
	eq(w.calls, 2)
	near(w.total, 9)
	near(w.peak, 7)
end)

test("hitches keep the newest first, up to the limit", function()
	local list = {}
	for i = 1, 5 do
		ns.Perf_PushHitch(list, { ms = i }, 3)
	end
	eq(#list, 3)
	eq(list[1].ms, 5)
	eq(list[3].ms, 3)
end)

H.done()
