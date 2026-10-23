-- Run from the AddOns folder: lua Tomte/tests/test_summary.lua
local ns = {}
assert(loadfile("Tomte/Modules/Summary/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local TRACKS = {
	{ key = "raid", label = "Raid" },
	{ key = "dungeons", label = "Dungeons" },
	{ key = "world", label = "World" },
}
local DIFFS = { { id = 17, name = "LFR" }, { id = 14, name = "Normal" }, { id = 15, name = "Heroic" }, { id = 16, name = "Mythic" } }

local function slots(...)
	local out = {}
	for i, p in ipairs({ ... }) do
		out[i] = { progress = p[1], threshold = p[2] }
	end
	return out
end

test("vault counts unlocked slots and finds the next one per track", function()
	local v = ns.Summary_Vault({
		raid = slots({ 2, 2 }, { 2, 4 }, { 2, 6 }),
		dungeons = slots({ 8, 1 }, { 8, 4 }, { 8, 8 }),
		world = slots({ 0, 2 }, { 0, 4 }, { 0, 8 }),
	}, TRACKS)
	eq(v.unlocked, 4)
	eq(v.total, 9)
	eq(v.rows[1].unlocked, 1)
	eq(v.rows[1].nextSlot, 2)
	eq(v.rows[2].nextSlot, nil, "all open")
	eq(v.rows[3].nextSlot, 1)
	eq(ns.Summary_VaultLine(v), "Raid 1/3 · Dungeons 3/3 · World 0/3")
end)

test("vault without data has no line", function()
	local v = ns.Summary_Vault(nil, TRACKS)
	eq(v.total, 0)
	eq(ns.Summary_VaultLine(v), nil)
	eq(ns.Summary_HomeText(v, false), "Factions, vault, raids and crests")
	eq(ns.Summary_HomeText(v, true), "Great Vault rewards waiting")
end)

test("a zero threshold slot never counts as unlocked", function()
	local v = ns.Summary_Vault({ raid = slots({ 0, 0 }) }, TRACKS)
	eq(v.unlocked, 0)
	eq(v.rows[1].nextSlot, 1)
end)

test("raids list the difficulties with kills", function()
	local raids = { { id = 1, name = "Voidspire", mapID = 9, bosses = { { encounterID = 1 }, { encounterID = 2 } } },
		{ id = 2, name = "Dreamrift", mapID = 8, bosses = { { encounterID = 3 } } } }
	local killed = { ["9:1:14"] = true, ["9:2:14"] = true, ["9:1:15"] = true }
	local rows = ns.Summary_Raids(raids, function(mapID, enc, diff)
		return killed[mapID .. ":" .. enc .. ":" .. diff]
	end, DIFFS)
	eq(rows[1].text, "Normal 2/2 · Heroic 1/2")
	eq(rows[1].any, true)
	eq(rows[2].text, "No kills this week")
	eq(rows[2].any, false)
end)

test("world bosses come from the lockouts", function()
	local names = ns.Summary_WorldBosses({ { name = "Raid A", killed = 1 }, { name = "Big One", worldBoss = true } })
	eq(#names, 1)
	eq(names[1], "Big One")
end)

test("factions: renown only, paragon waiting first, maxed last", function()
	local list = ns.Summary_Factions({
		{ id = 1, name = "Zeta", renown = true, level = 5, max = 20, earned = 1250, threshold = 2500 },
		{ id = 2, name = "Alpha", renown = true, level = 20, max = 20 },
		{ id = 3, name = "Sub", parent = 1, level = 3 },
		{ id = 4, name = "Beta", renown = true, level = 20, max = 20, paragon = { value = 10, threshold = 10, pending = true } },
	})
	eq(#list, 3)
	eq(list[1].rec.name, "Beta")
	eq(list[2].rec.name, "Zeta")
	eq(list[2].frac, 0.5)
	eq(list[3].rec.name, "Alpha")
	eq(list[3].maxed, true)
	eq(list[3].frac, 1)
end)

test("activities keep open rows, drop the grey note, count the done ones", function()
	local acts = ns.Summary_Activities({ hidden = 2, groups = {
		{ title = "Delves", items = { { left = "Gnawing Void", right = "open", state = "open" } } },
		{ title = "", items = { { left = "Everything here is done this week.", state = "dim" } } },
	} })
	eq(acts.open, 1)
	eq(acts.done, 2)
	eq(acts.rows[1].group, "Delves")
	eq(acts.rows[1].right, "open")
end)

test("tooltip lines: vault waiting, vault, crests, paragon", function()
	local v = ns.Summary_Vault({ raid = slots({ 1, 1 }) }, TRACKS)
	local lines = ns.Summary_TooltipLines({ vault = v, vaultReady = true, crests = { { name = "Gilded", text = "40" } },
		factionsWaiting = 2 })
	eq(lines[1].text, "Great Vault rewards waiting")
	eq(lines[2].text, "Vault: Raid 1/1")
	eq(lines[3].text, "Gilded: 40")
	eq(lines[4].text, "2 paragon rewards are waiting")
	eq(ns.Summary_TooltipLines({})[1].text, "Nothing read yet")
end)

H.done()
