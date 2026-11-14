-- Run from the AddOns folder: lua Tomte/tests/test_profile_wire.lua
local ns = {}
assert(loadfile("Tomte/Core/Profile.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/ProfileWire.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Text(n)
	local parts = { "Tomte1:" }
	local i = 0
	while #table.concat(parts) < n do
		i = i + 1
		parts[#parts + 1] = string.char(65 + i % 26) .. ":"
	end
	return table.concat(parts):sub(1, n)
end

test("offer, accept, no and result round trip", function()
	local o = ns.ProfileWire_Parse(ns.ProfileWire_Offer("ab12", 5000))
	eq(o.kind, "O")
	eq(o.tid, "ab12")
	eq(o.size, 5000)
	local a = ns.ProfileWire_Parse(ns.ProfileWire_Accept("ab12"))
	eq(a.kind, "A")
	eq(a.tid, "ab12")
	local n = ns.ProfileWire_Parse(ns.ProfileWire_No("ab12", "busy"))
	eq(n.kind, "N")
	eq(n.reason, "busy")
	local r = ns.ProfileWire_Parse(ns.ProfileWire_Result("ab12", "shown"))
	eq(r.kind, "R")
	eq(r.outcome, "shown")
end)

test("data fits the message size and reassembles in any order, duplicates too", function()
	local s = Text(3000)
	local list = ns.ProfileWire_Data("t", s, 255)
	assert(#list > 1, "more than one message")
	for _, m in ipairs(list) do
		assert(#m <= 255, "message too long: " .. #m)
	end
	local inbox = ns.ProfileWire_NewInbox()
	local got
	for i = #list, 1, -1 do
		local part = ns.ProfileWire_Parse(list[i])
		eq(part.kind, "D")
		got = ns.ProfileWire_Add(inbox, "Mira-Realm:t", part, 1) or got
		if i == 2 then
			eq(ns.ProfileWire_Add(inbox, "Mira-Realm:t", part, 1), nil, "duplicate doesn't finish it")
		end
	end
	eq(got, s)
end)

test("short and empty text are one message each", function()
	eq(#ns.ProfileWire_Data("t", "Tomte1:abc", 255), 1)
	local list = ns.ProfileWire_Data("t", "", 255)
	eq(#list, 1)
	local inbox = ns.ProfileWire_NewInbox()
	eq(ns.ProfileWire_Add(inbox, "k", ns.ProfileWire_Parse(list[1]), 0), "")
end)

test("parse rejects other versions, unknown kinds and bad numbers", function()
	for _, bad in ipairs({ "2:O:x:1", "1:Z:x", "1:D:t:0:3:x", "1:D:t:4:3:x", "1:D:t:1:999:x", "1:O:x:abc",
		"1:N:x:", "", "nonsense" }) do
		eq(ns.ProfileWire_Parse(bad), nil, bad)
	end
	eq(ns.ProfileWire_Parse(nil), nil, "nil")
end)

test("a transfer older than the stale time is dropped", function()
	local inbox = ns.ProfileWire_NewInbox()
	local list = ns.ProfileWire_Data("t", Text(600), 255)
	eq(ns.ProfileWire_Add(inbox, "a", ns.ProfileWire_Parse(list[1]), 0), nil)
	ns.ProfileWire_Add(inbox, "b", ns.ProfileWire_Parse(ns.ProfileWire_Data("u", Text(600), 255)[1]), 61)
	local done
	for i = 2, #list do
		done = ns.ProfileWire_Add(inbox, "a", ns.ProfileWire_Parse(list[i]), 61) or done
	end
	eq(done, nil, "first chunk was dropped with the stale entry")
end)

test("data longer than a settings string can be is refused", function()
	local inbox = ns.ProfileWire_NewInbox()
	local chunk = string.rep("x", 200)
	local n = math.floor(ns.PROFILE_MAX_TEXT / 200) + 5
	local text, err
	for i = 1, n do
		text, err = ns.ProfileWire_Add(inbox, "k", { kind = "D", tid = "t", i = i, n = n, chunk = chunk }, 0)
		if err then
			break
		end
	end
	eq(text, nil)
	eq(err, "too long")
end)

test("one question per sender every ten minutes", function()
	eq(ns.ProfileWire_MayAsk(nil, 5), true)
	eq(ns.ProfileWire_MayAsk(0, 599), false)
	eq(ns.ProfileWire_MayAsk(0, 600), true)
end)

H.done()
