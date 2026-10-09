-- Run from the AddOns folder: lua Tomte/tests/test_raids.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/WarWithin/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Weekly.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Weekly/RaidData.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local RAIDS = {
	{ id = 1302, name = "Manaforge Omega", mapID = 2810, bosses = { { name = "Plexus Sentinel", encounterID = 3129 },
		{ name = "Loom'ithar", encounterID = 3131 } } },
	{ id = 1296, name = "Liberation of Undermine", mapID = 2769, bosses = { { name = "Vexie", encounterID = 3009 } } },
}

local function Killed(mapID, encounterID, difficultyID)
	return encounterID == 3129 and (difficultyID == 14 or difficultyID == 15)
end

test("raid headers with totals per difficulty, bosses with dots", function()
	local items = ns.Weekly_RaidModel(RAIDS, Killed, {})
	eq(#items, 5)
	eq(items[1].kind, "raid")
	eq(items[1].name, "Manaforge Omega")
	eq(items[1].totals[1], "0/2", "LFR")
	eq(items[1].totals[2], "1/2", "Normal")
	eq(items[1].totals[3], "1/2", "Heroic")
	eq(items[1].totals[4], "0/2", "Mythic")
	eq(items[2].kind, "boss")
	eq(items[2].dots[2], true)
	eq(items[2].dots[4], false)
	eq(items[3].dots[2], false)
	eq(items[4].totals[2], "0/1")
end)

test("a collapsed raid keeps its header and totals only", function()
	local items = ns.Weekly_RaidModel(RAIDS, Killed, { [1302] = true })
	eq(#items, 3)
	eq(items[1].collapsed, true)
	eq(items[1].totals[2], "1/2", "totals still counted")
	eq(items[2].kind, "raid")
end)

test("no raids", function()
	eq(#ns.Weekly_RaidModel({}, Killed, {}), 0)
end)

test("raid order: the hand-kept order, newer journal raids on top, world bosses already left out", function()
	local listed = { 1302, 1296, 1273 }
	eq(table.concat(ns.Weekly_RaidOrder({ 1273, 1296, 1302 }, listed), ","), "1302,1296,1273", "same raids: list order")
	eq(table.concat(ns.Weekly_RaidOrder({ 1273, 1296, 1302, 1400 }, listed), ","), "1400,1302,1296,1273", "a newer one")
	eq(table.concat(ns.Weekly_RaidOrder({ 1296, 1302 }, listed), ","), "1302,1296", "journal lacks one")
	eq(table.concat(ns.Weekly_RaidOrder(nil, listed), ","), "1302,1296,1273", "no journal: the list")
	eq(table.concat(ns.Weekly_RaidOrder({}, listed), ","), "1302,1296,1273", "empty journal: the list")
	eq(table.concat(ns.Weekly_RaidOrder({ 1305, 1308 }, nil), ","), "1308,1305", "no list: journal, newest first")
	eq(#ns.Weekly_RaidOrder(nil, nil), 0, "nothing")
end)

test("Midnight raid list", function()
	eq(#ns.Content_Get(11, "raids"), 6)
end)

test("War Within raid list and four difficulties", function()
	eq(ns.Content_Get(10, "raids")[1], 1302)
	eq(#ns.WEEKLY_RAID_DIFFICULTIES, 4)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
