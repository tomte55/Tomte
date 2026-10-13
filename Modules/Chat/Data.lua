local addonName, ns = ...

-- Chat: pure logic shared by Trade Filter, Chat Tabs, Channel Tags and Chat Copy (unit-tested with plain Lua, no WoW
-- API).
-- Word matching follows Mentions (ns.Social_FindMention): whole words, not case sensitive, link text included.

-- Channels the modules offer, by zone channel ID (ChatChannels DB2), so client language doesn't matter.
-- short: the tag in Channel Tags' short styles.
ns.CHAT_CHANNELS = {
	{ key = "trade", id = 2, label = "Trade", short = "T" },
	{ key = "services", id = 42, label = "Trade (Services)", short = "S" },
	{ key = "general", id = 1, label = "General", short = "Gen" },
	{ key = "lfg", id = 26, label = "LookingForGroup", short = "LFG" },
	{ key = "defense", id = 22, label = "LocalDefense", short = "LD" },
}
ns.CHAT_CHANNEL_BY_ID = {}
for _, channel in ipairs(ns.CHAT_CHANNELS) do
	ns.CHAT_CHANNEL_BY_ID[channel.id] = channel
end

-- Common trade chat abbreviations per primary profession (base skill line ID), on top of the localized name.
-- English slang, used on most servers whatever the client language.
local PROF_ABBREVIATIONS = {
	[164] = { "bs", "smith", "blacksmith" }, -- Blacksmithing
	[165] = { "lw", "leatherworker" }, -- Leatherworking
	[197] = { "tailor" }, -- Tailoring
	[755] = { "jc", "jewelcrafter" }, -- Jewelcrafting
	[333] = { "ench", "enchanter", "chanter" }, -- Enchanting
	[171] = { "alch", "alchy", "alchemist" }, -- Alchemy
	[202] = { "engi", "engineer" }, -- Engineering
	[773] = { "scribe", "insc" }, -- Inscription
	[186] = { "miner", "ore" }, -- Mining
	[182] = { "herb", "herbs", "herbalist" }, -- Herbalism
	[393] = { "skinner" }, -- Skinning
}

-- Keywords, lower case and without duplicates. profs: { { name = localized name, skillLine = base ID } };
-- extraText: the user's comma-separated keywords.
function ns.Chat_BuildKeywords(profs, useProfs, extraText)
	local list, seen = {}, {}
	local function Add(word)
		word = word and word:match("^%s*(.-)%s*$"):lower()
		if word and word ~= "" and not seen[word] then
			seen[word] = true
			list[#list + 1] = word
		end
	end
	if useProfs then
		for _, prof in ipairs(profs or {}) do
			Add(prof.name)
			for _, abbr in ipairs(PROF_ABBREVIATIONS[prof.skillLine] or {}) do
				Add(abbr)
			end
		end
	end
	for _, word in ipairs(ns.Social_ParseWords(extraText)) do
		Add(word)
	end
	return list
end

-- Show a filtered channel message? Only when it has a keyword and none of the ignore words.
function ns.Chat_Decide(text, keywords, ignoreWords)
	if not ns.Social_FindMention(text, keywords) then
		return false
	end
	if ignoreWords and ns.Social_FindMention(text, ignoreWords) then
		return false
	end
	return true
end

-- Keyword highlighting (Trade Filter).

-- A letter or digit (ASCII), or any byte of a multi-byte UTF-8 character: part of a word (as in Social/Data.lua).
local function WordByte(b)
	return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- Length of the escape sequence starting at i ("|" in text), or nil when it isn't one we skip whole.
-- A hyperlink is skipped up to its closing |h: a color code inside |H...|h breaks the link.
local function EscapeLength(text, i)
	local nextChar = text:sub(i + 1, i + 1)
	local s, e
	if nextChar == "H" then
		s, e = text:find("^|H.-|h.-|h", i)
	elseif nextChar == "c" then
		s, e = text:find("^|c%x%x%x%x%x%x%x%x", i)
		if not e then
			s, e = text:find("^|cn[^:|]*:", i) -- named color: |cnPURE_RED_COLOR:
		end
	elseif nextChar == "K" then
		s, e = text:find("^|K.-|k", i) -- Battle.net protected name
	elseif nextChar == "r" or nextChar == "|" then
		return 2
	elseif nextChar == "T" then
		s, e = text:find("^|T.-|t", i)
	elseif nextChar == "A" then
		s, e = text:find("^|A.-|a", i)
	end
	return e and (e - i + 1) or nil
end

local function HighlightPlain(plain, words, wrap)
	local lower = plain:lower()
	local out, i, last = {}, 1, 1
	while i <= #plain do
		local best
		if not WordByte(lower:byte(i - 1)) then
			for _, word in ipairs(words) do
				local e = i + #word - 1
				if (not best or #word > best) and lower:sub(i, e) == word and not WordByte(lower:byte(e + 1)) then
					best = #word
				end
			end
		end
		if best then
			out[#out + 1] = plain:sub(last, i - 1)
			out[#out + 1] = wrap(plain:sub(i, i + best - 1))
			i = i + best
			last = i
		else
			i = i + 1
		end
	end
	out[#out + 1] = plain:sub(last)
	return table.concat(out)
end

-- Every whole-word keyword match passed through wrap(original text), outside links and escape sequences.
function ns.Chat_Highlight(text, words, wrap)
	if #words == 0 then
		return text
	end
	local out, plainStart, i = {}, 1, 1
	while i <= #text do
		local len = text:byte(i) == 124 and EscapeLength(text, i) -- 124 = "|"
		if len then
			out[#out + 1] = HighlightPlain(text:sub(plainStart, i - 1), words, wrap)
			out[#out + 1] = text:sub(i, i + len - 1)
			i = i + len
			plainStart = i
		else
			i = i + 1
		end
	end
	out[#out + 1] = HighlightPlain(text:sub(plainStart), words, wrap)
	return table.concat(out)
end

-- Channel tags (Channel Tags).

ns.CHAT_TAG_STYLES = {
	{ value = "full", text = "[2. Trade - City]" },
	{ value = "name", text = "[2. Trade]" },
	{ value = "numshort", text = "[2. T]" },
	{ value = "short", text = "[T]" },
	{ value = "number", text = "[2]" },
}

-- "Trade=T, Guild=Gu" -> { trade = "T", guild = "Gu" }. Entries without both sides are skipped.
function ns.Chat_ParseLabels(text)
	local labels = {}
	for part in (text or ""):gmatch("[^,]+") do
		local key, label = part:match("^%s*(.-)%s*=%s*(.-)%s*$")
		if key and key ~= "" and label ~= "" then
			labels[key:lower()] = label
		end
	end
	return labels
end

-- The tag text (no brackets) for a numbered channel. name: the part after "N. " ("Trade - City");
-- shortcut: the channel's shortcut ("Trade") or nil; zoneID: its zone channel ID (0 for custom channels).
function ns.Chat_ChannelTag(style, number, name, shortcut, zoneID, labels)
	if style == "full" then
		return number .. ". " .. name
	end
	local base = name:match("^(.-) %- ") or name
	local custom = (shortcut and labels[shortcut:lower()]) or labels[base:lower()]
	local known = ns.CHAT_CHANNEL_BY_ID[zoneID]
	local short = custom or (known and known.short) or base
	if style == "numshort" then
		return number .. ". " .. short
	elseif style == "short" then
		return short
	elseif style == "number" then
		return number
	end
	return number .. ". " .. (custom or base) -- "name", and any unknown style
end

-- Guild and group tags: the localized text Blizzard puts in brackets (read from its CHAT_<type>_GET format strings)
-- -> abbreviation. Also returns the raid warning text, the one tag without a link.
local GROUP_ABBREVIATIONS = {
	GUILD = "G", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL",
	INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
}

function ns.Chat_GroupTags(getGlobal)
	local tags = {}
	for chatType, abbr in pairs(GROUP_ABBREVIATIONS) do
		local format = getGlobal("CHAT_" .. chatType .. "_GET")
		local text = type(format) == "string" and format:match("%[(.-)%]")
		if text and text ~= "" then
			tags[text] = abbr
		end
	end
	local warning = getGlobal("CHAT_RAID_WARNING_GET")
	return tags, type(warning) == "string" and warning:match("%[(.-)%]") or nil
end

-- A formatted chat line with its tag shortened. ctx: { style, labels, group (also guild/group tags), groupTags,
-- raidWarning, channelInfo(number) -> shortcut, zoneID }.
function ns.Chat_ShortenLine(line, ctx)
	line = line:gsub("(|Hchannel:([^|]*)|h)%[(.-)%](|h)", function(open, target, text, close)
		if target:lower():find("^channel:") then
			local number, name = text:match("^(%d+)%. (.*)$")
			if not number then
				return nil
			end
			local shortcut, zoneID = ctx.channelInfo(number)
			return open .. "[" .. ns.Chat_ChannelTag(ctx.style, number, name, shortcut, zoneID or 0, ctx.labels) .. "]" .. close
		elseif ctx.group then
			local abbr = ctx.labels[text:lower()] or ctx.groupTags[text]
			if abbr then
				return open .. "[" .. abbr .. "]" .. close
			end
		end
		return nil
	end)
	if ctx.group and ctx.raidWarning then
		local tag = "[" .. ctx.raidWarning .. "]"
		local s, e = line:find(tag, 1, true)
		-- Only as the line's own tag: nothing before it but a timestamp ("12:00 ", "[12:00:01] ").
		if s and line:sub(1, s - 1):find("^[%d%s:%.%[%]APMapm]*$") then
			local abbr = ctx.labels[ctx.raidWarning:lower()] or "RW"
			line = line:sub(1, s - 1) .. "[" .. abbr .. "]" .. line:sub(e + 1)
		end
	end
	return line
end

-- Copying chat (Chat Copy).

-- Stands in for a Battle.net name (|K...|k): only the game can show those, addons can't read the name.
ns.CHAT_BNET_NAME = "<friend>"
ns.CHAT_HIDDEN_LINE = "<hidden line>"

-- A stored chat line as plain text: links become their text, Battle.net names CHAT_BNET_NAME, colors, textures and
-- atlases go. "||" (an escaped bar) is held aside first so it can't be read as the start of a code.
function ns.Chat_PlainLine(line)
	line = line:gsub("||", "\1")
	line = line:gsub("|H.-|h(.-)|h", "%1")
	line = line:gsub("|K.-|k", ns.CHAT_BNET_NAME)
	line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	line = line:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	line = line:gsub("|n", "\n")
	line = line:gsub("\1", "|")
	return (line:gsub("%s+$", ""))
end

-- A timestamp at the start of a line, in any of Blizzard's formats: "12:00 ", "03:15 PM ", "[12:00:01] ".
local TIMESTAMP = "^%[?%d%d?[:%.]%d%d[:%.%d]*%s?[AaPp]?%.?[Mm]?%.?%]?%s+"

-- The shorter line "Clean lines" gives: no timestamp, no channel or group tag, player names without brackets.
function ns.Chat_CleanLine(line)
	line = line:gsub("|Hchannel:.-|h.-|h%s*", "")
	line = line:gsub("|H(%a*[Pp]layer.-)|h%[(.-)%]|h", "|H%1|h%2|h")
	return (ns.Chat_PlainLine(line):gsub(TIMESTAMP, ""))
end

-- The copy text for a chat window. lines: its stored lines, oldest first; false for a line the game hides from
-- addons (chat lockdown). Clean drops empty lines.
function ns.Chat_CopyText(lines, clean)
	local out = {}
	for _, line in ipairs(lines) do
		local text
		if line == false then
			text = ns.CHAT_HIDDEN_LINE
		elseif clean then
			text = ns.Chat_CleanLine(line)
		else
			text = ns.Chat_PlainLine(line)
		end
		if not (clean and text == "") then
			out[#out + 1] = text
		end
	end
	return table.concat(out, "\n")
end
