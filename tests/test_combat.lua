-- Run from the AddOns folder: lua Tomte/tests/test_combat.lua
local ns = {}
assert(loadfile("Tomte/Modules/Combat/Data.lua"))("Tomte", ns)

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

local BM, MM, SV = 253, 254, 255

local function situation(extra)
	local s = { wantsPet = true, hasPet = true, dead = false, inCombat = false }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

test("Profile exists for hunters only", function()
	eq(ns.PetBar_Profile("HUNTER").unit, "pet")
	eq(ns.PetBar_Profile("HUNTER").spells[1].id, 136)
	eq(ns.PetBar_Profile("HUNTER").spells[2].id, 109304)
	eq(ns.PetBar_Profile("WARRIOR"), nil)
	eq(ns.PetBar_Profile(nil), nil)
end)

test("WantsPet: BM and SV always, MM only with the option", function()
	local p = ns.PetBar_Profile("HUNTER")
	eq(ns.PetBar_WantsPet(p, BM, false), true)
	eq(ns.PetBar_WantsPet(p, SV, false), true)
	eq(ns.PetBar_WantsPet(p, MM, false), false)
	eq(ns.PetBar_WantsPet(p, MM, true), true)
	eq(ns.PetBar_WantsPet(p, nil, true), false)
end)

test("Visible: unlocked always shows", function()
	eq(ns.PetBar_Visible("combat", situation({ hasPet = false, wantsPet = false, unlocked = true })), true)
end)

test("Visible: never in vehicles or pet battles", function()
	eq(ns.PetBar_Visible("always", situation({ vehicle = true })), false)
	eq(ns.PetBar_Visible("always", situation({ petBattle = true })), false)
	eq(ns.PetBar_Visible("always", situation({ vehicle = true, unlocked = true })), true)
end)

test("Visible: dead pet always shows", function()
	eq(ns.PetBar_Visible("combat", situation({ dead = true })), true)
end)

test("Visible: no pet shows only in combat for specs that want one", function()
	eq(ns.PetBar_Visible("always", situation({ hasPet = false })), false)
	eq(ns.PetBar_Visible("always", situation({ hasPet = false, inCombat = true })), true)
	eq(ns.PetBar_Visible("always", situation({ hasPet = false, inCombat = true, wantsPet = false })), false)
end)

test("Visible: combat mode shows in combat or when hurt", function()
	eq(ns.PetBar_Visible("combat", situation()), false)
	eq(ns.PetBar_Visible("combat", situation({ inCombat = true })), true)
	eq(ns.PetBar_Visible("combat", situation({ hurt = true })), true)
	eq(ns.PetBar_Visible("always", situation()), true)
end)

test("Reminder: pet died", function()
	eq(ns.PetBar_Reminder("died", situation({ dead = true })), "dead")
	eq(ns.PetBar_Reminder("died", situation({ dead = true, wantsPet = false })), nil)
end)

test("Reminder: pulling without a pet", function()
	eq(ns.PetBar_Reminder("combatStart", situation({ hasPet = false })), "missing")
	eq(ns.PetBar_Reminder("combatStart", situation({ hasPet = true, dead = true })), "dead")
	eq(ns.PetBar_Reminder("combatStart", situation()), nil)
end)

test("Reminder: leaving combat with a dead pet", function()
	eq(ns.PetBar_Reminder("combatEnd", situation({ dead = true })), "dead")
	eq(ns.PetBar_Reminder("combatEnd", situation({ hasPet = false })), "missing")
	eq(ns.PetBar_Reminder("combatEnd", situation()), nil)
end)

test("Reminder: quiet while mounted, on a taxi, in a vehicle or pet battle, or dead", function()
	for _, key in ipairs({ "mounted", "onTaxi", "vehicle", "petBattle", "playerDead" }) do
		eq(ns.PetBar_Reminder("combatStart", situation({ hasPet = false, [key] = true })), nil, key)
	end
end)

test("Throttle: same reminder at most every 10 s", function()
	local last = {}
	eq(ns.PetBar_Throttle(last, "dead", 100), true)
	eq(ns.PetBar_Throttle(last, "dead", 105), false)
	eq(ns.PetBar_Throttle(last, "missing", 105), true)
	eq(ns.PetBar_Throttle(last, "dead", 110.5), true)
end)

local function increasing(points)
	for i = 2, #points do
		assert(points[i][1] > points[i - 1][1], "x not increasing at " .. i)
	end
end

test("AlphaPoints: hidden above the threshold, full at half of it", function()
	local p = ns.PetBar_AlphaPoints(0.4)
	increasing(p)
	eq(p[1][1], 0)
	eq(p[1][2], 1)
	eq(p[#p][1], 1)
	eq(p[#p][2], 0)
	local atThreshold
	for _, point in ipairs(p) do
		if point[1] == 0.4 then
			atThreshold = point[2]
		end
	end
	eq(atThreshold, 0)
end)

test("ColorPoints: sorted, from 0 to 1, red at the bottom and green at the top", function()
	for _, t in ipairs({ 0.2, 0.4, 0.7 }) do
		local p = ns.PetBar_ColorPoints(t)
		increasing(p)
		eq(p[1][1], 0)
		eq(p[#p][1], 1)
		assert(p[1][2] > p[1][3], "bottom should be red")
		assert(p[#p][3] > p[#p][2], "top should be green")
	end
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
