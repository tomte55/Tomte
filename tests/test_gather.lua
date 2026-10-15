-- Run from the AddOns folder: lua Tomte/tests/test_gather.lua
local ns = {}
assert(loadfile("Tomte/Modules/Value/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Gather/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Slot(id, sub, src, n)
	return { link = "item:" .. id, itemID = id, count = n or 1, quality = 1, classID = 7, subClassID = sub,
		sources = { src } }
end
local ORE, HERB, HIDE = 7, 9, 6
local NODE, CORPSE = "GameObject-0-1-2-3-410000-0001", "Creature-0-1-2-3-220000-0002"

---------------------------------------------------------------------------------------------------------------
-- Classification and learning

test("ParseGUID", function()
	local kind, id = ns.Gather_ParseGUID(NODE)
	eq(kind, "GameObject"); eq(id, 410000)
	eq((ns.Gather_ParseGUID("Item-1-0-ABC")), "Item")
	eq(select(2, ns.Gather_ParseGUID("Item-1-0-ABC")), nil)
	eq((ns.Gather_ParseGUID(nil)), nil)
	eq((ns.Gather_ParseGUID("junk")), nil)
	eq((ns.Gather_ParseGUID(42)), nil)
end)

test("mining cast on a node is mining", function()
	local kind, reason = ns.Gather_Classify({ slots = { Slot(210930, ORE, NODE, 3) } },
		{ spellID = 423341, kind = "mining", at = 99 }, { now = 100 })
	eq(kind, "mining")
	eq(reason, "cast 423341")
end)

test("Opening is never a gather", function()
	local kind, reason = ns.Gather_Classify({ slots = { Slot(210930, ORE, NODE) } }, { spellID = 3365, at = 99 }, { now = 100 })
	eq(kind, nil)
	eq(reason, "opening")
end)

test("secret cast falls back to contents for nodes only", function()
	eq((ns.Gather_Classify({ slots = { Slot(210796, HERB, NODE, 2) } }, nil, { now = 100 })), "herbalism")
	eq((ns.Gather_Classify({ slots = { Slot(212664, HIDE, CORPSE, 2) } }, nil, { now = 100 })), nil)
end)

test("fishing respects the option", function()
	local win = { fishing = true, slots = { Slot(220137, 8, NODE) } }
	eq((ns.Gather_Classify(win, nil, { now = 1, fishing = true })), "fishing")
	eq((ns.Gather_Classify(win, nil, { now = 1, fishing = false })), nil)
end)

test("containers and items never count", function()
	eq((ns.Gather_Classify({ fromItem = true, slots = { Slot(210930, ORE, NODE) } }, nil, { now = 1 })), nil)
	eq((ns.Gather_Classify({ slots = { Slot(210930, ORE, "Item-1-0-4000000ABCDEF") } },
		{ spellID = 2575, kind = "mining", at = 1 }, { now = 1 })), nil)
	eq((ns.Gather_Classify({ slots = {} }, nil, { now = 1 })), nil)
	eq((ns.Gather_Classify({}, nil, { now = 1 })), nil)
end)

test("a cast older than 3 seconds is ignored", function()
	-- creature loot: only a fresh skinning cast makes it a gather
	local win = { slots = { Slot(212664, HIDE, CORPSE) } }
	eq((ns.Gather_Classify(win, { spellID = 8613, kind = "skinning", at = 96 }, { now = 100 })), nil)
	eq((ns.Gather_Classify(win, { spellID = 8613, kind = "skinning", at = 97 }, { now = 100 })), "skinning")
end)

test("a skinning cast on a node window doesn't fit", function()
	eq((ns.Gather_Classify({ slots = { Slot(210930, ORE, NODE) } }, { spellID = 8613, kind = "skinning", at = 1 },
		{ now = 1 })), nil)
end)

test("mixed contents go by the majority", function()
	local win = { slots = { Slot(210930, ORE, NODE, 2), Slot(210796, HERB, NODE, 1) } }
	eq((ns.Gather_Classify(win, nil, { now = 1 })), "mining")
	local even = { slots = { Slot(210930, ORE, NODE, 1), Slot(210796, HERB, NODE, 1) } }
	eq((ns.Gather_Classify(even, nil, { now = 1 })), nil)
end)

test("a known cast with unreadable sources still counts", function()
	local win = { slots = { { itemID = 1, count = 1, classID = 7, subClassID = 7, sources = {} } } }
	eq((ns.Gather_Classify(win, { spellID = 2575, kind = "mining", at = 1 }, { now = 1 })), "mining")
	eq((ns.Gather_Classify(win, nil, { now = 1 })), nil)
end)

test("SpellKind by ID, learned and localized name", function()
	local names = { ["Herb Gathering"] = "herbalism" }
	eq(ns.Gather_SpellKind(2575), "mining")
	eq(ns.Gather_SpellKind(999, "Herb Gathering", names), "herbalism")
	eq(ns.Gather_SpellKind(999, nil, names, { [999] = "skinning" }), "skinning")
	eq(ns.Gather_SpellKind(3365, "Herb Gathering", names), nil)
	eq(ns.Gather_SpellKind(998, "Other", names), nil)
end)

test("ItemKind", function()
	eq(ns.Gather_ItemKind(7, 7), "mining")
	eq(ns.Gather_ItemKind(7, 9), "herbalism")
	eq(ns.Gather_ItemKind(7, 6), "skinning")
	eq(ns.Gather_ItemKind(7, 10), nil)
	eq(ns.Gather_ItemKind(2, 7), nil)
end)

test("ContentsKind", function()
	local kind, src = ns.Gather_ContentsKind({ slots = { Slot(212664, HIDE, CORPSE, 3) } })
	eq(kind, "skinning"); eq(src, "Creature")
	kind, src = ns.Gather_ContentsKind({ slots = { Slot(210930, ORE, NODE) } })
	eq(kind, "mining"); eq(src, "GameObject")
end)

test("learn an unknown herb spell after two windows", function()
	local learned, pending = {}, {}
	local cast = { spellID = 999001, at = 1 }
	local win = { slots = { Slot(210796, HERB, NODE) } }
	eq(ns.Gather_Learn(learned, pending, cast, win, "herbalism"), nil)
	eq(ns.Gather_Learn(learned, pending, cast, win, "herbalism"), "herbalism")
	eq(learned[999001], "herbalism")
end)

test("learning restarts when the kind differs", function()
	local learned, pending = {}, {}
	local cast = { spellID = 999002 }
	ns.Gather_Learn(learned, pending, cast, {}, "herbalism")
	eq(ns.Gather_Learn(learned, pending, cast, {}, "mining"), nil)
	eq(learned[999002], nil)
	eq(ns.Gather_Learn(learned, pending, cast, {}, "mining"), "mining")
end)

test("never learn from known non-gathering spells", function()
	local learned, pending = {}, {}
	ns.Gather_Learn(learned, pending, { spellID = 3365 }, {}, "mining")
	ns.Gather_Learn(learned, pending, { spellID = 3365 }, {}, "mining")
	eq(learned[3365], nil)
	ns.Gather_Learn(learned, pending, { spellID = 2575 }, {}, "herbalism")
	ns.Gather_Learn(learned, pending, { spellID = 2575 }, {}, "herbalism")
	eq(learned[2575], nil)
	eq(ns.Gather_Learn(learned, pending, { spellID = 5 }, {}, nil), nil)
	eq(ns.Gather_Learn(learned, pending, nil, {}, "mining"), nil)
end)

---------------------------------------------------------------------------------------------------------------
-- Run model

local function Run(manual)
	return ns.Gather_NewRun("Player-1", 1000, { name = "Aldric", class = "PALADIN", manual = manual })
end

test("NewRun shape", function()
	local r = Run()
	eq(r.guid, "Player-1"); eq(r.start, 1000); eq(r.lastAt, 1000); eq(r.name, "Aldric")
	eq(r.nodes, 0); eq(r.gathers, 0); eq(r.manual, nil)
	eq(type(r.items), "table"); eq(type(r.zones), "table")
end)

test("nodes vs gathers", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1010, kind = "skinning", sources = { "Creature-0-1-2-3-1-A", "Creature-0-1-2-3-1-B",
		"Creature-0-1-2-3-1-C" }, mapID = 2248 })
	eq(r.nodes, 3); eq(r.gathers, 3)
	for i = 1, 3 do
		ns.Gather_AddGather(r, { at = 1020 + i, kind = "mining", sources = { NODE }, mapID = 2248, objectID = 410000,
			nodeName = "Rich Bismuth" })
	end
	eq(r.nodes, 4); eq(r.gathers, 6); eq(r.kinds.mining.nodes, 1); eq(r.kinds.mining.gathers, 3)
	eq(r.zones[2248].nodes, 4)
	eq(r.nodeTypes[410000].n, 1); eq(r.nodeTypes[410000].name, "Rich Bismuth")
	eq(r.lastAt, 1023)
end)

test("a gather without readable sources is one node", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1010, kind = "fishing", sources = {} })
	ns.Gather_AddGather(r, { at = 1020, kind = "fishing" })
	eq(r.nodes, 2); eq(r.gathers, 2); eq(r.kinds.fishing.nodes, 2)
end)

test("seen GUIDs are capped", function()
	local r = Run()
	for i = 1, 520 do
		ns.Gather_AddGather(r, { at = 1000 + i, kind = "skinning", sources = { "Creature-0-1-2-3-1-" .. i } })
	end
	eq(r.nodes, 520)
	assert(#r.seenList <= 500, "list " .. #r.seenList)
	local n = 0
	for _ in pairs(r.seen) do
		n = n + 1
	end
	eq(n, #r.seenList, "map matches list")
end)

test("AddItem books value per item and zone", function()
	local r = Run()
	local e = ns.Gather_AddItem(r, { itemID = 210930, link = "item:210930", count = 3, unit = 100, rank = 2, quality = 1,
		kind = "mining", mapID = 2248 })
	ns.Gather_AddItem(r, { itemID = 210930, link = "item:210930", count = 2, unit = 100, rank = 2, quality = 1,
		kind = "mining", mapID = 2248 })
	eq(e.n, 5); eq(e.v, 500); eq(e.rank, 2); eq(e.kind, "mining"); eq(e.c, "gathered")
	eq(r.zones[2248].v, 500)
end)

test("finds are capped at 20", function()
	local r = Run()
	for i = 1, 25 do
		ns.Gather_AddFind(r, { kind = "item", itemID = i, at = i })
	end
	eq(#r.finds, 20)
	eq(r.finds[20].itemID, 25)
	eq(ns.Gather_IsFind(3), true); eq(ns.Gather_IsFind(2), false); eq(ns.Gather_IsFind(nil), false)
end)

test("book only cleared slots", function()
	local pending = { [1] = { itemID = 1 }, [2] = { itemID = 2 } }
	eq(ns.Gather_Booked(pending, 1).itemID, 1)
	eq(ns.Gather_Booked(pending, 1), nil)
	eq(ns.Gather_Booked(pending, 7), nil)
	eq(pending[2].itemID, 2)
end)

test("idle end at the last gather", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1600, kind = "mining", sources = { NODE } })
	eq(ns.Gather_Idle(r, 2199, 600), false)
	eq(ns.Gather_Idle(r, 2200, 600), true)
	eq(ns.Gather_Duration(r), 600)
end)

test("duration floor of 60 seconds", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1010, kind = "mining", sources = { NODE } })
	eq(ns.Gather_Duration(r), 60)
	eq(ns.Gather_Duration(r, 1020, true), 60)
end)

test("live duration is capped two minutes after the last gather", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1300, kind = "mining", sources = { NODE } })
	eq(ns.Gather_Duration(r, 5000, true), 420)
	eq(ns.Gather_Duration(r, 1400, true), 400)
end)

test("Numbers per hour, and no value without prices", function()
	local r = Run()
	for i = 1, 30 do
		ns.Gather_AddGather(r, { at = 1000 + i * 60, kind = "mining", sources = { "GameObject-0-1-2-3-1-" .. i } })
	end
	local n = ns.Gather_Numbers(r)
	eq(n.duration, 1800); eq(n.nodes, 30); eq(n.nodesPerHour, 60); eq(n.value, nil); eq(n.valuePerHour, nil)
	eq(n.mainKind, "mining")
	ns.Gather_AddItem(r, { itemID = 1, link = "item:1", count = 10, unit = 1000, kind = "mining" })
	n = ns.Gather_Numbers(r)
	eq(n.value, 10000); eq(n.valuePerHour, 20000)
	n = ns.Gather_Numbers(r, nil, false, function()
		return 2000
	end)
	eq(n.value, 20000)
end)

local function Gathers(r, kind, n)
	for i = 1, n do
		ns.Gather_AddGather(r, { at = 1000 + r.gathers + 1, kind = kind,
			sources = { "GameObject-0-1-2-3-1-" .. kind .. i } })
	end
end

test("one kind with a stray node of another is not mixed", function()
	local r = Run()
	Gathers(r, "herbalism", 2)
	Gathers(r, "mining", 1)
	local n = ns.Gather_Numbers(r)
	eq(n.mainKind, "herbalism", "a single mining node isn't a share")
	eq(#n.kinds, 1)
	eq(ns.Gather_RunTitle(n.mainKind, n.kinds), "Herbalism run")
	r = Run()
	Gathers(r, "mining", 20)
	Gathers(r, "herbalism", 3)
	eq(ns.Gather_Numbers(r).mainKind, "mining", "3 of 23 is under a fifth")
end)

test("mining and herbalism together is a mixed run, biggest kind first", function()
	local r = Run()
	Gathers(r, "herbalism", 12)
	Gathers(r, "mining", 5)
	local n = ns.Gather_Numbers(r)
	eq(n.mainKind, "mixed")
	eq(n.kinds[1], "herbalism"); eq(n.kinds[2], "mining")
	eq(ns.Gather_RunTitle(n.mainKind, n.kinds), "Herbalism & Mining run")
	eq(ns.Gather_KindsText(n.kinds), "Herbalism & Mining")
	r = Run()
	Gathers(r, "herbalism", 2)
	Gathers(r, "mining", 2)
	n = ns.Gather_Numbers(r)
	eq(n.kinds[1], "mining", "tie: GATHER_KINDS order")
	eq(ns.Gather_RunTitle(n.mainKind, n.kinds), "Mining & Herbalism run")
end)

test("three kinds read as a list", function()
	eq(ns.Gather_KindsText({ "mining", "herbalism", "skinning" }), "Mining, Herbalism & Skinning")
	eq(ns.Gather_RunTitle(nil, {}), "Gathering run")
end)

test("a mixed run shows under each of its kinds and as Mixed in zone stats", function()
	local r = Run()
	Gathers(r, "mining", 6)
	Gathers(r, "herbalism", 6)
	r.zones[1] = { nodes = 12, v = 0 }
	eq(#ns.Gather_Filter({ r }, "all", nil, nil, "mining"), 1)
	eq(#ns.Gather_Filter({ r }, "all", nil, nil, "herbalism"), 1)
	eq(ns.Gather_ZoneStats({ r })[1].kind, "mixed")
	eq(ns.GATHER_KIND_NAMES.mixed, "Mixed")
end)

test("resume rules", function()
	local r = Run()
	r.lastAt = 1000
	eq(ns.Gather_Resume(r, "Player-1", 1500, 600), "continue")
	eq(ns.Gather_Resume(r, "Player-1", 1700, 600), "finish")
	eq(ns.Gather_Resume(r, "Player-2", 1100, 600), "finish")
	eq(ns.Gather_Resume(nil, "Player-1", 1100, 600), "none")
end)

test("Keep: manual or enough nodes, never empty", function()
	local r = Run()
	for i = 1, 4 do
		ns.Gather_AddGather(r, { at = 1000 + i, kind = "mining", sources = { "GameObject-0-1-2-3-1-" .. i } })
	end
	eq(ns.Gather_Keep(r, 5), false)
	ns.Gather_AddGather(r, { at = 1010, kind = "mining", sources = { "GameObject-0-1-2-3-1-x" } })
	eq(ns.Gather_Keep(r, 5), true)
	local m = Run(true)
	eq(ns.Gather_Keep(m, 5), false, "manual without nodes")
	ns.Gather_AddGather(m, { at = 1010, kind = "mining", sources = { NODE } })
	eq(ns.Gather_Keep(m, 5), true, "manual")
end)

test("knowledge counts gains, not spending", function()
	local r = Run()
	ns.Gather_Knowledge(r, 2881, 4)
	ns.Gather_Knowledge(r, 2881, 6)
	ns.Gather_Knowledge(r, 2881, 1) -- spent 5
	ns.Gather_Knowledge(r, 2881, 2)
	eq(r.knowledge[2881].gained, 3)
end)

test("skill from and to", function()
	local r = Run()
	ns.Gather_Skill(r, 2881, 87)
	ns.Gather_Skill(r, 2881, 90)
	ns.Gather_Skill(r, 2881, 93)
	eq(r.skill[2881].from, 87); eq(r.skill[2881].to, 93)
	ns.Gather_Skill(r, 2881, nil)
	eq(r.skill[2881].to, 93)
end)

test("Compact drops seen and trims items to 15", function()
	local r = Run()
	ns.Gather_AddGather(r, { at = 1010, kind = "mining", sources = { NODE } })
	for i = 1, 20 do
		ns.Gather_AddItem(r, { itemID = i, link = "item:" .. i, count = 1, unit = i, kind = "mining" })
	end
	local c = ns.Gather_Compact(r)
	eq(c.seen, nil); eq(c.seenList, nil)
	local n, min = 0, 99
	for id in pairs(c.items) do
		n = n + 1
		min = math.min(min, id)
	end
	eq(n, 15); eq(min, 6)
	eq(c.nodes, 1)
	eq(r.seen[NODE], true, "the live run keeps its own")
end)

test("Archive keeps keepCount per character, newest first", function()
	local runs = {}
	for i = 1, 4 do
		ns.Gather_Archive(runs, { guid = "A", start = i }, 3)
	end
	ns.Gather_Archive(runs, { guid = "B", start = 9 }, 3)
	eq(#runs, 4)
	eq(runs[1].guid, "B"); eq(runs[2].start, 4); eq(runs[4].start, 2)
end)

local function Done(guid, start, minutes, nodes, value, kind, zones)
	local r = ns.Gather_NewRun(guid, start, { name = guid })
	for i = 1, nodes do
		ns.Gather_AddGather(r, { at = start + math.floor(minutes * 60 * i / nodes), kind = kind or "mining",
			sources = { "GameObject-0-1-2-3-1-" .. guid .. start .. i }, mapID = zones and (i <= zones[1] and 1 or 2) or 1 })
	end
	if value then
		ns.Gather_AddItem(r, { itemID = 1, link = "item:1", count = 1, unit = value, kind = kind or "mining", mapID = 1 })
	end
	return r
end

test("Filter by scope, since and kind", function()
	local runs = { Done("A", 5000, 10, 5), Done("B", 4000, 10, 5, nil, "herbalism"), Done("A", 1000, 10, 5) }
	eq(#ns.Gather_Filter(runs, "all"), 3)
	eq(#ns.Gather_Filter(runs, "char", "A"), 2)
	eq(#ns.Gather_Filter(runs, "all", nil, 3000), 2)
	eq(#ns.Gather_Filter(runs, "all", nil, nil, "herbalism"), 1)
	eq(#ns.Gather_Filter(runs, "char", "A", 3000, "mining"), 1)
end)

test("Totals over two runs", function()
	local list = { Done("A", 1000, 30, 30, 30000), Done("A", 9000, 30, 10, nil) }
	local t = ns.Gather_Totals(list)
	eq(t.count, 2); eq(t.duration, 3600); eq(t.nodes, 40); eq(t.nodesPerHour, 40); eq(t.value, 30000)
	eq(t.valuePerHour, 30000)
	eq(ns.Gather_Totals({}).value, nil)
end)

test("ItemTotals keeps ranks apart", function()
	local a, b = Run(), Run()
	ns.Gather_AddItem(a, { itemID = 10, link = "item:10", count = 3, unit = 10, rank = 1 })
	ns.Gather_AddItem(a, { itemID = 11, link = "item:11", count = 2, unit = 30, rank = 2 })
	ns.Gather_AddItem(b, { itemID = 10, link = "item:10", count = 4, unit = 10, rank = 1 })
	local rows = ns.Gather_ItemTotals({ a, b })
	eq(#rows, 2)
	eq(rows[1].itemID, 10); eq(rows[1].n, 7); eq(rows[1].v, 70); eq(rows[1].ranks[1], 7); eq(rows[1].rank, 1)
	eq(rows[2].itemID, 11); eq(rows[2].ranks[2], 2)
end)

test("ZoneStats splits a run's time by node share", function()
	local r = Done("A", 1000, 60, 40, 4000, "mining", { 30 })
	local rows = ns.Gather_ZoneStats({ r })
	eq(#rows, 2)
	local a = rows[1].mapID == 1 and rows[1] or rows[2]
	eq(a.seconds, 2700); eq(a.nodes, 30); eq(a.runs, 1); eq(a.kind, "mining"); eq(a.nodesPerHour, 40)
	eq(a.value, 4000)
	local b = rows[1].mapID == 2 and rows[1] or rows[2]
	eq(b.seconds, 900); eq(b.value, nil)
end)

test("session summary and line", function()
	eq(ns.Gather_SessionLine(nil), nil)
	eq(ns.Gather_SessionLine({ runs = 0, nodes = 0, value = 0 }), nil)
	local money = function(c)
		return c .. "c"
	end
	local session = {}
	local g = ns.Gather_SessionAdd(session, 1, 1000)
	eq(session.gather, g)
	ns.Gather_SessionAdd(session, 41, 2860)
	eq(g.runs, 0); eq(g.nodes, 42); eq(g.value, 3860)
	eq(ns.Gather_SessionLine(g, money), "gathered 42 nodes · 3860c")
	ns.Gather_SessionAdd(session, 0, nil, 1)
	eq(g.runs, 1); eq(g.nodes, 42)
	eq(ns.Gather_SessionLine({ nodes = 1, value = 0 }, money), "gathered 1 node")
	eq(ns.Gather_SessionLine({ nodes = 3, value = 50 }), "gathered 3 nodes")
end)

H.done()
