local addonName, ns = ...

-- Bags: the search language of the search box and of category rules: pure logic (no WoW API calls; unit-tested in
-- tests/test_bagssearch.lua). Tomte's own syntax:
--   words            part of the item's name, type, subtype or tooltip text (quotes keep spaces: "fresh bread")
--   is:<word>        a property (the list in KEYWORDS below)
--   ilvl>=600        item level, count, price (gold) or q (quality number) with = > < >= <=
--   exp:<short>      the expansion an item is from (EXPANSIONS below)
--   and, or, not     a space is "and"; "|" is "or"; a leading "-" is "not"; parentheses group
-- It reads these item record fields (filled by Read.lua): name, typeName, subTypeName, text (the tooltip's lines in
-- lower case, read only when a search has words: Compile says so), count, quality, ilvl,
-- classID, subclassID, bind ("soulbound" | "warbound" | "boe" | nil), expansion, price (copper), upgrade
-- ("upgrade" | "maybe" | "alt" | nil), look ("you" | "other" | nil), junk, new, set, quest, toy, mount, pet, decor,
-- hearth, keystone.

-- Item classes and subclasses (Enum.ItemClass and its subclass enums, warcraft.wiki.gg/wiki/ItemType).
local CONSUMABLE, CONTAINER, WEAPON, GEM, ARMOR, REAGENT = 0, 1, 2, 3, 4, 5
local TRADEGOODS, ENHANCEMENT, RECIPE, QUEST, KEY, MISC = 7, 8, 9, 12, 13, 15
local BATTLEPET, PROFESSION = 17, 19
local POTION, FOOD = 1, 5 -- consumable subclasses
local KEYSTONE = 1 -- reagent subclass
local COMPANION, MOUNT = 2, 5 -- miscellaneous subclasses
local COPPER_PER_GOLD = 10000

local function Class(classID, subclassID)
	return function(item)
		return item.classID == classID and (subclassID == nil or item.subclassID == subclassID)
	end
end

local function Field(key, value)
	return function(item)
		return item[key] == value
	end
end

local function Quality(q)
	return function(item)
		return item.quality == q
	end
end

-- is:<word>, in the order the "?" help lists them.
local KEYWORDS = {
	{ "gear", "weapons and armor", function(item)
		return item.classID == WEAPON or item.classID == ARMOR
	end },
	{ "weapon", "weapons", Class(WEAPON) },
	{ "armor", "armor, rings, necks and trinkets", Class(ARMOR) },
	{ "upgrade", "an upgrade for you (Gear Check)", Field("upgrade", "upgrade") },
	{ "maybe", "maybe an upgrade (Gear Check)", Field("upgrade", "maybe") },
	{ "altupgrade", "an upgrade for another character (Gear Check)", Field("upgrade", "alt") },
	{ "transmog", "an appearance you haven't collected", function(item)
		return item.look ~= nil
	end },
	{ "mytransmog", "an appearance this character can collect", Field("look", "you") },
	{ "set", "in an equipment set", function(item)
		return item.set ~= nil
	end },
	{ "consumable", "consumables", Class(CONSUMABLE) },
	{ "potion", "potions", Class(CONSUMABLE, POTION) },
	{ "food", "food and drink", Class(CONSUMABLE, FOOD) },
	{ "hearth", "hearthstones", Field("hearth", true) },
	{ "keystone", "Mythic+ keystones", function(item)
		return item.keystone == true or (item.classID == REAGENT and item.subclassID == KEYSTONE)
	end },
	{ "reagent", "crafting reagents", function(item)
		return item.classID == REAGENT and item.subclassID ~= KEYSTONE and not item.keystone
	end },
	{ "tradegoods", "trade goods (cloth, herbs, ore...)", Class(TRADEGOODS) },
	{ "profession", "profession tools and gear", Class(PROFESSION) },
	{ "recipe", "recipes", Class(RECIPE) },
	{ "quest", "quest items", function(item)
		return item.quest == true or item.classID == QUEST
	end },
	{ "gem", "gems", Class(GEM) },
	{ "enhancement", "item enhancements", Class(ENHANCEMENT) },
	{ "bag", "bags", Class(CONTAINER) },
	{ "key", "keys", Class(KEY) },
	{ "toy", "toys", Field("toy", true) },
	{ "mount", "mounts", function(item)
		return item.mount == true or (item.classID == MISC and item.subclassID == MOUNT)
	end },
	{ "pet", "pets", function(item)
		return item.pet == true or item.classID == BATTLEPET or (item.classID == MISC and item.subclassID == COMPANION)
	end },
	{ "battlepet", "battle pet items", Class(BATTLEPET) },
	{ "decor", "housing decor", Field("decor", true) },
	{ "misc", "miscellaneous", Class(MISC) },
	{ "junk", "junk (grey items)", Field("junk", true) },
	{ "new", "new since you last looked", Field("new", true) },
	{ "soulbound", "soulbound", Field("bind", "soulbound") },
	{ "warbound", "warbound", Field("bind", "warbound") },
	{ "boe", "bind on equip, not bound yet", Field("bind", "boe") },
	{ "poor", "poor quality", Quality(0) },
	{ "common", "common quality", Quality(1) },
	{ "uncommon", "uncommon quality", Quality(2) },
	{ "rare", "rare quality", Quality(3) },
	{ "epic", "epic quality", Quality(4) },
	{ "legendary", "legendary quality", Quality(5) },
	{ "artifact", "artifact quality", Quality(6) },
	{ "heirloom", "heirlooms", Quality(7) },
}

local FLAGS = {}
for _, k in ipairs(KEYWORDS) do
	FLAGS[k[1]] = k[3]
end

-- exp:<short> to the expansion ID (LE_EXPANSION_*).
local EXPANSIONS = {
	classic = 0, tbc = 1, wrath = 2, cata = 3, mop = 4, wod = 5, legion = 6, bfa = 7, sl = 8, df = 9, tww = 10,
	midnight = 11,
}

-- Numbers a comparison can read.
local FIELDS = {
	ilvl = function(item)
		return item.ilvl
	end,
	count = function(item)
		return item.count
	end,
	price = function(item)
		return item.price and item.price / COPPER_PER_GOLD
	end,
	q = function(item)
		return item.quality
	end,
}

local COMPARE = {
	["="] = function(a, b)
		return a == b
	end,
	[">"] = function(a, b)
		return a > b
	end,
	["<"] = function(a, b)
		return a < b
	end,
	[">="] = function(a, b)
		return a >= b
	end,
	["<="] = function(a, b)
		return a <= b
	end,
}

-- Tokens --------------------------------------------------------------------------------------------------------------

-- { kind = "(" | ")" | "or" | "and" | "not" | "word", text, quoted }
local function Tokenize(text)
	local tokens = {}
	local i, n = 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif c == "(" or c == ")" then
			tokens[#tokens + 1] = { kind = c }
			i = i + 1
		elseif c == "|" then
			tokens[#tokens + 1] = { kind = "or" }
			i = i + 1
		elseif c == "-" and i < n and not text:sub(i + 1, i + 1):match("[%s%)]") then
			tokens[#tokens + 1] = { kind = "not" }
			i = i + 1
		elseif c == "\"" then
			local close = text:find("\"", i + 1, true)
			local phrase = text:sub(i + 1, (close or n + 1) - 1)
			tokens[#tokens + 1] = { kind = "word", text = phrase:lower(), quoted = true }
			i = (close or n) + 1
		else
			local word = text:match("^[^%s%(%)|\"]+", i)
			local lower = word:lower()
			if lower == "and" or lower == "or" or lower == "not" then
				tokens[#tokens + 1] = { kind = lower }
			else
				tokens[#tokens + 1] = { kind = "word", text = lower }
			end
			i = i + #word
		end
	end
	return tokens
end

-- Terms ---------------------------------------------------------------------------------------------------------------

local function Contains(haystack, needle)
	return haystack ~= nil and haystack:lower():find(needle, 1, true) ~= nil
end

-- A word or phrase: in the name, type, subtype or the tooltip text (already lower case).
local function Words(text)
	return function(item)
		return Contains(item.name, text) or Contains(item.typeName, text) or Contains(item.subTypeName, text)
			or (item.text ~= nil and item.text:find(text, 1, true) ~= nil)
	end
end

-- A word token to a matcher, or nil and the reason.
local function Term(token)
	local text = token.text
	if token.quoted then
		return Words(text), true
	end
	local prefix, rest = text:match("^(%a+):(.*)$")
	if prefix == "is" then
		if rest == "" then
			return nil, "is: needs a word after it, like is:upgrade"
		end
		local flag = FLAGS[rest]
		if not flag then
			return nil, ("is:%s isn't a keyword (click ? for the list)"):format(rest)
		end
		return function(item)
			return flag(item) == true
		end
	elseif prefix == "exp" then
		local id = EXPANSIONS[rest]
		if not id then
			return nil, ("exp:%s isn't an expansion (classic, tbc, ... tww, midnight)"):format(rest)
		end
		return function(item)
			return item.expansion == id
		end
	end
	local name, op, number = text:match("^(%a+)([<>=]=?)(.*)$")
	if name and FIELDS[name] then
		local value = tonumber(number)
		if not value then
			return nil, ("%s%s needs a number after it"):format(name, op)
		end
		local read, compare = FIELDS[name], COMPARE[op]
		if not compare then
			return nil, ("%s isn't a comparison"):format(op)
		end
		return function(item)
			local v = read(item)
			return v ~= nil and compare(v, value)
		end
	end
	return Words(text), true
end

-- Parser --------------------------------------------------------------------------------------------------------------

-- Recursive descent over the tokens: or < and < not < ( ) and terms. Errors are raised as { message } tables and
-- caught in Compile. Returns the matcher and whether it has words (which read the tooltip text).
local function Parse(tokens)
	local pos = 1
	local usesText = false

	local function Fail(message)
		error({ message = message }, 0)
	end

	local function Peek()
		return tokens[pos]
	end

	local Or

	local function Unary()
		local token = Peek()
		if not token then
			Fail("the search ends too early")
		end
		if token.kind == "not" then
			pos = pos + 1
			local inner = Unary()
			return function(item)
				return not inner(item)
			end
		elseif token.kind == "(" then
			pos = pos + 1
			local inner = Or()
			if not Peek() or Peek().kind ~= ")" then
				Fail("a ( isn't closed")
			end
			pos = pos + 1
			return inner
		elseif token.kind == "word" then
			pos = pos + 1
			local match, words = Term(token)
			if not match then
				Fail(words)
			end
			usesText = usesText or words == true
			return match
		end
		Fail(("%s can't go there"):format(token.kind))
	end

	local function And()
		local left = Unary()
		while true do
			local token = Peek()
			if not token or token.kind == "or" or token.kind == ")" then
				return left
			end
			if token.kind == "and" then
				pos = pos + 1
			end
			local a, b = left, Unary()
			left = function(item)
				return a(item) and b(item)
			end
		end
	end

	Or = function()
		local left = And()
		while Peek() and Peek().kind == "or" do
			pos = pos + 1
			local a, b = left, And()
			left = function(item)
				return a(item) or b(item)
			end
		end
		return left
	end

	local match = Or()
	if Peek() then
		Fail(("%s can't go there"):format(Peek().kind))
	end
	return { match = match, usesText = usesText }
end

-- A matcher for text (match(item) -> bool), nil and whether it has words (those also read item.text, the tooltip);
-- or nil and a short reason. nil and nil for empty text.
function ns.BagsSearch_Compile(text)
	if not text or not text:find("%S") then
		return nil, nil
	end
	local ok, result = pcall(Parse, Tokenize(text))
	if ok then
		return result.match, nil, result.usesText
	end
	if type(result) == "table" then
		return nil, result.message
	end
	error(result, 0) -- a bug in the parser, not a bad search
end

-- The is: keywords for the "?" list: { { word, help } } in display order.
function ns.BagsSearch_Keywords()
	local list = {}
	for i, k in ipairs(KEYWORDS) do
		list[i] = { k[1], k[2] }
	end
	return list
end
