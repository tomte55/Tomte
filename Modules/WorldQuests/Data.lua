local addonName, ns = ...

-- World quests: pure logic (no WoW API calls; tested with plain Lua). Scan.lua turns the game's data into plain quest
-- records; this file filters them, picks each one's section and sort order, and writes the row and toast text.
--
-- Quest record: { id, title, zone, seconds, type ("pvp" | "petbattle" | "profession" | "dungeon" | "raid" |
--   "worldboss" | nil), elite, quality (0-2), profession, knownSkill, loaded, xp, money (copper),
--   items = { { name, icon, count, quality, itemID, link, ilvl, gear, collectible ("mount" | "pet" | "toy", only when
--   missing), appearance (true when an appearance you can collect is missing), verdict (Gear Check's) } },
--   currencies = { { id, name, icon, amount, capped } }, reps = { { name, amount, max } }, failed (gave up loading) }
-- opts: { show = { pvp, petbattle, otherProfessions }, worth = { transmog, gold, goldAmount }, collapsed, maxLevel }

local floor, ceil = math.floor, math.ceil

local COPPER_PER_GOLD = 10000
local CRITICAL_SECONDS = 15 * 60 -- WORLD_QUESTS_TIME_CRITICAL_MINUTES
local LOW_SECONDS = 75 * 60 -- WORLD_QUESTS_TIME_LOW_MINUTES
local NO_TIME = math.huge

local SECTIONS = {
	{ key = "worth", title = "Worth it" },
	{ key = "gear", title = "Gear" },
	{ key = "gold", title = "Gold" },
	{ key = "currency", title = "Currencies" },
	{ key = "rep", title = "Reputation" },
	{ key = "other", title = "Other" },
}
ns.WQ_SECTIONS = SECTIONS

local WORTH_TIER = { collectible = 4, upgrade = 3, appearance = 2, gold = 1 }
local TIER_SCALE = 1e13
local EMPTY_SLOT_PCT = 50 -- an empty slot sorts like a big upgrade
local COLLECTIBLE_WORDS = { mount = "Mount", pet = "Pet", toy = "Toy" }
local TYPE_TAGS = { dungeon = "Dungeon", raid = "Raid", worldboss = "World boss", pvp = "PvP", petbattle = "Pet battle" }
local QUALITY_TAGS = { [1] = "Rare", [2] = "Epic" }
local VERDICT_WORDS = {
	upgrade = "Upgrade", upgradeBut = "Upgrade?", sidegrade = "Sidegrade", downgrade = "Downgrade",
}
local VERDICT_FIXED = {
	empty = "Upgrade (empty slot)", notForYou = "Not for you", simIt = "Sim it", pair = "Replaces your two-hander",
}

-- Formatting -----------------------------------------------------------------------------------------------------

local function Thousands(n)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function ns.WQ_FormatGold(copper)
	local gold = floor((copper or 0) / COPPER_PER_GOLD)
	if gold < 1 then
		return "<1g"
	end
	return Thousands(gold) .. "g"
end

-- text, tier ("critical" | "low" | "normal"), or nil when the game gives no time.
function ns.WQ_TimeText(seconds)
	if not seconds or seconds <= 0 then
		return nil
	end
	local tier = seconds <= CRITICAL_SECONDS and "critical" or seconds <= LOW_SECONDS and "low" or "normal"
	local text
	if seconds < 3600 then
		text = ("%dm"):format(math.max(1, ceil(seconds / 60)))
	elseif seconds < 86400 then
		local h, m = floor(seconds / 3600), floor(seconds % 3600 / 60)
		text = m > 0 and ("%dh %dm"):format(h, m) or ("%dh"):format(h)
	else
		text = ("%dd %dh"):format(floor(seconds / 86400), floor(seconds % 86400 / 3600))
	end
	return text, tier
end

-- Rewards --------------------------------------------------------------------------------------------------------

local function Find(items, test)
	for _, item in ipairs(items or {}) do
		if test(item) then
			return item
		end
	end
	return nil
end

local function IsCollectible(item)
	return item.collectible ~= nil
end

local function IsGear(item)
	return item.gear == true
end

local function IsAppearance(item)
	return item.appearance == true
end

local function IsCleanUpgrade(item)
	return item.gear == true and ns.Gear_IsCleanUpgrade(item.verdict)
end

-- The first currency that isn't capped, else the first.
local function MainCurrency(q)
	local first = q.currencies and q.currencies[1]
	for _, c in ipairs(q.currencies or {}) do
		if not c.capped then
			return c
		end
	end
	return first
end

local function RepTotal(q)
	local total, allMax = 0, #(q.reps or {}) > 0
	for _, r in ipairs(q.reps or {}) do
		total = total + (r.amount or 0)
		allMax = allMax and r.max == true
	end
	return total, allMax
end

local function HasReward(q)
	return (q.money or 0) > 0 or #(q.items or {}) > 0 or #(q.currencies or {}) > 0 or #(q.reps or {}) > 0
end

-- kind ("collectible" | "appearance" | "gear" | "item" | "currency" | "gold" | "rep" | "xp" | "none"), the reward.
local function MainReward(q)
	local collectible = Find(q.items, IsCollectible)
	if collectible then
		return "collectible", collectible
	end
	if q.reason == "appearance" then
		return "appearance", Find(q.items, IsAppearance)
	end
	if q.reason == "gold" then
		return "gold"
	end
	if q.reason == "upgrade" then
		return "gear", Find(q.items, IsCleanUpgrade)
	end
	local gear = Find(q.items, IsGear)
	if gear then
		return "gear", gear
	end
	if q.items and q.items[1] then
		return "item", q.items[1]
	end
	local currency = MainCurrency(q)
	if currency then
		return "currency", currency
	end
	if (q.money or 0) > 0 then
		return "gold"
	end
	if q.reps and q.reps[1] then
		return "rep", q.reps[1]
	end
	if (q.xp or 0) > 0 then
		return "xp"
	end
	return "none"
end

-- kind, reward for the row's icon and text: MainReward's kinds, or "loading" before the rewards are in.
function ns.WQ_MainReward(q)
	if not q.loaded then
		return "loading"
	end
	return MainReward(q)
end

-- Filtering and classification ---------------------------------------------------------------------------------

function ns.WQ_Filter(q, opts)
	local show = opts.show or {}
	if q.type == "pvp" and not show.pvp then
		return false
	elseif q.type == "petbattle" and not show.petbattle then
		return false
	elseif q.type == "profession" and q.knownSkill == false and not show.otherProfessions then
		return false
	end
	if opts.maxLevel and q.loaded and not HasReward(q) and (q.xp or 0) > 0 then
		return false
	end
	return true
end

local function WorthReason(q, opts)
	if Find(q.items, IsCollectible) then
		return "collectible"
	end
	if Find(q.items, IsCleanUpgrade) then
		return "upgrade"
	end
	local worth = opts.worth or {}
	if worth.transmog and Find(q.items, IsAppearance) then
		return "appearance"
	end
	if worth.gold and (q.money or 0) >= (worth.goldAmount or 0) * COPPER_PER_GOLD and (q.money or 0) > 0 then
		return "gold"
	end
	return nil
end

local function GearRank(item)
	local v = item.verdict
	if v and v.pct then
		return 2e9 + v.pct * 1000
	elseif v then
		return 1e9 + (item.ilvl or 0)
	end
	return item.ilvl or 0
end

local SECTION_OF = { gear = "gear", item = "other", currency = "currency", gold = "gold", rep = "rep" }

-- section, sortKey { dim, group, rank }, reason (Worth it only). Also sets q.section, q.reason, q.dim.
function ns.WQ_Classify(q, opts)
	local section, reason, rank, group, dim = "other", nil, 0, "", false
	if q.loaded then
		reason = WorthReason(q, opts)
	end
	q.reason = reason
	if reason then
		section = "worth"
		local value = 0
		if reason == "upgrade" then
			local item = Find(q.items, IsCleanUpgrade)
			value = (item.verdict.pct or EMPTY_SLOT_PCT) * 1000
		elseif reason == "gold" then
			value = q.money or 0
		end
		rank = WORTH_TIER[reason] * TIER_SCALE + value
	elseif q.loaded then
		local kind, reward = MainReward(q)
		section = SECTION_OF[kind] or "other"
		if kind == "gear" then
			rank = GearRank(reward)
			dim = reward.verdict ~= nil and reward.verdict.kind == "notForYou"
		elseif kind == "currency" then
			group, rank, dim = reward.name or "", reward.amount or 0, reward.capped == true
		elseif kind == "gold" then
			rank = q.money or 0
		elseif kind == "rep" then
			rank, dim = RepTotal(q)
		end
	end
	q.section, q.dim = section, dim
	return section, { dim = dim, group = group, rank = rank }, reason
end

local function Less(a, b)
	local ka, kb = a.sortKey, b.sortKey
	if ka.dim ~= kb.dim then
		return not ka.dim
	end
	if ka.group ~= kb.group then
		return ka.group < kb.group
	end
	if ka.rank ~= kb.rank then
		return ka.rank > kb.rank
	end
	local sa, sb = a.seconds or NO_TIME, b.seconds or NO_TIME
	if sa <= 0 then
		sa = NO_TIME
	end
	if sb <= 0 then
		sb = NO_TIME
	end
	if sa ~= sb then
		return sa < sb
	end
	if (a.title or "") ~= (b.title or "") then
		return (a.title or "") < (b.title or "")
	end
	return (a.id or 0) < (b.id or 0)
end

-- { { key, title, quests, collapsed } } in the fixed order, without empty sections. Filtered quests are left out.
function ns.WQ_Sections(quests, opts)
	local bySection = {}
	for _, q in ipairs(quests) do
		if ns.WQ_Filter(q, opts) then
			local section, key = ns.WQ_Classify(q, opts)
			q.sortKey = key
			bySection[section] = bySection[section] or {}
			table.insert(bySection[section], q)
		end
	end
	local collapsed = opts.collapsed or {}
	local sections = {}
	for _, def in ipairs(SECTIONS) do
		local list = bySection[def.key]
		if list then
			table.sort(list, Less)
			sections[#sections + 1] = { key = def.key, title = def.title, quests = list, collapsed = collapsed[def.key] == true }
		end
	end
	return sections
end

-- Text -----------------------------------------------------------------------------------------------------------

local function VerdictText(v)
	if not v then
		return nil
	end
	if VERDICT_FIXED[v.kind] then
		return VERDICT_FIXED[v.kind]
	end
	local word = VERDICT_WORDS[v.kind]
	if not word then
		return nil
	end
	return v.pct and ("%s %+.1f%%"):format(word, v.pct) or word
end

local function ItemText(item)
	if (item.count or 1) > 1 then
		return ("%d %s"):format(item.count, item.name or "?")
	end
	return item.name or "?"
end

local function GearText(item)
	local parts = {}
	if item.ilvl then
		parts[#parts + 1] = "ilvl " .. item.ilvl
	end
	parts[#parts + 1] = VerdictText(item.verdict)
	if #parts == 0 then
		parts[1] = item.name or "?"
	end
	return table.concat(parts, " · ")
end

local function CurrencyText(c)
	return ("%d %s"):format(c.amount or 0, c.name or "?") .. (c.capped and " (capped)" or "")
end

local function RepText(r)
	return ("+%d %s"):format(r.amount or 0, r.name or "?") .. (r.max and " (max renown)" or "")
end

-- main, secondary (nil when there's nothing else). Uses q.reason from WQ_Classify when it ran.
function ns.WQ_RewardText(q)
	if not q.loaded then
		return q.failed and "rewards unknown" or "loading…"
	end
	local kind, reward = MainReward(q)
	local main
	if kind == "collectible" then
		main = COLLECTIBLE_WORDS[reward.collectible] .. ": " .. (reward.name or "?")
	elseif kind == "appearance" then
		main = "Appearance: " .. (reward.name or "?")
	elseif kind == "gear" then
		main = GearText(reward)
	elseif kind == "item" then
		main = ItemText(reward)
	elseif kind == "currency" then
		main = CurrencyText(reward)
	elseif kind == "gold" then
		main = ns.WQ_FormatGold(q.money)
	elseif kind == "rep" then
		main = RepText(reward)
	elseif kind == "xp" then
		main = "Experience"
	else
		main = "No reward"
	end
	local rest = {}
	for _, c in ipairs(q.currencies or {}) do
		if c ~= reward then
			rest[#rest + 1] = CurrencyText(c)
		end
	end
	if kind ~= "gold" and (q.money or 0) > 0 then
		rest[#rest + 1] = ns.WQ_FormatGold(q.money)
	end
	for _, r in ipairs(q.reps or {}) do
		if r ~= reward then
			rest[#rest + 1] = RepText(r)
		end
	end
	return main, #rest > 0 and table.concat(rest, " · ") or nil
end

-- The item the row is about (for its tooltip and model), nil when the main reward isn't an item.
function ns.WQ_MainItem(q)
	if not q.loaded then
		return nil
	end
	local kind, reward = MainReward(q)
	if kind == "collectible" or kind == "appearance" or kind == "gear" or kind == "item" then
		return reward
	end
	return nil
end

function ns.WQ_Tags(q)
	local tags = {}
	if q.elite then
		tags[#tags + 1] = "Elite"
	end
	if q.type == "profession" then
		tags[#tags + 1] = q.profession or "Profession"
	elseif TYPE_TAGS[q.type] then
		tags[#tags + 1] = TYPE_TAGS[q.type]
	end
	if QUALITY_TAGS[q.quality] then
		tags[#tags + 1] = QUALITY_TAGS[q.quality]
	end
	return table.concat(tags, " · ")
end

-- list: { { title, what } }, the quests worth doing in a zone.
function ns.WQ_ToastText(zoneName, list)
	local first = list[1]
	if #list == 1 then
		return zoneName, ("%s rewards %s.\nClick for the list."):format(first.title, first.what)
	end
	return zoneName, ("%d world quests worth doing, like %s (%s).\nClick for the list."):format(#list, first.title, first.what)
end
