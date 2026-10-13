local addonName, ns = ...

-- Flight Timer's data set for Friend sharing: pure logic (no WoW API calls; unit-tested in
-- tests/test_flight_share.lua). Registered with Friend sharing in Flight.lua; the transport is Modules/Share.
-- Payload: "h<a>><b>=<seconds>;" per hop and "r<id>>...><id>=<seconds>;" per route, sorted. Friends are trusted:
-- import adds what's missing and never overwrites, and export sends everything known (received times too), so
-- times relay through friends of friends.

local MAX_SECONDS = 3600 -- an hour: longer than any flight path
local MAX_NODES = 30 -- per route; real routes have a handful of stops
local MAX_ENTRIES = 20000 -- per payload; the whole game has a few thousand legs
local HASH_MOD = 2147483648 -- 2^31: djb2 stays exact in Lua 5.1 doubles

-- The canonical key ("12>34") of a path text, or nil, reason. kind "h" takes 2 nodes, "r" 2 to MAX_NODES.
local function PathKey(kind, path)
	local nodes = {}
	for node in (path .. ">"):gmatch("([^>]*)>") do
		local id = node:match("^%d+$") and tonumber(node)
		if not id or id < 1 then
			return nil, "bad node"
		end
		nodes[#nodes + 1] = id
	end
	local n = #nodes
	if kind == "h" and n ~= 2 or n < 2 or n > MAX_NODES then
		return nil, "bad node count"
	end
	return table.concat(nodes, ">")
end

local function GoodSeconds(s)
	return type(s) == "number" and s >= 1 and s <= MAX_SECONDS and s == math.floor(s)
end

-- Own entries that would pass Import, as sorted "h1>2" / "r1>2>3" ids with their seconds.
local function Entries(db)
	local list, seconds = {}, {}
	local function Add(kind, tbl)
		for key, s in pairs(tbl) do
			if type(key) == "string" and PathKey(kind, key) == key and GoodSeconds(s) then
				local id = kind .. key
				list[#list + 1] = id
				seconds[id] = s
			end
		end
	end
	Add("h", db.hops)
	Add("r", db.routes)
	table.sort(list)
	return list, seconds
end

function ns.FlightShare_Export(db)
	local list, seconds = Entries(db)
	local out = {}
	for i, id in ipairs(list) do
		out[i] = id .. "=" .. seconds[id] .. ";"
	end
	return table.concat(out)
end

-- A hash of the keys only: two installs have the same keys exactly when neither has anything new for the other,
-- so slightly different seconds for the same leg never cause another sync.
function ns.FlightShare_Revision(db)
	local h = 5381
	for _, id in ipairs((Entries(db))) do
		for i = 1, #id do
			h = (h * 33 + id:byte(i)) % HASH_MOD
		end
		h = (h * 33 + 59) % HASH_MOD -- ";" between ids
	end
	return h
end

-- Returns how many entries were added, or nil, reason (then nothing was added).
function ns.FlightShare_Import(db, payload)
	if payload ~= "" and payload:sub(-1) ~= ";" then
		return nil, "unfinished payload"
	end
	local parsed = {}
	for entry in payload:gmatch("([^;]*);") do
		if #parsed >= MAX_ENTRIES then
			return nil, "too many entries"
		end
		local kind, path, s = entry:match("^([hr])([%d>]+)=(%d+)$")
		if not kind then
			return nil, "bad entry"
		end
		local key, why = PathKey(kind, path)
		s = tonumber(s)
		if not key then
			return nil, why
		elseif not GoodSeconds(s) then
			return nil, "bad seconds"
		end
		parsed[#parsed + 1] = { kind == "h" and db.hops or db.routes, key, s }
	end
	local added = 0
	for _, e in ipairs(parsed) do
		local tbl, key = e[1], e[2]
		if tbl[key] == nil then
			tbl[key] = e[3]
			added = added + 1
		end
	end
	return added
end
