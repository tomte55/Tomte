local addonName, ns = ...

-- Sending settings to a player: pure logic (no WoW API calls; unit-tested in tests/test_profile_wire.lua). The
-- messages of one transfer, chunking and reassembly. Sending, routes and the questions are in Panel/ShareSend.lua.
-- A message is fields joined by ":" (the settings string is Base64 after "Tomte1:", so the chunk is always last):
--   1:O:<tid>:<size>              offer: I'd like to send you my settings (size: bytes of the string)
--   1:A:<tid>                     accept: send them
--   1:N:<tid>:<reason>            no: declined, busy (another offer is open) or off (they don't take settings)
--   1:D:<tid>:<i>:<n>:<chunk>     data: chunk i of n of the settings string
--   1:R:<tid>:<outcome>           result: shown (the preview is open), same (nothing would change), bad (couldn't
--                                 be read), cancelled (closed without importing)

local VERSION = "1"
local ASK_GAP = 600 -- seconds: one question per sender in this time, so nobody can keep popping it up
local HEADER_ROOM = 24 -- bytes a data message's fields take before its chunk: "1:D:<6>:<3>:<3>:" with room to spare

ns.PROFILEWIRE_PREFIX = "TomteProfile" -- addon message prefix (16 characters at most)
ns.PROFILEWIRE_WHISPER = 255 -- bytes per addon whisper (warcraft.wiki.gg API_C_ChatInfo.SendAddonMessage)
ns.PROFILEWIRE_BNET = 1900 -- bytes per Friend sharing message: under ns.SHARE_CHUNK with room for its "<id>;"
ns.PROFILEWIRE_MAX_CHUNKS = 200 -- far above a settings string at whisper size; anything bigger is not ours
ns.PROFILEWIRE_STALE = 60 -- seconds before an unfinished transfer is dropped

local KINDS = { O = true, A = true, N = true, D = true, R = true }

function ns.ProfileWire_Offer(tid, size)
	return VERSION .. ":O:" .. tid .. ":" .. size
end

function ns.ProfileWire_Accept(tid)
	return VERSION .. ":A:" .. tid
end

function ns.ProfileWire_No(tid, reason)
	return VERSION .. ":N:" .. tid .. ":" .. reason
end

function ns.ProfileWire_Result(tid, outcome)
	return VERSION .. ":R:" .. tid .. ":" .. outcome
end

-- The settings string as data messages, each at most size bytes.
function ns.ProfileWire_Data(tid, text, size)
	local room = size - HEADER_ROOM
	local n = math.max(1, math.ceil(#text / room))
	local list = {}
	for i = 1, n do
		list[i] = ("%s:D:%s:%d:%d:%s"):format(VERSION, tid, i, n, text:sub((i - 1) * room + 1, i * room))
	end
	return list
end

-- A received message as a table, or nil for anything that isn't one of ours in this version.
function ns.ProfileWire_Parse(msg)
	if type(msg) ~= "string" then
		return nil
	end
	local version, kind, tid, rest = msg:match("^([^:]+):(%u):([%w]+):?(.*)$")
	if version ~= VERSION or not KINDS[kind] then
		return nil
	end
	if kind == "A" then
		return { kind = kind, tid = tid }
	elseif kind == "O" then
		local size = tonumber(rest:match("^(%d+)$"))
		return size and { kind = kind, tid = tid, size = size } or nil
	elseif kind == "N" then
		local reason = rest:match("^(%l+)$")
		return reason and { kind = kind, tid = tid, reason = reason } or nil
	elseif kind == "R" then
		local outcome = rest:match("^(%l+)$")
		return outcome and { kind = kind, tid = tid, outcome = outcome } or nil
	end
	local i, n, chunk = rest:match("^(%d+):(%d+):(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not i or i < 1 or i > n or n > ns.PROFILEWIRE_MAX_CHUNKS then
		return nil
	end
	return { kind = kind, tid = tid, i = i, n = n, chunk = chunk }
end

function ns.ProfileWire_NewInbox()
	return {}
end

-- Adds a data part under key (sender and transfer). The whole string once every chunk is in; nil while some are
-- missing; nil, "too long" when it grows past a settings string's size (the transfer is dropped).
function ns.ProfileWire_Add(inbox, key, part, now)
	for k, entry in pairs(inbox) do
		if now - entry.at > ns.PROFILEWIRE_STALE then
			inbox[k] = nil
		end
	end
	local entry = inbox[key]
	if not entry or entry.n ~= part.n then
		entry = { n = part.n, chunks = {}, have = 0, bytes = 0 }
		inbox[key] = entry
	end
	entry.at = now
	if not entry.chunks[part.i] then
		entry.chunks[part.i] = part.chunk
		entry.have = entry.have + 1
		entry.bytes = entry.bytes + #part.chunk
	end
	if entry.bytes > ns.PROFILE_MAX_TEXT then
		inbox[key] = nil
		return nil, "too long"
	end
	if entry.have < entry.n then
		return nil
	end
	inbox[key] = nil
	return table.concat(entry.chunks, "", 1, entry.n)
end

-- Whether a sender may be asked again: never asked, or the last question was ASK_GAP seconds ago.
function ns.ProfileWire_MayAsk(lastAskedAt, now)
	return lastAskedAt == nil or now - lastAskedAt >= ASK_GAP
end
