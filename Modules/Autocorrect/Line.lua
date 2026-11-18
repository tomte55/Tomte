local addonName, ns = ...

-- Autocorrect: pure logic (no WoW API calls; unit-tested in tests/test_autocorrect_line.lua). The chat line around a
-- finished word: two-word fixes (could of, old town), doubled words, the capital at a sentence start, which language
-- the line is in (the Swedish setting), and the undo. One word's own fix is Rules.lua; the edit box hooks are
-- Autocorrect.lua.

-- Characters that finish a word when typed.
ns.AUTOCORRECT_BOUNDARY = { [" "] = true, ["."] = true, [","] = true, ["!"] = true, ["?"] = true, [";"] = true,
	[":"] = true, [")"] = true, ['"'] = true }
-- Kinds of fix whose undo is remembered (by what was typed: a word, or two for pairs and doubled words). Capitals
-- belong to the sentence, so they're undone once only.
local REMEMBERED = { own = true, spelling = true, apostrophes = true, names = true, pairs = true, tidying = true }
-- A word in the line: letters, and any byte of a multi-byte letter (å, ä, ö), with inner apostrophes.
local WORD = "[%a\128-\255][%a\128-\255']*"

local Cased = ns.Autocorrect_Cased

-- Slash commands (and anything typed after one) are never touched.
function ns.Autocorrect_LineSkipped(text)
	return text:find("^%s*/") ~= nil
end

-- Whether the end of head sits inside a link's text (|H...|h[ typed so far, no closing ]|h yet).
local function InOpenLink(head)
	local open = head:match(".*()|H")
	if not open then
		return false
	end
	local close = head:match(".*()%]|h")
	return not close or close < open
end

local function Refused(ctx, typed, fix)
	local list = ctx.refused[typed]
	return list and list[ns.Autocorrect_Lower(fix)] or false
end

-- The edited line: text with bytes from..to replaced by segment, and the change that undoes it.
local function Apply(text, cursor, from, to, segment, info)
	local after = text:sub(1, from - 1) .. segment .. text:sub(to + 1)
	local newCursor = cursor + #segment - (to - from + 1)
	info.before, info.after, info.cursor, info.oldCursor = text, after, newCursor, cursor
	if REMEMBERED[info.kind] then
		info.remember, info.rememberFix = ns.Autocorrect_Lower(info.typed), ns.Autocorrect_Lower(info.fix)
	end
	return after, newCursor, info
end

-- The word before the current one, when only spaces sit between them: start, word, the spaces.
local function PreviousWord(before)
	local start, word, gap = before:match("()(" .. WORD .. ")(%s+)$")
	if start and (start == 1 or before:sub(start - 1, start - 1):find("%s")) then
		return start, word, gap
	end
end

-- Two-word fixes: a place name (old town), a word pair (could of), a doubled word (the the).
local function Pair(text, cursor, wordEnd, ctx, prevStart, prev, gap, word)
	local kinds = ctx.kinds
	local Lower = ctx.sv and ns.Autocorrect_Lower or string.lower
	local pl, wl = Lower(prev), Lower(word)
	local english = ctx.lang ~= "sv"
	local typed = pl .. " " .. wl
	local shown = prev .. " " .. word
	local place = kinds.names and ctx.places2 and ctx.places2[typed]
	if place and place ~= shown and not Refused(ctx, typed, place) then
		local a, b = place:match("^(%S+) (%S+)$")
		return Apply(text, cursor, prevStart, wordEnd, a .. gap .. b,
			{ kind = "names", typed = shown, fix = place })
	end
	if kinds.pairs and english then
		for _, rule in ipairs(ns.AUTOCORRECT_PAIRS) do
			if rule[1] == pl and rule[2][wl] then
				local a = rule[3] and Cased(prev, rule[3]) or prev
				local b = rule[4] and Cased(word, rule[4]) or word
				local fix = a .. " " .. b
				if not Refused(ctx, typed, fix) then
					return Apply(text, cursor, prevStart, wordEnd, a .. gap .. b,
						{ kind = "pairs", typed = shown, fix = fix })
				end
			end
		end
	end
	local fine = ns.AUTOCORRECT_DOUBLES_OK[wl] or (ctx.sv and ns.AUTOCORRECT_SV_DOUBLES_OK[wl])
	if kinds.tidying and pl == wl and not fine and not ctx.names[wl] and not ctx.keep[wl]
		and not Refused(ctx, typed, wl) then
		return Apply(text, cursor, prevStart + #prev, wordEnd, "", { kind = "tidying", typed = shown, fix = prev })
	end
end

-- After the player typed a boundary character at cursor (a byte offset, the character just before it): the fixed
-- line, the new cursor and the change, or nil when nothing changes. atEnd: the send pass, where cursor is the end of
-- the line and no boundary was typed.
function ns.Autocorrect_Finish(text, cursor, ctx, atEnd)
	if ns.Autocorrect_LineSkipped(text) then
		return nil
	end
	local wordEnd = cursor
	if not atEnd then
		if not ns.AUTOCORRECT_BOUNDARY[text:sub(cursor, cursor)] or text:sub(cursor + 1):find("^%S") then
			return nil -- not the end of a word, or typed inside one
		end
		wordEnd = cursor - 1
	end
	local head = text:sub(1, wordEnd)
	if InOpenLink(head) then
		return nil
	end
	local start = head:find("%S+$")
	if not start then
		return nil
	end
	local lead, word = head:sub(start):match("^([%(%[\"']*)(.*)$")
	if word == "" or word:find("%p$") and not word:find("%a'$") then
		return nil -- ends in punctuation: fixed when that was typed
	end
	local wordStart = start + #lead
	local before = head:sub(1, wordStart - 1)
	-- The Swedish setting: which language the line is in, from the words before this one (Swedish.lua).
	if ctx.sv then
		local words = {}
		for w in before:gsub("|H.-|h.-|h", ""):gmatch(WORD) do
			words[#words + 1] = ns.Autocorrect_Lower(w)
		end
		-- The conversation (ctx.conversation: party, guild, a whisper ...) decides only where the words don't.
		ctx.lang = ns.Autocorrect_Language(words, ctx.dict.level, ctx.sv.level, ctx.sv.letters, ctx.conversation)
	end

	local prevStart, prev, gap = PreviousWord(before)
	if prev then
		local a, b, c = Pair(text, cursor, wordEnd, ctx, prevStart, prev, gap, word)
		if a then
			ctx.lang = nil
			return a, b, c
		end
	end

	local sentenceStart = lead == "" and (before:find("^%s*$") or before:find("[%.!%?]%s+$")) and true or false
	ctx.sentenceStart = sentenceStart
	local fix, kind = ns.Autocorrect_Word(word, ctx)
	ctx.sentenceStart, ctx.lang = nil, nil
	local out = fix or word
	local swedish = ctx.sv ~= nil
	local lower = swedish and ns.Autocorrect_Lower(word) or word:lower()
	local small = out:find("^%l") or (swedish and out:find("^\195[\164\165\169\182]"))
	if sentenceStart and ctx.kinds.capitals and small and ns.Autocorrect_TakesCapital(word, swedish)
		and not ctx.keep[lower] and not ctx.names[lower] then
		out = ns.Autocorrect_CapitalFirst(out)
		kind = kind or "capitals"
	end
	if out == word then
		return nil
	end
	local info = { kind = kind, typed = word, fix = out }
	local after, newCursor = Apply(text, cursor, wordStart, wordEnd, out, info)
	if fix and info.remember then
		info.rememberFix = ns.Autocorrect_Lower(fix) -- the word's own fix, not the sentence's capital
	end
	return after, newCursor, info
end

-- The line as it was before change, and the cursor where it was: only while the line and cursor are exactly as the
-- fix left them (Backspace right after a fix). nil otherwise.
function ns.Autocorrect_Undo(text, cursor, change)
	if change and text == change.after and cursor == change.cursor then
		return change.before, change.oldCursor
	end
	return nil
end
