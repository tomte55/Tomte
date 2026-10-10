-- Run from the AddOns folder: lua Tomte/tests/test_rogue.lua
local ns = {}
assert(loadfile("Tomte/Modules/Rogue/Data.lua"))("Tomte", ns)

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

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
