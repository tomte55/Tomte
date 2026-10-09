-- Run from the AddOns folder: lua Tomte/tests/test_route.lua
local ns = {}
assert(loadfile("Tomte/Modules/Travel/Network.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Travel/Route.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local NET = { nodes = ns.WAY_NET_NODES, edges = ns.WAY_NET_EDGES, volumes = ns.WAY_NET_VOLUMES,
	conds = ns.WAY_NET_CONDS }

local function Api(faction, done)
	done = done or {}
	return {
		faction = faction, class = 2, level = 80,
		quest = function(id) return done[id] == true end,
		onQuest = function() return false end,
		ready = function() return false end,
		spell = function() return false end,
		ach = function() return false end,
	}
end

local function Has(list, text)
	for _, line in ipairs(list) do
		if line == text then
			return true
		end
	end
	return false
end

-- Conditions -----------------------------------------------------------------------------------------------

test("Eval: three-valued and/or/not", function()
	local api = Api("Horde")
	eq(ns.WayRoute_Eval({ "faction", "Horde" }, api), true)
	eq(ns.WayRoute_Eval({ "faction", "Alliance" }, api), false)
	eq(ns.WayRoute_Eval("?", api), nil, "unknown")
	eq(ns.WayRoute_Eval({ "and", { "faction", "Horde" }, "?" }, api), nil, "true and unknown")
	eq(ns.WayRoute_Eval({ "and", { "faction", "Alliance" }, "?" }, api), false, "false and unknown")
	eq(ns.WayRoute_Eval({ "or", { "faction", "Horde" }, "?" }, api), true, "true or unknown")
	eq(ns.WayRoute_Eval({ "or", { "faction", "Alliance" }, "?" }, api), nil, "false or unknown")
	eq(ns.WayRoute_Eval({ "not", "?" }, api), nil)
	eq(ns.WayRoute_Eval({ "not", { "faction", "Alliance" } }, api), true)
	eq(ns.WayRoute_Eval({ "atleast", 2, { "faction", "Horde" }, "?", { "faction", "Alliance" } }, api), nil)
	eq(ns.WayRoute_Eval({ "pc", 120899 }, api, NET.conds), true, "shared condition")
end)

test("Allowed: only a known false blocks", function()
	local api = Api("Alliance")
	eq(ns.WayRoute_Allowed("?", api), true)
	eq(ns.WayRoute_Allowed({ "pc", 120899 }, api, NET.conds), false, "Horde-only portal")
	eq(ns.WayRoute_Allowed({ "class", { 1, 2 } }, api), true)
	eq(ns.WayRoute_Allowed({ "level", 10, 20 }, api), false)
end)

-- Routes ---------------------------------------------------------------------------------------------------

local DORNOGAL = { map = 2552, x = 2900, y = -2380 }
local ORGRIMMAR = { map = 1, x = 1600, y = -4400 }
local STORMWIND = { map = 0, x = -8850, y = 640 }

test("Find: same map needs no route", function()
	eq(#ns.WayRoute_Find(NET, DORNOGAL, { map = 2552, x = 0, y = 0 }, Api("Horde")), 0)
end)

test("Find: Dornogal to Orgrimmar takes the Horde portal", function()
	local path = ns.WayRoute_Find(NET, DORNOGAL, ORGRIMMAR, Api("Horde"))
	assert(path and #path > 0, "a route")
	local summary = ns.WayRoute_Summary(NET, path)
	eq(summary[1], "Take the portal from Dornogal to Orgrimmar")
	eq(#summary, 1, "one hop")
end)

test("Find: Alliance goes from Dornogal to Stormwind, not Orgrimmar", function()
	local path = ns.WayRoute_Find(NET, DORNOGAL, STORMWIND, Api("Alliance"))
	assert(path and #path > 0, "a route")
	local summary = ns.WayRoute_Summary(NET, path)
	eq(summary[1], "Take the portal from Dornogal to Stormwind")
	eq(Has(summary, "Take the portal from Dornogal to Orgrimmar"), false)
end)

test("Find: Stormwind to Dornogal goes into the Wizard's Sanctum", function()
	local path = ns.WayRoute_Find(NET, STORMWIND, DORNOGAL, Api("Alliance"))
	assert(path and #path > 0, "a route")
	eq(ns.WayRoute_Summary(NET, path)[1], "Take the portal from Stormwind to Dornogal")
	local first = NET.nodes[path[1]]
	eq(ns.WayRoute_Interior(NET, first), false, "starts outside the interior")
end)

test("Find: Horde from Dornogal to Pandaria goes through Orgrimmar", function()
	local path = ns.WayRoute_Find(NET, DORNOGAL, { map = 870, x = 1600, y = 900 }, Api("Horde"))
	assert(path and #path > 0, "a route")
	local summary = ns.WayRoute_Summary(NET, path)
	eq(summary[1], "Take the portal from Dornogal to Orgrimmar")
	assert(#summary >= 2, "two hops at least")
end)

test("Find: nil when nothing leads there", function()
	eq(ns.WayRoute_Find(NET, DORNOGAL, { map = 99999, x = 0, y = 0 }, Api("Horde")), nil)
end)

-- Steps ----------------------------------------------------------------------------------------------------

test("NextIndex: a portal you stand at stays until you've taken it", function()
	local path = ns.WayRoute_Find(NET, DORNOGAL, ORGRIMMAR, Api("Horde"))
	local portal = NET.nodes[path[1]]
	eq(ns.WayRoute_NextIndex(NET, path, 1, DORNOGAL), 1, "far away")
	eq(ns.WayRoute_NextIndex(NET, path, 1, { map = 2552, x = portal[2], y = portal[3] }), 1, "standing at it")
end)

test("NextIndex: inside the sanctum it points at the portal", function()
	local path = ns.WayRoute_Find(NET, STORMWIND, DORNOGAL, Api("Alliance"))
	local entrance = NET.nodes[path[1]]
	local i = ns.WayRoute_NextIndex(NET, path, 1, { map = 0, x = entrance[2], y = entrance[3] })
	eq(NET.nodes[path[i]][7], "Take the portal from Stormwind to Dornogal")
end)

test("Texts: the step, then the next way off a map", function()
	local path = ns.WayRoute_Find(NET, DORNOGAL, { map = 870, x = 1600, y = 900 }, Api("Horde"))
	local text, nextText = ns.WayRoute_Texts(NET, path, 1)
	eq(text, "Take the portal from Dornogal to Orgrimmar")
	eq(nextText, "Take the portal from Pathfinder's Den to Jade Forest", "then the portal out of Orgrimmar")
end)

test("network: every edge's nodes exist and every shared condition is a table", function()
	for _, edge in ipairs(NET.edges) do
		assert(NET.nodes[edge[1]] and NET.nodes[edge[2]], "edge nodes")
	end
	for id, expr in pairs(NET.conds) do
		eq(type(expr), "table", "condition " .. id)
	end
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
