-- Run from the AddOns folder: lua Tomte/tests/test_prey.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Prey.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Prey/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local DEF = ns.Content_Get(11, "prey")

local function set(...)
	local t = {}
	for _, id in ipairs({ ... }) do
		t[id] = true
	end
	return function(id)
		return t[id] == true
	end
end

test("Midnight data: 30 targets per difficulty, ranks 0, 1, 4", function()
	eq(#DEF.difficulties, 3)
	for _, d in ipairs(DEF.difficulties) do
		eq(#d.quests, 30, d.name .. " quests")
	end
	eq(DEF.difficulties[2].rank, 1)
	eq(DEF.difficulties[3].rank, 4)
	eq(ns.Content_Get(10, "prey"), nil, "no prey in The War Within")
end)

test("index maps a quest to its difficulty and criteria", function()
	local index = ns.Prey_Index(DEF)
	eq(index[91095].difficulty, 1)
	eq(index[91095].criteria, 105912)
	eq(index[91124].criteria, 105941)
	eq(index[91242].difficulty, 2, "Hard after the odd/even run")
	eq(index[91242].criteria, 105958)
	eq(index[91211].difficulty, 3)
	eq(index[91211].criteria, 105972)
	eq(index[91269].criteria, 106001)
	eq(index[95021].achievement, 63452)
	eq(index[95021].extra, true)
	eq(index[12345], nil)
	eq(next(ns.Prey_Index(nil)), nil)
end)

test("difficulties open by journey rank", function()
	eq(#ns.Prey_Unlocked(DEF, nil), 1)
	eq(#ns.Prey_Unlocked(DEF, 1), 2)
	eq(#ns.Prey_Unlocked(DEF, 3), 2)
	eq(#ns.Prey_Unlocked(DEF, 4), 3)
end)

test("this week counts hunts and chests left per open difficulty", function()
	local rows = ns.Prey_Week(DEF, 4, set(91095, 91096, 91210, 95021, 91211))
	eq(#rows, 3)
	eq(rows[1].done, 2)
	eq(rows[1].chestsLeft, 0)
	eq(rows[2].done, 1)
	eq(rows[2].chestsLeft, 1)
	eq(rows[3].done, 2, "the 12.1 extra counts on Nightmare")
	eq(ns.Prey_WeekText(rows[2]), "1/4 this week · 1 chest left")
	eq(ns.Prey_WeekText(rows[1]), "2/4 this week · sacks only")
	eq(ns.Prey_WeekText({ done = 0, max = 4, chestsLeft = 2 }), "0/4 this week · 2 chests left")
	eq(ns.Prey_WeekText({ done = 4, max = 4, chestsLeft = 0 }), "4/4 this week")
	eq(#ns.Prey_Week(nil, 4, set()), 0)
end)

test("collection counts defeated targets per achievement", function()
	local rows = ns.Prey_Collection(DEF, function(achievement, criteria)
		return achievement == 42701 and criteria <= 105914
	end)
	eq(rows[1].done, 3)
	eq(rows[1].total, 30)
	eq(rows[2].done, 0)
end)

test("state names and the map point", function()
	eq(ns.Prey_StateName(0), "Cold trail")
	eq(ns.Prey_StateName(3), "Found")
	eq(ns.Prey_StateName(nil), nil)
	local x, y = ns.Prey_FindOnMap({ { questID = 1, x = 0.2, y = 0.3 }, { questID = 2, x = 0.5, y = 0.6 } }, 2)
	eq(x, 0.5)
	eq(y, 0.6)
	eq(ns.Prey_FindOnMap({ { questID = 2, x = 0, y = 0 } }, 2), nil, "no point at 0,0")
	eq(ns.Prey_FindOnMap(nil, 2), nil)
end)

test("hunt table tooltip lines", function()
	local index = ns.Prey_Index(DEF)
	local lines = ns.Prey_PinLines(DEF, index[91210], { name = "Hard", done = 1, max = 4, chestsLeft = 1 }, true)
	eq(lines[1].text, "Difficulty: Hard")
	eq(lines[2].text, "Hard: 1/4 this week · 1 chest left")
	eq(lines[3].text, "Not yet defeated for its achievement")
	local locked = ns.Prey_PinLines(DEF, index[91211], nil, false)
	eq(locked[2].text, "Nightmare hunts open at journey rank 4")
	eq(#locked, 2)
end)

test("home text", function()
	eq(ns.Prey_HomeText(nil), "No hunt. Pick a target at the Hunt Table.")
	eq(ns.Prey_HomeText({ title = "Prey: Lost Theldrin", state = 2 }), "Prey: Lost Theldrin: Hot trail")
	eq(ns.Prey_HomeText({ title = "Prey: X" }), "Prey: X")
end)

H.done()
