-- Run from the AddOns folder: lua Tomte/tests/test_dungeonjournal.lua
local ns = {}
assert(loadfile("Tomte/Modules/DungeonJournal/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- A made-up dungeon with two wings.
local INST = {
	id = 1, name = "Kesha's Vault", min = 20, max = 28,
	wings = {
		{ name = "Upper", min = 20,
			quests = {
				{ id = 101, name = "Both Sides", lvl = 18 },
				{ id = 102, name = "Alliance Only", lvl = 20, side = "A" },
				{ id = 103, name = "Horde Only", lvl = 22, side = "H" },
			},
			bosses = { { name = "Mira the Bold", npc = 11, loot = { 1001, 1002 } } },
			rares = { { name = "Old Aldric", npc = 12, loot = { 1003 } } },
			trash = { 1004 },
		},
		{ name = "Lower", min = 24,
			quests = {
				{ id = 104, name = "Mage Lesson", lvl = 24, side = "A", classes = { "MAGE" } },
				{ id = 105, name = "Deeper Down", lvl = 24, side = "A" },
			},
			bosses = { { name = "Grimtooth", npc = 13, loot = { 1005 } } },
			rares = {}, trash = {},
		},
	},
}

local function Ctx(over)
	local ctx = { level = 21, side = "A", class = "WARRIOR", done = function()
		return false
	end, active = function()
		return false
	end }
	for k, v in pairs(over or {}) do
		ctx[k] = v
	end
	return ctx
end

test("LevelText: a range, or a minimum, or nothing", function()
	eq(ns.DJ_LevelText(13, 20), "Level 13-20")
	eq(ns.DJ_LevelText(48, nil), "Level 48+")
	eq(ns.DJ_LevelText(nil, nil), nil)
end)

test("LevelGroup: right for you, coming up, behind you", function()
	eq(ns.DJ_LevelGroup(10, 24, 24), "now")
	eq(ns.DJ_LevelGroup(10, 24, 10), "now")
	eq(ns.DJ_LevelGroup(25, 45, 24), "later")
	eq(ns.DJ_LevelGroup(13, 18, 24), "past")
	eq(ns.DJ_LevelGroup(13, nil, 20), "now") -- no max: the next 8 levels count
	eq(ns.DJ_LevelGroup(13, nil, 22), "past")
	eq(ns.DJ_LevelGroup(nil, nil, 24), "later") -- no level known: at the end
end)

test("Groups: the dungeon list split by your level, each in level order", function()
	local list = {
		{ name = "A", min = 10, max = 20 }, { name = "B", min = 18, max = 30 }, { name = "C", min = 30, max = 40 },
		{ name = "D" },
	}
	local groups = ns.DJ_Groups(list, 25)
	eq(#groups, 3)
	eq(groups[1].key, "now")
	eq(groups[1].list[1].name, "B")
	eq(groups[2].key, "later")
	eq(#groups[2].list, 2)
	eq(groups[2].list[2].name, "D")
	eq(groups[3].key, "past")
	eq(groups[3].list[1].name, "A")
	eq(#ns.DJ_Groups({ list[3] }, 25), 1) -- empty groups left out
end)

test("QuestFits: side and class", function()
	eq(ns.DJ_QuestFits({ side = nil }, "H", "ROGUE"), true)
	eq(ns.DJ_QuestFits({ side = "A" }, "H", "ROGUE"), false)
	eq(ns.DJ_QuestFits({ side = "A", classes = { "MAGE" } }, "A", "ROGUE"), false)
	eq(ns.DJ_QuestFits({ side = "A", classes = { "MAGE" } }, "A", "MAGE"), true)
end)

test("QuestState: done, active, other, low, open in that order", function()
	local q = INST.wings[1].quests
	eq(ns.DJ_QuestState(q[3], Ctx({ done = function(id)
		return id == 103
	end })), "done") -- the other side's, but you did it
	eq(ns.DJ_QuestState(q[2], Ctx({ active = function(id)
		return id == 102
	end })), "active")
	eq(ns.DJ_QuestState(q[3], Ctx()), "other")
	eq(ns.DJ_QuestState(INST.wings[2].quests[1], Ctx({ level = 30 })), "other") -- a mage quest for a warrior
	eq(ns.DJ_QuestState({ id = 9, lvl = 25 }, Ctx()), "low")
	eq(ns.DJ_QuestState(q[1], Ctx()), "open")
end)

test("Quests: yours by default, the rest only when asked, each in its own wing after yours", function()
	local mine = ns.DJ_Quests(INST, "A", "WARRIOR", false)
	eq(#mine, 3)
	eq(mine[1].quest.id, 101)
	eq(mine[1].wing.name, "Upper")
	eq(mine[3].quest.id, 105)
	local all = ns.DJ_Quests(INST, "A", "WARRIOR", true)
	eq(#all, 5)
	eq(all[3].quest.id, 103) -- the Horde quest stays in Upper, so its wing heading isn't drawn twice
	eq(all[4].quest.id, 105)
	eq(all[5].quest.id, 104)
	eq(#ns.DJ_Quests(INST, "H", "WARRIOR", false), 2)
end)

test("Bosses: kill order per wing, then one rares and trash entry", function()
	local list = ns.DJ_Bosses(INST)
	eq(#list, 3)
	eq(list[1].boss.name, "Mira the Bold")
	eq(list[2].boss.name, "Grimtooth")
	eq(list[2].wing.name, "Lower")
	eq(list[3].boss.name, "Rares and trash")
	eq(list[3].boss.loot[1], 1003)
	eq(list[3].boss.loot[2], 1004)
	eq(list[3].boss.extra, true)
	local bare = { wings = { { quests = {}, bosses = { { name = "X", loot = {} } }, rares = {}, trash = {} } } }
	eq(#ns.DJ_Bosses(bare), 1)
end)

test("Matches: any name in the dungeon, through nameOf for items and quests", function()
	local function nameOf(kind, id, fallback)
		if kind == "item" and id == 1005 then
			return "Grimtooth's Cleaver"
		end
		return fallback
	end
	eq(ns.DJ_Matches(INST, "", nameOf), true)
	eq(ns.DJ_Matches(INST, "kesha", nameOf), true)
	eq(ns.DJ_Matches(INST, "LOWER", nameOf), true)
	eq(ns.DJ_Matches(INST, "aldric", nameOf), true)
	eq(ns.DJ_Matches(INST, "mage lesson", nameOf), true)
	eq(ns.DJ_Matches(INST, "cleaver", nameOf), true)
	eq(ns.DJ_Matches(INST, "a.b", nameOf), false) -- plain text, not a pattern
	eq(ns.DJ_Matches(INST, "nothing here", nameOf), false)
end)

test("Hit: what a search found, so the dungeon opens on it", function()
	local function nameOf(kind, id, fallback)
		return kind == "item" and ({ [1002] = "Mira's Locket", [1004] = "Dusty Rag", [1005] = "Grimtooth's Cleaver" })[id]
			or fallback
	end
	eq(ns.DJ_Hit(INST, "", nameOf), nil)
	eq(ns.DJ_Hit(INST, "nothing here", nameOf), nil)
	eq(next(ns.DJ_Hit(INST, "kesha", nameOf)), nil) -- the dungeon's own name: just open it
	local h = ns.DJ_Hit(INST, "grimtooth", nameOf)
	eq(h.tab, "bosses")
	eq(h.boss.name, "Grimtooth")
	eq(h.item, nil)
	h = ns.DJ_Hit(INST, "locket", nameOf)
	eq(h.boss.name, "Mira the Bold")
	eq(h.item, 1002)
	h = ns.DJ_Hit(INST, "rag", nameOf)
	eq(h.extra, true)
	eq(h.item, 1004)
	h = ns.DJ_Hit(INST, "deeper", nameOf)
	eq(h.tab, "quests")
	eq(h.quest.id, 105)
end)

test("Prep: quests you can take now, by the zone they start in", function()
	local inst = { wings = { { quests = {
		{ id = 1, map = 10, x = 1, y = 1 },
		{ id = 2, map = 20, x = 1, y = 1 },
		{ id = 3, map = 10, x = 1, y = 1 },
		{ id = 4, map = 10, x = 1, y = 1, side = "H" }, -- not yours
		{ id = 5, map = 10, x = 1, y = 1, lvl = 30 }, -- too low
		{ id = 6, item = 99 }, -- starts from an item: nowhere to go
		{ id = 7, map = 20, x = 1, y = 1 }, -- already have it
	}, bosses = {}, rares = {}, trash = {} } } }
	local groups = ns.DJ_Prep(inst, Ctx({ active = function(id)
		return id == 7
	end }))
	eq(#groups, 2)
	eq(groups[1].map, 10)
	eq(#groups[1].list, 2)
	eq(groups[1].list[2].id, 3)
	eq(groups[2].map, 20)
	eq(#groups[2].list, 1)
end)

test("FindByZone: the dungeon you're in, by its area's name or its own", function()
	local list = { { name = "A", area = 1 }, { name = "Kesha's Vault", area = 2 }, { name = "C" } }
	local function areaName(id)
		return ({ [1] = "Cave", [2] = "Valv" })[id]
	end
	eq(ns.DJ_FindByZone(list, "Valv", areaName).name, "Kesha's Vault")
	eq(ns.DJ_FindByZone(list, "C", areaName).name, "C")
	eq(ns.DJ_FindByZone(list, "Elsewhere", areaName), nil)
	eq(ns.DJ_FindByZone(list, nil, areaName), nil)
end)

test("Loot: every item the dungeon drops, once", function()
	local loot = ns.DJ_Loot(INST)
	eq(#loot, 5)
	eq(loot[1], 1001)
	eq(loot[5], 1004)
end)

test("The generated data loads and has the shape the page reads", function()
	local reg = {}
	local data = { CONTENT_FOREVER = "forever", Content_Register = function(_, key, value)
		reg[key] = value
	end }
	assert(loadfile("Tomte/Data/Forever/DungeonJournal.lua"))("Tomte", data)
	local list = reg.dungeonJournal
	assert(#list > 20, "fewer dungeons than expected")
	for _, inst in ipairs(list) do
		assert(type(inst.id) == "number" and type(inst.name) == "string" and #inst.wings > 0, inst.name)
		for _, w in ipairs(inst.wings) do
			assert(w.quests and w.bosses and w.rares and w.trash, inst.name)
		end
	end
end)

H.done()
