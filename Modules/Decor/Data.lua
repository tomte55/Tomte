local addonName, ns = ...

-- Housing decor: pure logic (no WoW API calls; unit-tested in tests/test_decor.lua). What kind of source a decor's
-- catalog source text names (vendor, achievement, quest, drop, profession, other), the vendors, zones and costs in it,
-- the page's filtering, grouping and counts, decor by vendor, the vendors in your zone, the learned vendor spots, what
-- a click does and the tooltip line. The source text is read with
-- Collect here's parser (ns.Collect_ParseSource in Modules/Collect/Data.lua, looked up at call time): the catalog
-- writes the same labelled lines as the mount and pet journals ("Vendor: Name|nZone: Zone|nCost: 100").

-- Groups on the Decor page, in this order. title: the section heading; word: the short name on a row.
ns.DECOR_SOURCES = {
	{ key = "vendor", title = "Vendors", word = "Vendor" },
	{ key = "achievement", title = "Achievements", word = "Achievement" },
	{ key = "quest", title = "Quests", word = "Quest" },
	{ key = "drop", title = "Drops", word = "Drop" },
	{ key = "profession", title = "Professions", word = "Profession" },
	{ key = "other", title = "Other", word = "Other" },
}

-- Collect's canonical label keys (the enUS label in lower case) -> our source. Every other label that isn't a
-- place or a price (treasure, world event, discovery, in-game shop, ...) is "other".
local LABEL_SOURCE = {
	vendor = "vendor", achievement = "achievement", quest = "quest", drop = "drop", profession = "profession",
}

-- Lines that say where or how much, never what kind of source.
local NOT_A_SOURCE = { zone = true, location = true, cost = true }
local ZONE_LABELS = { zone = true, location = true }

local SOURCE_KEYS = {}
for _, s in ipairs(ns.DECOR_SOURCES) do
	SOURCE_KEYS[s.key] = s
end

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Hyperlinks become their text ("|Hcurrency:3008|h[Valorstones]|h" -> "[Valorstones]" -> "Valorstones"); colors,
-- textures and the rest stay for the parser.
function ns.Decor_CleanSource(raw)
	if type(raw) ~= "string" then
		return ""
	end
	return (raw:gsub("|H.-|h%[?(.-)%]?|h", "%1"))
end

-- A source line's value without colors and textures.
local function Plain(s)
	return Trim((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- raw catalog source text -> { source, line, vendor, zone, cost, vendors, zones }. source: a DECOR_SOURCES key; line:
-- the parser's one-line summary ("Vendor: Name · 100g") or nil; vendor/zone/cost: the first vendor, zone and cost
-- values or nil (cost keeps its currency icon); vendors: every vendor line with the zone and cost lines after it,
-- { { name, zone, cost } } (a decor several vendors sell lists them one after another); zones: the parser's lower-case
-- zone candidates (for matching your zone). parse defaults to ns.Collect_ParseSource.
function ns.Decor_Describe(raw, parse)
	parse = parse or ns.Collect_ParseSource
	local parsed = parse(ns.Decor_CleanSource(raw))
	local d = { source = "other", line = parsed.line, zones = parsed.zones or {}, vendors = {} }
	local found = false
	local current -- the vendor the next zone and cost lines belong to
	for _, entry in ipairs(parsed.lines or {}) do
		local label = entry.label
		if not found and not NOT_A_SOURCE[label] then
			d.source = LABEL_SOURCE[label] or "other"
			found = true
		end
		if label == "vendor" then
			local name = Plain(entry.value)
			current = nil
			if name ~= "" then
				current = { name = name }
				d.vendors[#d.vendors + 1] = current
				d.vendor = d.vendor or name
			end
		elseif ZONE_LABELS[label] then
			local zone = Plain(entry.value)
			if zone ~= "" then
				d.zone = d.zone or zone
				if current and not current.zone then
					current.zone = zone
				end
			end
		elseif label == "cost" then
			local cost = Trim(entry.raw or entry.value or "")
			if cost ~= "" then
				d.cost = d.cost or cost
				if current and not current.cost then
					current.cost = cost
				end
			end
		end
	end
	return d
end

-- How many of a decor you have, from a HousingCatalogEntryInfo: in storage, waiting to be redeemed and placed
-- (Blizzard_HousingCatalogUtil.GetEntryTotalOwned adds the same three). Missing fields count as 0.
function ns.Decor_OwnedCount(info)
	if type(info) ~= "table" then
		return 0
	end
	local n = 0
	for _, key in ipairs({ "totalNumStored", "remainingRedeemable", "totalNumPlaced" }) do
		local v = info[key]
		if type(v) == "number" and v > 0 then
			n = n + v
		end
	end
	return n
end

-- The tooltip line for a decor item: text, theme role.
function ns.Decor_TooltipLine(count)
	if count and count > 0 then
		return ("Decor: collected (%d)"):format(count), "success"
	end
	return "Decor: not collected", "warning"
end

-- An item ID from "12345", an item link or an item string; nil when there's none.
function ns.Decor_ItemID(arg)
	if type(arg) == "number" then
		return arg
	end
	if type(arg) ~= "string" then
		return nil
	end
	return tonumber(arg:match("item:(%d+)")) or tonumber(Trim(arg))
end

local function Lower(s)
	return type(s) == "string" and s:lower() or ""
end

local SEARCHED = { "name", "line", "vendor", "zone" }

-- The whole source text in plain lower case (every line: achievement, quest, drop, currency names), cached on the
-- entry (the catalog makes new entries on every read).
local function FullSource(e)
	if not e.fullSource then
		local text = ns.Decor_CleanSource(e.raw):gsub("|n", " "):gsub("%s+", " ")
		e.fullSource = Lower(Plain(text))
	end
	return e.fullSource
end

-- query: lower case, trimmed. Matches the name, the source line, the vendor or the zone; full: also anything in the
-- whole source text.
function ns.Decor_Matches(e, query, full)
	if not query or query == "" then
		return true
	end
	for _, key in ipairs(SEARCHED) do
		if Lower(e[key]):find(query, 1, true) then
			return true
		end
	end
	return full == true and FullSource(e):find(query, 1, true) ~= nil
end

local function ByName(a, b)
	if a.name ~= b.name then
		return (a.name or "") < (b.name or "")
	end
	return (a.id or 0) < (b.id or 0)
end

-- entries: { id, name, owned (count), source, line, vendor, zone }. opts = { source = "all" | key, query (lower
-- case), owned = true to include what you have, full = true to search the whole source text }. The matching entries,
-- sorted by name.
function ns.Decor_List(entries, opts)
	local out = {}
	local source = opts.source or "all"
	for _, e in ipairs(entries) do
		if (opts.owned or (e.owned or 0) == 0) and (source == "all" or e.source == source)
			and ns.Decor_Matches(e, opts.query, opts.full) then
			out[#out + 1] = e
		end
	end
	table.sort(out, ByName)
	return out
end

-- list: from Decor_List. collapsed: [source key] = true. hideOwned: leave what you have out of the section's entries
-- but still count it. The non-empty sections in DECOR_SOURCES order: { key, title, entries, total, owned, missing,
-- collapsed }; a section whose decor you all have is left out while hideOwned is set.
function ns.Decor_Sections(list, collapsed, hideOwned)
	local by = {}
	for _, e in ipairs(list) do
		local key = SOURCE_KEYS[e.source] and e.source or "other"
		by[key] = by[key] or { entries = {}, total = 0, owned = 0 }
		local s = by[key]
		s.total = s.total + 1
		if (e.owned or 0) > 0 then
			s.owned = s.owned + 1
		end
		if not (hideOwned and (e.owned or 0) > 0) then
			s.entries[#s.entries + 1] = e
		end
	end
	local out = {}
	for _, s in ipairs(ns.DECOR_SOURCES) do
		local found = by[s.key]
		if found and #found.entries > 0 then
			out[#out + 1] = { key = s.key, title = s.title, entries = found.entries, total = found.total,
				owned = found.owned, missing = found.total - found.owned, collapsed = (collapsed or {})[s.key] == true }
		end
	end
	return out
end

-- "124 / 1,290": thousands passes ns.Thousands in (Core/Format.lua) or tostring.
function ns.Decor_Ratio(owned, total, thousands)
	thousands = thousands or tostring
	return ("%s / %s"):format(thousands(owned), thousands(total))
end

-- Decor by vendor ---------------------------------------------------------------------------------------------
-- Every vendor the catalog names (a decor several vendors sell is under each), plus what learned vendors (the shops
-- you opened) were seen selling, so a vendor's list is as full as Tomte knows it.

local function VendorMatches(v, query)
	return Lower(v.vendor):find(query, 1, true) or Lower(v.zone):find(query, 1, true)
end

-- entries: catalog entries (with vendors from Decor_Describe). learned: [npcID] = { name, items = { [itemID] = true
-- } } or nil. opts = { query (lower case), owned = true to keep vendors you have everything from, full = true to
-- search the decor's whole source text }. Returns the
-- vendors sorted by name: { key (lower-case name), vendor, zone, entries (everything they sell, by name), total,
-- owned, missing }. A vendor matches the query by name, zone or any decor they sell, and then lists all of it.
function ns.Decor_Vendors(entries, learned, opts)
	opts = opts or {}
	local byKey, byItem, order = {}, {}, {}
	local function Vendor(name, zone)
		local key = name:lower()
		local v = byKey[key]
		if not v then
			v = { key = key, vendor = name, zone = zone, entries = {}, has = {} }
			byKey[key] = v
			order[#order + 1] = v
		end
		v.zone = v.zone or zone
		return v
	end
	local function Add(v, e)
		if not v.has[e] then
			v.has[e] = true
			v.entries[#v.entries + 1] = e
		end
	end
	for _, e in ipairs(entries) do
		if e.itemID then
			byItem[e.itemID] = e
		end
		for _, sold in ipairs(e.vendors or {}) do
			Add(Vendor(sold.name, sold.zone), e)
		end
	end
	for _, spot in pairs(learned or {}) do
		if type(spot.name) == "string" and spot.name ~= "" then
			for itemID in pairs(spot.items or {}) do
				local e = byItem[itemID]
				if e then
					Add(Vendor(spot.name), e)
				end
			end
		end
	end
	local query = opts.query or ""
	local out = {}
	for _, v in ipairs(order) do
		v.has = nil
		v.total, v.owned = #v.entries, 0
		local match = query == "" or VendorMatches(v, query)
		for _, e in ipairs(v.entries) do
			if (e.owned or 0) > 0 then
				v.owned = v.owned + 1
			end
			match = match or ns.Decor_Matches(e, query, opts.full)
		end
		v.missing = v.total - v.owned
		if match and (opts.owned or v.missing > 0) then
			table.sort(v.entries, ByName)
			out[#out + 1] = v
		end
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

-- What a vendor asks for a decor: the cost on that vendor's line of its source text, else the first cost.
function ns.Decor_CostAt(e, vendorKey)
	for _, sold in ipairs(e.vendors or {}) do
		if sold.name:lower() == vendorKey and sold.cost then
			return sold.cost
		end
	end
	return e.cost
end

-- { total, owned, missing, by = { [source key] = { total, owned, missing } } } for every entry.
function ns.Decor_Counts(entries)
	local c = { total = 0, owned = 0, missing = 0, by = {} }
	for _, s in ipairs(ns.DECOR_SOURCES) do
		c.by[s.key] = { total = 0, owned = 0, missing = 0 }
	end
	for _, e in ipairs(entries) do
		local by = c.by[e.source] or c.by.other
		local have = (e.owned or 0) > 0
		c.total, by.total = c.total + 1, by.total + 1
		if have then
			c.owned, by.owned = c.owned + 1, by.owned + 1
		else
			c.missing, by.missing = c.missing + 1, by.missing + 1
		end
	end
	return c
end

-- The short source word for a row ("Vendor").
function ns.Decor_SourceWord(key)
	local s = SOURCE_KEYS[key] or SOURCE_KEYS.other
	return s.word
end

-- Learned vendors ---------------------------------------------------------------------------------------------
-- The catalog names a vendor and zone but not where the vendor stands, and Blizzard's tracking can't lead to many
-- of them. So Tomte learns the spot when you open a shop that sells decor: vendors = { [npcID] = { name, mapID, x,
-- y, items = { [itemID] = true }, seen } }.

-- The creature ID in a unit GUID ("Creature-0-1-2-3-<npcID>-<spawn>"), or nil for players and other kinds.
function ns.Decor_NpcID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(id)
	end
	return nil
end

-- Remembers (or moves) a vendor. info = { name, mapID, x, y, items = { itemID, ... }, now }. Items add to what was
-- seen before: some vendors rotate their stock. Returns true when the vendor is new.
function ns.Decor_LearnVendor(vendors, npcID, info)
	local v = vendors[npcID]
	local new = v == nil
	v = v or { items = {} }
	v.name, v.mapID, v.x, v.y, v.seen = info.name, info.mapID, info.x, info.y, info.now
	v.items = v.items or {}
	for _, itemID in ipairs(info.items or {}) do
		v.items[itemID] = true
	end
	vendors[npcID] = v
	return new
end

-- The learned vendor for a decor entry: the one seen selling its item (the latest seen when several do), else one
-- with the vendor name from the source text (case-insensitive). Returns npcID, vendor or nil.
function ns.Decor_VendorSpot(e, vendors)
	local bestID, best
	if e.itemID then
		for npcID, v in pairs(vendors) do
			if v.items and v.items[e.itemID] and (not best or (v.seen or 0) > (best.seen or 0)) then
				bestID, best = npcID, v
			end
		end
	end
	if not best and e.vendor then
		local want = e.vendor:lower()
		for npcID, v in pairs(vendors) do
			if type(v.name) == "string" and v.name:lower() == want then
				return npcID, v
			end
		end
	end
	return bestID, best
end

-- [itemID] = true for the decor that learned vendors on mapID sell.
function ns.Decor_LearnedItemsOn(vendors, mapID)
	local set = {}
	for _, v in pairs(vendors) do
		if mapID and v.mapID == mapID then
			for itemID in pairs(v.items or {}) do
				set[itemID] = true
			end
		end
	end
	return set
end

-- What clicking a decor does, for the click and its tooltip: "stop" (tracked by Blizzard: stop), "track"
-- (Blizzard's tracking), "waypoint" (a learned vendor spot), "learn" (a vendor Tomte hasn't seen yet) or "none".
function ns.Decor_Action(e, s)
	if s.tracking then
		return "stop"
	elseif s.trackable then
		return "track"
	elseif s.spot then
		return "waypoint"
	elseif e.source == "vendor" and e.vendor then
		return "learn"
	end
	return "none"
end

-- Vendors in your zone selling decor you're missing. nameSet: [lower-case place name] = display name (your zone,
-- subzone). learned: [itemID] = true for decor that learned vendors on your map sell (Decor_LearnedItemsOn), or
-- nil. Returns { { vendor, zone, entries } } (most missing first, then by vendor name) and the decor count.
-- A vendor entry whose source names no zone matches only through learned.
function ns.Decor_VendorsHere(entries, nameSet, learned)
	local byVendor, order, total = {}, {}, 0
	for _, e in ipairs(entries) do
		if e.source == "vendor" and (e.owned or 0) == 0 and e.vendor then
			local here
			for _, c in ipairs(e.zones or {}) do
				if nameSet[c] then
					here = nameSet[c]
					break
				end
			end
			if not here and learned and e.itemID and learned[e.itemID] then
				here = e.zone or e.vendor
			end
			if here then
				local v = byVendor[e.vendor]
				if not v then
					v = { vendor = e.vendor, zone = e.zone or here, entries = {} }
					byVendor[e.vendor] = v
					order[#order + 1] = v
				end
				v.entries[#v.entries + 1] = e
				total = total + 1
			end
		end
	end
	table.sort(order, function(a, b)
		if #a.entries ~= #b.entries then
			return #a.entries > #b.entries
		end
		return a.vendor < b.vendor
	end)
	for _, v in ipairs(order) do
		table.sort(v.entries, ByName)
	end
	return order, total
end

-- [lower-case name] = name for the non-empty names given (your zone's map name, zone text, subzone text).
function ns.Decor_NameSet(names)
	local set = {}
	for _, name in ipairs(names) do
		if type(name) == "string" and Trim(name) ~= "" then
			set[Trim(name):lower()] = Trim(name)
		end
	end
	return set
end

-- "1 decor" / "12 decor": the noun doesn't change, the count reads better with it.
local function DecorCount(n)
	return ("%d decor"):format(n)
end

-- Next up and Around you: "Decor vendor here: 3 decor you're missing" (one vendor) or "Decor vendors here: ...".
function ns.Decor_VendorsHereText(vendors, total)
	if total == 0 then
		return nil
	end
	return ("%s here: %s you're missing"):format(#vendors == 1 and "Decor vendor" or "Decor vendors", DecorCount(total))
end

-- "312 of 1,840 collected": thousands passes ns.Thousands in (Core/Format.lua) or tostring.
function ns.Decor_CollectedText(counts, thousands)
	thousands = thousands or tostring
	return ("%s of %s collected"):format(thousands(counts.owned), thousands(counts.total))
end

-- /tomte decor scan: one line per source, "Vendors: 40 missing, 12 collected".
function ns.Decor_ScanLines(counts)
	local lines = {}
	for _, s in ipairs(ns.DECOR_SOURCES) do
		local by = counts.by[s.key]
		if by and by.total > 0 then
			lines[#lines + 1] = ("%s: %d missing, %d collected"):format(s.title, by.missing, by.owned)
		end
	end
	return lines
end
