-- Run from the AddOns folder: lua Tomte/tests/test_bags.lua
local ns = {}
assert(loadfile("Tomte/Modules/Bags/Search.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Bags/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local categories = ns.Bags_Flatten(ns.BAGS_LAYOUT)

test("ItemClass: tools count as profession equipment where the game has no such class", function()
	local WEAPON, TRADE, PROFESSION, DAGGER, FISHING = 2, 7, 19, 15, 20
	local tools = { [7005] = true, [5956] = true }
	eq(ns.Bags_ItemClass(7005, WEAPON, DAGGER, tools), PROFESSION, "skinning knife, a dagger")
	eq(ns.Bags_ItemClass(5956, TRADE, 0, tools), PROFESSION, "a tool that isn't a weapon")
	eq(ns.Bags_ItemClass(6256, WEAPON, FISHING, tools), PROFESSION, "a fishing pole, by its subclass")
	eq(ns.Bags_ItemClass(1234, WEAPON, DAGGER, tools), WEAPON, "any other dagger")
	eq(ns.Bags_ItemClass(1234, TRADE, FISHING, tools), TRADE, "the subclass only means a pole on a weapon")
	eq(ns.Bags_ItemClass(7005, WEAPON, DAGGER, nil), WEAPON, "retail: no list, the game's own class")
	eq(ns.Bags_ItemClass(6256, WEAPON, FISHING, nil), WEAPON)
end)

test("the profession rule takes a tool, and the weapon rule no longer does", function()
	local tool = { classID = ns.Bags_ItemClass(7005, 2, 15, { [7005] = true }), subclassID = 15, name = "Skinning Knife" }
	local byKey = ns.Bags_Assign({ tool }, categories)
	eq(byKey.profession and #byKey.profession, 1)
	eq(byKey.weapon, nil)
end)

test("VendorMarks: each item gets its winning category's setting", function()
	local knife, bread, arrow = { name = "Knife" }, { name = "Bread" }, { name = "Arrow" }
	local cats = {
		{ key = "keep", rule = "knife", vendor = "hide" },
		{ key = "food", rule = "bread", vendor = "fade" },
		{ key = "rest", rule = "arrow" },
	}
	local marks, hidden = ns.Bags_VendorMarks({ knife, bread, arrow }, cats, "bags")
	eq(marks[knife], "hide")
	eq(marks[bread], "fade")
	eq(marks[arrow], nil)
	eq(hidden, 1, "only hidden ones are counted")
end)

test("VendorMarks: a higher priority category decides", function()
	local knife = { name = "Knife" }
	local marks, hidden = ns.Bags_VendorMarks({ knife }, {
		{ key = "keep", rule = "knife", vendor = "hide" },
		{ key = "sell", rule = "knife", priority = 5 },
	}, "bags")
	eq(marks[knife], nil, "the item is in the category that doesn't hide")
	eq(hidden, 0)
end)

test("VendorMarks: nothing set, a hidden category, and Empty", function()
	local knife = { name = "Knife" }
	local marks, hidden = ns.Bags_VendorMarks({ knife }, { { key = "a", rule = "knife" } }, "bags")
	eq(next(marks), nil, "no category asks")
	marks, hidden = ns.Bags_VendorMarks({ knife }, { { key = "a", rule = "knife", vendor = "hide", hidden = true } }, "bags")
	eq(hidden, 0, "already left out")
	local slot = { empty = true, kind = "normal" }
	marks, hidden = ns.Bags_VendorMarks({ slot }, { { key = "empty", auto = "empty", vendor = "hide" } }, "bags")
	eq(marks[slot], nil)
	eq(hidden, 0)
end)

test("KeepPlaces: a slot that now holds another item doesn't keep its place", function()
	local recipe = { bag = 6, slot = 1, itemID = 100, name = "Recipe" }
	local snapshot, was = ns.Bags_Snapshot({ recipe = { recipe } })
	local linen = { bag = 6, slot = 1, itemID = 2589, name = "Linen" }
	local out = ns.Bags_KeepPlaces(snapshot, { reagent = { linen } }, { [6001] = linen }, was)
	eq(#out.recipe, 0, "the cloth isn't drawn with the recipes")
	eq(out.reagent[1], linen, "it's with the reagents")
	local same = { bag = 6, slot = 1, itemID = 100, name = "Recipe" }
	out = ns.Bags_KeepPlaces(snapshot, { other = { same } }, { [6001] = same }, was)
	eq(out.recipe[1], same, "the same item keeps its place")
end)

test("DropHidden: removes hidden records, keeps order and the rest", function()
	local a, b, c = { name = "a" }, { name = "b" }, { name = "c" }
	local out = ns.Bags_DropHidden({ one = { a, b, c }, two = { b } }, { [b] = "hide", [c] = "fade" })
	eq(#out.one, 2)
	eq(out.one[1], a)
	eq(out.one[2], c, "faded stays")
	eq(#out.two, 0)
end)

test("rules with words need the tooltip text read first", function()
	eq(ns.Bags_RulesUseText({ { rule = "is:junk" }, { rule = "ilvl>600" } }), false, "keywords only")
	eq(ns.Bags_RulesUseText({ { rule = "is:junk" }, { rule = "artifact" } }), true, "a word")
	eq(ns.Bags_RulesUseText({ { auto = "empty" }, { rule = "is:" } }), false, "auto and broken rules")
	local byKey = ns.Bags_Assign({ { name = "Clay Jar", text = "dragon isles artifacts\nsoulbound", readable = true } },
		{ { key = "art", rule = "artifact" } })
	eq(byKey.art and #byKey.art, 1, "found through the tooltip text")
end)

local function where(item)
	local byKey = ns.Bags_Assign({ item }, categories)
	for key, list in pairs(byKey) do
		if list[1] == item then
			return key
		end
	end
	return nil
end

test("every default rule compiles", function()
	for _, c in ipairs(categories) do
		if c.rule then
			assert(ns.BagsSearch_Compile(c.rule), c.key .. " rule doesn't compile")
		else
			assert(c.auto, c.key .. " has neither rule nor auto")
		end
	end
end)

test("flatten keeps the order and names the section", function()
	eq(categories[1].key, "new")
	local weapon
	for _, c in ipairs(categories) do
		if c.key == "weapon" then
			weapon = c
		end
	end
	eq(weapon.section, "equipment")
	for i, c in ipairs(categories) do
		eq(c.order, i, c.key .. " order")
	end
end)

test("a reagent goes to Reagent, trade goods too", function()
	eq(where({ classID = 5, subclassID = 0 }), "reagent")
	eq(where({ classID = 7, subclassID = 9 }), "reagent")
end)

test("an upgrade armor piece goes to Upgrades, not Armor", function()
	eq(where({ classID = 4, upgrade = "upgrade" }), "upgrades")
	eq(where({ classID = 4 }), "armor")
end)

test("a new upgrade goes to New (higher priority)", function()
	eq(where({ classID = 4, upgrade = "upgrade", new = true }), "new")
end)

test("grey armor is junk", function()
	eq(where({ classID = 4, quality = 0, junk = true }), "junk")
end)

test("equal priority: the category higher in the list wins", function()
	-- a potion is also a consumable: Potion comes first
	eq(where({ classID = 0, subclassID = 1 }), "potion")
	local list = ns.Bags_Flatten({
		{ kind = "category", key = "b", name = "B", rule = "is:gear" },
		{ kind = "category", key = "a", name = "A", rule = "is:armor" },
		{ kind = "category", key = "other", name = "Other", auto = "other" },
	})
	local byKey = ns.Bags_Assign({ { classID = 4 } }, list)
	eq(byKey.b and #byKey.b, 1)
	eq(byKey.a, nil)
end)

test("items in an equipment set go to Equipment sets over Armor", function()
	eq(where({ classID = 4, set = { "Tank" } }), "sets")
end)

test("nothing matches: Other", function()
	eq(where({ classID = 18 }), "other")
end)

test("empty slots go to Empty", function()
	eq(where({ empty = true, kind = "normal" }), "empty")
	eq(where({ empty = true, kind = "reagent" }), "empty")
end)

test("a layout without Other drops unmatched items", function()
	local list = ns.Bags_Flatten({ { kind = "category", key = "a", name = "A", rule = "is:armor" } })
	local byKey = ns.Bags_Assign({ { classID = 0 } }, list)
	eq(next(byKey), nil)
end)

test("sorting: quality, then item level, then name", function()
	local list = ns.Bags_SortItems({
		{ quality = 3, ilvl = 600, name = "C" },
		{ quality = 4, ilvl = 600, name = "A" },
		{ quality = 3, ilvl = 610, name = "B" },
		{ quality = 3, ilvl = 600, name = "A" },
	})
	eq(list[1].quality, 4)
	eq(list[2].ilvl, 610)
	eq(list[3].name, "A")
	eq(list[4].name, "C")
end)

test("sorting: same item, bigger stack first, then bag and slot", function()
	local list = ns.Bags_SortItems({
		{ itemID = 1, count = 5, bag = 1, slot = 2 },
		{ itemID = 1, count = 20, bag = 2, slot = 1 },
		{ itemID = 1, count = 5, bag = 0, slot = 9 },
	})
	eq(list[1].count, 20)
	eq(list[2].bag, 0)
	eq(list[3].bag, 1)
end)

test("sort methods: type, name, item level, and reversed", function()
	local function make()
		return {
			{ name = "B", classID = 4, quality = 3, ilvl = 610 },
			{ name = "A", classID = 0, quality = 1 },
			{ name = "C", classID = 4, quality = 4, ilvl = 600 },
		}
	end
	local list = ns.Bags_SortItems(make(), "type")
	eq(list[1].name, "A")
	eq(list[2].name, "C")
	list = ns.Bags_SortItems(make(), "name")
	eq(list[1].name, "A")
	eq(list[3].name, "C")
	list = ns.Bags_SortItems(make(), "ilvl")
	eq(list[1].name, "B")
	list = ns.Bags_SortItems(make(), "quality", true)
	eq(list[1].name, "A")
	eq(list[3].name, "C")
	list = ns.Bags_SortItems(make(), "nonsense")
	eq(list[1].name, "C")
end)

test("a shared corner shows the first mark that applies", function()
	local corners = { marker = "TOPLEFT", upgrade = "TOPLEFT", transmog = "TOPRIGHT", crafting = "TOPRIGHT",
		set = "BOTTOMLEFT", ilvl = "BOTTOMLEFT", petlevel = "off" }
	local shown = ns.Bags_CornerMarks({ marker = "keep", transmog = "you", ilvl = 610 }, corners)
	eq(shown.TOPLEFT, "marker")
	eq(shown.TOPRIGHT, "transmog")
	eq(shown.BOTTOMLEFT, "ilvl")
	shown = ns.Bags_CornerMarks({ marker = "keep", upgrade = "upgrade", crafting = 3, transmog = "you", set = true,
		ilvl = 610 }, corners)
	eq(shown.TOPLEFT, "upgrade")
	eq(shown.TOPRIGHT, "crafting")
	eq(shown.BOTTOMLEFT, "set")
	shown = ns.Bags_CornerMarks({ petlevel = 25 }, corners)
	eq(next(shown), nil, "an Off mark never shows")
	local order = ns.Bags_MoveMark(ns.Bags_MarkOrder(nil), "marker", -1)
	shown = ns.Bags_CornerMarks({ marker = "keep", upgrade = "upgrade" }, corners, order)
	eq(shown.TOPLEFT, "marker", "the player's order wins")
end)

test("mark order: the player's, made whole", function()
	local order = ns.Bags_MarkOrder(nil)
	eq(table.concat(order, ","), table.concat(ns.BAGS_MARKS, ","))
	order = ns.Bags_MarkOrder({ "ilvl", "junk", "ilvl", "set", "upgrade" })
	eq(#order, #ns.BAGS_MARKS, "unknown and repeated keys dropped, missing ones back")
	eq(table.concat(order, ","), "ilvl,set,petlevel,upgrade,marker,crafting,transmog",
		"the saved order kept, each missing mark after the one before it by default")
	eq(table.concat(ns.Bags_MoveMark({ "a", "b", "c" }, "c", -1), ","), "a,c,b")
	eq(table.concat(ns.Bags_MoveMark({ "a", "b", "c" }, "a", -1), ","), "a,b,c", "stays inside the list")
	eq(table.concat(ns.Bags_MoveMark({ "a", "b", "c" }, "a", 1), ","), "b,a,c")
end)

test("corner stacks list each corner's marks in order", function()
	local stacks = ns.Bags_CornerStacks({ upgrade = "TOPLEFT", marker = "TOPLEFT", ilvl = "BOTTOMLEFT", set = "off" })
	eq(table.concat(stacks.TOPLEFT, ","), "upgrade,marker")
	eq(table.concat(stacks.BOTTOMLEFT, ","), "ilvl")
	eq(#stacks.TOPRIGHT, 0)
end)

test("what fits at a merchant, the mailbox, a trade or the Auction House", function()
	local soulbound = { bind = "soulbound" }
	local warbound = { bind = "warbound" }
	local boe = { bind = "boe" }
	local quest = { quest = true }
	eq(ns.Bags_Fits({ noValue = true }, "merchant"), false)
	local particle = { itemID = 1234, noValue = true }
	eq(ns.Bags_Fits(particle, "merchant", { [1234] = true }), true, "the vendor takes it as payment")
	eq(ns.Bags_Fits(particle, "merchant", { [999] = true }), false)
	eq(ns.Bags_Fits(particle, "mail", { [1234] = true }), true)
	eq(ns.Bags_Fits(soulbound, "merchant"), true)
	eq(ns.Bags_Fits(soulbound, "mail"), false)
	eq(ns.Bags_Fits(warbound, "mail"), true)
	eq(ns.Bags_Fits(warbound, "trade"), false)
	eq(ns.Bags_Fits(boe, "trade"), true)
	eq(ns.Bags_Fits(boe, "auction"), true)
	eq(ns.Bags_Fits(quest, "auction"), false)
	eq(ns.Bags_Fits({}, "auction"), true)
	eq(ns.Bags_Fits(soulbound, nil), true)
	eq(ns.Bags_Fits({ empty = true }, "merchant"), true)
	eq(ns.Bags_Fits({ warbandOK = false }, "warband"), false)
	eq(ns.Bags_Fits({ warbandOK = true }, "warband"), true)
end)

test("junk is grey, sellable and not soulbound", function()
	eq(ns.Bags_IsJunk(0, false, nil), true)
	eq(ns.Bags_IsJunk(0, false, "soulbound"), false)
	eq(ns.Bags_IsJunk(0, true, nil), false)
	eq(ns.Bags_IsJunk(1, false, nil), false)
end)

test("a bag's slots go by its family, the reagent bag by its place", function()
	eq(ns.Bags_SlotKind(0, false), "normal")
	eq(ns.Bags_SlotKind(nil, false), "normal")
	eq(ns.Bags_SlotKind(1, false), "quiver")
	eq(ns.Bags_SlotKind(4, false), "soul")
	eq(ns.Bags_SlotKind(33554432, false), "skinning")
	eq(ns.Bags_SlotKind(1, true), "reagent")
	eq(ns.Bags_SlotKind(4194304, false), "special", "a family without a name")
	eq(ns.Bags_SlotKindName("quiver"), "Quiver")
end)

test("a special bag takes only its own kind", function()
	eq(ns.Bags_BagTakes(0, 0), true, "ordinary bag, ordinary item")
	eq(ns.Bags_BagTakes(nil, 1), true, "ordinary bag, arrows")
	eq(ns.Bags_BagTakes(1, 0), false, "quiver, ordinary item")
	eq(ns.Bags_BagTakes(1, nil), false, "quiver, unknown item")
	eq(ns.Bags_BagTakes(1, 1), true, "quiver, arrows")
	eq(ns.Bags_BagTakes(1, 2), false, "quiver, bullets")
	eq(ns.Bags_BagTakes(32, 33), true, "an item of two families")
end)

test("free slots count ordinary bags; other kinds are apart, added up, in order", function()
	local free, total, others = ns.Bags_FreeSummary({
		{ free = 3, total = 16, kind = "normal" },
		{ free = 2, total = 12, kind = "soul" },
		{ free = 5, total = 16, kind = "quiver" },
		{ free = 1, total = 8, kind = "normal" },
		{ free = 1, total = 16, kind = "quiver" },
		{ free = 0, total = 0, kind = "herb" },
	})
	eq(free, 4)
	eq(total, 24)
	eq(#others, 2, "no slots, no line")
	eq(others[1].name, "Quiver")
	eq(others[1].free, 6)
	eq(others[1].total, 32)
	eq(others[2].name, "Soul")
	eq(ns.Bags_OtherFreeText(others), "Quiver 6, Soul 2")
end)

test("free slots with only special bags, and with no others", function()
	local free, total, others = ns.Bags_FreeSummary({ { free = 5, total = 16, kind = "quiver" } })
	eq(free, 0, "a full bag is full, whatever the quiver has")
	eq(total, 0)
	eq(#others, 1)
	eq(ns.Bags_OtherFreeText({}), nil)
end)

test("a grey upgrade isn't junk", function()
	eq(ns.Bags_IsJunk(0, false, nil, "upgrade"), false)
	eq(ns.Bags_IsJunk(0, false, nil, "maybe"), false)
	eq(ns.Bags_IsJunk(0, false, nil, nil), true)
end)

test("keeping places: a sold item leaves its slot empty where it was, new items go last", function()
	local a = { bag = 0, slot = 1, name = "A" }
	local b = { bag = 0, slot = 2, name = "B" }
	local c = { bag = 0, slot = 3, name = "C" }
	local snapshot = ns.Bags_Snapshot({ potion = { a, b, c }, empty = { { empty = true, bag = 1, slot = 1 } } })
	eq(snapshot.empty, nil)
	-- B was sold: its slot is empty now; D arrived in bag 2
	local emptyB = { empty = true, kind = "normal", bag = 0, slot = 2 }
	local d = { bag = 2, slot = 5, name = "D" }
	local bySlot = { [1] = a, [2] = emptyB, [3] = c, [2005] = d }
	local out = ns.Bags_KeepPlaces(snapshot, { potion = { a, c, d }, empty = { emptyB } }, bySlot)
	eq(#out.potion, 4)
	eq(out.potion[1], a)
	eq(out.potion[2], emptyB)
	eq(out.potion[3], c)
	eq(out.potion[4], d)
	eq(#out.empty, 0, "B's empty slot is kept in Potion, so Empty can't use it")
end)

test("keeping places: an item that arrived and left again leaves its slot empty (the view snapshots every draw)", function()
	local a = { bag = 0, slot = 1, name = "A" }
	local snapshot = ns.Bags_Snapshot({ potion = { a } })
	-- D taken from the bank into bag 2 slot 5: it joins at the end, and that place is kept from now on
	local d = { bag = 2, slot = 5, name = "D" }
	local out = ns.Bags_KeepPlaces(snapshot, { potion = { a, d } }, { [1] = a, [2005] = d })
	snapshot = ns.Bags_Snapshot(out)
	-- D put back in the bank
	local emptyD = { empty = true, kind = "normal", bag = 2, slot = 5 }
	out = ns.Bags_KeepPlaces(snapshot, { potion = { a }, empty = { emptyD } }, { [1] = a, [2005] = emptyD })
	eq(#out.potion, 2)
	eq(out.potion[2], emptyD, "D's place stays, empty")
end)

test("keeping places: an item put back in another free slot goes into the hole it left", function()
	local a = { bag = 0, slot = 1, itemID = 10 }
	local b = { bag = 0, slot = 2, itemID = 20 }
	local c = { bag = 0, slot = 3, itemID = 30 }
	local snapshot, was = ns.Bags_Snapshot({ potion = { a, b, c } })
	-- B went to the bank, then came back into bag 1 slot 7 (the game's first free slot), not slot 2
	local emptyB = { empty = true, kind = "normal", bag = 0, slot = 2 }
	local back = { bag = 1, slot = 7, itemID = 20 }
	local bySlot = { [1] = a, [2] = emptyB, [3] = c, [1007] = back }
	local out = ns.Bags_KeepPlaces(snapshot, { potion = { a, c, back }, empty = { emptyB } }, bySlot, was)
	eq(#out.potion, 3, "no new place")
	eq(out.potion[2], back, "in B's old place")
	eq(out.empty[1], emptyB, "the old slot is free for Empty again")
	-- another item arriving takes a hole too when there is one, else the end
	local d = { bag = 2, slot = 1, itemID = 40 }
	local snap2, was2 = ns.Bags_Snapshot({ potion = { a, emptyB, c } })
	out = ns.Bags_KeepPlaces(snap2, { potion = { a, c, d } }, { [1] = a, [2] = emptyB, [3] = c, [2001] = d }, was2)
	eq(out.potion[2], d, "a hole in its category")
end)

test("keeping places: Empty uses another free slot when its slot is kept in place", function()
	local a = { bag = 0, slot = 1 }
	local snapshot = ns.Bags_Snapshot({ potion = { a } })
	local emptyA = { empty = true, kind = "normal", bag = 0, slot = 1, free = 2 }
	local other = { empty = true, kind = "normal", bag = 1, slot = 4 }
	local out = ns.Bags_KeepPlaces(snapshot, { empty = { emptyA } }, { [1] = emptyA, [1004] = other })
	eq(out.potion[1], emptyA)
	eq(out.empty[1].slot, 4)
	eq(out.empty[1].bag, 1)
	eq(out.empty[1].free, 2)
	-- no other free slot of that kind: Empty shows nothing for it
	out = ns.Bags_KeepPlaces(snapshot, { empty = { emptyA } }, { [1] = emptyA })
	eq(#out.empty, 0)
end)

test("keeping places: an item that changes category stays where it was", function()
	local a = { bag = 0, slot = 1 }
	local snapshot = ns.Bags_Snapshot({ new = { a } })
	local out = ns.Bags_KeepPlaces(snapshot, { armor = { a } }, { [1] = a })
	eq(out.new[1], a)
	eq(#out.armor, 0)
end)

test("currency rows: tracked first, headers, and a search", function()
	local list = {
		{ index = 1, isHeader = true, name = "Midnight", isHeaderExpanded = true },
		{ index = 2, name = "Voidlight Marl", quantity = 5, isShowInBackpack = true },
		{ index = 3, isHeader = true, name = "Delves", isHeaderExpanded = false },
		{ index = 4, name = "Undercoin", quantity = 25 },
	}
	local tracked = { { currencyID = 3000, name = "Voidlight Marl", quantity = 5 },
		{ currencyID = 3001, name = "Hidden Coin", quantity = 1 } }
	local rows = ns.Bags_CurrencyRows(list, nil, { tracked[1] })
	eq(rows[1].name, "Tracked")
	eq(rows[2].name, "Voidlight Marl")
	eq(rows[2].info.isShowInBackpack, true)
	eq(rows[2].info.currencyID, 3000)
	eq(rows[3].kind, "header")
	eq(rows[3].index, 1)
	eq(rows[4].name, "Voidlight Marl")
	eq(rows[5].name, "Delves")
	eq(rows[5].expanded, false)
	eq(rows[6].name, "Undercoin")
	eq(rows[6].depth, 1)
	rows = ns.Bags_CurrencyRows(list, nil, tracked)
	eq(rows[3].name, "Hidden Coin", "tracked even when its header is folded")
	rows = ns.Bags_CurrencyRows(list, "under")
	eq(#rows, 3)
	eq(rows[2].name, "Delves")
	eq(rows[3].name, "Undercoin")
end)

test("currency rows: a hint while nothing is tracked, depth under a sub-header", function()
	local list = {
		{ index = 1, isHeader = true, name = "Midnight", isHeaderExpanded = true, currencyListDepth = 0 },
		{ index = 2, isHeader = true, name = "Season 2", isHeaderExpanded = true, currencyListDepth = 1 },
		{ index = 3, name = "Venomblight Manaflux", quantity = 5 },
	}
	local rows = ns.Bags_CurrencyRows(list)
	eq(rows[2].kind, "hint")
	eq(rows[3].depth, 0)
	eq(rows[4].depth, 1)
	eq(rows[5].depth, 2)
	rows = ns.Bags_CurrencyRows(list, "venom")
	eq(rows[2].kind, "header", "no hint while searching")
end)

test("battle pet level from a cage's link", function()
	eq(ns.Bags_PetLevel("|cff0070dd|Hbattlepet:1387:25:3:1546:276:276:0x0|h[Mr. Bigglesworth]|h|r"), 25)
	eq(ns.Bags_PetLevel("|cffffffff|Hitem:6948::::::::80:::::|h[Hearthstone]|h|r"), nil)
	eq(ns.Bags_PetLevel(nil), nil)
end)

test("grouping merges stacks of the same item, keeping the first stack's slot", function()
	local items = {
		{ link = "L1", count = 20, bag = 0, slot = 1, name = "Ore" },
		{ empty = true, kind = "normal", bag = 0, slot = 2 },
		{ link = "L1", count = 5, bag = 1, slot = 3, name = "Ore" },
		{ link = "L2", count = 1, bag = 1, slot = 4, name = "Herb" },
		{ link = "L2", readable = false, count = 1, bag = 1, slot = 5 },
	}
	local out = ns.Bags_Group(items)
	eq(#out, 4)
	eq(out[1].count, 25)
	eq(out[1].stacks, 2)
	eq(out[1].slot, 1)
	eq(out[1].name, "Ore")
	eq(#out[1].more, 1, "the other stack's place")
	eq(out[1].more[1].bag, 1)
	eq(out[1].more[1].slot, 3)
	eq(out[3].more, nil, "one stack has no others")
	eq(items[1].count, 20, "the original record is untouched")
	eq(items[1].more, nil, "the original record is untouched")
	eq(out[2].empty, true)
	eq(out[4].readable, false)
end)

test("StackLine says how a grouped item is split up and how much more fits", function()
	eq(ns.Bags_StackLine(22, 2, 20), "Stacks to 20: 2 stacks, 18 more fit")
	eq(ns.Bags_StackLine(40, 2, 20), "Stacks to 20: 2 stacks, full")
	eq(ns.Bags_StackLine(2, 1, 20), "Stacks to 20: 1 stack, 18 more fit")
	eq(ns.Bags_StackLine(22, 3, 20), "Stacks to 20: 3 stacks, 38 more fit", "not packed tight")
	eq(ns.Bags_StackLine(1, 1, 1), nil, "doesn't stack")
	eq(ns.Bags_StackLine(5, 1, nil), nil, "stack size not loaded yet")
	eq(ns.Bags_StackLine(5, nil, 20), nil, "not grouped")
end)

test("StacksToSell: a grouped item's other stacks, as many as buyback can still hold", function()
	eq(#ns.Bags_StacksToSell({}), 0, "not grouped")
	local more = {}
	for i = 1, 15 do
		more[i] = { bag = 1, slot = i }
	end
	eq(#ns.Bags_StacksToSell({ more = { more[1], more[2] } }), 2)
	local list = ns.Bags_StacksToSell({ more = more })
	eq(#list, 11, "12 with the clicked stack")
	eq(list[11].slot, 11)
	eq(#ns.Bags_StacksToSell({ more = more, noValue = true }), 0, "sells for nothing")
end)

test("counts add up stacks per item and skip empty slots", function()
	local counts = ns.Bags_Counts({
		{ itemID = 10, count = 20 }, { itemID = 10, count = 5 }, { itemID = 11 }, { empty = true }, { count = 3 },
	})
	eq(counts[10], 25)
	eq(counts[11], 1)
end)

local function Slot(bag, slot, itemID, count)
	return { bag = bag, slot = slot, itemID = itemID, count = count }
end

test("only the stack that grew is new, not every stack of the item", function()
	local before = ns.Bags_Held({
		Slot(0, 1, 10, 20), Slot(0, 2, 10, 20), Slot(0, 3, 10, 5), Slot(0, 4, 11, 4), Slot(0, 6, 13, 3),
	})
	local items = {
		Slot(0, 1, 10, 20), Slot(0, 2, 10, 20), Slot(0, 3, 10, 6), -- one Light Leather picked up, onto the 5
		Slot(0, 4, 11, 4), -- unchanged
		Slot(0, 5, 12, 1), -- didn't have it
		Slot(0, 6, 13, 1), -- used some
		{ empty = true, bag = 0, slot = 7 },
	}
	ns.Bags_MarkGained(items, before)
	eq(items[1].new, nil, "a full stack you had")
	eq(items[2].new, nil)
	eq(items[3].new, true, "the stack it went onto")
	eq(items[4].new, nil)
	eq(items[5].new, true)
	eq(items[6].new, nil)
	eq(items[7].new, nil)
end)

test("moving or splitting a stack isn't new; loot that spills into another slot is", function()
	local before = ns.Bags_Held({ Slot(0, 1, 10, 20), Slot(0, 2, 10, 18) })
	local moved = { Slot(0, 1, 10, 20), Slot(1, 4, 10, 18) } -- the 18 moved to another bag
	ns.Bags_MarkGained(moved, before)
	eq(moved[2].new, nil, "same total: nothing gained")
	local split = { Slot(0, 1, 10, 20), Slot(0, 2, 10, 10), Slot(0, 3, 10, 8) }
	ns.Bags_MarkGained(split, before)
	eq(split[3].new, nil)
	local spilled = { Slot(0, 1, 10, 20), Slot(0, 2, 10, 20), Slot(0, 3, 10, 3) } -- 5 looted: 2 on top, 3 in a new slot
	ns.Bags_MarkGained(spilled, before)
	eq(spilled[1].new, nil)
	eq(spilled[2].new, true)
	eq(spilled[3].new, true)
end)

test("bind state from the bind type and whether this copy is bound", function()
	eq(ns.Bags_BindState(1, true), "soulbound")
	eq(ns.Bags_BindState(2, false), "boe")
	eq(ns.Bags_BindState(3, false), "boe")
	eq(ns.Bags_BindState(2, true), "soulbound")
	eq(ns.Bags_BindState(8, true), "warbound")
	eq(ns.Bags_BindState(7, false), "warbound")
	eq(ns.Bags_BindState(9, false), "warbound")
	eq(ns.Bags_BindState(9, true), "soulbound")
	eq(ns.Bags_BindState(0, false), nil)
end)

test("why lists the winner first", function()
	local lines = ns.Bags_Why({ classID = 4, upgrade = "upgrade" }, categories)
	assert(lines[1]:find("^Upgrades"), lines[1])
	assert(lines[2]:find("^also Armor"), tostring(lines[2]))
	lines = ns.Bags_Why({ classID = 18 }, categories)
	assert(lines[1]:find("Other"), lines[1])
end)

test("Forever's default categories have no keystone or decor", function()
	local function Keys(flags)
		assert(loadfile("Tomte/Modules/Bags/Search.lua"))("Tomte", flags)
		assert(loadfile("Tomte/Modules/Bags/Data.lua"))("Tomte", flags)
		local keys = {}
		for _, node in ipairs(flags.Bags_Flatten(flags.BAGS_LAYOUT)) do
			keys[node.key] = true
		end
		return keys
	end
	local forever, retail = Keys({ FOREVER = true }), Keys({})
	eq(forever.keystone, nil, "no Mythic+")
	eq(forever.decor, nil, "no housing")
	eq(forever.key and forever.other and forever.empty, true, "the rest stay")
	eq(retail.keystone and retail.decor, true, "retail keeps them")
end)

test("HoldsSlot: the item's own place or one of a group's stacks", function()
	local grouped = ns.Bags_Group({ { bag = 0, slot = 1, link = "a", count = 2 }, { bag = 2, slot = 5, link = "a", count = 3 } })[1]
	eq(ns.Bags_HoldsSlot(grouped, 0, 1), true)
	eq(ns.Bags_HoldsSlot(grouped, 2, 5), true, "a stack merged into the group")
	eq(ns.Bags_HoldsSlot(grouped, 2, 6), false)
	eq(ns.Bags_HoldsSlot({ bag = 1, slot = 3 }, 1, 3), true)
	eq(ns.Bags_HoldsSlot({ bag = 1, slot = 3 }, nil, nil), false)
end)

H.done()
