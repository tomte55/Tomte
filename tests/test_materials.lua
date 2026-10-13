-- Run from the AddOns folder: lua Tomte/tests/test_materials.lua
local ns = {}
assert(loadfile("Tomte/Modules/Materials/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local BS, LW, ALCH, INSC = 164, 165, 171, 773
local NAMES = { [BS] = "Blacksmithing", [LW] = "Leatherworking", [ALCH] = "Alchemy", [INSC] = "Inscription" }
local function ProfName(line)
	return NAMES[line]
end

local function Entry(name, base, ...)
	local recipes = {}
	for i, r in ipairs({ ... }) do
		recipes[i] = { id = i + base * 100, name = r }
	end
	return { name = name, base = base, profName = NAMES[base], recipes = recipes }
end

local function Lines(input)
	input.profName = input.profName or ProfName
	input.usedBy = input.usedBy or {}
	if input.notUsed == nil then
		input.notUsed = true
	end
	return ns.Materials_Lines(input)
end

test("one character, one profession", function()
	local lines = Lines({ usedBy = { Entry("Tomten", ALCH, "A", "B", "C") }, uses = { [ALCH] = 22 } })
	eq(#lines, 1, "Alchemy is on line 1, so no Also line")
	eq(lines[1].text, "Used by Tomten: Alchemy (3)")
	eq(lines[1].role, "accent")
end)

test("one character, two professions", function()
	local lines = Lines({ usedBy = { Entry("Tomten", ALCH, "A", "B"), Entry("Tomten", LW, "C") } })
	eq(lines[1].text, "Used by Tomten: Alchemy (2), Leatherworking (1)")
end)

test("several characters: two names and +n, most recipes first", function()
	local lines = Lines({ usedBy = {
		Entry("Mira", ALCH, "A", "B", "C"),
		Entry("Tomten", BS, "D", "E"),
		Entry("Bob", LW, "F"),
		Entry("Tomten", LW, "G", "H"),
	} })
	eq(lines[1].text, "Used by Tomten, Mira +1", "Tomten has 4 recipes over two professions")
end)

test("Also: other professions, alphabetical, minus line 1's", function()
	local lines = Lines({ usedBy = { Entry("Tomten", ALCH, "A") }, uses = { [ALCH] = 22, [LW] = 1, [INSC] = 4 } })
	eq(#lines, 2)
	eq(lines[2].text, "Also: Inscription, Leatherworking")
	eq(lines[2].role, "textFaint")
end)

test("Also alone when no character uses it", function()
	local lines = Lines({ uses = { [LW] = 1, [ALCH] = 22 } })
	eq(#lines, 1)
	eq(lines[1].text, "Also: Alchemy, Leatherworking")
end)

test("Also skips a profession the client has no name for", function()
	local lines = Lines({ uses = { [LW] = 1, [999] = 3 } })
	eq(lines[1].text, "Also: Leatherworking")
	eq(#Lines({ uses = { [999] = 3 } }), 0, "nothing to show, and not 'not used' either")
end)

test("Also with Shift: recipe counts", function()
	local lines = Lines({ uses = { [LW] = 1, [INSC] = 4 }, shift = true })
	eq(lines[1].text, "Also: Inscription (4), Leatherworking (1)")
end)

test("not used in crafting: materials only, setting on", function()
	local lines = Lines({ isMaterial = true })
	eq(#lines, 1)
	eq(lines[1].text, "Not used in crafting")
	eq(lines[1].role, "textFaint")
	eq(#Lines({ isMaterial = false }), 0, "gear and the like get nothing")
	eq(#Lines({ isMaterial = true, notUsed = false }), 0, "setting off")
end)

test("used only through Alts: no 'not used' line", function()
	local lines = Lines({ usedBy = { Entry("Tomten", BS, "A") }, isMaterial = true })
	eq(#lines, 1)
	eq(lines[1].text, "Used by Tomten: Blacksmithing (1)")
end)

test("Shift: one line per recipe with who knows it", function()
	local lines = Lines({ usedBy = { Entry("Tomten", BS, "Sturdy Ingot"), Entry("Mira", BS, "Sturdy Ingot") },
		shift = true })
	eq(#lines, 2)
	eq(lines[1].text, "Used by")
	eq(lines[1].role, "accent")
	eq(lines[2].text, "  Sturdy Ingot - Tomten, Mira", "a recipe two characters know is one line")
	eq(lines[2].role, "textMuted")
end)

test("Shift: at most 5 recipes, then +n more", function()
	local lines = Lines({ usedBy = { Entry("Tomten", ALCH, "A", "B", "C", "D", "E", "F", "G") }, shift = true })
	eq(#lines, 7, "header, 5 recipes, +n more")
	eq(lines[2].text, "  A - Tomten")
	eq(lines[6].text, "  E - Tomten")
	eq(lines[7].text, "  +2 more")
end)

H.done()
