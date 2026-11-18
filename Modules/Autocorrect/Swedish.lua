local addonName, ns = ...

-- Autocorrect, Swedish: pure logic (no WoW API calls; unit-tested in tests/test_autocorrect_swedish.lua). The Swedish
-- word list as lookup tables, which language a chat line is in, compound words, and a guess at the nearest Swedish
-- word. Swedish words carry å, ä, ö (and é), two bytes each in the chat box's UTF-8, so everything here works on
-- letters, not bytes; the English rules (Rules.lua) stay on bytes, as English is plain ASCII. The word list is the
-- generated WordsSwedish.lua; Rules.lua's Autocorrect_Word asks this file when the Swedish setting is on.

local GUESS_MIN = 4 -- letters; shorter typos only through the tables (AUTOCORRECT_SV_TYPOS)
local SHORT_MAX = 4 -- words this short are only guessed for a slip
local GUESS_MAX = 24 -- longer: keyboard mash or a compound past any list
local FAR_MIN = 6 -- words this long may be two edits from the right one
local GUESS_LEVEL = 50 -- guesses only become words of this band or more common
local FAR_LEVEL = 35 -- two-edit guesses only become common words
local DETECT_LEVEL = 50 -- only words at least this common say which language a line is in
-- Letters in each part of a compound word: three-letter parts made typos look like compounds (kansek: kan + sek).
local PART_MIN = 4
local COST_EDIT, COST_SLIP, COST_KEY = 1, 0.5, 0.75
local BAND_COST = 0.25
local BANDS = { [10] = 1, [20] = 1, [35] = 2, [40] = 3, [50] = 3, [55] = 4, [60] = 4 }
-- Capital and small å, ä, ö, é in UTF-8.
local LOWER = { ["\195\133"] = "\195\165", ["\195\132"] = "\195\164", ["\195\150"] = "\195\182",
	["\195\137"] = "\195\169" }
local UPPER = {}
for upper, lower in pairs(LOWER) do
	UPPER[lower] = upper
end
local ALPHABET = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s",
	"t", "u", "v", "w", "x", "y", "z", "\195\165", "\195\164", "\195\182" }
-- The Swedish keyboard's letter rows: å right of p, ö and ä right of l.
local KEYS = { { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "\195\165" },
	{ "a", "s", "d", "f", "g", "h", "j", "k", "l", "\195\182", "\195\164" },
	{ "z", "x", "c", "v", "b", "n", "m" } }
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
-- Words that say nothing about a line's language although a list counts them: "i" is Swedish for "in" and English
-- typed in lowercase.
local NEUTRAL = { i = true }

-- Letters ------------------------------------------------------------------------------------------------------------

local function Chars(s)
	local list = {}
	for c in s:gmatch(CHAR) do
		list[#list + 1] = c
	end
	return list
end

-- Lowercase, with Å, Ä, Ö and É too (string.lower only knows ASCII).
function ns.Autocorrect_Lower(s)
	return (s:lower():gsub("\195[\132\133\137\150]", LOWER))
end

-- Whether s starts with a capital letter, Å, Ä, Ö or É included.
function ns.Autocorrect_StartsUpper(s)
	return s:find("^%u") ~= nil or LOWER[s:sub(1, 2)] ~= nil
end

-- s with its first letter a capital (å -> Å).
function ns.Autocorrect_CapitalFirst(s)
	local up = UPPER[s:sub(1, 2)]
	if up then
		return up .. s:sub(3)
	end
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- Whether s has å, ä, ö or é in it (either case).
function ns.Autocorrect_HasSwedishLetters(s)
	return s:find("\195[\132\133\137\150\164\165\169\182]") ~= nil
end

-- Whether word is only letters (a-z, å, ä, ö, é, either case), with at most one apostrophe inside: a word the
-- Swedish rules may look at.
function ns.Autocorrect_SwedishLetters(word)
	local plain = word:gsub("\195[\132\133\137\150\164\165\169\182]", "a")
	return plain:find("^[A-Za-z]+'?[A-Za-z]*$") ~= nil and not plain:find("'$")
end

-- The word list -------------------------------------------------------------------------------------------------------

local function Lines(text, fn)
	for line in text:gmatch("[^\r\n]+") do
		fn(line)
	end
end

-- The lookup tables, built when the setting is on (tens of thousands of words: not at load). words: { [level] = text }
-- (AUTOCORRECT_SV_WORDS), letters: "ar>är ..." (AUTOCORRECT_SV_LETTERS).
function ns.Autocorrect_SwedishDict(words, letters)
	local dict = { level = {}, letters = {}, buckets = {} }
	for size, text in pairs(words) do
		Lines(text, function(word)
			if not dict.level[word] or dict.level[word] > size then
				dict.level[word] = size
			end
		end)
	end
	for plain, fix in letters:gmatch("(%S+)>(%S+)") do
		dict.letters[plain] = fix
	end
	return dict
end

-- Which language a line is in from its words so far (lowercase): "sv", "en" or nil when they don't tell. Each word
-- counts for the language whose list has it as the more common word (a word as common in both counts for neither);
-- å, ä, ö, and the Swedish words typed without them (pa, ar), count for Swedish. Chat shorthand (ok, lol) is both
-- languages'. en, sv: the two dicts' level tables. prior: the conversation's language (Autocorrect_Conversation), which
-- decides only when the words don't: before any word, or when they're even.
function ns.Autocorrect_Language(words, en, sv, letters, prior)
	local score = prior == "sv" and 0.5 or prior == "en" and -0.5 or 0 -- above 0: Swedish
	local shorthand = ns.AUTOCORRECT_SHORTHAND or {}
	for _, word in ipairs(words) do
		if not NEUTRAL[word] and not shorthand[word] then
			if ns.Autocorrect_HasSwedishLetters(word) or (letters and letters[word]) then
				score = score + 2
			else
				-- The exact level, not its band: "you" is common in Swedish subtitles too, but more so in English.
				local e, s = en[word], sv[word]
				e = e and e <= DETECT_LEVEL and e or nil
				s = s and s <= DETECT_LEVEL and s or nil
				if s and (not e or s < e) then
					score = score + 1
				elseif e and (not s or e < s) then
					score = score - 1
				end
			end
		end
	end
	if score > 0 then
		return "sv"
	elseif score < 0 then
		return "en"
	end
	return nil
end

-- Conversations ------------------------------------------------------------------------------------------------------

-- A whole chat message's language ("sv", "en" or nil): its words, links and color codes left out.
function ns.Autocorrect_MessageLanguage(text, en, sv, letters)
	text = text:gsub("|H.-|h.-|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	local words = {}
	for word in text:gmatch("[%a\128-\255][%a\128-\255']*") do
		words[#words + 1] = ns.Autocorrect_Lower(word)
	end
	return ns.Autocorrect_Language(words, en, sv, letters)
end

local CONVERSATION_KEEP = 6 -- messages remembered per conversation: the last few say what it's in now
-- Chat types that are one conversation with another (the raid's warnings are the raid's).
local SAME_AS = { PARTY_LEADER = "PARTY", RAID_LEADER = "RAID", RAID_WARNING = "RAID",
	INSTANCE_CHAT_LEADER = "INSTANCE_CHAT", WHISPER_INFORM = "WHISPER" }

-- Which conversation a message or the chat box belongs to: "PARTY", "GUILD", "WHISPER:mira", "CHANNEL:2" ..., nil when
-- it can't be told apart (a whisper whose target isn't readable). chatType: a CHAT_MSG_ suffix or the box's chatType;
-- target: the whisper partner's name (Name-Realm or Name) or the channel's number.
function ns.Autocorrect_ConversationKey(chatType, target)
	if type(chatType) ~= "string" then
		return nil
	end
	chatType = SAME_AS[chatType] or chatType
	if chatType == "WHISPER" then
		local name = type(target) == "string" and target:match("^[^%-]+")
		return name and name ~= "" and ("WHISPER:" .. ns.Autocorrect_Lower(name)) or nil
	elseif chatType == "CHANNEL" then
		return target and ("CHANNEL:" .. tostring(target)) or nil
	end
	return chatType
end

-- Remembers a message's language (Autocorrect_Language's verdict, nil for none) in its conversation.
-- memory: { [key] = { verdicts, newest last } }, kept by the caller.
function ns.Autocorrect_NoteConversation(memory, key, lang)
	if not key or not lang then
		return
	end
	local list = memory[key] or {}
	memory[key] = list
	list[#list + 1] = lang
	if #list > CONVERSATION_KEEP then
		table.remove(list, 1)
	end
end

-- A conversation's language from its last messages: "sv", "en", or nil when they're even or there are none. The
-- newest message counts a little more, so a conversation that just switched language follows it.
function ns.Autocorrect_Conversation(memory, key)
	local list = key and memory[key]
	if not list then
		return nil
	end
	local score = 0
	for i, lang in ipairs(list) do
		local weight = i == #list and 1.5 or 1
		score = score + (lang == "sv" and weight or -weight)
	end
	if score > 0 then
		return "sv"
	elseif score < 0 then
		return "en"
	end
	return nil
end

-- Whether a lowercase word is two words joined, the second Swedish and the first maybe with a linking s (spelkväll,
-- kärleksbrev): what Swedish does with words, not a typo. en: the English level table, for a first part chat borrows
-- from English (raidgrupp).
function ns.Autocorrect_SwedishCompound(word, sv, en)
	local chars = Chars(word)
	local level = sv.level
	local function Known(part)
		return level[part] or (en and en[part])
	end
	for i = PART_MIN, #chars - PART_MIN do
		local left = table.concat(chars, "", 1, i)
		local right = table.concat(chars, "", i + 1)
		if level[right] and (Known(left) or (chars[i] == "s" and i > PART_MIN and Known(left:sub(1, -2)))) then
			return true
		end
	end
	return false
end

-- Swedish endings chat puts on English game words: the quest, the bosses (questen, bossarna).
local ENDINGS = { "arna", "erna", "orna", "en", "et", "ar", "er", "or", "na", "n", "t" }
local STEM_MIN = 3 -- letters

-- The English word under a Swedish ending (questen -> quest, bossar -> boss), or nil. en: the English level table.
function ns.Autocorrect_SwedishEnding(word, en)
	for _, ending in ipairs(ENDINGS) do
		if #word - #ending >= STEM_MIN and word:sub(-#ending) == ending then
			local stem = word:sub(1, -#ending - 1)
			if en[stem] then
				return stem
			end
		end
	end
	return nil
end

-- Guessing -----------------------------------------------------------------------------------------------------------

local neighbours -- [letter] = { [letter] = true } for keys side by side
local function Neighbours()
	if not neighbours then
		neighbours = {}
		for _, row in ipairs(KEYS) do
			for i, c in ipairs(row) do
				neighbours[c] = neighbours[c] or {}
				if row[i - 1] then
					neighbours[c][row[i - 1]] = true
				end
				if row[i + 1] then
					neighbours[c][row[i + 1]] = true
				end
			end
		end
	end
	return neighbours
end

-- Every word one edit away, with what the edit costs: cb(candidate, cost). chars: the word's letters.
local function Edits(chars, cb)
	local n = #chars
	local near = Neighbours()
	local concat = table.concat
	for i = 1, n do
		local before, c, after = concat(chars, "", 1, i - 1), chars[i], concat(chars, "", i + 1)
		local doubled = c == chars[i - 1] or c == chars[i + 1]
		cb(before .. after, doubled and COST_SLIP or COST_EDIT) -- delete
		if i < n then
			cb(before .. chars[i + 1] .. c .. concat(chars, "", i + 2), COST_SLIP) -- swap
		end
		for _, r in ipairs(ALPHABET) do
			if r ~= c then
				cb(before .. r .. after, (near[c] and near[c][r]) and COST_KEY or COST_EDIT) -- replace
			end
		end
	end
	for i = 0, n do
		local before, after = concat(chars, "", 1, i), concat(chars, "", i + 1)
		for _, r in ipairs(ALPHABET) do
			local doubled = r == chars[i] or r == chars[i + 1]
			cb(before .. r .. after, doubled and COST_SLIP or COST_EDIT) -- insert
		end
	end
end

-- Optimal string alignment distance between two letter lists, or limit + 1 once it's over the limit.
local function Distance(a, b, limit)
	local la, lb = #a, #b
	if math.abs(la - lb) > limit then
		return limit + 1
	end
	local prev2, prev, cur = {}, {}, {}
	for j = 0, lb do
		prev[j] = j
	end
	for i = 1, la do
		cur[0] = i
		local best = i
		for j = 1, lb do
			local v = prev[j - 1] + (a[i] == b[j] and 0 or 1)
			if prev[j] + 1 < v then
				v = prev[j] + 1
			end
			if cur[j - 1] + 1 < v then
				v = cur[j - 1] + 1
			end
			if i > 1 and j > 1 and a[i] == b[j - 1] and a[i - 1] == b[j] and prev2[j - 2] + 1 < v then
				v = prev2[j - 2] + 1
			end
			cur[j] = v
			if v < best then
				best = v
			end
		end
		if best > limit then
			return limit + 1
		end
		prev2, prev, cur = prev, cur, prev2
	end
	return prev[lb]
end

local NONE = {}

-- Common words by first letter and length in letters ([letter .. length] = { letter lists }), for two-edit guesses.
local function Bucket(dict, key)
	local buckets = dict.buckets
	if not next(buckets) then
		for word, size in pairs(dict.level) do
			if size <= FAR_LEVEL then
				local chars = Chars(word)
				local k = chars[1] .. #chars
				local list = buckets[k]
				if not list then
					list = {}
					buckets[k] = list
				end
				list[#list + 1] = { word = word, chars = chars }
			end
		end
	end
	return buckets[key] or NONE
end

-- The nearest Swedish word to a lowercase word, what the edits cost and the score it won with, when one is clearly
-- the best; nil when none is or it's a toss-up. refused: fixes the player undid for this word. en: the English level
-- table (compounds may start with an English word).
function ns.Autocorrect_SwedishGuess(word, sv, refused, en)
	local chars = Chars(word)
	if #chars < GUESS_MIN or #chars > GUESS_MAX then
		return nil
	end
	local level = sv.level
	local found = {} -- [candidate] = cost
	Edits(chars, function(candidate, cost)
		local size = level[candidate]
		if size and size <= GUESS_LEVEL and (found[candidate] or 99) > cost and not (refused and refused[candidate]) then
			found[candidate] = cost
		end
	end)
	if not next(found) and #chars >= FAR_MIN and not ns.Autocorrect_SwedishCompound(word, sv, en) then
		for len = #chars - 2, #chars + 2 do
			for _, entry in ipairs(Bucket(sv, chars[1] .. len)) do
				if Distance(chars, entry.chars, 2) <= 2 and not (refused and refused[entry.word]) then
					found[entry.word] = 2 * COST_EDIT
				end
			end
		end
	end
	local edits = {}
	for candidate, cost in pairs(found) do
		edits[candidate] = cost
		found[candidate] = cost + BAND_COST * (BANDS[level[candidate]] - 1)
	end
	local best, second
	local function Better(a, b)
		return found[a] < found[b] - 0.01
	end
	for candidate in pairs(found) do
		if not best or Better(candidate, best) then
			best, second = candidate, best
		elseif not second or Better(candidate, second) then
			second = candidate
		end
	end
	-- Two words joined is what Swedish does: only a slip (two letters swapped, one doubled) is fixed in what could be one.
	if best and edits[best] > COST_SLIP and ns.Autocorrect_SwedishCompound(word, sv, en) then
		return nil
	end
	if best and (not second or Better(best, second)) and (#chars >= SHORT_MAX + 1 or edits[best] <= COST_SLIP) then
		return best, edits[best], found[best]
	end
	return nil
end
