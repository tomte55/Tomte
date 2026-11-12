-- Run from the AddOns folder: lua Tomte/tests/test_alts_forever.lua
-- Alts' pure rules where they differ on World of Warcraft: Forever (ns.FOREVER).
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Load(forever)
	local ns = { FOREVER = forever or nil }
	assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
	assert(loadfile("Tomte/Modules/Alts/PlanData.lua"))("Tomte", ns)
	assert(loadfile("Tomte/Modules/Alts/RosterData.lua"))("Tomte", ns)
	assert(loadfile("Tomte/Modules/Alts/GearData.lua"))("Tomte", ns)
	assert(loadfile("Tomte/Modules/Alts/ListData.lua"))("Tomte", ns)
	return ns
end

local INSCRIPTION, JEWELCRAFTING, BS = 773, 755, 164

local function HasProfession(ns, base)
	for _, p in ipairs(ns.ALTS_PROFESSIONS) do
		if p[1] == base then
			return true
		end
	end
	return false
end

test("the main professions: eleven on retail, nine on Forever", function()
	local retail, forever = Load(false), Load(true)
	eq(#retail.ALTS_PROFESSIONS, 11, "retail")
	eq(#forever.ALTS_PROFESSIONS, 9, "Forever")
	eq(HasProfession(retail, INSCRIPTION), true, "retail has Inscription")
	eq(HasProfession(forever, INSCRIPTION), false, "no Inscription")
	eq(HasProfession(forever, JEWELCRAFTING), false, "no Jewelcrafting")
	eq(HasProfession(forever, BS), true, "Blacksmithing stays")
end)

test("uncovered professions on Forever don't ask for what isn't there", function()
	local ns = Load(true)
	local names = ns.Alts_Uncovered({})
	eq(#names, 9, "every one of the nine")
	for _, name in ipairs(names) do
		eq(name ~= "Inscription" and name ~= "Jewelcrafting", true, name)
	end
end)

-- A recipe item needing Blacksmithing 125, for a character with no expansion lines.
local function RecipeLines(ns, skill)
	local chars = { a = { guid = "a", name = "Aldric",
		profs = { [BS] = { name = "Blacksmithing", base = BS, skill = skill, known = {} } } } }
	return ns.Alts_RecipeItemLines(chars, {}, nil, { base = BS, level = 125 })
end

test("recipe items on Forever weigh the profession's own skill", function()
	local low = RecipeLines(Load(true), 100)
	eq(#low, 1, "one line")
	eq(low[1].text, "Aldric: Blacksmithing 100/125, not yet", "too low")
	local high = RecipeLines(Load(true), 150)
	eq(high[1].text, "Learnable by Aldric (Blacksmithing 150)", "high enough")
end)

test("recipe learners: who can learn it now or later, for Gold & value's markers", function()
	local ns = Load(true)
	local chars = { a = { guid = "a", name = "Aldric",
		profs = { [BS] = { name = "Blacksmithing", base = BS, skill = 100, known = {} } } } }
	local who = ns.Alts_RecipeLearners(chars, {}, nil, { base = BS, level = 125 })
	eq(#who.known, 0)
	eq(#who.ready, 0)
	eq(who.low[1].c.name, "Aldric")
	eq(who.low[1].skill, 100)
	eq(who.need, 125)
	eq(who.profName, "Blacksmithing")
	who = ns.Alts_RecipeLearners({}, {}, nil, { base = BS, level = 125 })
	eq(#who.ready + #who.low, 0, "nobody has the profession")
end)

test("recipe items on retail still go by the expansion line only", function()
	local lines = RecipeLines(Load(false), 100)
	eq(lines[1].text, "Learnable by Aldric (Blacksmithing)", "no line, no reading: counts as able")
end)

-- I carry the material; the crafter is on a realm mail can't reach.
local function Todo(noWarband)
	local ns = Load(true)
	local recipes = { [1] = { name = "Bar", base = BS, item = 900, reagents = { { items = { 800 }, qty = 2 } } } }
	local chars = {
		me = { guid = "me", name = "Kesha", profs = {} },
		far = { guid = "far", name = "Mira", profs = { [BS] = { base = BS, name = "Blacksmithing", known = { [1] = true } } } },
	}
	local pool = ns.Alts_Pool(function()
		return { { guid = "me", where = "bags", n = 5 } }
	end)
	return ns.Alts_CraftTodo({ recipeID = 1, crafts = 1 }, {
		me = "me", chars = chars, recipes = recipes, pool = pool,
		plan = function(id, crafts, count)
			return ns.Alts_Plan(id, crafts, { recipes = recipes, chars = chars, producers = ns.Alts_Producers(recipes),
				maxDepth = 1, count = count })
		end,
		itemName = function()
			return "Ore"
		end,
		recipeName = function()
			return "Bar"
		end,
		canMail = function(guid)
			return guid ~= "far"
		end,
		noWarband = noWarband,
	})
end

test("a crafter mail can't reach: the Warband bank line only where there is one", function()
	local line = Todo(false).lines[1]
	eq(line.kind, "deposit", "with the bank")
	eq(line.mine, true, "yours to do")
	line = Todo(true).lines[1]
	eq(line.kind, "other", "without it")
	eq(line.mine, nil, "nothing for you to do, so no bag mark")
	eq(line.text, "You have 2 Ore for Mira, but mail doesn't reach their realm", "says why")
end)

H.done()
