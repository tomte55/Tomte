local addonName, ns = ...

-- Friend sharing: pure logic (no WoW API calls; unit-tested in tests/test_share_protocol.lua). The wire format of
-- the hidden Battle.net messages, chunking and reassembly. Sending, timers and events are in Share.lua.
-- A message is fields joined by "^" (not "|", WoW's escape character), the protocol version first:
--   1^H^<tomte version>^<set>=<rev>,...    hello: what I have
--   1^R^<set>                              request: send me that set
--   1^D^<set>^<rev>^<i>^<n>^<chunk>        data: chunk i of n of the set's payload at that revision

local VERSION = "1"
-- Bytes of payload per data message. Battle.net game data takes up to 4078 bytes (warcraft.wiki.gg
-- API_BNSendGameData), but ChatThrottleLib holds it to 255 "for reasons of traffic fairness"; 2000 sits between.
local CHUNK = 2000
local MAX_CHUNKS = 500 -- 1 MB: far above 20000 flight entries; anything bigger is not ours
local STALE = 60 -- seconds before an unfinished transfer is dropped

ns.SHARE_CHUNK = CHUNK

function ns.Share_BuildHello(version, sets)
	local list = {}
	for i, set in ipairs(sets) do
		list[i] = set[1] .. "=" .. set[2]
	end
	return VERSION .. "^H^" .. version .. "^" .. table.concat(list, ",")
end

function ns.Share_BuildRequest(key)
	return VERSION .. "^R^" .. key
end

function ns.Share_BuildData(key, rev, payload)
	local count = math.max(math.ceil(#payload / CHUNK), 1)
	local list = {}
	for i = 1, count do
		list[i] = ("%s^D^%s^%d^%d^%d^%s"):format(VERSION, key, rev, i, count, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
	end
	return list
end

local function ParseSets(text)
	local sets = {}
	if text == "" then
		return sets
	end
	for item in (text .. ","):gmatch("([^,]*),") do
		local key, rev = item:match("^(%l+)=(%d+)$")
		if not key then
			return nil
		end
		sets[key] = tonumber(rev)
	end
	return sets
end

-- Returns msg or nil, reason.
function ns.Share_Parse(text)
	local version, kind, rest = text:match("^(%d+)%^(%u)%^(.*)$")
	if not version then
		return nil, "not a Tomte message"
	elseif version ~= VERSION then
		return nil, "unknown protocol " .. version
	end
	if kind == "H" then
		local tomte, setText = rest:match("^([%w%.%-]+)%^([^%^]*)$")
		local sets = tomte and ParseSets(setText)
		if not sets then
			return nil, "bad hello"
		end
		return { type = "H", version = tomte, sets = sets }
	elseif kind == "R" then
		local key = rest:match("^(%l+)$")
		if not key then
			return nil, "bad request"
		end
		return { type = "R", set = key }
	elseif kind == "D" then
		local key, rev, index, count, chunk = rest:match("^(%l+)%^(%d+)%^(%d+)%^(%d+)%^(.*)$")
		index, count = tonumber(index), tonumber(count)
		if not key or index < 1 or index > count or count > MAX_CHUNKS then
			return nil, "bad data"
		end
		return { type = "D", set = key, rev = tonumber(rev), index = index, count = count, chunk = chunk }
	end
	return nil, "unknown message " .. kind
end

-- inbox: [from:set:rev] = { count, parts, got, at }. Returns the whole payload once every chunk is in.
-- Battle.net delivery isn't ordered, so chunks go in by index. Revisions are hashes, not ordered, so each one
-- reassembles on its own (a late chunk of an older one can't spoil a newer one); unfinished ones go stale.
function ns.Share_Receive(inbox, from, msg, now)
	local id = from .. ":" .. msg.set .. ":" .. msg.rev
	local t = inbox[id]
	if not t or t.count ~= msg.count or now - t.at > STALE then
		t = { count = msg.count, parts = {}, got = 0 }
		inbox[id] = t
	end
	t.at = now
	if not t.parts[msg.index] then
		t.parts[msg.index] = msg.chunk
		t.got = t.got + 1
	end
	if t.got < t.count then
		return nil
	end
	inbox[id] = nil
	return table.concat(t.parts, "", 1, t.count)
end

local function VersionParts(text)
	if type(text) ~= "string" or not text:match("^%d+[%d%.]*$") or text:match("%.%.") or text:match("%.$") then
		return nil
	end
	local parts = {}
	for n in text:gmatch("%d+") do
		parts[#parts + 1] = tonumber(n)
	end
	return parts
end

-- True when Tomte version a is newer than b ("1.12.0" > "1.11.3", missing parts are 0). Anything but dotted
-- numbers (a dev checkout's "?", "1.12.0-beta") is never newer, so nobody is told to update by an odd string.
function ns.Share_NewerVersion(a, b)
	local pa, pb = VersionParts(a), VersionParts(b)
	if not (pa and pb) then
		return false
	end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x > y
		end
	end
	return false
end

function ns.Share_Prune(inbox, now)
	for id, t in pairs(inbox) do
		if now - t.at > STALE then
			inbox[id] = nil
		end
	end
end
