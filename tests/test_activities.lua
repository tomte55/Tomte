-- Run from the AddOns folder: lua Tomte/tests/test_activities.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/WarWithin/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Weekly/ActivityData.lua"))("Tomte", ns)

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

local function Curated()
	return {
		{ group = "Delves", entries = {
			{ label = "The Key to Success", state = "done" },
			{ label = "Restored Coffer Keys", state = "open", n = 1, of = 4 },
		} },
		{ group = "Dornogal", entries = {
			{ label = "Worldsoul weekly", state = "progress", title = "Worldsoul: Spreading the Light" },
		} },
	}
end

local LEARNED = {
	[100] = { title = "Theater Troupe", group = "Isle of Dorn" },
	[101] = { title = "Spreading the Light", group = "Hallowfall" },
	[102] = { title = "Old one" }, -- learned before groups were kept
}
local VIEW = { quests = { [100] = "log", [101] = "done", [102] = "log" } }

local function Find(groups, title)
	for _, g in ipairs(groups) do
		if g.title == title then
			return g
		end
	end
end

test("curated groups first, then learned quests by their log header", function()
	local m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, false)
	eq(m.groups[1].title, "Delves")
	eq(m.groups[2].title, "Dornogal")
	eq(m.groups[3].title, "Hallowfall", "learned groups by name")
	eq(Find(m.groups, "Isle of Dorn").items[1].left, "Theater Troupe")
	eq(m.groups[#m.groups].title, "Other weekly quests", "no group comes last")
	eq(m.groups[#m.groups].items[1].left, "Old one")
	eq(m.hidden, 0)
end)

test("item texts and states", function()
	local m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, false)
	local delves = m.groups[1].items
	eq(delves[1].right, "done")
	eq(delves[1].state, "done")
	eq(delves[2].left, "Restored Coffer Keys")
	eq(delves[2].right, "1/4")
	eq(delves[2].state, "open")
	eq(m.groups[2].items[1].right, "in progress")
	eq(m.groups[2].items[1].left, "Worldsoul weekly: Worldsoul: Spreading the Light")
	local all = ns.Weekly_ActivityModel({ { group = "D", entries = { { label = "Keys", n = 4, of = 4 } } } }, {},
		{ quests = {} }, false)
	eq(all.groups[1].items[1].state, "done", "4/4 is done")
end)

test("hide completed drops done items and empty groups, and counts them", function()
	local m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, true)
	eq(#m.groups[1].items, 1, "Delves keeps the keys")
	eq(Find(m.groups, "Hallowfall"), nil, "only done quest")
	eq(m.hidden, 2)
end)

test("everything done and hidden leaves one note", function()
	local curated = { { group = "Delves", entries = { { label = "Key", state = "done" } } } }
	local m = ns.Weekly_ActivityModel(curated, {}, { quests = {} }, true)
	eq(#m.groups, 1)
	eq(m.groups[1].title, "")
	eq(m.groups[1].items[1].left, "Everything here is done this week.")
	eq(m.hidden, 1)
end)

test("no data at all", function()
	local m = ns.Weekly_ActivityModel({}, {}, {}, false)
	eq(m.groups[1].items[1].left, "Nothing tracked yet. Weekly quests are learned when they're in your quest log.")
end)

test("no hand-kept list for the expansion: a grey line on top", function()
	local m = ns.Weekly_ActivityModel(nil, {}, { quests = {} }, false, "No activities data for Midnight yet.")
	eq(m.groups[1].items[1].left, "No activities data for Midnight yet.")
	eq(m.groups[1].items[1].state, "dim")
	eq(m.groups[2].items[1].left, "Nothing tracked yet. Weekly quests are learned when they're in your quest log.")
	m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, false)
	eq(m.groups[1].title ~= "", true, "with a list: no extra line")
end)

test("Midnight tables exist", function()
	eq(#ns.Content_Get(11, "activities") > 0, true)
	eq(#ns.Content_Get(11, "resources") > 0, true)
	eq(#ns.Content_Get(11, "subfactions")[2710], 4)
	eq(#ns.Content_Get(11, "crests"), 2)
end)

test("curated and resource tables exist for The War Within", function()
	eq(#ns.Content_Get(10, "activities") > 0, true)
	eq(#ns.Content_Get(10, "resources") > 0, true)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
