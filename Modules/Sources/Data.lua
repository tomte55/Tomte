local addonName, ns = ...

-- Where to get it (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_sources.lua). Reads the
-- generated table (Data/Forever/ItemSources.lua), finds items by name and puts the sources in the order worth going to. The page is
-- Page.lua; the module and the map pins are in Sources.lua.

local MAX_RESULTS = 40
local NEAR_BELOW, NEAR_ABOVE = 6, 3 -- levels around you where a mob is worth farming: much lower gives little, much higher kills you
local SPAWNS_COUNTED = 10 -- more than this doesn't make a place better: a few mobs at a good chance beat one rare spawn at 100%
-- Zones held by one side, by area ID, as in the generated table: farming in the other side's lands means guards and a long trip.
local SIDE_ZONES = {
	[12] = "A", [40] = "A", [1] = "A", [38] = "A", [141] = "A", [148] = "A", [44] = "A", [10] = "A", [1519] = "A", [1537] = "A", [1657] = "A",
	[14] = "H", [215] = "H", [17] = "H", [85] = "H", [130] = "H", [1637] = "H", [1638] = "H", [1497] = "H",
}
local RANK_NAMES = { ["1"] = "elite", ["2"] = "rare elite", ["3"] = "boss", ["4"] = "rare" }

local function Split(text, sep)
	local parts, from = {}, 1
	while true do
		local at = text:find(sep, from, true)
		if not at then
			parts[#parts + 1] = text:sub(from)
			return parts
		end
		parts[#parts + 1] = text:sub(from, at - 1)
		from = at + 1
	end
end

-- The item's name in the table, nil when it has no sources.
function ns.Sources_Name(items, itemID)
	local entry = items[itemID]
	return entry and entry:match("^([^|]*)") or nil
end

-- Items by name: { { itemID, name } }, the whole name first, then the start of it, then anywhere; shorter names first.
function ns.Sources_Search(items, text)
	local query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if #query < 2 then
		return {}
	end
	local found = {}
	for itemID, entry in pairs(items) do
		local name = entry:match("^([^|]*)")
		local lower = name:lower()
		local at = lower:find(query, 1, true)
		if at then
			local tier = lower == query and 1 or (at == 1 and 2 or 3)
			found[#found + 1] = { itemID = itemID, name = name, tier = tier }
		end
	end
	table.sort(found, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		elseif #a.name ~= #b.name then
			return #a.name < #b.name
		end
		return a.itemID < b.itemID
	end)
	for i = #found, MAX_RESULTS + 1, -1 do
		found[i] = nil
	end
	return found
end

local function ReadUnit(units, id)
	local line = units[id]
	if not line then
		return nil
	end
	local f = Split(line, "|")
	local low, high = f[2]:match("^(%d+)%-?(%d*)")
	low = tonumber(low) or 1
	return { id = id, name = f[1], levels = f[2], low = low, high = tonumber(high) or low, friendly = f[3], rank = RANK_NAMES[f[4]],
		zone = tonumber(f[5]), x = tonumber(f[6]), y = tonumber(f[7]), spawns = tonumber(f[8]) or 1 }
end

local function ReadObject(objects, id)
	local line = objects[id]
	if not line then
		return nil
	end
	local f = Split(line, "|")
	return { id = id, name = f[1], zone = tonumber(f[2]), x = tonumber(f[3]), y = tonumber(f[4]), spawns = tonumber(f[5]) or 1 }
end

-- An item's sources as they are in the table: { { kind = "drop" | "vendor" | "object", id, name, chance, levels, low, high,
-- friendly ("A", "H", "AH" or ""), rank, zone, x, y, spawns } }. Nothing for an item with none.
function ns.Sources_Read(data, itemID)
	local entry = data.items[itemID]
	local rows = {}
	if not entry then
		return rows
	end
	local list = entry:match("|(.*)$") or ""
	for _, part in ipairs(Split(list, ",")) do
		local letter, id, chance = part:match("^(%a)(%d+):?([%d%.e%-]*)$")
		id = tonumber(id)
		local row
		if letter == "o" then
			row = ReadObject(data.objects, id)
		elseif letter then
			row = ReadUnit(data.units, id)
		end
		if row then
			row.kind = letter == "u" and "drop" or (letter == "v" and "vendor" or "object")
			row.chance = tonumber(chance)
			row.zoneName = data.zones[row.zone]
			rows[#rows + 1] = row
		end
	end
	return rows
end

-- Whether a mob's levels are worth your while.
function ns.Sources_Near(row, level)
	return row.high >= level - NEAR_BELOW and row.low <= level + NEAR_ABOVE
end

-- How good a place to farm: the chance, and how many there are to kill. Few spawns count for little.
function ns.Sources_Score(row)
	return (row.chance or 0) * math.min(row.spawns or 1, SPAWNS_COUNTED)
end

local function Faction(faction)
	return faction == "Alliance" and "A" or (faction == "Horde" and "H" or nil)
end

-- The sources sorted for this character: { buy, gather, drops }. Only vendors who'd sell to you, and no mobs on your side. Drops: near
-- your level first, your side's lands before the other's, the best place to farm first; then the ones above you by level and last the
-- ones far below.
function ns.Sources_Sort(rows, level, faction)
	local letter = Faction(faction)
	local buy, gather, drops = {}, {}, {}
	for _, row in ipairs(rows) do
		local onYourSide = letter ~= nil and (row.friendly or ""):find(letter, 1, true) ~= nil
		if row.kind == "vendor" then
			if onYourSide or letter == nil then
				buy[#buy + 1] = row
			end
		elseif row.kind == "object" then
			gather[#gather + 1] = row
		elseif not onYourSide then
			drops[#drops + 1] = row
		end
	end
	local function Band(row)
		if ns.Sources_Near(row, level) then
			local side = SIDE_ZONES[row.zone]
			return (side and letter and side ~= letter) and 2 or 1
		end
		return row.low > level and 3 or 4
	end
	table.sort(drops, function(a, b)
		local x, y = Band(a), Band(b)
		if x ~= y then
			return x < y
		end
		if x == 3 and a.low ~= b.low then
			return a.low < b.low
		end
		local p, q = ns.Sources_Score(a), ns.Sources_Score(b)
		if p ~= q then
			return p > q
		end
		return a.id < b.id
	end)
	table.sort(gather, function(a, b)
		if (a.chance or 0) ~= (b.chance or 0) then
			return (a.chance or 0) > (b.chance or 0)
		end
		return a.id < b.id
	end)
	table.sort(buy, function(a, b)
		return a.id < b.id
	end)
	return { buy = buy, gather = gather, drops = drops }
end

function ns.Sources_ChanceText(chance)
	if not chance or chance <= 0 then
		return nil
	end
	return chance >= 10 and ("%d%%"):format(math.floor(chance + 0.5)) or ("%.1f%%"):format(chance)
end

-- The line under a source's name.
function ns.Sources_SubText(row)
	local parts = {}
	if row.zoneName and row.zoneName ~= "" then
		parts[#parts + 1] = row.zoneName
	end
	if row.levels then
		parts[#parts + 1] = "level " .. row.levels
	end
	if row.rank then
		parts[#parts + 1] = row.rank
	end
	return table.concat(parts, ", ")
end

-- One line for a tooltip: the best way to get it. nil with none.
function ns.Sources_TipLine(sorted, level)
	local row = sorted.buy[1]
	if row then
		return ("Sold by %s, %s"):format(row.name, row.zoneName or "?")
	end
	row = sorted.drops[1]
	local mined = sorted.gather[1]
	if mined and not (row and ns.Sources_Near(row, level)) then
		return ("From %s, %s"):format(mined.name, mined.zoneName or "?")
	end
	if row then
		local chance = ns.Sources_ChanceText(row.chance)
		return ("Drops from %s, %s%s"):format(row.name, row.zoneName or "?", chance and (" (" .. chance .. ")") or "")
	end
	return nil
end
