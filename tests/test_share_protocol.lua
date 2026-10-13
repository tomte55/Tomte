-- Run from the AddOns folder: lua Tomte/tests/test_share_protocol.lua
local ns = {}
assert(loadfile("Tomte/Modules/Share/Protocol.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("hello round trip carries version and set revisions", function()
	local text = ns.Share_BuildHello("1.12.0", { { "flight", 123456 }, { "crafting", 7 } })
	eq(text, "1^H^1.12.0^flight=123456,crafting=7")
	local msg = ns.Share_Parse(text)
	eq(msg.type, "H")
	eq(msg.version, "1.12.0")
	eq(msg.sets.flight, 123456)
	eq(msg.sets.crafting, 7)
end)

test("hello with no sets parses to an empty set list", function()
	local msg = ns.Share_Parse(ns.Share_BuildHello("1.12.0", {}))
	eq(msg.type, "H")
	eq(next(msg.sets), nil)
end)

test("request round trip", function()
	local msg = ns.Share_Parse(ns.Share_BuildRequest("flight"))
	eq(msg.type, "R")
	eq(msg.set, "flight")
end)

test("data round trip in one chunk", function()
	local list = ns.Share_BuildData("flight", 42, "h1>2=30;")
	eq(#list, 1)
	local msg = ns.Share_Parse(list[1])
	eq(msg.type, "D")
	eq(msg.set, "flight")
	eq(msg.rev, 42)
	eq(msg.index, 1)
	eq(msg.count, 1)
	eq(msg.chunk, "h1>2=30;")
end)

test("an empty payload is still one data message", function()
	local list = ns.Share_BuildData("flight", 0, "")
	eq(#list, 1)
	local msg = ns.Share_Parse(list[1])
	eq(msg.count, 1)
	eq(msg.chunk, "")
end)

test("a large payload is split into chunks of at most SHARE_CHUNK bytes", function()
	local payload = string.rep("h1234>5678=42;", 1000) -- 14000 bytes
	local list = ns.Share_BuildData("flight", 9, payload)
	eq(#list, math.ceil(#payload / ns.SHARE_CHUNK))
	local joined = {}
	for i, text in ipairs(list) do
		local msg = ns.Share_Parse(text)
		eq(msg.index, i)
		eq(msg.count, #list)
		assert(#msg.chunk <= ns.SHARE_CHUNK, "chunk too big")
		assert(#text < 4078, "message over the Battle.net limit")
		joined[i] = msg.chunk
	end
	eq(table.concat(joined), payload)
end)

test("unknown version, unknown type and garbage are rejected", function()
	local msg, reason = ns.Share_Parse("2^H^1.0^flight=1")
	eq(msg, nil)
	eq(reason, "unknown protocol 2")
	eq((ns.Share_Parse("1^X^stuff")), nil)
	eq((ns.Share_Parse("hello there")), nil)
	eq((ns.Share_Parse("")), nil)
	eq((ns.Share_Parse("1^R^Flight!")), nil, "bad set key")
	eq((ns.Share_Parse("1^H^1.0^flight=abc")), nil, "bad revision")
	eq((ns.Share_Parse("1^D^flight^1^0^1^x")), nil, "index 0")
	eq((ns.Share_Parse("1^D^flight^1^3^2^x")), nil, "index above count")
	eq((ns.Share_Parse("1^D^flight^1^1^999^x")), nil, "too many chunks")
end)

local function Parts(payload, rev)
	local msgs = {}
	for i, text in ipairs(ns.Share_BuildData("flight", rev or 5, payload)) do
		msgs[i] = ns.Share_Parse(text)
	end
	return msgs
end

test("reassembly works out of order and ignores duplicates", function()
	local payload = string.rep("r1>2>3=99;", 600)
	local msgs = Parts(payload)
	assert(#msgs >= 3, "needs several chunks")
	local inbox = {}
	local got
	for i = #msgs, 2, -1 do
		eq(ns.Share_Receive(inbox, 7, msgs[i], 100), nil, "not complete yet")
	end
	eq(ns.Share_Receive(inbox, 7, msgs[2], 100), nil, "duplicate")
	got = ns.Share_Receive(inbox, 7, msgs[1], 101)
	eq(got == payload, true, "payload")
	eq(next(inbox), nil, "finished transfer removed")
end)

test("senders and sets reassemble separately", function()
	local a, b = Parts(string.rep("a", 3000)), Parts(string.rep("b", 3000))
	local inbox = {}
	ns.Share_Receive(inbox, 1, a[1], 0)
	ns.Share_Receive(inbox, 2, b[1], 0)
	eq(ns.Share_Receive(inbox, 1, a[2], 0), string.rep("a", 3000))
	eq(ns.Share_Receive(inbox, 2, b[2], 0), string.rep("b", 3000))
end)

test("two revisions in flight reassemble separately", function()
	local old, new = Parts(string.rep("x", 3000), 1), Parts(string.rep("y", 3000), 2)
	local inbox = {}
	ns.Share_Receive(inbox, 1, old[1], 0)
	ns.Share_Receive(inbox, 1, new[1], 1)
	eq(ns.Share_Receive(inbox, 1, old[2], 2) == string.rep("x", 3000), true, "late old part finishes the old one")
	eq(ns.Share_Receive(inbox, 1, new[2], 3) == string.rep("y", 3000), true, "new one not spoiled")
end)

test("a stale unfinished transfer is dropped", function()
	local msgs = Parts(string.rep("x", 3000))
	local inbox = {}
	ns.Share_Receive(inbox, 1, msgs[1], 0)
	ns.Share_Prune(inbox, 61)
	eq(next(inbox), nil)
	eq(ns.Share_Receive(inbox, 1, msgs[2], 62), nil, "first half gone")
end)

H.done()
