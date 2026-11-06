-- Run from the AddOns folder: lua Tomte/tests/test_leveling.lua
local ns = {}
assert(loadfile("Tomte/Modules/Leveling/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local BOWS, GUNS, CROSSBOW, WAND = 2, 3, 18, 19
local PROJECTILE, ARROW, BULLET = 6, 2, 3

test("SlimService keeps what can still be learned", function()
	local s = ns.Leveling_SlimService("Frostbolt", "available", "Rank 2", 4, 100)
	eq(s.name, "Frostbolt")
	eq(s.rank, "Rank 2")
	eq(s.level, 4)
	eq(s.cost, 100)
	eq(ns.Leveling_SlimService("Frostbolt", "unavailable", "", 6, 200).rank, nil, "empty rank")
	eq(ns.Leveling_SlimService("Frostbolt", "used", "Rank 1", 1, 0), nil, "learned")
	eq(ns.Leveling_SlimService("Frost", "header"), nil, "header")
	eq(ns.Leveling_SlimService(nil, "available"), nil, "no name yet")
end)

test("TrainerSplit: ready now, and the next level with anything", function()
	local rows = {
		{ name = "B", level = 4, cost = 10 }, { name = "A", level = 4, cost = 5 }, { name = "C", level = 2, cost = 1 },
		{ name = "D", level = 8, cost = 1 }, { name = "E", level = 6, cost = 1 }, { name = "F", level = 6, cost = 1 },
	}
	local ready, nextLevel, upcoming = ns.Leveling_TrainerSplit(rows, 4)
	eq(#ready, 3)
	eq(ready[1].name, "C", "lowest level first")
	eq(ready[2].name, "A", "then by name")
	eq(nextLevel, 6)
	eq(#upcoming, 2)
	eq(ns.Leveling_TrainerCost(ready), 16)
end)

test("TrainerSplit copes with nothing saved and nothing left", function()
	local ready, nextLevel, upcoming = ns.Leveling_TrainerSplit(nil, 4)
	eq(#ready, 0)
	eq(nextLevel, nil)
	eq(#upcoming, 0)
end)

test("MergeTrainer keeps later rows only when the trainer hid them", function()
	local old = { { name = "Old now", level = 4 }, { name = "Later", level = 8 } }
	local rows = { { name = "New", level = 4 } }
	local hidden = ns.Leveling_MergeTrainer(old, rows, 4, false)
	eq(#hidden, 2, "later row kept, learnable one replaced")
	eq(hidden[2].name, "Later")
	eq(#ns.Leveling_MergeTrainer(old, rows, 4, true), 1, "the whole list was shown")
	eq(#ns.Leveling_MergeTrainer(nil, rows, 4, false), 1, "first visit")
end)

test("names", function()
	eq(ns.Leveling_ServiceName({ name = "Frostbolt", rank = "Rank 2" }), "Frostbolt (Rank 2)")
	eq(ns.Leveling_ServiceName({ name = "Polymorph" }), "Polymorph")
	eq(ns.Leveling_JoinNames({ "A", "B" }, 3), "A, B")
	eq(ns.Leveling_JoinNames({ "A", "B", "C", "D" }, 2), "A, B and 2 more")
end)

test("old ranks: only known low ones, once each", function()
	local list = ns.Leveling_OldRanks({
		{ spellID = 1, name = "Frostbolt", subtext = "Rank 1", highest = false },
		{ spellID = 1, name = "Frostbolt", subtext = "Rank 1", highest = false },
		{ spellID = 2, name = "Frostbolt", subtext = "Rank 2", highest = true },
		{ spellID = 3, name = "Blink", highest = false },
		{ spellID = 4, name = "Unknown" },
	})
	eq(#list, 2)
	eq(list[1], "Blink")
	eq(list[2], "Frostbolt (Rank 1)")
end)

test("low reagents: consumable spells only, fewest first, a name once at its lowest", function()
	local list = ns.Leveling_LowReagents({
		{ name = "Portal", consumable = true, count = 2 },
		{ name = "Arcane Brilliance", consumable = true, count = 4 },
		{ name = "Arcane Brilliance", consumable = true, count = 1 },
		{ name = "Plenty", consumable = true, count = 20 },
		{ name = "Fireball", consumable = false, count = 0 },
		{ name = "No count", consumable = true },
	}, 5)
	eq(#list, 2)
	eq(list[1].name, "Arcane Brilliance")
	eq(list[1].count, 1)
	eq(list[2].name, "Portal")
end)

test("ammo for the weapon", function()
	eq(ns.Leveling_AmmoFor(BOWS), ARROW)
	eq(ns.Leveling_AmmoFor(CROSSBOW), ARROW)
	eq(ns.Leveling_AmmoFor(GUNS), BULLET)
	eq(ns.Leveling_AmmoFor(WAND), nil)
	eq(ns.Leveling_AmmoFor(nil), nil)
end)

test("ammo state", function()
	eq(ns.Leveling_AmmoState(false, 0, 100), nil, "doesn't use ammo")
	eq(ns.Leveling_AmmoState(true, 0, 100), "none")
	eq(ns.Leveling_AmmoState(true, nil, 100), "none")
	eq(ns.Leveling_AmmoState(true, 100, 100), "low")
	eq(ns.Leveling_AmmoState(true, 101, 100), "ok")
end)

test("PickAmmo: the right kind, the best you can use and afford", function()
	local items = {
		{ index = 1, classID = PROJECTILE, subclassID = ARROW, minLevel = 1, price = 10 },
		{ index = 2, classID = PROJECTILE, subclassID = ARROW, minLevel = 10, price = 100 },
		{ index = 3, classID = PROJECTILE, subclassID = ARROW, minLevel = 25, price = 500 },
		{ index = 4, classID = PROJECTILE, subclassID = BULLET, minLevel = 10, price = 100 },
		{ index = 5, classID = 0, subclassID = ARROW, minLevel = 12, price = 1 },
	}
	eq(ns.Leveling_PickAmmo(items, BOWS, 15, 1000).index, 2, "level")
	eq(ns.Leveling_PickAmmo(items, BOWS, 30, 1000).index, 3, "best")
	eq(ns.Leveling_PickAmmo(items, BOWS, 30, 50).index, 1, "money")
	eq(ns.Leveling_PickAmmo(items, GUNS, 30, 1000).index, 4, "bullets")
	eq(ns.Leveling_PickAmmo(items, GUNS, 5, 1000), nil, "none usable")
	eq(ns.Leveling_PickAmmo(items, WAND, 30, 1000), nil, "no ammo for a wand")
	items[2].usable = false
	eq(ns.Leveling_PickAmmo(items, BOWS, 15, 1000).index, 1, "not usable")
	items[2].usable = nil
	eq(ns.Leveling_PickAmmo(items, BOWS, 30).index, 3, "no money given: the best you can use")
end)

test("AmmoRoom: ammo bags apart from ordinary bags", function()
	local ammoRoom, normalRoom = ns.Leveling_AmmoRoom({
		{ family = 0, free = 2, topUp = 0 },
		{ family = 1, free = 3, topUp = 143 },
		{ family = 1, free = 1, topUp = 0 },
	}, 200)
	eq(ammoRoom, 943, "free slots and part stacks in both quivers")
	eq(normalRoom, 400)
	ammoRoom, normalRoom = ns.Leveling_AmmoRoom({ { family = 0, free = 1, topUp = 50 } }, 200)
	eq(ammoRoom, nil, "no ammo bag")
	eq(normalRoom, 250)
	eq(ns.Leveling_AmmoRoom({ { family = 1, free = 0, topUp = 0 } }, 200), 0, "a full quiver isn't no quiver")
end)

test("AmmoFill: fills an ammo bag, ignoring the target", function()
	local item = { price = 100, stack = 200 }
	local amount, cost = ns.Leveling_AmmoFill(item, 1143, 5000, 3000, 400, 100000)
	eq(amount, 1143, "exactly the room, never into other bags")
	eq(cost, 572, "rounded up to whole copper")
	eq(ns.Leveling_AmmoFill(item, 0, 5000, 0, 400, 100000), 0, "full")
end)

test("AmmoFill: without an ammo bag, up to the target and what the bags hold", function()
	local item = { price = 100, stack = 200 }
	eq(ns.Leveling_AmmoFill(item, nil, 5000, 150, 400, 100000), 250, "the rest of the target")
	eq(ns.Leveling_AmmoFill(item, nil, 100, 150, 400, 100000), 100, "bags nearly full")
	eq(ns.Leveling_AmmoFill(item, nil, 5000, 600, 400, 100000), 0, "already past the target")
end)

test("AmmoFill: limited by money and stock", function()
	local amount, cost = ns.Leveling_AmmoFill({ price = 100, stack = 200 }, 1000, 0, 0, 400, 75)
	eq(amount, 150, "as many as you can pay for")
	eq(cost, 75)
	eq(ns.Leveling_AmmoFill({ price = 100, stack = 200 }, 1000, 0, 0, 400, 0), 0, "no money")
	eq(ns.Leveling_AmmoFill({ price = 100, stack = 200, available = 300 }, 1000, 0, 0, 400, 100000), 300, "limited stock")
	eq(ns.Leveling_AmmoFill({ price = 100, stack = 200, available = -1 }, 1000, 0, 0, 400, 100000), 1000, "unlimited")
	eq(ns.Leveling_AmmoFill({ price = 0 }, 1000, 0, 0, 400, 0), 1000, "free")
end)

test("AutoBudget: a quarter of your money, in whole copper", function()
	eq(ns.Leveling_AutoBudget(1000), 250)
	eq(ns.Leveling_AutoBudget(3), 0)
	eq(ns.Leveling_AutoBudget(0), 0)
end)

test("BuyBatches: purchases no larger than the game allows", function()
	local batches = ns.Leveling_BuyBatches(543, 200)
	eq(#batches, 3)
	eq(batches[1], 200)
	eq(batches[2], 200)
	eq(batches[3], 143)
	eq(#ns.Leveling_BuyBatches(0, 200), 0)
	eq(#ns.Leveling_BuyBatches(400, 200), 2, "whole stacks leave nothing over")
end)

test("NewlyLow warns once until it recovers", function()
	local fresh, now = ns.Leveling_NewlyLow({}, { "a", "b" })
	eq(#fresh, 2)
	fresh, now = ns.Leveling_NewlyLow(now, { "a", "b" })
	eq(#fresh, 0)
	fresh, now = ns.Leveling_NewlyLow(now, { "b" })
	eq(#fresh, 0)
	fresh = ns.Leveling_NewlyLow(now, { "a", "b" })
	eq(#fresh, 1)
	eq(fresh[1], "a")
end)

test("quest groups, in order of what decides", function()
	local G = ns.Leveling_QuestGroup
	eq(G({ complete = true, timeLeft = 5, elite = true }), "done")
	eq(G({ timeLeft = 5, elite = true }), "timed")
	eq(G({ elite = true, difficulty = 0 }), "hard", "elite beats grey")
	eq(G({ difficulty = 3 }), "hard", "difficult")
	eq(G({ difficulty = 4 }), "hard", "impossible")
	eq(G({ difficulty = 2 }), "now")
	eq(G({ difficulty = 1 }), "easy")
	eq(G({ difficulty = 0 }), "grey")
	eq(G({}), "now", "unknown difficulty")
end)

test("SortQuests sorts by level, and the shortest timer first", function()
	local groups = ns.Leveling_SortQuests({
		{ title = "B", level = 5, difficulty = 2 }, { title = "A", level = 5, difficulty = 2 },
		{ title = "C", level = 3, difficulty = 2 }, { title = "T1", level = 1, timeLeft = 90 },
		{ title = "T2", level = 9, timeLeft = 30 },
	})
	eq(groups.now[1].title, "C")
	eq(groups.now[2].title, "A")
	eq(groups.now[3].title, "B")
	eq(groups.timed[1].title, "T2")
	eq(#groups.grey, 0, "every group exists")
end)

test("TimeLeft", function()
	eq(ns.Leveling_TimeLeft(12), "12s")
	eq(ns.Leveling_TimeLeft(240), "4m")
	eq(ns.Leveling_TimeLeft(3900), "1h 5m")
end)

test("SkillsBehind: worn first, then furthest behind", function()
	local list = ns.Leveling_SkillsBehind({
		{ name = "Axes", rank = 40, max = 50 },
		{ name = "Bows", rank = 45, max = 50, worn = true },
		{ name = "Daggers", rank = 1, max = 50 },
		{ name = "Swords", rank = 42, max = 50, worn = true },
		{ name = "Empty", rank = 0, max = 0 },
	}, 5)
	eq(#list, 4)
	eq(list[1].name, "Swords")
	eq(list[2].name, "Bows")
	eq(list[3].name, "Daggers")
	eq(list[4].name, "Axes")
	eq(#ns.Leveling_SkillsBehind({ { name = "A", rank = 46, max = 50 } }, 5), 0, "close enough")
end)

test("XPView places the bar's parts", function()
	local v = ns.Leveling_XPView(250, 1000, 100, 500)
	eq(v.fraction, 0.25)
	eq(v.percent, 25)
	eq(v.toGo, 750)
	eq(v.restedEnd, 0.35)
	eq(v.turnInEnd, 0.75)
	eq(v.reachesLevel, false)
end)

test("XPView caps at the bar's end and says when turn-ins reach the level", function()
	local v = ns.Leveling_XPView(900, 1000, 500, 100)
	eq(v.restedEnd, 1)
	eq(v.turnInEnd, 1)
	eq(v.reachesLevel, true, "exactly enough")
	eq(ns.Leveling_XPView(900, 1000, 0, 0).reachesLevel, false, "nothing to turn in")
end)

test("XPView has nothing to show without XP to earn", function()
	eq(ns.Leveling_XPView(0, 0), nil)
	eq(ns.Leveling_XPView(0, nil), nil)
	eq(ns.Leveling_XPView(nil, 100).fraction, 0, "no XP read yet")
end)

local function Clean()
	return { visited = true, ready = {}, talents = false, oldRanks = {}, reagents = {}, turnIns = {} }
end

test("Checklist with nothing waiting says what came up clean", function()
	local s = Clean()
	s.ammoState, s.ammoText = "ok", "1,200"
	local todo, fine = ns.Leveling_Checklist(s)
	eq(#todo, 0)
	eq(fine, "All fine: trainer, talents, spell ranks, ammo (1,200)")
end)

test("Checklist leaves out ammo for a character that doesn't use it", function()
	local _, fine = ns.Leveling_Checklist(Clean())
	eq(fine, "All fine: trainer, talents, spell ranks")
end)

test("Checklist puts turn-ins first and adds up their XP", function()
	local s = Clean()
	s.talents = true
	s.turnIns = { { title = "Kolkar Attack", xp = 300 }, { title = "Lost Eggs", xp = 200 }, { title = "Old Bones" } }
	local todo = ns.Leveling_Checklist(s)
	eq(todo[1].key, "turnIns")
	eq(todo[1].text, "3 quests to turn in")
	eq(todo[1].sub, "Kolkar Attack, Lost Eggs and 1 more")
	eq(todo[1].xp, 500)
	eq(todo[2].key, "talents")
end)

test("Checklist gives no XP while a reward isn't known", function()
	local s = Clean()
	s.turnIns = { { title = "Old Bones", xp = 0 } }
	local todo = ns.Leveling_Checklist(s)
	eq(todo[1].text, "1 quest to turn in")
	eq(todo[1].xp, nil)
end)

test("Checklist: the trainer", function()
	local s = Clean()
	s.visited = false
	local todo, fine = ns.Leveling_Checklist(s)
	eq(todo[1].text, "Visit your class trainer once")
	eq(fine, "All fine: talents, spell ranks", "an unseen trainer isn't fine")

	s.visited = true
	s.ready = { { name = "Serpent Sting", rank = "Rank 2", level = 10, cost = 500 }, { name = "Track Beasts", level = 4, cost = 100 } }
	todo = ns.Leveling_Checklist(s)
	eq(todo[1].text, "2 new at your class trainer")
	eq(todo[1].sub, "Serpent Sting (Rank 2), Track Beasts")
	eq(todo[1].cost, 600)
end)

test("Checklist: old ranks, reagents and ammo", function()
	local s = Clean()
	s.oldRanks = { "Frostbolt (Rank 1)" }
	s.reagents = { { name = "Portal", count = 1 }, { name = "Rebirth", count = 3 } }
	s.ammoState = "none"
	local todo = ns.Leveling_Checklist(s)
	eq(todo[1].text, "An old rank on your bars")
	eq(todo[2].sub, "Portal: 1 cast, Rebirth: 3 casts")
	eq(todo[3].text, "Out of ammo")
	eq(todo[3].role, "danger")

	s.oldRanks = { "A", "B" }
	s.ammoState, s.ammoText = "low", "80"
	todo = ns.Leveling_Checklist(s)
	eq(todo[1].text, "2 old ranks on your bars")
	eq(todo[3].text, "Low on ammo: 80 left")
	eq(todo[3].role, "warning")
end)

test("Every quest group has its colors", function()
	for _, g in ipairs(ns.LEVELING_QUEST_GROUPS) do
		eq(type(g.role), "string", g.key)
		eq(type(g.textRole), "string", g.key)
	end
end)

H.done()
