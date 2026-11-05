-- Run from the AddOns folder: lua Tomte/tests/test_changes.lua
local ns = {}
assert(loadfile("Tomte/Core/ChangesData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("versions compare by number", function()
	eq(ns.Changes_Compare("1.24.0", "1.23.0"), 1)
	eq(ns.Changes_Compare("1.9.0", "1.10.0"), -1, "not as text")
	eq(ns.Changes_Compare("1.24.0", "1.24.0"), 0)
	eq(ns.Changes_Compare("1.24", "1.24.0"), 0, "a missing part is 0")
	eq(ns.Changes_Compare("2.0.0", "1.99.9"), 1)
end)

local LIST = {
	{ version = "1.26.0" }, -- written ahead of a release: not shown before the TOC says so
	{ version = "1.25.1" },
	{ version = "1.25.0" },
	{ version = "1.24.0" },
}

local function versions(list)
	local out = {}
	for i, e in ipairs(list) do
		out[i] = e.version
	end
	return table.concat(out, " ")
end

test("after an update: every release since the last one seen, newest first", function()
	eq(versions(ns.Changes_ToShow(LIST, "1.24.0", "1.25.1")), "1.25.1 1.25.0")
	eq(versions(ns.Changes_ToShow(LIST, "1.25.0", "1.25.1")), "1.25.1")
end)

test("nothing new, or nothing seen yet", function()
	eq(#ns.Changes_ToShow(LIST, "1.25.1", "1.25.1"), 0, "same version")
	eq(#ns.Changes_ToShow(LIST, "1.26.0", "1.25.1"), 0, "a newer one seen (went back a version)")
	eq(versions(ns.Changes_ToShow(LIST, nil, "1.25.1")), "1.25.1 1.25.0 1.24.0",
		"updating from before it remembered: every release up to this one")
	eq(#ns.Changes_ToShow(LIST, nil, "1.23.0"), 0, "a version without highlights")
end)

test("every release's lines name a module or a label, and have text", function()
	for _, entry in ipairs(ns.CHANGES) do
		assert(entry.version and entry.date, "version and date")
		for _, group in ipairs({ "new", "improved", "fixed" }) do
			for _, line in ipairs(entry[group] or {}) do
				assert((line.module or line.label) and line.text and #line.text > 0, entry.version .. " " .. group)
			end
		end
	end
end)

H.done()
