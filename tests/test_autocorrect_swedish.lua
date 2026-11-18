-- Run from the AddOns folder: lua Tomte/tests/test_autocorrect_swedish.lua
local ns = {}
for _, file in ipairs({ "Words", "WordsSwedish", "Data", "Swedish", "Rules", "Line" }) do
	assert(loadfile("Tomte/Modules/Autocorrect/" .. file .. ".lua"))("Tomte", ns)
end

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local dict = ns.Autocorrect_NewDict(ns.AUTOCORRECT_WORDS, ns.AUTOCORRECT_UPPER, ns.AUTOCORRECT_CONTRACTIONS)
local sv = ns.Autocorrect_SwedishDict(ns.AUTOCORRECT_SV_WORDS, ns.AUTOCORRECT_SV_LETTERS)
local places, places2 = ns.Autocorrect_Places(ns.AUTOCORRECT_PLACES, dict)
local ALL = { spelling = true, apostrophes = true, capitals = true, names = true, pairs = true, tidying = true }

local function ctx(extra)
	local c = { dict = dict, sv = sv, kinds = ALL, own = {}, keep = {}, refused = {}, names = {}, places = places,
		places2 = places2 }
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	return c
end

local function fix(word, lang)
	return (ns.Autocorrect_Word(word, ctx({ lang = lang })))
end

local function fixes(cases, lang)
	for typed, want in pairs(cases) do
		eq(fix(typed, lang), want, typed)
	end
end

-- The line after typing its last character (cursor at the end).
local function typed(text, extra)
	local out = ns.Autocorrect_Finish(text, #text, ctx(extra))
	return out or text
end

test("å, ä, ö: lowercase, capitals and letters", function()
	eq(ns.Autocorrect_Lower("ÅSA ÄR ÖL"), "åsa är öl")
	eq(ns.Autocorrect_CapitalFirst("är"), "Är")
	eq(ns.Autocorrect_CapitalFirst("jag"), "Jag")
	eq(ns.Autocorrect_StartsUpper("Örjan"), true)
	eq(ns.Autocorrect_StartsUpper("öl"), false)
	eq(ns.Autocorrect_SwedishLetters("kärleksbrev"), true)
	eq(ns.Autocorrect_SwedishLetters("på3"), false)
end)

test("the word list: everyday words, and spellings without å, ä, ö left out", function()
	for _, word in ipairs({ "jag", "och", "inte", "är", "på", "också", "måste", "gärna" }) do
		eq(sv.level[word] ~= nil, true, word)
	end
	for _, word in ipairs({ "ar", "pa", "maste", "garna" }) do
		eq(sv.level[word], nil, word)
		eq(sv.letters[word] ~= nil, true, word)
	end
	for typo in pairs(ns.AUTOCORRECT_SV_TYPOS) do
		eq(sv.level[typo], nil, "a Swedish typo isn't a Swedish word: " .. typo)
	end
end)

test("which language a line is in", function()
	local function lang(...)
		return ns.Autocorrect_Language({ ... }, dict.level, sv.level, sv.letters)
	end
	eq(lang("jag", "vill"), "sv")
	eq(lang("kan", "du"), "sv")
	eq(lang("hey", "you"), "en")
	eq(lang("what", "are", "you"), "en")
	eq(lang("ok"), nil, "chat shorthand belongs to both")
	eq(lang("i", "think"), "en", "a small i says nothing")
	eq(lang("pa"), "sv", "a Swedish word missing its å counts")
	eq(lang("grön"), "sv", "å, ä, ö count")
	eq(lang(), nil)
	eq(lang("i"), nil)
end)

test("Swedish words are never fixed into English, whatever the line", function()
	fixes({ jag = nil, och = nil, inte = nil, kanske = nil, ["också"] = nil }, "en")
	fixes({ jag = nil, och = nil, inte = nil }, nil)
end)

test("in a Swedish line: å, ä, ö put back, Swedish typos and guesses", function()
	fixes({ pa = "på", ar = "är", ["for"] = "för", maste = "måste", ocksa = "också", garna = "gärna", Ar = "Är",
		jga = "jag", itne = "inte", ohc = "och", kansek = "kanske", mycke = "mycket", tillsammas = "tillsammans",
		verkligne = "verkligen", fortfrande = "fortfarande", ["behöer"] = "behöver" }, "sv")
	eq(fix("i", "sv"), nil, "Swedish i stays small")
end)

test("in an English line the Swedish fixes stay off", function()
	fixes({ ["for"] = nil, pa = nil, jga = nil, teh = "the", i = "I" }, "en")
end)

test("compounds and English game words with Swedish endings are left alone", function()
	fixes({ ["spelkväll"] = nil, raidgrupp = nil, questen = nil, bossarna = nil, raiden = nil }, "sv")
	local _, _, why = ns.Autocorrect_Word("questen", ctx({ lang = "sv" }))
	eq(why, "the English word quest with a Swedish ending")
end)

test("a line that isn't known yet takes only a clear fix in either language", function()
	eq(fix("jga", nil), nil, "the Swedish typo table waits for a Swedish line")
	eq(fix("tillsammas", nil), "tillsammans", "only Swedish has a near word")
	eq(fix("becuase", nil), "because", "only English has a near word")
end)

test("the line decides: Swedish after Swedish words, English after English ones", function()
	eq(typed("Jag tror det ar "), "Jag tror det är ")
	eq(typed("I think it ar "), "I think it ar ")
	eq(typed("i think i ", {}), "i think I ")
	eq(typed("ja ja "), "ja ja ", "a Swedish double that's fine")
	eq(typed("Det är kul "), "Det är kul ")
end)

test("a sentence starting with å, ä or ö gets its capital", function()
	eq(typed("Kul. är "), "Kul. Är ")
end)

test("conversations: party, guild, whispers by name, channels by number", function()
	local key = ns.Autocorrect_ConversationKey
	eq(key("PARTY"), "PARTY")
	eq(key("PARTY_LEADER"), "PARTY")
	eq(key("RAID_WARNING"), "RAID")
	eq(key("WHISPER", "Mira-Realm5PvE"), "WHISPER:mira")
	eq(key("WHISPER_INFORM", "Mira"), "WHISPER:mira", "your whisper to her is the same conversation")
	eq(key("WHISPER", nil), nil, "a whisper whose target can't be read")
	eq(key("CHANNEL", 2), "CHANNEL:2")
	eq(key(nil), nil)
end)

test("a conversation's language follows its last messages, the newest a little more", function()
	local memory = {}
	eq(ns.Autocorrect_Conversation(memory, "GUILD"), nil)
	ns.Autocorrect_NoteConversation(memory, "GUILD", "sv")
	ns.Autocorrect_NoteConversation(memory, "GUILD", "sv")
	ns.Autocorrect_NoteConversation(memory, "GUILD", nil) -- a message that said nothing
	eq(ns.Autocorrect_Conversation(memory, "GUILD"), "sv")
	ns.Autocorrect_NoteConversation(memory, "GUILD", "en")
	ns.Autocorrect_NoteConversation(memory, "GUILD", "en")
	eq(ns.Autocorrect_Conversation(memory, "GUILD"), "en", "two each: the newest decides")
	for _ = 1, 6 do
		ns.Autocorrect_NoteConversation(memory, "GUILD", "sv")
	end
	eq(#memory.GUILD, 6, "only the last few are kept")
	eq(ns.Autocorrect_Conversation(memory, "PARTY"), nil, "each conversation its own")
end)

test("a message's language, links and colors left out", function()
	local function lang(text)
		return ns.Autocorrect_MessageLanguage(text, dict.level, sv.level, sv.letters)
	end
	eq(lang("ska vi köra en dunge?"), "sv")
	eq(lang("anyone want to run a dungeon"), "en")
	eq(lang("|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r"), nil)
end)

test("the conversation decides where the line's own words don't", function()
	local function lang(prior, ...)
		return ns.Autocorrect_Language({ ... }, dict.level, sv.level, sv.letters, prior)
	end
	eq(lang("sv"), "sv", "nothing typed yet: the conversation's")
	eq(lang("sv", "what", "are", "you"), "en", "the line's own words win")
	eq(typed("jga ", { conversation = "sv" }), "Jag ", "a first word in a Swedish conversation")
	eq(typed("jga ", { conversation = "en" }), "Jga ", "in an English one only the sentence's capital")
	eq(typed("ok pa ", { conversation = "sv" }), "ok på ")
end)

test("the Swedish setting off: everything as before", function()
	local off = { dict = dict, kinds = ALL, own = {}, keep = {}, refused = {}, names = {}, places = places,
		places2 = places2 }
	eq((ns.Autocorrect_Word("teh", off)), "the")
	eq((ns.Autocorrect_Word("är", off)), nil, "å, ä, ö words are left alone")
	eq(ns.Autocorrect_Finish("i think i ", 10, off), "i think I ")
end)

H.done()
