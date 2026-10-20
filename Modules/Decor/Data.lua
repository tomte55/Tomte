local addonName, ns = ...

-- Housing decor: pure logic (no WoW API calls; unit-tested in tests/test_decor.lua). What kind of source a decor's
-- catalog source text names (vendor, achievement, quest, drop, profession, other), the vendor and zone in it, the
-- page's filtering, grouping and counts, the vendors in your zone, the learned vendor spots, what a click does and
-- the tooltip line. The source text is read with
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

-- raw catalog source text -> { source, line, vendor, zone, zones }. source: a DECOR_SOURCES key; line: the parser's
-- one-line summary ("Vendor: Name · 100g") or nil; vendor/zone: the first vendor and zone values or nil; zones: the
-- parser's lower-case zone candidates (for matching your zone). parse defaults to ns.Collect_ParseSource.
function ns.Decor_Describe(raw, parse)
	parse = parse or ns.Collect_ParseSource
	local parsed = parse(ns.Decor_CleanSource(raw))
	local d = { source = "other", line = parsed.line, zones = parsed.zones or {} }
	local found = false
	for _, entry in ipairs(parsed.lines or {}) do
		local label = entry.label
		if not found and not NOT_A_SOURCE[label] then
			d.source = LABEL_SOURCE[label] or "other"
			found = true
		end
		if label == "vendor" and not d.vendor then
			local name = Plain(entry.value)
			d.vendor = name ~= "" and name or nil
		elseif ZONE_LABELS[label] and not d.zone then
			local zone = Plain(entry.value)
			d.zone = zone ~= "" and zone or nil
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

-- query: lower case, trimmed. Matches the name, the source line, the vendor or the zone.
function ns.Decor_Matches(e, query)
	if not query or query == "" then
		return true
	end
	for _, key in ipairs(SEARCHED) do
		if Lower(e[key]):find(query, 1, true) then
			return true
		end
	end
	return false
end

local function ByName(a, b)
	if a.name ~= b.name then
		return (a.name or "") < (b.name or "")
	end
	return (a.id or 0) < (b.id or 0)
end

-- entries: { id, name, owned (count), source, line, vendor, zone }. opts = { source = "all" | key, query (lower
-- case), owned = true to include what you have }. The matching entries, sorted by name.
function ns.Decor_List(entries, opts)
	local out = {}
	local source = opts.source or "all"
	for _, e in ipairs(entries) do
		if (opts.owned or (e.owned or 0) == 0) and (source == "all" or e.source == source)
			and ns.Decor_Matches(e, opts.query) then
			out[#out + 1] = e
		end
	end
	table.sort(out, ByName)
	return out
end

-- list: from Decor_List. collapsed: [source key] = true. The non-empty sections in DECOR_SOURCES order:
-- { key, title, entries, missing, owned, collapsed }.
function ns.Decor_Sections(list, collapsed)
	local by = {}
	for _, e in ipairs(list) do
		local key = SOURCE_KEYS[e.source] and e.source or "other"
		by[key] = by[key] or {}
		table.insert(by[key], e)
	end
	local out = {}
	for _, s in ipairs(ns.DECOR_SOURCES) do
		local entries = by[s.key]
		if entries then
			local owned = 0
			for _, e in ipairs(entries) do
				if (e.owned or 0) > 0 then
					owned = owned + 1
				end
			end
			out[#out + 1] = { key = s.key, title = s.title, entries = entries, owned = owned,
				missing = #entries - owned, collapsed = (collapsed or {})[s.key] == true }
		end
	end
	return out
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
