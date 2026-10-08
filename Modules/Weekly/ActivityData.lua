local addonName, ns = ...

-- Activities tab: pure logic (tested with plain Lua). Learned weekly quests (Collect.lua) grouped by their quest log
-- header, after a short hand-kept list per expansion for what never shows in the log. Quest IDs from Plumber's
-- tables (checked 2026-10-08): Coffer Key flags 91175-91178, Coffer Key Shard flags 84736-84739, "The Key to Success"
-- 84370 (account-wide), Worldsoul weekly quest line 5572.

ns.WEEKLY_ACTIVITIES = {
	[10] = {
		{ group = "Delves", entries = {
			{ label = "The Key to Success", quest = 84370, account = true },
			{ label = "Restored Coffer Keys", flags = { 91175, 91176, 91177, 91178 } },
			{ label = "Coffer Key Shards", flags = { 84736, 84737, 84738, 84739 } },
		} },
		{ group = "Dornogal", entries = {
			{ label = "Worldsoul weekly", questLine = 5572 },
		} },
	},
}

-- Currencies for the Resources list (shown when discovered), after the crests. From Plumber's War Within list.
ns.WEEKLY_RESOURCES = {
	[10] = { 3269, 3028, 3149, 2815, 3218, 3226, 3090, 3056, 2803, 2123, 2797 },
}

local OTHER = "Other weekly quests"

local function CuratedItem(e)
	local right, state
	if e.state == "done" then
		right, state = "done", "done"
	elseif e.of then
		right, state = ("%d/%d"):format(e.n or 0, e.of), (e.n or 0) >= e.of and "done" or "open"
	elseif e.state == "progress" then
		right, state = "in progress", "open"
	else
		right, state = "open", "open"
	end
	local left = e.title and ("%s: %s"):format(e.label, e.title) or e.label
	return { kind = "row", left = left, right = right, state = state }
end

-- curated: { { group, entries = { { label, state = "done" | "open" | "progress", n, of, title } } } } (the reader
-- fills the state); learned: db.quests; v: the character's view (v.quests[questID] = "log" | "done").
-- Returns { groups = { { title, items } }, hidden = n }; items use the board row schema, hidden counts done items
-- left out by hideCompleted.
function ns.Weekly_ActivityModel(curated, learned, v, hideCompleted)
	local groups, hidden = {}, 0
	local function Add(title, items)
		local kept = {}
		for _, item in ipairs(items) do
			if hideCompleted and item.state == "done" then
				hidden = hidden + 1
			else
				kept[#kept + 1] = item
			end
		end
		if #kept > 0 then
			groups[#groups + 1] = { title = title, items = kept }
		end
	end
	for _, g in ipairs(curated) do
		local items = {}
		for _, e in ipairs(g.entries) do
			items[#items + 1] = CuratedItem(e)
		end
		Add(g.group, items)
	end

	local byGroup, order = {}, {}
	for id, state in pairs(v.quests or {}) do
		local q = learned[id]
		if q then
			local title = q.group or OTHER
			if not byGroup[title] then
				byGroup[title] = {}
				order[#order + 1] = title
			end
			local done = state == "done"
			table.insert(byGroup[title], { kind = "row", left = q.title or ("Quest " .. id),
				right = done and "done" or "open", state = done and "done" or "open" })
		end
	end
	table.sort(order, function(a, b)
		if (a == OTHER) ~= (b == OTHER) then
			return b == OTHER
		end
		return a < b
	end)
	for _, title in ipairs(order) do
		table.sort(byGroup[title], function(a, b)
			return a.left < b.left
		end)
		Add(title, byGroup[title])
	end

	if #groups == 0 then
		local text = hidden > 0 and "Everything here is done this week."
			or "Nothing tracked yet. Weekly quests are learned when they're in your quest log."
		groups[1] = { title = "", items = { { kind = "row", left = text, state = hidden > 0 and "done" or "dim" } } }
	end
	return { groups = groups, hidden = hidden }
end
