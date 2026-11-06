-- Run from the AddOns folder: lua Tomte/tests/test_sources.lua
local ns = {}
assert(loadfile("Tomte/Modules/Sources/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Forever/ItemSources.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local DATA = {
	items = {
		[1] = "Linen Cloth|u10:30,u11:50,u12:100,u13:40,v20,o30:60",
		[2] = "Linen Bag|v20",
		[3] = "Bolt of Linen Cloth|u10:5",
		[4] = "Oops|u999:5,o999:5",
	},
	units = {
		[10] = "Kobold|5-7|||12|40.5|60|20",
		[11] = "Defias|18-20|||40|30|30|15",
		[12] = "Lone Rare|6|||12|10|10|1",
		[13] = "Orc Peon|5|H||14|20|20|12",
		[20] = "Supply Officer|30|AH|||14|50|50|1",
	},
	objects = { [30] = "Battered Chest|12|60|70|8" },
	zones = { [12] = "Elwynn Forest", [14] = "Durotar", [40] = "Westfall" },
}
DATA.units[20] = "Supply Officer|30|AH||14|50|50|1"

test("Search: the whole name, then the start, then anywhere", function()
	local found = ns.Sources_Search(DATA.items, "linen cloth")
	eq(found[1].itemID, 1)
	eq(found[2].itemID, 3)
	found = ns.Sources_Search(DATA.items, "  LINEN ")
	eq(found[1].itemID, 2, "the start, shortest first")
	eq(found[2].itemID, 1)
	eq(found[3].itemID, 3, "anywhere comes last")
	eq(#ns.Sources_Search(DATA.items, "l"), 0, "too short")
	eq(#ns.Sources_Search(DATA.items, ""), 0)
	eq(#ns.Sources_Search(DATA.items, nil), 0)
	eq(#ns.Sources_Search(DATA.items, "(.)"), 0, "a search isn't a pattern")
end)

test("Read: every kind of source, with its place", function()
	local rows = ns.Sources_Read(DATA, 1)
	eq(#rows, 6)
	eq(rows[1].kind, "drop")
	eq(rows[1].name, "Kobold")
	eq(rows[1].chance, 30)
	eq(rows[1].low, 5)
	eq(rows[1].high, 7)
	eq(rows[1].x, 40.5)
	eq(rows[1].zoneName, "Elwynn Forest")
	eq(rows[5].kind, "vendor")
	eq(rows[5].chance, nil)
	eq(rows[5].friendly, "AH")
	eq(rows[6].kind, "object")
	eq(rows[6].name, "Battered Chest")
	eq(rows[6].spawns, 8)
	eq(#ns.Sources_Read(DATA, 99), 0, "no such item")
	eq(#ns.Sources_Read(DATA, 4), 0, "unknown units and objects are skipped")
	eq(ns.Sources_Name(DATA.items, 1), "Linen Cloth")
	eq(ns.Sources_Name(DATA.items, 99), nil)
end)

test("Sort: near your level first, by where it's best to farm", function()
	local sorted = ns.Sources_Sort(ns.Sources_Read(DATA, 1), 6, "Alliance")
	eq(sorted.drops[1].name, "Kobold", "30% of 20 spawns beats 100% of one")
	eq(sorted.drops[2].name, "Lone Rare")
	eq(sorted.drops[3].name, "Orc Peon", "Durotar: the other side's lands")
	eq(sorted.drops[4].name, "Defias", "above you comes after")
	sorted = ns.Sources_Sort(ns.Sources_Read(DATA, 1), 19, "Alliance")
	eq(sorted.drops[1].name, "Defias")
end)

test("Sort: your side's lands before the other side's, at the same level", function()
	local rows = {
		{ kind = "drop", id = 1, name = "Theirs", low = 10, high = 12, friendly = "", zone = 12, chance = 90, spawns = 20 },
		{ kind = "drop", id = 2, name = "Ours", low = 10, high = 12, friendly = "", zone = 17, chance = 10, spawns = 20 },
		{ kind = "drop", id = 3, name = "Far above", low = 30, high = 31, friendly = "", zone = 17, chance = 90, spawns = 20 },
	}
	local horde = ns.Sources_Sort(rows, 11, "Horde").drops
	eq(horde[1].name, "Ours")
	eq(horde[2].name, "Theirs", "still near your level")
	eq(horde[3].name, "Far above")
	eq(ns.Sources_Sort(rows, 11, "Alliance").drops[1].name, "Theirs", "the other way round")
end)

test("Sort: what's on your side", function()
	local alliance = ns.Sources_Sort(ns.Sources_Read(DATA, 1), 6, "Alliance")
	eq(#alliance.drops, 4, "a Horde mob can be killed")
	eq(#alliance.buy, 1, "AH sells to both")
	local horde = ns.Sources_Sort(ns.Sources_Read(DATA, 1), 6, "Horde")
	eq(#horde.drops, 3, "not your own side's mobs")
	local only = { { kind = "vendor", id = 1, friendly = "A", low = 1, high = 1 } }
	eq(#ns.Sources_Sort(only, 6, "Horde").buy, 0, "that vendor won't sell to you")
	eq(#ns.Sources_Sort(only, 6, "Alliance").buy, 1)
	eq(#ns.Sources_Sort(ns.Sources_Read(DATA, 1), 6, "Alliance").gather, 1)
end)

test("Near", function()
	local mob = { low = 10, high = 12 }
	eq(ns.Sources_Near(mob, 18), true)
	eq(ns.Sources_Near(mob, 19), false, "too far below you")
	eq(ns.Sources_Near(mob, 7), true)
	eq(ns.Sources_Near(mob, 6), false, "too far above you")
end)

test("Texts", function()
	eq(ns.Sources_ChanceText(33.4), "33%")
	eq(ns.Sources_ChanceText(4.25), "4.2%")
	eq(ns.Sources_ChanceText(0), nil)
	eq(ns.Sources_ChanceText(nil), nil)
	eq(ns.Sources_SubText({ zoneName = "Elwynn Forest", levels = "5-7", rank = "elite" }), "Elwynn Forest, level 5-7, elite")
	eq(ns.Sources_SubText({ zoneName = "Elwynn Forest" }), "Elwynn Forest")
end)

test("TipLine: buying first, then what's near you", function()
	local sorted = ns.Sources_Sort(ns.Sources_Read(DATA, 1), 6, "Alliance")
	eq(ns.Sources_TipLine(sorted, 6), "Sold by Supply Officer, Durotar")
	sorted.buy = {}
	eq(ns.Sources_TipLine(sorted, 6), "Drops from Kobold, Elwynn Forest (30%)")
	eq(ns.Sources_TipLine(sorted, 60), "From Battered Chest, Elwynn Forest", "no mob near you: the chest")
	eq(ns.Sources_TipLine({ buy = {}, gather = {}, drops = {} }, 6), nil)
end)

test("the generated data: Linen Cloth, and every source can be read", function()
	local data = { items = ns.SOURCES_ITEMS, units = ns.SOURCES_UNITS, objects = ns.SOURCES_OBJECTS, zones = ns.SOURCES_ZONES }
	eq(ns.Sources_Name(data.items, 2589), "Linen Cloth")
	eq(#ns.Sources_Read(data, 2589) > 0, true)
	eq(ns.Sources_Search(data.items, "linen cloth")[1].itemID, 2589)
	local checked = 0
	for itemID in pairs(data.items) do
		for _, row in ipairs(ns.Sources_Read(data, itemID)) do
			assert(row.name and row.zone and row.x and row.y, "item " .. itemID)
			checked = checked + 1
		end
		eq(#ns.Sources_Read(data, itemID) > 0, true, "item " .. itemID)
	end
	eq(checked > 1000, true)
end)

H.done()
