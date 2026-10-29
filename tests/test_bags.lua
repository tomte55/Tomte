-- Run from the AddOns folder: lua Tomte/tests/test_bags.lua
local ns = {}
assert(loadfile("Tomte/Modules/Bags/Search.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Bags/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local categories = ns.Bags_Flatten(ns.BAGS_LAYOUT)

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
	local corners = { junk = "TOPLEFT", upgrade = "TOPLEFT", transmog = "TOPRIGHT", crafting = "TOPRIGHT",
		set = "BOTTOMLEFT", ilvl = "BOTTOMLEFT", petlevel = "off" }
	local shown = ns.Bags_CornerMarks({ upgrade = "upgrade", transmog = "you", ilvl = 610 }, corners)
	eq(shown.TOPLEFT, "upgrade")
	eq(shown.TOPRIGHT, "transmog")
	eq(shown.BOTTOMLEFT, "ilvl")
	shown = ns.Bags_CornerMarks({ junk = true, upgrade = "upgrade", crafting = 3, transmog = "you", set = true,
		ilvl = 610 }, corners)
	eq(shown.TOPLEFT, "junk")
	eq(shown.TOPRIGHT, "crafting")
	eq(shown.BOTTOMLEFT, "set")
	shown = ns.Bags_CornerMarks({ petlevel = 25 }, corners)
	eq(next(shown), nil, "an Off mark never shows")
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
	eq(items[1].count, 20, "the original record is untouched")
	eq(out[2].empty, true)
	eq(out[4].readable, false)
end)

test("counts add up stacks per item and skip empty slots", function()
	local counts = ns.Bags_Counts({
		{ itemID = 10, count = 20 }, { itemID = 10, count = 5 }, { itemID = 11 }, { empty = true }, { count = 3 },
	})
	eq(counts[10], 25)
	eq(counts[11], 1)
end)

test("items there's more of than before are new, every stack of them", function()
	local items = {
		{ itemID = 10, count = 20 }, { itemID = 10, count = 7 }, -- had 25, got 2 more on top
		{ itemID = 11, count = 4 }, -- had 4: unchanged
		{ itemID = 12, count = 1 }, -- didn't have it
		{ itemID = 13, count = 1 }, -- had 3, used some
		{ empty = true },
	}
	ns.Bags_MarkGained(items, { [10] = 25, [11] = 4, [13] = 3 })
	eq(items[1].new, true)
	eq(items[2].new, true)
	eq(items[3].new, nil)
	eq(items[4].new, true)
	eq(items[5].new, nil)
	eq(items[6].new, nil)
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

H.done()
