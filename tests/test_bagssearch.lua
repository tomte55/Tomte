-- Run from the AddOns folder: lua Tomte/tests/test_bagssearch.lua
local ns = {}
assert(loadfile("Tomte/Modules/Bags/Search.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local Compile = ns.BagsSearch_Compile

local function matches(text, item)
	local match, err = Compile(text)
	assert(match, "didn't compile: " .. tostring(text) .. " (" .. tostring(err) .. ")")
	return match(item)
end

local function fails(text)
	local match, err = Compile(text)
	eq(match, nil, text .. " matcher")
	eq(type(err), "string", text .. " error")
end

test("empty text is no filter and no error", function()
	local m, err = Compile("")
	eq(m, nil)
	eq(err, nil)
	m, err = Compile("   ")
	eq(m, nil)
	eq(err, nil)
	eq(Compile(nil), nil)
end)

test("words match the name, any case", function()
	eq(matches("bread", { name = "Fresh Bread" }), true)
	eq(matches("BREAD", { name = "Fresh Bread" }), true)
	eq(matches("bread", { name = "Potion" }), false)
end)

test("words also match type and subtype", function()
	eq(matches("cloth", { name = "Weavercloth", typeName = "Tradeskill" }), true)
	eq(matches("tradeskill", { name = "Ore", typeName = "Tradeskill" }), true)
	eq(matches("plate", { name = "Helm", subTypeName = "Plate" }), true)
end)

test("words also match the tooltip text", function()
	local slate = { name = "Slab of Slate", text = "slab of slate\nsoulbound\nuse: study to increase your mining" }
	eq(matches("use", slate), true)
	eq(matches("\"use: study\"", slate), true)
	eq(matches("use", { name = "Ore" }), false)
end)

test("Compile says whether the search reads tooltip text", function()
	local _, _, usesText = Compile("is:potion")
	eq(usesText, false)
	_, _, usesText = Compile("is:potion or use")
	eq(usesText, true)
	_, _, usesText = Compile("\"fresh bread\"")
	eq(usesText, true)
	_, _, usesText = Compile("ilvl>600")
	eq(usesText, false)
end)

test("quoted text keeps its spaces", function()
	eq(matches("\"fresh bread\"", { name = "Fresh Bread" }), true)
	eq(matches("\"fresh bread\"", { name = "Bread, Fresh" }), false)
end)

test("is:upgrade, is:maybe and is:altupgrade read Gear Check's verdict", function()
	eq(matches("is:upgrade", { upgrade = "upgrade" }), true)
	eq(matches("is:upgrade", { upgrade = "maybe" }), false)
	eq(matches("is:upgrade", {}), false)
	eq(matches("is:maybe", { upgrade = "maybe" }), true)
	eq(matches("is:altupgrade", { upgrade = "alt" }), true)
end)

test("gear with an item level comparison", function()
	eq(matches("is:gear ilvl>=600", { classID = 4, ilvl = 610 }), true)
	eq(matches("is:gear ilvl>=600", { classID = 4, ilvl = 590 }), false)
	eq(matches("is:gear ilvl>=600", { classID = 0, ilvl = 610 }), false)
	eq(matches("is:gear and ilvl>=600", { classID = 2, ilvl = 600 }), true)
end)

test("or between consumable subclasses", function()
	eq(matches("is:potion or is:food", { classID = 0, subclassID = 1 }), true)
	eq(matches("is:potion or is:food", { classID = 0, subclassID = 5 }), true)
	eq(matches("is:potion | is:food", { classID = 0, subclassID = 0 }), false)
end)

test("not, minus and parentheses", function()
	eq(matches("-is:junk", { junk = true }), false)
	eq(matches("-is:junk", { junk = false }), true)
	eq(matches("not (is:rare or is:epic)", { quality = 3 }), false)
	eq(matches("not (is:rare or is:epic)", { quality = 4 }), false)
	eq(matches("not (is:rare or is:epic)", { quality = 2 }), true)
end)

test("and binds tighter than or", function()
	-- is:epic or (is:weapon and ilvl>600)
	eq(matches("is:epic or is:weapon ilvl>600", { quality = 4, classID = 0 }), true)
	eq(matches("is:epic or is:weapon ilvl>600", { quality = 3, classID = 2, ilvl = 590 }), false)
end)

test("price compares in gold", function()
	eq(matches("price>10", { price = 100001 }), true)
	eq(matches("price>10", { price = 100000 }), false)
	eq(matches("price>10", {}), false)
end)

test("count and quality numbers", function()
	eq(matches("count>=20", { count = 20 }), true)
	eq(matches("count<20", { count = 20 }), false)
	eq(matches("q=4", { quality = 4 }), true)
end)

test("exp: names an expansion", function()
	eq(matches("exp:tww", { expansion = 10 }), true)
	eq(matches("exp:midnight", { expansion = 10 }), false)
end)

test("keystones aren't reagents", function()
	eq(matches("is:keystone", { classID = 5, subclassID = 1 }), true)
	eq(matches("is:reagent", { classID = 5, subclassID = 1 }), false)
	eq(matches("is:reagent", { classID = 5, subclassID = 0 }), true)
end)

test("transmog: any uncollected look, or only this character's", function()
	eq(matches("is:transmog", { look = "other" }), true)
	eq(matches("is:mytransmog", { look = "other" }), false)
	eq(matches("is:mytransmog", { look = "you" }), true)
end)

test("bad searches return a reason, never an error", function()
	fails("is:")
	fails("is:nonsense")
	fails("(is:gear")
	fails("is:gear)")
	fails("is:gear or")
	fails("and")
	fails("ilvl>")
	fails("ilvl>abc")
	fails("exp:nowhere")
	fails("not")
end)

test("the keyword list has every is: word with help", function()
	local list = ns.BagsSearch_Keywords()
	assert(#list > 20, "keyword list too short")
	for _, k in ipairs(list) do
		eq(type(k[1]), "string")
		eq(type(k[2]), "string")
		assert(Compile("is:" .. k[1]), "is:" .. k[1] .. " doesn't compile")
	end
end)

H.done()
