local addonName, ns = ...

-- Talent guide: pure logic (no WoW API calls; unit-tested in tests/test_talentguide.lua). Reads a build string from
-- Method's World of Warcraft: Forever talent calculator, and works out the next talent of the build from your
-- current ranks. The format is written up in docs/superpowers/specs/2026-11-22-tomte-talent-guide-design.md.

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" -- base64 order: value 0..63
local CHAR_BITS = 6
local HASH_BITS = 128 -- the tree hash after the header (Method writes zeros)
local MAX_POINTS = 51 -- talent points from level 10 to 60
ns.TALENTGUIDE_FIRST_LEVEL = 10 -- the level the first talent point comes at

-- The header's 16-bit ID per class, as Method writes it (game IDs, from its calculator script).
local CLASS_OF_ID = {
	[1482] = "MAGE", [1484] = "DRUID", [1485] = "HUNTER", [1486] = "PALADIN", [1487] = "PRIEST",
	[1488] = "ROGUE", [1489] = "SHAMAN", [1490] = "WARLOCK", [1491] = "WARRIOR",
}

local VALUE = {}
for i = 1, #ALPHABET do
	VALUE[ALPHABET:sub(i, i)] = i - 1
end

-- Reads values of any bit width from the string, least significant bits first (Blizzard's loadout serialization).
-- read(bits) is nil once the string runs out.
local function Reader(text)
	local values = {}
	for i = 1, #text do
		values[i] = VALUE[text:sub(i, i)]
	end
	local index, used = 1, 0 -- the character being read, and how many of its bits are spent
	local reader = {}
	function reader.read(bits)
		local value, shift = 0, 0
		while bits > 0 do
			local current = values[index]
			if not current then
				return nil
			end
			local take = math.min(CHAR_BITS - used, bits)
			local part = math.floor(current / 2 ^ used) % 2 ^ take
			value = value + part * 2 ^ shift
			shift, bits, used = shift + take, bits - take, used + take
			if used == CHAR_BITS then
				index, used = index + 1, 0
			end
		end
		return math.floor(value) -- a whole number on Lua 5.3 too (2 ^ n is a float there)
	end
	-- Bits not read yet.
	function reader.left()
		return math.max(0, (#values - index + 1) * CHAR_BITS - used)
	end
	return reader
end

local function Valid(text)
	return text ~= "" and not text:find("[^A-Za-z0-9+/]")
end

-- The class a string is for ("MAGE"), from its header, or nil.
function ns.TalentGuide_StringClass(text)
	local loadout = type(text) == "string" and text:gsub("%s", ""):match("^([^;]*)") or ""
	if not Valid(loadout) then
		return nil
	end
	local reader = Reader(loadout)
	if not reader.read(8) then
		return nil
	end
	local id = reader.read(16)
	return id and CLASS_OF_ID[id] or nil
end

-- Decodes a build string against the class tree. nodes: { { id = nodeID, maxRanks = n }, ... } sorted by id.
-- Returns build = { class, ranks = { [nodeID] = rank }, order = { nodeID, ... } or nil, points }, or nil and the
-- reason: "format" (not a build string), "tree" (doesn't fit this tree), "order" (the order disagrees with the ranks).
function ns.TalentGuide_Decode(text, nodes)
	if type(text) ~= "string" then
		return nil, "format"
	end
	text = text:gsub("%s", "")
	local loadout, order = text:match("^([^;]*);(.*)$")
	loadout = loadout or text
	if not Valid(loadout) or (order and order ~= "" and not Valid(order)) then
		return nil, "format"
	end
	local reader = Reader(loadout)
	local version, classID = reader.read(8), reader.read(16)
	if not (version and classID) then
		return nil, "format"
	end
	for _ = 1, HASH_BITS / 8 do
		if not reader.read(8) then
			return nil, "format"
		end
	end
	local ranks, points = {}, 0
	for _, node in ipairs(nodes) do
		local selected = reader.read(1)
		if not selected then
			return nil, "tree"
		end
		if selected == 1 then
			local purchased = reader.read(1)
			if not purchased then
				return nil, "tree"
			end
			local rank = 0 -- a granted node costs no point
			if purchased == 1 then
				local partial = reader.read(1)
				rank = node.maxRanks
				if partial == 1 then
					rank = reader.read(6)
				end
				local choice = reader.read(1)
				if choice == 1 then
					reader.read(2)
				end
				if not (partial and rank and choice) then
					return nil, "tree"
				end
			end
			if rank > 0 then
				ranks[node.id] = rank
				points = points + rank
			end
		end
	end
	-- Only the last character's padding may be left: more means the game's tree has fewer nodes than the string.
	if reader.left() >= CHAR_BITS or points > MAX_POINTS then
		return nil, "tree"
	end
	local build = { class = CLASS_OF_ID[classID], ranks = ranks, points = points }
	if order and order ~= "" then
		if #order > MAX_POINTS then
			return nil, "order"
		end
		local list, counts = {}, {}
		for i = 1, #order do
			local node = nodes[VALUE[order:sub(i, i)] + 1]
			if not node then
				return nil, "order"
			end
			list[i] = node.id
			counts[node.id] = (counts[node.id] or 0) + 1
		end
		for id, rank in pairs(ranks) do
			if counts[id] ~= rank then
				return nil, "order"
			end
		end
		for id in pairs(counts) do
			if not ranks[id] then
				return nil, "order"
			end
		end
		build.order = list
	end
	return build
end

-- The next point of the build against current ranks ({ [nodeID] = rank }): { step, nodeID, rank (the rank it takes
-- the talent to), level }, or nil when the build is done or has no order.
function ns.TalentGuide_Next(build, current)
	if not build.order then
		return nil
	end
	local need = {}
	for step, id in ipairs(build.order) do
		need[id] = (need[id] or 0) + 1
		if (current[id] or 0) < need[id] then
			return { step = step, nodeID = id, rank = need[id], level = ns.TALENTGUIDE_FIRST_LEVEL + step - 1 }
		end
	end
	return nil
end

-- Talents of the build not finished yet: list of nodeIDs, sorted (for a build without an order).
function ns.TalentGuide_Missing(build, current)
	local list = {}
	for id, rank in pairs(build.ranks) do
		if (current[id] or 0) < rank then
			list[#list + 1] = id
		end
	end
	table.sort(list)
	return list
end

-- Talents with more ranks than the build gives them: { [nodeID] = true }.
function ns.TalentGuide_OffBuild(build, current)
	local off = {}
	for id, rank in pairs(current) do
		if rank > (build.ranks[id] or 0) then
			off[id] = true
		end
	end
	return off
end

-- Talents of the build with points the order doesn't give them yet: with P points placed, more ranks than the
-- order's first P points hold. { [nodeID] = true }; empty for a build without an order. Talents off the build
-- entirely are TalentGuide_OffBuild's.
function ns.TalentGuide_Early(build, current)
	local early = {}
	if not build.order then
		return early
	end
	local placed = 0
	for _, rank in pairs(current) do
		placed = placed + rank
	end
	local due = {}
	for step = 1, math.min(placed, #build.order) do
		local id = build.order[step]
		due[id] = (due[id] or 0) + 1
	end
	for id, rank in pairs(current) do
		local final = build.ranks[id] or 0
		if rank <= final and rank > (due[id] or 0) then
			early[id] = true
		end
	end
	return early
end

-- How far along the build is: points that match it, out of build.points.
function ns.TalentGuide_Done(build, current)
	local done = 0
	for id, rank in pairs(build.ranks) do
		done = done + math.min(current[id] or 0, rank)
	end
	return done
end

-- Points per tree, in tree order: { 18, 0, 33 }. treeOf: { [nodeID] = tree index }, trees: how many.
function ns.TalentGuide_Tally(build, treeOf, trees)
	local tally = {}
	for i = 1, trees do
		tally[i] = 0
	end
	for id, rank in pairs(build.ranks) do
		local tree = treeOf[id]
		if tree and tally[tree] then
			tally[tree] = tally[tree] + rank
		end
	end
	return tally
end

-- A build's name: the tree with the most points and the split, "Frost 18/0/33". treeNames: in tree order.
function ns.TalentGuide_Name(tally, treeNames)
	local best
	for i, points in ipairs(tally) do
		if not best or points > tally[best] then
			best = i
		end
	end
	local split = table.concat(tally, "/")
	local name = best and treeNames[best]
	return name and (name .. " " .. split) or split
end
