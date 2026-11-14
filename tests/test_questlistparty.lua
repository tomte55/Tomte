-- Run from the AddOns folder: lua Tomte/tests/test_questlistparty.lua
local ns = {}
assert(loadfile("Tomte/Modules/QuestList/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/QuestList/PartyData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ME, PALA, KESHA = "Player-1-ME", "Player-1-PALA", "Player-1-KESHA"

local LOGGERS = { questID = 100, title = "Goblin Invaders",
	objectives = { { label = "Venture Co. Logger slain", have = 4, need = 15 } } }
local FEEDERS = { questID = 200, title = "Blood Feeders",
	objectives = { { label = "Deepmoss Venomspitter slain", have = 7, need = 7, finished = true },
		{ label = "Deepmoss Creeper slain", have = 2, need = 7 } } }

-- Tooltip reads ---------------------------------------------------------------------------------------------------------

test("grouped tooltip: each party member's count, matched to your objective", function()
	local lines = {
		{ kind = "title", text = "Goblin Invaders" },
		{ kind = "player", guid = ME },
		{ kind = "objective", text = "4/15 Venture Co. Logger slain", completed = false },
		{ kind = "player", guid = PALA },
		{ kind = "objective", text = "9/15 Venture Co. Logger slain", completed = false },
	}
	local read = ns.QuestListParty_ReadTooltip(lines, { LOGGERS }, ME)
	eq(read[ME], nil)
	eq(read[PALA][100][1].have, 9)
	eq(read[PALA][100][1].need, 15)
	eq(read[PALA][100][1].finished, false)
end)

test("a finished objective, and the second of two", function()
	local lines = {
		{ kind = "title", text = "Blood Feeders" },
		{ kind = "player", guid = PALA },
		{ kind = "objective", text = "7/7 Deepmoss Venomspitter slain", completed = true },
		{ kind = "player", guid = KESHA },
		{ kind = "objective", text = "Deepmoss Creeper slain: 3/7", completed = false },
	}
	local read = ns.QuestListParty_ReadTooltip(lines, { LOGGERS, FEEDERS }, ME)
	eq(read[PALA][200][1].finished, true)
	eq(read[KESHA][200][2].have, 3)
	eq(read[KESHA][200][1], nil)
end)

test("the title line's quest ID wins over its text", function()
	local lines = {
		{ kind = "title", text = "Something else", id = 100 },
		{ kind = "player", guid = PALA },
		{ kind = "objective", text = "1/15 Venture Co. Logger slain" },
	}
	eq(ns.QuestListParty_ReadTooltip(lines, { LOGGERS }, ME)[PALA][100][1].have, 1)
end)

test("solo tooltips, quests not in your log and unknown objectives are left out", function()
	local lines = {
		{ kind = "title", text = "Goblin Invaders" },
		{ kind = "objective", text = "4/15 Venture Co. Logger slain" },
		{ kind = "title", text = "Someone else's quest" },
		{ kind = "player", guid = PALA },
		{ kind = "objective", text = "2/8 Fangs" },
		{ kind = "title", text = "Goblin Invaders" },
		{ kind = "player", guid = PALA },
		{ kind = "objective", text = "1/1 Something you don't need" },
	}
	eq(next(ns.QuestListParty_ReadTooltip(lines, { LOGGERS }, ME)), nil)
end)

-- Sync ------------------------------------------------------------------------------------------------------------------

test("an entry, and back", function()
	local q = { questID = 200, complete = false, objectives = { { have = 7, need = 7, finished = true },
		{ have = 2, need = 7 }, { label = "Find the note", finished = true } } }
	local e = ns.QuestListParty_Entry(q)
	eq(e, "200:0:7/7,2/7,1/1")
	local msg = ns.QuestListParty_Decode(ns.QuestListParty_Pack("S", { e })[1])
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
		entries[i] = ns.QuestListParty_Entry({ questID = 10000 + i, objectives = { { have = 1, need = 10 },
			{ have = 2, need = 10 } } })
	end
	local messages = ns.QuestListParty_Pack("S", entries)
	eq(#messages > 1, true)
	eq(messages[1]:sub(1, 2), "1S")
	eq(messages[2]:sub(1, 2), "1Q")
	local n = 0
	for _, m in ipairs(messages) do
		eq(#m <= 255, true)
		n = n + #ns.QuestListParty_Decode(m).quests
	end
	eq(n, 30)
end)

test("an empty log is still a full state", function()
	local messages = ns.QuestListParty_Pack("S", {})
	eq(#messages, 1)
	local msg = ns.QuestListParty_Decode(messages[1])
	eq(msg.kind, "full")
	eq(#msg.quests, 0)
	eq(#ns.QuestListParty_Pack("Q", {}), 0)
end)

test("hello, gone and turned in", function()
	eq(ns.QuestListParty_Decode(ns.QuestListParty_Hello()).kind, "hello")
	local gone = ns.QuestListParty_Decode(ns.QuestListParty_PackIDs("G", { 5, 6 })[1])
	eq(gone.kind, "gone")
	eq(gone.ids[2], 6)
	eq(ns.QuestListParty_Decode(ns.QuestListParty_PackIDs("T", { 7 })[1]).kind, "turnedIn")
end)

test("other versions and garbage are ignored", function()
	eq(ns.QuestListParty_Decode("2H"), nil)
	eq(ns.QuestListParty_Decode(""), nil)
	eq(ns.QuestListParty_Decode(nil), nil)
	eq(ns.QuestListParty_Decode("1Z"), nil)
	eq(#ns.QuestListParty_Decode("1Qnonsense|5:1:").quests, 1)
end)

test("diff: changed, gone and turned in", function()
	local before = { [1] = "1:0:1/5", [2] = "2:0:0/1", [3] = "3:1:1/1" }
	local after = { [1] = "1:0:2/5", [4] = "4:0:0/3" }
	local changed, gone, turned = ns.QuestListParty_Diff(before, after, { [3] = true })
	eq(table.concat(changed, " "), "1:0:2/5 4:0:0/3")
	eq(table.concat(gone, " "), "2")
	eq(table.concat(turned, " "), "3")
end)

-- Party lines -----------------------------------------------------------------------------------------------------------

test("counts under each objective, in party order", function()
	local members = {
		{ name = "Pala", class = "PALADIN", onQuest = true, quest = { objectives = { [2] = { have = 5, need = 7 } } } },
		{ name = "Kesha", class = "MAGE", onQuest = true, quest = { objectives = { [2] = { have = 7, need = 7,
			finished = true } } } },
	}
	local lines = ns.QuestListParty_Lines(FEEDERS, members, { missing = true })
	eq(lines.objectives[1], nil)
	eq(lines.objectives[2][1].name, "Pala")
	eq(lines.objectives[2][2].finished, true)
	eq(#lines.waiting, 0)
end)

test("on it without a count, missing, turned in", function()
	local members = {
		{ name = "Pala", onQuest = true },
		{ name = "Kesha", onQuest = false },
		{ name = "Mira", onQuest = false, turnedIn = true },
		{ name = "Aldric" }, -- unknown: nothing to say
	}
	local lines = ns.QuestListParty_Lines(LOGGERS, members, { missing = true })
	eq(lines.waiting[1].name, "Pala")
	eq(lines.missing[1].name, "Kesha")
	eq(lines.turnedIn[1].name, "Mira")
	eq(ns.QuestListParty_Summary(lines), "Pala has it too · Kesha doesn't have it · Mira turned it in")
end)

test("missing only when asked; nothing to say is nil", function()
	eq(ns.QuestListParty_Lines(LOGGERS, { { name = "Kesha", onQuest = false } }, { missing = false }), nil)
	eq(ns.QuestListParty_Lines(LOGGERS, {}, {}), nil)
	eq(ns.QuestListParty_Summary(nil), nil)
end)

test("counts read before they dropped the quest don't show", function()
	local members = { { name = "Pala", onQuest = false, quest = { objectives = { [1] = { have = 3, need = 15 } } } } }
	local lines = ns.QuestListParty_Lines(LOGGERS, members, { missing = true })
	eq(lines.objectives[1], nil)
	eq(lines.missing[1].name, "Pala")
end)

test("a synced member's finished quest counts every objective as done", function()
	local members = { { name = "Pala", onQuest = true, quest = { complete = true,
		objectives = { [1] = { have = 1, need = 7 } } } } }
	eq(ns.QuestListParty_Lines(FEEDERS, members, {}).objectives[1][1].finished, true)
end)

test("summary names: two and three", function()
	local lines = { waiting = { { name = "A" }, { name = "B" } }, missing = { { name = "C" }, { name = "D" },
		{ name = "E" } }, turnedIn = {} }
	eq(ns.QuestListParty_Summary(lines, function(n)
		return "<" .. n .. ">"
	end), "<A> and <B> have it too · <C>, <D> and <E> don't have it")
end)

test("under a hidden objective, only members who still need it", function()
	local entries = { { name = "Pala", finished = true }, { name = "Kesha", finished = false } }
	eq(#ns.QuestListParty_At(entries, true), 2)
	local at = ns.QuestListParty_At(entries, false)
	eq(#at, 1)
	eq(at[1].name, "Kesha")
	eq(#ns.QuestListParty_At(nil, true), 0)
end)

test("count text", function()
	eq(ns.QuestListParty_CountText({ have = 9, need = 15 }, { need = 15 }), "9/15")
	eq(ns.QuestListParty_CountText({ have = 1, need = 1, finished = true }, { label = "Find the note" }), "done")
	eq(ns.QuestListParty_CountText({ have = 0, need = 1 }, { label = "Find the note" }), "not yet")
end)

-- Chat ------------------------------------------------------------------------------------------------------------------

test("chat line: link and each objective", function()
	local out = ns.QuestListParty_ChatLines("[Blood Feeders]", FEEDERS.objectives, false)
	eq(#out, 1)
	eq(out[1], "[Blood Feeders]: 7/7 Deepmoss Venomspitter slain, 2/7 Deepmoss Creeper slain")
	eq(ns.QuestListParty_ChatLines("[X]", { { label = "Find the note", finished = true } })[1], "[X]: Find the note (done)")
	eq(ns.QuestListParty_ChatLines("[X]", {}, true)[1], "[X] done, ready to turn in")
	eq(ns.QuestListParty_ChatLines("[X]", {}, false)[1], "[X]")
end)

test("find group lines", function()
	eq(ns.QuestListParty_GroupText("LFG", "[X]", false, 1, 5), "LFG [X]")
	eq(ns.QuestListParty_GroupText("LFM", "[X]", false, 1, 5), "LFM [X]")
	eq(ns.QuestListParty_GroupText("LFM", "[X]", true, 2, 5), "LFM [X] (elite), 2/5")
	eq(ns.QuestListParty_GroupText("LFM", "[X]", false, 12, nil), "LFM [X]")
	eq(ns.QuestListParty_GroupText("LFG", "[X]", true, 3, 5), "LFG [X] (elite)")
end)

test("a long progress splits into messages of at most 255", function()
	local objectives = {}
	for i = 1, 8 do
		objectives[i] = { label = ("A rather long objective name number %d slain"):format(i), have = 1, need = 10 }
	end
	local out = ns.QuestListParty_ChatLines(("|cffffff00|Hquest:100:20|h[Goblin Invaders]|h|r"), objectives, false)
	eq(#out > 1, true)
	for _, m in ipairs(out) do
		eq(#m <= 255, true)
	end
	eq(out[2]:sub(1, 2), "1/")
end)

H.done()
