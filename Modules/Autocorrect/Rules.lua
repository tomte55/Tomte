local addonName, ns = ...

-- Autocorrect: pure logic (no WoW API calls; unit-tested in tests/test_autocorrect.lua). What to do with one finished
-- word: the player's own words, known typos, apostrophes, capitals and names, words run together, and a guess at the
-- nearest English word when one is clearly best. The line around the word (pairs, doubles, sentence starts, undo) is
-- Line.lua; the tables are Data.lua and the generated Words.lua.

local GUESS_MIN = 4 -- shorter words are too ambiguous to guess (known short typos are in AUTOCORRECT_TYPOS)
local SHORT_MAX = 4 -- words this short are only guessed for a slip (nede -> need), never slang (gief, heya)
local GUESS_MAX = 20 -- longer "words" are keyboard mash or links pasted as text: no guess (and no hitch on a key)
local FAR_MIN = 6 -- words this long may be two edits away from the right one
local GUESS_LEVEL = 50 -- guesses only become words of this SCOWL size or more common
local FAR_LEVEL = 35 -- two-edit guesses only become common words
local SPLIT_LEVEL = 35 -- both halves of a split are at least this common
local KNOWN_LEVEL = 60 -- game and learned words: known, but rarer than any guess may become
-- What an edit costs: a slip (swapped neighbours, a doubled or missing double letter, a silent e kept before -ing or
-- -ed: stareing) is likelier than any other change; hitting the key next to the right one is in between.
local COST_EDIT, COST_SLIP, COST_KEY = 1, 0.5, 0.75
local BAND_COST = 0.25 -- added per commonness band below the top one
local LETTERS = "abcdefghijklmnopqrstuvwxyz"
-- SCOWL sizes, most common first: a guess beats another of the same cost only by being in an earlier band.
local BANDS = { [10] = 1, [20] = 1, [35] = 2, [40] = 3, [50] = 3, [55] = 4, [60] = 4 }

local function Lines(text, fn)
	for line in text:gmatch("[^\r\n]+") do
		fn(line)
	end
end

-- The lookup tables, built once when the module starts (tens of thousands of words: not at load).
function ns.Autocorrect_NewDict(words, upper, contractions)
	local dict = { level = {}, upper = {}, contraction = {}, buckets = {} }
	local level = dict.level
	for size, text in pairs(words) do
		Lines(text, function(word)
			if not level[word] or level[word] > size then
				level[word] = size
			end
		end)
	end
	Lines(upper, function(word)
		local lower = word:lower()
		if not level[lower] then
			dict.upper[lower] = word
		end
	end)
	local never = ns.AUTOCORRECT_NOT_CONTRACTIONS
	Lines(contractions, function(word)
		local bare = word:gsub("'", ""):lower()
		if not level[bare] and not never[bare] then
			dict.contraction[bare] = word
		end
	end)
	for bare, word in pairs(ns.AUTOCORRECT_APOSTROPHES) do
		dict.contraction[bare] = word
	end
	ns.Autocorrect_AddWords(dict, ns.AUTOCORRECT_GAME_WORDS)
	return dict
end

-- Words that are right as typed but no guess should ever turn into ({ [word] = true }, any case): game words, words
-- the client knows, words other players use.
function ns.Autocorrect_AddWords(dict, words)
	local level = dict.level
	for word in pairs(words) do
		local lower = word:lower()
		if not level[lower] then
			level[lower] = KNOWN_LEVEL
		end
	end
end

-- Place names split into single words (lowercase = Proper, only where the lowercase form isn't an English word) and
-- two-word names ("old town" = "Old Town"). Longer names are left to the player.
function ns.Autocorrect_Places(list, dict, single, double)
	single, double = single or {}, double or {}
	for _, name in ipairs(list) do
		local a, b, extra = name:match("^(%S+)%s*(%S*)%s*(.*)$")
		if a and b == "" then
			local lower = a:lower()
			if lower:find("^[a-z]+$") and not dict.level[lower] then
				single[lower] = name
			end
		elseif a and extra == "" then
			double[name:lower()] = name
		end
	end
	return single, double
end

-- Words never touched, whoever typed them: anything but letters (and an inner apostrophe), shouting, stretched words
-- ("sooo"), chat shorthand.
function ns.Autocorrect_Skip(word)
	if not word:find("^[A-Za-z]+'?[A-Za-z]*$") or word:find("'$") then
		return true, "not a plain word"
	end
	if #word >= 2 and not word:find("%l") then
		return true, "written in capitals"
	end
	local last = word:sub(-1):lower()
	if #word >= 3 and word:sub(-3):lower() == last:rep(3) then
		return true, "stretched on purpose"
	end
	if ns.AUTOCORRECT_SHORTHAND[word:lower()] then
		return true, "chat shorthand"
	end
	return false
end

-- Guessing -----------------------------------------------------------------------------------------------------------

local neighbours -- [letter] = { [letter] = true } for keys side by side
local function Neighbours()
	if not neighbours then
		neighbours = {}
		for _, row in ipairs(ns.AUTOCORRECT_KEYS) do
			for i = 1, #row do
				local c = row:sub(i, i)
				neighbours[c] = neighbours[c] or {}
				if i > 1 then
					neighbours[c][row:sub(i - 1, i - 1)] = true
				end
				if i < #row then
					neighbours[c][row:sub(i + 1, i + 1)] = true
				end
			end
		end
	end
	return neighbours
end

-- Every word one edit away, with what the edit costs: cb(candidate, cost).
local function Edits(word, cb)
	local n = #word
	local near = Neighbours()
	for i = 1, n do
		local before, c, after = word:sub(1, i - 1), word:sub(i, i), word:sub(i + 1)
		local doubled = c == word:sub(i - 1, i - 1) or c == word:sub(i + 1, i + 1)
		local silentE = c == "e" and (after:find("^ing") or after:find("^ed")) and i > 2
		cb(before .. after, (doubled or silentE) and COST_SLIP or COST_EDIT) -- delete
		if i < n then
			local d = word:sub(i + 1, i + 1)
			cb(before .. d .. c .. word:sub(i + 2), COST_SLIP) -- swap
		end
		for j = 1, #LETTERS do
			local r = LETTERS:sub(j, j)
			if r ~= c then
				cb(before .. r .. after, (near[c] and near[c][r]) and COST_KEY or COST_EDIT) -- replace
			end
		end
	end
	for i = 0, n do
		local before, after = word:sub(1, i), word:sub(i + 1)
		for j = 1, #LETTERS do
			local r = LETTERS:sub(j, j)
			local doubled = r == word:sub(i, i) or r == word:sub(i + 1, i + 1)
			cb(before .. r .. after, doubled and COST_SLIP or COST_EDIT) -- insert
		end
	end
end

-- Optimal string alignment distance (swaps count as one edit), or limit + 1 once it's over the limit.
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
		local ca = a:byte(i)
		for j = 1, lb do
			local cb = b:byte(j)
			local v = prev[j - 1] + (ca == cb and 0 or 1)
			if prev[j] + 1 < v then
				v = prev[j] + 1
			end
			if cur[j - 1] + 1 < v then
				v = cur[j - 1] + 1
			end
			if i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == cb and prev2[j - 2] + 1 < v then
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

-- Common words by first letter and length, for two-edit guesses ([letter .. length] = { words }), sorted on first use.
local function Bucket(dict, key)
	local buckets = dict.buckets
	if not next(buckets) then
		for word, size in pairs(dict.level) do
			if size <= FAR_LEVEL and not word:find("'") then
				local k = word:sub(1, 1) .. #word
				local list = buckets[k]
				if not list then
					list = {}
					buckets[k] = list
				end
				list[#list + 1] = word
			end
		end
	end
	return buckets[key] or NONE
end

-- Whether a word is two known words joined ("minipet", "bankalt"): a compound the player meant, not a typo.
local function Compound(word, level)
	for i = 3, #word - 3 do
		if level[word:sub(1, i)] and level[word:sub(i + 1)] then
			return true
		end
	end
	return false
end

-- The nearest English word to a lowercase word and what the edits cost, when one is clearly the best; nil when none
-- is or it's a toss-up.
function ns.Autocorrect_Guess(word, dict, refused)
	if #word < GUESS_MIN or #word > GUESS_MAX then
		return nil
	end
	local level, never = dict.level, ns.AUTOCORRECT_NO_GUESS
	local found = {} -- [candidate] = cost
	Edits(word, function(candidate, cost)
		local size = level[candidate]
		if size and size <= GUESS_LEVEL and not candidate:find("'") and (found[candidate] or 99) > cost
			and not never[candidate] and not (refused and refused[candidate]) then
			found[candidate] = cost
		end
	end)
	if not next(found) and #word >= FAR_MIN and not Compound(word, level) then
		local first = word:sub(1, 1)
		for len = #word - 2, #word + 2 do
			for _, candidate in ipairs(Bucket(dict, first .. len)) do
				if Distance(word, candidate, 2) <= 2 and not never[candidate] and not (refused and refused[candidate]) then
					found[candidate] = 2 * COST_EDIT
				end
			end
		end
	end
	-- Score: the edits' cost plus a little for each band rarer than the most common words.
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
	if best and (not second or Better(best, second)) and (#word >= SHORT_MAX + 1 or edits[best] <= COST_SLIP) then
		return best, edits[best]
	end
	return nil
end

-- "tothe" -> "to the": one half a short everyday word (AUTOCORRECT_SPLIT_WORDS), the other a common word, and the
-- cut whose rarer half is the most common when there's a choice ("tot he" loses to "to the"); nil on a tie.
function ns.Autocorrect_Split(word, dict)
	local level, short, shortRight = dict.level, ns.AUTOCORRECT_SPLIT_WORDS, ns.AUTOCORRECT_SPLIT_RIGHT
	local found, rank, tie
	for i = 1, #word - 1 do
		local left, right = word:sub(1, i), word:sub(i + 1)
		local l = level[left] or 99
		local r = #right >= 2 and level[right] or 99
		local worst = BANDS[math.max(l, r)]
		if worst and math.max(l, r) <= SPLIT_LEVEL and (short[left] or shortRight[right]) then
			if not rank or worst < rank then
				found, rank, tie = (left == "i" and "I" or left) .. " " .. right, worst, false
			elseif worst == rank then
				tie = true
			end
		end
	end
	return not tie and found or nil
end

-- One word ---------------------------------------------------------------------------------------------------------

-- The typed word's leading capital carried over to the fix.
local function Cased(typed, fix)
	if typed:find("^%u") then
		return fix:sub(1, 1):upper() .. fix:sub(2)
	end
	return fix
end
ns.Autocorrect_Cased = Cased

-- What to do with a finished word: fix, kind, reason (reason in player wording, for /tomte autocorrect why). ctx:
-- dict, kinds (which fixes are on), own / keep / refused (the player's words), names (people, lowercase = true),
-- places (single-word place names, lowercase = Proper), sentenceStart.
function ns.Autocorrect_Word(word, ctx)
	local skip, why = ns.Autocorrect_Skip(word)
	if skip then
		return nil, nil, why
	end
	local lower = word:lower()
	if ctx.keep[lower] then
		return nil, nil, "you keep this word"
	end
	if ctx.names[lower] then
		return nil, nil, "a name you know"
	end
	if word:sub(2):find("%u") then
		return nil, nil, "mixed capitals"
	end
	local kinds, dict = ctx.kinds, ctx.dict
	local refused = ctx.refused[lower]
	-- A known fix that's turned off or was undone ends it there: no guessing past it (dont never becomes font).
	local blocked
	local function Offer(fix, kind)
		if not fix then
			return nil
		end
		if (kind == "own" or kinds[kind]) and not (refused and refused[fix:lower()]) then
			return Cased(word, fix)
		end
		blocked = blocked or kind
	end
	local STEPS = {
		{ ctx.own[lower], "own", "your own correction" },
		{ ns.AUTOCORRECT_TYPOS[lower], "spelling", "a common typo" },
		{ dict.contraction[lower], "apostrophes", "missing its apostrophe" },
		{ lower == "i" and "I" or nil, "capitals", "always a capital" },
		{ ctx.places[lower] or dict.upper[lower], "names", "a name written with a capital" },
	}
	for _, step in ipairs(STEPS) do
		local fix = Offer(step[1], step[2])
		if fix then
			return fix, step[2], step[3]
		end
	end
	if blocked then
		return nil, nil, "its fix (" .. blocked .. ") is off or you undid it"
	end
	if dict.level[lower] then
		return nil, nil, "an English word"
	end
	if word:find("^%u") then
		return nil, nil, "an unknown word with a capital: taken as a name"
	end
	if word:find("'") then
		return nil, nil, "an unknown word with an apostrophe"
	end
	if lower:find("in$") and dict.level[lower .. "g"] then
		return nil, nil, "dialect: " .. lower .. "' for " .. lower .. "g"
	end
	if lower:find("s$") and dict.level[lower:sub(1, -2)] then
		return nil, nil, "more than one " .. lower:sub(1, -2)
	end
	-- A slip (sumon -> summon) beats a split (sum on); otherwise the split goes first (tothe -> to the, not tithe).
	local guess, cost
	if kinds.spelling then
		guess, cost = ns.Autocorrect_Guess(lower, dict, refused)
	end
	if not (guess and cost <= COST_SLIP) then
		local fix = Offer(ns.Autocorrect_Split(lower, dict), "tidying")
		if fix then
			return fix, "tidying", "two words run together"
		elseif blocked then
			return nil, nil, "two words run together, and tidying is off or you undid it"
		end
	end
	if guess then
		return Cased(word, guess), "spelling", "the one clear nearest word"
	end
	return nil, nil, "no clear fix"
end
