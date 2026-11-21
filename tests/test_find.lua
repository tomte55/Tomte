-- Run from the AddOns folder: lua Tomte/tests/test_find.lua
local ns = {}
assert(loadfile("Tomte/Modules/Find/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

local function Finds(text, name, title, kinds)
	return ns.Find_Matches(ns.Find_Words(text), ns.Find_Haystack(name, title, kinds))
end

local function Number(n)
	local s = tostring(n)
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

test("words: every word must be found, any case", function()
	eq(Finds("tailor", "Snang", "Journeyman Tailor"), true)
	eq(Finds("Expert TAILOR", "Magar", "Expert Tailor"), true)
	eq(Finds("expert tailor", "Snang", "Journeyman Tailor"), false)
	eq(Finds("snan", "Snang", "Journeyman Tailor"), true, "part of a name")
end)

test("a profession's name finds its trainers' titles", function()
	eq(Finds("tailoring", "Snang", "Journeyman Tailor"), true)
	eq(Finds("enchanting", "Godan", "Journeyman Enchanter"), true)
	eq(Finds("alchemy", "Yelmak", "Journeyman Alchemist"), true)
	eq(Finds("herbalism", "Jandi", "Herbalist"), true)
	eq(Finds("blacksmithing", "Saru", "Journeyman Blacksmith"), true)
	eq(Finds("mining", "Makaru", "Mining Trainer"), true)
	eq(Finds("mining", "Aldric", "Journeyman Miner"), false, "too short a stem is not tried")
end)

test("the kind's names are searched too", function()
	eq(Finds("tailor trainer", "Snang", "Journeyman Tailor", { "Profession Trainers" }), true)
	eq(Finds("mailbox", nil, nil, { "Mailbox" }), true, "a mailbox has no name")
	eq(Finds("bank", "Kesha", "Banker", { "Banker" }), true)
end)

test("an empty search finds nobody", function()
	eq(Finds("", "Snang", "Journeyman Tailor"), false)
	eq(Finds("   ", "Snang", "Journeyman Tailor"), false)
end)

local function Rows()
	return {
		{ name = "Far", mapID = 2, zone = "Stonetalon Mountains", world = { map = 1, x = 3000, y = 0 } },
		{ name = "Other", mapID = 9, zone = "Elwynn Forest", world = { map = 0, x = 0, y = 0 } },
		{ name = "Gate", mapID = 3, zone = "Durotar", world = { map = 1, x = 50, y = 0 } },
		{ name = "Inside", mapID = 1, zone = "Orgrimmar", world = { map = 1, x = 300, y = 400 } },
		{ name = "Close", mapID = 1, zone = "Orgrimmar", world = { map = 1, x = 30, y = 40 } },
	}
end

test("rank: your zone first even when a gate NPC outside is closer, then by distance, then other continents", function()
	local rows = ns.Find_Rank(Rows(), { mapID = 1, world = { map = 1, x = 0, y = 0 } })
	local order = {}
	for i, r in ipairs(rows) do
		order[i] = r.name
	end
	eq(table.concat(order, " "), "Close Inside Gate Far Other")
	near(rows[1].dist, 50)
	eq(rows[1].here, true)
	eq(rows[3].here, false)
	eq(rows[5].dist, nil)
	eq(rows[5].far, true)
end)

test("rank: inside an instance nobody has a distance, sorted by zone", function()
	local rows = ns.Find_Rank(Rows(), { mapID = 77 })
	eq(rows[1].zone, "Durotar")
	eq(rows[1].dist, nil)
	eq(rows[1].far, false)
end)

test("yards rounded as said aloud", function()
	eq(ns.Find_RoundYards(43), 40)
	eq(ns.Find_RoundYards(2), 10, "never 0")
	eq(ns.Find_RoundYards(1249), 1200)
end)

test("where: says plainly when it's outside your zone", function()
	local rows = ns.Find_Rank(Rows(), { mapID = 1, world = { map = 1, x = 0, y = 0 } })
	eq(ns.Find_Where(rows[1], "Orgrimmar", Number), "here in Orgrimmar, 50 yards")
	eq(ns.Find_Where(rows[3], "Orgrimmar", Number), "outside Orgrimmar: Durotar, 50 yards")
	eq(ns.Find_Where(rows[4], "Orgrimmar", Number), "outside Orgrimmar: Stonetalon Mountains, 3,000 yards")
	eq(ns.Find_Where(rows[5], "Orgrimmar", Number), "outside Orgrimmar: Elwynn Forest, another continent")
	local lost = ns.Find_Rank(Rows(), { mapID = 77 })
	eq(ns.Find_Where(lost[1], nil, Number), "outside your zone: Durotar")
end)

H.done()
