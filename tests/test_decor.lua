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

H.done()
