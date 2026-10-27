-- Run from the AddOns folder: lua Tomte/tests/test_counts.lua
local ns = {}
assert(loadfile("Tomte/Modules/Counts/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ORE = 2771

local function record()
	return {
		chars = {
			me = { name = "Aldric", class = "PALADIN", places = {
				bags = { { id = ORE, count = 10 }, { id = 6948, count = 1 } },
				bank = { { id = ORE, count = 2 } },
			} },
			alt = { name = "Kesha", class = "HUNTER", places = {
				mail = { { id = ORE, count = 20 } },
			} },
			empty = { name = "Mira", class = "MAGE", places = { bags = {} } },
		},
		warband = { items = { { id = ORE, count = 5 } } },
		guilds = { ["Ravens-Realm"] = { name = "Ravens", tabs = { [1] = { { id = ORE, count = 1 } } } } },
	}
end

test("index counts per character, place, warband and guild", function()
	local index = ns.Counts_Index(record())
	local ore = index[ORE]
	eq(ore.chars.me.bags, 10)
	eq(ore.chars.me.bank, 2)
	eq(ore.chars.alt.mail, 20)
	eq(ore.chars.empty, nil)
	eq(ore.warband, 5)
	eq(ore.guilds["Ravens-Realm"], 1)
	eq(index[6948].chars.me.bags, 1)
end)

test("rows: most first, then warband and guilds, with the total", function()
	local rec = record()
	local rows, total = ns.Counts_Rows(ns.Counts_Index(rec)[ORE], rec, "me")
	eq(total, 38)
	eq(rows[1].name, "Kesha")
	eq(rows[2].name, "Aldric")
	eq(rows[3].kind, "warband")
	eq(rows[4].name, "Ravens")
	local none = ns.Counts_Rows(nil, rec, "me")
	eq(#none, 0)
end)

test("the current character comes first among equals", function()
	local rec = { chars = {
		me = { name = "Zed", places = { bags = { { id = 1, count = 3 } } } },
		alt = { name = "Abe", places = { bags = { { id = 1, count = 3 } } } },
	} }
	local rows = ns.Counts_Rows(ns.Counts_Index(rec)[1], rec, "me")
	eq(rows[1].name, "Zed")
end)

test("places text only when it's in more than one place", function()
	eq(ns.Counts_PlacesText({ bags = 10, bank = 2 }), "bags 10, bank 2")
	eq(ns.Counts_PlacesText({ bags = 10 }), "")
	eq(ns.Counts_PlacesText({ equipped = 1, mail = 3 }), "mail 3, worn 1")
end)

test("tooltip lines: per character, warband, guild, total", function()
	local rec = record()
	local rows, total = ns.Counts_Rows(ns.Counts_Index(rec)[ORE], rec, "me")
	local lines = ns.Counts_TipLines(rows, total)
	eq(lines[1].left, "Kesha")
	eq(lines[1].right, "20 (mail)")
	eq(lines[1].class, "HUNTER")
	eq(lines[2].right, "12 (bags 10, bank 2)")
	eq(lines[3].left, "Warband bank")
	eq(lines[4].left, "Ravens")
	eq(lines[5].left, "Total")
	eq(lines[5].right, "38")
end)

test("one place only: no total line, bags shown without a place", function()
	local rec = { chars = { me = { name = "Aldric", places = { bags = { { id = 1, count = 4 } } } } } }
	local rows, total = ns.Counts_Rows(ns.Counts_Index(rec)[1], rec, "me")
	local lines = ns.Counts_TipLines(rows, total)
	eq(#lines, 1)
	eq(lines[1].right, "4")
end)

test("more than eight characters: the rest in one line", function()
	local rec = { chars = {} }
	for i = 1, 10 do
		rec.chars["g" .. i] = { name = "C" .. string.format("%02d", i), places = { bags = { { id = 1, count = i } } } }
	end
	local rows, total = ns.Counts_Rows(ns.Counts_Index(rec)[1], rec, "g1")
	local lines = ns.Counts_TipLines(rows, total)
	eq(lines[9].left, "and 2 more")
	eq(lines[9].right, "3") -- the two smallest: 2 and 1
	eq(lines[10].left, "Total")
	eq(lines[10].right, "55")
end)

test("where, for Alts", function()
	local list = ns.Counts_Where(ns.Counts_Index(record())[ORE])
	local sum = 0
	for _, w in ipairs(list) do
		sum = sum + w.n
	end
	eq(sum, 37, "guild banks aren't Alts' materials")
	eq(#ns.Counts_Where(nil), 0)
end)

test("Links gives one saved link per item, from characters, the Warband bank and guild banks", function()
	local rec = {
		chars = { a = { places = { bags = { { id = 1, link = "L1", count = 2 }, { id = 2, count = 1 } } } } },
		warband = { items = { { id = 3, link = "L3" } } },
		guilds = { g = { tabs = { { { id = 4, link = "L4" }, { id = 1, link = "other" } } } } },
	}
	local links = ns.Counts_Links(rec)
	eq(links[1], "L1")
	eq(links[2], nil, "saved without a link")
	eq(links[3], "L3")
	eq(links[4], "L4")
	eq(next(ns.Counts_Links({})), nil, "an empty record")
end)

H.done()
