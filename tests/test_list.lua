-- Run from the AddOns folder: lua Tomte/tests/test_list.lua
local ns = {}
assert(loadfile("Tomte/Modules/Alts/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Alts/ListData.lua"))("Tomte", ns)

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

local HERB, ORE, INGOT, FLASK, BAR = 100, 200, 300, 400, 500
local recipes = {
	[1] = { name = "Flask", base = 1, item = FLASK, qMin = 1, reagents = { { items = { HERB }, qty = 5 }, { items = { INGOT }, qty = 2 } } },
	[2] = { name = "Iron Ingot", base = 2, item = INGOT, qMin = 1, reagents = { { items = { ORE }, qty = 2 } } },
	[3] = { name = "Bar", base = 1, item = BAR, qMin = 1, reagents = { { items = { HERB }, qty = 10 } } },
}
local chars = {
	Main = { guid = "Main", name = "Tomte", profs = {} },
	Alch = { guid = "Alch", name = "Mira", profs = { [1] = { base = 1, known = { [1] = true, [3] = true } } } },
	Smith = { guid = "Smith", name = "Tolvan", profs = { [2] = { base = 2, known = { [2] = true } } } },
}
local producers = ns.Alts_Producers(recipes)

local function Ctx(me, places)
	return {
		me = me, chars = chars, recipes = recipes,
		pool = ns.Alts_Pool(function(itemID)
			return places[itemID] or {}
		end),
		plan = function(recipeID, crafts, count)
			return ns.Alts_Plan(recipeID, crafts, { recipes = recipes, chars = chars, producers = producers, count = count, maxDepth = 3 })
		end,
		itemName = function(id)
			return ({ [HERB] = "Herb", [ORE] = "Ore", [INGOT] = "Ingot" })[id] or tostring(id)
		end,
		recipeName = function(id)
			return recipes[id].name
		end,
		price = function()
			return 10000
		end,
		gold = function(c)
			return math.floor(c / 10000) .. "g"
		end,
	}
end

local function Find(todo, kind)
	for _, l in ipairs(todo.lines) do
		if l.kind == kind then
			return l
		end
	end
end

test("list add, remove, crafted", function()
	local list = {}
	ns.Alts_ListAdd(list, 1, 3, 0)
	ns.Alts_ListAdd(list, 1, 2, 0)
	ns.Alts_ListAdd(list, 3, 1, 0)
	eq(#list, 2)
	eq(list[1].crafts, 5)
	ns.Alts_ListCrafted(list, 3, true)
	eq(#list, 1, "auto removes at 0")
	ns.Alts_ListCrafted(list, 1, false)
	eq(list[1].crafts, 4)
	ns.Alts_ListRemove(list, 1)
	eq(#list, 0)
end)

test("gatherer: mail herbs from bags, grab from bank, others' ore, intermediate craft", function()
	local places = {
		[HERB] = { { guid = "Main", where = "bags", n = 8 }, { guid = "Main", where = "bank", n = 10 } },
		[ORE] = { { guid = "Smith", where = "bags", n = 20 } },
	}
	local todo = ns.Alts_CraftTodo({ recipeID = 1, crafts = 3 }, Ctx("Main", places))
	-- 15 herbs: 8 from my bags (mail), 7 from my bank (fetch); 6 ingots made from 12 ore by Tolvan.
	local mail = Find(todo, "mail")
	eq(mail.n, 8)
	eq(mail.to, "Alch")
	eq(mail.text, "Mail 8 Herb to Mira")
	local fetch = Find(todo, "fetch")
	eq(fetch.n, 7)
	eq(fetch.text, "Grab 7 Herb from bank", "only the step in front of you")
	local craft = Find(todo, "craft")
	assert(craft.text:find("Tolvan: craft 6 Iron Ingot first"), craft.text)
	eq(Find(todo, "missing"), nil)
	eq(todo.crafter, "Alch")
	eq(todo.lines[1].mine, true, "my lines first")
end)

test("crafter with everything in bags is ready; bank and warband lines otherwise", function()
	local places = { [HERB] = { { guid = "Alch", where = "bags", n = 10 } } }
	local todo = ns.Alts_CraftTodo({ recipeID = 3, crafts = 1 }, Ctx("Alch", places))
	eq(Find(todo, "ready").text, "Ready: craft 1 Bar")
	eq(todo.done, true)
	places = { [HERB] = { { guid = "Alch", where = "bank", n = 4 }, { where = "warband", n = 6 } } }
	todo = ns.Alts_CraftTodo({ recipeID = 3, crafts = 1 }, Ctx("Alch", places))
	eq(Find(todo, "grab").text, "Grab 4 Herb from bank")
	eq(Find(todo, "take").text, "Take 6 Herb from Warband bank")
	eq(todo.done, false)
end)

test("the crafter's own steps only show on the crafter", function()
	local places = { [HERB] = { { guid = "Alch", where = "bank", n = 4 }, { where = "warband", n = 6 } } }
	local todo = ns.Alts_CraftTodo({ recipeID = 3, crafts = 1 }, Ctx("Main", places))
	eq(Find(todo, "take"), nil, "Mira's Warband bank step")
	eq(Find(todo, "other"), nil, "Mira's own bank")
	eq(#todo.lines, 1)
	eq(Find(todo, "wait").text, "Mira crafts 1 Bar")
	eq(todo.done, false)
end)

test("missing materials with a price", function()
	local todo = ns.Alts_CraftTodo({ recipeID = 3, crafts = 1 }, Ctx("Main", { [HERB] = { { guid = "Main", where = "bags", n = 4 } } }))
	eq(Find(todo, "missing").text, "Get 6 Herb (~6g)")
	eq(Find(todo, "wait").text, "Mira crafts 1 Bar")
end)

test("two crafts don't count the same herbs", function()
	local places = { [HERB] = { { guid = "Alch", where = "bags", n = 12 } } }
	local todos = ns.Alts_ListTodo({ { recipeID = 3, crafts = 1 }, { recipeID = 3, crafts = 1 } }, Ctx("Alch", places))
	eq(todos[1].done, true)
	eq(Find(todos[2], "missing").n, 8)
end)

test("mail plan and attach plan", function()
	local places = { [HERB] = { { guid = "Main", where = "bags", n = 30 } } }
	local todo = ns.Alts_CraftTodo({ recipeID = 3, crafts = 1 }, Ctx("Main", places))
	local wants, to = ns.Alts_CraftMail(todo)
	eq(to, "Alch")
	eq(wants[1].n, 10)
	local stacks = { { bag = 0, slot = 1, itemID = HERB, count = 4 }, { bag = 0, slot = 2, itemID = HERB, count = 200 } }
	local exact = ns.Alts_AttachPlan(wants, stacks, true, 12)
	eq(#exact, 2)
	eq(exact[1].split, nil)
	eq(exact[2].split, 6)
	local whole = ns.Alts_AttachPlan(wants, stacks, false, 12)
	eq(#whole, 2)
	eq(whole[2].split, nil)
	eq(ns.Alts_MarkedItems({ todo })[HERB], 10)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
