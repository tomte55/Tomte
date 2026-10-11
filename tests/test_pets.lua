-- Run from the AddOns folder: lua Tomte/tests/test_pets.lua
local ns = {}
assert(loadfile("Tomte/Modules/Pets/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Pets/Strings.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Pets/Tamers.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq
local function list(t)
	local out = {}
	for i, v in ipairs(t or {}) do
		out[i] = tostring(v)
	end
	return table.concat(out, ",")
end

-- The game's type chart (attack type -> strong vs, weak vs), as GetAttackModifier gives it.
-- 1 Humanoid, 2 Dragonkin, 3 Flying, 4 Undead, 5 Critter, 6 Magic, 7 Elemental, 8 Beast, 9 Aquatic, 10 Mechanical
local STRONG = { [1] = 2, [2] = 6, [3] = 9, [4] = 1, [5] = 4, [6] = 3, [7] = 10, [8] = 5, [9] = 7, [10] = 8 }
local WEAK = { [1] = 8, [2] = 4, [3] = 2, [4] = 9, [5] = 1, [6] = 10, [7] = 5, [8] = 3, [9] = 6, [10] = 7 }
local function Modifier(atk, def)
	if STRONG[atk] == def then
		return 1.5
	elseif WEAK[atk] == def then
		return 2 / 3
	end
	return 1
end
local chart = ns.Pets_TypeChart(Modifier, 10)
local HUMANOID, DRAGON, FLYING, UNDEAD, CRITTER, MAGIC, ELEMENTAL, BEAST, AQUATIC, MECH = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

local function ab(type, extra)
	local a = { type = type, usable = true }
	for k, v in pairs(extra or {}) do
		a[k] = v
	end
	return a
end

test("type chart from the modifier", function()
	eq(chart[HUMANOID][DRAGON], 1.5)
	eq(chart[HUMANOID][BEAST] < 1, true)
	eq(chart[BEAST][BEAST], 1)
end)

test("strong attack types against a family", function()
	eq(list(ns.Pets_Strong(chart, CRITTER)), tostring(BEAST))
	eq(list(ns.Pets_Strong(chart, DRAGON)), tostring(HUMANOID))
end)

test("matchup counts strong and weak abilities", function()
	local pet = { type = MECH, abilities = { ab(BEAST), ab(MECH), ab(ELEMENTAL) } } -- vs a Critter
	local enemy = { type = CRITTER, abilities = {} }
	local score, info = ns.Pets_Matchup(chart, pet, enemy)
	eq(info.strong, 1, "strong")
	eq(info.weak, 1, "weak") -- Elemental is weak vs Critter
	eq(score, 0)
end)

test("matchup ignores abilities without strong/weak hints", function()
	local pet = { type = MECH, abilities = { ab(BEAST, { noHints = true }) } }
	local _, info = ns.Pets_Matchup(chart, pet, { type = CRITTER, abilities = {} })
	eq(info.strong, 0)
end)

test("matchup counts what the enemy's attacks do to the pet", function()
	-- Enemy attacks with Flying (strong vs Aquatic, weak vs Dragonkin) and Beast (weak vs Flying)
	local enemy = { type = BEAST, abilities = { ab(FLYING), ab(BEAST) } }
	local dragon = { type = DRAGON, abilities = {} }
	local score, info = ns.Pets_Matchup(chart, dragon, enemy)
	eq(info.resists, 1, "dragon resists flying")
	eq(info.weakTo, 0)
	eq(score, 1)
	local aquatic = { type = AQUATIC, abilities = {} }
	score, info = ns.Pets_Matchup(chart, aquatic, enemy)
	eq(info.weakTo, 1, "aquatic weak to flying")
	eq(score, -1)
end)

test("unusable abilities don't count for offense", function()
	local pet = { type = MECH, abilities = { ab(BEAST, { usable = false }) } }
	local _, info = ns.Pets_Matchup(chart, pet, { type = CRITTER, abilities = {} })
	eq(info.strong, 0)
end)

local enemyCritter = { type = CRITTER, abilities = { ab(CRITTER) } }
local function allies()
	return {
		{ type = MECH, abilities = { ab(MECH) } }, -- neutral
		{ type = BEAST, abilities = { ab(BEAST), ab(BEAST) } }, -- strong x2
		{ type = HUMANOID, abilities = { ab(BEAST) } }, -- strong x1, resists Critter attacks
	}
end

test("best pet skips dead and leveling pets", function()
	local a = allies()
	eq(ns.Pets_Best(chart, a, enemyCritter, { active = 1 }), 2) -- beast 2 and humanoid 2: the first wins
	a[2].dead = true
	eq(ns.Pets_Best(chart, a, enemyCritter, { active = 1 }), 3)
	a[2].dead = false
	eq(ns.Pets_Best(chart, a, enemyCritter, { active = 1, leveling = 2 }), 3)
end)

test("best pet keeps the active pet on a tie", function()
	local a = { { type = MECH, abilities = {} }, { type = MECH, abilities = {} } }
	eq(ns.Pets_Best(chart, a, enemyCritter, { active = 2 }), 2)
end)

test("swap advice needs a clear margin", function()
	local a = allies()
	local advice = ns.Pets_SwapAdvice(chart, a, enemyCritter, { active = 1 })
	eq(advice and advice.index, 2)
	eq(advice.info.strong, 2)
	eq(ns.Pets_SwapAdvice(chart, a, enemyCritter, { active = 3 }), nil) -- beast ties the active humanoid
end)

test("no swap advice when the active pet is best", function()
	eq(ns.Pets_SwapAdvice(chart, allies(), enemyCritter, { active = 2 }), nil)
end)

test("no swap advice when every pet is dead but the active one", function()
	local a = allies()
	a[2].dead, a[3].dead = true, true
	eq(ns.Pets_SwapAdvice(chart, a, enemyCritter, { active = 1 }), nil)
end)

test("encounters indexed by NPC", function()
	local index = ns.Pets_IndexEncounters({
		[1601] = { section = 105, npcs = { 223446 } },
		[1589] = { section = 104, npcs = { 223446, 5 } },
	})
	eq(list(index[223446]), "1589,1601")
	eq(list(index[5]), "1589")
end)

test("species signature is order-free", function()
	eq(ns.Pets_Signature({ 30, 4, 200 }), "4,30,200")
	eq(ns.Pets_Signature({ 200, 30, 4 }), "4,30,200")
	eq(ns.Pets_Signature({}), "")
end)

-- Team picking ----------------------------------------------------------------------------------------------------

local function pet(guid, species, level, rarity, health, maxHealth)
	return { guid = guid, species = species, level = level, rarity = rarity or 4, health = health or 100,
		maxHealth = maxHealth or 100, type = BEAST, abilities = { 11, 12, 13, 14, 15, 16 } }
end
local function speciesTag(species, a1, a2, a3)
	return { kind = "species", species = species, abilities = { a1 or 0, a2 or 0, a3 or 0 }, breed = 0 }
end

test("pick prefers level 25, then rarity, then health", function()
	local owned = { pet("low", 7, 20, 4), pet("common", 7, 25, 2), pet("rare", 7, 25, 4, 50, 100),
		pet("rareFull", 7, 25, 4) }
	local picks = ns.Pets_PickTeam({ pets = { speciesTag(7) } }, owned, {}, {})
	eq(picks[1].guid, "rareFull")
end)

test("pick prefers a living pet", function()
	local owned = { pet("dead", 7, 25, 4, 0), pet("alive", 7, 15, 2) }
	local picks = ns.Pets_PickTeam({ pets = { speciesTag(7) } }, owned, {}, {})
	eq(picks[1].guid, "alive")
end)

test("pick falls back to a dead pet instead of calling it missing", function()
	local owned = { pet("dead", 7, 25, 4, 0), pet("alive", 7, 25) }
	local picks, missing = ns.Pets_PickTeam({ pets = { speciesTag(7), speciesTag(7) } }, owned, {}, {})
	eq(picks[1].guid, "alive")
	eq(picks[2].guid, "dead")
	eq(picks[2].dead, true)
	eq(#missing, 0)
end)

test("missing says when you own the species but not enough of it", function()
	local _, missing = ns.Pets_PickTeam({ pets = { speciesTag(7), speciesTag(7) } }, { pet("a", 7, 25) }, {}, {})
	eq(missing[1].slot, 2)
	eq(missing[1].another, true)
	local _, none = ns.Pets_PickTeam({ pets = { speciesTag(9) } }, { pet("a", 7, 25) }, {}, {})
	eq(none[1].another, nil)
end)

test("pick takes distinct pets for a duplicate species", function()
	local owned = { pet("a", 7, 25), pet("b", 7, 25, 3) }
	local picks, missing = ns.Pets_PickTeam({ pets = { speciesTag(7), speciesTag(7) } }, owned, {}, {})
	eq(picks[1].guid, "a")
	eq(picks[2].guid, "b")
	eq(#missing, 0)
end)

test("pick reports a species you don't have enough of", function()
	local picks, missing = ns.Pets_PickTeam({ pets = { speciesTag(7), speciesTag(7), speciesTag(9) } },
		{ pet("a", 7, 25) }, {}, {})
	eq(picks[1].guid, "a")
	eq(picks[2].keep, true)
	eq(#missing, 2)
	eq(missing[1].slot, 2)
	eq(missing[2].species, 9)
end)

test("pick keeps the slotted pet on a tie", function()
	local owned = { pet("a", 7, 25), pet("b", 7, 25) }
	local picks = ns.Pets_PickTeam({ pets = { speciesTag(7) } }, owned, { [1] = "b" }, {})
	eq(picks[1].guid, "b")
end)

test("pick turns ability digits into ability IDs", function()
	local picks = ns.Pets_PickTeam({ pets = { speciesTag(7, 1, 2, 0) } }, { pet("a", 7, 25) }, {}, {})
	eq(list(picks[1].abilities), "11,15") -- tier 3 is "any": nil
	eq(picks[1].abilities[3], nil)
end)

test("leveling and ignore tags", function()
	local owned = { pet("lvl", 3, 10), pet("x", 7, 25) }
	local team = { pets = { { kind = "leveling" }, { kind = "ignore" }, speciesTag(7) } }
	local picks = ns.Pets_PickTeam(team, owned, {}, { leveling = "lvl" })
	eq(picks[1].guid, "lvl")
	eq(picks[2].keep, true)
	picks = ns.Pets_PickTeam(team, owned, {}, {})
	eq(picks[1].keep, true) -- no leveling pet set: leave the slot
end)

test("random tag takes the best pet of that family not already used", function()
	local owned = { pet("beast1", 1, 25), pet("beast2", 2, 25, 3) }
	owned[2].type = BEAST
	local mech = pet("mech", 3, 25)
	mech.type = MECH
	owned[3] = mech
	local team = { pets = { speciesTag(1), { kind = "random", type = BEAST }, { kind = "random", type = 0 } } }
	local picks = ns.Pets_PickTeam(team, owned, {}, {})
	eq(picks[1].guid, "beast1")
	eq(picks[2].guid, "beast2")
	eq(picks[3].guid, "mech")
end)

test("pick with no owned pets reports everything missing", function()
	local picks, missing = ns.Pets_PickTeam({ pets = { speciesTag(7), speciesTag(8) } }, {}, {}, {})
	eq(picks[1].keep, true)
	eq(#missing, 2)
end)

-- Readiness, leveling ---------------------------------------------------------------------------------------------

test("readiness lists empty, dead, hurt and low slots", function()
	local loadout = {
		[1] = { level = 25, health = 0, maxHealth = 100 },
		[2] = { level = 17, health = 100, maxHealth = 100 },
		[3] = nil,
	}
	local problems = ns.Pets_Readiness(loadout, {})
	local kinds = {}
	for i, p in ipairs(problems) do
		kinds[i] = p.kind .. p.slot
	end
	eq(table.concat(kinds, " "), "dead1 low2 empty3")
end)

test("readiness: hurt pets, and the leveling slot may be low", function()
	local loadout = {
		{ level = 25, health = 50, maxHealth = 100 },
		{ level = 3, health = 100, maxHealth = 100 },
		{ level = 25, health = 100, maxHealth = 100 },
	}
	local problems = ns.Pets_Readiness(loadout, { leveling = 2 })
	eq(#problems, 1)
	eq(problems[1].kind, "hurt")
	eq(#ns.Pets_Readiness(loadout, { leveling = 2, minLevel = 1 }), 1)
end)

test("readiness of an empty loadout", function()
	eq(#ns.Pets_Readiness({}, {}), 3)
end)

test("next leveling pet drops pets at 25 and pets you no longer own", function()
	local owned = { pet("a", 1, 25), pet("b", 1, 12), pet("c", 1, 3) }
	local guid, queue = ns.Pets_NextLeveling({ "gone", "a", "b", "c" }, owned)
	eq(guid, "b")
	eq(list(queue), "b,c")
	guid, queue = ns.Pets_NextLeveling({ "a" }, owned)
	eq(guid, nil)
	eq(#queue, 0)
end)

test("author from Xu-Fu notes", function()
	eq(ns.Pets_ParseAuthor("Strategy added by Someone\nTurn 1: x"), "Someone")
	eq(ns.Pets_ParseAuthor("Turn 1: x"), nil)
	eq(ns.Pets_ParseAuthor(nil), nil)
end)

test("notes cleaned of forum tags and entities", function()
	eq(ns.Pets_CleanNotes("See [url=https://x.y/z]this guide[/url] &amp; [b]go[/b]&nbsp;now"),
		"See this guide & go now")
end)

-- Rematch strings ----------------------------------------------------------------------------------------------

test("base 32", function()
	eq(ns.Pets_Base32("6Q6M"), 223446)
	eq(ns.Pets_Base32("2OQ"), 2842)
	eq(ns.Pets_Base32("0"), 0)
	eq(ns.Pets_Base32("6q6m"), 223446)
	eq(ns.Pets_Base32("W1"), nil)
	eq(ns.Pets_Base32(""), nil)
end)

test("pet tags", function()
	local t = ns.Pets_ParseTag("12102OQ")
	eq(t.kind, "species")
	eq(t.species, 2842)
	eq(list(t.abilities), "1,2,1")
	eq(t.breed, 0)
	t = ns.Pets_ParseTag("2117B5")
	eq(t.breed, 7)
	eq(t.species, 11 * 32 + 5)
	eq(ns.Pets_ParseTag("ZL").kind, "leveling")
	t = ns.Pets_ParseTag("ZR0")
	eq(t.kind, "random")
	eq(t.type, 0)
	eq(ns.Pets_ParseTag("ZR8").type, 8)
	eq(ns.Pets_ParseTag("ZI").kind, "ignore")
	eq(ns.Pets_ParseTag("ZU").kind, "ignore")
	eq(ns.Pets_ParseTag("13102OQ"), nil) -- ability digit 3
	eq(ns.Pets_ParseTag("121"), nil)
	eq(ns.Pets_ParseTag(""), nil)
end)

-- Made-up strings in Xu-Fu's export shape (literal \n in the notes, script block at the end).
local SAMPLE = [==[Pebble Trouble:6Q6M:12102OQ:12102OQ:20001DD:N:Strategy added by Tomte Tester\nTurn 1: Rock Toss\nTurn 2: Swap: bring in #2\n\n-----BEGIN PET BATTLE SCRIPT-----\nuse(Rock Toss:123) [round=1]\nchange(#2) [round=2]\nuse(#1)\n-----END PET BATTLE SCRIPT-----]==]

test("team string: name, NPC, pets", function()
	local team = ns.Pets_ParseTeam(SAMPLE)
	eq(team.name, "Pebble Trouble")
	eq(list(team.npcs), "223446")
	eq(team.pets[1].species, 2842)
	eq(team.pets[3].species, 1024 + 13 * 32 + 13)
	eq(team.prefs, nil)
end)

test("team string: notes keep colons and get real newlines", function()
	local team = ns.Pets_ParseTeam(SAMPLE)
	eq(team.notes, "Strategy added by Tomte Tester\nTurn 1: Rock Toss\nTurn 2: Swap: bring in #2")
end)

test("team string: script split off the notes", function()
	local team = ns.Pets_ParseTeam(SAMPLE)
	eq(team.script, "use(Rock Toss:123) [round=1]\nchange(#2) [round=2]\nuse(#1)")
end)

test("team string: preferences, quotes in the name, several NPCs", function()
	local team = ns.Pets_ParseTeam([==["Big" Bob:6Q6M,1:ZL:01101FS:ZR0:P:::::25::N:Just win\n]==])
	eq(team.name, '"Big" Bob')
	eq(list(team.npcs), "223446,1")
	eq(team.pets[1].kind, "leveling")
	eq(team.prefs.minLevel, 25)
	eq(team.notes, "Just win")
	eq(team.script, nil)
end)

test("team string: entities in the script are unescaped", function()
	local team = ns.Pets_ParseTeam([==[X:1:ZL:ZL:ZL:N:-----BEGIN PET BATTLE SCRIPT-----\nuse(#1) [self.hp &gt; 3 &amp; round&lt;2]\n-----END PET BATTLE SCRIPT-----]==])
	eq(team.script, "use(#1) [self.hp > 3 & round<2]")
	eq(team.notes, "")
end)

test("team string without notes", function()
	local team = ns.Pets_ParseTeam("Plain:A:ZL:ZL:ZL")
	eq(team.name, "Plain")
	eq(list(team.npcs), "10")
	eq(team.notes, "")
end)

test("team string with a trailing N: and nothing after it", function()
	eq(ns.Pets_ParseTeam("Plain:A:ZL:ZL:ZL:N:").notes, "")
end)

test("team string: a name with colons", function()
	local team = ns.Pets_ParseTeam("Fight Night: Tiny: Terror:6Q6M:ZL:ZL:ZL:N:hi")
	eq(team and team.name, "Fight Night: Tiny: Terror")
	eq(list(team.npcs), "223446")
	eq(team.notes, "hi")
end)

test("bad team strings", function()
	eq(ns.Pets_ParseTeam("hello world"), nil)
	eq(ns.Pets_ParseTeam("Name:6Q6M:XYZ:ZL:ZL"), nil)
	eq(ns.Pets_ParseTeam("Name:6Q6M:ZL:ZL"), nil) -- two pets
	eq(ns.Pets_ParseTeam(""), nil)
end)

test("import: several lines, headers skipped, junk counted", function()
	local text = "__ My Group:1:2:3 __\n" .. SAMPLE .. "\n\nnot a team\r\nPlain:A:ZL:ZL:ZL\n"
	local teams, skipped = ns.Pets_ParseImport(text)
	eq(#teams, 2)
	eq(teams[2].name, "Plain")
	eq(skipped, 1)
end)

test("breed names", function()
	eq(ns.PETS_BREEDS[4], "P/P")
	eq(ns.PETS_BREEDS[12], "H/B")
end)

-- Tamer table ---------------------------------------------------------------------------------------------------

test("tamer table: every encounter has a known section, a name and NPCs", function()
	local sections = {}
	for _, sec in ipairs(ns.PETS_SECTIONS) do
		eq(sections[sec.id], nil, "section listed twice")
		sections[sec.id] = true
		eq(type(sec.expansion), "number", "expansion")
	end
	for id, e in pairs(ns.PETS_ENCOUNTERS) do
		eq(sections[e.section], true, "section of " .. id)
		eq(type(e.name) == "string" and e.name ~= "", true, "name of " .. id)
		eq(#e.npcs > 0, true, "npcs of " .. id)
	end
end)

test("tamer table: Collector Dyna has her world quest and Family Battler pages", function()
	local index = ns.Pets_IndexEncounters(ns.PETS_ENCOUNTERS)
	eq(list(index[223446]), "1589,1601")
end)

H.done()
