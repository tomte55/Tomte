local addonName, ns = ...

-- Session recap, pure logic: no WoW API calls (unit-tested with plain Lua).
-- Log entry = { kind, at, title, icon, quality, tier, itemID, link, detail, factionID, from, to, guid }
-- kinds: loot, upgrade, mount, pet, toy, achievement, rare, tame, renown.

local DEDUPE_WINDOW = 120 -- seconds: a loot note and an upgrade note of the same item are one find
local MIN_WORTH_TIME = 600
local MIN_WORTH_MONEY = 10000 -- 1 gold
local QUALITY_EPIC, QUALITY_LEGENDARY = 4, 5

ns.RECAP_SOURCES = { "loot", "vendor", "mail", "auction" } -- in display order for ties; "other" is the rest
ns.RECAP_SOURCE_NAMES = { loot = "loot", vendor = "vendor", mail = "mail", auction = "auction house", other = "other" }

local function Find(log, match)
	for i, e in ipairs(log) do
		if match(e) then
			return i, e
		end
	end
	return nil
end

local function SameItem(a, b)
	return a.itemID ~= nil and a.itemID == b.itemID and math.abs((a.at or 0) - (b.at or 0)) <= DEDUPE_WINDOW
end

-- Adds an entry to the log; false when it was folded into (or already covered by) an existing one.
function ns.Recap_AddNote(log, entry, max)
	if entry.kind == "renown" and entry.factionID then
		local _, e = Find(log, function(e)
			return e.kind == "renown" and e.factionID == entry.factionID
		end)
		if e then
			e.to = math.max(e.to or 0, entry.to or 0)
			e.at = entry.at
			return false
		end
	elseif entry.kind == "rare" and entry.guid then
		if Find(log, function(e)
			return e.kind == "rare" and e.guid == entry.guid
		end) then
			return false
		end
	elseif entry.kind == "loot" then
		if Find(log, function(e)
			return e.kind == "upgrade" and SameItem(e, entry)
		end) then
			return false
		end
	elseif entry.kind == "upgrade" then
		local i = Find(log, function(e)
			return e.kind == "loot" and SameItem(e, entry)
		end)
		if i then
			log[i] = entry
			return true
		end
	end
	log[#log + 1] = entry
	while #log > max do
		table.remove(log, 1)
		log.dropped = (log.dropped or 0) + 1
	end
	return true
end

---------------------------------------------------------------------------------------------------------------
-- Gold

-- Which source a money change belongs to, from what's open (ctx = { loot, auction, mail, vendor }).
function ns.Recap_MoneySource(ctx)
	if ctx.loot then
		return "loot"
	elseif ctx.auction then
		return "auction"
	elseif ctx.mail then
		return "mail"
	elseif ctx.vendor then
		return "vendor"
	end
	return nil
end

function ns.Recap_GoldAttribute(gold, delta, source)
	if not source or delta == 0 then
		return
	end
	local side = delta > 0 and gold["in"] or gold.out
	side[source] = (side[source] or 0) + math.abs(delta)
end

-- Net per source, largest first; "other" is whatever the sources don't explain (so the parts add up to net).
function ns.Recap_GoldSources(gold, net)
	local list, attributed = {}, 0
	for order, source in ipairs(ns.RECAP_SOURCES) do
		local amount = (gold["in"][source] or 0) - (gold.out[source] or 0)
		attributed = attributed + amount
		if amount ~= 0 then
			list[#list + 1] = { source = source, amount = amount, order = order }
		end
	end
	local other = net - attributed
	if other ~= 0 then
		list[#list + 1] = { source = "other", amount = other, order = #ns.RECAP_SOURCES + 1 }
	end
	table.sort(list, function(a, b)
		if math.abs(a.amount) ~= math.abs(b.amount) then
			return math.abs(a.amount) > math.abs(b.amount)
		end
		return a.order < b.order
	end)
	return list
end

---------------------------------------------------------------------------------------------------------------
-- Summary

function ns.Recap_Duration(seconds)
	seconds = math.max(math.floor(seconds or 0), 0)
	if seconds < 60 then
		return "<1m"
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return ("%dh %dm"):format(h, m)
	end
	return ("%dm"):format(m)
end

function ns.Recap_Counts(log)
	local counts = { items = 0, renownLevels = 0 }
	for _, e in ipairs(log) do
		counts[e.kind] = (counts[e.kind] or 0) + 1
		if e.kind == "loot" or e.kind == "upgrade" then
			counts.items = counts.items + 1
		elseif e.kind == "renown" then
			counts.renownLevels = counts.renownLevels + math.max((e.to or 0) - (e.from or 0), 0)
		end
	end
	return counts
end

local COUNT_WORDS = {
	{ "achievement", "achievement" }, { "rare", "rare" }, { "tame", "tame" }, { "mount", "mount" },
	{ "pet", "pet" }, { "toy", "toy" }, { "items", "item" },
}

function ns.Recap_CountsLine(counts)
	local parts = {}
	for _, w in ipairs(COUNT_WORDS) do
		local n = counts[w[1]] or 0
		if n > 0 then
			parts[#parts + 1] = ("%d %s%s"):format(n, w[2], n == 1 and "" or "s")
		end
	end
	if counts.renownLevels > 0 then
		parts[#parts + 1] = ("+%d renown"):format(counts.renownLevels)
	end
	return table.concat(parts, " · ")
end

-- summary = { duration, net, counts }; money(copper) formats an amount.
function ns.Recap_SummaryLine(summary, money)
	local parts = { ns.Recap_Duration(summary.duration) }
	if summary.net ~= 0 then
		parts[#parts + 1] = (summary.net > 0 and "+" or "-") .. money(math.abs(summary.net))
	end
	local counts = ns.Recap_CountsLine(summary.counts)
	if counts ~= "" then
		parts[#parts + 1] = counts
	end
	return table.concat(parts, " · ")
end

-- Worth a login toast: summary = { duration, net, entries, xp }.
function ns.Recap_Worth(summary)
	if (summary.duration or 0) < MIN_WORTH_TIME then
		return false
	end
	return (summary.entries or 0) > 0 or math.abs(summary.net or 0) >= MIN_WORTH_MONEY or summary.xp == true
end

local function IsItem(e)
	return e.kind == "loot" or e.kind == "upgrade"
end

local function Rank(e)
	local q = e.quality or 0
	if IsItem(e) and q >= QUALITY_LEGENDARY then
		return 1
	elseif e.kind == "mount" then
		return 2
	elseif e.kind == "upgrade" or (IsItem(e) and q >= QUALITY_EPIC) then
		return 3
	elseif e.kind == "achievement" then
		return 4
	elseif e.kind == "rare" then
		return 5
	elseif e.kind == "tame" then
		return 6
	elseif e.kind == "pet" then
		return 7
	elseif e.kind == "toy" then
		return 8
	elseif e.kind == "renown" then
		return 9
	end
	return 10
end

-- The best n entries and how many others there are (dropped ones included).
function ns.Recap_Highlights(log, n)
	local sorted = {}
	for i, e in ipairs(log) do
		sorted[i] = { e = e, rank = Rank(e), i = i }
	end
	table.sort(sorted, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		if (a.e.at or 0) ~= (b.e.at or 0) then
			return (a.e.at or 0) > (b.e.at or 0)
		end
		return a.i > b.i
	end)
	local shown = {}
	for i = 1, math.min(n, #sorted) do
		shown[i] = sorted[i].e
	end
	return shown, (#sorted - #shown) + (log.dropped or 0)
end

local KIND_LABELS = {
	upgrade = "Upgrade", mount = "New mount", pet = "New battle pet", toy = "New toy", achievement = "Achievement",
	rare = "Rare killed", tame = "Tamed",
}
local QUALITY_LABELS = { [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom" }

function ns.Recap_RowLabel(e)
	if e.kind == "loot" then
		return QUALITY_LABELS[e.quality or 0] or "Loot"
	elseif e.kind == "renown" then
		return ("Renown %d (+%d)"):format(e.to or 0, math.max((e.to or 0) - (e.from or 0), 0))
	end
	return KIND_LABELS[e.kind] or e.kind
end

---------------------------------------------------------------------------------------------------------------
-- Detection helpers

function ns.Recap_IsRareVignette(atlas, guid)
	if type(atlas) ~= "string" or type(guid) ~= "string" then
		return false
	end
	return atlas:find("^VignetteKill") ~= nil and (guid:find("^Creature%-") ~= nil or guid:find("^Vehicle%-") ~= nil)
end

-- Patterns for the "you receive" loot messages (LOOT_ITEM_SELF etc.); nil formats are skipped. The ones with
-- a count (*_MULTIPLE) go first: the single-item pattern would also match a stack and lose its count.
function ns.Recap_LootPatterns(formats)
	local counted, single = {}, {}
	for i = 1, #formats do
		local fmt = formats[i]
		if type(fmt) == "string" then
			local list = (fmt:find("%%d") or fmt:find("%%%d+%$d")) and counted or single
			list[#list + 1] = ns.Moments_FormatToPattern(fmt)
		end
	end
	for _, pattern in ipairs(single) do
		counted[#counted + 1] = pattern
	end
	return counted
end

-- The item link in a loot message about yourself and how many (1 unless the message says), or nil.
function ns.Recap_LootLink(text, patterns)
	if type(text) ~= "string" then
		return nil
	end
	for _, pattern in ipairs(patterns) do
		local captures = { text:match(pattern) }
		for _, capture in ipairs(captures) do
			local link, rest = capture:match("(|c[^|]*|Hitem:.-|h|r)(.*)$")
			if link then
				local count
				for _, other in ipairs(captures) do
					if other:match("^%d+$") then
						count = tonumber(other)
					end
				end
				count = count or tonumber(rest:match("^%s*x(%d+)") or "") or 1
				return link, count
			end
		end
	end
	return nil
end

function ns.Recap_ItemID(link)
	local id = type(link) == "string" and link:match("|Hitem:(%d+)")
	return id and tonumber(id) or nil
end
