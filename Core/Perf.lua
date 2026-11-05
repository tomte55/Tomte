local addonName, ns = ...

-- Performance measuring: how long Tomte's own code runs, per module folder, file or bus owner, and event or script.
-- The event buses (Events.lua) time every handler; ns.Perf_Wrap and ns.Perf_WrapEvents time a plain frame's
-- scripts and other callbacks; Modules.lua times each module's init and first start. Each finds the file it was
-- made in with debugstack, once, at creation. Recording runs only while the Performance module is on (ns.perfOn);
-- startup times always (a number per module, once). Pure rules in PerfData.lua; the page in Modules/Performance.
-- Loaded before Events.lua: Core.lua's bus is made at file load.

local clock = debugprofilestop -- ms since the client started, sub-millisecond; never call debugprofilestart
local gcount = collectgarbage
local Add = ns.Perf_Add
local SourceOf, GroupOf = ns.Perf_SourceOf, ns.Perf_GroupOf

local stats = {} -- [group] = ns.Perf_NewStat()
local hitches = {} -- newest first: { at = GetTime(), group, sub, what, ms }
local startup = {} -- [module key] = ms in init and the first start
local login = true -- from file load until ns.PERF_LOGIN_SECONDS after the first loading screen
local loadedAt = GetTime()
local onSince, onFromLoad -- when recording started, and whether that was before the first loading screen
local hitchHook

ns.perfOn = false
ns.Perf_Clock = clock

local function Record(group, sub, what, ms, kb)
	Add(stats, group, sub, what, ms, kb, login)
	if ms >= ns.PERF_HITCH_MS then
		ns.Perf_PushHitch(hitches, { at = GetTime(), group = group, sub = sub, what = what, ms = ms },
			ns.PERF_HITCHES_KEPT)
		if hitchHook then
			hitchHook(group, sub, what, ms)
		end
	end
end
ns.Perf_Record = Record

-- The group and file of the code `depth` levels up: 1 = the function that calls this, 2 = its caller.
function ns.Perf_Caller(depth)
	return GroupOf(SourceOf(debugstack(depth + 1, 1, 0)))
end

local function Finish(group, sub, what, t0, m0, ...)
	Record(group, sub, what, clock() - t0, gcount("count") - m0)
	return ...
end

-- fn, timed while recording, under the caller's module folder and file; what names it ("OnUpdate", "tooltip").
-- Make it once (at file load, or when a script is set), not per call: finding the caller reads the stack.
function ns.Perf_Wrap(fn, what)
	local group, file = ns.Perf_Caller(2)
	return function(...)
		if not ns.perfOn then
			return fn(...)
		end
		local t0, m0 = clock(), gcount("count")
		return Finish(group, file, what, t0, m0, fn(...))
	end
end

-- An OnEvent script, timed per event.
function ns.Perf_WrapEvents(fn)
	local group, file = ns.Perf_Caller(2)
	return function(self, event, ...)
		if not ns.perfOn then
			return fn(self, event, ...)
		end
		local t0, m0 = clock(), gcount("count")
		return Finish(group, file, event or "?", t0, m0, fn(self, event, ...))
	end
end

function ns.Perf_Startup(key, ms)
	startup[key] = (startup[key] or 0) + ms
end

function ns.Perf_SetOn(state)
	if state == ns.perfOn then
		return
	end
	ns.perfOn = state
	if state then
		onSince = GetTime()
		onFromLoad = login and onSince - loadedAt < 60
	end
end

-- Starts the totals over from now (startup times stay: they only happen once).
function ns.Perf_Reset()
	wipe(stats)
	wipe(hitches)
	onSince = GetTime()
	onFromLoad = false
end

function ns.Perf_SetHitchHook(fn)
	hitchHook = fn
end

function ns.Perf_Stats()
	return stats
end

function ns.Perf_Hitches()
	return hitches
end

function ns.Perf_StartupTimes()
	return startup
end

-- When recording started (GetTime), whether it ran since the UI loaded (so Blizzard's session numbers cover the same
-- span), and when the UI loaded.
function ns.Perf_Since()
	return onSince, onFromLoad == true, loadedAt
end

function ns.Perf_InLogin()
	return login
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(ns.PERF_LOGIN_SECONDS, function()
		login = false
	end)
end)
