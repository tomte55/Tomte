local addonName, ns = ...

-- Flight-master coverage, pure logic: no WoW API calls (unit-tested with plain Lua).
-- A flight master is timed when it is in any recorded hop or route. Legs are distinct recorded hops,
-- A>B and B>A counted once. The atlas (Atlas.lua) supplies continents > zones > flight masters.

-- Returns timed ([nodeID] = true) and legs ({ a, b } with a < b, each pair once).
function ns.Coverage_Timed(db)
	local timed, legs, seen = {}, {}, {}
	for key in pairs(db.hops) do
		local a, b = key:match("^(%d+)>(%d+)$")
		if a then
			a, b = tonumber(a), tonumber(b)
			timed[a], timed[b] = true, true
			if a > b then
				a, b = b, a
			end
			local pair = a .. ">" .. b
			if not seen[pair] then
				seen[pair] = true
				legs[#legs + 1] = { a, b }
			end
		end
	end
	for key in pairs(db.routes) do
		for id in key:gmatch("%d+") do
			timed[tonumber(id)] = true
		end
	end
	return timed, legs
end

-- node = { nodeID, name, undiscovered }
function ns.Coverage_NodeState(node, timed)
	if timed[node.nodeID] then
		return "timed"
	end
	return node.undiscovered and "undiscovered" or "known"
end

function ns.Coverage_Count(nodes, timed)
	local n = 0
	for _, node in ipairs(nodes) do
		if timed[node.nodeID] then
			n = n + 1
		end
	end
	return n, #nodes
end

local function ByName(a, b)
	return a.name < b.name
end

-- Returns { timed, total, legs, continents = { { mapID, name, timed, total, legs, zones = { { mapID, name,
-- timed, total, legs, nodes = { { nodeID, name, state } } } } } } }. Zones and nodes sorted by name,
-- empty zones and continents left out.
function ns.Coverage_Summarize(atlas, db)
	local timed, legs = ns.Coverage_Timed(db)
	local zoneOf, continentOf = {}, {}
	local result = { timed = 0, total = 0, legs = 0, continents = {} }
	for _, continent in ipairs(atlas.continents) do
		local c = { mapID = continent.mapID, name = continent.name, timed = 0, total = 0, legs = 0, zones = {} }
		for _, zone in ipairs(continent.zones) do
			if #zone.nodes > 0 then
				local z = { mapID = zone.mapID, name = zone.name, legs = 0, nodes = {} }
				for i, node in ipairs(zone.nodes) do
					z.nodes[i] = { nodeID = node.nodeID, name = node.name, state = ns.Coverage_NodeState(node, timed) }
					zoneOf[node.nodeID], continentOf[node.nodeID] = z, c
				end
				table.sort(z.nodes, ByName)
				z.timed, z.total = ns.Coverage_Count(zone.nodes, timed)
				c.timed, c.total = c.timed + z.timed, c.total + z.total
				c.zones[#c.zones + 1] = z
			end
		end
		if #c.zones > 0 then
			table.sort(c.zones, ByName)
			result.timed, result.total = result.timed + c.timed, result.total + c.total
			result.continents[#result.continents + 1] = c
		end
	end
	for _, leg in ipairs(legs) do
		local za, zb = zoneOf[leg[1]], zoneOf[leg[2]]
		if za or zb then
			result.legs = result.legs + 1
		end
		if za then
			za.legs = za.legs + 1
		end
		if zb and zb ~= za then
			zb.legs = zb.legs + 1
		end
		local ca, cb = continentOf[leg[1]], continentOf[leg[2]]
		if ca then
			ca.legs = ca.legs + 1
		end
		if cb and cb ~= ca then
			cb.legs = cb.legs + 1
		end
	end
	return result
end
