-- Run from the AddOns folder: lua Tomte/tests/test_nameplates.lua
local ns = {}
assert(loadfile("Tomte/Modules/Nameplates/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function title()
	return { kind = "title" }
end

local function player(mine)
	return { kind = "player", mine = mine }
end

local function obj(text, completed)
	return { kind = "objective", text = text, completed = completed }
end

test("Progress reads counts in any word order", function()
	eq(ns.Plates_Progress("3/8 Boars slain"), "3/8")
	eq(ns.Plates_Progress("Boars slain: 3 / 8"), "3/8")
	eq(ns.Plates_Progress("Sangliers tués : 0/10"), "0/10")
end)

test("Progress reads percentages", function()
	eq(ns.Plates_Progress("Slay boars (45%)"), "45%")
	eq(ns.Plates_Progress("Slay boars 45 %"), "45%")
end)

test("Progress is nil without a count", function()
	eq(ns.Plates_Progress("Speak to Aldric"), nil)
	eq(ns.Plates_Progress(nil), nil)
	eq(ns.Plates_Progress(12), nil)
end)

test("QuestState shows your first open objective", function()
	local s = ns.Plates_QuestState({ title(), obj("1/1 Tusk", true), obj("2/8 Boars slain", false) })
	eq(s.progress, "2/8")
	eq(s.party, false)
end)

test("QuestState is nil when every objective is done", function()
	eq(ns.Plates_QuestState({ title(), obj("8/8 Boars slain", true) }), nil)
	eq(ns.Plates_QuestState({}), nil)
	eq(ns.Plates_QuestState(nil), nil)
end)

test("QuestState skips other players' objectives unless asked", function()
	local lines = { title(), player(false), obj("1/5 Eggs", false), player(true), obj("5/5 Eggs", true) }
	eq(ns.Plates_QuestState(lines, false), nil)
	local s = ns.Plates_QuestState(lines, true)
	eq(s.progress, "1/5")
	eq(s.party, true)
end)

test("QuestState prefers yours over a group member's", function()
	local lines = { title(), player(false), obj("1/5 Eggs", false), player(true), obj("3/5 Eggs", false) }
	local s = ns.Plates_QuestState(lines, true)
	eq(s.progress, "3/5")
	eq(s.party, false)
end)

test("QuestState: a new title resets to your objectives", function()
	local lines = { title(), player(false), obj("1/5 Eggs", false), title(), obj("Find the cave", false) }
	local s = ns.Plates_QuestState(lines, false)
	eq(s.progress, nil)
	eq(s.party, false)
end)

test("ItemSets and MergeSets", function()
	local a = ns.Plates_ItemSets({ 837, 838 }, 206350)
	eq(a[837].item, 206350)
	eq(a[838].item, 206350)
	local m = ns.Plates_MergeSets({ a, { [900] = { item = 1 }, [838] = { item = 2 } } })
	eq(m[837].item, 206350)
	eq(m[838].item, 2)
	eq(m[900].item, 1)
	eq(next(ns.Plates_MergeSets({})), nil)
end)

test("Keyflame data counts Radiant Remnants", function()
	local m = ns.Plates_ItemSets(ns.PLATES_KEYFLAME_SETS, ns.PLATES_RADIANT_REMNANT)
	eq(m[837].item, 206350)
	eq(m[1081].item, 206350)
	eq(#ns.PLATES_KEYFLAME_SETS, 16)
end)

test("CastFraction runs up, channels run down", function()
	H.near(ns.Plates_CastFraction(1000, 3000, 2000), 0.5)
	H.near(ns.Plates_CastFraction(1000, 3000, 2500, true), 0.25)
	eq(ns.Plates_CastFraction(1000, 3000, 500), 0)
	eq(ns.Plates_CastFraction(1000, 3000, 9000), 1)
end)

test("CastFraction is nil for odd times", function()
	eq(ns.Plates_CastFraction(3000, 3000, 3000), nil)
	eq(ns.Plates_CastFraction(nil, 3000, 3000), nil)
end)

H.done()
