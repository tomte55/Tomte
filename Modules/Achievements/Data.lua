local addonName, ns = ...

-- Almost Done, pure logic: no WoW API calls (unit-tested with plain Lua). Percent from criteria, milestones,
-- filters, sorting, the tracker's top N, reward type from text and expansion from category names.

-- Newest first: "Classic" is last so "Wrath of the Lich King Classic"-style names still match their expansion.
ns.ACH_EXPANSIONS = {
	"Midnight", "The War Within", "Dragonflight", "Shadowlands", "Battle for Azeroth", "Legion",
	"Warlords of Draenor", "Mists of Pandaria", "Cataclysm", "Wrath of the Lich King", "The Burning Crusade",
	"Classic",
}
ns.ACH_OTHER = "Other"

-- criteria: list of { name, completed, quantity, required }. Every criterion counts equally: a completed one 1,
-- an incomplete one quantity / required. Returns percent (0-100), done, total, the name of the one left (when
-- exactly one is left and it has a name), and the count to show: have, need. That's done/total, except for a single
-- counted criterion ("Complete 200 World Quests"), where it's its quantity/required. nil when there are no criteria.
function ns.Ach_Percent(criteria)
	if not criteria or #criteria == 0 then
		return nil
	end
	local sum, done, last, left = 0, 0, nil, 0
	for _, c in ipairs(criteria) do
		if c.completed then
			sum = sum + 1
			done = done + 1
		else
			left = left + 1
			last = c.name
			local required = c.required or 0
			if required > 0 then
				sum = sum + math.min((c.quantity or 0) / required, 1)
			end
		end
	end
	local have, need = done, #criteria
	local only = criteria[1]
	if #criteria == 1 and (only.required or 0) > 1 then
		need = only.required
		have = only.completed and need or math.min(only.quantity or 0, need)
	end
	return sum / #criteria * 100, done, #criteria, left == 1 and last ~= "" and last or nil, have, need
end

-- "99%  -  198/200" for a record carrying percent, have and need (falling back to done and total).
function ns.Ach_ProgressText(record, sep)
	return ("%d%%%s%d/%d"):format(math.floor(record.percent), sep or "  -  ", record.have or record.done,
		record.need or record.total)
end

-- The strongest milestone between two states ({ percent, done, total }) of one achievement, or nil.
-- fired: kinds already shown for it this session (almost and lastStep show once; pinned on every step).
function ns.Ach_Milestone(before, after, threshold, pinned, fired)
	if not before then
		return nil
	end
	local beforeLeft, afterLeft = before.total - before.done, after.total - after.done
	if after.total >= 2 and beforeLeft >= 2 and afterLeft == 1 and not fired.lastStep then
		return "lastStep"
	end
	if before.percent < threshold and after.percent >= threshold and not fired.almost then
		return "almost"
	end
	if pinned and (after.done > before.done or after.percent > before.percent) then
		return "pinned"
	end
	return nil
end

-- "title" for title rewards, "other" for any other reward text, nil for none. Item rewards are typed from the
-- item itself (Rewards.lua); this is the fallback.
function ns.Ach_RewardTypeFromText(text)
	if not text or text == "" then
		return nil
	end
	if text:find("^Title") then
		return "title"
	end
	return "other"
end

-- names: a category and its ancestors, nearest first. The first expansion name found in any of them.
function ns.Ach_ExpansionFromChain(names)
	for _, name in ipairs(names) do
		for _, expansion in ipairs(ns.ACH_EXPANSIONS) do
			if name:find(expansion, 1, true) then
				return expansion
			end
		end
	end
	return nil
end

local function Contains(haystack, needle)
	return haystack ~= nil and haystack:lower():find(needle, 1, true) ~= nil
end

local function MatchesSearch(record, text)
	if text == "" then
		return true
	end
	if Contains(record.name, text) or Contains(record.reward, text) then
		return true
	end
	for _, name in ipairs(record.critNames or {}) do
		if Contains(name, text) then
			return true
		end
	end
	return false
end

-- A professions achievement is "mine" when its category, name or a criterion names one of my professions.
local function IsMyProfession(record, professions)
	for _, profession in ipairs(professions) do
		local p = profession:lower()
		if Contains(record.catName, p) or Contains(record.name, p) then
			return true
		end
		for _, name in ipairs(record.critNames or {}) do
			if Contains(name, p) then
				return true
			end
		end
	end
	return false
end

-- holidays: lower-case titles of the calendar's holidays around today.
local function IsRunningEvent(record, holidays)
	local name = (record.catName or ""):lower()
	if name == "" then
		return false
	end
	for _, title in ipairs(holidays) do
		if title:find(name, 1, true) then
			return true
		end
	end
	return false
end

local function RewardPasses(record, filter, rewardInfo)
	if filter == "any" then
		return true
	end
	local info = rewardInfo(record)
	local rewardType = info and info.type or ns.Ach_RewardTypeFromText(record.reward)
	if not rewardType then
		return false
	end
	if filter == "reward" then
		return true
	elseif filter == "new" then
		return not (info and info.owned)
	end
	return rewardType == filter
end

-- settings: the module's saved settings. ctx: { pinned, ignored, professions, holidays, searchText (lower case),
-- rewardInfo(record) -> { type, owned } | nil }. Pinned records skip every filter except search.
function ns.Ach_Passes(record, settings, ctx)
	if not MatchesSearch(record, ctx.searchText or "") then
		return false
	end
	if ctx.pinned[record.id] then
		return true
	end
	if ctx.ignored[record.id] and not settings.showIgnored then
		return false
	end
	if settings.categories[record.top or ns.ACH_OTHER] == false then
		return false
	end
	if settings.expansions[record.expansion or ns.ACH_OTHER] == false then
		return false
	end
	if record.top == "Professions" then
		if settings.professions == "none" then
			return false
		elseif settings.professions == "mine" and not IsMyProfession(record, ctx.professions) then
			return false
		end
	elseif record.top == "World Events" then
		if settings.events == "none" then
			return false
		elseif settings.events == "running" and not IsRunningEvent(record, ctx.holidays) then
			return false
		end
	end
	-- Threshold first: the reward lookup asks several journals, and most records are below it.
	if record.percent < settings.threshold then
		return false
	end
	return RewardPasses(record, settings.reward, ctx.rewardInfo)
end

local function ByName(a, b)
	if a.name ~= b.name then
		return a.name < b.name
	end
	return a.id < b.id
end

local function ByPercent(a, b)
	if a.percent ~= b.percent then
		return a.percent > b.percent
	end
	return ByName(a, b)
end

local SORTS = {
	percent = ByPercent,
	name = ByName,
	points = function(a, b)
		if (a.points or 0) ~= (b.points or 0) then
			return (a.points or 0) > (b.points or 0)
		end
		return ByPercent(a, b)
	end,
	steps = function(a, b)
		local la, lb = a.total - a.done, b.total - b.done
		if la ~= lb then
			return la < lb
		end
		return ByPercent(a, b)
	end,
}

function ns.Ach_Sort(list, mode)
	table.sort(list, SORTS[mode] or ByPercent)
end

-- The tracker's rows: pins (in pin order, if they have a record) flagged .pinned, then list (already filtered and
-- sorted) up to n. Returns new tables, so the flag doesn't stick to the records.
function ns.Ach_TopN(list, pins, byID, n)
	local out, used = {}, {}
	local function Add(record, pinned)
		local row = setmetatable({ pinned = pinned or nil }, { __index = record })
		out[#out + 1] = row
		used[record.id] = true
	end
	for _, id in ipairs(pins) do
		if #out >= n then
			break
		end
		local record = byID[id]
		if record and not used[id] then
			Add(record, true)
		end
	end
	for _, record in ipairs(list) do
		if #out >= n then
			break
		end
		if not used[record.id] then
			Add(record)
		end
	end
	return out
end

-- children: { completed, percent }. A completed child counts 1, an incomplete one its percent.
function ns.Ach_MetaPercent(children)
	if #children == 0 then
		return 0, 0, 0
	end
	local sum, done = 0, 0
	for _, c in ipairs(children) do
		if c.completed then
			sum = sum + 1
			done = done + 1
		else
			sum = sum + (c.percent or 0) / 100
		end
	end
	return sum / #children * 100, done, #children
end
