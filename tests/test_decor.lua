-- Run from the AddOns folder: lua Tomte/tests/test_decor.lua
local ns = {}
assert(loadfile("Tomte/Modules/Collect/Data.lua"))("Tomte", ns) -- the source text parser Decor reads with
assert(loadfile("Tomte/Modules/Decor/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
local VENDOR = "|cFFFFD200Vendor: |rLars Bronsmaelt|n|cFFFFD200Zone: |rDornogal|n|cFFFFD200Cost: |r250" .. GOLD
local CURRENCY = "|cFFFFD200Vendor: |rKesha|n|cFFFFD200Zone: |rHallowfall|n|cFFFFD200Cost: |r50 "
	.. "|Hcurrency:3008|h[Valorstones]|h"

test("a vendor source with zone and cost", function()
	local d = ns.Decor_Describe(VENDOR)
	eq(d.source, "vendor")
	eq(d.vendor, "Lars Bronsmaelt")
	eq(d.zone, "Dornogal")
	eq(d.zones[1], "dornogal")
	assert(d.line:find("Vendor: Lars Bronsmaelt", 1, true), "line: " .. tostring(d.line))
end)

test("hyperlinks in the source become their text", function()
	eq(ns.Decor_CleanSource("50 |Hcurrency:3008|h[Valorstones]|h"), "50 Valorstones")
	eq(ns.Decor_CleanSource("|Hitem:1|hName|h"), "Name")
	eq(ns.Decor_CleanSource(nil), "")
	local d = ns.Decor_Describe(CURRENCY)
	eq(d.vendor, "Kesha")
	assert(d.line:find("Valorstones", 1, true), "line keeps the currency name: " .. tostring(d.line))
	assert(not d.line:find("|H", 1, true), "no hyperlink left")
end)

test("the first labelled source decides, places and prices don't", function()
	eq(ns.Decor_Describe("|cFFFFD200Zone: |rDornogal|n|cFFFFD200Achievement: |rDelve Deeper").source, "achievement")
	eq(ns.Decor_Describe("Quest: The Hearth|nZone: Isle of Dorn").source, "quest")
	eq(ns.Decor_Describe("Drop: Big Boss|nZone: The Rookery").source, "drop")
	eq(ns.Decor_Describe("Profession: Blacksmithing").source, "profession")
	eq(ns.Decor_Describe("Achievement: A|nVendor: B|nZone: C").source, "achievement")
	eq(ns.Decor_Describe("Treasure: Old Chest|nZone: Azj-Kahet").source, "other")
	eq(ns.Decor_Describe("Endeavor: Neighborhood work").source, "other")
	eq(ns.Decor_Describe("").source, "other")
	eq(ns.Decor_Describe(nil).source, "other")
end)

test("vendor and zone come from any line, the source from the first", function()
	local d = ns.Decor_Describe("Achievement: A|nVendor: B|nZone: Dornogal")
	eq(d.vendor, "B")
	eq(d.zone, "Dornogal")
end)

test("a custom parser can be passed", function()
	local d = ns.Decor_Describe("x", function()
		return { lines = { { label = "vendor", value = "V" } }, zones = { "here" } }
	end)
	eq(d.source, "vendor")
	eq(d.vendor, "V")
end)

test("owned count adds stored, redeemable and placed", function()
	eq(ns.Decor_OwnedCount({ totalNumStored = 2, remainingRedeemable = 1, totalNumPlaced = 3 }), 6)
	eq(ns.Decor_OwnedCount({ totalNumStored = 0 }), 0)
	eq(ns.Decor_OwnedCount(nil), 0)
	eq(ns.Decor_OwnedCount({ totalNumStored = "x" }), 0)
end)

test("tooltip line", function()
	local text, role = ns.Decor_TooltipLine(3)
	eq(text, "Decor: collected (3)")
	eq(role, "success")
	text, role = ns.Decor_TooltipLine(0)
	eq(text, "Decor: not collected")
	eq(role, "warning")
end)

test("item ID from a number, link or text", function()
	eq(ns.Decor_ItemID(123), 123)
	eq(ns.Decor_ItemID("|cffffffff|Hitem:245321::::|h[Chair]|h|r"), 245321)
	eq(ns.Decor_ItemID(" 77 "), 77)
	eq(ns.Decor_ItemID("chair"), nil)
	eq(ns.Decor_ItemID(nil), nil)
end)

local ENTRIES = {
	{ id = 1, name = "Oak Chair", owned = 0, source = "vendor", vendor = "Lars", zone = "Dornogal", zones = { "dornogal" },
		line = "Vendor: Lars" },
	{ id = 2, name = "Banner", owned = 2, source = "vendor", vendor = "Lars", zone = "Dornogal", zones = { "dornogal" } },
	{ id = 3, name = "Anvil", owned = 0, source = "vendor", vendor = "Mira", zone = "Dornogal", zones = { "dornogal" } },
	{ id = 4, name = "Bench", owned = 0, source = "vendor", vendor = "Lars", zone = "Dornogal", zones = { "dornogal" } },
	{ id = 5, name = "Trophy", owned = 0, source = "achievement", line = "Achievement: Delve Deeper" },
	{ id = 6, name = "Lamp", owned = 1, source = "drop" },
	{ id = 7, name = "Rug", owned = 0, source = "vendor", vendor = "Aldric", zone = "Hallowfall", zones = { "hallowfall" } },
	{ id = 8, name = "Stool", owned = 0, source = "weird" },
}

test("list hides owned unless asked, filters by source and query, sorts by name", function()
	local list = ns.Decor_List(ENTRIES, { source = "all", query = "" })
	eq(#list, 6)
	eq(list[1].name, "Anvil")
	eq(#ns.Decor_List(ENTRIES, { source = "all", owned = true }), 8)
	eq(#ns.Decor_List(ENTRIES, { source = "vendor" }), 4)
	local q = ns.Decor_List(ENTRIES, { source = "all", query = "delve" })
	eq(#q, 1)
	eq(q[1].name, "Trophy")
	eq(#ns.Decor_List(ENTRIES, { query = "hallowfall" }), 1, "matches the zone")
	eq(#ns.Decor_List(ENTRIES, { query = "lars", owned = true }), 3, "matches the vendor")
end)

test("sections follow the source order and count", function()
	local sections = ns.Decor_Sections(ns.Decor_List(ENTRIES, { owned = true }), { drop = true })
	eq(sections[1].key, "vendor")
	eq(#sections[1].entries, 5)
	eq(sections[1].owned, 1)
	eq(sections[1].missing, 4)
	eq(sections[2].key, "achievement")
	eq(sections[3].key, "drop")
	eq(sections[3].collapsed, true)
	eq(sections[4].key, "other", "an unknown source lands in Other")
	eq(#sections, 4)
end)

test("hiding what you have still counts it", function()
	local sections = ns.Decor_Sections(ns.Decor_List(ENTRIES, { owned = true }), {}, true)
	eq(sections[1].key, "vendor")
	eq(#sections[1].entries, 4)
	eq(sections[1].total, 5)
	eq(sections[1].owned, 1)
	eq(sections[2].key, "achievement")
	for _, s in ipairs(sections) do
		assert(s.key ~= "drop", "a section you have everything of is left out")
	end
	eq(ns.Decor_Ratio(124, 1290, function(n)
		return n == 1290 and "1,290" or tostring(n)
	end), "124 / 1,290")
end)

test("every vendor, zone and cost in the source text", function()
	local d = ns.Decor_Describe(VENDOR .. "|n|cFFFFD200Vendor: |rMira|n|cFFFFD200Zone: |rHallowfall")
	eq(#d.vendors, 2)
	eq(d.vendors[1].name, "Lars Bronsmaelt")
	eq(d.vendors[1].zone, "Dornogal")
	eq(d.vendors[1].cost, "250" .. GOLD, "the cost keeps its currency icon")
	eq(d.vendors[2].name, "Mira")
	eq(d.vendors[2].zone, "Hallowfall")
	eq(d.vendors[2].cost, nil)
	eq(d.vendor, "Lars Bronsmaelt")
	eq(d.cost, "250" .. GOLD)
	eq(#ns.Decor_Describe("Drop: Big Boss").vendors, 0)
end)

local function Sold(...)
	local list = {}
	for i = 1, select("#", ...), 2 do
		list[#list + 1] = { name = select(i, ...), zone = select(i + 1, ...) }
	end
	return list
end

local SHOP = {
	{ id = 1, itemID = 101, name = "Oak Chair", owned = 0, vendors = Sold("Lars", "Dornogal") },
	{ id = 2, itemID = 102, name = "Banner", owned = 2, vendors = Sold("Lars", "Dornogal", "Mira", "Hallowfall") },
	{ id = 3, itemID = 103, name = "Anvil", owned = 3, vendors = Sold("Mira", "Hallowfall") },
	{ id = 4, itemID = 104, name = "Rug", owned = 0, vendors = {} },
	{ id = 5, name = "Trophy", owned = 0 },
}

test("decor by vendor", function()
	local all = ns.Decor_Vendors(SHOP, nil, { owned = true })
	eq(#all, 2)
	eq(all[1].vendor, "Lars")
	eq(all[1].zone, "Dornogal")
	eq(all[1].total, 2)
	eq(all[1].owned, 1)
	eq(all[1].missing, 1)
	eq(all[1].entries[1].name, "Banner", "sorted by name")
	eq(all[2].vendor, "Mira")
	eq(all[2].total, 2, "a decor several vendors sell is under each")
	local missing = ns.Decor_Vendors(SHOP, nil, {})
	eq(#missing, 1, "a vendor you have everything from is left out")
	eq(missing[1].vendor, "Lars")
	eq(#missing[1].entries, 2, "but a vendor's list keeps what you have")
end)

test("learned vendors add what they were seen selling", function()
	local learned = { [900] = { name = "lars", items = { [104] = true, [999] = true } },
		[901] = { name = "Kesha", items = { [101] = true } }, [902] = { items = { [101] = true } } }
	local all = ns.Decor_Vendors(SHOP, learned, { owned = true })
	eq(#all, 3)
	eq(all[1].vendor, "Kesha")
	eq(all[1].total, 1)
	eq(all[2].vendor, "Lars")
	eq(all[2].total, 3, "the rug joins Lars (names match without case), an unknown item doesn't")
	eq(all[3].vendor, "Mira")
end)

test("decor by vendor matches the vendor, zone or any of their decor", function()
	local function Names(query)
		local names = {}
		for _, v in ipairs(ns.Decor_Vendors(SHOP, nil, { owned = true, query = query })) do
			names[#names + 1] = v.vendor
		end
		return table.concat(names, ",")
	end
	eq(Names("mira"), "Mira")
	eq(Names("hallow"), "Mira")
	eq(Names("banner"), "Lars,Mira")
	eq(Names("oak"), "Lars")
	eq(Names("nothing"), "")
	local lars = ns.Decor_Vendors(SHOP, nil, { owned = true, query = "oak" })[1]
	eq(#lars.entries, 2, "a matching vendor lists everything they sell")
end)

test("the cost at a vendor", function()
	local e = { cost = "5g", vendors = { { name = "Lars", cost = "5g" }, { name = "Mira", cost = "9g" }, { name = "Kesha" } } }
	eq(ns.Decor_CostAt(e, "mira"), "9g")
	eq(ns.Decor_CostAt(e, "kesha"), "5g", "a vendor line without a cost falls back to the first")
	eq(ns.Decor_CostAt({}, "lars"), nil)
end)

test("counts per source", function()
	local c = ns.Decor_Counts(ENTRIES)
	eq(c.total, 8)
	eq(c.owned, 2)
	eq(c.missing, 6)
	eq(c.by.vendor.total, 5)
	eq(c.by.vendor.missing, 4)
	eq(c.by.other.total, 1)
	eq(ns.Decor_CollectedText(c), "2 of 8 collected")
	local lines = ns.Decor_ScanLines(c)
	eq(lines[1], "Vendors: 4 missing, 1 collected")
	eq(#lines, 4)
end)

test("vendors here: missing only, most first", function()
	local set = ns.Decor_NameSet({ "Dornogal", "", "  ", nil })
	eq(set.dornogal, "Dornogal")
	local vendors, total = ns.Decor_VendorsHere(ENTRIES, set)
	eq(total, 3)
	eq(#vendors, 2)
	eq(vendors[1].vendor, "Lars")
	eq(#vendors[1].entries, 2)
	eq(vendors[1].entries[1].name, "Bench")
	eq(vendors[2].vendor, "Mira")
	local none, n = ns.Decor_VendorsHere(ENTRIES, ns.Decor_NameSet({ "Stormwind City" }))
	eq(#none, 0)
	eq(n, 0)
end)

test("vendors here text", function()
	eq(ns.Decor_VendorsHereText({ {} }, 3), "Decor vendor here: 3 decor you're missing")
	eq(ns.Decor_VendorsHereText({ {}, {} }, 5), "Decor vendors here: 5 decor you're missing")
	eq(ns.Decor_VendorsHereText({}, 0), nil)
end)

test("source words", function()
	eq(ns.Decor_SourceWord("vendor"), "Vendor")
	eq(ns.Decor_SourceWord("nope"), "Other")
end)

test("npc ID from a GUID", function()
	eq(ns.Decor_NpcID("Creature-0-3767-2552-12345-219318-0000ABCDEF"), 219318)
	eq(ns.Decor_NpcID("Vehicle-0-3767-2552-12345-1234-0000ABCDEF"), 1234)
	eq(ns.Decor_NpcID("Player-1305-0ABCDEF1"), nil)
	eq(ns.Decor_NpcID(nil), nil)
end)

test("learning a vendor adds items and moves the spot", function()
	local vendors = {}
	eq(ns.Decor_LearnVendor(vendors, 7, { name = "Kesha", mapID = 2339, x = 0.5, y = 0.4, items = { 1, 2 }, now = 10 }),
		true)
	eq(ns.Decor_LearnVendor(vendors, 7, { name = "Kesha", mapID = 2339, x = 0.51, y = 0.41, items = { 3 }, now = 20 }),
		false)
	local v = vendors[7]
	eq(v.x, 0.51)
	eq(v.seen, 20)
	eq(v.items[1] and v.items[2] and v.items[3], true)
end)

test("vendor spot: by item first (latest seen), then by name", function()
	local vendors = {
		[1] = { name = "Lars Bronsmaelt", mapID = 2339, items = { [100] = true }, seen = 5 },
		[2] = { name = "Kesha", mapID = 2215, items = { [100] = true, [200] = true }, seen = 9 },
		[3] = { name = "Mira", mapID = 2248, items = {}, seen = 1 },
	}
	local id = ns.Decor_VendorSpot({ itemID = 100, vendor = "Lars Bronsmaelt" }, vendors)
	eq(id, 2) -- both sell it; the one seen last wins over the name
	eq((ns.Decor_VendorSpot({ itemID = 999, vendor = "mira" }, vendors)), 3)
	eq((ns.Decor_VendorSpot({ itemID = 999, vendor = "Aldric" }, vendors)), nil)
	eq((ns.Decor_VendorSpot({ vendor = "Kesha" }, vendors)), 2)
end)

test("learned items on a map", function()
	local vendors = {
		[1] = { mapID = 2339, items = { [100] = true } },
		[2] = { mapID = 2215, items = { [200] = true } },
	}
	local set = ns.Decor_LearnedItemsOn(vendors, 2339)
	eq(set[100], true)
	eq(set[200], nil)
	eq(next(ns.Decor_LearnedItemsOn(vendors, nil)), nil)
end)

test("what a click does", function()
	local vendorEntry = { source = "vendor", vendor = "Kesha" }
	eq(ns.Decor_Action(vendorEntry, { tracking = true, trackable = true, spot = true }), "stop")
	eq(ns.Decor_Action(vendorEntry, { trackable = true, spot = true }), "track")
	eq(ns.Decor_Action(vendorEntry, { spot = true }), "waypoint")
	eq(ns.Decor_Action(vendorEntry, {}), "learn")
	eq(ns.Decor_Action({ source = "drop" }, {}), "none")
end)

test("vendors here also match by learned spots", function()
	local entries = {
		{ id = 1, name = "Lamp", source = "vendor", vendor = "Kesha", zone = "Hallowfall", zones = { "hallowfall" },
			itemID = 100, owned = 0 },
		{ id = 2, name = "Chair", source = "vendor", vendor = "Mira", zones = {}, itemID = 200, owned = 0 },
	}
	local vendors, total = ns.Decor_VendorsHere(entries, ns.Decor_NameSet({ "Dornogal" }), { [200] = true })
	eq(total, 1)
	eq(vendors[1].vendor, "Mira")
	local _, none = ns.Decor_VendorsHere(entries, ns.Decor_NameSet({ "Dornogal" }))
	eq(none, 0)
end)

test("search skips the money icon in the source line", function()
	local e = { id = 1, name = "Isolation Painting", vendor = "Hesta Forlath", zone = "Silvermoon City",
		line = "Vendor: Hesta Forlath · 375|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" }
	assert(not ns.Decor_Matches(e, "gold"), "the icon's path isn't text")
	assert(not ns.Decor_Matches(e, "gold"))
	assert(ns.Decor_Matches(e, "hesta"))
	assert(ns.Decor_Matches(e, "375"))
end)

test("search fields, each on its own", function()
	local e = { id = 1, name = "Oak Chair", vendor = "Hesta Forlath", zone = "Silvermoon City",
		line = "Vendor: Hesta Forlath", raw = "|cFFFFD200Achievement: |rTwo Hundred Chairs" }
	assert(ns.Decor_Matches(e, "oak", { name = true }))
	assert(not ns.Decor_Matches(e, "hesta", { name = true }), "the vendor isn't the name")
	assert(ns.Decor_Matches(e, "hesta", { vendor = true }))
	assert(not ns.Decor_Matches(e, "silvermoon", { name = true, vendor = true }))
	assert(ns.Decor_Matches(e, "silvermoon", { zone = true }))
	assert(not ns.Decor_Matches(e, "hundred", { name = true, vendor = true, zone = true }))
	assert(ns.Decor_Matches(e, "hundred", { source = true }), "the source covers the whole source text")
	assert(ns.Decor_Matches(e, "hundred"), "nil: every field")
	-- By vendor: the vendor's own name counts under vendor, its zone under zone.
	local shop = { { id = 2, name = "Lamp", vendors = { { name = "Kesha", zone = "Dornogal" } } } }
	eq(#ns.Decor_Vendors(shop, nil, { owned = true, query = "kesha" }), 1)
	eq(#ns.Decor_Vendors(shop, nil, { owned = true, query = "kesha", fields = { name = true } }), 0)
	eq(#ns.Decor_Vendors(shop, nil, { owned = true, query = "dornogal", fields = { zone = true } }), 1)
	eq(#ns.Decor_Vendors(shop, nil, { owned = true, query = "lamp", fields = { name = true } }), 1)
end)

test("the last search field stays on", function()
	local fields = { name = true, vendor = true }
	eq(ns.Decor_ToggleSearchField(fields, "vendor"), true)
	eq(fields.vendor, false)
	eq(ns.Decor_ToggleSearchField(fields, "name"), false)
	eq(fields.name, true)
	eq(ns.Decor_ToggleSearchField(fields, "zone"), true)
	eq(fields.zone, true)
end)

test("search through the whole source text", function()
	local raw = "|cFFFFD200Achievement: |rTwo Hundred Chairs|n|cFFFFD200Category: |rHousing"
	local e = { id = 1, name = "Oak Chair", line = "Achievement: Two Hundred Chairs", raw = raw }
	assert(not ns.Decor_Matches(e, "housing", { name = true, vendor = true, zone = true }), "the category line is only in the source")
	assert(ns.Decor_Matches(e, "housing"), "the full source text has it")
	assert(not ns.Decor_Matches(e, "ffd200"), "color codes aren't searched")
	local cur = { id = 2, name = "Lamp", raw = "|cFFFFD200Cost: |r50 |Hcurrency:3008|h[Valorstones]|h" }
	assert(ns.Decor_Matches(cur, "valorstones"))
	local list = ns.Decor_List({ e, cur }, { query = "valorstones", owned = true })
	eq(#list, 1)
	eq(list[1].name, "Lamp")
	eq(#ns.Decor_List({ e, cur }, { query = "valorstones", owned = true, fields = { name = true, vendor = true, zone = true } }), 0)
	local vendors = ns.Decor_Vendors({ { id = 3, name = "Rug", vendors = { { name = "Kesha" } }, raw = raw } }, nil,
		{ query = "category", owned = true })
	eq(#vendors, 1)
end)

H.done()
