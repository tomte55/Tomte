-- Run from the AddOns folder: lua Tomte/tests/test_instances.lua
local ns = {}
assert(loadfile("Tomte/Modules/Instances/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

local D = ns.INSTANCES_DIFF

local function badge(info)
	local text, role = ns.Instances_BadgeText(info)
	return text, role
end

test("BadgeText: the spec's examples", function()
	eq(badge({ instanceType = "party", difficultyID = D.dungeonHeroic, groupSize = 5, isHeroic = true }), "5 · H")
	eq(badge({ instanceType = "party", difficultyID = D.keystone, groupSize = 5, isChallengeMode = true,
		keystone = 12 }), "M+12")
	eq(badge({ instanceType = "scenario", difficultyID = 208, groupSize = 1, delveTier = 8 }), "D8")
	eq(badge({ instanceType = "raid", difficultyID = D.raidLFR, groupSize = 25, isLFR = true }), "LFR")
	eq(badge({ instanceType = "party", difficultyID = D.dungeonTimewalking, groupSize = 5 }), "TW")
	eq(badge({ instanceType = "raid", difficultyID = D.raidMythic, groupSize = 25, displayMythic = true }), "25 · M")
end)

test("BadgeText: letters and sizes", function()
	eq(badge({ instanceType = "party", difficultyID = D.dungeonNormal, groupSize = 3 }), "3 · N")
	eq(badge({ instanceType = "party", difficultyID = D.dungeonMythic, groupSize = 5, displayMythic = true }), "5 · M")
	eq(badge({ instanceType = "raid", difficultyID = D.raid25Heroic, groupSize = 12, isHeroic = true }), "12 · H")
	eq(badge({ instanceType = "raid", difficultyID = D.raidStory, groupSize = 1 }), "Story")
	eq(badge({ instanceType = "raid", difficultyID = D.raidTimewalking, groupSize = 10 }), "TW")
	eq(badge({ instanceType = "party", difficultyID = D.dungeonHeroic, groupSize = 0, isHeroic = true }), "H",
		"no size when the group size is 0")
	eq(badge({ instanceType = "scenario", difficultyID = 999, groupSize = 2, displayHeroic = true }), "2 · H",
		"an unknown difficulty takes the display flags")
	eq(badge({ instanceType = "pvp", difficultyID = 0, groupSize = 10 }), "PvP")
end)

test("BadgeText: keystone without a level, and roles", function()
	eq(badge({ instanceType = "party", difficultyID = D.keystone, groupSize = 5, isChallengeMode = true }), "M+")
	local _, role = badge({ instanceType = "party", difficultyID = D.dungeonHeroic, groupSize = 5 })
	eq(role, "info")
	_, role = badge({ instanceType = "scenario", groupSize = 1, delveTier = 3 })
	eq(role, "warning")
end)

test("BadgeText: nothing outside instances unless a world tier is up", function()
	eq(badge(nil), nil)
	eq(badge({ instanceType = "none", difficultyID = 0 }), nil)
	eq(badge({ instanceType = "none", difficultyID = 0, worldTier = "heroic" }), "H")
	eq(badge({ instanceType = "none", difficultyID = 0, worldTier = "mythic" }), "M")
end)

test("BadgeText: nothing in housing, which counts as outside", function()
	eq(badge({ instanceType = "interior", difficultyID = 1, groupSize = 1 }), nil)
	eq(badge({ instanceType = "neighborhood", difficultyID = 1, groupSize = 4 }), nil)
	eq(ns.Instances_IsOutside("interior"), true)
	eq(ns.Instances_IsOutside("neighborhood"), true)
	eq(ns.Instances_IsOutside("none"), true)
	eq(ns.Instances_IsOutside(nil), true)
	eq(ns.Instances_IsOutside("party"), false)
	eq(ns.Instances_IsOutside("scenario"), false)
end)

test("BadgeText: world tier roles", function()
	local _, role = badge({ instanceType = "none", worldTier = "heroic" })
	eq(role, "info")
	_, role = badge({ instanceType = "none", worldTier = "mythic" })
	eq(role, "accent")
end)

test("Letter", function()
	eq(ns.Instances_Letter(D.dungeonHeroic), "H")
	eq(ns.Instances_Letter(D.raidMythic), "M")
	eq(ns.Instances_Letter(D.keystone), "M+")
	eq(ns.Instances_Letter(D.raid25), "N")
	eq(ns.Instances_Letter(D.raid10Heroic), "H")
	eq(ns.Instances_Letter(D.raidLFR), "LFR")
	eq(ns.Instances_Letter(D.dungeonTimewalking), "TW")
	eq(ns.Instances_Letter(12345), nil)
end)

test("LegacyFor: size on top of Normal or Heroic, nothing while Mythic", function()
	eq(ns.Instances_LegacyFor(D.raid10, D.raidNormal), D.raid10)
	eq(ns.Instances_LegacyFor(D.raid25, D.raidNormal), D.raid25)
	eq(ns.Instances_LegacyFor(D.raid10, D.raidHeroic), D.raid10Heroic)
	eq(ns.Instances_LegacyFor(D.raid25, D.raidHeroic), D.raid25Heroic)
	eq(ns.Instances_LegacyFor(D.raid10, D.raidMythic), nil)
	eq(ns.Instances_LegacyFor(D.raid25, nil), D.raid25, "unknown raid difficulty: Normal")
end)

test("OutsideText", function()
	eq(ns.Instances_OutsideText(D.dungeonHeroic, D.raidMythic), "H / M")
	eq(ns.Instances_OutsideText(D.dungeonNormal, D.raidNormal), "N / N")
	eq(ns.Instances_OutsideText(nil, D.raidHeroic), "? / H")
end)

test("CanChoose: solo, leader, member, inside, Dungeon Finder group", function()
	eq(ns.Instances_CanChoose({}), true, "solo")
	eq(ns.Instances_CanChoose({ inGroup = true, isLeader = true }), true, "leader")
	local ok, why = ns.Instances_CanChoose({ inGroup = true, isLeader = false })
	eq(ok, false)
	eq(why, "Only the group leader can change difficulty.")
	ok, why = ns.Instances_CanChoose({ inInstance = true })
	eq(ok, false)
	eq(why, "You can't change difficulty inside an instance.")
	ok = ns.Instances_CanChoose({ inGroup = true, isLeader = true, inInstanceGroup = true })
	eq(ok, false, "a Dungeon Finder group")
end)

test("SaveFor: exact, legacy sizes folded into Normal and Heroic, unlocked ignored", function()
	local saves = {
		{ difficultyID = D.raid25, locked = true, numEncounters = 12, encounterProgress = 4 },
		{ difficultyID = D.raidMythic, locked = false, numEncounters = 8, encounterProgress = 8 },
		{ difficultyID = D.dungeonMythic, locked = true, numEncounters = 4, encounterProgress = 1 },
	}
	eq(ns.Instances_SaveFor(saves, D.raidNormal), saves[1], "25 player counts for Normal")
	eq(ns.Instances_SaveFor(saves, D.raidHeroic), nil)
	eq(ns.Instances_SaveFor(saves, D.raidMythic), nil, "an expired lockout")
	eq(ns.Instances_SaveFor(saves, D.dungeonMythic), saves[3])
	eq(ns.Instances_SaveFor(nil, D.dungeonMythic), nil)
end)

test("LockoutSummary", function()
	eq(ns.Instances_LockoutSummary(nil), "Not saved")
	eq(ns.Instances_LockoutSummary({ locked = false, numEncounters = 8, encounterProgress = 3 }), "Not saved")
	eq(ns.Instances_LockoutSummary({ locked = true, numEncounters = 8, encounterProgress = 3 }),
		"Saved: 3 of 8 bosses down")
	local text, role = ns.Instances_LockoutSummary({ locked = true, numEncounters = 8, encounterProgress = 8 })
	eq(text, "Saved: all 8 bosses down")
	eq(role, "danger")
	eq(ns.Instances_LockoutSummary({ locked = true, numEncounters = 8, encounterProgress = 2, extended = true }),
		"Saved: 2 of 8 bosses down (extended)")
	eq(ns.Instances_LockoutSummary({ locked = true, numEncounters = 0, encounterProgress = 0 }), "Saved")
	_, role = ns.Instances_LockoutSummary(nil)
	eq(role, "success", "not saved")
	_, role = ns.Instances_LockoutSummary({ locked = true, numEncounters = 8, encounterProgress = 3 })
	eq(role, "warning", "part cleared")
end)

test("LockoutShort", function()
	local text, role = ns.Instances_LockoutShort(nil)
	eq(text, "free")
	eq(role, "textMuted")
	eq(ns.Instances_LockoutShort({ locked = false, numEncounters = 8, encounterProgress = 8 }), "free", "expired")
	text, role = ns.Instances_LockoutShort({ locked = true, numEncounters = 0, encounterProgress = 0 })
	eq(text, "saved")
	eq(role, "warning")
	eq(ns.Instances_LockoutShort({ locked = true, numEncounters = 8, encounterProgress = 3 }), "3/8")
	local _, role = ns.Instances_LockoutShort({ locked = true, numEncounters = 4, encounterProgress = 4 })
	eq(role, "danger")
end)

test("Nearest: picks the closest in yards within range", function()
	local a, b = { x = 0.5, y = 0.5, name = "a" }, { x = 0.52, y = 0.5, name = "b" }
	-- A 1000 x 1000 yard map: 0.01 is 10 yards.
	local e, d = ns.Instances_Nearest({ a, b }, 0.515, 0.5, 1000, 1000, 30)
	eq(e, b)
	near(d, 5)
	e = ns.Instances_Nearest({ a, b }, 0.6, 0.6, 1000, 1000, 30)
	eq(e, nil, "out of range")
	e = ns.Instances_Nearest({ a }, nil, nil, 1000, 1000, 30)
	eq(e, nil, "no position")
	e = ns.Instances_Nearest({ a }, 0.5, 0.5, 0, 0, 30)
	eq(e, nil, "no map size")
	-- Width and height differ: the same map offset is more yards across a wide map.
	e = ns.Instances_Nearest({ a }, 0.52, 0.5, 2000, 500, 30)
	eq(e, nil, "40 yards across a wide map")
	e = ns.Instances_Nearest({ a }, 0.5, 0.52, 2000, 500, 30)
	eq(e, a, "10 yards down it")
end)

test("QueueProgress: tanks and healers weigh more", function()
	local totals = { tank = 1, healer = 1, dps = 3 }
	eq(ns.Instances_QueueProgress({ tank = 1, healer = 1, dps = 3 }, totals), 0, "nobody yet")
	eq(ns.Instances_QueueProgress({ tank = 0, healer = 0, dps = 0 }, totals), 1, "full")
	local tankFound = ns.Instances_QueueProgress({ tank = 0, healer = 1, dps = 3 }, totals)
	local dpsFound = ns.Instances_QueueProgress({ tank = 1, healer = 1, dps = 2 }, totals)
	local healerFound = ns.Instances_QueueProgress({ tank = 1, healer = 0, dps = 3 }, totals)
	assert(tankFound > healerFound and healerFound > dpsFound, "tank > healer > one dps")
	near(tankFound, 3 / 8)
	near(dpsFound, 1 / 8)
end)

test("QueueProgress: no roles or odd numbers", function()
	eq(ns.Instances_QueueProgress(nil, nil), nil)
	eq(ns.Instances_QueueProgress({ tank = 1 }, { tank = 1, healer = 1, dps = 3 }), nil, "a missing role")
	eq(ns.Instances_QueueProgress({ tank = 1, healer = 1, dps = 3 }, { tank = "1", healer = 1, dps = 3 }), nil,
		"a total that isn't a number")
	eq(ns.Instances_QueueProgress({ tank = 0, healer = 0, dps = 0 }, { tank = 0, healer = 0, dps = 0 }), nil)
	eq(ns.Instances_QueueProgress({ tank = 5, healer = 0, dps = 0 }, { tank = 1, healer = 1, dps = 3 }), 5 / 8,
		"needs above the total are capped")
end)

test("WaitText", function()
	eq(ns.Instances_WaitText(252, nil), "4:12")
	local time, diff, role = ns.Instances_WaitText(252, 342)
	eq(time, "4:12")
	eq(diff, "avg 5:42")
	eq(role, "textMuted")
	time, diff, role = ns.Instances_WaitText(600, 470)
	eq(diff, "2:10 over avg")
	eq(role, "warning")
	time, diff, role = ns.Instances_WaitText(490, 470)
	eq(diff, "avg 7:50", "less than 30 s over still shows the average")
	eq(role, "textMuted")
	eq((ns.Instances_WaitText(3725, 0)), "1:02:05")
	time, diff = ns.Instances_WaitText(30, 0)
	eq(diff, nil, "no average")
	eq((ns.Instances_WaitText(-5, nil)), "0:00")
end)

test("RoleSlots: found per role, in tank, healer, damage order", function()
	local slots = ns.Instances_RoleSlots({ tank = 1, healer = 0, dps = 1 }, { tank = 1, healer = 1, dps = 3 })
	eq(#slots, 3)
	eq(slots[1].role, "TANK")
	eq(slots[1].found, 0)
	eq(slots[2].role, "HEALER")
	eq(slots[2].found, 1)
	eq(slots[3].role, "DAMAGER")
	eq(slots[3].found, 2)
	eq(slots[3].total, 3)
	local raid = ns.Instances_RoleSlots({ tank = 0, healer = 2, dps = 9 }, { tank = 2, healer = 6, dps = 17 })
	eq(raid[3].found, 8, "raid finder")
	eq(#ns.Instances_RoleSlots({ tank = 0, healer = 0, dps = 2 }, { tank = 0, healer = 0, dps = 3 }), 1,
		"roles with no place are left out")
	eq(ns.Instances_RoleSlots({ tank = 5, healer = 0, dps = 0 }, { tank = 1, healer = 1, dps = 3 })[1].found, 0,
		"needs above the total")
	eq(ns.Instances_RoleSlots(nil, nil), nil)
	eq(ns.Instances_RoleSlots({ tank = 1 }, { tank = 1, healer = 1, dps = 3 }), nil, "a missing role")
end)

test("PickHoliday: holiday boss first, then Timewalking, lowest ID, joinable only", function()
	eq(ns.Instances_PickHoliday({}), nil)
	eq(ns.Instances_PickHoliday({ { id = 2712, joinable = true } }), nil, "a normal random dungeon")
	eq(ns.Instances_PickHoliday({
		{ id = 1146, isTimeWalker = true, joinable = true },
		{ id = 287, isHoliday = true, joinable = true },
	}), 287)
	eq(ns.Instances_PickHoliday({
		{ id = 1971, isTimeWalker = true, joinable = true },
		{ id = 1146, isTimeWalker = true, joinable = true },
	}), 1146)
	eq(ns.Instances_PickHoliday({ { id = 287, isHoliday = true, joinable = false } }), nil, "not joinable")
	eq(ns.Instances_PickHoliday({ { id = 285, joinable = true } }), 285, "a known holiday ID without the flag")
end)

H.done()
