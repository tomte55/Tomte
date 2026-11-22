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
	if input.known == nil then
		input.known = true
	end
	return ns.Materials_Lines(input)
end

-- The roles of a line's parts, separators left out: "accent textFaint".
local function Roles(line)
	local roles = {}
	for _, part in ipairs(line.parts) do
		if part.text ~= ", " and part.text ~= "Used in: " then
			roles[#roles + 1] = part.role
		end
	end
	return table.concat(roles, " ")
end

test("one character, one profession", function()
	local lines = Lines({ usedBy = { Entry("Aldric", ALCH, "A", "B", "C") }, uses = { [ALCH] = 22 } })
	eq(#lines, 1)
	eq(lines[1].text, "Used in: Alchemy (Aldric)")
	eq(Roles(lines[1]), "accent")
end)

test("one character, two professions: most recipes first", function()
	local lines = Lines({ usedBy = { Entry("Aldric", LW, "C"), Entry("Aldric", ALCH, "A", "B") } })
	eq(lines[1].text, "Used in: Alchemy (Aldric), Leatherworking (Aldric)")
end)

test("several characters in one profession: two names and +n, most recipes first", function()
	local lines = Lines({ usedBy = {
		Entry("Mira", ALCH, "A"),
		Entry("Aldric", ALCH, "A", "B"),
		Entry("Bob", ALCH, "A"),
	} })
	eq(lines[1].text, "Used in: Alchemy (Aldric, Bob +1)", "Bob and Mira tie, so by name")
end)

test("yours first with who has them, then the others by name, one list", function()
	-- Linen Cloth on Forever: Tailoring used to vanish from both the "Used by" and the "Also" line.
	local lines = Lines({ usedBy = { Entry("Aldric", LW, "A", "B"), Entry("Mira", ALCH, "C") },
		uses = { [LW] = 6, [ALCH] = 2, [BS] = 3, [INSC] = 1 } })
	eq(#lines, 1)
	eq(lines[1].text, "Used in: Leatherworking (Aldric), Alchemy (Mira), Blacksmithing, Inscription")
	eq(Roles(lines[1]), "accent accent textFaint textFaint")
end)

test("no character uses it: the table's professions", function()
	local lines = Lines({ uses = { [LW] = 1, [ALCH] = 22 } })
	eq(#lines, 1)
	eq(lines[1].text, "Used in: Alchemy, Leatherworking")
	eq(Roles(lines[1]), "textFaint textFaint")
end)

test("skips a profession the client has no name for", function()
	local lines = Lines({ uses = { [LW] = 1, [999] = 3 } })
	eq(lines[1].text, "Used in: Leatherworking")
	eq(#Lines({ uses = { [999] = 3 } }), 0, "nothing to show, and not 'not used' either")
end)

test("Shift: recipe counts, the table's where it has one, then one line per recipe", function()
	local lines = Lines({ usedBy = { Entry("Aldric", BS, "Sturdy Ingot"), Entry("Mira", BS, "Sturdy Ingot"),
		Entry("Mira", ALCH, "Oil") }, uses = { [BS] = 4, [LW] = 1, [INSC] = 4 }, shift = true })
	eq(lines[1].text, "Used in: Blacksmithing (4), Alchemy (1), Inscription (4), Leatherworking (1)")
	eq(lines[2].text, "  Sturdy Ingot - Aldric, Mira", "a recipe two characters know is one line")
	eq(lines[2].role, "textMuted")
	eq(lines[3].text, "  Oil - Mira")
	eq(#lines, 3)
end)

test("Shift: at most 5 recipes, then +n more", function()
	local lines = Lines({ usedBy = { Entry("Aldric", ALCH, "A", "B", "C", "D", "E", "F", "G") }, shift = true })
	eq(#lines, 7, "Used in, 5 recipes, +n more")
	eq(lines[1].text, "Used in: Alchemy (7)")
	eq(lines[2].text, "  A - Aldric")
	eq(lines[6].text, "  E - Aldric")
	eq(lines[7].text, "  +2 more")
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
	local lines = Lines({ usedBy = { Entry("Aldric", BS, "A") }, isMaterial = true })
	eq(#lines, 1)
	eq(lines[1].text, "Used in: Blacksmithing (Aldric)")
end)

test("Known: only items no newer than the table's build", function()
	eq(ns.Materials_Known(210796, 275385), true, "older item")
	eq(ns.Materials_Known(275385, 275385), true, "the newest one")
	eq(ns.Materials_Known(280001, 275385), false, "newer than the table")
	eq(ns.Materials_Known(210796, nil), false, "a table without the build mark knows nothing")
	eq(ns.Materials_Known(nil, 275385), false, "no item")
end)

test("not used in crafting: never for an item the table can't know", function()
	eq(#Lines({ isMaterial = true, known = false }), 0, "newer than the table")
	local lines = Lines({ isMaterial = false, known = true })
	eq(#lines, 0, "a keystone isn't a material")
	lines = Lines({ uses = { [LW] = 1 }, isMaterial = true, known = false })
	eq(lines[1].text, "Used in: Leatherworking", "what the table does say still shows")
end)

H.done()
