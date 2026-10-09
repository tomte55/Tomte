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

test("shopping list: full chain only what's missing, one step the recipe's own materials", function()
	-- Full chain: Alloy is crafted, Flux crafted from Herb; nothing of anything on hand.
	local full = ns.Alts_Plan(1, 1, Ctx({}))
	local items = ns.Alts_ShoppingItems(full, "full")
	local byItem = {}
	for _, it in ipairs(items) do
		byItem[it.itemID] = it.qty
	end
	eq(byItem[2001], nil, "crafted Alloy not bought")
	eq(byItem[4001], 8, "ore for 2 alloy (first rank)")
	eq(byItem[5001], nil, "crafted Flux not bought")
	eq(byItem[6001], 1, "herb for one Flux craft (makes 2)")
	eq(byItem[3001], 5, "dust")
	eq(#items, 3, "three items")
	-- Only the missing part: 3 ore on hand.
	local some = ns.Alts_ShoppingItems(ns.Alts_Plan(1, 1, Ctx({ [4002] = 3 })), "full")
	eq(some[1].itemID, 4001, "ore first")
	eq(some[1].qty, 5, "8 - 3 ore")
	-- One step: the recipe's own materials, Alloy itself bought (2), its ore and flux left off.
	local one = ns.Alts_ShoppingItems(ns.Alts_Plan(1, 1, Ctx({ [2001] = 1 }, 1)), "one")
	eq(#one, 2, "alloy and dust")
	eq(one[1].itemID, 2001, "alloy")
	eq(one[1].qty, 1, "2 needed - 1 on hand")
	eq(one[2].qty, 5, "dust")
	-- Several plans (the Crafting list) add up per item.
	local both = ns.Alts_ShoppingItems({ ns.Alts_Plan(3, 1, Ctx({})), ns.Alts_Plan(3, 3, Ctx({})) }, "full")
	eq(#both, 1, "one entry")
	eq(both[1].qty, 4, "1 + 3 herbs")
	eq(#ns.Alts_ShoppingItems(ns.Alts_Plan(3, 1, Ctx({ [6001] = 9 })), "full"), 0, "nothing missing")
end)

test("recipe items: name, known by, learnable by with +n", function()
	eq(ns.Alts_RecipeItemName("Plans: Charged Runeaxe"), "charged runeaxe", "prefix")
	eq(ns.Alts_RecipeItemName("Formula: Enchant Weapon - Authority"), "enchant weapon - authority", "dash kept")
	eq(ns.Alts_RecipeItemName("Flux"), "flux", "no prefix")
	eq(ns.Alts_RecipeItemName(nil), nil, "no name")
	local byName = ns.Alts_RecipesByName(RECIPES)
	eq(byName["flux"][1], 3, "by name")
	local status, names = ns.Alts_RecipeItemStatus(CHARS, RECIPES, byName["flux"])
	eq(status, "known", "Alchy knows Flux")
	eq(names, "Alchy", "known by")
	status, names = ns.Alts_RecipeItemStatus(CHARS, RECIPES, byName["unknown thing"])
	eq(status, "learnable", "nobody knows it")
	eq(names, "Alchy, Bob", "both alchemists")
	local chars = {}
	for i, n in ipairs({ "E", "D", "C", "B", "A" }) do
		chars[i] = { name = n, profs = { [1] = { base = ALCH, known = {} } } }
	end
	local _, five, base = ns.Alts_RecipeItemStatus(chars, RECIPES, { 4 })
	eq(five, "A, B, C, +2", "three names then +n")
	eq(base, ALCH, "its profession")
	eq(ns.Alts_RecipeItemStatus({ x = { name = "X", profs = {} } }, RECIPES, { 4 }), nil, "nobody has the profession")
end)

test("free profession slots and gap text", function()
	local chars = {
		a = { name = "Tomten", level = 80, profs = { [164] = { name = "Blacksmithing" }, [186] = { name = "Mining" } } },
		b = { name = "Mira", level = 34, profs = { [171] = { name = "Alchemy" } } },
		c = { name = "Tomtis", level = 80, profs = { [185] = { name = "Cooking", secondary = true } } },
		d = { name = "Zed", level = 80 },
	}
	local free = ns.Alts_FreeSlots(chars)
	eq(#free, 3, "three with a free slot")
	eq(free[1].name, "Tomtis", "max level first, by name")
	eq(free[2].name, "Zed", "then the next max level one")
	eq(free[3].name, "Mira", "then lower levels")
	eq(ns.Alts_GapText({ "Inscription" }, { free[1], free[3] }),
		"Nobody has Inscription. Free profession slot: Tomtis (lvl 80), Mira (lvl 34).", "hint")
	eq(ns.Alts_GapText({ "Inscription", "Skinning" }, {}),
		"Nobody has Inscription or Skinning, and every character has two professions.", "no slot")
	local uncovered = ns.Alts_Uncovered(chars)
	eq(#uncovered, 8, "eleven minus three")
	eq(uncovered[1], "Enchanting", "in name order")
end)

test("total gold with and without the Warband bank", function()
	local chars = { a = { money = 10000 }, b = { money = 20000 } }
	eq(ns.Alts_TotalGold(chars), 30000, "characters only")
	eq(ns.Alts_TotalGold(chars, 3000000000), 3000030000, "plus Warband")
	eq(ns.Alts_WarbandText(3000000000), " (Warband 300,000g)", "warband part")
	eq(ns.Alts_WarbandText(0), "", "empty")
	eq(ns.Alts_WarbandText(nil), "", "never read")
end)

test("weekly status: vault and Concentration line", function()
	local now = 1000000
	local view = {
		vault = { raid = { { progress = 2, threshold = 2 }, { progress = 2, threshold = 4 } },
			world = { { progress = 3, threshold = 2 } } },
		profs = {
			[2872] = { name = "Blacksmithing", conc = { qty = 1000, max = 1000, full = true } },
			[2871] = { name = "Alchemy", conc = { qty = 400, max = 1000, full = false, fullAt = now + 6 * 3600 } },
			[2881] = { name = "Mining" },
		},
	}
	local status = ns.Alts_WeeklyStatus(view, now)
	eq(status.vault, "Vault 2/3", "unlocked of all slots")
	eq(#status.conc, 2, "only professions with Concentration")
	eq(ns.Alts_WeeklyLine(status), "Vault 2/3 · Concentration: Alchemy full in 6h, |cffffd100Blacksmithing full|r", "line")
	view.vaultReady = true
	eq(ns.Alts_WeeklyStatus(view, now).vault, "Vault rewards waiting", "ready")
	eq(ns.Alts_WeeklyStatus({ vault = {}, profs = {} }, now), nil, "nothing to say")
	eq(ns.Alts_WeeklyLine(nil), "", "no Weekly")
end)

test("gear for a character: armor type, weapons, main stat, profession tools", function()
	local hunter = { class = "HUNTER", primary = "AGI", profs = { [164] = { base = 164 } } }
	local mage = { class = "MAGE", primary = "INT", profs = {} }
	local function item(classID, sub, loc, prim)
		return { classID = classID, subclassID = sub, equipLoc = loc, primaries = prim }
	end
	eq(ns.Alts_GearFor(item(4, 3, "INVTYPE_CHEST", { AGI = true, INT = true }), hunter), "gear", "mail chest, hybrid stat")
	eq(ns.Alts_GearFor(item(4, 4, "INVTYPE_CHEST"), hunter), false, "plate")
	eq(ns.Alts_GearFor(item(4, 3, "INVTYPE_HEAD", { STR = true }), hunter), false, "wrong main stat")
	eq(ns.Alts_GearFor(item(4, 3, "INVTYPE_HEAD", nil), hunter), "gear", "stats still loading")
	eq(ns.Alts_GearFor(item(4, 1, "INVTYPE_CLOAK", { AGI = true }), hunter), "gear", "cloak")
	eq(ns.Alts_GearFor(item(4, 0, "INVTYPE_FINGER", {}), hunter), "gear", "ring without main stat")
	eq(ns.Alts_GearFor(item(4, 6, "INVTYPE_SHIELD"), hunter), false, "shield")
	eq(ns.Alts_GearFor(item(4, 0, "INVTYPE_HOLDABLE", { INT = true }), mage), "gear", "off-hand for a mage")
	eq(ns.Alts_GearFor(item(2, 2, "INVTYPE_RANGED", { AGI = true }), hunter), "gear", "bow")
	eq(ns.Alts_GearFor(item(2, 19, "INVTYPE_RANGEDRIGHT", { INT = true }), hunter), false, "wand")
	eq(ns.Alts_GearFor(item(2, 19, "INVTYPE_RANGEDRIGHT", { INT = true }), mage), "gear", "wand for a mage")
	eq(ns.Alts_GearFor(item(19, 0, "INVTYPE_PROFESSION_TOOL"), hunter), "tool", "Blacksmithing hammer")
	eq(ns.Alts_GearFor(item(19, 6, "INVTYPE_PROFESSION_TOOL"), hunter), false, "not a tailor")
	eq(ns.Alts_GearFor(item(0, 0, ""), hunter), false, "a flask")
	eq(ns.Alts_GearFor(item(4, 3, "INVTYPE_CHEST"), { primary = "AGI" }), false, "class unknown")
end)

test("what a craft replaces and the upgrade mark", function()
	local worn = { [1] = 600, [11] = 610, [12] = 590, [16] = 605 }
	local t = ns.Alts_WornFor("INVTYPE_HEAD", worn)
	eq(t.ilvl, 600, "head")
	eq(t.name, "Head", "slot name")
	eq(ns.Alts_WornFor("INVTYPE_FINGER", worn).ilvl, 590, "the weaker ring")
	eq(ns.Alts_WornFor("INVTYPE_WEAPON", worn).slot, 16, "one-hander without an off hand: main hand")
	eq(ns.Alts_WornFor("INVTYPE_FEET", worn).ilvl, nil, "empty slot")
	eq(ns.Alts_WornFor("INVTYPE_PROFESSION_TOOL", worn), nil, "not worn gear")
	worn.twoHand = true
	eq(ns.Alts_Upgrade(590, 620, ns.Alts_WornFor("INVTYPE_HOLDABLE", worn)), nil, "off hand next to a two-hander")
	eq(ns.Alts_Upgrade(590, 620, { ilvl = 600, loading = true }), nil, "loading")
	local kind, gain = ns.Alts_Upgrade(605, 620, t)
	eq(kind, "sure", "every quality")
	eq(gain, 5, "gain at the lowest")
	kind, gain = ns.Alts_Upgrade(590, 620, t)
	eq(kind, "top", "top quality only")
	eq(gain, 20, "gain at the highest")
	kind, gain = ns.Alts_Upgrade(580, 595, t)
	eq(kind, "no", "never")
	eq(gain, -5, "how far short")
	eq(ns.Alts_Upgrade(580, 595, { name = "Feet" }), "empty", "empty slot")
	eq(ns.Alts_Upgrade(nil, nil, t), nil, "item level unknown")
	eq(ns.Alts_Upgrade(nil, 610, t), "sure", "one quality")
end)

test("profession gear: item kind, slots, what it replaces", function()
	eq(select(1, ns.Alts_ProfItem(19, 0, "INVTYPE_PROFESSION_TOOL")), 164, "Blacksmithing tool")
	eq(select(2, ns.Alts_ProfItem(19, 5, "INVTYPE_PROFESSION_GEAR")), "acc", "Mining accessory")
	eq(ns.Alts_ProfItem(19, 13, "INVTYPE_PROFESSION_TOOL"), nil, "archaeology")
	eq(ns.Alts_ProfItem(4, 0, "INVTYPE_PROFESSION_TOOL"), nil, "not a profession item")
	eq(ns.Alts_ProfSlots(185, "acc"), 1, "cooking has one accessory")
	eq(ns.Alts_ProfSlots(164, "acc"), 2, "two accessories")
	eq(ns.Alts_ProfSlots(794, "tool"), 0, "archaeology")
	local worn = {
		{ base = 164, kind = "tool", ilvl = 590 },
		{ base = 164, kind = "acc", ilvl = 580 },
		{ base = 186, kind = "acc", ilvl = 600 },
		{ base = 186, kind = "acc", ilvl = 570 },
	}
	eq(ns.Alts_ProfTarget(worn, 164, "tool").ilvl, 590, "the worn tool")
	eq(ns.Alts_ProfTarget(worn, 164, "acc").ilvl, nil, "a free accessory slot")
	eq(ns.Alts_ProfTarget(worn, 186, "acc").ilvl, 570, "the weaker accessory")
	eq(ns.Alts_ProfTarget(worn, 186, "tool").name, "Tool", "no tool")
	eq(ns.Alts_ProfTarget(worn, 794, "tool"), nil, "no such slot")
	worn[1].ilvl = false
	eq(ns.Alts_ProfTarget(worn, 164, "tool").loading, true, "loading")
end)

test("profession gear: best craft and best home for a bag item", function()
	local cands = {
		{ recipeID = 1, lo = 580, hi = 610, known = true },
		{ recipeID = 2, lo = 600, hi = 640, known = false },
		{ recipeID = 3, lo = 595, hi = 610, known = true },
	}
	local best = ns.Alts_BestProfCraft(cands, { ilvl = 590 })
	eq(best.recipeID, 3, "known, highest, then the better lowest quality")
	eq(best.mark, "sure", "an upgrade at every quality")
	eq(best.gain, 5, "gain")
	eq(ns.Alts_BestProfCraft(cands, { ilvl = 620 }), nil, "nothing better")
	eq(ns.Alts_BestProfCraft(cands, { name = "Tool" }).mark, "empty", "a free slot")
	eq(ns.Alts_BestProfCraft({}, { ilvl = 1 }), nil, "no recipes")
	local home = ns.Alts_ProfBagUpgrade(600, {
		{ guid = "a", target = { ilvl = 590 } },
		{ guid = "b", target = { ilvl = 560 } },
		{ guid = "c", target = { ilvl = 620 } },
	})
	eq(home.guid, "b", "the biggest gain")
	eq(home.gain, 40, "gain")
	eq(ns.Alts_ProfBagUpgrade(600, { { guid = "a", target = { ilvl = 590 } }, { guid = "d", target = { name = "Tool" } } }).guid,
		"d", "a free slot first")
	eq(ns.Alts_ProfBagUpgrade(500, { { guid = "a", target = { ilvl = 590 } } }), nil, "nobody's upgrade")
end)

test("ForgetMatches skips the character being played and finds its stale twin", function()
	local alts = {
		new = { name = "Tomten", realm = "Silvermoon" }, -- transferred: new GUID, same name
		old = { name = "Tomten", realm = "ArgentDawn" },
		x = { name = "Other", realm = "ArgentDawn" },
	}
	local r = ns.Alts_ForgetMatches({ alts }, "tomten", "new")
	eq(#r.matches, 1, "matches")
	eq(r.matches[1].guid, "old", "the stale one")
	eq(r.playing, true, "playing")
	eq(r.ambiguous, false, "one realm left")
	r = ns.Alts_ForgetMatches({ alts }, "Other", "new")
	eq(r.matches[1].guid, "x")
	eq(r.playing, false)
	r = ns.Alts_ForgetMatches({ { new = alts.new } }, "TOMTEN", "new")
	eq(#r.matches, 0, "only the current one")
	eq(r.playing, true)
	eq(#ns.Alts_ForgetMatches({ alts }, "nobody", "new").matches, 0)
end)

test("ForgetMatches: name on several realms is ambiguous, name-realm picks one", function()
	local alts = {
		a = { name = "Bob", realm = "ArgentDawn" },
		b = { name = "Bob", realm = "Silvermoon" },
		c = { name = "Bob", realm = "Silvermoon" }, -- deleted and remade on the same realm
	}
	local r = ns.Alts_ForgetMatches({ alts }, "bob", "me")
	eq(#r.matches, 3)
	eq(r.ambiguous, true)
	r = ns.Alts_ForgetMatches({ alts }, "bob-silvermoon", "me")
	eq(#r.matches, 2, "both on that realm")
	eq(r.ambiguous, false)
	r = ns.Alts_ForgetMatches({ alts }, " Bob-Argent Dawn ", "me")
	eq(#r.matches, 1, "realm with a space")
	eq(r.matches[1].guid, "a")
end)

test("ForgetMatches merges Alts and Weekly characters", function()
	local alts = { a = { name = "Bob", realm = "R" } }
	local weekly = { a = { name = "Bob", realm = "R" }, w = { name = "Bob", realm = "R" } }
	local r = ns.Alts_ForgetMatches({ alts, weekly, nil }, "bob", "me")
	eq(#r.matches, 2)
	eq(r.ambiguous, false)
end)

test("ForgetEverywhere clears every per-character store", function()
	local function Root()
		return {
			alts = { chars = { g = {}, k = {} } },
			weekly = { chars = { g = {} }, hidden = { g = true } },
			ach = { cache = { g = {} }, pins = { g = { 1 } } },
			gear = { weights = { g = {} }, hinted = { g = {} } },
			hunter = { chars = { g = {} } },
			moments = { zones = { g = { [1] = true } } },
			way = { routes = { g = {} } },
			sessionLast = { g = {}, k = {} },
			recap = { history = { { guid = "g" }, { guid = "k" }, { guid = "g" } } },
		}
	end
	local root = Root()
	eq(ns.Alts_ForgetEverywhere(root, "g"), 13, "entries removed")
	for _, t in ipairs({ root.alts.chars, root.weekly.chars, root.weekly.hidden, root.ach.cache, root.ach.pins,
		root.gear.weights, root.gear.hinted, root.hunter.chars, root.moments.zones, root.way.routes, root.sessionLast }) do
		eq(t.g, nil, "cleared")
	end
	eq(root.alts.chars.k ~= nil, true, "others stay")
	eq(root.sessionLast.k ~= nil, true, "others' sessions stay")
	eq(#root.recap.history, 1, "history")
	eq(root.recap.history[1].guid, "k")
	eq(ns.Alts_ForgetEverywhere({}, "g"), 0, "missing modules are fine")
end)

-- Crafting quality --------------------------------------------------------------------------------------------

local function RankCtx(have, ranks)
	local ctx = Ctx(have)
	ctx.ranks = ranks
	return ctx
end

test("ranks: a picked rank counts only that item", function()
	local have = { [2001] = 0, [3001] = 5, [4001] = 8, [4003] = 2, [5001] = 2 }
	local any = ns.Alts_Plan(2, 1, RankCtx(have))
	eq(Material(any, 4001).have, 10, "any rank adds them up")
	eq(Material(any, 4001).missing, 0)
	local r3 = ns.Alts_Plan(2, 1, RankCtx(have, { ["4001,4002,4003"] = 4003 }))
	local m = Material(r3, 4003)
	eq(#m.items, 1, "one item")
	eq(m.have, 2, "only rank 3")
	eq(m.missing, 2)
	eq(m.slot[1], 4001, "keeps the full slot")
	eq(#m.slot, 3)
	eq(Material(r3, 4001), nil, "no any-rank material")
end)

test("ranks: an item that isn't in the slot is ignored", function()
	local plan = ns.Alts_Plan(2, 1, RankCtx({ [4001] = 4 }, { ["4001,4002,4003"] = 9999 }))
	eq(#Material(plan, 4001).items, 3)
end)

test("ranks: a crafted material is still found and its step gets the rank", function()
	local recipes = {
		[1] = { name = "Axe", base = BS, item = 1001, reagents = { { items = { 2001, 2002, 2003 }, qty = 2 } } },
		[2] = { name = "Alloy", base = BS, item = 2001, qMin = 1, nq = 3, reagents = { { items = { 4001 }, qty = 3 } } },
	}
	local chars = { a = { guid = "a", name = "T", profs = { [1] = { base = BS, known = { [1] = true, [2] = true } } } } }
	local plan = ns.Alts_Plan(1, 1, {
		recipes = recipes, chars = chars, producers = ns.Alts_Producers(recipes), maxDepth = ns.ALTS_FULL_DEPTH,
		ranks = { ["2001,2002,2003"] = 2003 },
		count = function(items)
			return items[1] == 4001 and 6 or 0
		end,
	})
	eq(#plan.steps, 2, "alloy first, then the axe")
	eq(plan.steps[1].recipeID, 2)
	eq(plan.steps[1].quality, 3, "made at rank 3")
	eq(plan.steps[2].quality, nil, "the top craft has no picked rank")
	eq(plan.missing, 0)
end)

test("quality: clamp, count and links", function()
	local gear = { nq = 5, out = { "lo", "hi" }, outQ = { "q1", "q2", "q3", "q4", "q5" } }
	eq(ns.Alts_Qualities(gear), 5)
	eq(ns.Alts_Qualities({}), 1, "none")
	eq(ns.Alts_ClampQuality(gear, "range"), nil, "range")
	eq(ns.Alts_ClampQuality(gear, nil), nil)
	eq(ns.Alts_ClampQuality(gear, 3), 3)
	eq(ns.Alts_ClampQuality({ nq = 2 }, 5), 2, "a recipe with fewer qualities uses its highest")
	local lo, hi, exact = ns.Alts_QualityLinks(gear, 4)
	eq(lo, "q4")
	eq(hi, "q4")
	eq(exact, true)
	lo, hi, exact = ns.Alts_QualityLinks(gear, nil)
	eq(lo, "lo")
	eq(hi, "hi")
	eq(exact, false)
	lo, hi, exact = ns.Alts_QualityLinks({ out = { "lo", "hi" } }, 3)
	eq(hi, "hi", "read before every quality was stored: the range")
	eq(exact, false)
	eq((ns.Alts_QualityLinks({}, 3)), nil, "no output")
end)

test("quality: one item level is a sure upgrade or none", function()
	eq((ns.Alts_Upgrade(600, 600, { ilvl = 590 })), "sure")
	eq((ns.Alts_Upgrade(580, 580, { ilvl = 590 })), "no")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
