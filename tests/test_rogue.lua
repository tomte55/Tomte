-- Run from the AddOns folder: lua Tomte/tests/test_rogue.lua
local ns = {}
assert(loadfile("Tomte/Modules/Rogue/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local DEADLY, INSTANT, WOUND, AMPLIFYING = 2823, 315584, 8679, 381664
local CRIPPLING, ATROPHIC, NUMBING = 3408, 381637, 5761
local ASSASSINATION, OUTLAW = 259, 260
local RULES = { lethal = true, nonLethal = true, lowSeconds = 600 }

local function set(...)
	local t = {}
	for _, id in ipairs({ ... }) do
		t[id] = true
	end
	return t
end

local function ids(problems)
	local out = {}
	for i, p in ipairs(problems) do
		out[i] = p.spellID .. ":" .. p.reason
	end
	return table.concat(out, " ")
end

test("PoisonKind sorts lethal and non-lethal", function()
	eq(ns.Rogue_PoisonKind(DEADLY), "lethal")
	eq(ns.Rogue_PoisonKind(AMPLIFYING), "lethal")
	eq(ns.Rogue_PoisonKind(CRIPPLING), "nonLethal")
	eq(ns.Rogue_PoisonKind(12345), nil)
end)

test("nothing on: Assassination is offered Deadly and Crippling", function()
	local s = { known = set(DEADLY, INSTANT, CRIPPLING), active = {}, specID = ASSASSINATION }
	eq(ids(ns.Rogue_PoisonProblems(s, RULES)), DEADLY .. ":missing " .. CRIPPLING .. ":missing")
end)

test("other specs are offered Instant first", function()
	local s = { known = set(DEADLY, INSTANT, CRIPPLING), active = {}, specID = OUTLAW }
	eq(ids(ns.Rogue_PoisonProblems(s, RULES)), INSTANT .. ":missing " .. CRIPPLING .. ":missing")
end)

test("unknown poisons are never offered", function()
	local s = { known = set(INSTANT), active = {}, specID = ASSASSINATION }
	eq(ids(ns.Rogue_PoisonProblems(s, RULES)), INSTANT .. ":missing", "no Deadly, no non-lethal known")
end)

test("the poison applied last wins", function()
	local s = { known = set(DEADLY, INSTANT, WOUND, CRIPPLING, NUMBING), active = {}, specID = ASSASSINATION,
		last = { lethal = { WOUND }, nonLethal = { NUMBING } } }
	eq(ids(ns.Rogue_PoisonProblems(s, RULES)), WOUND .. ":missing " .. NUMBING .. ":missing")
end)

test("any poison of a kind fills its slot", function()
	local s = { known = set(DEADLY, INSTANT, CRIPPLING), active = { [INSTANT] = 3000, [CRIPPLING] = 3000 },
		specID = ASSASSINATION }
	eq(#ns.Rogue_PoisonProblems(s, RULES), 0)
end)

test("a poison running low is reported, and doesn't ask for a second one", function()
	local s = { known = set(DEADLY, CRIPPLING), active = { [DEADLY] = 120, [CRIPPLING] = 3000 },
		specID = ASSASSINATION }
	local problems = ns.Rogue_PoisonProblems(s, RULES)
	eq(ids(problems), DEADLY .. ":low")
	eq(problems[1].left, 120)
	eq(problems[1].kind, "lethal")
end)

test("unreadable time (math.huge) never counts as low", function()
	local s = { known = set(DEADLY, CRIPPLING), active = { [DEADLY] = math.huge, [CRIPPLING] = math.huge } }
	eq(#ns.Rogue_PoisonProblems(s, RULES), 0)
end)

test("Dragon-Tempered Blades wants two of each", function()
	local s = { known = set(DEADLY, AMPLIFYING, INSTANT, CRIPPLING, ATROPHIC), twoEach = true,
		active = { [DEADLY] = 3000, [CRIPPLING] = 3000 }, specID = ASSASSINATION,
		last = { lethal = { AMPLIFYING, DEADLY } } }
	eq(ids(ns.Rogue_PoisonProblems(s, RULES)), AMPLIFYING .. ":missing " .. ATROPHIC .. ":missing")
end)

test("a kind turned off in the rules is skipped", function()
	local s = { known = set(DEADLY, CRIPPLING), active = {}, specID = ASSASSINATION }
	local rules = { lethal = true, nonLethal = false, lowSeconds = 600 }
	eq(ids(ns.Rogue_PoisonProblems(s, rules)), DEADLY .. ":missing")
end)

test("low threshold 0 never warns", function()
	local s = { known = set(DEADLY, CRIPPLING), active = { [DEADLY] = 5, [CRIPPLING] = 5 } }
	eq(#ns.Rogue_PoisonProblems(s, { lethal = true, nonLethal = true, lowSeconds = 0 }), 0)
end)

test("RememberPoison keeps newest first, no duplicates, at most 4", function()
	local last = ns.Rogue_RememberPoison(nil, DEADLY)
	last = ns.Rogue_RememberPoison(last, INSTANT)
	last = ns.Rogue_RememberPoison(last, DEADLY)
	eq(last[1], DEADLY)
	eq(last[2], INSTANT)
	eq(#last, 2)
	for _, id in ipairs({ WOUND, AMPLIFYING, INSTANT, WOUND }) do
		last = ns.Rogue_RememberPoison(last, id)
	end
	eq(#last, 4)
	eq(last[1], WOUND)
	eq(ns.Rogue_RememberPoison(last, 999), last, "a non-poison changes nothing")
	eq(#last, 4)
end)

test("FormatLeft", function()
	eq(ns.Rogue_FormatLeft(3599), "59 min")
	eq(ns.Rogue_FormatLeft(60), "1 min")
	eq(ns.Rogue_FormatLeft(45.7), "45 sec")
	eq(ns.Rogue_FormatLeft(-3), "0 sec")
end)

local function line(text, r, g, b)
	return { text = text, r = r or 1, g = g or 1, b = b or 1 }
end

test("LockState finds the lock line near the top", function()
	local box = { line("Sturdy Lockbox"), line("Locked"), line("Use: Open the box.") }
	eq(ns.Rogue_LockState(box, "Locked"), "pickable")
	eq(ns.Rogue_LockState({ line("Sturdy Lockbox"), line("Locked", 1, 0.13, 0.13) }, "Locked"), "tooHard",
		"a red line: your skill can't open it")
	eq(ns.Rogue_LockState({ line("Sturdy Lockbox"), line("[-]Locked", 1, 0.13, 0.13) }, "Locked"), "tooHard",
		"colorblind marker")
	eq(ns.Rogue_LockState({ line("Kiste"), line("Verschlossen") }, "Verschlossen"), "pickable", "other languages")
	eq(ns.Rogue_LockState({ line("Sturdy Lockbox"), line("Use: Open the box.") }, "Locked"), nil, "opened")
	eq(ns.Rogue_LockState({ line("Locked"), line("Binds when picked up") }, "Locked"), nil, "the name line is skipped")
	eq(ns.Rogue_LockState({ line("Box"), line("Unique"), line("x"), line("y"), line("z"), line("Locked") }, "Locked"),
		nil, "too far down: a description")
	eq(ns.Rogue_LockState({ line("Box"), line("\"The chest is Locked\"") }, "Locked"), nil, "a sentence isn't the line")
	eq(ns.Rogue_LockState({ line("Box"), line("Locked") }, nil), nil, "no LOCKED text")
end)

test("Lockpick macros", function()
	eq(ns.Rogue_LockpickMacro("Pick Lock", 0, 5), "/cast [@none] Pick Lock\n/use 0 5")
	eq(ns.Rogue_LockpickTradeMacro("Skeleton Pinkie", "TradeRecipientItem7ItemButton"),
		"/cast [@none] Skeleton Pinkie\n/click TradeRecipientItem7ItemButton")
end)

-- World of Warcraft: Forever: poisons are items, one on each weapon.
local FAMILIES = {
	{ key = "instant", items = { 1, 2, 3 } },
	{ key = "deadly", items = { 11, 12 } },
}
local LOW = { lowSeconds = 600 }

test("Forever: a stone beside no poison isn't a poison, charges or an imbue are", function()
	local STONE = { hasEnchant = true, enchantType = 2, charges = 0, timeLeft = 1000000 }
	eq(ns.Rogue_ForeverPoisonLeft({}), nil, "nothing")
	eq(ns.Rogue_ForeverPoisonLeft({ STONE }), nil, "stone")
	eq(ns.Rogue_ForeverPoisonLeft({ { hasEnchant = false, charges = 5 } }), nil, "not on")
	eq(ns.Rogue_ForeverPoisonLeft({ STONE, { hasEnchant = true, enchantType = 2, charges = 60, timeLeft = 90000 } }), 90)
	eq(ns.Rogue_ForeverPoisonLeft({ { hasEnchant = true, enchantType = 3, charges = 0, timeLeft = 0 } }), math.huge)
end)

test("Forever: offers the highest rank in the bags, per weapon", function()
	local p = ns.Rogue_ForeverProblems({ known = true, families = FAMILIES, bags = { [1] = 2, [2] = 1 },
		weapons = { { slot = 16 }, { slot = 17, left = 100 }, } }, LOW)
	eq(#p, 2)
	eq(p[1].slot, 16)
	eq(p[1].reason, "missing")
	eq(p[1].itemID, 2, "rank II over rank I")
	eq(p[1].family, "instant")
	eq(p[2].reason, "low")
	eq(p[2].left, 100)
end)

test("Forever: the family last used on that weapon wins while it's in the bags", function()
	local s = { known = true, families = FAMILIES, bags = { [1] = 1, [11] = 1 }, weapons = { { slot = 17 } },
		last = { [17] = "deadly" } }
	eq(ns.Rogue_ForeverProblems(s, LOW)[1].itemID, 11)
	s.bags = { [1] = 1 }
	eq(ns.Rogue_ForeverProblems(s, LOW)[1].itemID, 1, "falls back")
end)

test("Forever: no poison in the bags: no item, still reported; nothing before the skill", function()
	local s = { known = true, families = FAMILIES, bags = {}, weapons = { { slot = 16 } } }
	local p = ns.Rogue_ForeverProblems(s, LOW)
	eq(#p, 1)
	eq(p[1].itemID, nil)
	s.known = false
	eq(#ns.Rogue_ForeverProblems(s, LOW), 0, "not learned")
	s.bags = { [1] = 1 }
	eq(#ns.Rogue_ForeverProblems(s, LOW), 1, "a poison in the bags means it's learned")
end)

test("Forever: a poison with time left is fine; low warning 0 is off", function()
	local s = { known = true, families = FAMILIES, bags = { [1] = 1 }, weapons = { { slot = 16, left = 700 } } }
	eq(#ns.Rogue_ForeverProblems(s, LOW), 0)
	s.weapons[1].left = 10
	eq(#ns.Rogue_ForeverProblems(s, { lowSeconds = 0 }), 0)
end)

test("Forever: remembers per weapon and builds the macro", function()
	local last = { lethal = {} }
	ns.Rogue_ForeverRemember(last, 16, "deadly")
	eq(last.forever[16], "deadly")
	eq(ns.Rogue_ForeverMacro(8928, 17), "/use item:8928\n/use 17")
end)

test("Forever: weapons only take poison", function()
	eq(ns.Rogue_TakesPoison(2, 7), true, "sword")
	eq(ns.Rogue_TakesPoison(2, 20), false, "fishing pole")
	eq(ns.Rogue_TakesPoison(4, 6), false, "shield")
end)

H.done()
