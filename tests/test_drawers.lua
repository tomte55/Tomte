-- Run from the AddOns folder: lua Tomte/tests/test_drawers.lua
local ns = {}
assert(loadfile("Tomte/Modules/Drawers/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function list(entries)
	local out = {}
	for i, e in ipairs(entries) do
		out[i] = e.kind .. ":" .. e.id
	end
	return table.concat(out, " ")
end

test("IsEntry accepts the four kinds with a positive whole ID", function()
	eq(ns.Drawers_IsEntry({ kind = "item", id = 6948 }), true)
	eq(ns.Drawers_IsEntry({ kind = "toy", id = 54452 }), true)
	eq(ns.Drawers_IsEntry({ kind = "spell", id = 556 }), true)
	eq(ns.Drawers_IsEntry({ kind = "mount", id = 381 }), true)
	eq(ns.Drawers_IsEntry({ kind = "macro", id = 1 }), false, "unknown kind")
	eq(ns.Drawers_IsEntry({ kind = "item", id = 0 }), false, "zero")
	eq(ns.Drawers_IsEntry({ kind = "item", id = 1.5 }), false, "fraction")
	eq(ns.Drawers_IsEntry({ kind = "item", id = "6948" }), false, "string id")
	eq(ns.Drawers_IsEntry("item:6948"), false, "not a table")
end)

test("ParseLink reads item, spell and mount links", function()
	local kind, id = ns.Drawers_ParseLink("|cffffffff|Hitem:6948::::::::80:::::|h[Hearthstone]|h|r")
	eq(kind, "item")
	eq(id, 6948)
	kind, id = ns.Drawers_ParseLink("|cff71d5ff|Hspell:556:0|h[Astral Recall]|h|r")
	eq(kind, "spell")
	eq(id, 556)
	kind, id = ns.Drawers_ParseLink("|cff71d5ff|Hmount:458:0|h[Brown Horse]|h|r")
	eq(kind, "mountSpell")
	eq(id, 458)
end)

test("ParseLink takes bare item: and spell: text, ignores other links", function()
	local kind, id = ns.Drawers_ParseLink("  item:6948")
	eq(kind, "item")
	eq(id, 6948)
	eq(ns.Drawers_ParseLink("|Hachievement:123:abc|h[Thing]|h"), nil, "achievement link")
	eq(ns.Drawers_ParseLink("Hearthstone"), nil, "plain name")
	eq(ns.Drawers_ParseLink(nil), nil, "nil")
end)

test("ParseCursor: item, spell (spellID or base), mount, others nil", function()
	local kind, id = ns.Drawers_ParseCursor("item", 6948, "|Hitem:6948|h")
	eq(kind, "item")
	eq(id, 6948)
	kind, id = ns.Drawers_ParseCursor("spell", 12, "spell", 556, 556)
	eq(kind, "spell")
	eq(id, 556)
	kind, id = ns.Drawers_ParseCursor("spell", 12, "spell", nil, 8690)
	eq(kind, "spell", "base spell")
	eq(id, 8690)
	kind, id = ns.Drawers_ParseCursor("mount", 381, 5)
	eq(kind, "mount")
	eq(id, 381)
	eq(ns.Drawers_ParseCursor("macro", 3), nil, "macro")
	eq(ns.Drawers_ParseCursor("money", 100), nil, "money")
	eq(ns.Drawers_ParseCursor("spell", 12, "spell"), nil, "spell without an ID")
end)

test("Add appends, refuses duplicates, full drawers and bad entries", function()
	local entries = {}
	eq(ns.Drawers_Add(entries, { kind = "item", id = 6948 }), 1)
	eq(ns.Drawers_Add(entries, { kind = "toy", id = 6948 }), 2, "same ID, other kind")
	local index, why = ns.Drawers_Add(entries, { kind = "item", id = 6948 })
	eq(index, nil)
	eq(why, "duplicate")
	index, why = ns.Drawers_Add(entries, { kind = "spell", id = 556 }, 2)
	eq(index, nil)
	eq(why, "full")
	index, why = ns.Drawers_Add(entries, { kind = "pet", id = 1 })
	eq(why, "invalid")
	eq(list(entries), "item:6948 toy:6948")
end)

test("Add stores a copy", function()
	local entries, entry = {}, { kind = "item", id = 6948 }
	ns.Drawers_Add(entries, entry)
	entry.id = 1
	eq(entries[1].id, 6948)
end)

test("Remove and Move", function()
	local entries = {
		{ kind = "item", id = 1 }, { kind = "item", id = 2 }, { kind = "item", id = 3 },
	}
	eq(ns.Drawers_Move(entries, 1, -1), nil, "first can't go up")
	eq(ns.Drawers_Move(entries, 3, 1), nil, "last can't go down")
	eq(ns.Drawers_Move(entries, 1, 1), 2)
	eq(list(entries), "item:2 item:1 item:3")
	eq(ns.Drawers_Move(entries, 3, -1), 2)
	eq(list(entries), "item:2 item:3 item:1")
	eq(ns.Drawers_Remove(entries, 2).id, 3)
	eq(list(entries), "item:2 item:1")
	eq(ns.Drawers_Remove(entries, 5), nil, "no such index")
end)

test("Clean drops junk, duplicates and overflow in place", function()
	local entries = {
		{ kind = "item", id = 1 }, "junk", { kind = "item", id = 1 }, { kind = "spell", id = 2 },
		{ kind = "mount", id = 3 },
	}
	eq(ns.Drawers_Clean(entries, 2), 3)
	eq(list(entries), "item:1 spell:2")
	eq(entries[3], nil)
end)

test("Layout UP: one line going up from the button", function()
	local points, box = ns.Drawers_Layout(3, "UP", 8, 36, 4)
	eq(points[1].x, 0)
	eq(points[1].y, 40)
	eq(points[3].y, 120)
	eq(box.left, -18)
	eq(box.right, 18)
	eq(box.bottom, 22)
	eq(box.top, 138)
end)

test("Layout wraps to new lines", function()
	local points = ns.Drawers_Layout(5, "UP", 2, 36, 4)
	eq(points[3].x, 40, "second line to the right")
	eq(points[3].y, 40)
	eq(points[5].x, 80)
	points = ns.Drawers_Layout(3, "RIGHT", 2, 36, 4)
	eq(points[2].x, 80)
	eq(points[3].x, 40, "second line starts again by the button")
	eq(points[3].y, -40, "and goes down")
	points = ns.Drawers_Layout(2, "LEFT", 8, 36, 4)
	eq(points[2].x, -80)
	points = ns.Drawers_Layout(2, "DOWN", 8, 36, 4)
	eq(points[2].y, -80)
end)

test("Layout: empty drawer and a bad perLine", function()
	local points, box = ns.Drawers_Layout(0, "UP", 8, 36, 4)
	eq(#points, 0)
	eq(box.left, 0)
	points = ns.Drawers_Layout(2, "UP", 0, 36, 4)
	eq(points[2].x, 40, "perLine below 1 counts as 1")
end)

test("Saved returns the settings and the entry list, making a missing list", function()
	local db = { d1 = { name = "Toys" }, entries = { d1 = { { kind = "toy", id = 54452 } } } }
	local saved, entries = ns.Drawers_Saved(db, 1)
	eq(saved.name, "Toys")
	eq(#entries, 1)
	db.d2 = {}
	local _, made = ns.Drawers_Saved(db, 2)
	eq(#made, 0)
	eq(db.entries.d2, made, "kept in db")
end)

test("Name falls back to Drawer <n> and trims", function()
	eq(ns.Drawers_Name("  Toys ", 1), "Toys")
	eq(ns.Drawers_Name("", 2), "Drawer 2")
	eq(ns.Drawers_Name("   ", 3), "Drawer 3")
	eq(ns.Drawers_Name(nil, 4), "Drawer 4")
end)

H.done()
