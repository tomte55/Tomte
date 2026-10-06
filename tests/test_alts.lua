-- Run from the AddOns folder: lua Tomte/tests/test_alts.lua
local ns = {}
assert(loadfile("Tomte/Modules/Alts/Data.lua"))("Tomte", ns)

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

local BS, ALCH = 164, 171
-- Axe needs 2 Alloy + 5 Dust; Alloy (makes 1) needs 4 Ore (3 ranks) + 1 Flux; Flux (makes 2) needs 1 Herb.
local RECIPES = {
	[1] = { name = "Charged Runeaxe", base = BS, item = 1001,
		reagents = { { items = { 2001 }, qty = 2 }, { items = { 3001 }, qty = 5 } } },
	[2] = { name = "Charged Alloy", base = BS, item = 2001, qMin = 1, qMax = 1,
		reagents = { { items = { 4001, 4002, 4003 }, qty = 4 }, { items = { 5001 }, qty = 1 } } },
	[3] = { name = "Flux", base = ALCH, item = 5001, qMin = 2, qMax = 3, reagents = { { items = { 6001 }, qty = 1 } } },
	[4] = { name = "Unknown Thing", base = ALCH, item = 7001, reagents = {} },
}
local CHARS = {
	a = { guid = "a", name = "Tomten", profs = { [2872] = { name = "Blacksmithing", base = BS, known = { [1] = true, [2] = true } } } },
	b = { guid = "b", name = "Alchy", profs = { [2871] = { name = "Alchemy", base = ALCH, known = { [3] = true } } } },
	c = { guid = "c", name = "Bob", profs = { [2871] = { name = "Alchemy", base = ALCH, known = {} } } },
}

local function Ctx(have, depth)
	return {
		recipes = RECIPES, chars = CHARS, producers = ns.Alts_Producers(RECIPES), maxDepth = depth or ns.ALTS_FULL_DEPTH,
		count = function(items)
			local n = 0
			for _, id in ipairs(items) do
				n = n + (have[id] or 0)
			end
			return n
		end,
	}
end

local function Material(plan, firstItem)
	for _, m in ipairs(plan.materials) do
		if m.items[1] == firstItem then
			return m
		end
	end
end

test("crafters: who knows it, who could learn it", function()
	local known, learnable = ns.Alts_Crafters(CHARS, RECIPES[3], 3)
	eq(#known, 1, "known")
	eq(known[1].name, "Alchy", "knower")
	eq(#learnable, 1, "learnable")
	eq(learnable[1].name, "Bob", "learner")
	eq((ns.Alts_RecipeStatus(CHARS, RECIPES[4], 4)), "learnable", "status")
	eq((ns.Alts_RecipeStatus(CHARS, { base = 999 }, 99)), "none", "none")
end)

test("search: by name, known first", function()
	local list = ns.Alts_Search(RECIPES, CHARS, "", nil)
	eq(#list, 4, "all")
	eq(list[1].status, "known", "known first")
	eq(list[4].recipe.name, "Unknown Thing", "learnable last")
	eq(#ns.Alts_Search(RECIPES, CHARS, "alloy", nil), 1, "match")
	eq(#ns.Alts_Search(RECIPES, CHARS, "", 2), 2, "limit")
end)

test("plan: everything in stock is one step", function()
	local plan = ns.Alts_Plan(1, 1, Ctx({ [2001] = 2, [3001] = 9 }))
	eq(#plan.steps, 1, "steps")
	eq(plan.steps[1].crafters[1].name, "Tomten", "crafter")
	eq(plan.missing, 0, "missing")
	eq(Material(plan, 2001).need, 2, "need")
	eq(Material(plan, 2001).crafted, nil, "not crafted")
end)

test("plan: full chain crafts the missing materials first", function()
	-- 1 Alloy in stock, so 1 to craft: 4 Ore (ranks summed: 3 + 2) and 1 Flux, which needs 1 craft of 1 Herb.
	local plan = ns.Alts_Plan(1, 1, Ctx({ [2001] = 1, [3001] = 5, [4001] = 3, [4002] = 2, [6001] = 1 }))
	eq(#plan.steps, 3, "steps")
	eq(plan.steps[1].recipeID, 3, "flux first")
	eq(plan.steps[2].recipeID, 2, "then alloy")
	eq(plan.steps[3].recipeID, 1, "then the axe")
	eq(plan.steps[2].crafts, 1, "alloy crafts")
	eq(Material(plan, 2001).crafted, 2, "alloy crafted")
	eq(Material(plan, 4001).have, 5, "quality ranks summed")
	eq(plan.missing, 0, "missing")
	eq(plan.unknown, 0, "unknown")
end)

test("plan: yields round crafts up, shortages are counted", function()
	-- 2 Alloy to craft: 8 Ore (none in stock) and 2 Flux, one Flux craft (makes 2) from the 1 Herb.
	local plan = ns.Alts_Plan(1, 1, Ctx({ [2001] = 0, [3001] = 0, [6001] = 1 }))
	local flux
	for _, s in ipairs(plan.steps) do
		if s.recipeID == 3 then
			flux = s
		end
	end
	eq(flux.crafts, 1, "flux crafts for 2 alloy")
	eq(Material(plan, 4001).missing, 8, "ore missing")
	eq(Material(plan, 3001).missing, 5, "dust missing")
	eq(plan.missing, 13, "total missing")
end)

test("plan: one step stops at the first crafted material", function()
	local plan = ns.Alts_Plan(1, 1, Ctx({ [2001] = 0, [3001] = 5 }, 1))
	eq(#plan.steps, 2, "alloy + axe")
	eq(Material(plan, 5001).missing, 2, "flux not expanded")
	eq(Material(plan, 5001).crafted, nil, "flux not crafted")
end)

test("plan: shared stock is not counted twice", function()
	local recipes = {
		[1] = { name = "A", base = BS, item = 10, reagents = { { items = { 20 }, qty = 1 }, { items = { 30 }, qty = 1 } } },
		[2] = { name = "B", base = BS, item = 30, reagents = { { items = { 20 }, qty = 2 } } },
	}
	local chars = { a = { name = "X", profs = { [1] = { base = BS, known = { [1] = true, [2] = true } } } } }
	local plan = ns.Alts_Plan(1, 1, {
		recipes = recipes, chars = chars, producers = ns.Alts_Producers(recipes), maxDepth = 8,
		count = function(items)
			return items[1] == 20 and 2 or 0
		end,
	})
	local m = plan.materials[1]
	eq(m.need, 3, "need")
	eq(m.missing, 1, "only 2 in stock for 3")
end)

test("plan: a recipe that makes its own reagent does not loop", function()
	local recipes = { [1] = { name = "Loop", base = BS, item = 10, reagents = { { items = { 10 }, qty = 1 } } } }
	local chars = { a = { name = "X", profs = { [1] = { base = BS, known = { [1] = true } } } } }
	local plan = ns.Alts_Plan(1, 1, {
		recipes = recipes, chars = chars, producers = ns.Alts_Producers(recipes), maxDepth = 8,
		count = function()
			return 0
		end,
	})
	eq(plan.missing, 1, "missing")
	eq(#plan.steps, 1, "steps")
end)

test("roster: current first, then by key; gold and ago", function()
	local chars = {
		x = { name = "Zed", level = 80, money = 50000, seen = 10 },
		y = { name = "Amy", level = 70, money = 1230000000, seen = 30 },
		z = { name = "Me", level = 10 },
	}
	local list = ns.Alts_Roster(chars, "level", "z")
	eq(list[1].name, "Me", "current")
	eq(list[2].name, "Zed", "highest level")
	eq(ns.Alts_Roster(chars, "name", nil)[1].name, "Amy", "by name")
	eq(ns.Alts_Roster(chars, "gold", nil)[1].name, "Amy", "by gold")
	eq(ns.Alts_Gold(1230000000), "123,000g", "gold")
	eq(ns.Alts_Gold(ns.Alts_TotalGold(chars)), "123,005g", "total")
	eq(ns.Alts_Price(4500), "45s", "silver")
	eq(ns.Alts_Price(80), "80c", "copper")
	eq(ns.Alts_Price(123456), "12g", "gold")
	eq(ns.Alts_Ago(30), "now", "now")
	eq(ns.Alts_Ago(7200), "2 h", "hours")
	eq(ns.Alts_Ago(3 * 86400), "3 days", "days")
	eq(ns.Alts_ProfText({ name = "Blacksmithing", skill = 72, max = 100 }), "Blacksmithing 72/100", "prof")
	eq(ns.Alts_ProfText({ name = "Blacksmithing", skill = 72, max = 100 }, true), "Blac 72", "short")
end)

test("plan: leftovers of a craft serve later slots, steps in dependency order", function()
	-- T needs 3 X and 1 Y; Y needs 1 X; X (makes 2) needs 1 Ore. 4 X from 2 crafts cover all 4.
	local recipes = {
		[1] = { name = "T", base = BS, item = 10, reagents = { { items = { 20 }, qty = 3 }, { items = { 30 }, qty = 1 } } },
		[2] = { name = "Y", base = BS, item = 30, reagents = { { items = { 20 }, qty = 1 } } },
		[3] = { name = "X", base = BS, item = 20, qMin = 2, reagents = { { items = { 40 }, qty = 1 } } },
	}
	local chars = { a = { name = "X", profs = { [1] = { base = BS, known = { [1] = true, [2] = true, [3] = true } } } } }
	local plan = ns.Alts_Plan(1, 1, {
		recipes = recipes, chars = chars, producers = ns.Alts_Producers(recipes), maxDepth = 8,
		count = function()
			return 0
		end,
	})
	eq(plan.steps[1].recipeID, 3, "X first")
	eq(plan.steps[1].crafts, 2, "X crafts")
	eq(plan.steps[2].recipeID, 2, "then Y")
	eq(plan.steps[3].recipeID, 1, "then T")
	eq(plan.missing, 2, "2 ore missing")
end)

test("search filters: character, profession, known only", function()
	eq(#ns.Alts_Search(RECIPES, CHARS, { text = "", char = "a" }), 2, "Tomten's")
	eq(#ns.Alts_Search(RECIPES, CHARS, { text = "", char = "c" }), 2, "Bob can learn the alchemy ones")
	eq(#ns.Alts_Search(RECIPES, CHARS, { text = "", char = "c", learnable = false }), 0, "Bob knows none")
	eq(#ns.Alts_Search(RECIPES, CHARS, { text = "", base = ALCH }), 2, "alchemy")
	eq(#ns.Alts_Search(RECIPES, CHARS, { text = "", learnable = false }), 3, "known by someone")
end)

test("group: profession > expansion (current first, then newest) > category", function()
	local recipes = {
		[1] = { name = "Old Axe", base = BS, line = 2822, lineName = "Dragon Isles Blacksmithing", category = "Weapons" },
		[2] = { name = "New Axe", base = BS, line = 2872, lineName = "Khaz Algar Blacksmithing", category = "Weapons" },
		[3] = { name = "Old Helm", base = BS, line = 2822, lineName = "Dragon Isles Blacksmithing", category = "Armor" },
		[4] = { name = "Potion", base = ALCH, line = 2871, lineName = "Khaz Algar Alchemy" },
	}
	local chars = { a = { name = "X", profs = { [1] = { base = BS, known = { [1] = true, [2] = true, [3] = true } } } } }
	local results = ns.Alts_Search(recipes, chars, "", nil)
	local names = { [BS] = "Blacksmithing", [ALCH] = "Alchemy" }
	local opts = {
		profName = function(base) return names[base] end,
		current = function(r) return r.line == 2822 end,
		collapsed = {},
	}
	local rows = ns.Alts_Group(results, opts)
	eq(rows[1].kind, "prof", "prof first")
	eq(rows[1].text, "Alchemy", "professions by name")
	eq(rows[2].text, "Khaz Algar Alchemy", "its expansion")
	eq(rows[3].result.recipe.name, "Potion", "no lone Other header")
	local bs
	for i, row in ipairs(rows) do
		if row.text == "Blacksmithing" then
			bs = i
		end
	end
	eq(rows[bs + 1].text, "Dragon Isles Blacksmithing", "current expansion first")
	eq(rows[bs + 2].text, "Armor", "categories by name")
	eq(rows[bs + 3].result.recipe.name, "Old Helm", "recipe")
	local last = rows[#rows]
	eq(last.text, "Khaz Algar Blacksmithing", "other expansion last")
	eq(last.collapsed, true, "and folded by default")
	opts.collapsed = { ["p" .. BS] = true }
	local collapsed = ns.Alts_Group(results, opts)
	eq(#collapsed, 4, "Blacksmithing folded")
	eq(collapsed[4].collapsed, true, "marked")
	opts.expand = true
	eq(#ns.Alts_Group(results, opts), #rows + 2, "searching opens everything (the folded expansion too)")
	opts.expand, opts.collapsed = nil, { ["p" .. BS .. ":2872"] = false }
	eq(#ns.Alts_Group(results, opts), #rows + 2, "opened by hand stays open")
end)

test("line belongs to the continent", function()
	eq(ns.Alts_LineInContinent("Dragon Isles Blacksmithing", "Dragon Isles"), true, "same name")
	eq(ns.Alts_LineInContinent("Khaz Algar Blacksmithing", "Dragon Isles"), false, "other")
	eq(ns.Alts_LineInContinent("Legion Blacksmithing", "Broken Isles"), true, "alias")
	eq(ns.Alts_LineInContinent("Zandalari Blacksmithing", "Zandalar"), true, "zandalari")
	eq(ns.Alts_LineInContinent(nil, "Zandalar"), false, "no name")
end)

test("group: levels that would say nothing are left out", function()
	local recipes = {
		[1] = { name = "A", base = BS, line = 1 },
		[2] = { name = "B", base = BS, line = 2 },
	}
	local chars = { a = { name = "X", profs = { [1] = { base = BS, known = { [1] = true, [2] = true } } } } }
	local results = ns.Alts_Search(recipes, chars, "", nil)
	local opts = { profName = function() return "Blacksmithing" end, current = function() return false end, collapsed = {} }
	local rows = ns.Alts_Group(results, opts)
	eq(#rows, 3, "profession header and two recipes")
	eq(rows[2].kind, "recipe", "no expansion or Other header")
	opts.lineName = function(r) return r.line == 1 and "Old Blacksmithing" or "New Blacksmithing" end
	rows = ns.Alts_Group(results, opts)
	eq(rows[2].text, "New Blacksmithing", "names looked up, newest first")
	eq(rows[3].kind, "recipe", "still no lone Other")
end)

test("professions: main ones listed, secondary ones only in their own line", function()
	local c = { profs = { [185] = { name = "Cooking", secondary = true, skill = 52, max = 100 }, [186] = { name = "Mining" },
		[164] = { name = "Blacksmithing" }, [356] = { name = "Fishing", secondary = true, skill = 20, max = 100 } } }
	local list = ns.Alts_Profs(c)
	eq(#list, 2, "main only")
	eq(list[1].name, "Blacksmithing", "by name")
	eq(ns.Alts_SecondaryText(c), "Secondary: Cooking 52/100, Fishing 20/100", "secondary line")
	eq(ns.Alts_SecondaryText({ profs = {} }), nil, "none")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
