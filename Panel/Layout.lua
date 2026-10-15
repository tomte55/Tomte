local addonName, ns = ...

-- Settings layout: pure logic (no WoW API calls; unit-tested in tests/test_panel_layout.lua). The groups the
-- settings rail shows (a module's `category` is a group key), how option cards are dealt into columns, when a
-- dropdown becomes segmented buttons, and what search matches. Drawn by Sidebar.lua, ModulePage.lua and Options.lua.

-- icon: a file ID (checked against the community listfile); nil = Tomte's own icon (ns.ICON).
-- short: the label under the icon on the rail, which is only about 60 pixels wide.
ns.PANEL_GROUPS = {
	{ key = "tomte", name = "Tomte", short = "Tomte", description = "The window, minimap buttons and Home." },
	{ key = "week", name = "Your week", short = "Week", icon = 134376,
		description = "What to do this week, on every character." },
	{ key = "gear", name = "Gear", short = "Gear", icon = 132751, description = "Your gear, its upkeep and your looks." },
	{ key = "professions", name = "Professions & gold", short = "Profs", icon = 134708,
		description = "Gathering, fishing, materials and gold." },
	{ key = "collections", name = "Collections", short = "Collect", icon = 1542848,
		description = "Mounts, pets, achievements and holidays." },
	{ key = "travel", name = "Travel", short = "Travel", icon = 132261,
		description = "Flights, waypoints, mounts and teleports." },
	{ key = "social", name = "Social & chat", short = "Social", icon = 133471,
		description = "Friends, whispers, groups and chat." },
	{ key = "ambience", name = "Ambience", short = "Ambience", icon = 133885,
		description = "AFK screen, moments and session recaps." },
	{ key = "class", name = "Class & combat", short = "Class", icon = 135274,
		description = "Helpers for your class and your pet." },
}

local byKey = {}
for _, group in ipairs(ns.PANEL_GROUPS) do
	byKey[group.key] = group
end

function ns.PanelLayout_Group(key)
	return byKey[key]
end

-- 2 when two columns of at least minColumn fit in width (with gap between them) and there is more than one card.
function ns.PanelLayout_Columns(width, gap, minColumn, cards)
	if (cards or 2) < 2 then
		return 1
	end
	return (width - gap) / 2 >= minColumn and 2 or 1
end

-- Columns, card width (at most maxCard, so a control stays near its label on a wide window) and the width the cards
-- take together.
function ns.PanelLayout_Cards(width, gap, minColumn, maxCard, cards)
	local columns = ns.PanelLayout_Columns(width, gap, minColumn, cards)
	local cardW = columns == 2 and math.floor((width - gap) / 2) or width
	cardW = math.min(cardW, maxCard)
	return columns, cardW, columns * cardW + (columns - 1) * gap
end

-- Cards in order, each into the shorter column (ties go left), gap between cards. Returns places[i] = { column, y }
-- and the height of the taller column.
function ns.PanelLayout_Deal(heights, columns, gap)
	local tops = {}
	for c = 1, columns do
		tops[c] = 0
	end
	local places = {}
	for i, h in ipairs(heights) do
		local column = 1
		for c = 2, columns do
			if tops[c] < tops[column] then
				column = c
			end
		end
		places[i] = { column = column, y = tops[column] }
		tops[column] = tops[column] + h + gap
	end
	local total = 0
	for c = 1, columns do
		total = math.max(total, tops[c] > 0 and tops[c] - gap or 0)
	end
	return places, total
end

-- Segmented buttons instead of a dropdown: 2 to maxChoices choices whose label widths (padding included) add up to
-- at most max.
function ns.PanelLayout_UseSegments(widths, max, maxChoices)
	if #widths < 2 or #widths > maxChoices then
		return false
	end
	local sum = 0
	for _, w in ipairs(widths) do
		sum = sum + w
	end
	return sum <= max
end

-- text must already be lower case; "" matches everything. Looks at the name, summary, description and group name.
function ns.PanelLayout_Matches(module, groupName, text)
	if text == "" then
		return true
	end
	for _, s in ipairs({ module.name or "", module.summary or "", module.description or "", groupName or "" }) do
		if s:lower():find(text, 1, true) then
			return true
		end
	end
	return false
end
