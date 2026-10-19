-- Run from the AddOns folder: lua Tomte/tests/test_check.lua
local ns = {}
assert(loadfile("Tomte/Core/CheckData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("ContentKind maps instance types", function()
	eq(ns.Check_ContentKind("party", 8), "dungeon")
	eq(ns.Check_ContentKind("raid", 16), "raid")
	eq(ns.Check_ContentKind("scenario", 208), "delve")
	eq(ns.Check_ContentKind("scenario", 12), nil, "other scenarios")
	eq(ns.Check_ContentKind("none", 0), nil, "open world")
	eq(ns.Check_ContentKind("pvp", 0), nil, "battlegrounds")
	eq(ns.Check_ContentKind(nil, nil), nil)
end)

H.done()
