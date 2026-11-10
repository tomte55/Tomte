-- Run from the AddOns folder: lua Tomte/tests/test_questlist.lua
local ns = {}
assert(loadfile("Tomte/Modules/QuestList/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Q(id, fields)
	local q = { questID = id, title = "Q" .. id, level = 10, xp = 0, zone = "The Barrens", watched = true }
	for k, v in pairs(fields or {}) do
		q[k] = v
	end
	return q
end

local function ids(list)
	local out = {}
	for i, q in ipairs(list) do
		out[i] = q.questID
	end
	return table.concat(out, " ")
end

local function opts(o)
	local t = { show = "all", groupBy = "stop", turnInsFirst = true, open = 1, perSection = 6 }
	for k, v in pairs(o or {}) do
		t[k] = v
	end
	return t
end

test("stops keep their order; quests left off a stop go to a folded Other quests group", function()
	local quests = { Q(1), Q(2), Q(3, { zone = "Stonetalon Mountains" }), Q(4) }
	local stops = { { quests = { quests[2], quests[1] }, zone = "Crossroads", distance = 120 },
		{ quests = { quests[4] }, zone = "The Barrens", distance = 800 } }
	local s = ns.QuestList_Sections(quests, stops, opts())
	eq(#s, 3)
	eq(s[1].kind, "stop")
	eq(s[1].title, "Crossroads")
	eq(s[1].distance, 120)
	eq(ids(s[1].quests), "1 2")
	eq(s[1].open, true, "nearest stop open")
	eq(s[2].open, false, "second stop folded with open = 1")
	eq(s[2].shown, 0)
	eq(s[3].kind, "other")
	eq(s[3].title, "Other quests")
	eq(ids(s[3].quests), "3")
	eq(s[3].open, false)
end)

test("only the nearest stops get a group; the rest join Other quests, nearest first", function()
	local quests = { Q(1, { yards = 100 }), Q(2, { yards = 900 }), Q(3, { yards = 400 }), Q(4), Q(5, { yards = 2000 }) }
	local stops = { { quests = { quests[1] }, distance = 100 }, { quests = { quests[3] }, distance = 400 },
		{ quests = { quests[2] }, distance = 900 }, { quests = { quests[5] }, distance = 2000 } }
	local s = ns.QuestList_Sections(quests, stops, opts({ stops = 2 }))
	eq(#s, 3)
	eq(s[1].kind, "stop")
	eq(s[2].kind, "stop")
	eq(s[3].kind, "other")
	eq(ids(s[3].quests), "2 5 4", "farther stops by distance, no distance last")
	local all = ns.QuestList_Sections(quests, stops, opts({ stops = 2, folded = { other = false } }))
	eq(all[3].open, true, "opened by hand")
	eq(all[3].shown, 3)
end)

test("open opens that many stops", function()
	local quests = { Q(1), Q(2) }
	local stops = { { quests = { quests[1] } }, { quests = { quests[2] } } }
	local s = ns.QuestList_Sections(quests, stops, opts({ open = 2 }))
	eq(s[1].open, true)
	eq(s[2].open, true)
	eq(s[1].title, "Nearby", "a stop without a zone")
end)

test("quests hidden from the list go to a folded Hidden line; untracked ones stay in all mode", function()
	local quests = { Q(1), Q(2, { watched = false }), Q(3, { watched = false, active = true }), Q(4) }
	local hidden = { [4] = true }
	local s = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list", hidden = hidden }))
	eq(#s, 2)
	eq(ids(s[1].quests), "3 1 2", "untracked still listed (the active one first)")
	eq(s[2].kind, "hidden")
	eq(ids(s[2].quests), "4")
	eq(s[2].open, false)
	local t = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list", show = "tracked", hidden = hidden }))
	eq(ids(t[1].quests), "3 1", "tracked mode: watched or active")
	eq(ids(t[2].quests), "4", "hidden ones still reachable")
	eq(#ns.QuestList_Sections(quests, {}, opts({ groupBy = "list" })), 1, "nothing hidden: no Hidden line")
end)

test("a quest hidden from the list is not put on its stop", function()
	local quests = { Q(1), Q(2) }
	local s = ns.QuestList_Sections(quests, { { quests = { quests[1], quests[2] }, zone = "Camp" } },
		opts({ hidden = { [2] = true } }))
	eq(ids(s[1].quests), "1")
	eq(s[2].kind, "hidden")
end)

test("a quest's distance shows only when its stop header doesn't already say it", function()
	local a, b = Q(1, { yards = 141 }), Q(2, { yards = 420 })
	eq(ns.QuestList_ShowQuestDistance({ kind = "stop", distance = 141, quests = { a } }, a), false, "only quest")
	local stop = { kind = "stop", distance = 138, quests = { a, b } }
	eq(ns.QuestList_ShowQuestDistance(stop, a), false, "the nearest, same rounded distance")
	eq(ns.QuestList_ShowQuestDistance(stop, b), true, "a farther one")
	eq(ns.QuestList_ShowQuestDistance({ kind = "zone", quests = { a } }, a), true, "zones have no distance")
	eq(ns.QuestList_ShowQuestDistance(stop, Q(3)), false, "no spot")
end)

test("the player's fold wins, both ways", function()
	local quests = { Q(1), Q(2) }
	local stops = { { quests = { quests[1] } } }
	local key = "stop:1"
	local s = ns.QuestList_Sections(quests, stops, opts({ folded = { [key] = true, hidden = false },
		hidden = { [2] = true } }))
	eq(s[1].key, key)
	eq(s[1].open, false)
	eq(s[2].open, true, "Hidden opened by hand")
	eq(s[2].shown, 1)
end)

test("turn-ins first, then timed, then level, then most XP", function()
	local quests = { Q(1, { level = 5 }), Q(2, { level = 12, complete = true }), Q(3, { level = 9, timeLeft = 300 }),
		Q(4, { level = 5, xp = 500 }), Q(5, { level = 9, timeLeft = 100 }) }
	local s = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list" }))
	eq(ids(s[1].quests), "2 5 3 4 1")
	local plain = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list", turnInsFirst = false }))
	eq(ids(plain[1].quests), "5 3 4 1 2", "turn-in sorted by level when not first")
end)

test("zones: yours first, then by name; open counts", function()
	local quests = { Q(1, { zone = "Ashenvale" }), Q(2, { zone = "The Barrens" }), Q(3, { zone = "Durotar" }) }
	local s = ns.QuestList_Sections(quests, {}, opts({ groupBy = "zone", zone = "The Barrens", open = 2 }))
	eq(s[1].title, "The Barrens")
	eq(s[2].title, "Ashenvale")
	eq(s[3].title, "Durotar")
	eq(s[1].open, true)
	eq(s[2].open, true)
	eq(s[3].open, false)
end)

test("+N more past perSection, all once expanded", function()
	local quests = {}
	for i = 1, 8 do
		quests[i] = Q(i)
	end
	local s = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list", perSection = 3 }))
	eq(s[1].shown, 3)
	eq(s[1].more, 5)
	local e = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list", perSection = 3, expanded = { list = true } }))
	eq(e[1].shown, 8)
	eq(e[1].more, 0)
end)

test("an empty log has no sections", function()
	eq(#ns.QuestList_Sections({}, {}, opts()), 0)
end)

test("follow takes the nearest stop's top quest only", function()
	local quests = { Q(1), Q(2, { complete = true }) }
	local s = ns.QuestList_Sections(quests, { { quests = quests } }, opts())
	eq(ns.QuestList_FollowQuest(s).questID, 2, "turn-in on top")
	eq(ns.QuestList_FollowQuest(ns.QuestList_Sections(quests, {}, opts())), nil, "no stops")
	eq(ns.QuestList_FollowQuest({}), nil)
end)

test("objectives read both ways the game writes them", function()
	local o = ns.QuestList_Objective({ text = "0/6 Grimtotem Brute slain" })
	eq(o.label, "Grimtotem Brute slain")
	eq(o.have, 0)
	eq(o.need, 6)
	o = ns.QuestList_Objective({ text = "Kodo Liver: 1/1", finished = true })
	eq(o.label, "Kodo Liver")
	eq(o.have, 1)
	eq(o.need, 1)
	eq(o.finished, true)
	o = ns.QuestList_Objective({ text = "Find the note" })
	eq(o.label, "Find the note")
	eq(o.need, nil)
	eq(ns.QuestList_ObjectiveText(o), "Find the note")
	o = ns.QuestList_Objective({ text = "Lightning Gland: 2/5", numFulfilled = 3, numRequired = 5 })
	eq(o.have, 3, "the objective's own numbers win")
	eq(ns.QuestList_ObjectiveText(o), "3/5 Lightning Gland")
	o = ns.QuestList_Objective({ text = "Explore", numFulfilled = 0, numRequired = 0 })
	eq(o.need, nil, "a count of zero is no count")
end)

test("a bar only for counts above one", function()
	eq(ns.QuestList_ObjectiveShare({ have = 3, need = 6 }), 0.5)
	eq(ns.QuestList_ObjectiveShare({ have = 0, need = 1 }), nil)
	eq(ns.QuestList_ObjectiveShare({ label = "x" }), nil)
	eq(ns.QuestList_ObjectiveShare({ have = 9, need = 6 }), 1, "clamped")
end)

test("quest folding: manual wins, idle folds after 30 minutes when on", function()
	eq(ns.QuestList_QuestFolded(true, false, nil, 0), true)
	eq(ns.QuestList_QuestFolded(false, true, 0, 99999), false)
	eq(ns.QuestList_QuestFolded(nil, true, 0, 1799), false)
	eq(ns.QuestList_QuestFolded(nil, true, 0, 1800), true)
	eq(ns.QuestList_QuestFolded(nil, false, 0, 1800), false)
	eq(ns.QuestList_QuestFolded(nil, true, nil, 1800), false)
end)

test("stops in your zone are named by their direction", function()
	eq(ns.QuestList_Compass(0, 100, 100), "North")
	eq(ns.QuestList_Compass(100, 0, 100), "East")
	eq(ns.QuestList_Compass(-100, -100, 141), "Southwest")
	eq(ns.QuestList_Compass(70, 100, 122), "Northeast", "closer to north than east still reads northeast past 22.5 degrees")
	eq(ns.QuestList_Compass(20, 100, 102), "North")
	eq(ns.QuestList_Compass(0, -100, 100), "South")
	eq(ns.QuestList_Compass(100, -1, 100), "East", "just under east")
	eq(ns.QuestList_Compass(10, 10, 14), "Right here")
end)

test("the active quest comes first and opens its group", function()
	local quests = { Q(1, { yards = 100 }), Q(2, { yards = 900 }), Q(3, { yards = 400, active = true, level = 30 }) }
	local stops = { { quests = { quests[1] }, distance = 100 } }
	local s = ns.QuestList_Sections(quests, stops, opts({ stops = 1 }))
	eq(s[2].kind, "other")
	eq(s[2].open, true, "Other quests opens for the active quest")
	eq(ids(s[2].quests), "3 2", "active first, before nearer ones")
	local f = ns.QuestList_Sections(quests, stops, opts({ stops = 1, folded = { other = true } }))
	eq(f[2].open, false, "a fold clicked by hand still wins")
	local one = ns.QuestList_Sections({ Q(1, { level = 5 }), Q(2, { level = 9, active = true }) }, {},
		opts({ groupBy = "list" }))
	eq(ids(one[1].quests), "2 1")
end)

test("inside a dungeon its quests come first, open; the rest wait in Other quests", function()
	local quests = { Q(1, { zone = "Wailing Caverns" }), Q(2), Q(3, { dungeon = "Wailing Caverns" }),
		Q(4, { zone = "Wailing Caverns", watched = false }) }
	local s = ns.QuestList_Sections(quests, {}, opts({ instance = "Wailing Caverns", hidden = {} }))
	eq(s[1].kind, "instance")
	eq(s[1].title, "Wailing Caverns")
	eq(ids(s[1].quests), "1 3 4")
	eq(s[1].open, true)
	eq(s[2].kind, "other")
	eq(ids(s[2].quests), "2")
	eq(s[2].open, false)
	local z = ns.QuestList_Sections(quests, {}, opts({ groupBy = "zone", instance = "Wailing Caverns", open = 1 }))
	eq(z[1].kind, "instance")
	eq(z[2].title, "The Barrens")
	eq(z[2].open, true, "the instance group doesn't use up the open count")
	local l = ns.QuestList_Sections(quests, {}, opts({ groupBy = "list", instance = "Wailing Caverns" }))
	eq(#l, 2)
	eq(l[2].kind, "list")
	eq(#ns.QuestList_Sections(quests, {}, opts({ instance = "Ragefire Chasm" })), 1, "no quests for it: no group")
end)

test("level and count text", function()
	eq(ns.QuestList_LevelText(18), "18")
	eq(ns.QuestList_LevelText(60, true), "60+")
	eq(ns.QuestList_LevelText(nil), "?")
	eq(ns.QuestList_CountText(1), "1 quest")
	eq(ns.QuestList_CountText(3), "3 quests")
end)

H.done()
