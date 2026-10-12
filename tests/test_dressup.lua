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

H.done()
