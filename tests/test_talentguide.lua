-- Run from the AddOns folder: lua Tomte/tests/test_talentguide.lua
local ns = {}
assert(loadfile("Tomte/Modules/TalentGuide/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local MAGE = 1482

-- A made-up tree, sorted by node ID as the string expects: two trees of talents.
local NODES = {
	{ id = 100, maxRanks = 5 }, -- tree 1
	{ id = 101, maxRanks = 3 }, -- tree 1
	{ id = 102, maxRanks = 1 }, -- tree 2
	{ id = 103, maxRanks = 2 }, -- tree 2
	{ id = 104, maxRanks = 1 }, -- tree 1
}
local TREE_OF = { [100] = 1, [101] = 1, [102] = 2, [103] = 2, [104] = 1 }

-- Writes a string the way Method's calculator does: Blizzard's loadout bits, then the order as node indexes.
local function Encode(classID, ranks, order, nodes)
	local bits = {}
	local function add(width, value)
		for _ = 1, width do
			bits[#bits + 1] = value % 2
			value = math.floor(value / 2)
		end
	end
	add(8, 2)
	add(16, classID)
	for _ = 1, 16 do
		add(8, 0)
	end
	for _, node in ipairs(nodes or NODES) do
		local rank = ranks[node.id] or 0
		add(1, rank > 0 and 1 or 0)
		if rank > 0 then
			add(1, 1)
			local partial = rank ~= node.maxRanks
			add(1, partial and 1 or 0)
			if partial then
				add(6, rank)
			end
			add(1, 0)
		end
	end
	local out = {}
	for i = 1, #bits, 6 do
		local value = 0
		for j = 5, 0, -1 do
			value = value * 2 + (bits[i + j] or 0)
		end
		out[#out + 1] = ALPHABET:sub(value + 1, value + 1)
	end
	local text = table.concat(out)
	if order then
		local index = {}
		for i, node in ipairs(nodes or NODES) do
			index[node.id] = i - 1
		end
		local letters = {}
		for i, id in ipairs(order) do
			letters[i] = ALPHABET:sub(index[id] + 1, index[id] + 1)
		end
		text = text .. ";" .. table.concat(letters)
	end
	return text
end

local RANKS = { [100] = 5, [101] = 2, [103] = 1 }
local ORDER = { 100, 100, 101, 100, 100, 103, 101, 100 }

test("decodes ranks, points, class and order", function()
	local build = assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS, ORDER), NODES))
	eq(build.class, "MAGE", "class")
	eq(build.points, 8, "points")
	eq(build.ranks[100], 5, "full rank")
	eq(build.ranks[101], 2, "partial rank")
	eq(build.ranks[102], nil, "untaken")
	eq(#build.order, 8, "order length")
	eq(build.order[3], 101, "third point")
end)

test("the class from the header alone", function()
	eq(ns.TalentGuide_StringClass(Encode(1491, RANKS)), "WARRIOR")
	eq(ns.TalentGuide_StringClass(Encode(4242, RANKS)), nil, "unknown ID")
	eq(ns.TalentGuide_StringClass("not a build!"), nil, "junk")
end)

test("a build without an order", function()
	local build = assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS), NODES))
	eq(build.order, nil)
	eq(ns.TalentGuide_Next(build, {}), nil, "no next step without an order")
	local missing = ns.TalentGuide_Missing(build, { [100] = 5, [101] = 1 })
	eq(#missing, 2, "unfinished talents")
	eq(missing[1], 101)
	eq(missing[2], 103)
end)

test("spaces and line breaks from a paste are ignored", function()
	local text = Encode(MAGE, RANKS, ORDER)
	local build = assert(ns.TalentGuide_Decode("  " .. text:sub(1, 10) .. "\n" .. text:sub(11) .. " ", NODES))
	eq(build.points, 8)
end)

test("refuses what isn't a build string", function()
	local _, why = ns.TalentGuide_Decode("https://www.method.gg/wow-forever/talent-calculator", NODES)
	eq(why, "format", "a link")
	_, why = ns.TalentGuide_Decode("", NODES)
	eq(why, "format", "empty")
	_, why = ns.TalentGuide_Decode("CocB", NODES)
	eq(why, "format", "too short for the header")
end)

test("refuses a string for a bigger or smaller tree", function()
	local more = { { id = 100, maxRanks = 5 }, { id = 101, maxRanks = 3 }, { id = 102, maxRanks = 1 },
		{ id = 103, maxRanks = 2 }, { id = 104, maxRanks = 1 }, { id = 105, maxRanks = 1 }, { id = 106, maxRanks = 1 },
		{ id = 107, maxRanks = 1 }, { id = 108, maxRanks = 1 }, { id = 109, maxRanks = 1 }, { id = 110, maxRanks = 1 } }
	local text = Encode(MAGE, { [110] = 1, [100] = 5 }, nil, more)
	local _, why = ns.TalentGuide_Decode(text, NODES)
	eq(why, "tree", "string from a bigger tree")
	text = Encode(MAGE, { [100] = 5, [104] = 1 })
	_, why = ns.TalentGuide_Decode(text, more)
	eq(why, "tree", "string from a smaller tree")
end)

test("refuses an order that disagrees with the ranks", function()
	local _, why = ns.TalentGuide_Decode(Encode(MAGE, RANKS, { 100, 100 }), NODES)
	eq(why, "order", "too few points")
	_, why = ns.TalentGuide_Decode(Encode(MAGE, RANKS) .. ";AAAAACCDB9", NODES)
	eq(why, "order", "an index past the tree")
end)

test("next step follows the order and skips what you have", function()
	local build = assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS, ORDER), NODES))
	local nextStep = ns.TalentGuide_Next(build, {})
	eq(nextStep.step, 1)
	eq(nextStep.nodeID, 100)
	eq(nextStep.rank, 1)
	eq(nextStep.level, 10, "first point at 10")
	nextStep = ns.TalentGuide_Next(build, { [100] = 2 })
	eq(nextStep.step, 3, "after two points in 100")
	eq(nextStep.nodeID, 101)
	nextStep = ns.TalentGuide_Next(build, { [100] = 4, [101] = 1 })
	eq(nextStep.nodeID, 103, "points taken ahead of the order count")
	eq(nextStep.level, 15)
	nextStep = ns.TalentGuide_Next(build, { [100] = 5, [101] = 2, [103] = 1 })
	eq(nextStep, nil, "done")
end)

test("talents off the build and progress", function()
	local build = assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS, ORDER), NODES))
	local current = { [100] = 3, [101] = 3, [102] = 1 }
	local off = ns.TalentGuide_OffBuild(build, current)
	eq(off[101], true, "one rank too many")
	eq(off[102], true, "not in the build")
	eq(off[100], nil, "on the way")
	eq(ns.TalentGuide_Done(build, current), 5, "3 + 2 count, extras don't")
end)

test("talents taken ahead of the order", function()
	local build = assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS, ORDER), NODES))
	local early = ns.TalentGuide_Early(build, { [103] = 1 })
	eq(early[103], true, "the first point went to step 6's talent")
	early = ns.TalentGuide_Early(build, { [100] = 2, [101] = 1 })
	eq(next(early), nil, "three points in order")
	early = ns.TalentGuide_Early(build, { [100] = 1, [101] = 1 })
	eq(early[101], true, "101 is due at step 3, two points placed")
	eq(early[100], nil, "100 is on time")
	early = ns.TalentGuide_Early(build, { [102] = 1 })
	eq(early[102], nil, "off the build is not early")
	eq(next(ns.TalentGuide_Early(assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS), NODES)), { [103] = 1 })), nil,
		"no order, nothing is early")
end)

test("tally and name", function()
	local build = assert(ns.TalentGuide_Decode(Encode(MAGE, RANKS, ORDER), NODES))
	local tally = ns.TalentGuide_Tally(build, TREE_OF, 3)
	eq(table.concat(tally, "/"), "7/1/0")
	eq(ns.TalentGuide_Name(tally, { "Arcane", "Fire", "Frost" }), "Arcane 7/1/0")
	eq(ns.TalentGuide_Name({ 0, 0, 0 }, {}), "0/0/0", "no names")
end)

H.done()
