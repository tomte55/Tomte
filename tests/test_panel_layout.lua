-- Run from the AddOns folder: lua Tomte/tests/test_panel_layout.lua
local ns = {}
assert(loadfile("Tomte/Panel/Layout.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("groups have unique keys, names and descriptions", function()
	local seen = {}
	for _, g in ipairs(ns.PANEL_GROUPS) do
		assert(not seen[g.key], "duplicate " .. g.key)
		seen[g.key] = true
		assert(g.name and g.description, g.key)
		eq(ns.PanelLayout_Group(g.key), g)
	end
	eq(ns.PANEL_GROUPS[1].key, "tomte", "Tomte is pinned first")
	eq(ns.PanelLayout_Group("General"), nil)
end)

test("two columns only when each column gets the minimum", function()
	eq(ns.PanelLayout_Columns(736, 16, 360, 3), 2)
	eq(ns.PanelLayout_Columns(735, 16, 360, 3), 1)
	eq(ns.PanelLayout_Columns(1400, 16, 360, 1), 1, "a single card uses the full width")
	eq(ns.PanelLayout_Columns(1400, 16, 360, 0), 1)
end)

test("dealing: each card into the shorter column, ties go left", function()
	local places, total = ns.PanelLayout_Deal({ 100, 50, 30, 40 }, 2, 10)
	eq(places[1].column, 1)
	eq(places[1].y, 0)
	eq(places[2].column, 2)
	eq(places[3].column, 2, "right column is shorter (60 < 110)")
	eq(places[3].y, 60)
	eq(places[4].column, 2, "100 < 110")
	eq(places[4].y, 100)
	eq(total, 140)
end)

test("dealing into one column stacks in order", function()
	local places, total = ns.PanelLayout_Deal({ 20, 30 }, 1, 10)
	eq(places[2].column, 1)
	eq(places[2].y, 30)
	eq(total, 60)
	local _, empty = ns.PanelLayout_Deal({}, 2, 10)
	eq(empty, 0)
end)

test("segments: 2-3 choices that fit", function()
	eq(ns.PanelLayout_UseSegments({ 60, 70 }, 170, 3), true)
	eq(ns.PanelLayout_UseSegments({ 60, 70, 40 }, 170, 3), true)
	eq(ns.PanelLayout_UseSegments({ 60, 70, 41 }, 170, 3), false, "too wide")
	eq(ns.PanelLayout_UseSegments({ 20, 20, 20, 20 }, 170, 3), false, "too many")
	eq(ns.PanelLayout_UseSegments({ 20 }, 170, 3), false, "one choice stays a dropdown")
end)

test("search matches name, summary, description and group", function()
	local m = { name = "Flight Timer", summary = "Counts down taxi flights.", description = "Remembers each leg." }
	eq(ns.PanelLayout_Matches(m, "Travel", ""), true)
	eq(ns.PanelLayout_Matches(m, "Travel", "flight t"), true)
	eq(ns.PanelLayout_Matches(m, "Travel", "taxi"), true)
	eq(ns.PanelLayout_Matches(m, "Travel", "each leg"), true)
	eq(ns.PanelLayout_Matches(m, "Travel", "travel"), true)
	eq(ns.PanelLayout_Matches(m, "Travel", "mount"), false)
	eq(ns.PanelLayout_Matches({ name = "X" }, nil, "x"), true, "missing fields are fine")
end)

-- Every module registered by a file in the TOC names a known group and has an icon and a summary.
test("every module has a known group, an icon and a summary", function()
	local files = 0
	for line in io.lines("Tomte/Tomte.toc") do
		local file = line:match("^([%w_/\\]+%.lua)%s*$")
		if file then
			local f = assert(io.open("Tomte/" .. file:gsub("\\", "/"), "rb"))
			local text = f:read("*a")
			f:close()
			if text:find("ns.RegisterModule(", 1, true) and not file:find("^Core") then
				files = files + 1
				local lines = {}
				for l in (text .. "\n"):gmatch("([^\n]*)\n") do
					lines[#lines + 1] = l
				end
				local found = 0
				for i, l in ipairs(lines) do
					local key = l:match('^%s*category = "([^"]+)"')
					if key then
						found = found + 1
						assert(ns.PanelLayout_Group(key), file .. ": unknown group " .. key)
						local icon, summary
						for j = math.max(1, i - 12), math.min(#lines, i + 12) do
							icon = icon or lines[j]:match("^%s*icon = %S")
							summary = summary or lines[j]:match('^%s*summary = "')
						end
						assert(icon, file .. ": no icon near its category")
						assert(summary, file .. ": no summary near its category")
					end
				end
				assert(found > 0, file .. ": registers a module without a category line")
			end
		end
	end
	assert(files >= 30, "found only " .. files .. " module files")
end)

H.done()
