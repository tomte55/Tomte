local addonName, ns = ...

-- Groups in chat (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_chatgroups.lua).
-- Reads a chat message into who is looking for what, and keeps the list. ChatGroups.lua feeds it, Page.lua shows it. See
-- docs/superpowers/specs/2026-11-06-tomte-forever-rest-and-chat-groups.md.

local MAX_ENTRIES = 60 -- the page's list stays short enough to read
local NEAR_LEVELS = 3 -- how far outside a dungeon's levels still counts as near yours

-- Whole words that mean something else is going on: sales, boosts and guild ads name dungeons too.
local NOT_LOOKING = { "wts", "wtb", "wtt", "selling", "buying", "boost", "boosting", "boosts", "summons", "lfw", "guild", "recruiting" }
local FOR_MEMBERS = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "need", "needs", "looking for more" }
local FOR_GROUP = { "lfg", "lf group", "looking for group", "looking for a group" }
-- Enough without a dungeon named: a quest group, say. "need" and a plain "lf" aren't: "need a drink", "lf enchanter".
local PLAIN_ASKING = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lfg", "lf group", "looking for group", "looking for a group" }
local ROLE_WORDS = {
	tank = { "tank", "tanks" },
	heal = { "heal", "heals", "healer", "healers", "healz" },
	dps = { "dps", "dd", "damage" },
}

-- Lowercase words with single spaces, and one at each end so a word can be found whole. A link counts as its name.
local function Words(text)
	local plain = text:gsub("|H.-|h%[?(.-)%]?|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	plain = plain:lower():gsub("'", ""):gsub("[^%w]+", " ")
	return " " .. plain .. " "
end

-- Where the first of these whole words or phrases starts, nil when none is there.
local function Find(words, list)
	local first
	for _, word in ipairs(list) do
		local at = words:find(" " .. word .. " ", 1, true)
		if at and (not first or at < first) then
			first = at
		end
	end
	return first
end

-- The dungeon named first in the message. Longest wins at the same spot, so "dm east" isn't read as "dm".
local function FindDungeon(words, dungeons)
	local best, bestAt, bestLen
	for _, dungeon in ipairs(dungeons) do
		for _, alias in ipairs(dungeon.aliases) do
			local at = words:find(" " .. alias .. " ", 1, true)
			if at and (not bestAt or at < bestAt or (at == bestAt and #alias > bestLen)) then
				best, bestAt, bestLen = dungeon, at, #alias
			end
		end
	end
	return best
end

-- Whether the message says something besides the asking: a bare "lfm" tells nobody anything.
local function SaysMore(words)
	local rest = words
	for _, word in ipairs(PLAIN_ASKING) do
		rest = rest:gsub(" " .. word .. " ", " ")
	end
	return rest:find("%w") ~= nil
end

-- What a message says, or nil if it isn't someone looking: { kind = "group" (a group wants people) | "player" (someone wants
-- a group), dungeon = key, or nil for anything else such as a quest, tank, heal, dps }. dungeons: Data/Forever/Dungeons.lua's
-- list.
function ns.ChatGroups_Parse(text, dungeons)
	if type(text) ~= "string" then
		return nil
	end
	local words = Words(text)
	if Find(words, NOT_LOOKING) then
		return nil
	end
	local dungeon = FindDungeon(words, dungeons)
	if not dungeon and not (Find(words, PLAIN_ASKING) and SaysMore(words)) then
		return nil
	end
	local roles = { tank = Find(words, ROLE_WORDS.tank) ~= nil, heal = Find(words, ROLE_WORDS.heal) ~= nil,
		dps = Find(words, ROLE_WORDS.dps) ~= nil }
	local kind
	if Find(words, FOR_MEMBERS) then
		kind = "group"
	elseif Find(words, FOR_GROUP) then
		kind = "player"
	elseif words:find(" lf ", 1, true) then
		-- "lf tank for rfc" is a group wanting a role; "lf rfc" could be either, and most often is someone wanting a group.
		kind = (roles.tank or roles.heal or roles.dps) and "group" or "player"
	else
		return nil
	end
	return { kind = kind, dungeon = dungeon and dungeon.key, tank = roles.tank, heal = roles.heal, dps = roles.dps }
end

-- Adds an entry { sender, at, ... } at the top: a sender's new message replaces the old one. The oldest fall off the end.
function ns.ChatGroups_Add(list, entry)
	for i = #list, 1, -1 do
		if list[i].sender == entry.sender then
			table.remove(list, i)
		end
	end
	table.insert(list, 1, entry)
	while #list > MAX_ENTRIES do
		table.remove(list)
	end
end

-- Takes out what's older than maxAge seconds.
function ns.ChatGroups_Prune(list, now, maxAge)
	for i = #list, 1, -1 do
		if now - list[i].at > maxAge then
			table.remove(list, i)
		end
	end
end

-- [key] = dungeon, from the dungeon list.
function ns.ChatGroups_ByKey(dungeons)
	local byKey = {}
	for _, dungeon in ipairs(dungeons) do
		byKey[dungeon.key] = dungeon
	end
	return byKey
end

-- Whether a level is close enough to a dungeon's.
function ns.ChatGroups_Near(dungeon, level)
	return dungeon ~= nil and level >= dungeon.min - NEAR_LEVELS and level <= dungeon.max + NEAR_LEVELS
end

-- The entries to show. kind: "all" | "group" | "player". near: only dungeons near level; what names no dungeon stays, as its
-- level isn't known and most of it comes from your own zone's channels.
function ns.ChatGroups_View(list, kind, near, level, byKey)
	local out = {}
	for _, entry in ipairs(list) do
		if (kind == "all" or entry.kind == kind) and (not near or not entry.dungeon
			or ns.ChatGroups_Near(byKey[entry.dungeon], level)) then
			out[#out + 1] = entry
		end
	end
	return out
end

-- A row's heading: the dungeon, or a word for anything else.
function ns.ChatGroups_Title(entry, byKey)
	local dungeon = entry.dungeon and byKey[entry.dungeon]
	return ("%s: %s"):format(dungeon and dungeon.name or "Quest or other", ns.ChatGroups_RoleText(entry))
end

-- "Needs tank, healer", "Looking for a group as a healer", or the plain version when no role was named.
function ns.ChatGroups_RoleText(entry)
	local roles = {}
	if entry.tank then
		roles[#roles + 1] = "tank"
	end
	if entry.heal then
		roles[#roles + 1] = "healer"
	end
	if entry.dps then
		roles[#roles + 1] = "damage"
	end
	local list = table.concat(roles, ", ")
	if entry.kind == "player" then
		return #roles > 0 and ("Looking for a group as " .. list) or "Looking for a group"
	end
	return #roles > 0 and ("Needs " .. list) or "Needs more people"
end
