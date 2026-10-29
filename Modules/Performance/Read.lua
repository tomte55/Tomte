local addonName, ns = ...

-- Performance: the game's own numbers in plain tables. Frame rate, latency, Blizzard's addon profiler
-- (C_AddOnProfiler: always on, per-frame averages in ms) and addon memory. Rules in Data.lua.

local MEMORY_SECONDS = 5 -- UpdateAddOnMemoryUsage walks every addon's memory: not on every refresh

local M = Enum.AddOnProfilerMetric or {} -- only read when C_AddOnProfiler exists
local IsSecret = ns.IsSecret

local memory, memoryAt = {}, nil -- [addon name] = KB, at the last UpdateAddOnMemoryUsage

local function Number(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

local function Metrics(get, ...)
	return {
		recent = Number(get(..., M.RecentAverageTime)),
		session = Number(get(..., M.SessionAverageTime)),
		peak = Number(get(..., M.PeakTime)),
		encounter = Number(get(..., M.EncounterAverageTime)),
	}
end

-- GetApplicationMetric and GetOverallMetric take only the metric.
local function NoName(fn)
	return function(_, metric)
		return fn(metric)
	end
end

local function LoadedAddons()
	local list = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			list[#list + 1] = (C_AddOns.GetAddOnInfo(i))
		end
	end
	return list
end

local function ReadMemory(names, force)
	local now = GetTime()
	if not force and memoryAt and now - memoryAt < MEMORY_SECONDS then
		return
	end
	memoryAt = now
	UpdateAddOnMemoryUsage()
	wipe(memory)
	for _, name in ipairs(names) do
		memory[name] = Number(GetAddOnMemoryUsage(name))
	end
end

function ns.PerfRead_Profiler()
	return C_AddOnProfiler ~= nil and C_AddOnProfiler.IsEnabled() == true
end

-- { fps, home, world, profiler, app, overall, tomte = { recent, session, peak, encounter, mem, over = { [ms] = n } },
-- addons = { { name, recent, session, peak, mem } } (loaded addons, Tomte included) }. withAddons = false skips
-- the addon list (the readout only needs Tomte). forceMemory reads memory now.
function ns.PerfRead_Game(withAddons, forceMemory)
	local _, _, home, world = GetNetStats()
	local game = { fps = GetFramerate(), home = home, world = world, profiler = ns.PerfRead_Profiler() }
	if not game.profiler then
		game.app, game.overall, game.tomte, game.addons = {}, {}, {}, {}
		return game
	end
	local P = C_AddOnProfiler
	game.app = Metrics(NoName(P.GetApplicationMetric), nil)
	game.overall = Metrics(NoName(P.GetOverallMetric), nil)
	game.tomte = Metrics(P.GetAddOnMetric, addonName)
	game.tomte.over = {
		[5] = Number(P.GetAddOnMetric(addonName, M.CountTimeOver5Ms)),
		[10] = Number(P.GetAddOnMetric(addonName, M.CountTimeOver10Ms)),
		[50] = Number(P.GetAddOnMetric(addonName, M.CountTimeOver50Ms)),
		[100] = Number(P.GetAddOnMetric(addonName, M.CountTimeOver100Ms)),
	}
	game.addons = {}
	if withAddons == false then
		return game
	end
	local names = LoadedAddons()
	ReadMemory(names, forceMemory)
	for _, name in ipairs(names) do
		local a = Metrics(P.GetAddOnMetric, name)
		a.name, a.mem = name, memory[name]
		game.addons[#game.addons + 1] = a
	end
	game.tomte.mem = memory[addonName]
	return game
end

-- Tomte's memory in KB, read at most every MEMORY_SECONDS (the readout's tooltip; PerfRead_Game(false) skips it).
function ns.PerfRead_TomteMemory()
	ReadMemory(LoadedAddons())
	return memory[addonName]
end
