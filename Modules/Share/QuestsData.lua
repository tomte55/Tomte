local addonName, ns = ...

-- Friend sharing, quest progress (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in
-- tests/test_sharequests.lua). The format of the hidden party messages that carry quest progress between party members
-- who run Tomte. Sending and receiving in Quests.lua; the Quest list shows what comes in (Modules/QuestList/Party.lua).
-- See docs/superpowers/specs/2026-11-14-tomte-quest-list-party-design.md.

local VERSION = "1" -- the first character of every message; other versions are ignored
local MESSAGE_MAX = 255 -- bytes in one addon message

-- One quest as an entry: "<questID>:<complete 0|1>:<have>/<need>,...". An objective without a count is 1/1 or 0/1.
-- q: { questID, complete, objectives = { { have, need, finished } } }.
function ns.ShareQuests_Entry(q)
	local parts = {}
	for k, o in ipairs(q.objectives or {}) do
		if o.need then
			parts[k] = ("%d/%d"):format(o.have or 0, o.need)
		else
			parts[k] = o.finished and "1/1" or "0/1"
		end
	end
	return ("%d:%d:%s"):format(q.questID, q.complete and 1 or 0, table.concat(parts, ","))
end

function ns.ShareQuests_Hello()
	return VERSION .. "H"
end

-- Entries packed into as few messages as fit. kind "S" (a full state: the first message says so, the rest continue it)
-- or "Q" (changed quests). A full state of an empty log is still one message, so the receiver forgets the old one.
function ns.ShareQuests_Pack(kind, entries)
	local messages, current = {}, nil
	for _, e in ipairs(entries) do
		if current and #current + 1 + #e <= MESSAGE_MAX then
			current = current .. "|" .. e
		else
			if current then
				messages[#messages + 1] = current
			end
			current = VERSION .. (#messages == 0 and kind or "Q") .. e
		end
	end
	if current then
		messages[#messages + 1] = current
	elseif kind == "S" then
		messages[1] = VERSION .. "S"
	end
	return messages
end

-- Quest IDs as messages: kind "G" (gone from the log) or "T" (turned in).
function ns.ShareQuests_PackIDs(kind, ids)
	local messages, current = {}, nil
	for _, id in ipairs(ids) do
		local s = tostring(id)
		if current and #current + 1 + #s <= MESSAGE_MAX then
			current = current .. "," .. s
		else
			if current then
				messages[#messages + 1] = current
			end
			current = VERSION .. kind .. s
		end
	end
	messages[#messages + 1] = current
	return messages
end

-- A received message: { kind = "hello" } | { kind = "full" | "update", quests = { { questID, complete,
-- objectives = { { have, need, finished } } } } } | { kind = "gone" | "turnedIn", ids = { questID } }, or nil for
-- anything else (another version, garbage).
function ns.ShareQuests_Decode(text)
	if type(text) ~= "string" or text:sub(1, 1) ~= VERSION then
		return nil
	end
	local kind, body = text:sub(2, 2), text:sub(3)
	if kind == "H" then
		return { kind = "hello" }
	elseif kind == "S" or kind == "Q" then
		local quests = {}
		for e in body:gmatch("[^|]+") do
			local id, c, objs = e:match("^(%d+):([01]):(.*)$")
			if id then
				local q = { questID = tonumber(id), complete = c == "1", objectives = {} }
				for h, n in objs:gmatch("(%d+)/(%d+)") do
					h, n = tonumber(h), tonumber(n)
					q.objectives[#q.objectives + 1] = { have = h, need = n, finished = h >= n }
				end
				quests[#quests + 1] = q
			end
		end
		return { kind = kind == "S" and "full" or "update", quests = quests }
	elseif kind == "G" or kind == "T" then
		local ids = {}
		for id in body:gmatch("%d+") do
			ids[#ids + 1] = tonumber(id)
		end
		return { kind = kind == "G" and "gone" or "turnedIn", ids = ids }
	end
	return nil
end

-- What to send after the log changed. before, after: { [questID] = entry } (the last sent, and now); turnedIn:
-- { [questID] = true } for quests just handed in. Returns changed entries, gone IDs and turned-in IDs, by quest ID.
function ns.ShareQuests_Diff(before, after, turnedIn)
	local changed, gone, turned = {}, {}, {}
	local ids = {}
	for id, e in pairs(after) do
		if before[id] ~= e then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	for i, id in ipairs(ids) do
		changed[i] = after[id]
	end
	for id in pairs(before) do
		if after[id] == nil then
			if turnedIn and turnedIn[id] then
				turned[#turned + 1] = id
			else
				gone[#gone + 1] = id
			end
		end
	end
	table.sort(gone)
	table.sort(turned)
	return changed, gone, turned
end
