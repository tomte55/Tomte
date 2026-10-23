-- Run from the AddOns folder: lua Tomte/tests/test_dressup.lua
local ns = {}
assert(loadfile("Tomte/Modules/DressUp/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq, near = H.test, H.eq, H.near

test("slot bar lists each slot once, with names", function()
	local seen = {}
	for _, slot in ipairs(ns.DRESSUP_SLOTS) do
		if slot then
			assert(not seen[slot], "slot twice: " .. slot)
			seen[slot] = true
			assert(ns.DRESSUP_SLOT_NAMES[slot], "name for " .. slot)
		end
	end
	eq(seen[2] or false, false, "no neck")
	eq(seen[16], true, "main hand")
end)

test("FitScale takes a share of the screen, clamped", function()
	near(ns.DressUp_FitScale(0.8, 545, 1000), 800 / 545)
	near(ns.DressUp_FitScale(0.8, 545, 100), 0.6, "min")
	near(ns.DressUp_FitScale(0.8, 100, 10000), 3, "max")
	near(ns.DressUp_FitScale(0.8, 0, 1000), 1, "no height yet")
end)

test("source text and list lines", function()
	local names = { [1] = "Boss Drop", [2] = "Quest" }
	eq(ns.DressUp_SourceText(1, { encounter = "Ri'mok", instance = "Gate of the Setting Sun", difficulty = "Heroic" },
		names), "Ri'mok, Gate of the Setting Sun (Heroic)")
	eq(ns.DressUp_SourceText(1, { encounter = "A", instance = "B" }, names), "A, B")
	eq(ns.DressUp_SourceText(2, nil, names), "Quest")
	eq(ns.DressUp_SourceText(nil, nil, names), nil)
	eq(ns.DressUp_ListLine("Head", "Swarmcall Helm", "Quest"), "Head: Swarmcall Helm - Quest")
	eq(ns.DressUp_ListLine("Head", "Swarmcall Helm", nil), "Head: Swarmcall Helm")
	eq(ns.DressUp_ListLine("Head", nil, "Quest"), nil)
end)

test("FindByName: exact, then a unique start, then a unique part", function()
	local sets = { { name = "Red Robe" }, { name = "Red Robe Two" }, { name = "Blue Plate" }, { name = "Fishing" } }
	eq(ns.DressUp_FindByName(sets, "red robe").name, "Red Robe", "exact beats the longer start")
	eq(ns.DressUp_FindByName(sets, "  BLUE ").name, "Blue Plate", "start, any case, trimmed")
	eq(ns.DressUp_FindByName(sets, "fish").name, "Fishing")
	eq(ns.DressUp_FindByName(sets, "plate").name, "Blue Plate", "a part")
	local none, names = ns.DressUp_FindByName(sets, "red")
	eq(none, nil, "ambiguous")
	eq(#names, 2)
	local _, missing = ns.DressUp_FindByName(sets, "green")
	eq(#missing, 0)
	local _, empty = ns.DressUp_FindByName(sets, "")
	eq(#empty, 0, "empty query")
end)

test("ensemble counts each look once", function()
	local have, total = ns.DressUp_EnsembleCounts({
		{ appearanceID = 1, collected = true },
		{ appearanceID = 2, collected = false },
		{ appearanceID = 2, collected = true }, -- another piece with the same look
		{ appearanceID = 3, collected = false },
		{ collected = true }, -- no look: skipped
	})
	eq(have, 2)
	eq(total, 3)
	eq(select(2, ns.DressUp_EnsembleCounts({})), 0)
	local text, role = ns.DressUp_EnsembleLine(2, 3)
	eq(text, "2 of 3 appearances collected")
	eq(role, "accent")
	eq(select(2, ns.DressUp_EnsembleLine(0, 3)), "warning")
	eq(ns.DressUp_EnsembleLine(3, 3), "All 3 appearances collected")
	eq(ns.DressUp_EnsembleLine(0, 0), nil)
end)

test("catalyst look text", function()
	eq(ns.DressUp_LookText(nil), nil, "no look")
	eq(ns.DressUp_LookText(true), "Look collected")
	local text, role = ns.DressUp_LookText(false)
	eq(text, "New look")
	eq(role, "success")
end)

test("pending changes: only slots with something pending", function()
	local slots = {
		{ slot = 0, type = 0, options = { 0 } },
		{ slot = 12, type = 0, options = { 1, 2 } },
		{ slot = 12, type = 1, options = { 1, 2 } },
	}
	local viewed = {
		["0:0:0"] = { hasPending = true, transmogID = 100, displayType = 1 },
		["12:0:1"] = { hasPending = false, transmogID = 5, displayType = 1 },
		["12:0:2"] = { hasPending = true, transmogID = 200, displayType = 3 },
	}
	local list = ns.DressUp_PendingChanges(slots, function(slot, kind, option)
		return viewed[slot .. ":" .. kind .. ":" .. option]
	end)
	eq(#list, 2)
	eq(list[1].transmogID, 100)
	eq(list[2].slot, 12)
	eq(list[2].option, 2)
	eq(list[2].displayType, 3)
	eq(ns.DressUp_PendingChanges(slots, function() return nil end), nil, "nothing pending")
end)

test("titles: filter, search and sort", function()
	local titles = {
		{ id = 2, name = "Corporal ", known = true },
		{ id = 36, name = ", Champion of the Naaru", known = false },
		{ id = 5, name = "the Patient", known = true },
		{ id = 9, name = "Jenkins", known = false },
		{ id = 7, name = "   ", known = true }, -- no name: left out
	}
	local owned = ns.DressUp_FilterTitles(titles, "", "owned")
	eq(#owned, 2)
	eq(owned[1].name, "Corporal", "trimmed, sorted")
	eq(owned[2].name, "the Patient")
	local missing = ns.DressUp_FilterTitles(titles, "", "missing")
	eq(#missing, 2)
	eq(missing[1].known, false)
	eq(#ns.DressUp_FilterTitles(titles, "", "all"), 4)
	local found = ns.DressUp_FilterTitles(titles, "NAARU", "all")
	eq(#found, 1)
	eq(found[1].id, 36)
	eq(#ns.DressUp_FilterTitles(titles, "naaru", "owned"), 0, "search within the filter")
end)

H.done()
