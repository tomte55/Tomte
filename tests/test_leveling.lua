-- Run from the AddOns folder: lua Tomte/tests/test_leveling.lua
local ns = {}
assert(loadfile("Tomte/Modules/Leveling/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local BOWS, GUNS, CROSSBOW, WAND = 2, 3, 18, 19
local PROJECTILE, ARROW, BULLET = 6, 2, 3

test("ItemEnchant reads the link", function()
	eq(ns.Leveling_ItemEnchant("|cffffffff|Hitem:2304:15:::::::|h[Grips]|h|r"), 15)
	eq(ns.Leveling_ItemEnchant("|cffffffff|Hitem:2304::::::::|h[Grips]|h|r"), nil, "no enchant")
	eq(ns.Leveling_ItemEnchant("item:2304:0:0"), nil, "zero is none")
	eq(ns.Leveling_ItemEnchant("item:2304"), nil)
	eq(ns.Leveling_ItemEnchant(nil), nil)
end)

local function kitGear()
	return {
		{ slot = 5, label = "chest", name = "Vest", link = "item:1:15:" },
		{ slot = 7, label = "legs", name = "Pants", link = "item:2::" },
		{ slot = 10, label = "hands", name = "Grips", link = "item:3::" },
	}
end

test("KitPlan: the best kit you can use, on the first empty piece", function()
	local kits = { { itemID = 3, name = "Heavy", count = 1, minLevel = 20 }, { itemID = 1, name = "Light", count = 5, minLevel = 0 } }
	local plan = ns.Leveling_KitPlan(kits, kitGear(), 10)
	eq(plan.kit.itemID, 1, "Heavy is too high a level")
	eq(plan.slot, 7, "the chest has an enchant")
	eq(plan.gear, "Pants")
	eq(#plan.empty, 2)
	eq(ns.Leveling_KitPlan(kits, kitGear(), 25).kit.itemID, 3)
end)

test("KitPlan: nothing to do", function()
	local light = { { itemID = 1, count = 5 } }
	eq(ns.Leveling_KitPlan({}, kitGear(), 10), nil, "no kit")
	eq(ns.Leveling_KitPlan({ { itemID = 1, count = 0 } }, kitGear(), 10), nil, "none left")
	eq(ns.Leveling_KitPlan(light, { { slot = 5, label = "chest", link = "item:1:15:" } }, 10), nil, "every piece has something")
	eq(ns.Leveling_KitPlan(light, { { slot = 5, label = "chest" } }, 10), nil, "a link that can't be read isn't offered")
	eq(ns.Leveling_KitPlan(light, {}, 10), nil, "nothing worn")
end)

test("the kit's macro and tooltip line", function()
	eq(ns.Leveling_KitMacro(2304, 10), "/use item:2304\n/use 10")
	eq(ns.Leveling_KitTipLine(ns.Leveling_EmptyGear(kitGear())), "Can go on: legs, hands")
	eq(ns.Leveling_KitTipLine({}), "Nothing empty to put it on")
end)

test("the To do row for armor kits", function()
	local plan = ns.Leveling_KitPlan({ { itemID = 1, name = "Light Armor Kit", count = 5 } }, kitGear(), 10)
	local todo = ns.Leveling_Checklist({ visited = true, ready = {}, oldRanks = {}, reagents = {}, turnIns = {}, kit = plan })
	eq(todo[1].key, "kits")
	eq(todo[1].text, "2 pieces could take your Light Armor Kit")
	eq(#ns.Leveling_Checklist({ visited = true, ready = {}, oldRanks = {}, reagents = {}, turnIns = {} }), 0)
end)

test("AmmoTypes merges stacks, usable and best first", function()
	local items = {
		{ itemID = 1, name = "Rough", count = 200, subclassID = ARROW, minLevel = 1 },
		{ itemID = 3, name = "Heavy", count = 150, subclassID = BULLET, minLevel = 1 },
		{ itemID = 2, name = "Sharp", count = 50, subclassID = ARROW, minLevel = 10 },
		{ itemID = 1, name = "Rough", count = 150, subclassID = ARROW, minLevel = 1 },
		{ itemID = 4, name = "Jagged", count = 20, subclassID = ARROW, minLevel = 40 },
	}
	local types = ns.Leveling_AmmoTypes(items, BOWS, 20)
	eq(#types, 4)
	eq(types[1].itemID, 2, "best you can use")
	eq(types[2].itemID, 1)
	eq(types[2].count, 350, "two stacks")
	eq(types[3].fits, false)
	eq(types[3].itemID, 4, "too high a level, listed after what you can use")
	eq(types[4].itemID, 3, "bullets for a bow")
	eq(types[4].fits, false)
	eq(ns.Leveling_AmmoTypes(items, GUNS, 20)[1].itemID, 3)
	eq(ns.Leveling_AmmoTypes(items, CROSSBOW, 20)[1].itemID, 2, "crossbows fire arrows")
	eq(ns.Leveling_AmmoTypes({ { itemID = 1, count = 5, subclassID = ARROW } }, BOWS, 1)[1].fits, true, "item data not loaded")
	eq(ns.Leveling_AmmoTypes(items, nil, 20)[1].fits, false, "no weapon")
end)

test("AmmoNext goes round what you can use", function()
	local types = { { itemID = 2, fits = true }, { itemID = 1, fits = true }, { itemID = 3, fits = false } }
	eq(ns.Leveling_AmmoNext(types, 1).itemID, 2, "from the cheap one to the best")
	eq(ns.Leveling_AmmoNext(types, 2).itemID, 1, "and back")
	eq(ns.Leveling_AmmoNext(types, nil).itemID, 2, "an empty slot gets the best")
	eq(ns.Leveling_AmmoNext(types, 3).itemID, 2, "unusable in the slot gets the best")
	eq(ns.Leveling_AmmoNext({ { itemID = 2, fits = true } }, 2), nil, "only one: nothing to switch to")
	eq(ns.Leveling_AmmoNext({ { itemID = 3, fits = false } }, nil), nil)
	eq(ns.Leveling_AmmoNext({}, nil), nil)
end)

test("AmmoView", function()
	eq(ns.Leveling_AmmoView(false, 500, 100, true, false), nil, "no use for ammo")
	local fine = ns.Leveling_AmmoView(true, 1578, 100, true, true)
	eq(fine.count, 1578, "past the quiver's 999")
	eq(fine.role, "text")
	eq(fine.hint, nil, "nothing to say, even with another kind carried")
	eq(ns.Leveling_AmmoView(true, 100, 100, true, false).role, "warning")
	local out = ns.Leveling_AmmoView(true, 0, 100, true, true)
	eq(out.role, "danger")
	eq(out.hint, "Click to switch")
	eq(ns.Leveling_AmmoView(true, 0, 100, true, false).hint, "No ammo")
	local wrong = ns.Leveling_AmmoView(true, 500, 100, false, true)
	eq(wrong.count, 0, "bullets in a bow's slot can't be fired")
	eq(wrong.hint, "Click to switch")
	eq(ns.Leveling_AmmoView(true, 0, 100, nil, false).hint, "No ammo", "empty slot")
end)

test("AmmoMacro", function()
	eq(ns.Leveling_AmmoMacro(2512), "/equip item:2512")
end)

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
		{ spellID = 3, name = "Tame Beast", highest = false },
		{ spellID = 5, name = "Tame Beast", subtext = "", highest = false },
		{ spellID = 6, name = "Berserking", subtext = "Racial", highest = false },
		{ spellID = 4, name = "Unknown" },
	})
	eq(#list, 1, "a spell with no rank is never an old rank")
	eq(list[1], "Frostbolt (Rank 1)")
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

test("CaresAboutAmmo: hunters always, other classes only with ammo loaded", function()
	eq(ns.Leveling_CaresAboutAmmo("HUNTER", false), true)
	eq(ns.Leveling_CaresAboutAmmo("HUNTER", true), true)
	eq(ns.Leveling_CaresAboutAmmo("ROGUE", false), false, "a rogue with a bow and no arrows")
	eq(ns.Leveling_CaresAboutAmmo("WARRIOR", true), true, "a warrior who loaded bullets")
	eq(ns.Leveling_CaresAboutAmmo(nil, false), false)
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

test("SupplyToast says what ran low", function()
	local ARROW_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"
	local REAGENT_ICON = "Interface\\Icons\\INV_Misc_Dust_02"
	local arrows = { kind = "ammo", name = "Sharp Arrow", countText = "1,097", icon = 12345 }
	local rebirth = { kind = "reagent", name = "Rebirth", count = 1 }
	local portal = { kind = "reagent", name = "Portal", count = 3 }

	local title, text, icon = ns.Leveling_SupplyToast({ arrows })
	eq(title, "Low on ammo")
	eq(text, "Sharp Arrow: 1,097 left. Buy more at a vendor.")
	eq(icon, 12345, "the ammo's own icon")

	title, text, icon = ns.Leveling_SupplyToast({ { kind = "ammo", countText = "97" } })
	eq(text, "Ammo: 97 left. Buy more at a vendor.", "the item hasn't loaded")
	eq(icon, ARROW_ICON)

	title, text, icon = ns.Leveling_SupplyToast({ { kind = "ammo", out = true } })
	eq(title, "Out of ammo")
	eq(text, "Buy more at a vendor.")
	eq(icon, ARROW_ICON)

	title, text, icon = ns.Leveling_SupplyToast({ rebirth, portal })
	eq(title, "Low on reagents")
	eq(text, "Rebirth: 1 cast left. Portal: 3 casts left.")
	eq(icon, REAGENT_ICON)

	title, text, icon = ns.Leveling_SupplyToast({ arrows, rebirth })
	eq(title, "Low on ammo and reagents")
	eq(text, "Sharp Arrow: 1,097 left. Rebirth: 1 cast left. Buy more at a vendor.")
	eq(icon, 12345)

	title, text = ns.Leveling_SupplyToast({ { kind = "ammo", out = true }, rebirth })
	eq(title, "Out of ammo, low on reagents")
	eq(text, "Rebirth: 1 cast left. Buy more at a vendor.")
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

test("QuestDungeon: the dungeon's log heading, else its quest tag", function()
	local dungeons = { { name = "Wailing Caverns" }, { name = "Ragefire Chasm" } }
	eq(ns.Leveling_QuestDungeon({ zone = "Wailing Caverns" }, dungeons), "Wailing Caverns")
	eq(ns.Leveling_QuestDungeon({ zone = "Orgrimmar", tagID = 81 }, dungeons), "Dungeon")
	eq(ns.Leveling_QuestDungeon({ zone = "Orgrimmar", tagID = 62 }, dungeons), "Raid")
	eq(ns.Leveling_QuestDungeon({ zone = "The Barrens", tagID = 1 }, dungeons), nil, "a group quest isn't a dungeon")
	eq(ns.Leveling_QuestDungeon({ zone = "The Barrens" }, dungeons), nil)
end)

test("NextStops: close quests share a stop, the nearest stop first", function()
	local quests = {
		{ questID = 1, title = "Far A", level = 15, difficulty = 2 },
		{ questID = 2, title = "Near B", level = 18, difficulty = 2, xp = 100 },
		{ questID = 3, title = "Near A", level = 18, difficulty = 2, xp = 900 },
		{ questID = 4, title = "Hand in", level = 20, complete = true },
		{ questID = 5, title = "No point", level = 10, difficulty = 2 },
	}
	local points = {
		[1] = { x = 2000, y = 0, continent = 1, zone = "Stonetalon Mountains" },
		[2] = { x = 100, y = 0, continent = 1, zone = "The Barrens" },
		[3] = { x = 350, y = 0, continent = 1, zone = "The Barrens" }, -- 250 from 2: same stop
		[4] = { x = 600, y = 0, continent = 1, zone = "The Barrens" }, -- 250 from 3: chained in
	}
	local stops = ns.Leveling_NextStops(quests, points, { x = 0, y = 0, continent = 1 }, false, 300)
	eq(#stops, 2, "the quest without a point is left out")
	eq(stops[1].zone, "The Barrens")
	eq(stops[1].distance, 100)
	eq(stops[1].quests[1].title, "Hand in", "turn-ins first")
	eq(stops[1].quests[2].title, "Near A", "then by level, the most XP first")
	eq(stops[1].quests[3].title, "Near B")
	eq(stops[1].groups[4], "done")
	eq(stops[2].quests[1].title, "Far A")
	eq(stops[2].distance, 2000)
end)

test("NextStops: hard and dungeon quests only while grouped, other continents left out", function()
	local quests = {
		{ questID = 1, title = "Elite", level = 18, elite = true },
		{ questID = 2, title = "Dungeon", level = 18, difficulty = 2, dungeon = "Wailing Caverns" },
		{ questID = 3, title = "Grey", level = 5, difficulty = 0 },
		{ questID = 4, title = "Abroad", level = 18, difficulty = 2 },
	}
	local points = {
		[1] = { x = 0, y = 0, continent = 1 }, [2] = { x = 0, y = 0, continent = 1 },
		[3] = { x = 0, y = 0, continent = 1 }, [4] = { x = 0, y = 0, continent = 0 },
	}
	local you = { x = 0, y = 0, continent = 1 }
	eq(#ns.Leveling_NextStops(quests, points, you, false, 300), 0, "solo: none of them")
	local stops = ns.Leveling_NextStops(quests, points, you, true, 300)
	eq(#stops[1].quests, 2, "grouped: the elite and the dungeon quest")
	eq(#ns.Leveling_NextStops(quests, points, nil, false, 300), 1, "no position: every continent counts")
	eq(ns.Leveling_StopYards(234), 230)
	eq(ns.Leveling_StopYards(236), 240)
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

test("ProfessionRanks: a profession at its cap, the next rank and the level it needs", function()
	local profs = { { name = "Skinning", skill = 75, max = 75 }, { name = "Mining", skill = 60, max = 75 },
		{ name = "Cooking", skill = 150, max = 150 }, { name = "First Aid", skill = 300, max = 300 } }
	local list = ns.Leveling_ProfessionRanks(profs, 16)
	eq(#list, 2)
	eq(list[1].name, "Skinning")
	eq(list[1].rank, "Journeyman")
	eq(list[1].ready, true)
	eq(list[2].rank, "Expert")
	eq(list[2].needLevel, 20)
	eq(list[2].ready, false, "level 16 is too low for Expert")
end)

test("Checklist: capped professions, ready ones first", function()
	local todo = ns.Leveling_Checklist({ visited = true, ready = {}, oldRanks = {}, reagents = {}, turnIns = {},
		professions = ns.Leveling_ProfessionRanks({ { name = "Skinning", skill = 75, max = 75 } }, 16) })
	eq(todo[1].key, "professions")
	eq(todo[1].text, "Skinning is at 75/75")
	eq(todo[1].sub, "Learn Journeyman Skinning at its trainer.")
	local waiting = ns.Leveling_Checklist({ visited = true, ready = {}, oldRanks = {}, reagents = {}, turnIns = {},
		professions = ns.Leveling_ProfessionRanks({ { name = "Cooking", skill = 150, max = 150 } }, 16) })
	eq(waiting[1].sub, "Expert Cooking needs level 20.")
end)

test("TurnInPlaces: finished quests counted by their quest log zone", function()
	eq(ns.Leveling_TurnInPlaces({ { zone = "The Barrens" }, { zone = "Mulgore" }, { zone = "The Barrens" }, {} }),
		"The Barrens: 2, Mulgore: 1")
	eq(ns.Leveling_TurnInPlaces({}), nil)
	local todo = ns.Leveling_Checklist({ visited = true, ready = {}, oldRanks = {}, reagents = {},
		turnIns = { { title = "A", zone = "The Barrens" }, { title = "B", zone = "Mulgore" } } })
	eq(todo[1].sub, "Mulgore: 1, The Barrens: 1", "where to go, rather than the names; a tie goes by name")
end)

test("Checklist: the mount fund and dungeons with your quests", function()
	local todo = ns.Leveling_Checklist({ visited = true, ready = {}, oldRanks = {}, reagents = {}, turnIns = {},
		mount = ns.Leveling_MountFund(470000, 100, 30, 0, 50000), mountText = "47g of 100g", mountHours = "11h",
		dungeons = { { name = "Wailing Caverns", min = 17, max = 24, quests = 2 } } })
	local keys = {}
	for _, item in ipairs(todo) do
		keys[item.key] = item
	end
	eq(keys.mount.text, "Riding: 47g of 100g saved")
	eq(keys.mount.sub, "About 11h at your usual gold per hour.")
	eq(keys.dungeons.text, "Wailing Caverns: 2 of your quests")
	eq(keys.dungeons.sub, "Levels 17-24. Groups in chat lists who's going.")
end)

test("MountFund: saved, still to go and how long at your pace", function()
	local f = ns.Leveling_MountFund(470000, 100, 30, 0, 50000)
	eq(f.goal, 1000000)
	eq(f.left, 530000)
	eq(f.hours, 10.6)
	eq(ns.Leveling_MountFund(470000, 100, 29, 0, 50000), nil, "below level 30")
	eq(ns.Leveling_MountFund(470000, 100, 35, 1, 50000), nil, "has a mount")
	eq(ns.Leveling_MountFund(470000, 0, 35, 0, 50000), nil, "goal off")
	eq(ns.Leveling_MountFund(1200000, 100, 35, 0, 50000).left, 0)
	eq(ns.Leveling_MountFund(470000, 100, 35, 0, 0).hours, nil, "no pace yet")
end)

test("DungeonsNear: dungeons around your level with quests in your log", function()
	local dungeons = { { key = "rfc", name = "Ragefire Chasm", min = 13, max = 18 },
		{ key = "wc", name = "Wailing Caverns", min = 17, max = 24 }, { key = "sfk", name = "Shadowfang Keep", min = 22, max = 30 } }
	local quests = { { zone = "Wailing Caverns" }, { zone = "Wailing Caverns" }, { zone = "Shadowfang Keep" }, { zone = "Mulgore" } }
	local near = ns.Leveling_DungeonsNear(dungeons, 16, quests)
	eq(#near, 1, "Shadowfang Keep is too far ahead")
	eq(near[1].name, "Wailing Caverns")
	eq(near[1].quests, 2)
end)

H.done()
