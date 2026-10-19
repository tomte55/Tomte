-- Run from the AddOns folder: lua Tomte/tests/test_combat.lua
local ns = {}
assert(loadfile("Tomte/Modules/Combat/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local BM, MM, SV = 253, 254, 255

local function situation(extra)
	local s = { wantsPet = true, hasPet = true, dead = false, inCombat = false }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

local AFF, DEMO, DESTRO = 265, 266, 267
local BLOOD, FROST, UNHOLY = 250, 251, 252

local function knows(ids)
	local set = {}
	for _, id in ipairs(ids) do
		set[id] = true
	end
	return function(id)
		return set[id] == true
	end
end

test("Profiles: hunters, warlocks and death knights", function()
	eq(ns.PetBar_Profile("HUNTER").unit, "pet")
	eq(ns.PetBar_Profile("HUNTER").spells[1].id, 136)
	eq(ns.PetBar_Profile("HUNTER").spells[2].id, 109304)
	eq(ns.PetBar_Profile("HUNTER").revive[1], 982)
	eq(ns.PetBar_Profile("HUNTER").call[1], 883)
	eq(ns.PetBar_Profile("WARLOCK").unit, "pet")
	eq(ns.PetBar_Profile("WARLOCK").spells[1].id, 333889)
	eq(ns.PetBar_Profile("WARLOCK").sacrifice, 196099)
	eq(ns.PetBar_Profile("DEATHKNIGHT").spells[1].id, 63560)
	eq(ns.PetBar_Profile("DEATHKNIGHT").spells[1].buff, true)
	eq(ns.PetBar_Profile("DEATHKNIGHT").revive[1], 46584)
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

test("Profiles: every spell is a number, revive and call are non-empty lists", function()
	for _, class in ipairs({ "HUNTER", "WARLOCK", "DEATHKNIGHT" }) do
		local p = ns.PetBar_Profile(class)
		for _, spell in ipairs(p.spells) do
			eq(type(spell.id), "number", class .. " spell")
		end
		assert(#p.revive > 0 and #p.call > 0, class .. " needs revive and call")
	end
end)

test("ForSpec: death knights only as Unholy, other profiles every spec", function()
	local dk = ns.PetBar_Profile("DEATHKNIGHT")
	eq(ns.PetBar_ForSpec(dk, UNHOLY), true)
	eq(ns.PetBar_ForSpec(dk, BLOOD), false)
	eq(ns.PetBar_ForSpec(dk, FROST), false)
	eq(ns.PetBar_ForSpec(dk, nil), false)
	eq(ns.PetBar_ForSpec(ns.PetBar_Profile("HUNTER"), nil), true)
	eq(ns.PetBar_ForSpec(ns.PetBar_Profile("WARLOCK"), DESTRO), true)
end)

test("WantsPet: every warlock spec, not with Grimoire of Sacrifice", function()
	local p = ns.PetBar_Profile("WARLOCK")
	for _, spec in ipairs({ AFF, DEMO, DESTRO }) do
		eq(ns.PetBar_WantsPet(p, spec, false, false), true, spec)
		eq(ns.PetBar_WantsPet(p, spec, false, true), false, spec)
	end
end)

test("WantsPet: Unholy only", function()
	local p = ns.PetBar_Profile("DEATHKNIGHT")
	eq(ns.PetBar_WantsPet(p, UNHOLY, false), true)
	eq(ns.PetBar_WantsPet(p, BLOOD, true), false)
	eq(ns.PetBar_WantsPet(p, FROST, true), false)
end)

test("SummonSpell: last summon if known, else the first known, else the first", function()
	local list = { 30146, 691, 697, 366222, 688 }
	eq(ns.PetBar_SummonSpell(list, 697, knows({ 691, 697, 688 })), 697)
	eq(ns.PetBar_SummonSpell(list, 30146, knows({ 691, 688 })), 691)
	eq(ns.PetBar_SummonSpell(list, nil, knows({ 30146, 691 })), 30146)
	eq(ns.PetBar_SummonSpell(list, 12345, knows({ 688 })), 688)
	eq(ns.PetBar_SummonSpell(list, nil, knows({})), 30146)
	eq(ns.PetBar_SummonSpell({ 883 }, nil, knows({})), 883)
end)

test("IsSummon: only the profile's revive and call spells", function()
	local p = ns.PetBar_Profile("WARLOCK")
	eq(ns.PetBar_IsSummon(p, 691), true)
	eq(ns.PetBar_IsSummon(p, 333889), false)
	eq(ns.PetBar_IsSummon(ns.PetBar_Profile("HUNTER"), 982), true)
	eq(ns.PetBar_IsSummon(ns.PetBar_Profile("DEATHKNIGHT"), 46585), false)
end)

test("HasOption: only hunters have the Marksmanship option", function()
	eq(ns.PetBar_HasOption(ns.PetBar_Profile("HUNTER")), true)
	eq(ns.PetBar_HasOption(ns.PetBar_Profile("WARLOCK")), false)
	eq(ns.PetBar_HasOption(ns.PetBar_Profile("DEATHKNIGHT")), false)
end)

test("Visible: never for an off spec, unless unlocked", function()
	eq(ns.PetBar_Visible("always", situation({ offSpec = true })), false)
	eq(ns.PetBar_Visible("combat", situation({ offSpec = true, dead = true, inCombat = true })), false)
	eq(ns.PetBar_Visible("combat", situation({ offSpec = true, unlocked = true })), true)
end)

H.done()
