local addonName, ns = ...

-- Item counts: pure logic (no WoW API calls; unit-tested in tests/test_counts.lua): the record of what every
-- character owns, counted per item, and the tooltip's lines. Collect.lua fills the record, Tooltip.lua shows it,
-- Counts.lua registers the module; Alts and Bags ask through ns.Counts_* functions.
--
-- The record (TomteDB.counts):
--   chars[guid] = { name, realm, class, money, at, bankAt (when the bank was read), places = { [place] =
--                   { { id, link, count } ... } } }
--     place: "bags", "bank", "mail", "equipped"
--   warband = { at, items = { { id, link, count } ... } }
--   guilds[key] = { name, at, tabs = { [tab] = { { id, link, count } ... } } }   key: "Guild-Realm"

ns.COUNTS_PLACES = { "bags", "bank", "mail", "equipped" }
-- How each place reads in a tooltip line.
local PLACE_NAMES = { bags = "bags", bank = "bank", mail = "mail", equipped = "worn" }
local MAX_CHAR_LINES = 8 -- characters listed in a tooltip; the rest are summed in one line

-- The record counted per item: [itemID] = { chars = { [guid] = { [place] = n } }, warband = n, guilds = { [key] = n } }.
function ns.Counts_Index(record)
	local index = {}
	local function Entry(id)
		local e = index[id]
		if not e then
			e = { chars = {}, warband = 0, guilds = {} }
			index[id] = e
		end
		return e
	end
	for guid, char in pairs(record.chars or {}) do
		for place, items in pairs(char.places or {}) do
			for _, item in ipairs(items) do
				if item.id then
					local e = Entry(item.id)
					local byPlace = e.chars[guid] or {}
					e.chars[guid] = byPlace
					byPlace[place] = (byPlace[place] or 0) + (item.count or 1)
				end
			end
		end
	end
	for _, item in ipairs(record.warband and record.warband.items or {}) do
		if item.id then
			local e = Entry(item.id)
			e.warband = e.warband + (item.count or 1)
		end
	end
	for key, guild in pairs(record.guilds or {}) do
		for _, items in pairs(guild.tabs or {}) do
			for _, item in ipairs(items) do
				if item.id then
					local e = Entry(item.id)
					e.guilds[key] = (e.guilds[key] or 0) + (item.count or 1)
				end
			end
		end
	end
	return index
end

-- A saved link per item ID ({ [id] = link }), the first one found: other characters' items, for reading their
-- tooltips (Bags' Find on all characters). Items saved without a link are left out.
function ns.Counts_Links(record)
	local links = {}
	local function Add(items)
		for _, item in ipairs(items or {}) do
			if item.id and item.link and not links[item.id] then
				links[item.id] = item.link
			end
		end
	end
	for _, char in pairs(record.chars or {}) do
		for _, items in pairs(char.places or {}) do
			Add(items)
		end
	end
	Add(record.warband and record.warband.items)
	for _, guild in pairs(record.guilds or {}) do
		for _, items in pairs(guild.tabs or {}) do
			Add(items)
		end
	end
	return links
end

-- One item's counts as rows, most first (the current character, me, first among equals): { kind = "char", guid,
-- name, class, total, places = { [place] = n } }, then { kind = "warband", total }, then { kind = "guild", name,
-- total }. Also the grand total.
function ns.Counts_Rows(entry, record, me)
	local rows, total = {}, 0
	if not entry then
		return rows, 0
	end
	local chars = {}
	for guid, places in pairs(entry.chars) do
		local n = 0
		for _, count in pairs(places) do
			n = n + count
		end
		if n > 0 then
			local c = record.chars and record.chars[guid] or {}
			chars[#chars + 1] = { kind = "char", guid = guid, name = c.name or "?", class = c.class, total = n,
				places = places }
			total = total + n
		end
	end
	table.sort(chars, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		if (a.guid == me) ~= (b.guid == me) then
			return a.guid == me
		end
		return a.name < b.name
	end)
	for _, row in ipairs(chars) do
		rows[#rows + 1] = row
	end
	if entry.warband > 0 then
		rows[#rows + 1] = { kind = "warband", total = entry.warband }
		total = total + entry.warband
	end
	local guilds = {}
	for key, n in pairs(entry.guilds) do
		if n > 0 then
			local g = record.guilds and record.guilds[key] or {}
			guilds[#guilds + 1] = { kind = "guild", name = g.name or key, total = n }
			total = total + n
		end
	end
	table.sort(guilds, function(a, b)
		return a.name < b.name
	end)
	for _, row in ipairs(guilds) do
		rows[#rows + 1] = row
	end
	return rows, total
end

-- Where a character's count is: "bags 10, bank 2" in COUNTS_PLACES order; "" when it's all in one place.
function ns.Counts_PlacesText(places)
	local parts, n = {}, 0
	for _, place in ipairs(ns.COUNTS_PLACES) do
		if (places[place] or 0) > 0 then
			parts[#parts + 1] = ("%s %d"):format(PLACE_NAMES[place], places[place])
			n = n + 1
		end
	end
	if n <= 1 then
		return ""
	end
	return table.concat(parts, ", ")
end

-- The tooltip's lines: { left, right, class (a character's class file name, or nil), role } for each row, at most
-- MAX_CHAR_LINES characters (the rest in an "and N more" line), and a Total line when more than one row counts.
function ns.Counts_TipLines(rows, total)
	local lines, shownChars, restChars, restCount = {}, 0, 0, 0
	for _, row in ipairs(rows) do
		if row.kind == "char" then
			if shownChars < MAX_CHAR_LINES then
				shownChars = shownChars + 1
				local where = ns.Counts_PlacesText(row.places)
				local right = where == "" and tostring(row.total) or ("%d (%s)"):format(row.total, where)
				if where == "" then
					for _, place in ipairs(ns.COUNTS_PLACES) do
						if (row.places[place] or 0) > 0 and place ~= "bags" then
							right = ("%d (%s)"):format(row.total, PLACE_NAMES[place])
						end
					end
				end
				lines[#lines + 1] = { left = row.name, right = right, class = row.class }
			else
				restChars, restCount = restChars + 1, restCount + row.total
			end
		elseif row.kind == "warband" then
			lines[#lines + 1] = { left = "Warband bank", right = tostring(row.total), role = "info" }
		elseif row.kind == "guild" then
			lines[#lines + 1] = { left = row.name, right = tostring(row.total), role = "success" }
		end
	end
	if restChars > 0 then
		table.insert(lines, shownChars + 1, { left = ("and %d more"):format(restChars), right = tostring(restCount),
			role = "textMuted" })
	end
	if #rows > 1 then
		lines[#lines + 1] = { left = "Total", right = tostring(total), role = "heading" }
	end
	return lines
end

-- For Alts' crafting materials: { { guid, where = place | "warband", n } } of one item.
function ns.Counts_Where(entry)
	local list = {}
	if not entry then
		return list
	end
	for guid, places in pairs(entry.chars) do
		for _, place in ipairs(ns.COUNTS_PLACES) do
			local n = places[place]
			if n and n > 0 then
				list[#list + 1] = { guid = guid, where = place, n = n }
			end
		end
	end
	if entry.warband > 0 then
		list[#list + 1] = { where = "warband", n = entry.warband }
	end
	return list
end
