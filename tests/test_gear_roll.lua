-- Run from the AddOns folder: lua Tomte/tests/test_gear_roll.lua
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ns = {}
loadfile("Tomte/Modules/Gear/Rules.lua")("Tomte", ns)
loadfile("Tomte/Modules/Gear/ForeverRules.lua")("Tomte", ns)
loadfile("Tomte/Modules/Gear/RollData.lua")("Tomte", ns)

local function Info(fields)
	fields.canNeed = fields.canNeed ~= false
	fields.canGreed = fields.canGreed ~= false
	return fields
end

test("JudgeLevel: now, a few levels ahead, or out of reach", function()
	eq(ns.GearRoll_JudgeLevel(16, nil), 16)
	eq(ns.GearRoll_JudgeLevel(16, 12), 16)
	eq(ns.GearRoll_JudgeLevel(16, 17), 17)
	eq(ns.GearRoll_JudgeLevel(16, 21), 21)
	eq(ns.GearRoll_JudgeLevel(16, 22), nil)
end)

test("an upgrade is a need", function()
	local a = ns.GearRoll_Advice(Info({ gear = true, verdict = { kind = "upgrade", pct = 12, reasons = {}, warnings = 0 } }))
	eq(a.roll, "need")
	eq(a.text, "Upgrade +12.0%")
end)

test("an upgrade a few levels ahead is a need, and says the level", function()
	local a = ns.GearRoll_Advice(Info({ gear = true, ahead = 17,
		verdict = { kind = "levelUp", ilvlDiff = 4, reasons = {}, warnings = 0 } }))
	eq(a.roll, "need")
	eq(a.text, "Upgrade at level 17")
end)

test("an upgrade once you train its weapon type is a need, and says what to learn", function()
	local a = ns.GearRoll_Advice(Info({ gear = true,
		verdict = { kind = "upgrade", pct = 30, reasons = {}, warnings = 0, untrained = "Two-Handed Swords" } }))
	eq(a.roll, "need")
	eq(a.text, "Upgrade once you learn Two-Handed Swords")
	local worse = ns.GearRoll_Advice(Info({ gear = true,
		verdict = { kind = "downgrade", pct = -30, reasons = {}, warnings = 0, untrained = "Two-Handed Swords" } }))
	eq(worse.roll, "greed")
end)

test("LaterText: what a later upgrade waits for, nil when it's no upgrade", function()
	local up = { kind = "upgrade", pct = 10, reasons = {}, warnings = 0 }
	eq(ns.GearRoll_LaterText(up, 17), "Upgrade at level 17")
	up.untrained = "Two-Handed Swords"
	eq(ns.GearRoll_LaterText(up, nil), "Upgrade once you learn Two-Handed Swords")
	eq(ns.GearRoll_LaterText(up, 18), "Upgrade at level 18 once you learn Two-Handed Swords")
	eq(ns.GearRoll_LaterText({ kind = "downgrade", pct = -5, reasons = {}, warnings = 0 }, 17), nil)
	eq(ns.GearRoll_LaterText({ kind = "upgrade", pct = 10, reasons = {}, warnings = 0 }, nil), nil, "nothing to wait for")
end)

test("an upgrade with a catch is still a need, with the catch", function()
	local a = ns.GearRoll_Advice(Info({ gear = true, verdict = { kind = "upgradeBut", pct = 8, warnings = 1,
		reasons = { "Your Axes skill is behind (20/80)" } } }))
	eq(a.roll, "need")
	eq(a.reason, "Your Axes skill is behind (20/80)")
end)

test("out of reach, not for you, or no better: greed", function()
	local far = ns.GearRoll_Advice(Info({ gear = true, needsLevel = 30, sell = 50 }))
	eq(far.roll, "greed")
	eq(far.text, "Needs level 30")
	local wrong = ns.GearRoll_Advice(Info({ gear = true, verdict = { kind = "notForYou", why = "wrong main stat", reasons = {} } }))
	eq(wrong.roll, "greed")
	eq(wrong.text, "Not for you: wrong main stat")
	local worse = ns.GearRoll_Advice(Info({ gear = true, verdict = { kind = "downgrade", pct = -20, reasons = {}, warnings = 0 } }))
	eq(worse.roll, "greed")
	local same = ns.GearRoll_Advice(Info({ gear = true, verdict = { kind = "sidegrade", pct = 0, reasons = {}, warnings = 0 } }))
	eq(same.roll, "greed")
end)

test("the game saying no to need turns a need into greed", function()
	local a = ns.GearRoll_Advice(Info({ gear = true, canNeed = false,
		verdict = { kind = "upgrade", pct = 12, reasons = {}, warnings = 0 } }))
	eq(a.roll, "greed")
	eq(a.reason, "The game won't let you need it")
end)

test("recipes: one you can learn is a need, a known one greed", function()
	eq(ns.GearRoll_Advice(Info({ recipe = "learnable" })).roll, "need")
	eq(ns.GearRoll_Advice(Info({ recipe = "learnable" })).text, "A recipe you can learn")
	eq(ns.GearRoll_Advice(Info({ recipe = "known", sell = 10 })).roll, "greed")
	eq(ns.GearRoll_Advice(Info({ recipe = "known", sell = 10 })).text, "You know this recipe")
	eq(ns.GearRoll_Advice(Info({ recipe = "other", sell = 10 })).roll, "greed")
end)

test("bags: bigger than your smallest is a need", function()
	local a = ns.GearRoll_Advice(Info({ bag = { slots = 10, smallest = 6 } }))
	eq(a.roll, "need")
	eq(a.text, "A bigger bag: 10 slots, your smallest has 6")
	eq(ns.GearRoll_Advice(Info({ bag = { slots = 10, smallest = 0 } })).text, "A bag for your empty bag slot")
	eq(ns.GearRoll_Advice(Info({ bag = { slots = 6, smallest = 10 }, sell = 20 })).roll, "greed")
end)

test("the rest: greed for what sells, never pass on it", function()
	local a = ns.GearRoll_Advice(Info({ sell = 120 }))
	eq(a.roll, "greed")
	eq(a.sell, 120)
	eq(ns.GearRoll_Advice(Info({ sell = 0 })).roll, "greed")
	eq(ns.GearRoll_Advice(Info({ sell = 0, canGreed = false, canNeed = false })).roll, "pass")
end)

local ARMOR, CLOTH, PLATE = 4, 1, 4
local function HealingPlate()
	return { classID = ARMOR, subclassID = PLATE, equipLoc = "INVTYPE_CHEST", minLevel = 40,
		stats = { STA = 8, HEAL = 22, PRIMARY = { STR = 4, INT = 10 } } }
end
local WARRIOR = { class = "WARRIOR", level = 42 }

test("BuiltFor: a healing plate chest is built for the paladin healer, not the warrior", function()
	local mira = { name = "Mira", class = "PALADIN", className = "Paladin", level = 41, role = "HEALER" }
	eq(ns.GearRoll_BuiltFor(HealingPlate(), WARRIOR, { mira }), mira)
	local healerAt39 = { name = "Mira", class = "PALADIN", level = 39, role = "HEALER" }
	eq(ns.GearRoll_BuiltFor(HealingPlate(), WARRIOR, { healerAt39 }), healerAt39, "a level short is fine")
	eq(ns.GearRoll_BuiltFor(HealingPlate(), WARRIOR, { { name = "Kesha", class = "PRIEST", level = 42 } }), nil,
		"a priest can't wear plate")
	eq(ns.GearRoll_BuiltFor(HealingPlate(), WARRIOR, { { name = "Aldric", class = "WARRIOR", level = 42 } }), nil,
		"another warrior gets the same out of it")
	eq(ns.GearRoll_BuiltFor(HealingPlate(), WARRIOR, nil), nil)
end)

test("BuiltFor: the one who gets the most, and nothing for weapons or what you can't use", function()
	local robe = { classID = ARMOR, subclassID = CLOTH, equipLoc = "INVTYPE_ROBE",
		stats = { HEAL = 20, PRIMARY = { INT = 6, SPI = 6 } } }
	local mage = { class = "MAGE", level = 30 }
	local kesha = { name = "Kesha", class = "PRIEST", level = 30 }
	local druid = { name = "Aldric", class = "DRUID", level = 30, role = "HEALER" }
	eq(ns.GearRoll_BuiltFor(robe, mage, { druid, kesha }), druid, "the healer role weighs healing highest")
	eq(ns.GearRoll_BuiltFor(robe, mage, { kesha }), kesha)
	local sword = { classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", stats = { PRIMARY = { STR = 5 } } }
	eq(ns.GearRoll_BuiltFor(sword, WARRIOR, { kesha }), nil)
	eq(ns.GearRoll_BuiltFor(robe, { class = "WARRIOR", level = 30 }, { kesha }), nil, "wrong main stat for you")
end)

test("a small upgrade gives way to the party member it's built for", function()
	local mira = { name = "Mira", class = "PALADIN", className = "Paladin", role = "HEALER" }
	local small = { kind = "upgrade", pct = 0.8, reasons = {}, warnings = 0 }
	local a = ns.GearRoll_Advice(Info({ gear = true, verdict = small, builtFor = mira }))
	eq(a.roll, "greed")
	eq(a.text, "Built for Mira (healer), only +0.8% for you")
	mira.role = nil
	eq(ns.GearRoll_Advice(Info({ gear = true, verdict = small, builtFor = mira })).text,
		"Built for Mira (Paladin), only +0.8% for you")
	local big = { kind = "upgrade", pct = 6, reasons = {}, warnings = 0 }
	eq(ns.GearRoll_Advice(Info({ gear = true, verdict = big, builtFor = mira })).roll, "need", "a real upgrade is yours")
	eq(ns.GearRoll_Advice(Info({ gear = true, verdict = small })).roll, "need", "nobody it's built for")
	local empty = { kind = "empty", reasons = {}, warnings = 0 }
	eq(ns.GearRoll_Advice(Info({ gear = true, verdict = empty, builtFor = mira })).roll, "need", "an empty slot")
end)

H.done()
