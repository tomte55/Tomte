-- Run from the AddOns folder: lua Tomte/tests/test_achwalk.lua
-- The shared achievement walk with stubbed WoW globals; frames are driven by calling the stored OnUpdate.

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

local COUNTS = { [1] = 2, [2] = 3, [3] = 1 }
local frame

local function Load()
	frame = nil
	_G.CreateFrame = function()
		local f = { shown = true, scripts = {} }
		function f:SetScript(name, fn)
			self.scripts[name] = fn
		end
		function f:Show()
			self.shown = true
		end
		function f:Hide()
			self.shown = false
		end
		function f:IsShown()
			return self.shown
		end
		frame = f
		return f
	end
	local clock = 0
	_G.debugprofilestop = function()
		clock = clock + 1
		return clock
	end
	_G.GetCategoryList = function()
		return { 1, 2, 3 }
	end
	_G.GetCategoryNumAchievements = function(cat)
		return COUNTS[cat]
	end
	_G.GetAchievementInfo = function(cat, i)
		return cat * 100 + i
	end
	local ns = {}
	assert(loadfile("Tomte/Modules/Achievements/Walk.lua"))("Tomte", ns)
	return ns
end

local function Tick(n)
	for _ = 1, n or 1 do
		if frame.shown then
			frame.scripts.OnUpdate(frame, 0.016)
		end
	end
end

local function Recorder()
	local r = { seen = {}, n = 0, finished = 0, categories = 0 }
	r.handlers = {
		visit = function(id)
			r.seen[id] = (r.seen[id] or 0) + 1
			r.n = r.n + 1
		end,
		category = function()
			r.categories = r.categories + 1
		end,
		finish = function()
			r.finished = r.finished + 1
		end,
	}
	return r
end

local ALL = { 101, 102, 201, 202, 203, 301 }

local function ExactlyOnce(r, ids)
	for _, id in ipairs(ids) do
		eq(r.seen[id], 1, "visits of " .. id)
	end
	eq(r.n, #ids, "total visits")
end

test("two subscribers share one pass", function()
	local ns = Load()
	local a, b = Recorder(), Recorder()
	ns.AchWalk_Join("a", a.handlers)
	ns.AchWalk_Join("b", b.handlers)
	Tick(50)
	ExactlyOnce(a, ALL)
	ExactlyOnce(b, ALL)
	eq(a.finished, 1)
	eq(b.finished, 1)
	eq(a.categories, 3)
	eq(frame.shown, false, "walker stops")
	eq(ns.AchWalk_Progress("a"), nil, "finished subscriber has no progress")
end)

test("a late subscriber gets a full lap", function()
	local ns = Load()
	local a, b = Recorder(), Recorder()
	ns.AchWalk_Join("a", a.handlers)
	Tick(1) -- partway into the walk
	ns.AchWalk_Join("b", b.handlers)
	eq(ns.AchWalk_Progress("b"), 0)
	Tick(100)
	ExactlyOnce(a, ALL)
	ExactlyOnce(b, ALL)
	eq(a.finished, 1)
	eq(b.finished, 1)
	eq(frame.shown, false)
end)

test("skipped categories get no visits", function()
	local ns = Load()
	ns.AchWalk_SetSkipped(function(cat)
		return cat == 2
	end)
	local a = Recorder()
	ns.AchWalk_Join("a", a.handlers)
	Tick(50)
	ExactlyOnce(a, { 101, 102, 301 })
	eq(a.finished, 1)
end)

test("leave stops visits; rejoin restarts", function()
	local ns = Load()
	local a = Recorder()
	ns.AchWalk_Join("a", a.handlers)
	Tick(1)
	ns.AchWalk_Leave("a")
	local before = a.n
	Tick(50)
	eq(a.n, before, "no visits after leaving")
	eq(a.finished, 0)
	eq(frame.shown, false)
	local b = Recorder()
	ns.AchWalk_Join("a", b.handlers)
	Tick(50)
	ExactlyOnce(b, ALL)
end)

test("finish can join again", function()
	local ns = Load()
	local a = Recorder()
	local laps = 0
	a.handlers.finish = function()
		laps = laps + 1
		if laps == 1 then
			ns.AchWalk_Join("a", a.handlers)
		end
	end
	ns.AchWalk_Join("a", a.handlers)
	Tick(100)
	eq(laps, 2)
	eq(a.n, 2 * #ALL)
end)

test("progress grows per category", function()
	local ns = Load()
	local a = Recorder()
	ns.AchWalk_Join("a", a.handlers)
	eq(ns.AchWalk_Progress("a"), 0)
	local last = 0
	for _ = 1, 20 do
		Tick(1)
		local p = ns.AchWalk_Progress("a")
		if p then
			assert(p >= last, "progress went down")
			last = p
		end
	end
end)

test("no categories finishes at once", function()
	local ns = Load()
	_G.GetCategoryList = function()
		return {}
	end
	local a = Recorder()
	ns.AchWalk_Join("a", a.handlers)
	eq(a.finished, 1)
end)

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
