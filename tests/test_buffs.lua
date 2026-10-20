-- Run from the AddOns folder: lua Tomte/tests/test_buffs.lua
local ns = {}
assert(loadfile("Tomte/Modules/Buffs/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Rules(over)
	local rules = {
		food = { on = true, where = "all" },
		flask = { on = true, where = "group" },
		rune = { on = true, where = "raid" },
		weapon = { on = true, where = "group" },
		group = { on = true, where = "all" },
	}
	for k, v in pairs(over or {}) do
		rules[k] = v
	end
	return rules
end

-- A max-level mage in a raid with nothing on and a weapon without oil.
local function Situation(over)
	local s = {
		class = "MAGE", content = "raid", readyCheck = false, atMax = true, hasData = true, aurasHidden = false,
		food = false, flask = false, rune = false,
		weapons = { { slot = 16, has = false } },
		group = { spellID = 1459, name = "Arcane Intellect", known = true, missing = { { name = "Aldric" } },
			unknown = 0 },
	}
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end

local function States(results)
	local out = {}
	for i, r in ipairs(results) do
		out[i] = r.key .. "=" .. r.state
	end
	return table.concat(out, " ")
end

test("PlaceAllows: where choices and ready checks", function()
	eq(ns.Buffs_PlaceAllows("raid", "raid"), true, "raid in raid")
	eq(ns.Buffs_PlaceAllows("raid", "dungeon"), false, "raid in dungeon")
	eq(ns.Buffs_PlaceAllows("group", "dungeon"), true, "group in dungeon")
	eq(ns.Buffs_PlaceAllows("group", "delve"), false, "group in delve")
	eq(ns.Buffs_PlaceAllows("all", "delve"), true, "all in delve")
	eq(ns.Buffs_PlaceAllows("all", nil), false, "open world")
	eq(ns.Buffs_PlaceAllows("raid", nil, true), true, "ready check in the open world runs everything")
	eq(ns.Buffs_PlaceAllows("raid", "dungeon", true), false, "ready check in a dungeon keeps the place rule")
	eq(ns.Buffs_PlaceAllows(nil, "delve"), true, "unknown choice falls back to everywhere")
end)

test("Watching: instances and ready checks only", function()
	eq(ns.Buffs_Watching("dungeon", false), true)
	eq(ns.Buffs_Watching(nil, false), false)
	eq(ns.Buffs_Watching(nil, true), true)
end)

test("everything missing in a raid", function()
	local results = ns.Buffs_Evaluate(Situation(), Rules())
	eq(States(results), "food=missing flask=missing rune=missing weapon=missing group=missing")
	eq(#ns.Buffs_Missing(results), 5)
end)

test("everything on", function()
	local s = Situation({ food = true, flask = true, rune = true, weapons = { { slot = 16, has = true } } })
	s.group.missing = {}
	eq(States(ns.Buffs_Evaluate(s, Rules())), "food=ok flask=ok rune=ok weapon=ok group=ok")
end)

test("dungeon: rune is raid-only by default", function()
	local results = ns.Buffs_Evaluate(Situation({ content = "dungeon" }), Rules())
	eq(States(results), "food=missing flask=missing rune=notHere weapon=missing group=missing")
end)

test("delve: only food and the group buff by default", function()
	local results = ns.Buffs_Evaluate(Situation({ content = "delve" }), Rules())
	eq(States(results), "food=missing flask=notHere rune=notHere weapon=notHere group=missing")
end)

test("a check turned off", function()
	local results = ns.Buffs_Evaluate(Situation(), Rules({ flask = { on = false, where = "all" } }))
	eq(results[2].state, "off")
end)

test("below max level: no consumables, the group buff still counts", function()
	local results = ns.Buffs_Evaluate(Situation({ atMax = false }), Rules())
	eq(States(results), "food=notMax flask=notMax rune=notMax weapon=notMax group=missing")
end)

test("auras hidden by the game: unknown, never missing", function()
	local s = Situation({ aurasHidden = true })
	s.food, s.flask, s.rune = nil, nil, nil
	local results = ns.Buffs_Evaluate(s, Rules())
	eq(States(results), "food=unknown flask=unknown rune=unknown weapon=missing group=unknown")
end)

test("a read that couldn't be done is unknown", function()
	local s = Situation()
	s.food = nil
	eq(ns.Buffs_Evaluate(s, Rules())[1].state, "unknown")
end)

test("no consumable list for this expansion", function()
	local results = ns.Buffs_Evaluate(Situation({ hasData = false }), Rules())
	eq(results[1].state, "noData")
	eq(results[4].state, "missing", "weapons don't need the list")
end)

test("weapons: rogues skipped, no weapon, one of two missing", function()
	eq(ns.Buffs_Evaluate(Situation({ class = "ROGUE" }), Rules())[4].state, "none", "rogue")
	eq(ns.Buffs_Evaluate(Situation({ weapons = {} }), Rules())[4].state, "none", "shield and off-hand only")
	local r = ns.Buffs_Evaluate(Situation({ weapons = { { slot = 16, has = true }, { slot = 17, has = false } } }),
		Rules())[4]
	eq(r.state, "missing")
	eq(#r.weapons, 1)
	eq(r.weapons[1].slot, 17)
end)

test("TakesWeaponEnchant: ranged weapons count, shields and fishing poles don't", function()
	eq(ns.Buffs_TakesWeaponEnchant(2, 2), true, "bow")
	eq(ns.Buffs_TakesWeaponEnchant(2, 3), true, "gun")
	eq(ns.Buffs_TakesWeaponEnchant(2, 18), true, "crossbow")
	eq(ns.Buffs_TakesWeaponEnchant(2, 10), true, "staff")
	eq(ns.Buffs_TakesWeaponEnchant(2, 20), false, "fishing pole")
	eq(ns.Buffs_TakesWeaponEnchant(2, 14), false, "miscellaneous held item")
	eq(ns.Buffs_TakesWeaponEnchant(4, 6), false, "shield")
	eq(ns.Buffs_TakesWeaponEnchant(nil, nil), false, "empty slot")
end)

test("group buff: no class buff, not known, out of range", function()
	local s = Situation({ class = "HUNTER" })
	s.group = nil
	eq(ns.Buffs_Evaluate(s, Rules())[5].state, "none", "hunter")
	s = Situation()
	s.group.known = false
	eq(ns.Buffs_Evaluate(s, Rules())[5].state, "none", "not learned")
	s = Situation()
	s.group.missing, s.group.unknown = {}, 2
	local r = ns.Buffs_Evaluate(s, Rules())[5]
	eq(r.state, "ok")
	eq(r.why, "everyone has it (2 out of range)")
end)

test("missing texts", function()
	local results = ns.Buffs_Evaluate(Situation(), Rules())
	eq(ns.Buffs_MissingText(results[1]), "No food buff")
	eq(ns.Buffs_MissingText(results[2]), "No flask")
	eq(ns.Buffs_MissingText(results[3]), "No augment rune")
	eq(ns.Buffs_MissingText(results[4]), "No weapon oil or stone")
	eq(ns.Buffs_MissingText(results[5], "Arcane Intellect"), "No Arcane Intellect: Aldric")
end)

test("NameList shortens long lists", function()
	eq(ns.Buffs_NameList({ "Aldric", "Kesha" }), "Aldric, Kesha")
	eq(ns.Buffs_NameList({ "Aldric", "Kesha", "Mira", "Tolvan", "Bryn" }), "Aldric, Kesha, Mira and 2 more")
	eq(ns.Buffs_NameList({ "Aldric", "Kesha", "Mira" }, 2), "Aldric, Kesha and 1 more")
end)

H.done()
