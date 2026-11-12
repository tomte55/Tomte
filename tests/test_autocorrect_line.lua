-- Run from the AddOns folder: lua Tomte/tests/test_autocorrect_line.lua
local ns = {}
for _, file in ipairs({ "Words", "Data", "Rules", "Line" }) do
	assert(loadfile("Tomte/Modules/Autocorrect/" .. file .. ".lua"))("Tomte", ns)
end

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local dict = ns.Autocorrect_NewDict(ns.AUTOCORRECT_WORDS, ns.AUTOCORRECT_UPPER, ns.AUTOCORRECT_CONTRACTIONS)
local places, places2 = ns.Autocorrect_Places(ns.AUTOCORRECT_PLACES, dict)
local ALL = { spelling = true, apostrophes = true, capitals = true, names = true, pairs = true, tidying = true }

local function ctx(extra)
	local c = { dict = dict, kinds = ALL, own = {}, keep = {}, refused = {}, names = {}, places = places,
		places2 = places2 }
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	return c
end

-- The line after typing its last character (cursor at the end).
local function typed(text, extra)
	local out, cursor, change = ns.Autocorrect_Finish(text, #text, ctx(extra))
	return out or text, cursor, change
end

local function lines(cases, extra)
	for input, want in pairs(cases) do
		eq((typed(input, extra)), want, input)
	end
end

test("a word is fixed when it's finished", function()
	local out, cursor, change = typed("pass me teh ")
	eq(out, "pass me the ")
	eq(cursor, #"pass me the ")
	eq(change.typed, "teh")
	eq(change.fix, "the")
	eq(change.kind, "spelling")
	lines({ ["we are thinkk,"] = "we are think,", ["is it dont?"] = "is it don't?" })
end)

test("unfinished words are left", function()
	eq(ns.Autocorrect_Finish("pass me teh", 11, ctx()), nil)
end)

test("capitals at a sentence start", function()
	lines({ ["hello there. how "] = "hello there. How ", ["ok! where "] = "ok! Where ", ["teh "] = "The ",
		["i think "] = "i think " })
	eq((typed("hello ")), "Hello ", "first word of the line")
	eq((typed("i ")), "I ", "a lone i")
	eq((typed("lol ")), "lol ", "shorthand stays")
	eq((typed("hello ", { kinds = { spelling = true } })), "hello ", "capitals off")
end)

test("word pairs", function()
	lines({ ["we could of "] = "we could have ", ["ok your late "] = "ok you're late ",
		["ill meet "] = "I'll meet ", ["so its been "] = "so it's been ", ["Lets go "] = "Let's go " })
	lines({ ["we could of "] = "we could of " }, { kinds = { spelling = true } })
	lines({ ["on your next "] = "on your next ", ["your best "] = "your best ", ["your home "] = "your home ",
		["your back "] = "your back ", ["it lets all "] = "it lets all ", ["an ill tank "] = "an ill tank ",
		["your going "] = "you're going " })
end)

test("two-word place names", function()
	eq((typed("near old town,")), "near Old Town,")
	eq((typed("in thunder bluff ")), "in Thunder Bluff ")
	eq((typed("near old town,", { kinds = { pairs = true } })), "near old town,", "names off")
end)

test("doubled words", function()
	lines({ ["to the the "] = "to the ", ["bye bye "] = "bye bye ", ["ok so so "] = "ok so so ",
		["The the "] = "The ", ["yeah yeah "] = "yeah yeah ", ["oh oh "] = "oh oh " })
	eq((typed("ask Will will ", { names = { will = true } })), "ask Will will ", "a name and its word")
	eq((typed("the the ", { keep = { the = true } })), "the the ", "a kept word")
end)

test("commands are left alone", function()
	lines({ ["/who teh "] = "/who teh ", ["  /dance teh "] = "  /dance teh " })
	eq(ns.Autocorrect_LineSkipped("/w Kesha teh"), true)
	eq(ns.Autocorrect_LineSkipped("hi /wave"), false)
end)

test("link stays intact", function()
	local link = "|cff9d9d9d|Hitem:2589::::::::80:::::|h[Linen Cloth]|h|r"
	eq((typed(link .. " pls teh ")), link .. " pls the ")
	eq((typed("sell " .. link .. " ")), "sell " .. link .. " ")
	eq((typed("|Hitem:2589|h[Linen teh ")), "|Hitem:2589|h[Linen teh ", "inside an open link")
end)

test("text after the cursor is kept", function()
	local text = "pass me teh  the salt"
	local out, cursor = ns.Autocorrect_Finish(text, 12, ctx())
	eq(out, "pass me the  the salt")
	eq(cursor, 12)
	eq(ns.Autocorrect_Finish("pass me tehsalt", 8, ctx()), nil, "space typed inside a word")
end)

test("send pass fixes the last word", function()
	local out, cursor = ns.Autocorrect_Finish("see you tommorow", 16, ctx(), true)
	eq(out, "see you tomorrow")
	eq(cursor, 16)
	eq(ns.Autocorrect_Finish("see you tomorrow", 16, ctx(), true), nil)
end)

test("undo only right after", function()
	local out, cursor, change = typed("pass me teh ")
	local back, at = ns.Autocorrect_Undo(out, cursor, change)
	eq(back, "pass me teh ")
	eq(at, 12)
	eq(ns.Autocorrect_Undo(out .. "x", cursor + 1, change), nil, "typed more")
	eq(ns.Autocorrect_Undo(out, cursor - 2, change), nil, "cursor moved")
end)

test("pair undo", function()
	local out, cursor, change = typed("near old town,")
	eq(out, "near Old Town,")
	eq((ns.Autocorrect_Undo(out, cursor, change)), "near old town,")
	eq(change.typed, "old town")
	eq(change.fix, "Old Town")
end)

test("what an undo remembers", function()
	local _, _, change = typed("pass me teh ")
	eq(change.remember, "teh")
	eq(change.rememberFix, "the")
	_, _, change = typed("hello ")
	eq(change.remember, nil, "capitals aren't remembered")
	_, _, change = typed("to the the ")
	eq(change.remember, "the the", "a doubled word is remembered as the pair")
	eq(change.rememberFix, "the")
	eq((typed("to the the ", { refused = { ["the the"] = { the = true } } })), "to the the ")
	_, _, change = typed("go tothe ")
	eq(change.remember, "tothe", "a split is remembered")
	eq((typed("go tothe ", { refused = { tothe = { ["to the"] = true } } })), "go tothe ")
	_, _, change = typed("we could of ")
	eq(change.remember, "could of")
	eq(change.rememberFix, "could have")
	eq((typed("we could of ", { refused = { ["could of"] = { ["could have"] = true } } })), "we could of ")
end)

H.done()
