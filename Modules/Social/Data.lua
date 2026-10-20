local addonName, ns = ...

-- Social modules, pure logic: no WoW API calls (unit-tested with plain Lua). Whisper conversations and
-- unread counts, name mentions, word lists, who came online for Friends and the small text helpers the toasts use.

-- Values other than "off" are keys of SOUNDS in Toast.lua (ns.Social_PlaySound).
ns.SOCIAL_SOUND_CHOICES = {
	{ value = "off", text = "Off" },
	{ value = "whisper", text = "Whisper" },
	{ value = "chime", text = "Chime" },
	{ value = "bell", text = "Bell" },
	{ value = "invite", text = "Invite" },
	{ value = "alarm", text = "Alarm" },
}

local MAX_MESSAGES = 50 -- per conversation
local MAX_CONVERSATIONS = 30

-- How long a toast stays: longer for longer text, within [min, max] seconds.
function ns.Social_HoldTime(text, min, perChar, max)
	local n = type(text) == "string" and #text or 0
	return math.min(math.max(min + n * perChar, min), max)
end

-- Which way the toast stack flows from where it was placed (x, y = the stack's spot, in a screen w x h): it grows
-- down in the upper half and up in the lower half, so it never runs off the screen. Cards come in from the side edge
-- in the outer thirds, else from the top (growing down) or bottom (growing up). Returns grow, from.
function ns.Toast_Flow(x, y, w, h)
	local grow = y >= h / 2 and "down" or "up"
	local from
	if x < w / 3 then
		from = "left"
	elseif x > w * 2 / 3 then
		from = "right"
	else
		from = grow == "down" and "top" or "bottom"
	end
	return grow, from
end

-- How long ago a held-back card came in, for its corner: "40s ago", "3m ago". Nil for a hold too short to mention.
function ns.Toast_HeldText(seconds)
	if not seconds or seconds < 5 then
		return nil
	elseif seconds < 60 then
		return math.floor(seconds) .. "s ago"
	end
	return ns.Ago(seconds) .. " ago"
end

-- store = { convos = { [key] = convo } }, convo = { key, with, char, charName, name, class, bn, last, unread, pinned,
-- messages }. Whispers with a character are per character of yours: key = ns.Social_ConvoKey(with, your GUID), with =
-- their "Name-Realm", char = your GUID, charName = your character's name. Battle.net whispers reach your account:
-- key = with = "bn:BattleTag", no char. Conversations saved before tagging have neither with nor char.
-- info = { name, class, bn, with, char, charName } (kept up to date: a later whisper may know the class);
-- entry = { at, text, out }. An outgoing message (entry.out) marks the conversation read: you answered it.
-- An untagged conversation is claimed by the first tagged message with the same person: it moves to the new key and
-- keeps its messages and pin. Returns the conversation and the key it was claimed from (nil when none).
function ns.Social_AddMessage(store, key, info, entry)
	local convo, claimed = store.convos[key], nil
	if not convo and info.with and info.with ~= key then
		local old = store.convos[info.with]
		if old and old.char == nil then
			store.convos[info.with] = nil
			old.key = key
			store.convos[key] = old
			convo, claimed = old, info.with
		end
	end
	if not convo then
		convo = { key = key, unread = 0, messages = {} }
		store.convos[key] = convo
	end
	convo.with = info.with or convo.with
	convo.char = info.char or convo.char
	convo.charName = info.charName or convo.charName
	convo.name = info.name or convo.name
	convo.class = info.class or convo.class
	convo.bn = info.bn or convo.bn
	convo.last = entry.at
	local messages = convo.messages
	messages[#messages + 1] = entry
	while #messages > MAX_MESSAGES do
		table.remove(messages, 1)
	end
	if entry.out then
		convo.unread = 0
	else
		convo.unread = convo.unread + 1
	end
	ns.Social_TrimConvos(store, MAX_CONVERSATIONS)
	return convo, claimed
end

-- A conversation's key: per character of yours (guid) for a character, one per account for Battle.net ("bn:...").
function ns.Social_ConvoKey(with, guid)
	if not guid or with:sub(1, 3) == "bn:" then
		return with
	end
	return with .. "@" .. guid
end

-- Who to whisper: "Name-Realm" or "bn:BattleTag" (an untagged conversation's key is that already).
function ns.Social_With(convo)
	return convo.with or convo.key
end

-- Whether the character with this GUID can answer it: its own, untagged (old or Battle.net) ones.
function ns.Social_IsMine(convo, guid)
	return convo.char == nil or convo.char == guid
end

-- Conversations, newest first.
function ns.Social_SortedConvos(store)
	local list = {}
	for _, convo in pairs(store.convos) do
		list[#list + 1] = convo
	end
	table.sort(list, function(a, b)
		if a.last ~= b.last then
			return a.last > b.last
		end
		return a.key < b.key
	end)
	return list
end

-- Keeps the newest max conversations; unread ones past max stay, up to a hard cap of 2 * max (spam
-- whispers nobody reads mustn't pile up): past that the oldest go, read or not.
-- Pinned conversations (convo.pinned, from the inbox) are never trimmed or pruned.
function ns.Social_TrimConvos(store, max)
	local list = ns.Social_SortedConvos(store)
	for i = #list, max + 1, -1 do
		if list[i].unread == 0 and not list[i].pinned then
			store.convos[list[i].key] = nil
		end
	end
	list = ns.Social_SortedConvos(store)
	for i = #list, max * 2 + 1, -1 do
		if not list[i].pinned then
			store.convos[list[i].key] = nil
		end
	end
end

-- Forgets read conversations whose last message is older than maxAge seconds, and unread ones older than
-- unreadAge (default twice maxAge).
function ns.Social_PruneConvos(store, now, maxAge, unreadAge)
	unreadAge = unreadAge or maxAge * 2
	for key, convo in pairs(store.convos) do
		local age = now - (convo.last or 0)
		if not convo.pinned and age > (convo.unread == 0 and maxAge or unreadAge) then
			store.convos[key] = nil
		end
	end
end

-- Inbox ---------------------------------------------------------------------------------------------------------

-- The inbox list: pinned conversations first, each part in the order given. Returns the list and how many are
-- pinned.
function ns.Inbox_Order(list)
	local out, pinnedCount = {}, 0
	for _, convo in ipairs(list) do
		if convo.pinned then
			pinnedCount = pinnedCount + 1
			out[#out + 1] = convo
		end
	end
	for _, convo in ipairs(list) do
		if not convo.pinned then
			out[#out + 1] = convo
		end
	end
	return out, pinnedCount
end

-- The header's line about who they are. who = nil (not a friend, guildmate or Battle.net friend), or { online,
-- level, className, area, game } where game is set when they're on Battle.net but not in WoW ("app" = the
-- Battle.net app, else another game's name or true).
function ns.Inbox_StatusText(who)
	if not who then
		return "Not on your friends list"
	end
	if not who.online then
		return "Offline"
	end
	if who.game == "app" then
		return "On the Battle.net app"
	elseif who.game then
		return type(who.game) == "string" and ("Online in " .. who.game) or "Online in another game"
	end
	local parts = { "Online" }
	if who.level and who.className then
		parts[#parts + 1] = ("Level %d %s"):format(who.level, who.className)
	end
	if who.area and who.area ~= "" then
		parts[#parts + 1] = who.area
	end
	return table.concat(parts, " · ")
end

-- Where the NEW divider goes: the index of the first unread message, or nil when nothing was unread.
function ns.Inbox_NewIndex(count, unread)
	if unread <= 0 or count <= 0 then
		return nil
	end
	return math.max(count - unread + 1, 1)
end

-- The conversation as plain text for copying: "<stamp> You: text" / "<stamp> Name: text" per line, links and
-- color codes stripped. stamp(at) formats a message's time.
function ns.Inbox_CopyText(convo, stamp)
	local lines = {}
	for _, m in ipairs(convo.messages) do
		lines[#lines + 1] = ("%s %s: %s"):format(stamp(m.at), m.out and "You" or (convo.name or ns.Social_With(convo)),
			ns.Social_PlainText(m.text))
	end
	return table.concat(lines, "\n")
end

-- Is entry (a message table) still unread? The unread messages are the last convo.unread ones: an answer or reading
-- the conversation sets unread to 0. A message trimmed away counts as read.
function ns.Social_IsUnread(convo, entry)
	if not convo then
		return false
	end
	local messages = convo.messages
	for i = #messages, math.max(#messages - convo.unread + 1, 1), -1 do
		if messages[i] == entry then
			return true
		end
	end
	return false
end

function ns.Social_MarkRead(store, key)
	local convo = store.convos[key]
	if convo then
		convo.unread = 0
	end
end

-- guid (optional): only conversations that are that character's (ns.Social_IsMine).
function ns.Social_MarkAllRead(store, guid)
	for _, convo in pairs(store.convos) do
		if not guid or ns.Social_IsMine(convo, guid) then
			convo.unread = 0
		end
	end
end

-- Total unread messages and the unread conversations, newest first. guid (optional): only that character's
-- conversations (ns.Social_IsMine).
function ns.Social_Unread(store, guid)
	local total, convos = 0, {}
	for _, convo in ipairs(ns.Social_SortedConvos(store)) do
		if convo.unread > 0 and (not guid or ns.Social_IsMine(convo, guid)) then
			total = total + convo.unread
			convos[#convos + 1] = convo
		end
	end
	return total, convos
end

-- "Anna", "Anna and Björn", "Anna, Björn and Cecilia", "Anna, Björn, Cecilia and 2 more".
function ns.Social_NameList(names, max)
	local n = #names
	if n == 0 then
		return ""
	end
	if n == 1 then
		return names[1]
	end
	max = max or 3
	if n <= max then
		return table.concat(names, ", ", 1, n - 1) .. " and " .. names[n]
	end
	return table.concat(names, ", ", 1, max) .. (" and %d more"):format(n - max)
end

-- "Name#1234" -> "Name".
function ns.Social_ShortTag(battleTag)
	if type(battleTag) ~= "string" then
		return nil
	end
	return battleTag:match("^([^#]+)") or battleTag
end

-- A comma-separated list from an input box -> lower-case words (ns.Social_Lower), trimmed, without duplicates or
-- blanks.
function ns.Social_ParseWords(text)
	local list, seen = {}, {}
	for part in (text or ""):gmatch("[^,]+") do
		local word = ns.Social_Lower(part:match("^%s*(.-)%s*$"))
		if word ~= "" and not seen[word] then
			seen[word] = true
			list[#list + 1] = word
		end
	end
	return list
end

-- Chat text without color codes, textures and link wrappers ("|Hitem:...|h[Sword]|h" -> "[Sword]").
function ns.Social_PlainText(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- Whispered links arrive without a color code ("|Hitem:...|h[Sword]|h"; the chat frame colors them itself). Each
-- uncolored link is replaced by paint(kind, link) ("item", "|Hitem:...|h[Sword]|h"), or kept when that returns nil.
-- Links that already carry a color ("|cffa335ee|H...", "|cnIQ4:|H...") are left alone.
function ns.Social_ColorLinks(text, paint)
	return (text:gsub("()(|H(%a+):?[^|]*|h.-|h)", function(at, link, kind)
		local before = text:sub(1, at - 1)
		if before:find("|c%x%x%x%x%x%x%x%x$") or before:find("|cn[^|:]*:$") then
			return nil
		end
		return paint(kind, link)
	end))
end

-- Lower case for names and keywords: string.lower only knows ASCII. Also Latin-1 (À-Þ), Latin Extended-A (Ā-ž) and
-- Cyrillic (Ѐ-Я; ruRU clients). Every mapped letter keeps its byte length, so a position found in the lower-case text
-- is valid in the original (Chat_Highlight relies on that). İ is left alone: its lower case is i plus a combining dot.
local function LowerCodepoint(cp)
	if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then
		return cp + 0x20
	elseif cp >= 0x100 and cp <= 0x17F then
		if cp == 0x178 then
			return 0xFF -- Ÿ -> ÿ
		elseif (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
			return cp % 2 == 1 and cp + 1 or cp -- odd capitals
		elseif cp ~= 0x130 and (cp <= 0x137 or (cp >= 0x14A and cp <= 0x177)) then
			return cp % 2 == 0 and cp + 1 or cp -- even capitals
		end
	elseif cp >= 0x410 and cp <= 0x42F then
		return cp + 0x20
	elseif cp >= 0x400 and cp <= 0x40F then
		return cp + 0x50
	end
	return cp
end

-- A two-byte UTF-8 letter in lower case, or nil to keep it.
local function LowerPair(lead, cont)
	local cp = (lead:byte() - 0xC0) * 64 + (cont:byte() - 0x80)
	local lower = LowerCodepoint(cp)
	if lower == cp then
		return nil
	end
	return string.char(0xC0 + math.floor(lower / 64), 0x80 + lower % 64)
end

function ns.Social_Lower(text)
	return (text:lower():gsub("([\192-\223])([\128-\191])", LowerPair))
end

-- A letter or digit (ASCII), or any byte of a multi-byte UTF-8 character: part of a word.
local function WordByte(b)
	return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- The first word (lower case, from ParseWords) that appears in text as a whole word, or nil.
-- "tomte" matches "hi Tomte!" and "tomte's" but not "tomtes" or "atomte".
function ns.Social_FindMention(text, words)
	if type(text) ~= "string" or #words == 0 then
		return nil
	end
	local lower = ns.Social_Lower(ns.Social_PlainText(text))
	for _, word in ipairs(words) do
		local start = 1
		while true do
			local s, e = lower:find(word, start, true)
			if not s then
				break
			end
			if not WordByte(lower:byte(s - 1)) and not WordByte(lower:byte(e + 1)) then
				return word
			end
			start = s + 1
		end
	end
	return nil
end

-- "now", "5m", "3h", "2d" (Core/Format.lua).
ns.Social_Ago = ns.Ago

-- Toasts held back while busy -> one digest: { count, names } where names are distinct, in arrival order.
function ns.Social_Digest(held)
	local names, seen, count = {}, {}, 0
	for _, toast in ipairs(held) do
		count = count + (toast.count or 1)
		local name = toast.digestName
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	return count, names
end

-- Is any of the names (character name, BattleTag, ...) on the watch list (lower case, from ParseWords)?
-- A BattleTag on the list may leave out the number: "anna" matches "Anna#1234".
function ns.Social_IsWatched(watch, ...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if type(name) == "string" and name ~= "" then
			local lower = ns.Social_Lower(name)
			local short = lower:match("^([^#]+)#") or lower:match("^([^%-]+)%-")
			for _, w in ipairs(watch) do
				if w == lower or w == short then
					return true
				end
			end
		end
	end
	return false
end

-- Keys in now that weren't in before (both sets: [key] = true or a table). nil before = first look: none.
-- known (optional set): only keys in it count; a friend just added to the list didn't "come online".
function ns.Social_NewlyOnline(before, now, known)
	local list = {}
	if not before then
		return list
	end
	for key in pairs(now) do
		if not before[key] and (not known or known[key]) then
			list[#list + 1] = key
		end
	end
	table.sort(list)
	return list
end
