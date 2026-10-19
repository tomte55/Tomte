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

H.done()
