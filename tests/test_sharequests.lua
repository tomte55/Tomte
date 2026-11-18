-- Run from the AddOns folder: lua Tomte/tests/test_sharequests.lua
local ns = {}
assert(loadfile("Tomte/Modules/Share/QuestsData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("an entry, and back", function()
	local q = { questID = 200, complete = false, objectives = { { have = 7, need = 7, finished = true },
		{ have = 2, need = 7 }, { label = "Find the note", finished = true } } }
	local e = ns.ShareQuests_Entry(q)
	eq(e, "200:0:7/7,2/7,1/1")
	local msg = ns.ShareQuests_Decode(ns.ShareQuests_Pack("S", { e })[1])
	eq(msg.kind, "full")
	eq(msg.quests[1].questID, 200)
	eq(msg.quests[1].complete, false)
	eq(#msg.quests[1].objectives, 3)
	eq(msg.quests[1].objectives[1].finished, true)
	eq(msg.quests[1].objectives[2].finished, false)
end)

test("a full state too long for one message continues as updates", function()
	local entries = {}
	for i = 1, 30 do
		entries[i] = ns.ShareQuests_Entry({ questID = 10000 + i, objectives = { { have = 1, need = 10 },
			{ have = 2, need = 10 } } })
	end
	local messages = ns.ShareQuests_Pack("S", entries)
	eq(#messages > 1, true)
	eq(messages[1]:sub(1, 2), "1S")
	eq(messages[2]:sub(1, 2), "1Q")
	local n = 0
	for _, m in ipairs(messages) do
		eq(#m <= 255, true)
		n = n + #ns.ShareQuests_Decode(m).quests
	end
	eq(n, 30)
end)

test("an empty log is still a full state", function()
	local messages = ns.ShareQuests_Pack("S", {})
	eq(#messages, 1)
	local msg = ns.ShareQuests_Decode(messages[1])
	eq(msg.kind, "full")
	eq(#msg.quests, 0)
	eq(#ns.ShareQuests_Pack("Q", {}), 0)
end)

test("hello, gone and turned in", function()
	eq(ns.ShareQuests_Decode(ns.ShareQuests_Hello()).kind, "hello")
	local gone = ns.ShareQuests_Decode(ns.ShareQuests_PackIDs("G", { 5, 6 })[1])
	eq(gone.kind, "gone")
	eq(gone.ids[2], 6)
	eq(ns.ShareQuests_Decode(ns.ShareQuests_PackIDs("T", { 7 })[1]).kind, "turnedIn")
end)

test("other versions and garbage are ignored", function()
	eq(ns.ShareQuests_Decode("2H"), nil)
	eq(ns.ShareQuests_Decode(""), nil)
	eq(ns.ShareQuests_Decode(nil), nil)
	eq(ns.ShareQuests_Decode("1Z"), nil)
	eq(#ns.ShareQuests_Decode("1Qnonsense|5:1:").quests, 1)
end)

test("diff: changed, gone and turned in", function()
	local before = { [1] = "1:0:1/5", [2] = "2:0:0/1", [3] = "3:1:1/1" }
	local after = { [1] = "1:0:2/5", [4] = "4:0:0/3" }
	local changed, gone, turned = ns.ShareQuests_Diff(before, after, { [3] = true })
	eq(table.concat(changed, " "), "1:0:2/5 4:0:0/3")
	eq(table.concat(gone, " "), "2")
	eq(table.concat(turned, " "), "3")
end)

-- Party lines -----------------------------------------------------------------------------------------------------------

H.done()
