local addonName, ns = ...

-- Settings layout: pure logic (no WoW API calls; unit-tested in tests/test_panel_layout.lua). The groups the
-- settings rail shows (a module's `category` is a group key), how option cards are dealt into columns, when a
-- dropdown becomes segmented buttons, what search matches (names, descriptions, option labels and tooltips) and which
-- shown() rows show. Drawn by Sidebar.lua, ModulePage.lua and Options.lua.

-- icon: a file ID (checked against the community listfile); nil = Tomte's own icon (ns.ICON).
-- short: the label under the icon on the rail, which is only about 60 pixels wide.
ns.PANEL_GROUPS = {
	{ key = "tomte", name = "Tomte", short = "Tomte", description = "The window, minimap buttons and Home." },
	{ key = "week", name = "Your week", short = "Week", icon = 134376,
		description = "What to do this week, on every character." },
	{ key = "quests", name = "Quests", short = "Quests", icon = 236672, -- achievement_quests_completed_daily_01
		description = "Quest givers, world quests and gold quests." },
	{ key = "gear", name = "Gear & loot", short = "Gear", icon = 132751,
		description = "Your gear, its upkeep, your loot and your looks." },
	{ key = "professions", name = "Professions & gold", short = "Profs", icon = 134708,
		description = "Gathering, fishing, materials, mail and gold." },
	{ key = "collections", name = "Collections", short = "Collect", icon = 1542848,
		description = "Mounts, pets, achievements, decor and holidays." },
	{ key = "travel", name = "Travel", short = "Travel", icon = 132261,
		description = "Flights, waypoints, mounts and teleports." },
	{ key = "social", name = "Groups & friends", short = "Groups", icon = 133471,
		description = "Instances, groups, friends and whispers." },
	{ key = "chat", name = "Chat", short = "Chat", icon = 2056011, -- ui_chat
		description = "Chat tabs, filters, tags, mentions and copying." },
	{ key = "interface", name = "Interface", short = "Interface", icon = 134063, -- inv_misc_gear_01
		description = "The cursor, graphics and other screen helpers." },
	{ key = "class", name = "Class & combat", short = "Class", icon = 135274,
		description = "Helpers for your class and your pet." },
	{ key = "ambience", name = "Ambience", short = "Ambience", icon = 133885,
		description = "AFK screen, moments, recaps, showcase and the casino." },
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

-- text must already be lower case; "" matches everything. Looks at the name, summary, description and group name,
-- and at the text labels, button texts and tooltips of the module's options (label functions aren't called: they
-- can read the game).
function ns.PanelLayout_Matches(module, groupName, text)
	if text == "" then
		return true
	end
	local function Has(s)
		return type(s) == "string" and s:lower():find(text, 1, true) ~= nil
	end
	if Has(module.name) or Has(module.summary) or Has(module.description) or Has(groupName) then
		return true
	end
	for _, spec in ipairs(type(module.options) == "table" and module.options or {}) do
		if Has(spec.label) or Has(spec.text) or Has(spec.tooltip) then
			return true
		end
	end
	return false
end

-- Which option rows with a shown() show now, as "1"/"0" in schema order (rows without shown() don't count). The
-- options page rebuilds when this changes.
function ns.PanelLayout_Visibility(options)
	local marks = {}
	for _, spec in ipairs(options or {}) do
		if spec.shown then
			marks[#marks + 1] = spec.shown() and "1" or "0"
		end
	end
	return table.concat(marks)
end

-- Setting previews (Preview.lua) ------------------------------------------------------------------------------

-- The scale a preview of w x h is drawn at in a box of at most maxW x maxH: real size when it fits, shrunk evenly when
-- it doesn't, never enlarged.
function ns.PanelLayout_PreviewScale(w, h, maxW, maxH)
	if not (w and h and w > 0 and h > 0) then
		return 1
	end
	return math.min(1, maxW / w, maxH / h)
end

-- The settings a preview draws with, other than the saved ones: { [key] = { value = v } } (wrapped, so false and nil
-- count as values). The row's own key takes the choice under the mouse (has: there is one). forceOn: the second try,
-- after the saved settings showed nothing because what the row is about is off: then the switch the preview needs
-- (needs, Preview_When), the switches the row hangs on (parentOf(key) -> its parent key, up the chain) and the row's
-- own switch (kind "checkbox") count as on, so a player deciding whether to turn something on sees what it gives.
function ns.PanelLayout_PreviewOverrides(key, kind, value, has, parentOf, forceOn, needs)
	local overrides = {}
	if forceOn then
		local seen = {}
		local function On(k)
			while k and not seen[k] do
				seen[k] = true
				overrides[k] = { value = true }
				k = parentOf(k)
			end
		end
		On(needs)
		On(key and parentOf(key))
		if key and kind == "checkbox" and not has then
			overrides[key] = { value = true }
		end
	end
	if key and has then
		overrides[key] = { value = value }
	end
	return overrides
end

-- get(key) for a preview: the override for key (PreviewOverrides), else read(key) (the saved setting).
function ns.PanelLayout_PreviewGetter(read, overrides)
	return function(key)
		local o = overrides[key]
		if o then
			return o.value
		end
		return read(key)
	end
end
