local addonName, ns = ...

-- Trade Filter, recipe requests: pure logic (no WoW API calls; unit-tested in tests/test_chat_recipes.lua).
-- A message that names a recipe ("LF enchanter, Enchant Boots - Minor Speed", or its link) shows only when you know
-- it. The recipes are read in Filter.lua (Forever: RecipesForever.lua's spell IDs; retail: what Alts read).

local MIN_WORDS = 2 -- a name must have this many words to count: one-word names ("Disenchant") are everyday words

local function WordCount(text)
	local n = 0
	for _ in text:gmatch("%S+") do
		n = n + 1
	end
	return n
end

-- A letter or digit (ASCII), or any byte of a multi-byte UTF-8 character: part of a word (as in Social/Data.lua).
local function WordByte(b)
	return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function FindWhole(lower, phrase)
	local start = 1
	while true do
		local s, e = lower:find(phrase, start, true)
		if not s then
			return false
		end
		if not WordByte(lower:byte(s - 1)) and not WordByte(lower:byte(e + 1)) then
			return true
		end
		start = s + 1
	end
end

-- The index the verdict reads. recipes: { { id = spell ID, name = localized name or nil, item = item it makes or
-- nil/0, base = profession skill line, known = bool } }. Only professions with at least one known recipe count: an
-- unread profession (or one the game won't answer for) leaves its requests to the keywords, as before.
-- Returns { phrases = { lower-case names, longest first }, byPhrase, bySpell, byItem, readable = { [base] = true } }.
function ns.Chat_RecipeIndex(recipes)
	local index = { phrases = {}, byPhrase = {}, bySpell = {}, byItem = {}, readable = {}, count = 0 }
	for _, r in ipairs(recipes or {}) do
		if r.known then
			index.readable[r.base] = true
		end
	end
	local function Add(map, key, r)
		local list = map[key]
		if not list then
			list = {}
			map[key] = list
		end
		list[#list + 1] = r
	end
	local function AddPhrase(phrase, r)
		if WordCount(phrase) >= MIN_WORDS then
			if not index.byPhrase[phrase] then
				index.phrases[#index.phrases + 1] = phrase
			end
			Add(index.byPhrase, phrase, r)
		end
	end
	for _, r in ipairs(recipes or {}) do
		if index.readable[r.base] then
			index.count = index.count + 1
			Add(index.bySpell, r.id, r)
			if r.item and r.item > 0 then
				Add(index.byItem, r.item, r)
			end
			if type(r.name) == "string" and r.name ~= "" then
				local name = ns.Social_Lower(r.name)
				AddPhrase(name, r)
				-- "Enchant Boots - Minor Speed" is also asked for as "Minor Speed".
				local suffix = name:match("^.- %- (.+)$")
				if suffix then
					AddPhrase(suffix, r)
				end
			end
		end
	end
	table.sort(index.phrases, function(a, b)
		if #a ~= #b then
			return #a > #b
		end
		return a < b
	end)
	return index
end

-- Whether the message names a recipe of a profession you have: "known" (one you know), "unknown" (only ones you
-- don't), or nil (none). Also returns what named it (a phrase, or "link"). Any known match wins: "Minor Stamina" is
-- both a bracer and a boots enchant.
function ns.Chat_RecipeVerdict(text, index)
	if type(text) ~= "string" or not index or index.count == 0 then
		return nil
	end
	local verdict, what
	local function Judge(list, how)
		for _, r in ipairs(list or {}) do
			if r.known then
				verdict, what = "known", how
				return true
			end
			if not verdict then
				verdict, what = "unknown", how
			end
		end
	end
	for kind, id in text:gmatch("|H(%a+):(%d+)") do
		id = tonumber(id)
		local list = (kind == "enchant" or kind == "spell") and index.bySpell[id] or kind == "item" and index.byItem[id]
		if Judge(list, "link") then
			return verdict, what
		end
	end
	local lower = ns.Social_Lower(ns.Social_PlainText(text))
	for _, phrase in ipairs(index.phrases) do
		if FindWhole(lower, phrase) and Judge(index.byPhrase[phrase], phrase) then
			return verdict, what
		end
	end
	return verdict, what
end

-- Show a filtered channel message? words: { prof = your professions' words, own = your own keywords }; index: from
-- Chat_RecipeIndex, or nil to leave recipes out. Your own keywords always count; a profession word counts unless
-- the message asks for a recipe you don't know; a recipe you know counts without one. Ignore words hide anyway.
-- Returns show, why (for /tomte tradefilter why), and the known recipe's name as written when the text named it (to
-- highlight).
function ns.Chat_DecideRequest(text, words, ignoreWords, index)
	if ignoreWords and ns.Social_FindMention(text, ignoreWords) then
		return false, "has an ignore word"
	end
	if ns.Social_FindMention(text, words.own or {}) then
		return true, "has one of your keywords"
	end
	local verdict, what = ns.Chat_RecipeVerdict(text, index)
	if verdict == "known" then
		return true, "names a recipe you know (" .. what .. ")", what ~= "link" and what or nil
	end
	local prof = ns.Social_FindMention(text, words.prof or {})
	if not prof then
		return false, "no keyword"
	end
	if verdict == "unknown" then
		return false, "names a recipe you don't know (" .. what .. ")"
	end
	return true, "names your profession (" .. prof .. ")"
end
