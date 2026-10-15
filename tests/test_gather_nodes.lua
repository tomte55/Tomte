-- Run from the AddOns folder: lua Tomte/tests/test_gather_nodes.lua
local ns = {}
assert(loadfile("Tomte/Modules/Gather/Nodes.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local SIZE = 5000 -- yards: a zone 5000 yards across, so 10 yards is 0.002 of it
local function SizeOf()
	return SIZE, SIZE
end

local function DB()
	return { nodes = {}, nodeTypes = {} }
end

local BISMUTH = { name = "Bismuth", item = 210930 }
local ORE, HERB = 410000, 420000
local MAP = 2248

local function Add(db, x, y, kind, objectID, info, mapID)
	return ns.GatherNodes_Add(db, mapID or MAP, x, y, kind, objectID, SizeOf, info)
end

local function Count(db)
	local n = 0
	for _, spots in pairs(db.nodes) do
		for _ in pairs(spots) do
			n = n + 1
		end
	end
	return n
end

test("pack and unpack keep a position to 1/10000 of the map", function()
	local pos = ns.GatherNodes_Pack(0.12345, 0.6789)
	eq(pos, 1235 * 10000 + 6789)
	local x, y = ns.GatherNodes_Unpack(pos)
	eq(x, 0.1235); eq(y, 0.6789)
	eq(ns.GatherNodes_Pack(1.2, -0.1), 9999 * 10000, "clamped to the map")
end)

test("a new spot is added with its node type", function()
	local db = DB()
	eq(Add(db, 0.5, 0.5, "mining", ORE, BISMUTH), true)
	eq(db.nodes[MAP][ns.GatherNodes_Pack(0.5, 0.5)], ORE)
	eq(db.nodeTypes[ORE].kind, "mining")
	eq(db.nodeTypes[ORE].name, "Bismuth")
	eq(db.nodeTypes[ORE].item, 210930)
end)

test("the same node gathered again a few yards away merges", function()
	local db = DB()
	Add(db, 0.5, 0.5, "mining", ORE, BISMUTH)
	eq(Add(db, 0.5 + 0.0015, 0.5, "mining", ORE, BISMUTH), false, "7.5 yards")
	eq(Add(db, 0.5 + 0.001, 0.5 + 0.001, "mining", ORE + 1), false, "7 yards, another ore type: same spot")
	eq(Count(db), 1)
	eq(Add(db, 0.5 + 0.003, 0.5, "mining", ORE, BISMUTH), true, "15 yards: another node")
	eq(Count(db), 2)
end)

test("mining and herbalism at the same spot stay apart", function()
	local db = DB()
	Add(db, 0.5, 0.5, "mining", ORE, BISMUTH)
	eq(Add(db, 0.5, 0.5, "herbalism", HERB, { name = "Mycobloom" }), true)
	eq(Count(db), 2)
end)

test("a node without an object ID keeps its kind letter", function()
	local db = DB()
	Add(db, 0.2, 0.2, "herbalism", nil)
	eq(db.nodes[MAP][ns.GatherNodes_Pack(0.2, 0.2)], "h")
	eq(ns.GatherNodes_Kind(db, "h"), "herbalism")
	eq(Add(db, 0.2, 0.2, "herbalism", HERB), false, "merges with the letter spot")
end)

test("skinning and fishing aren't nodes", function()
	local db = DB()
	eq(Add(db, 0.5, 0.5, "skinning", nil), false)
	eq(Add(db, 0.5, 0.5, "fishing", 12345), false)
	eq(Count(db), 0)
end)

test("an unknown map size falls back to a share of the map", function()
	local db = DB()
	local function NoSize()
		return 0, 0
	end
	ns.GatherNodes_Add(db, MAP, 0.5, 0.5, "mining", ORE, NoSize)
	eq(ns.GatherNodes_Add(db, MAP, 0.5015, 0.5, "mining", ORE, NoSize), false)
	eq(ns.GatherNodes_Add(db, MAP, 0.503, 0.5, "mining", ORE, NoSize), true)
end)

test("own gathering updates the node type, a friend's only fills gaps", function()
	local db = DB()
	Add(db, 0.5, 0.5, "mining", ORE, { name = "Bismuth" })
	Add(db, 0.6, 0.6, "mining", ORE, { name = "Bismuth", item = 210930 })
	eq(db.nodeTypes[ORE].item, 210930)
	local payload = "t" .. ORE .. "=m:1:Wismut;t" .. HERB .. "=h:2:Mycobloom;"
	eq(ns.GatherNodes_Import(db, payload, SizeOf), 0)
	eq(db.nodeTypes[ORE].name, "Bismuth", "ours kept")
	eq(db.nodeTypes[HERB].name, "Mycobloom", "missing filled")
end)

test("export is sorted and the same every time", function()
	local db = DB()
	Add(db, 0.3, 0.3, "herbalism", HERB, { name = "Mycobloom", item = 210796 })
	Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(db, 0.1, 0.1, "mining", nil, nil, 15)
	local text = ns.GatherNodes_Export(db)
	eq(text, "t410000=m:210930:Bismuth;t420000=h:210796:Mycobloom;n15:10001000=m;n2248:10001000=410000,30003000=420000;")
	eq(ns.GatherNodes_Export(db), text)
end)

test("names are cleaned and cut in the payload", function()
	local db = DB()
	Add(db, 0.1, 0.1, "mining", ORE, { name = "Ore; vein: rich=|cff^" .. ("x"):rep(80) })
	local name = ns.GatherNodes_Export(db):match("^t%d+=m::([^;]*);")
	eq(name, ("Ore vein richcff" .. ("x"):rep(80)):sub(1, 60))
end)

test("import round trip adds everything to an empty db", function()
	local from = DB()
	Add(from, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(from, 0.3, 0.3, "herbalism", HERB, { name = "Mycobloom" })
	Add(from, 0.4, 0.4, "herbalism", nil, nil, 15)
	local to = DB()
	eq(ns.GatherNodes_Import(to, ns.GatherNodes_Export(from), SizeOf), 3)
	eq(ns.GatherNodes_Export(to), ns.GatherNodes_Export(from))
	eq(ns.GatherNodes_Revision(to), ns.GatherNodes_Revision(from))
end)

test("import fills gaps: a friend's spot next to yours is not added", function()
	local to = DB()
	Add(to, 0.5, 0.5, "mining", ORE, BISMUTH)
	local payload = "t410000=m:210930:Bismuth;n2248:" .. ns.GatherNodes_Pack(0.501, 0.5) .. "=410000,"
		.. ns.GatherNodes_Pack(0.7, 0.7) .. "=410000;"
	eq(ns.GatherNodes_Import(to, payload, SizeOf), 1)
	eq(to.nodes[MAP][ns.GatherNodes_Pack(0.5, 0.5)], ORE, "yours kept")
	eq(Count(to), 2)
end)

test("any bad entry rejects the whole payload and adds nothing", function()
	local bad = {
		"n2248:10001000=410000;", -- object with no node type anywhere
		"t410000=x:1:Ore;", -- unknown kind letter
		"t410000=m:1:Ore;n2248:100000000=m;", -- pos over 99999999
		"n0:10001000=m;", -- map 0
		"n2248:10001000=s;", -- skinning letter
		"n2248:10001000=0;", -- object 0
		"n2248:=m;", -- no pos
		"n2248:10001000=m,;", -- empty spot
		"n2248:10001000=m", -- no closing ;
		"x1;", -- unknown entry
		"n2248:10001000=m;;", -- empty entry
		"t0=m:1:Ore;", -- object 0 in a type
	}
	for i, payload in ipairs(bad) do
		local db = DB()
		local added, why = ns.GatherNodes_Import(db, "n15:20002000=h;" .. payload, SizeOf)
		eq(added, nil, "payload " .. i .. " accepted")
		eq(type(why), "string", "payload " .. i .. " reason")
		eq(next(db.nodes), nil, "payload " .. i .. " added something")
	end
end)

test("too many nodes are rejected", function()
	local list = {}
	for i = 1, 50001 do
		list[i] = tostring(i) .. "=m"
	end
	local added, why = ns.GatherNodes_Import(DB(), "n1:" .. table.concat(list, ",") .. ";", SizeOf)
	eq(added, nil)
	eq(why, "too many nodes")
end)

test("an empty payload imports nothing", function()
	eq(ns.GatherNodes_Export(DB()), "")
	eq(ns.GatherNodes_Import(DB(), "", SizeOf), 0)
end)

test("revision follows the spots, not the node types", function()
	local a, b = DB(), DB()
	Add(a, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(b, 0.1, 0.1, "mining", ORE, { name = "Wismut" })
	eq(ns.GatherNodes_Revision(a), ns.GatherNodes_Revision(b))
	Add(b, 0.5, 0.5, "mining", ORE)
	eq(ns.GatherNodes_Revision(a) ~= ns.GatherNodes_Revision(b), true)
	eq(ns.GatherNodes_Revision(DB()), 5381)
end)

test("two installs converge and relay to a third", function()
	local a, b, c = DB(), DB(), DB()
	Add(a, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(a, 0.2, 0.2, "mining", ORE, BISMUTH)
	Add(b, 0.8, 0.8, "herbalism", HERB, { name = "Mycobloom" })
	Add(b, 0.1005, 0.1, "mining", ORE, BISMUTH) -- a's first node, 2.5 yards off
	eq(ns.GatherNodes_Import(b, ns.GatherNodes_Export(a), SizeOf), 1)
	eq(ns.GatherNodes_Import(a, ns.GatherNodes_Export(b), SizeOf), 1)
	eq(Count(a), 3); eq(Count(b), 3)
	eq(ns.GatherNodes_Import(c, ns.GatherNodes_Export(b), SizeOf), 3)
	eq(c.nodeTypes[ORE].name, "Bismuth")
	eq(ns.GatherNodes_Import(a, ns.GatherNodes_Export(b), SizeOf), 0, "nothing new the second time")
end)

test("the grid finds the same merges as a full scan", function()
	local db = DB()
	local seed = 7
	local function Rand()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local kept = {}
	for _ = 1, 3000 do
		local x, y = Rand() * 0.2, Rand() * 0.2
		local px, py = ns.GatherNodes_Unpack(ns.GatherNodes_Pack(x, y))
		local near = false
		for _, p in ipairs(kept) do
			local dx, dy = (p[1] - px) * SIZE, (p[2] - py) * SIZE
			if dx * dx + dy * dy <= 100 then
				near = true
				break
			end
		end
		local added = Add(db, x, y, "mining", ORE)
		if added then
			kept[#kept + 1] = { px, py }
		end
		-- Packing moves a spot by up to half a step: only compare cases clearly inside or outside the radius.
		local edge = false
		for _, p in ipairs(kept) do
			local dx, dy = (p[1] - px) * SIZE, (p[2] - py) * SIZE
			local d = math.sqrt(dx * dx + dy * dy)
			if d > 9.9 and d < 10.1 then
				edge = true
			end
		end
		if not edge then
			eq(added, not near, "spot " .. #kept)
		end
	end
	eq(Count(db), #kept)
end)

test("counts per kind on a map and in total", function()
	local db = DB()
	Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(db, 0.3, 0.3, "herbalism", HERB, { name = "Mycobloom" })
	Add(db, 0.5, 0.5, "herbalism", nil)
	Add(db, 0.5, 0.5, "mining", nil, nil, 15)
	local here, all = ns.GatherNodes_Counts(db, MAP)
	eq(here.mining, 1); eq(here.herbalism, 2)
	eq(all.mining, 2); eq(all.herbalism, 2)
end)

test("list for a map filters by kind", function()
	local db = DB()
	Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(db, 0.3, 0.3, "herbalism", HERB, { name = "Mycobloom" })
	local list = ns.GatherNodes_List(db, MAP, { mining = true })
	eq(#list, 1)
	eq(list[1].kind, "mining"); eq(list[1].objectID, ORE); eq(list[1].x, 0.1); eq(list[1].y, 0.1)
	eq(#ns.GatherNodes_List(db, MAP), 2, "nil kinds: all")
	eq(#ns.GatherNodes_List(db, 999), 0)
end)

test("list leaves hidden node types out, never spots of an unknown type", function()
	local db = DB()
	Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(db, 0.3, 0.3, "herbalism", HERB, { name = "Mycobloom" })
	Add(db, 0.5, 0.5, "mining", nil)
	local list = ns.GatherNodes_List(db, MAP, nil, { [ORE] = true })
	eq(#list, 2)
	eq(list[1].objectID, HERB)
	eq(list[2].objectID, nil, "the unknown-type spot stays")
end)

test("types on a map with counts, by kind then name", function()
	local db = DB()
	Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(db, 0.6, 0.6, "mining", ORE, BISMUTH)
	Add(db, 0.2, 0.2, "mining", ORE + 1, { name = "Aqirite" })
	Add(db, 0.3, 0.3, "herbalism", HERB, { name = "Mycobloom" })
	Add(db, 0.5, 0.5, "mining", nil)
	Add(db, 0.4, 0.4, "mining", ORE, BISMUTH, 15)
	local types = ns.GatherNodes_Types(db, MAP)
	eq(#types, 3, "unknown-type spots aren't listed")
	eq(types[1].name, "Mycobloom", "herbalism before mining")
	eq(types[2].name, "Aqirite")
	eq(types[3].objectID, ORE)
	eq(types[3].count, 2, "only this map's spots")
	eq(types[3].item, BISMUTH.item)
	eq(#ns.GatherNodes_Types(db, MAP, { herbalism = true }), 1, "filtered by kind")
	eq(#ns.GatherNodes_Types(db, 999), 0)
end)

test("groups merge a node's variants by the item they drop", function()
	local MYCO = 210796
	local types = {
		{ objectID = 1, kind = "herbalism", name = "Mycobloom", item = MYCO, count = 30 },
		{ objectID = 2, kind = "herbalism", name = "Lush Mycobloom", item = MYCO, count = 6 },
		{ objectID = 3, kind = "herbalism", name = "Crystallized Mycobloom", item = MYCO + 1, count = 8 }, -- rank 2
		{ objectID = 4, kind = "herbalism", name = "Blessing Blossom", item = 210805, count = 24 },
		{ objectID = 5, kind = "mining", name = "Mystery Vein", count = 2 }, -- no item known
		{ objectID = 6, kind = "herbalism", name = "Odd Herb", item = 999, count = 1 }, -- item not loaded yet
	}
	local names = { [MYCO] = "Mycobloom", [MYCO + 1] = "Mycobloom", [210805] = "Blessing Blossom" }
	local groups = ns.GatherNodes_Groups(types, function(t)
		return t.item and names[t.item]
	end)
	eq(#groups, 4)
	eq(groups[1].name, "Blessing Blossom")
	eq(groups[2].name, "Mycobloom")
	eq(groups[2].count, 44, "every variant and rank")
	eq(table.concat(groups[2].ids, ","), "1,2,3")
	eq(groups[3].name, "Odd Herb", "falls back to the type's name")
	eq(groups[4].kind, "mining", "herbalism before mining")
end)

test("forget one map keeps the others and the node types", function()
	local db = DB()
	Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)
	Add(db, 0.3, 0.3, "herbalism", HERB)
	Add(db, 0.4, 0.4, "mining", ORE, BISMUTH, 15)
	eq(ns.GatherNodes_Forget(db, MAP), 2)
	eq(db.nodes[MAP], nil)
	eq(Count(db), 1)
	eq(db.nodeTypes[ORE].name, "Bismuth")
	eq(ns.GatherNodes_Forget(db, MAP), 0, "nothing left")
	eq(select(2, Add(db, 0.1, 0.1, "mining", ORE, BISMUTH)) ~= nil, true, "the map records again")
end)

H.done()
