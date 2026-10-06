local addonName, ns = ...

-- Next up: pure ranking (unit-tested with plain Lua). Sources are module.home entries of kind "next"; each returns
-- candidates { key, text, why, icon, right, state, bonus, onClick, stay }. The final score is the source's priority
-- (the user's setting, else the entry's own score) plus bonus/10 (0-9, the order inside one source).

-- lists: { { source = entry key, score = default priority, items = { candidates } } }
-- opts: { enabled = { [source] = false to skip }, priority = { [source] = 0-100 }, dismissed = { [key] = state|true },
--         mode = "login" | "change", limit, perSource (optional cap per source) }
-- "login": a dismissed key stays hidden. "change": it's hidden while its state is the one dismissed.
function ns.NextUp_Rank(lists, opts)
	local enabled, priority, dismissed = opts.enabled or {}, opts.priority or {}, opts.dismissed or {}
	local all, order = {}, {}
	for _, list in ipairs(lists) do
		if enabled[list.source] ~= false then
			local base = priority[list.source] or list.score or 50
			for _, c in ipairs(list.items or {}) do
				local gone = dismissed[c.key]
				if gone ~= nil and opts.mode == "change" then
					gone = gone == (c.state == nil and true or c.state)
				end
				if not gone then
					c.score = base + math.min(math.max(c.bonus or 0, 0), 9) / 10
					c.source = list.source
					all[#all + 1] = c
					order[c] = #all
				end
			end
		end
	end
	table.sort(all, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return order[a] < order[b]
	end)
	-- At most perSource from one source, so one busy source (achievements) can't fill the list.
	local limit, perSource = opts.limit or 5, opts.perSource
	local out, count = {}, {}
	for _, c in ipairs(all) do
		if #out >= limit then
			break
		end
		local n = count[c.source] or 0
		if not perSource or n < perSource then
			count[c.source] = n + 1
			out[#out + 1] = c
		end
	end
	return out
end

-- What a dismissal remembers for a candidate (its state, or true).
function ns.NextUp_DismissValue(c)
	if c.state == nil then
		return true
	end
	return c.state
end
