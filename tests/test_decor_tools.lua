-- Run from the AddOns folder: lua Tomte/tests/test_decor_tools.lua
local ns = {}
assert(loadfile("Tomte/Modules/Decor/ToolsData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("ClipAdd puts a decor on top, counts cuts and keeps the list short", function()
	local list = {}
	ns.DecorTools_ClipAdd(list, 1, false, 3)
	ns.DecorTools_ClipAdd(list, 2, true, 3)
	ns.DecorTools_ClipAdd(list, 3, false, 3)
	eq(list[1].id, 3)
	eq(list[2].cut, 1)
	ns.DecorTools_ClipAdd(list, 2, true, 3)
	eq(list[1].id, 2, "moved to the top")
	eq(list[1].cut, 2, "second cut")
	eq(#list, 3)
	ns.DecorTools_ClipAdd(list, 4, false, 3)
	eq(#list, 3, "oldest fell off")
	eq(list[3].id, 3)
end)

test("ClipPlaced lowers the cut count, never below 0; ClipRemove takes it out", function()
	local list = { { id = 5, cut = 1 }, { id = 6, cut = 0 } }
	ns.DecorTools_ClipPlaced(list, 5)
	ns.DecorTools_ClipPlaced(list, 5)
	eq(list[1].cut, 0)
	ns.DecorTools_ClipPlaced(list, 6)
	eq(list[2].cut, 0)
	ns.DecorTools_ClipRemove(list, 5)
	eq(#list, 1)
	eq(list[1].id, 6)
end)

test("RecentPush keeps newest first without repeats", function()
	local list = { 3, 2, 1 }
	ns.DecorTools_RecentPush(list, 1, 3)
	eq(table.concat(list, ","), "1,3,2")
	ns.DecorTools_RecentPush(list, 9, 3)
	eq(table.concat(list, ","), "9,1,3")
end)

test("SlotAction places a filled slot, binds an empty one while holding a decor", function()
	eq(ns.DecorTools_SlotAction(10, 20), "place")
	eq(ns.DecorTools_SlotAction(nil, 20), "bind")
	eq(ns.DecorTools_SlotAction(nil, nil), "none")
end)

test("RotateSteps: 90 degrees is six 15 degree steps, sign follows the direction", function()
	local n, sign = ns.DecorTools_RotateSteps(90)
	eq(n, 6)
	eq(sign, 1)
	n, sign = ns.DecorTools_RotateSteps(-45)
	eq(n, 3)
	eq(sign, -1)
	eq(ns.DecorTools_RotateSteps(0), 0)
	eq(ns.DecorTools_RotateSteps(20), 1, "rounds to the nearest step")
end)

test("PulseSeconds at 45 degrees per second", function()
	eq(ns.DecorTools_PulseSeconds(45), 1)
	eq(ns.DecorTools_PulseSeconds(-90), 2)
end)

test("TagToggle adds and removes; empty tags stay", function()
	local tags = {}
	eq(ns.DecorTools_TagToggle(tags, "Kitchen", 7), true)
	eq(tags.Kitchen[7], true)
	eq(ns.DecorTools_TagToggle(tags, "Kitchen", 7), false)
	eq(tags.Kitchen[7], nil)
	eq(type(tags.Kitchen), "table", "the tag stays")
end)

test("TagName trims and refuses empty names", function()
	eq(ns.DecorTools_TagName("  Garden  "), "Garden")
	eq(ns.DecorTools_TagName("   "), nil)
	eq(ns.DecorTools_TagName(nil), nil)
	eq(#ns.DecorTools_TagName(("x"):rep(50)), 30)
end)

test("SavedGroups: favorites first, tags by name, decor by name, empty ones out", function()
	local names = { [1] = "Chair", [2] = "Apple", [3] = "Bench" }
	local function nameOf(id)
		return names[id]
	end
	local groups = ns.DecorTools_SavedGroups({ [1] = true, [2] = true },
		{ zoo = { [3] = true }, Attic = { [1] = true }, empty = {} }, nameOf)
	eq(#groups, 3)
	eq(groups[1].title, "Favorites")
	eq(groups[1].ids[1], 2, "Apple before Chair")
	eq(groups[2].title, "Attic")
	eq(groups[2].tag, "Attic")
	eq(groups[3].title, "zoo")
end)

test("CountIDs and ShareEncode", function()
	local items = ns.DecorTools_CountIDs({ 5, 3, 5, 5 })
	eq(#items, 2)
	eq(items[1].id, 3)
	eq(items[2].count, 3)
	eq(ns.DecorTools_ShareEncode(items), "TomteDecor1:3,5x3")
end)

test("ShareDecode reads what ShareEncode writes and adds up repeats", function()
	local items = ns.DecorTools_ShareDecode("  TomteDecor1:3,5x3,3x2  ")
	eq(#items, 2)
	eq(items[1].id, 3)
	eq(items[1].count, 3)
	eq(items[2].count, 3)
end)

test("ShareDecode refuses other text with a reason", function()
	local items, why = ns.DecorTools_ShareDecode("ADT:abc")
	eq(items, nil)
	eq(type(why), "string")
	eq(ns.DecorTools_ShareDecode("TomteDecor1:"), nil, "empty")
	eq(ns.DecorTools_ShareDecode("TomteDecor1:12,abc"), nil, "bad part")
	eq(ns.DecorTools_ShareDecode(nil), nil)
end)

test("Matches is a plain, case-insensitive search", function()
	eq(ns.DecorTools_Matches("Wooden Chair", "chair"), true)
	eq(ns.DecorTools_Matches("Wooden Chair", " "), true, "empty matches all")
	eq(ns.DecorTools_Matches("Wooden Chair", "table"), false)
	eq(ns.DecorTools_Matches("Lamp (Blue)", "(blue"), true, "no patterns")
	eq(ns.DecorTools_Matches(nil, "x"), false)
end)

test("DestroyCount clamps to what can go and the run's most", function()
	eq(ns.DecorTools_DestroyCount("5", 3, 100), 3)
	eq(ns.DecorTools_DestroyCount(" 2 ", 10, 100), 2)
	eq(ns.DecorTools_DestroyCount("500", 1000, 100), 100)
	eq(ns.DecorTools_DestroyCount("0", 10, 100), nil)
	eq(ns.DecorTools_DestroyCount("two", 10, 100), nil)
end)

test("HintLine names the set keys only", function()
	local function keyText(k)
		return k:lower()
	end
	eq(ns.DecorTools_HintLine({ duplicate = "CTRL-D", copy = "", lock = "L" }, keyText), "ctrl-d another  ·  l lock")
	eq(ns.DecorTools_HintLine({ duplicate = "", copy = "" }, keyText), nil)
end)

H.done()
