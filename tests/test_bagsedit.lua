-- Run from the AddOns folder: lua Tomte/tests/test_bagsedit.lua
local ns = {}
assert(loadfile("Tomte/Modules/Bags/Search.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Bags/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Bags/EditData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function keys(list)
	local out = {}
	for i, node in ipairs(list) do
		out[i] = node.key
	end
	return table.concat(out, ",")
end

local function small()
	return ns.BagsEdit_Copy({
		{ kind = "category", key = "a", name = "A", rule = "is:potion" },
		{ kind = "section", key = "s", name = "S", children = {
			{ kind = "category", key = "b", name = "B", rule = "is:weapon" },
		} },
		{ kind = "divider" },
		{ kind = "category", key = "other", name = "Other", auto = "other" },
	})
end

test("copy keys every node and leaves the defaults alone", function()
	local layout = ns.BagsEdit_Copy(ns.BAGS_LAYOUT)
	local seen = {}
	local function check(nodes)
		for _, node in ipairs(nodes) do
			assert(node.key, "a node without a key")
			assert(not seen[node.key], "duplicate key " .. node.key)
			seen[node.key] = true
			check(node.children or {})
		end
	end
	check(layout)
	layout[1].name = "Changed"
	eq(ns.BAGS_LAYOUT[1].name, "New")
end)

test("find returns the list, index, node and section", function()
	local layout = small()
	local list, i, node, section = ns.BagsEdit_Find(layout, "b")
	eq(i, 1)
	eq(node.name, "B")
	eq(section.key, "s")
	eq(list, section.children)
	eq(ns.BagsEdit_Find(layout, "nope"), nil)
end)

test("move up and down within a list, not past its ends", function()
	local layout = small()
	eq(ns.BagsEdit_Move(layout, "a", -1), false)
	eq(ns.BagsEdit_Move(layout, "a", 1), true)
	eq(layout[1].key, "s")
	eq(layout[2].key, "a")
	eq(ns.BagsEdit_Move(layout, "b", 1), false)
end)

test("a category moves into a section and back out after it", function()
	local layout = small()
	eq(ns.BagsEdit_SetSection(layout, "a", "s"), true)
	eq(keys(layout[1].children), "b,a")
	eq(ns.BagsEdit_SetSection(layout, "b", nil), true)
	eq(layout[2].key, "b")
	eq(keys(layout[1].children), "a")
	eq(ns.BagsEdit_SetSection(layout, "s", nil), false, "sections stay at the top level")
end)

test("adding puts new nodes on top (or at a section's end) with fresh keys", function()
	local layout = small()
	local c = ns.BagsEdit_AddCategory(layout, "Mine", "is:upgrade")
	eq(layout[1], c)
	eq(c.rule, "is:upgrade")
	local d = ns.BagsEdit_AddCategory(layout, "In S", "", "s")
	local _, _, _, section = ns.BagsEdit_Find(layout, d.key)
	eq(section.key, "s")
	assert(c.key ~= d.key)
	local sec = ns.BagsEdit_AddSection(layout, "New section")
	eq(sec.kind, "section")
	eq(ns.BagsEdit_AddDivider(layout).kind, "divider")
end)

test("removing a section keeps its categories; Other can't go", function()
	local layout = small()
	eq(ns.BagsEdit_Remove(layout, "s"), true)
	eq(layout[2].key, "b")
	eq(ns.BagsEdit_Remove(layout, "other"), false)
	eq(ns.BagsEdit_Remove(layout, "a"), true)
	eq(layout[1].key, "b")
end)

test("item IDs from pasted text and back", function()
	local ids = ns.BagsEdit_ParseIDs("123, 456 789\n12")
	eq(ids[123], true)
	eq(ids[12], true)
	eq(ns.BagsEdit_IDsText(ids), "12, 123, 456, 789")
	eq(ns.BagsEdit_IDsText(nil), "")
end)

test("saving a search under the same name replaces it", function()
	local searches = {}
	ns.BagsEdit_SaveSearch(searches, "Ups", "is:upgrade")
	ns.BagsEdit_SaveSearch(searches, "Ups", "is:upgrade ilvl>600")
	eq(#searches, 1)
	eq(searches[1].text, "is:upgrade ilvl>600")
end)

test("export and import round-trip, with odd characters", function()
	local layout = small()
	local c = ns.BagsEdit_AddCategory(layout, "Pipes | and \\ slashes", "is:potion | is:food")
	c.priority, c.ownLine, c.hidden = 7, true, true
	c.shows = { bank = false }
	c.items = { [6948] = true, [12] = true }
	local text = ns.BagsEdit_Export(layout)
	local other = small()
	local added, err = ns.BagsEdit_Import(other, text)
	assert(added, err)
	local got = other[1]
	eq(got.name, "Pipes | and \\ slashes")
	eq(got.rule, "is:potion | is:food")
	eq(got.priority, 7)
	eq(got.ownLine, true)
	eq(got.hidden, true)
	eq(got.shows.bank, false)
	eq(got.items[6948], true)
	eq(got.kind, "category")
	-- the section and its category came along
	local section
	for _, node in ipairs(other) do
		if node.kind == "section" and node.name == "S" and node ~= other[#other] and node.key ~= "s" then
			section = node
		end
	end
	assert(section, "the section wasn't imported")
	eq(section.children[1].name, "B")
	-- every key unique
	local seen = {}
	local function check(nodes)
		for _, node in ipairs(nodes) do
			if node.key then
				assert(not seen[node.key], "duplicate key " .. node.key)
				seen[node.key] = true
			end
			check(node.children or {})
		end
	end
	check(other)
end)

test("an export line has exactly six fields", function()
	local layout = small()
	local c = ns.BagsEdit_AddCategory(layout, "X", "is:potion")
	c.items = { [5] = true, [7] = true }
	local text = ns.BagsEdit_Export({ c })
	local line = text:match("\n([^\n]+)$")
	local n = select(2, line:gsub("|", "|")) + 1
	eq(n, 6)
	eq(line:sub(-4), "|5,7")
end)

test("why: an item put in a category by hand says so", function()
	local cats = ns.Bags_Flatten(ns.BagsEdit_Copy({
		{ kind = "category", key = "mine", name = "Mine", rule = "", items = { [100] = true } },
		{ kind = "category", key = "other", name = "Other", auto = "other" },
	}))
	local lines = ns.Bags_Why({ itemID = 100 }, cats)
	assert(lines[1]:find("you put this item in it"), lines[1])
end)

test("import refuses other text", function()
	local added, err = ns.BagsEdit_Import(small(), "hello")
	eq(added, nil)
	eq(type(err), "string")
	added, err = ns.BagsEdit_Import(small(), "TomteBags:1\ncat|x")
	eq(added, nil)
end)

test("hand-kept items win over every rule", function()
	local cats = ns.Bags_Flatten(ns.BagsEdit_Copy({
		{ kind = "category", key = "up", name = "Up", rule = "is:upgrade", priority = 9 },
		{ kind = "category", key = "mine", name = "Mine", rule = "", items = { [100] = true } },
		{ kind = "category", key = "other", name = "Other", auto = "other" },
	}))
	local byKey = ns.Bags_Assign({ { itemID = 100, upgrade = "upgrade" }, { itemID = 5, upgrade = "upgrade" } }, cats)
	eq(byKey.mine[1].itemID, 100)
	eq(byKey.up[1].itemID, 5)
end)

test("a category left out of a place doesn't take items there", function()
	local cats = ns.Bags_Flatten(ns.BagsEdit_Copy({
		{ kind = "category", key = "pot", name = "Potions", rule = "is:potion", shows = { bank = false } },
		{ kind = "category", key = "other", name = "Other", auto = "other" },
	}))
	local potion = { classID = 0, subclassID = 1 }
	eq(ns.Bags_Assign({ potion }, cats, "bags").pot[1], potion)
	eq(ns.Bags_Assign({ potion }, cats, "bank").other[1], potion)
end)

H.done()
