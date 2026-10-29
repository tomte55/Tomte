-- Run from the AddOns folder: lua Tomte/tests/test_journal.lua
-- Core/Journal.lua with stubbed frames and journals: a callback that errors is reported once and stops the scan.
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local frames = {}
_G.CreateFrame = function()
	local f = { scripts = {}, shown = true }
	function f:SetScript(name, fn)
		self.scripts[name] = fn
	end
	function f:Show()
		self.shown = true
	end
	function f:Hide()
		self.shown = false
	end
	frames[#frames + 1] = f
	return f
end
local clock = 0
_G.debugprofilestop = function()
	clock = clock + 0.01 -- 400 reads per 4 ms frame budget
	return clock
end
_G.C_MountJournal = {
	GetMountIDs = function()
		return { 1, 2, 3 }
	end,
	GetMountInfoByID = function(id)
		return "Mount " .. id, 100 + id, 0, nil, nil, nil, nil, nil, nil, false, false
	end,
	GetMountInfoExtraByID = function()
		return nil, nil, "A vendor"
	end,
}
_G.C_PetJournal = {
	GetPetInfoBySpeciesID = function(id)
		if id == 5 then
			return "Pet 5", 1, nil, nil, "A drop", nil, nil, nil, nil, nil, true, 99
		end
	end,
	GetNumCollectedInfo = function()
		return 0
	end,
}
local reported = {}
local ns = {
	errorHandler = function(err)
		reported[#reported + 1] = tostring(err)
	end,
	Perf_Wrap = function(fn)
		return fn
	end,
}
assert(loadfile("Tomte/Core/Journal.lua"))("Tomte", ns)

local function Clear()
	for i = #reported, 1, -1 do
		reported[i] = nil
	end
end

-- Runs the owner's frame like game frames until it hides (at most 50).
local function Run(f)
	for _ = 1, 50 do
		if not f.shown then
			return
		end
		f.scripts.OnUpdate(f, 0.016)
	end
end

test("a clean scan reads every missing mount and pet and finishes", function()
	Clear()
	local mounts, pets, done = 0, 0, false
	ns.Journal_Scan("ok", {
		mount = function()
			mounts = mounts + 1
		end,
		pet = function(id)
			pets = pets + 1
			eq(id, 5)
		end,
		done = function()
			done = true
		end,
	})
	Run(frames[#frames])
	eq(mounts, 3)
	eq(pets, 1)
	eq(done, true)
	eq(#reported, 0)
end)

test("a mount callback that errors is reported once and stops the scan", function()
	Clear()
	local calls = 0
	ns.Journal_Scan("bad", {
		mount = function()
			calls = calls + 1
			error("boom")
		end,
	})
	local f = frames[#frames]
	f.scripts.OnUpdate(f, 0.016)
	eq(calls, 1, "not retried")
	eq(#reported, 1)
	eq(f.shown, false, "the frame stops")
	eq(ns.Journal_Progress("bad"), nil, "no scan left")
end)

test("a pet callback or mountsDone that errors stops the scan too", function()
	Clear()
	ns.Journal_Scan("pets", {
		pet = function()
			error("pet boom")
		end,
	})
	Run(frames[#frames])
	eq(#reported, 1)
	eq(ns.Journal_Progress("pets"), nil)
	Clear()
	ns.Journal_Scan("phase", {
		mountsDone = function()
			error("done boom")
		end,
	})
	Run(frames[#frames])
	eq(#reported, 1)
	eq(ns.Journal_Progress("phase"), nil)
end)

H.done()
