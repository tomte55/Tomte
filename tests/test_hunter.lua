-- Run from the AddOns folder: lua Tomte/tests/test_hunter.lua
local ns = {}
assert(loadfile("Tomte/Modules/Hunter/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function pet(n, name, family, extra)
	local p = { petNumber = n, name = name, family = family }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local RULES = {
	noPet = true, marksman = false, passive = true, growl = true,
	specs = { dungeon = "Ferocity", raid = "any", delve = "any" },
}

test("NpcID reads creature and vehicle GUIDs only", function()
	eq(ns.Hunter_NpcID("Creature-0-3767-0-11-12345-0000ABCDEF"), 12345)
	eq(ns.Hunter_NpcID("Vehicle-0-3767-0-11-777-0000ABCDEF"), 777)
	eq(ns.Hunter_NpcID("Pet-0-3767-0-11-12345-0100ABCDEF"), nil)
	eq(ns.Hunter_NpcID("Player-1234-0ABCDEF0"), nil)
	eq(ns.Hunter_NpcID(nil), nil)
end)

test("IsPetFamily leaves out demons and ghouls", function()
	eq(ns.Hunter_IsPetFamily("Wolf"), true)
	eq(ns.Hunter_IsPetFamily("Felguard"), false)
	eq(ns.Hunter_IsPetFamily("Ghoul"), false)
	eq(ns.Hunter_IsPetFamily(nil), false)
	eq(ns.Hunter_IsPetFamily(""), false)
	eq(ns.Hunter_IsPetFamily("Wichtel", 23), false, "Imp by ID on a German client")
	eq(ns.Hunter_IsPetFamily("Ghul", 40), false, "Ghoul by ID")
	eq(ns.Hunter_IsPetFamily("Wolf", 1), true)
	eq(ns.Hunter_IsPetFamily("Felguard", 1), true, "the ID wins over the name")
	eq(ns.Hunter_IsPetFamily(nil, 1), false)
end)

test("SlimPet keeps the first spec ability", function()
	local slim = ns.Hunter_SlimPet({ name = "Fluffy", familyName = "Wolf", specialization = "Ferocity",
		specAbilities = { 264667, 1 }, petNumber = 3, slotID = 1, isExotic = false, uiModelSceneID = 718 })
	eq(slim.family, "Wolf")
	eq(slim.uiModelSceneID, 718)
	eq(slim.specAbility, 264667)
	eq(slim.exotic, nil)
end)

test("NewPets finds pet numbers that weren't there before", function()
	local old = { active = { [1] = pet(1, "A", "Wolf") }, stabled = { pet(2, "B", "Cat") } }
	local new = { active = { [1] = pet(1, "A", "Wolf"), [2] = pet(3, "C", "Bat") }, stabled = { pet(2, "B", "Cat") } }
	local found = ns.Hunter_NewPets(old, new)
	eq(#found, 1)
	eq(found[1].name, "C")
end)

test("NewPets: moving a pet between slots is not a tame", function()
	local old = { active = { [1] = pet(1, "A", "Wolf") }, stabled = {} }
	local new = { active = {}, stabled = { pet(1, "A", "Wolf") } }
	eq(#ns.Hunter_NewPets(old, new), 0)
end)

test("NewPets: nothing on the first read", function()
	eq(#ns.Hunter_NewPets(nil, { active = { [1] = pet(1, "A", "Wolf") } }), 0)
end)

test("MergeSnapshot keeps the cached stabled list when the read lacks it", function()
	local old = { active = { [1] = pet(1, "A", "Wolf") }, stabled = { pet(2, "B", "Cat") }, stabledRead = true }
	local new = { active = { [1] = pet(1, "A", "Wolf") }, stabled = {} }
	eq(#ns.Hunter_MergeSnapshot(old, new), 0)
	eq(new.stabled[1].name, "B")
	eq(new.stabledRead, nil)
end)

test("MergeSnapshot: the first full read after partial ones is not a tame", function()
	local old = { active = { [1] = pet(1, "A", "Wolf") }, stabled = {} }
	local new = { active = { [1] = pet(1, "A", "Wolf") }, stabled = { pet(2, "B", "Cat") } }
	eq(#ns.Hunter_MergeSnapshot(old, new), 0)
	eq(new.stabledRead, true)
end)

test("MergeSnapshot finds a tame in the active slots and in a re-read stable", function()
	local old = { active = { [1] = pet(1, "A", "Wolf") }, stabled = { pet(2, "B", "Cat") }, stabledRead = true }
	local new = { active = { [1] = pet(1, "A", "Wolf"), [2] = pet(9, "N", "Bat") }, stabled = { pet(2, "B", "Cat"), pet(10, "M", "Crab") } }
	local found = ns.Hunter_MergeSnapshot(old, new)
	eq(#found, 2)
end)

test("MergeSnapshot ignores a burst of new pets", function()
	local old = { active = {}, stabled = {} }
	local new = { active = { [1] = pet(1, "A", "Wolf"), [2] = pet(2, "B", "Wolf"), [3] = pet(3, "C", "Wolf") }, stabled = {} }
	eq(#ns.Hunter_MergeSnapshot(old, new), 0)
	eq(#ns.Hunter_MergeSnapshot(nil, new), 0)
end)

test("MergeSnapshot: a pet missing from one partial read is not new when it comes back", function()
	local first = { active = { [1] = pet(1, "A", "Wolf"), [2] = pet(2, "B", "Cat") }, stabled = {} }
	ns.Hunter_MergeSnapshot(nil, first)
	local partial = { active = { [1] = pet(1, "A", "Wolf") }, stabled = {} }
	eq(#ns.Hunter_MergeSnapshot(first, partial), 0)
	local full = { active = { [1] = pet(1, "A", "Wolf"), [2] = pet(2, "B", "Cat") }, stabled = {} }
	eq(#ns.Hunter_MergeSnapshot(partial, full), 0)
	eq(full.known[2], true)
end)

test("MergeSnapshot: no tames while settling, but the pets are remembered", function()
	local old = { active = { [1] = pet(1, "A", "Wolf") }, stabled = {} }
	local new = { active = { [1] = pet(1, "A", "Wolf"), [2] = pet(5, "N", "Bat") }, stabled = {} }
	eq(#ns.Hunter_MergeSnapshot(old, new, true), 0)
	eq(new.known[5], true)
end)

test("Ownership counts the family and matches the creature", function()
	local snap = { active = { [1] = pet(1, "A", "Wolf", { creatureID = 50 }) }, stabled = { pet(2, "B", "Wolf", { creatureID = 60 }), pet(3, "C", "Cat") } }
	local count, same = ns.Hunter_Ownership(snap, "Wolf", 60)
	eq(count, 2)
	eq(same.name, "B")
	count, same = ns.Hunter_Ownership(snap, "Bat", 99)
	eq(count, 0)
	eq(same, nil)
end)

test("TameNote: new family only once the stabled list was read", function()
	local wolf = pet(1, "Kesha", "Wolf", { creatureID = 50 })
	local activeOnly = { active = { [1] = wolf }, stabled = {} }
	local full = { active = { [1] = wolf }, stabled = { pet(2, "Mira", "Cat") }, stabledRead = true }
	eq(ns.Hunter_TameNote(nil, 0, nil), "unread")
	eq(ns.Hunter_TameNote(activeOnly, 0, nil), "notActive")
	eq(ns.Hunter_TameNote(full, 0, nil), "new")
	eq(ns.Hunter_TameNote(activeOnly, 1, nil), "owned")
	eq(ns.Hunter_TameNote(full, 1, wolf), "same")
	local cached = { active = { [1] = wolf }, stabled = { pet(2, "Mira", "Cat") } } -- stabled kept from an older read
	eq(ns.Hunter_TameNote(cached, 0, nil), "new")
end)

test("FindPet finds a pet by number in a newer snapshot", function()
	local snap = { active = { [1] = pet(1, "A", "Wolf") }, stabled = { pet(2, "B", "Cat") } }
	eq(ns.Hunter_FindPet(snap, 2).name, "B")
	eq(ns.Hunter_FindPet(snap, 1).name, "A")
	eq(ns.Hunter_FindPet(snap, 9), nil)
	eq(ns.Hunter_FindPet(snap, nil), nil)
	eq(ns.Hunter_FindPet(nil, 1), nil)
end)

test("SameEntry matches by table, pet number or npcID", function()
	local old, new = pet(4, "Old", "Wolf"), pet(4, "Renamed", "Wolf")
	eq(ns.Hunter_SameEntry(old, new), true)
	eq(ns.Hunter_SameEntry(old, pet(5, "X", "Wolf")), false)
	eq(ns.Hunter_SameEntry({ npcID = 7 }, { npcID = 7 }), true)
	eq(ns.Hunter_SameEntry({ npcID = 7 }, { npcID = 8 }), false)
	eq(ns.Hunter_SameEntry({ name = "a" }, { name = "a" }), false)
	eq(ns.Hunter_SameEntry(nil, old), false)
	eq(ns.Hunter_SameEntry(old, old), true)
end)

test("RecordSeen keeps one entry per creature", function()
	local seen = {}
	eq(ns.Hunter_RecordSeen(seen, "Wolf", 50, "Timber Wolf", "Elwynn", 1), true)
	eq(ns.Hunter_RecordSeen(seen, "Wolf", 50, "Timber Wolf", "Elwynn", 2), false)
	eq(ns.Hunter_RecordSeen(seen, "Wolf", nil, "Rabid Wolf", "Duskwood", 3), true)
	eq(seen.Wolf.creatures[50].at, 1)
end)

test("StableSummary splits owned and seen-only families, sorted", function()
	local snap = { active = { [1] = pet(1, "Zed", "Wolf") }, stabled = { pet(2, "Amy", "Wolf"), pet(3, "Kit", "Cat") } }
	local seen = {}
	ns.Hunter_RecordSeen(seen, "Wolf", 1, "Timber Wolf", "Elwynn", 1)
	ns.Hunter_RecordSeen(seen, "Bat", 2, "Vampire Bat", "Duskwood", 1)
	local s = ns.Hunter_StableSummary(snap, seen)
	eq(s.pets, 3)
	eq(#s.owned, 2)
	eq(s.owned[1].name, "Cat")
	eq(s.owned[2].pets[1].name, "Amy")
	eq(#s.seenOnly, 1)
	eq(s.seenOnly[1].name, "Bat")
	eq(s.seenOnly[1].creatures[1].zone, "Duskwood")
	eq(s.seenOnly[1].creatures[1].npcID, 2)
	eq(s.seenOnly[1].creatures[1].family, "Bat")
end)

test("StableSummary: name-keyed creature has no npcID", function()
	local seen = {}
	ns.Hunter_RecordSeen(seen, "Bat", nil, "Old Bat", "Duskwood", 1)
	local s = ns.Hunter_StableSummary(nil, seen)
	eq(s.seenOnly[1].creatures[1].npcID, nil)
	eq(s.seenOnly[1].creatures[1].name, "Old Bat")
end)

test("Problems: no pet only for specs that want one", function()
	eq(ns.Hunter_Problems({ specID = 253, hasPet = false }, RULES)[1], "No pet out")
	eq(#ns.Hunter_Problems({ specID = 254, hasPet = false }, RULES), 0)
	local mm = { noPet = true, marksman = true, specs = {} }
	eq(#ns.Hunter_Problems({ specID = 254, hasPet = false }, mm), 1)
end)

test("Problems: dead pet", function()
	eq(ns.Hunter_Problems({ specID = 253, hasPet = true, petDead = true }, RULES)[1], "Your pet is dead")
	eq(ns.Hunter_Problems({ specID = 253, hasPet = false, petDead = true }, RULES)[1], "Your pet is dead")
end)

test("Problems: wrong spec for the content", function()
	local p = ns.Hunter_Problems({ specID = 253, hasPet = true, petSpec = "Tenacity", content = "dungeon" }, RULES)
	eq(p[1], "Tenacity pet in a dungeon (you wanted Ferocity)")
	eq(#ns.Hunter_Problems({ specID = 253, hasPet = true, petSpec = "Ferocity", content = "dungeon" }, RULES), 0)
	eq(#ns.Hunter_Problems({ specID = 253, hasPet = true, petSpec = "Tenacity", content = "raid" }, RULES), 0)
	eq(#ns.Hunter_Problems({ specID = 253, hasPet = true, petSpec = "Tenacity" }, RULES), 0)
end)

test("Problems: passive and growl", function()
	local p = ns.Hunter_Problems({ specID = 253, hasPet = true, passive = true, growl = true, inGroup = true,
		groupHasTank = true, content = "dungeon", petSpec = "Ferocity" }, RULES)
	eq(#p, 2)
	eq(p[1], "Pet is on Passive")
	eq(p[2], "Growl is on, and the group has a tank")
	eq(ns.Hunter_Problems({ specID = 253, hasPet = true, growl = false, inGroup = false, content = "delve" }, RULES)[1],
		"Growl is off (solo delve)")
	eq(#ns.Hunter_Problems({ specID = 253, hasPet = true, growl = true, inGroup = false, content = "delve" }, RULES), 0)
	eq(#ns.Hunter_Problems({ specID = 253, hasPet = true, growl = nil, inGroup = true, groupHasTank = true }, RULES), 0)
end)

test("Forever: any spec wants a pet, and an unhappy pet is a problem", function()
	eq(ns.Hunter_Problems({ specID = 1, wantsAnySpec = true, hasPet = false }, RULES)[1], "No pet out")
	eq(#ns.Hunter_Problems({ specID = 1, hasPet = false }, RULES), 0, "retail's spec IDs only")
	local rules = { noPet = true, specs = {}, happy = true }
	eq(ns.Hunter_Problems({ hasPet = true, happiness = 1 }, rules)[1], "Pet isn't happy: feed it")
	eq(ns.Hunter_Problems({ hasPet = true, happiness = 2 }, rules)[1], "Pet isn't happy: feed it")
	eq(#ns.Hunter_Problems({ hasPet = true, happiness = 3 }, rules), 0, "happy")
	eq(#ns.Hunter_Problems({ hasPet = true }, rules), 0, "no happiness on retail")
	rules.happy = false
	eq(#ns.Hunter_Problems({ hasPet = true, happiness = 1 }, rules), 0, "setting off")
end)

local HAWK, MONKEY, CHEETAH, PACK = 13165, 13163, 5118, 13159

local function cast(s)
	local id, kind = ns.Hunter_AspectToCast(s)
	return tostring(id) .. " " .. tostring(kind)
end

test("AspectToCast: the best aspect you know when none is on", function()
	local both = { [HAWK] = true, [MONKEY] = true }
	eq(cast({ known = both, on = false }), "13165 none", "Hawk first")
	eq(cast({ known = { [MONKEY] = true }, on = false }), "13163 none", "Monkey before Hawk is learned")
	eq(cast({ known = {}, on = false }), "nil nil", "none learned")
	eq(cast({ known = both, on = HAWK }), "nil nil", "an aspect is on")
	eq(cast({ known = both }), "nil nil", "buffs unreadable")
	for _, flag in ipairs({ "dead", "resting", "mounted", "taxi" }) do
		eq(cast({ known = both, on = false, [flag] = true }), "nil nil", flag)
	end
end)

test("AspectToCast: Cheetah when travelling, with the setting on", function()
	local known = { [HAWK] = true, [CHEETAH] = true }
	local s = { known = known, on = HAWK, travelling = true, travel = true }
	eq(cast(s), "5118 travel", "Hawk on, on the move")
	s.travel = false
	eq(cast(s), "nil nil", "setting off")
	s.travel, s.inInstance = true, true
	eq(cast(s), "nil nil", "not in a dungeon")
	s.inInstance, s.hostile = false, true
	eq(cast(s), "nil nil", "not with something to fight targeted")
	s.hostile, s.travelling = false, false
	eq(cast(s), "nil nil", "standing still")
	eq(cast({ known = known, on = false, travelling = true, travel = true }), "5118 travel", "none on, on the move")
	eq(cast({ known = { [HAWK] = true }, on = HAWK, travelling = true, travel = true }), "nil nil", "Cheetah unknown")
	eq(cast({ known = known, on = CHEETAH, travelling = true, travel = true }), "nil nil", "already on")
end)

test("AspectToCast: off Cheetah or Pack before and as a fight starts", function()
	local known = { [HAWK] = true, [CHEETAH] = true }
	eq(cast({ known = known, on = CHEETAH, hostile = true }), "13165 fight", "a target to fight")
	eq(cast({ known = known, on = PACK, hostile = true }), "13165 fight", "Pack too")
	eq(cast({ known = known, on = false, hostile = true }), "13165 fight", "none on, a target to fight")
	eq(cast({ known = known, on = CHEETAH }), "nil nil", "nothing targeted: keep travelling")
	eq(cast({ known = known, on = CHEETAH, combat = true }), "13165 fight", "the fight starts")
	eq(cast({ known = known, on = false, combat = true }), "13165 fight", "the fight starts with none on")
	eq(cast({ known = known, on = HAWK, combat = true }), "nil nil", "Hawk already on")
	eq(cast({ known = known, combat = true }), "nil nil", "buffs unreadable")
end)

test("AspectToCast: in a city or an inn, Cheetah for the road and never a fighting aspect", function()
	local known = { [HAWK] = true, [CHEETAH] = true }
	eq(cast({ known = known, on = HAWK, resting = true, travelling = true, travel = true }), "5118 travel", "travelling")
	eq(cast({ known = known, on = false, resting = true, travelling = true, travel = true }), "5118 travel",
		"none on, travelling")
	eq(cast({ known = known, on = false, resting = true }), "nil nil", "no 'no aspect' nag")
	eq(cast({ known = known, on = CHEETAH, resting = true, hostile = true }), "nil nil", "no swap for a target")
	eq(cast({ known = known, on = CHEETAH, resting = true, combat = true }), "nil nil", "no swap as a fight starts")
end)

test("AspectToCast: heading for a quest", function()
	local known = { [HAWK] = true, [CHEETAH] = true }
	local near = { yards = 60, fight = true }
	eq(cast({ known = known, on = CHEETAH, dest = near }), "13165 arrive", "close to a quest you fight at")
	eq(cast({ known = known, on = CHEETAH, dest = { yards = 60, fight = false } }), "nil nil", "handing it in")
	eq(cast({ known = known, on = CHEETAH, dest = { yards = 400, fight = true } }), "nil nil", "still far")
	eq(cast({ known = known, on = CHEETAH, dest = near, inInstance = true }), "nil nil", "not in a dungeon")
	eq(cast({ known = known, on = HAWK, dest = near, travelling = true, travel = true }), "nil nil",
		"no Cheetah when you're arriving")
end)

test("Travelling: a while on the move, or soon when the quest is far", function()
	eq(ns.Hunter_Travelling(nil, nil), false, "standing still")
	eq(ns.Hunter_Travelling(5, nil), false, "a short run")
	eq(ns.Hunter_Travelling(ns.HUNTER_TRAVEL_SECONDS, nil), true, "a long run")
	eq(ns.Hunter_Travelling(4, { yards = 500, fight = true }), true, "a far quest")
	eq(ns.Hunter_Travelling(4, { yards = 150, fight = true }), false, "a near quest")
end)

test("GrowlForgotten: off with the pet out, alone in the open world", function()
	eq(ns.Hunter_GrowlForgotten({ hasPet = true, growl = false }), true)
	eq(ns.Hunter_GrowlForgotten({ hasPet = true, growl = true }), false)
	eq(ns.Hunter_GrowlForgotten({ hasPet = true }), false, "no Growl on the bar")
	eq(ns.Hunter_GrowlForgotten({ hasPet = true, growl = false, inGroup = true }), false)
	eq(ns.Hunter_GrowlForgotten({ hasPet = true, growl = false, content = "dungeon" }), false)
	eq(not ns.Hunter_GrowlForgotten({ hasPet = true, growl = false, petDead = true }), true)
end)

H.done()
