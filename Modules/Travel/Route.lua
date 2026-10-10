local addonName, ns = ...

-- Waypoints, portal routes, pure logic: no WoW API calls (unit-tested with plain Lua). Unlock conditions, the
-- shortest way through Blizzard's waypoint network (Network.lua) from where you stand to a spot on another continent,
-- and which step to point at. Points are { map = instance ID, x, y } in world yards, the same space as the network.
-- Router.lua does the WoW side.

ns.WAY_ROUTE_SPEED = 10 -- yards per cost unit: edge costs are about seconds, flying covers ground quickly
ns.WAY_ROUTE_AT = 25 -- yards: standing at a step

-- Conditions -----------------------------------------------------------------------------------------------

-- Three-valued: true, false, or nil when it can't be checked ("?"). api: { faction = "Horde", class = classID,
-- level = n, quest(id), onQuest(id), ready(id), spell(id), ach(id) }. conds: shared conditions by ID ({ "pc", id }).
local Eval
local function All(expr, api, conds, from)
	local unknown = false
	for i = from, #expr do
		local v = Eval(expr[i], api, conds)
		if v == false then
			return false
		elseif v == nil then
			unknown = true
		end
	end
	if unknown then
		return nil
	end
	return true
end

local function Count(expr, api, conds, from)
	local yes, unknown = 0, 0
	for i = from, #expr do
		local v = Eval(expr[i], api, conds)
		if v == true then
			yes = yes + 1
		elseif v == nil then
			unknown = unknown + 1
		end
	end
	return yes, unknown
end

local LEAVES = {
	faction = function(e, api)
		return api.faction == e[2]
	end,
	class = function(e, api)
		for _, id in ipairs(e[2]) do
			if id == api.class then
				return true
			end
		end
		return false
	end,
	level = function(e, api)
		return api.level >= e[2] and (e[3] == 0 or api.level <= e[3])
	end,
	quest = function(e, api)
		return api.quest(e[2])
	end,
	onquest = function(e, api)
		return api.onQuest(e[2])
	end,
	ready = function(e, api)
		return api.ready(e[2])
	end,
	questor = function(e, api)
		return api.quest(e[2]) or api.onQuest(e[2])
	end,
	spell = function(e, api)
		return api.spell(e[2])
	end,
	ach = function(e, api)
		return api.ach(e[2])
	end,
}

function Eval(expr, api, conds)
	if expr == true or expr == false then
		return expr
	elseif type(expr) ~= "table" then
		return nil -- "?"
	end
	local op = expr[1]
	if op == "and" then
		return All(expr, api, conds, 2)
	elseif op == "or" then
		local yes, unknown = Count(expr, api, conds, 2)
		if yes > 0 then
			return true
		end
		return unknown == 0 and false or nil
	elseif op == "atleast" then
		local yes, unknown = Count(expr, api, conds, 3)
		if yes >= expr[2] then
			return true
		end
		return yes + unknown < expr[2] and false or nil
	elseif op == "not" then
		local v = Eval(expr[2], api, conds)
		if v == nil then
			return nil
		end
		return not v
	elseif op == "pc" then
		local shared = conds and conds[expr[2]]
		if shared == nil then
			return nil
		end
		return Eval(shared, api, conds)
	end
	local leaf = LEAVES[op]
	if not leaf then
		return nil
	end
	return leaf(expr, api) and true or false
end
ns.WayRoute_Eval = Eval

-- Usable unless it's known to be locked: what an addon can't check never blocks a route.
function ns.WayRoute_Allowed(expr, api, conds)
	return Eval(expr, api, conds) ~= false
end

-- Graph ----------------------------------------------------------------------------------------------------

-- net: { nodes, edges, volumes, conds } (Network.lua). Node fields: 1 map, 2 x, 3 y, 4 type, 5 volume, 6 condition,
-- 7 name. A node in an interior volume (bounds false, like the Wizard's Sanctum) is only reached through its edges
-- or from inside the same interior.
local function Interior(net, node)
	return node[5] ~= 0 and net.volumes[node[5]] == false
end
ns.WayRoute_Interior = Interior

local function Dist(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

local function CanWalk(net, from, to)
	if from[1] ~= to[1] then
		return false
	end
	return not Interior(net, to) or from[5] == to[5]
end

-- Shortest path from start to dest (points) as a list of node IDs, {} when they're on the same map (no route
-- needed), nil when there's no way. api is for conditions (see Eval).
function ns.WayRoute_Find(net, start, dest, api)
	if start.map == dest.map then
		return {}
	end
	local nodes, cache = {}, {}
	local function Ok(expr)
		if expr == true then
			return true
		end
		local v = cache[expr]
		if v == nil then
			v = ns.WayRoute_Allowed(expr, api, net.conds)
			cache[expr] = v
		end
		return v
	end
	local ids = {}
	for id, node in pairs(net.nodes) do
		if Ok(node[6]) then
			nodes[id] = node
			ids[#ids + 1] = id
		end
	end
	table.sort(ids) -- the same route every time when costs tie
	local byMap = {}
	for _, id in ipairs(ids) do
		local map = nodes[id][1]
		byMap[map] = byMap[map] or {}
		table.insert(byMap[map], id)
	end
	local adj = {}
	for _, edge in ipairs(net.edges) do
		if nodes[edge[1]] and nodes[edge[2]] and Ok(edge[4]) then
			adj[edge[1]] = adj[edge[1]] or {}
			table.insert(adj[edge[1]], edge)
		end
	end

	local dist, prev, done = {}, {}, {}
	for _, id in ipairs(ids) do
		local node = nodes[id]
		if node[1] == start.map then
			local d = Dist(start.x, start.y, node[2], node[3])
			if d <= ns.WAY_ROUTE_AT then
				dist[id] = 0
			elseif not Interior(net, node) then
				dist[id] = d / ns.WAY_ROUTE_SPEED
			end
		end
	end
	local DEST = "dest"
	local best, bestCost
	local function Relax(id, cost)
		if not done[id] and (not dist[id] or bestCost + cost < dist[id]) then
			dist[id], prev[id] = bestCost + cost, best
		end
	end
	while true do
		best, bestCost = nil, nil
		for _, id in ipairs(ids) do
			if not done[id] and dist[id] and (not bestCost or dist[id] < bestCost) then
				best, bestCost = id, dist[id]
			end
		end
		if dist[DEST] and not done[DEST] and (not bestCost or dist[DEST] <= bestCost) then
			break
		end
		if not best then
			return nil
		end
		done[best] = true
		local node = nodes[best]
		for _, edge in ipairs(adj[best] or {}) do
			Relax(edge[2], edge[3])
		end
		for _, id in ipairs(byMap[node[1]]) do
			local other = nodes[id]
			if id ~= best and CanWalk(net, node, other) then
				Relax(id, Dist(node[2], node[3], other[2], other[3]) / ns.WAY_ROUTE_SPEED)
			end
		end
		if node[1] == dest.map then
			Relax(DEST, Dist(node[2], node[3], dest.x, dest.y) / ns.WAY_ROUTE_SPEED)
		end
	end
	local path, id = {}, prev[DEST]
	while id do
		table.insert(path, 1, id)
		id = prev[id]
	end
	return path
end

-- Steps ----------------------------------------------------------------------------------------------------

-- The step to point at, from index i on: steps you're standing at are passed when the next one is on the same map
-- (a portal you stand at stays until you've taken it), and inside an interior it points straight at the next step
-- in the same interior. pos: the player's point. reached: the game says you've reached step i (its radius can be
-- wider than WAY_ROUTE_AT), so it counts as standing at it.
function ns.WayRoute_NextIndex(net, path, i, pos, reached)
	local first = i
	while path[i] and path[i + 1] do
		local node, nextNode = net.nodes[path[i]], net.nodes[path[i + 1]]
		local here = (reached and i == first)
			or (node[1] == pos.map and Dist(pos.x, pos.y, node[2], node[3]) <= ns.WAY_ROUTE_AT)
		if here and nextNode[1] == node[1] then
			i = i + 1
		elseif Interior(net, node) and nextNode[5] == node[5] then
			i = i + 1
		else
			break
		end
	end
	return i
end

-- A step that leaves the map: the next step is on another map (portal, zeppelin, boat, tunnel).
local function Leaves(net, path, j)
	local node, nextNode = net.nodes[path[j]], net.nodes[path[j + 1]]
	return nextNode ~= nil and nextNode[1] ~= node[1]
end

-- What the card says: the step's own text, then the next way off a map after it.
function ns.WayRoute_Texts(net, path, i)
	local node = net.nodes[path[i]]
	if not node then
		return nil
	end
	for j = i + 1, #path - 1 do
		if Leaves(net, path, j) then
			return node[7], net.nodes[path[j]][7]
		end
	end
	return node[7], nil
end

-- Every way off a map along the path: the route in a few lines.
function ns.WayRoute_Summary(net, path)
	local list = {}
	for j = 1, #path - 1 do
		if Leaves(net, path, j) then
			list[#list + 1] = net.nodes[path[j]][7]
		end
	end
	return list
end
