-- Run from the AddOns folder: lua Tomte/tests/test_autocorrect.lua
local ns = {}
assert(loadfile("Tomte/Modules/Autocorrect/Words.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Autocorrect/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Autocorrect/Rules.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local dict = ns.Autocorrect_NewDict(ns.AUTOCORRECT_WORDS, ns.AUTOCORRECT_UPPER, ns.AUTOCORRECT_CONTRACTIONS)
local ALL = { spelling = true, apostrophes = true, capitals = true, names = true, pairs = true, tidying = true }

local function ctx(extra)
	local c = { dict = dict, kinds = ALL, own = {}, keep = {}, refused = {}, names = {}, places = {} }
	for k, v in pairs(ns.Autocorrect_Places(ns.AUTOCORRECT_PLACES, dict)) do
		c.places[k] = v
	end
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	return c
end

local function fix(word, extra)
	return (ns.Autocorrect_Word(word, ctx(extra)))
end

local function fixes(cases, extra)
	for typed, want in pairs(cases) do
		eq(fix(typed, extra), want, typed)
	end
end

test("known typos", function()
	fixes({ teh = "the", recieve = "receive", tommorow = "tomorrow", wnat = "want", Teh = "The",
		definately = "definitely", seperate = "separate", alot = "a lot" })
end)

test("guesses with one clear nearest word", function()
	fixes({ thinkk = "think", winnning = "winning", stareing = "staring", kontest = "contest",
		fountian = "fountain", becuase = "because", freind = "friend", wierd = "weird", tiem = "time",
		somthing = "something", realy = "really", probly = "probably" })
end)

test("apostrophes", function()
	fixes({ dont = "don't", im = "I'm", hes = "he's", Dont = "Don't", cant = "can't", wont = "won't",
		youre = "you're", didnt = "didn't", ive = "I've", thats = "that's" })
	for _, w in ipairs({ "ill", "its", "were", "well", "hell", "shell", "lets", "id" }) do
		eq(fix(w), nil, w)
	end
end)

test("capitals and names", function()
	fixes({ i = "I", stormwind = "Stormwind", orgrimmar = "Orgrimmar", english = "English", monday = "Monday" })
	for _, w in ipairs({ "will", "brown", "may", "bill" }) do
		eq(fix(w), nil, w)
	end
end)

test("run-together words", function()
	fixes({ tothe = "to the", ofthe = "of the", inthe = "in the" })
end)

test("left alone", function()
	for _, w in ipairs({ "lol", "brb", "gg", "sooo", "yesss", "nooo", "nothin'", "goin", "LFG", "AFK", "WTS", "2h",
		"ilvl540", "www.wowhead.com", "http://x.y", "caf\195\169", "Aldric", "the", "receive", "u", "ur", "ty",
		"pls", "Aldric's", "teh's" }) do
		eq(fix(w), nil, w)
	end
end)

test("game words and compounds are left alone", function()
	for _, w in ipairs({ "worgen", "draenei", "voljin", "respec", "addon", "melee", "procs", "anima", "mana", "brez",
		"minipet", "bagspace", "bankalt", "oneshot", "gief", "heya", "mplus", "wowhead", "whisp", "guildy", "brann",
		"pugger", "pallys", "blizz", "specc", "achi", "achis", "achiev", "sellin", "buyin", "lolol", "heyy",
		"sadge", "copium", "hopium", "gamba", "poggies", "archon", "catalysted", "tyr" }) do
		eq(fix(w), nil, w)
	end
end)

test("splits only around everyday words, slips beat splits", function()
	fixes({ wantto = "want to", infront = "in front", doyou = "do you", sumon = "summon", healign = "healing",
		dungon = "dungeon", collecton = "collection" })
	eq(fix("wether"), nil, "wether")
	eq(fix("ther"), nil, "ther: the, there or their")
end)

test("player's own words win", function()
	eq(fix("teh", { keep = { teh = true } }), nil, "kept")
	eq(fix("teh", { refused = { teh = { the = true } } }), nil, "refused")
	eq(fix("wtv", { own = { wtv = "whatever" } }), "whatever", "own")
	eq(fix("teh", { own = { teh = "tea" } }), "tea", "own beats the list")
end)

test("a refused pair still allows another fix", function()
	eq(fix("dont", { refused = { dont = { ["don't"] = true } } }), nil)
end)

test("kinds can be turned off", function()
	eq(fix("teh", { kinds = { apostrophes = true } }), nil, "spelling off")
	eq(fix("dont", { kinds = { spelling = true } }), nil, "apostrophes off")
	eq(fix("stormwind", { kinds = { spelling = true } }), nil, "names off")
	eq(fix("i", { kinds = { spelling = true } }), nil, "capitals off")
	eq(fix("tothe", { kinds = { spelling = true } }), nil, "tidying off")
end)

test("names are never guessed", function()
	eq(fix("kesha", { names = { kesha = true } }), nil, "known person")
	eq(fix("Kesha"), nil, "capitalised mid-sentence")
	eq(fix("Kesha", { sentenceStart = true }), nil, "capitalised at a sentence start, unknown: still a name")
	eq(fix("Teh", { sentenceStart = true }), "The", "capitalised typo at a sentence start")
end)

test("garbage is left and fast", function()
	eq(fix("asdfghjklqwerty"), nil)
	eq(fix(("abcdefghij"):rep(25)), nil, "a very long word isn't guessed")
	eq(fix("xqzvbn"), nil)
	local words = { "teh", "thinkk", "winnning", "asdfghjklqwerty", "the", "kontest", "lol", "stareing",
		"somthing", "zzzzzzzzzzzz" }
	local c = ctx()
	local start = os.clock()
	for i = 1, 200 do
		ns.Autocorrect_Word(words[i % #words + 1], c)
	end
	local each = (os.clock() - start) / 200
	assert(each < 0.005, ("%.2f ms per word"):format(each * 1000))
end)

test("why explains", function()
	local _, kind, reason = ns.Autocorrect_Word("thinkk", ctx())
	eq(kind, "spelling")
	assert(type(reason) == "string" and reason ~= "", "reason")
	local none, _, why = ns.Autocorrect_Word("lol", ctx())
	eq(none, nil)
	assert(type(why) == "string" and why ~= "", "reason for leaving it")
end)

H.done()
