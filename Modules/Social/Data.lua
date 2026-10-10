local addonName, ns = ...

-- Social modules, pure logic: no WoW API calls (unit-tested with plain Lua). Whisper conversations and
-- unread counts, name mentions, word lists and the small text helpers the toasts use.

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

-- store = { convos = { [key] = convo } }, convo = { key, name, class, bn, last, unread, messages }.
-- info = { name, class, bn } (kept up to date: a later whisper may know the class); entry = { at, text, out }.
-- An outgoing message (entry.out) marks the conversation read: you answered it.
function ns.Social_AddMessage(store, key, info, entry)
	local convo = store.convos[key]
	if not convo then
		convo = { key = key, unread = 0, messages = {} }
		store.convos[key] = convo
	end
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
	return convo
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
function ns.Social_TrimConvos(store, max)
	local list = ns.Social_SortedConvos(store)
	for i = #list, max + 1, -1 do
		if list[i].unread == 0 then
			store.convos[list[i].key] = nil
		end
	end
	list = ns.Social_SortedConvos(store)
	for i = #list, max * 2 + 1, -1 do
		store.convos[list[i].key] = nil
	end
end

-- Forgets read conversations whose last message is older than maxAge seconds, and unread ones older than
-- unreadAge (default twice maxAge).
function ns.Social_PruneConvos(store, now, maxAge, unreadAge)
	unreadAge = unreadAge or maxAge * 2
	for key, convo in pairs(store.convos) do
		local age = now - (convo.last or 0)
		if age > (convo.unread == 0 and maxAge or unreadAge) then
			store.convos[key] = nil
		end
	end
end

function ns.Social_MarkRead(store, key)
	local convo = store.convos[key]
	if convo then
		convo.unread = 0
	end
end

function ns.Social_MarkAllRead(store)
	for _, convo in pairs(store.convos) do
		convo.unread = 0
	end
end

-- Total unread messages and the unread conversations, newest first.
function ns.Social_Unread(store)
	local total, convos = 0, {}
	for _, convo in ipairs(ns.Social_SortedConvos(store)) do
		if convo.unread > 0 then
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

-- A comma-separated list from an input box -> lower-case words, trimmed, without duplicates or blanks.
function ns.Social_ParseWords(text)
	local list, seen = {}, {}
	for part in (text or ""):gmatch("[^,]+") do
		local word = part:match("^%s*(.-)%s*$"):lower()
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
	local lower = ns.Social_PlainText(text):lower()
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

-- "now", "5m", "3h", "2d".
function ns.Social_Ago(seconds)
	if seconds < 60 then
		return "now"
	elseif seconds < 3600 then
		return ("%dm"):format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return ("%dh"):format(math.floor(seconds / 3600))
	end
	return ("%dd"):format(math.floor(seconds / 86400))
end

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
			local lower = name:lower()
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
