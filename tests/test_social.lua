-- Run from the AddOns folder: lua Tomte/tests/test_social.lua
local ns = {}
assert(loadfile("Tomte/Modules/Social/Data.lua"))("Tomte", ns)

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

local function newStore()
	return { convos = {} }
end

test("HoldTime grows with the text, within bounds", function()
	eq(ns.Social_HoldTime("", 6, 0.05, 15), 6)
	eq(ns.Social_HoldTime(("x"):rep(100), 6, 0.05, 15), 11)
	eq(ns.Social_HoldTime(("x"):rep(1000), 6, 0.05, 15), 15)
	eq(ns.Social_HoldTime(nil, 6, 0.05, 15), 6)
end)

test("AddMessage counts unread and an answer marks it read", function()
	local store = newStore()
	ns.Social_AddMessage(store, "Thrall-Draenor", { name = "Thrall" }, { at = 10, text = "hi" })
	local convo = ns.Social_AddMessage(store, "Thrall-Draenor", { name = "Thrall", class = "SHAMAN" }, { at = 20, text = "raid?" })
	eq(convo.unread, 2)
	eq(convo.class, "SHAMAN")
	eq(convo.last, 20)
	eq(#convo.messages, 2)
	ns.Social_AddMessage(store, "Thrall-Draenor", {}, { at = 30, text = "yes", out = true })
	eq(convo.unread, 0)
	eq(convo.name, "Thrall", "name kept")
	eq(#convo.messages, 3)
end)

test("AddMessage keeps the newest 50 messages", function()
	local store = newStore()
	for i = 1, 60 do
		ns.Social_AddMessage(store, "a", {}, { at = i, text = "m" .. i })
	end
	local messages = store.convos.a.messages
	eq(#messages, 50)
	eq(messages[1].text, "m11")
	eq(messages[50].text, "m60")
end)

test("TrimConvos drops the oldest read conversations only", function()
	local store = newStore()
	for i = 1, 5 do
		ns.Social_AddMessage(store, "c" .. i, {}, { at = i, text = "x" })
	end
	ns.Social_MarkRead(store, "c2")
	ns.Social_MarkRead(store, "c3")
	ns.Social_TrimConvos(store, 2)
	eq(store.convos.c1 ~= nil, true, "unread c1 kept")
	eq(store.convos.c2, nil)
	eq(store.convos.c3, nil)
	eq(store.convos.c5 ~= nil, true)
end)

test("TrimConvos caps unread conversations at twice the max, oldest first", function()
	local store = newStore()
	for i = 1, 7 do
		ns.Social_AddMessage(store, "c" .. i, {}, { at = i, text = "x" })
	end
	ns.Social_MarkRead(store, "c5")
	ns.Social_TrimConvos(store, 2)
	-- c5 (read, past max) goes first; then the oldest unread down to 4
	eq(store.convos.c5, nil)
	eq(store.convos.c1, nil)
	eq(store.convos.c2, nil)
	eq(store.convos.c3 ~= nil, true)
	eq(store.convos.c7 ~= nil, true)
	local n = 0
	for _ in pairs(store.convos) do
		n = n + 1
	end
	eq(n, 4)
end)

test("AddMessage keeps spam from piling up past twice the max", function()
	local store = newStore()
	for i = 1, 100 do
		ns.Social_AddMessage(store, "spam" .. i, {}, { at = i, text = "buy gold" })
	end
	local n = 0
	for _ in pairs(store.convos) do
		n = n + 1
	end
	eq(n, 60)
	eq(store.convos.spam100 ~= nil, true)
	eq(store.convos.spam1, nil)
end)

test("PruneConvos forgets old read conversations, and unread ones after twice the age", function()
	local store = newStore()
	ns.Social_AddMessage(store, "old", {}, { at = 0, text = "x" })
	ns.Social_AddMessage(store, "oldUnread", {}, { at = 0, text = "x" })
	ns.Social_AddMessage(store, "ancientUnread", {}, { at = -1000, text = "x" })
	ns.Social_AddMessage(store, "new", {}, { at = 900, text = "x" })
	ns.Social_MarkRead(store, "old")
	ns.Social_MarkRead(store, "new")
	ns.Social_PruneConvos(store, 1000, 500)
	eq(store.convos.old, nil)
	eq(store.convos.oldUnread ~= nil, true)
	eq(store.convos.ancientUnread, nil)
	eq(store.convos.new ~= nil, true)
	ns.Social_PruneConvos(store, 1000, 500, 900)
	eq(store.convos.oldUnread, nil)
end)

test("Unread totals messages and lists conversations newest first", function()
	local store = newStore()
	ns.Social_AddMessage(store, "a", {}, { at = 1, text = "x" })
	ns.Social_AddMessage(store, "b", {}, { at = 2, text = "x" })
	ns.Social_AddMessage(store, "b", {}, { at = 3, text = "x" })
	ns.Social_AddMessage(store, "c", {}, { at = 4, text = "x" })
	ns.Social_MarkRead(store, "c")
	local total, convos = ns.Social_Unread(store)
	eq(total, 3)
	eq(#convos, 2)
	eq(convos[1].key, "b")
	eq(convos[2].key, "a")
	ns.Social_MarkAllRead(store)
	eq((ns.Social_Unread(store)), 0)
end)

test("NameList joins names and caps the list", function()
	eq(ns.Social_NameList({}), "")
	eq(ns.Social_NameList({ "Anna" }), "Anna")
	eq(ns.Social_NameList({ "Anna", "Björn" }), "Anna and Björn")
	eq(ns.Social_NameList({ "Anna", "Björn", "Cecilia" }), "Anna, Björn and Cecilia")
	eq(ns.Social_NameList({ "A", "B", "C", "D", "E" }, 3), "A, B, C and 2 more")
end)

test("ShortTag strips the BattleTag number", function()
	eq(ns.Social_ShortTag("Anna#1234"), "Anna")
	eq(ns.Social_ShortTag("Anna"), "Anna")
	eq(ns.Social_ShortTag(nil), nil)
end)

test("ParseWords trims, lowers and dedupes", function()
	local words = ns.Social_ParseWords(" Tomte, tank ,, TOMTE,heal ")
	eq(#words, 3)
	eq(words[1], "tomte")
	eq(words[2], "tank")
	eq(words[3], "heal")
	eq(#ns.Social_ParseWords(""), 0)
	eq(#ns.Social_ParseWords(nil), 0)
end)

test("PlainText strips colors, links and textures", function()
	eq(ns.Social_PlainText("|cffff0000red|r text"), "red text")
	eq(ns.Social_PlainText("got |cffa335ee|Hitem:123::|h[Sword]|h|r!"), "got [Sword]!")
	eq(ns.Social_PlainText("|TInterface\\Icons\\x:0|t hi"), " hi")
end)

test("FindMention matches whole words only, any case", function()
	local words = { "tomte", "tank" }
	eq(ns.Social_FindMention("hey Tomte, you there?", words), "tomte")
	eq(ns.Social_FindMention("TOMTE", words), "tomte")
	eq(ns.Social_FindMention("tomte's pet", words), "tomte")
	eq(ns.Social_FindMention("tomtes are small", words), nil)
	eq(ns.Social_FindMention("atomte", words), nil)
	eq(ns.Social_FindMention("need a tank", words), "tank")
	eq(ns.Social_FindMention("tanks", words), nil)
	eq(ns.Social_FindMention("tomtes and tomte", words), "tomte", "second occurrence")
	eq(ns.Social_FindMention("x", {}), nil)
	eq(ns.Social_FindMention(nil, words), nil)
end)

test("FindMention treats UTF-8 letters as part of a word", function()
	local words = { "björn" }
	eq(ns.Social_FindMention("hej björn!", words), "björn")
	eq(ns.Social_FindMention("björnå", words), nil)
end)

test("FindMention ignores names inside links' hidden part but sees the shown text", function()
	local words = { "tomte" }
	eq(ns.Social_FindMention("|Hplayer:Other|h[Tomte]|h", words), "tomte")
	eq(ns.Social_FindMention("|Hitem:tomte|h[Sword]|h", words), nil)
end)

test("Ago formats short relative times", function()
	eq(ns.Social_Ago(5), "now")
	eq(ns.Social_Ago(300), "5m")
	eq(ns.Social_Ago(7200), "2h")
	eq(ns.Social_Ago(200000), "2d")
end)

test("Digest counts merged toasts and lists distinct names in order", function()
	local count, names = ns.Social_Digest({
		{ digestName = "Thrall", count = 2 },
		{ digestName = "Jaina" },
		{ digestName = "Thrall" },
		{},
	})
	eq(count, 5)
	eq(#names, 2)
	eq(names[1], "Thrall")
	eq(names[2], "Jaina")
end)

test("IsWatched matches names, BattleTags with or without number, and realms", function()
	local watch = ns.Social_ParseWords("Anna, thrall, Cecilia#4321")
	eq(ns.Social_IsWatched(watch, "Anna#1234"), true)
	eq(ns.Social_IsWatched(watch, "Thrall-Draenor"), true)
	eq(ns.Social_IsWatched(watch, "Cecilia#4321"), true)
	eq(ns.Social_IsWatched(watch, "Cecilia#9999"), false)
	eq(ns.Social_IsWatched(watch, nil, "", "Björn"), false)
	eq(ns.Social_IsWatched(watch, nil, "ANNA"), true)
	eq(ns.Social_IsWatched({}, "Anna"), false)
end)

test("NewlyOnline lists new keys, none on the first look", function()
	eq(#ns.Social_NewlyOnline(nil, { a = true }), 0)
	local list = ns.Social_NewlyOnline({ a = true }, { a = true, c = true, b = true })
	eq(#list, 2)
	eq(list[1], "b")
	eq(list[2], "c")
end)

test("NewlyOnline skips keys that weren't known before", function()
	local list = ns.Social_NewlyOnline({ a = true }, { a = true, b = true, c = true }, { a = true, b = true })
	eq(#list, 1)
	eq(list[1], "b")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
