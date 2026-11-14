local addonName, ns = ...

-- Quest list: pure logic for party progress (no WoW API calls; unit-tested in tests/test_questlistparty.lua). A unit's
-- tooltip quest lines read into party members' counts, the sync message format, which party lines each quest shows,
-- and the text for "Tell party my progress". Reads, sync and the menu actions in Party.lua, drawing in List.lua.
-- See docs/superpowers/specs/2026-11-14-tomte-quest-list-party-design.md.

local VERSION = "1" -- the first character of every sync message; other versions are ignored
local MESSAGE_MAX = 255 -- bytes in one addon message, and in one chat message

-- Tooltip reads -------------------------------------------------------------------------------------------------------

-- A unit's quest lines, in tooltip order: { kind = "title", text, id } | { kind = "player", guid } |
-- { kind = "objective", text, completed }. Grouped, each quest's title is followed per party member by a player line
-- and that member's objectives; solo there are no player lines and the objectives are yours.
-- quests: your quests { { questID, title, objectives = { { label } } } } (the list's own reads).
-- Returns { [guid] = { [questID] = { [k] = { have, need, finished } } } } for everyone but myGUID, k being the index of
-- your objective with the same label. Objectives you don't have, and quests not in your log, are left out.
function ns.QuestListParty_ReadTooltip(lines, quests, myGUID)
	local byID, byTitle = {}, {}
	for _, q in ipairs(quests) do
		byID[q.questID] = q
		if q.title and not byTitle[q.title] then
			byTitle[q.title] = q
		end
	end
	local out = {}
	local quest, guid
	for _, line in ipairs(lines) do
		if line.kind == "title" then
			quest = (line.id and byID[line.id]) or (line.text and byTitle[line.text]) or nil
			guid = nil
		elseif line.kind == "player" then
			guid = line.guid
		elseif line.kind == "objective" and quest and guid and guid ~= myGUID then
			local obj = ns.QuestList_Objective({ text = line.text, finished = line.completed })
			for k, mine in ipairs(quest.objectives or {}) do
				if mine.label == obj.label then
					local member = out[guid] or {}
					out[guid] = member
					member[quest.questID] = member[quest.questID] or {}
					member[quest.questID][k] = { have = obj.have, need = obj.need,
						finished = obj.finished or (obj.need ~= nil and (obj.have or 0) >= obj.need) }
					break
				end
			end
		end
	end
	return out
end

-- Sync messages -------------------------------------------------------------------------------------------------------

-- One quest as a sync entry: "<questID>:<complete 0|1>:<have>/<need>,...". An objective without a count is 1/1 or 0/1.
-- q: { questID, complete, objectives = { { have, need, finished } } }.
function ns.QuestListParty_Entry(q)
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

function ns.QuestListParty_Hello()
	return VERSION .. "H"
end

-- Entries packed into as few messages as fit. kind "S" (a full state: the first message says so, the rest continue it)
-- or "Q" (changed quests). A full state of an empty log is still one message, so the receiver forgets the old one.
function ns.QuestListParty_Pack(kind, entries)
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
function ns.QuestListParty_PackIDs(kind, ids)
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
function ns.QuestListParty_Decode(text)
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
function ns.QuestListParty_Diff(before, after, turnedIn)
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

-- Party lines -----------------------------------------------------------------------------------------------------------

-- What the list shows about the party under one of your quests.
-- q: { objectives = { { label, have, need, finished } } } (yours).
-- members: in party order, { name, class, onQuest (true | false | nil when unknown), turnedIn (bool),
-- quest = { complete, objectives = { [k] = { have, need, finished } } } or nil }.
-- opts.missing: list who doesn't have it.
-- Returns nil when there's nothing to say, else { objectives = { [k] = { { name, class, have, need, finished } } },
-- waiting = { who } (on it, no count read yet), missing = { who }, turnedIn = { who } }, who being { name, class }.
function ns.QuestListParty_Lines(q, members, opts)
	local out = { objectives = {}, waiting = {}, missing = {}, turnedIn = {} }
	local any = false
	for _, m in ipairs(members) do
		local who = { name = m.name, class = m.class }
		if m.turnedIn then
			out.turnedIn[#out.turnedIn + 1] = who
			any = true
		elseif m.onQuest == false then
			-- Counts read before they turned it in or dropped it don't count any more.
			if opts and opts.missing then
				out.missing[#out.missing + 1] = who
				any = true
			end
		else
			local counted = false
			local data = m.quest
			for k in ipairs(q.objectives or {}) do
				local o = data and data.objectives and data.objectives[k]
				if o then
					local list = out.objectives[k] or {}
					out.objectives[k] = list
					list[#list + 1] = { name = m.name, class = m.class, have = o.have, need = o.need,
						finished = (o.finished or data.complete) and true or false }
					counted, any = true, true
				end
			end
			if not counted and m.onQuest then
				out.waiting[#out.waiting + 1] = who
				any = true
			end
		end
	end
	return any and out or nil
end

-- The party lines to draw at one of your objectives. ownDrawn: your own objective line shows (then every member's
-- count goes under it); when it doesn't (the quest is done, or finished objectives are hidden), only members who still
-- need it show, with the objective's name.
function ns.QuestListParty_At(entries, ownDrawn)
	if not entries then
		return {}
	end
	if ownDrawn then
		return entries
	end
	local list = {}
	for _, e in ipairs(entries) do
		if not e.finished then
			list[#list + 1] = e
		end
	end
	return list
end

-- A member's count at your objective: "9/15", or "done" / "not yet" where the objective has no count.
function ns.QuestListParty_CountText(entry, own)
	if own and own.need and entry.need then
		return ("%d/%d"):format(entry.have or 0, entry.need)
	end
	return entry.finished and "done" or "not yet"
end

local function Names(list, fmt)
	local names = {}
	for i, who in ipairs(list) do
		names[i] = fmt(who.name, who.class)
	end
	if #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- The faint line under a quest's objectives: "Kesha has it too · Pala doesn't have it · Mira turned it in", nil when
-- empty. fmt(name, class) dresses each name (class color in the game).
function ns.QuestListParty_Summary(lines, fmt)
	if not lines then
		return nil
	end
	fmt = fmt or function(name)
		return name
	end
	local parts = {}
	if #lines.waiting > 0 then
		parts[#parts + 1] = Names(lines.waiting, fmt) .. (#lines.waiting == 1 and " has it too" or " have it too")
	end
	if #lines.missing > 0 then
		parts[#parts + 1] = Names(lines.missing, fmt) .. (#lines.missing == 1 and " doesn't have it" or " don't have it")
	end
	if #lines.turnedIn > 0 then
		parts[#parts + 1] = Names(lines.turnedIn, fmt) .. " turned it in"
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " · ")
end

-- Chat ------------------------------------------------------------------------------------------------------------------

-- The Find group line: "LFG [link]", or "LFM [link], 2/5" with your group's size (left out solo or without a most).
-- kind: "LFG" | "LFM"; elite: an elite quest, said, since that's why a group is wanted.
function ns.QuestListParty_GroupText(kind, link, elite, size, most)
	local text = kind .. " " .. link .. (elite and " (elite)" or "")
	if kind == "LFM" and size and size > 1 and most then
		text = ("%s, %d/%d"):format(text, size, most)
	end
	return text
end

-- "Tell party my progress": the quest's link, then each objective, split over as few messages as fit.
-- objectives: yours { { label, have, need, finished } }; complete: ready to turn in.
function ns.QuestListParty_ChatLines(link, objectives, complete)
	if complete then
		return { link .. " done, ready to turn in" }
	end
	local parts = {}
	for _, o in ipairs(objectives or {}) do
		if o.need then
			parts[#parts + 1] = ns.QuestList_ObjectiveText(o)
		else
			parts[#parts + 1] = o.label .. (o.finished and " (done)" or "")
		end
	end
	local messages, current = {}, link .. ":"
	local fresh = true -- nothing after the link (or at the start of a continuation) yet
	for _, p in ipairs(parts) do
		local sep = fresh and " " or ", "
		if #current + #sep + #p > MESSAGE_MAX then
			messages[#messages + 1] = current
			current = p
		else
			current = current .. sep .. p
		end
		fresh = false
	end
	if #parts == 0 then
		current = link
	end
	messages[#messages + 1] = current
	return messages
end
