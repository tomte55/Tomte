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
	eq(#ns.PANEL_GROUPS, 12)
end)

-- The rail's label is about 60 pixels wide: one short word.
test("short labels are one word of at most 9 letters", function()
	for _, g in ipairs(ns.PANEL_GROUPS) do
		assert(g.short and g.short:match("^%a+$") and #g.short <= 9, g.key .. ": " .. tostring(g.short))
	end
end)

test("two columns only when each column gets the minimum", function()
	eq(ns.PanelLayout_Columns(736, 16, 360, 3), 2)
	eq(ns.PanelLayout_Columns(735, 16, 360, 3), 1)
	eq(ns.PanelLayout_Columns(1400, 16, 360, 1), 1, "a single card uses the full width")
	eq(ns.PanelLayout_Columns(1400, 16, 360, 0), 1)
end)

test("cards are capped so controls stay near their labels", function()
	local columns, cardW, total = ns.PanelLayout_Cards(1400, 14, 360, 540, 3)
	eq(columns, 2)
	eq(cardW, 540)
	eq(total, 1094)
	columns, cardW, total = ns.PanelLayout_Cards(1400, 14, 360, 540, 1)
	eq(columns, 1, "one card")
	eq(cardW, 540)
	eq(total, 540)
	columns, cardW, total = ns.PanelLayout_Cards(800, 14, 360, 540, 3)
	eq(cardW, 393, "two columns share a narrower page")
	eq(total, 800)
	columns, cardW = ns.PanelLayout_Cards(600, 14, 360, 540, 3)
	eq(columns, 1)
	eq(cardW, 540)
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
test("search also finds a module by its options' labels, button texts and tooltips", function()
	local m = { name = "Gathering", options = {
		{ type = "header", label = "Route" },
		{ type = "checkbox", key = "recordNodes", label = "Remember node spots", tooltip = "Saves where herbs grew." },
		{ type = "button", label = function()
			return "dynamic"
		end, text = "Clear spots" },
	} }
	eq(ns.PanelLayout_Matches(m, "Professions", "node spots"), true, "label")
	eq(ns.PanelLayout_Matches(m, "Professions", "herbs"), true, "tooltip")
	eq(ns.PanelLayout_Matches(m, "Professions", "clear spots"), true, "button text")
	eq(ns.PanelLayout_Matches(m, "Professions", "route"), true, "header")
	eq(ns.PanelLayout_Matches(m, "Professions", "dynamic"), false, "label functions aren't called")
	eq(ns.PanelLayout_Matches({ name = "X", options = "not a table" }, nil, "y"), false)
end)
test("Visibility marks each shown() row, in order", function()
	local open = true
	local options = {
		{ type = "checkbox", key = "a", label = "A" },
		{ type = "button", label = "B", shown = function()
			return open
		end },
		{ type = "slider", key = "c", label = "C", shown = function()
			return nil
		end },
	}
	eq(ns.PanelLayout_Visibility(options), "10")
	open = false
	eq(ns.PanelLayout_Visibility(options), "00")
	eq(ns.PanelLayout_Visibility(nil), "")
	eq(ns.PanelLayout_Visibility({ { label = "plain" } }), "", "rows without shown() don't count")
end)
test("PreviewScale keeps real size when it fits and shrinks evenly when not", function()
	eq(ns.PanelLayout_PreviewScale(300, 200, 400, 300), 1, "fits")
	eq(ns.PanelLayout_PreviewScale(800, 200, 400, 300), 0.5, "too wide")
	eq(ns.PanelLayout_PreviewScale(200, 600, 400, 300), 0.5, "too tall")
	eq(ns.PanelLayout_PreviewScale(800, 900, 400, 300), 1 / 3, "the tighter side wins")
	eq(ns.PanelLayout_PreviewScale(0, 100, 400, 300), 1, "nothing drawn")
	eq(ns.PanelLayout_PreviewScale(nil, nil, 400, 300), 1)
end)
test("PreviewOverrides: the saved settings first, then what the row needs turned on", function()
	local parents = { size = "strip", strip = "enabled" }
	local function parentOf(key)
		return parents[key]
	end
	local function none()
		return nil
	end
	local o = ns.PanelLayout_PreviewOverrides("look", "dropdown", "tiles", true, none)
	eq(o.look.value, "tiles", "the hovered choice")
	o = ns.PanelLayout_PreviewOverrides("look", "dropdown", nil, false, none)
	eq(o.look, nil, "no hovered choice: the saved value")
	o = ns.PanelLayout_PreviewOverrides("growUp", "checkbox", nil, false, none)
	eq(o.growUp, nil, "first try: a switch as it is, so clicking it changes the picture")
	o = ns.PanelLayout_PreviewOverrides("size", "slider", nil, false, parentOf)
	eq(next(o), nil, "first try: parents as they are")
	o = ns.PanelLayout_PreviewOverrides("growUp", "checkbox", nil, false, none, true)
	eq(o.growUp.value, true, "forced: the switch on")
	o = ns.PanelLayout_PreviewOverrides("growUp", "checkbox", false, true, none, true)
	eq(o.growUp.value, false, "a hovered choice wins")
	o = ns.PanelLayout_PreviewOverrides("size", "slider", nil, false, parentOf, true)
	eq(o.strip.value, true, "forced: the parent switch on")
	eq(o.enabled.value, true, "and its parent")
	eq(o.size, nil, "a slider keeps its saved value")
	o = ns.PanelLayout_PreviewOverrides("scale", "slider", nil, false, parentOf, true, "strip")
	eq(o.strip.value, true, "forced: the switch the preview needs")
	eq(o.enabled.value, true, "and its parents")
	o = ns.PanelLayout_PreviewOverrides(nil, "button", nil, false, parentOf, true)
	eq(next(o), nil, "a row without a key")
	local loop = { a = "b", b = "a" }
	o = ns.PanelLayout_PreviewOverrides("a", "slider", nil, false, function(k)
		return loop[k]
	end, true)
	eq(o.b.value, true, "a parent loop ends")
end)
test("PreviewGetter answers overrides first, then the saved value", function()
	local saved = { look = "strips", growUp = true }
	local function read(key)
		return saved[key]
	end
	local get = ns.PanelLayout_PreviewGetter(read, { look = { value = "tiles" }, growUp = { value = false } })
	eq(get("look"), "tiles")
	eq(get("growUp"), false, "false is a value")
	get = ns.PanelLayout_PreviewGetter(read, { look = { value = nil } })
	eq(get("look"), nil, "nil is a value")
	eq(get("growUp"), true, "other keys read the saved value")
end)

H.done()
