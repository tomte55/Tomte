-- Run from the AddOns folder: lua Tomte/tests/test_social.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Social/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

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

test("ColorLinks paints uncolored links only", function()
	local function paint(kind, link)
		return "<" .. kind .. ">" .. link .. "</>"
	end
	eq(ns.Social_ColorLinks("got |Hitem:123::|h[Sword]|h!", paint), "got <item>|Hitem:123::|h[Sword]|h</>!")
	eq(ns.Social_ColorLinks("|Hachievement:6:x|h[A]|h and |Hspell:5|h[B]|h", paint),
		"<achievement>|Hachievement:6:x|h[A]|h</> and <spell>|Hspell:5|h[B]|h</>")
	eq(ns.Social_ColorLinks("|cffa335ee|Hitem:1|h[Sword]|h|r", paint), "|cffa335ee|Hitem:1|h[Sword]|h|r")
	eq(ns.Social_ColorLinks("|cnIQ4:|Hitem:1|h[Sword]|h|r", paint), "|cnIQ4:|Hitem:1|h[Sword]|h|r")
	eq(ns.Social_ColorLinks("|Hitem:1|h[Sword]|h", function() end), "|Hitem:1|h[Sword]|h", "nil keeps the link")
	eq(ns.Social_ColorLinks("no links", paint), "no links")
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

test("inbox: pinned conversations first, each part in order", function()
	local a, b, c, d = { key = "a" }, { key = "b", pinned = true }, { key = "c" }, { key = "d", pinned = true }
	local list, pinnedCount = ns.Inbox_Order({ a, b, c, d })
	eq(pinnedCount, 2)
	eq(list[1].key .. list[2].key .. list[3].key .. list[4].key, "bdac")
	local _, none = ns.Inbox_Order({ a, c })
	eq(none, 0)
end)

test("inbox: pinned conversations are never trimmed or pruned", function()
	local store = { convos = {
		old = { key = "old", last = 0, unread = 0, pinned = true, messages = {} },
		gone = { key = "gone", last = 0, unread = 0, messages = {} },
	} }
	ns.Social_PruneConvos(store, 100 * 86400, 86400)
	eq(store.convos.old ~= nil, true, "pinned kept")
	eq(store.convos.gone, nil, "unpinned pruned")
	for i = 1, 5 do
		store.convos["n" .. i] = { key = "n" .. i, last = 1000 + i, unread = 0, messages = {} }
	end
	ns.Social_TrimConvos(store, 2)
	eq(store.convos.old ~= nil, true, "pinned survives the trim")
	eq(store.convos.n5 ~= nil and store.convos.n4 ~= nil, true, "newest kept")
	eq(store.convos.n1, nil)
end)

test("inbox: status line", function()
	eq(ns.Inbox_StatusText(nil), "Not on your friends list")
	eq(ns.Inbox_StatusText({ online = false }), "Offline")
	eq(ns.Inbox_StatusText({ online = true, level = 80, className = "Paladin", area = "Dornogal" }),
		"Online · Level 80 Paladin · Dornogal")
	eq(ns.Inbox_StatusText({ online = true, area = "" }), "Online")
	eq(ns.Inbox_StatusText({ online = true, game = "app" }), "On the Battle.net app")
	eq(ns.Inbox_StatusText({ online = true, game = "Overwatch" }), "Online in Overwatch")
	eq(ns.Inbox_StatusText({ online = true, game = true }), "Online in another game")
end)

test("inbox: NEW divider at the first unread message", function()
	eq(ns.Inbox_NewIndex(10, 2), 9)
	eq(ns.Inbox_NewIndex(3, 5), 1, "more unread than kept")
	eq(ns.Inbox_NewIndex(10, 0), nil)
	eq(ns.Inbox_NewIndex(0, 1), nil)
end)

test("inbox: copy text strips links and colors", function()
	local convo = { key = "Kalle-Realm", name = "Kalle", messages = {
		{ at = 1, text = "Want |cff00ff00|Hitem:1|h[Sword]|h|r?", out = true },
		{ at = 2, text = "Sure" },
	} }
	eq(ns.Inbox_CopyText(convo, function(at)
		return "t" .. at
	end), "t1 You: Want [Sword]?\nt2 Kalle: Sure")
end)

test("toast flow follows where the stack sits", function()
	local W, H2 = 1920, 1080
	local function flow(x, y)
		local grow, from = ns.Toast_Flow(x, y, W, H2)
		return grow .. "/" .. from
	end
	eq(flow(200, 700), "down/left", "left, above the middle (the default spot)")
	eq(flow(1700, 900), "down/right")
	eq(flow(960, 1000), "down/top", "top middle drops in from the top")
	eq(flow(960, 150), "up/bottom", "bottom middle rises from the bottom")
	eq(flow(200, 150), "up/left", "bottom left grows up, still slides in from the side")
	eq(flow(960, 540), "down/top", "the exact middle counts as the upper half")
end)

test("Lower: accented and Cyrillic capitals, byte length kept", function()
	eq(ns.Social_Lower("ÁSGEIR"), "ásgeir")
	eq(ns.Social_Lower("Ærø Ŝtål ŁÓDŹ"), "ærø ŝtål łódź")
	eq(ns.Social_Lower("ТОМТЕ Ёж"), "томте ёж")
	eq(ns.Social_Lower("Ÿ Ŀ"), "ÿ ŀ")
	eq(ns.Social_Lower("×ß İ"), "×ß İ", "no case, or a lower case of another length")
	local s = "Ásgeir ÖRN Ŀ İ Ж"
	eq(#ns.Social_Lower(s), #s, "same length")
end)

test("FindMention: accented capitals match either way", function()
	eq(ns.Social_FindMention("Hej Ásgeir!", ns.Social_ParseWords("ásgeir")), "ásgeir")
	eq(ns.Social_FindMention("hej ásgeir", ns.Social_ParseWords("Ásgeir")), "ásgeir")
	eq(ns.Social_FindMention("ÁSGEIRS", ns.Social_ParseWords("ásgeir")), nil, "still whole words")
end)

test("IsWatched: accented capitals match", function()
	eq(ns.Social_IsWatched(ns.Social_ParseWords("ásgeir"), "Ásgeir-Draenor"), true)
	eq(ns.Social_IsWatched(ns.Social_ParseWords("ÖRN"), "Örn#1234"), true)
end)

local ME, ALT = "Player-1-AAAA", "Player-1-BBBB"

test("ConvoKey: character whispers per character, Battle.net per account", function()
	eq(ns.Social_ConvoKey("Kesha-Draenor", ME), "Kesha-Draenor@" .. ME)
	eq(ns.Social_ConvoKey("bn:Kesha#1234", ME), "bn:Kesha#1234")
	eq(ns.Social_ConvoKey("Kesha-Draenor", nil), "Kesha-Draenor")
end)

test("AddMessage tags the conversation; two characters keep two conversations", function()
	local store = newStore()
	local a = ns.Social_AddMessage(store, ns.Social_ConvoKey("Kesha-Draenor", ME),
		{ name = "Kesha", with = "Kesha-Draenor", char = ME, charName = "Aldric" }, { at = 1, text = "hi" })
	local b = ns.Social_AddMessage(store, ns.Social_ConvoKey("Kesha-Draenor", ALT),
		{ name = "Kesha", with = "Kesha-Draenor", char = ALT, charName = "Mira" }, { at = 2, text = "hey" })
	eq(a ~= b, true, "two conversations")
	eq(a.char, ME)
	eq(a.charName, "Aldric")
	eq(ns.Social_With(a), "Kesha-Draenor")
	eq(ns.Social_With(b), "Kesha-Draenor")
	eq(ns.Social_With({ key = "Old-Draenor" }), "Old-Draenor", "untagged: the key")
end)

test("IsMine: tagged ones are their character's, untagged ones everyone's", function()
	eq(ns.Social_IsMine({ char = ME }, ME), true)
	eq(ns.Social_IsMine({ char = ALT }, ME), false)
	eq(ns.Social_IsMine({}, ME), true)
end)

test("Unread and MarkAllRead count only this character's and untagged conversations", function()
	local store = newStore()
	ns.Social_AddMessage(store, "Old-Draenor", {}, { at = 1, text = "x" })
	ns.Social_AddMessage(store, "Kesha-Draenor@" .. ME, { with = "Kesha-Draenor", char = ME }, { at = 2, text = "x" })
	ns.Social_AddMessage(store, "Kesha-Draenor@" .. ALT, { with = "Kesha-Draenor", char = ALT }, { at = 3, text = "x" })
	ns.Social_AddMessage(store, "bn:Mira#1", { bn = true, with = "bn:Mira#1" }, { at = 4, text = "x" })
	local total, convos = ns.Social_Unread(store, ME)
	eq(total, 3, "mine, untagged and Battle.net")
	eq(#convos, 3)
	eq((ns.Social_Unread(store)), 4, "no GUID: all")
	ns.Social_MarkAllRead(store, ME)
	eq((ns.Social_Unread(store, ME)), 0)
	eq(store.convos["Kesha-Draenor@" .. ALT].unread, 1, "the alt's stays unread")
end)

test("AddMessage: an untagged conversation is claimed by the first character that whispers with them", function()
	local store = newStore()
	ns.Social_AddMessage(store, "Kesha-Draenor", { name = "Kesha" }, { at = 1, text = "old" })
	store.convos["Kesha-Draenor"].pinned = true
	local key = ns.Social_ConvoKey("Kesha-Draenor", ME)
	local convo, claimed = ns.Social_AddMessage(store, key,
		{ with = "Kesha-Draenor", char = ME, charName = "Aldric" }, { at = 2, text = "new" })
	eq(claimed, "Kesha-Draenor")
	eq(store.convos["Kesha-Draenor"], nil, "old key gone")
	eq(store.convos[key], convo)
	eq(convo.key, key)
	eq(#convo.messages, 2, "messages kept")
	eq(convo.pinned, true, "pin kept")
	eq(convo.name, "Kesha", "name kept")
	local _, again = ns.Social_AddMessage(store, ns.Social_ConvoKey("Kesha-Draenor", ALT),
		{ with = "Kesha-Draenor", char = ALT }, { at = 3, text = "alt" })
	eq(again, nil, "a tagged one isn't claimed")
end)

test("CopyText names a tagged conversation by who it's with", function()
	local convo = { key = "Kesha-Draenor@" .. ME, with = "Kesha-Draenor", messages = { { at = 1, text = "hi" } } }
	eq(ns.Inbox_CopyText(convo, function()
		return "t"
	end), "t Kesha-Draenor: hi")
end)

H.done()
