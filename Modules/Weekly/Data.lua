local addonName, ns = ...

-- Weekly board: pure logic (no WoW API calls; tested with plain Lua). A snapshot is one character's data as last
-- read (Collect.lua). Weekly_View applies the weekly reset and the Concentration recharge to it for "now"; the model
-- builders turn views into the rows the page and popup draw. Only `date` is used (tests point it at os.date).
--
-- Row items: { kind = "header" | "banner" | "row", left, right, state = "done" | "open" | "warn" | "dim" | "gold",
--   frac (0-1, draws a bar), indent, note (grey, after left), dimLeft (left in grey whatever the state) }
-- A header has text, and may have right/state too.

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

ns.WEEKLY_TRACKS = {
	{ key = "raid", enum = "Raid", type = 3, label = "Raid" }, -- Enum.WeeklyRewardChestThresholdType[enum], else type
	{ key = "dungeons", enum = "Activities", type = 1, label = "Dungeons" },
	{ key = "world", enum = "World", type = 6, label = "World" },
}

-- Season 2 Mistcrests, lowest first. Adventurer and Hero are wiki-verified; Veteran, Champion and Myth come from
-- Wowhead (one source says Myth is 3441). /tomte weekly ids checks them in game.
ns.WEEKLY_CRESTS = { 3442, 3443, 3444, 3445, 3446 }

-- Per expansion (Enum.ExpansionLevel: 10 The War Within, 11 Midnight): base skill line (GetProfessionInfo) -> that
-- expansion's skill line, its weekly knowledge quests and what each is worth. trainerPts / treasurePts (each) /
-- bigPts are knowledge points (drops and treatises give 1). at = { x, y, who } for a trainer quest that isn't from
-- the Artisan's Consortium. Third-party data (WeeklyKnowledge, checked 2026-10-04); /tomte weekly ids shows the
-- quest IDs in game.
ns.WEEKLY_PROFS = {
	[10] = {
		[171] = { name = "Alchemy", child = 2871, trainer = { 84133 }, trainerPts = 2, treatise = 83725,
			treasures = { 83253, 83255 }, treasurePts = 2 },
		[164] = { name = "Blacksmithing", child = 2872, trainer = { 84127 }, trainerPts = 2, treatise = 83726,
			treasures = { 83256, 83257 }, treasurePts = 1 },
		[333] = { name = "Enchanting", child = 2874, trainer = { 84084, 84085, 84086 }, trainerPts = 3,
			at = { 52.8, 71.2, "your Enchanting trainer" }, treatise = 83727, treasures = { 83258, 83259 }, treasurePts = 1,
			drops = { 84290, 84291, 84292, 84293, 84294 }, bigDrop = 84295, bigPts = 4, from = "disenchanting" },
		[202] = { name = "Engineering", child = 2875, trainer = { 84128 }, trainerPts = 1, treatise = 83728,
			treasures = { 83260, 83261 }, treasurePts = 1 },
		[182] = { name = "Herbalism", child = 2877, gathering = true, trainer = { 82916, 82958, 82962, 82965, 82970 },
			trainerPts = 3, at = { 44.8, 69.4, "your Herbalism trainer" }, treatise = 83729,
			drops = { 81416, 81417, 81418, 81419, 81420 }, bigDrop = 81421, bigPts = 4, from = "picking herbs" },
		[773] = { name = "Inscription", child = 2878, trainer = { 84129 }, trainerPts = 2, treatise = 83730,
			treasures = { 83262, 83264 }, treasurePts = 2 },
		[755] = { name = "Jewelcrafting", child = 2879, trainer = { 84130 }, trainerPts = 2, treatise = 83731,
			treasures = { 83265, 83266 }, treasurePts = 2 },
		[165] = { name = "Leatherworking", child = 2880, trainer = { 84131 }, trainerPts = 2, treatise = 83732,
			treasures = { 83267, 83268 }, treasurePts = 1 },
		[186] = { name = "Mining", child = 2881, gathering = true, trainer = { 83102, 83103, 83104, 83105, 83106 },
			trainerPts = 3, at = { 52.6, 52.6, "your Mining trainer" }, treatise = 83733,
			drops = { 83050, 83051, 83052, 83053, 83054 }, bigDrop = 83049, bigPts = 3, from = "mining" },
		[393] = { name = "Skinning", child = 2882, gathering = true, trainer = { 82992, 82993, 83097, 83098, 83100 },
			trainerPts = 3, at = { 54.4, 57.6, "your Skinning trainer" }, treatise = 83734,
			drops = { 81459, 81460, 81461, 81462, 81463 }, bigDrop = 81464, bigPts = 2, from = "skinning" },
		[197] = { name = "Tailoring", child = 2883, trainer = { 84132 }, trainerPts = 2, treatise = 83735,
			treasures = { 83269, 83270 }, treasurePts = 1 },
	},
	[11] = {
		[171] = { name = "Alchemy", child = 2906, trainer = { 93690 }, trainerPts = 1, treatise = 95127,
			treasures = { 93528, 93529 }, treasurePts = 1 },
		[164] = { name = "Blacksmithing", child = 2907, trainer = { 93691 }, trainerPts = 2, treatise = 95128,
			treasures = { 93530, 93531 }, treasurePts = 2 },
		[333] = { name = "Enchanting", child = 2909, trainer = { 93697, 93698, 93699 }, trainerPts = 3,
			at = { 47.8, 53.8, "Dolothos, the Enchanting trainer" }, treatise = 95129, treasures = { 93532, 93533 },
			treasurePts = 2, drops = { 95048, 95049, 95050, 95051, 95052 }, bigDrop = 95053, bigPts = 4,
			from = "disenchanting" },
		[202] = { name = "Engineering", child = 2910, trainer = { 93692 }, trainerPts = 1, treatise = 95138,
			treasures = { 93534, 93535 }, treasurePts = 1 },
		[182] = { name = "Herbalism", child = 2912, gathering = true, trainer = { 93700, 93701, 93702, 93703, 93704 },
			trainerPts = 3, at = { 48.2, 51.6, "Botanist Nathera, the Herbalism trainer" }, treatise = 95130,
			drops = { 81425, 81426, 81427, 81428, 81429 }, bigDrop = 81430, bigPts = 4, from = "picking herbs" },
		[773] = { name = "Inscription", child = 2913, trainer = { 93693 }, trainerPts = 4, treatise = 95131,
			treasures = { 93536, 93537 }, treasurePts = 2 },
		[755] = { name = "Jewelcrafting", child = 2914, trainer = { 93694 }, trainerPts = 3, treatise = 95133,
			treasures = { 93538, 93539 }, treasurePts = 2 },
		[165] = { name = "Leatherworking", child = 2915, trainer = { 93695 }, trainerPts = 2, treatise = 95134,
			treasures = { 93540, 93541 }, treasurePts = 2 },
		[186] = { name = "Mining", child = 2916, gathering = true, trainer = { 93705, 93706, 93707, 93708, 93709 },
			trainerPts = 3, at = { 42.6, 52.8, "Belil, the Mining trainer" }, treatise = 95135,
			drops = { 88673, 88674, 88675, 88676, 88677 }, bigDrop = 88678, bigPts = 3, from = "mining" },
		[393] = { name = "Skinning", child = 2917, gathering = true, trainer = { 93710, 93711, 93712, 93713, 93714 },
			trainerPts = 3, at = { 43.2, 55.6, "Tyn, the Skinning trainer" }, treatise = 95136,
			drops = { 88534, 88549, 88537, 88536, 88530 }, bigDrop = 88529, bigPts = 3, from = "skinning" },
		[197] = { name = "Tailoring", child = 2918, trainer = { 93696 }, trainerPts = 2, treatise = 95137,
			treasures = { 93542, 93543 }, treasurePts = 2 },
	},
}

-- Where an expansion's profession weeklies happen (map IDs from WeeklyKnowledge; coordinates in percent).
ns.WEEKLY_EXPANSIONS = {
	[10] = { city = "Dornogal", map = 2339, zone = "Khaz Algar", treatise = "Algari Treatise on %s",
		consortium = { 59.2, 55.6, "Kala Clayhoof at the Artisan's Consortium" }, orders = { 58.0, 56.4 } },
	[11] = { city = "Silvermoon City", map = 2393, zone = "Midnight's zones", treatise = "Thalassian Treatise on %s",
		consortium = { 45.0, 55.2, "the Artisan's Consortium" }, orders = { 45.0, 55.6 } },
}
local DEFAULT_EXPANSION = 11 -- snapshots from before the expansion was stored

-- The newest expansion with data that the character's expansion level reaches (GetExpansionLevel()).
function ns.Weekly_Expansion(level)
	local best
	for expansion in pairs(ns.WEEKLY_PROFS) do
		if expansion <= (level or 0) and (not best or expansion > best) then
			best = expansion
		end
	end
	return best
end

function ns.Weekly_ProfDef(expansion, base)
	local profs = ns.WEEKLY_PROFS[expansion or DEFAULT_EXPANSION]
	return profs and profs[base]
end

-- Every knowledge quest ID of a profession.
function ns.Weekly_ProfQuestIDs(def)
	local ids = {}
	for _, field in ipairs({ "trainer", "treasures", "drops" }) do -- by name: gathering has no treasures
		for _, id in ipairs(def[field] or {}) do
			ids[#ids + 1] = id
		end
	end
	ids[#ids + 1] = def.treatise
	ids[#ids + 1] = def.bigDrop
	return ids
end

local profQuest = {}
for _, profs in pairs(ns.WEEKLY_PROFS) do
	for _, def in pairs(profs) do
		for _, id in ipairs(ns.Weekly_ProfQuestIDs(def)) do
			profQuest[id] = true
		end
	end
end

-- Profession knowledge quests are shown per profession, never as learned weekly quests.
function ns.Weekly_IsProfQuest(id)
	return profQuest[id] == true
end

function ns.Weekly_Duration(seconds)
	seconds = max(0, floor(seconds))
	local d, h, m = floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60)
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return ("%dh %dm"):format(h, m)
	end
	return ("%dm"):format(m)
end

-- Concentration now, predicted from a stored reading: amount and when it is full (the reading time when it was
-- already full; nil when the reading has no recharge rate).
function ns.Weekly_ConcNow(conc, now)
	if not conc or not conc.max or conc.max <= 0 then
		return nil
	end
	local qty = conc.qty or 0
	if qty >= conc.max then
		return conc.max, conc.at
	end
	local cycle, per = conc.cycleMS, conc.perCycle
	if not cycle or cycle <= 0 or not per or per <= 0 or not conc.at then
		return qty, nil
	end
	local cycles = max(floor((now - conc.at) * 1000 / cycle), 0)
	local fullAt = conc.at + ceil((conc.max - qty) / per) * cycle / 1000
	return min(conc.max, qty + cycles * per), fullAt
end

-- A new Concentration reading: the "toasted" mark survives only while it stays full.
function ns.Weekly_MergeConc(old, new)
	if new.qty >= new.max and old and old.notified then
		new.notified = true
	end
	return new
end

local function AnyUnlocked(vault)
	for _, slots in pairs(vault or {}) do
		for _, s in ipairs(slots) do
			if (s.progress or 0) >= (s.threshold or 1) then
				return true
			end
		end
	end
	return false
end

-- No known reset time (the API gave none) counts as current rather than reset forever.
function ns.Weekly_IsStale(snap, now)
	return snap.nextReset ~= nil and now >= snap.nextReset
end

-- The snapshot as it is at `now`: after a weekly reset, weekly progress shows as reset and a vault with unlocked
-- slots is waiting; lockouts drop at their own expiry; Concentration is predicted.
function ns.Weekly_View(snap, now)
	local stale = ns.Weekly_IsStale(snap, now)
	local v = {
		guid = snap.guid, name = snap.name, realm = snap.realm, class = snap.class, at = snap.at, seen = snap.seen,
		stale = stale, vault = {}, currencies = {}, quests = {}, renown = snap.renown or {}, lockouts = {}, profs = {},
	}
	v.vaultReady = snap.vaultReady == true or (stale and AnyUnlocked(snap.vault))
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		local slots = {}
		for i, s in ipairs(snap.vault and snap.vault[track.key] or {}) do
			slots[i] = { threshold = s.threshold, progress = stale and 0 or s.progress, ilvl = not stale and s.ilvl or nil }
		end
		v.vault[track.key] = slots
	end
	for id, c in pairs(snap.currencies or {}) do
		v.currencies[id] = {
			name = c.name, qty = c.qty, earnedWeek = stale and 0 or c.earnedWeek, weeklyCap = c.weeklyCap,
			total = c.total, seasonCap = c.seasonCap, useTotal = c.useTotal,
		}
	end
	for id, state in pairs(snap.quests or {}) do
		if not stale or state == "log" then
			v.quests[id] = stale and "log" or state
		end
	end
	for _, l in ipairs(snap.lockouts or {}) do
		if (l.expires or 0) > now then
			v.lockouts[#v.lockouts + 1] = l
		end
	end
	for skillLine, p in pairs(snap.profs or {}) do
		local prof = { name = p.name, icon = p.icon, base = p.base, expansion = p.expansion, gathering = p.gathering,
			knowledge = stale and {} or (p.knowledge or {}) }
		if p.conc then
			local qty, fullAt = ns.Weekly_ConcNow(p.conc, now)
			prof.conc = { qty = qty, max = p.conc.max, fullAt = fullAt, full = qty ~= nil and qty >= p.conc.max,
				notified = p.conc.notified }
		end
		v.profs[skillLine] = prof
	end
	return v
end

-- Vault track: unlocked slots, the next locked slot (nil when all are open) and the best unlocked item level.
function ns.Weekly_VaultGoal(slots)
	local unlocked, nextSlot, best = 0, nil, nil
	for i, s in ipairs(slots) do
		if s.progress >= s.threshold then
			unlocked = unlocked + 1
			if s.ilvl and (not best or s.ilvl > best) then
				best = s.ilvl
			end
		elseif not nextSlot then
			nextSlot = i
		end
	end
	return unlocked, nextSlot, best
end

-- "2/4 to slot 2 · ilvl 694"
function ns.Weekly_VaultText(slots)
	local unlocked, nextSlot, best = ns.Weekly_VaultGoal(slots)
	local text
	if nextSlot then
		local s = slots[nextSlot]
		text = ("%d/%d to slot %d"):format(s.progress, s.threshold, nextSlot)
	else
		text = "all slots open"
	end
	if best then
		text = text .. (" · ilvl %d"):format(best)
	end
	return text, unlocked, #slots
end

-- What a capped currency counts against its cap: the season total, this week's earnings, or what you hold.
-- Returns amount, cap (nil when uncapped).
function ns.Weekly_CurrencyProgress(c)
	if c.useTotal and (c.seasonCap or 0) > 0 then
		return c.total or 0, c.seasonCap
	elseif (c.weeklyCap or 0) > 0 then
		return c.earnedWeek or 0, c.weeklyCap
	elseif (c.seasonCap or 0) > 0 then
		return c.qty or 0, c.seasonCap
	end
	return c.qty or 0, nil
end

local function Pts(n)
	return n == 1 and "1 pt" or (n .. " pts")
end
ns.Weekly_Pts = Pts

-- Knowledge sources of one profession: { label, n, of, pts (each), tip, loc = { map, x, y, text } } rows.
function ns.Weekly_Knowledge(def, done, expansion)
	local function Count(ids)
		local n = 0
		for _, id in ipairs(ids) do
			if done[id] then
				n = n + 1
			end
		end
		return n
	end
	local exp = ns.WEEKLY_EXPANSIONS[expansion or DEFAULT_EXPANSION]
	local trainer = def.at or exp.consortium
	local rows = {
		{
			label = "Trainer quest", n = Count(def.trainer) > 0 and 1 or 0, of = 1, pts = def.trainerPts or 1,
			tip = ("One quest a week from %s in %s."):format(trainer[3], exp.city),
			loc = { map = exp.map, x = trainer[1], y = trainer[2], text = trainer[3] },
		},
		{
			label = "Treatise", n = done[def.treatise] and 1 or 0, of = 1, pts = 1,
			tip = ("Use an %s (one a week counts). Scribes make it: buy one on the Auction House or place a crafting order in %s."):format(
				exp.treatise:format(def.name), exp.city),
			loc = { map = exp.map, x = exp.orders[1], y = exp.orders[2], text = "Crafting orders" },
		},
	}
	if def.treasures then
		rows[#rows + 1] = { label = "Treasures", n = Count(def.treasures), of = #def.treasures, pts = def.treasurePts or 1,
			tip = ("Two different items, looted at random from treasures and chests in %s. One of each counts per week."):format(exp.zone) }
	end
	if def.drops then
		rows[#rows + 1] = { label = "Weekly drops", n = Count(def.drops), of = #def.drops, pts = 1,
			tip = ("Drop at random while %s in %s. Up to %d count per week."):format(def.from, exp.zone, #def.drops) }
		rows[#rows + 1] = { label = "Big drop", n = done[def.bigDrop] and 1 or 0, of = 1, pts = def.bigPts or 1,
			tip = ("A rarer drop while %s in %s, once a week."):format(def.from, exp.zone) }
	end
	return rows
end

-- Knowledge sources done / total, and the points still to collect this week.
local function KnowledgeTotal(def, done, expansion)
	local n, of, left = 0, 0, 0
	for _, row in ipairs(ns.Weekly_Knowledge(def, done, expansion)) do
		n, of = n + row.n, of + row.of
		left = left + (row.of - row.n) * row.pts
	end
	return n, of, left
end

-- Right-hand text of a knowledge row.
local function KnowledgeStatus(k)
	if k.n >= k.of then
		return "done", "done"
	elseif k.of > 1 then
		return ("%d/%d · %s each"):format(k.n, k.of, Pts(k.pts)), "open"
	end
	return "open · " .. Pts(k.pts), "open"
end

-- Learned weekly quests worth showing for a view: in the log or done this week. Sorted by title.
function ns.Weekly_Quests(v, learned)
	local list = {}
	for id, state in pairs(v.quests) do
		local q = learned[id]
		if q then
			list[#list + 1] = { id = id, title = q.title or ("Quest " .. id), done = state == "done" }
		end
	end
	table.sort(list, function(a, b)
		if a.title ~= b.title then
			return a.title < b.title
		end
		return a.id < b.id
	end)
	return list
end

-- Professions of a view in name order: { skillLine, prof, def }.
local function Profs(v)
	local list = {}
	for skillLine, prof in pairs(v.profs) do
		local def = ns.Weekly_ProfDef(prof.expansion, prof.base)
		if def then
			list[#list + 1] = { skillLine = skillLine, prof = prof, def = def }
		end
	end
	table.sort(list, function(a, b)
		return (a.prof.name or a.def.name) < (b.prof.name or b.def.name)
	end)
	return list
end

local function ConcText(conc, now)
	if not conc.qty then
		return nil
	elseif conc.full then
		return "Full, wasting", "warn"
	elseif conc.fullAt then
		local when = conc.fullAt - now < 6 * 86400 and date("%a %H:%M", conc.fullAt) or date("%d %b", conc.fullAt)
		return ("%d / %d · full %s"):format(conc.qty, conc.max, when), "open"
	end
	return ("%d / %d"):format(conc.qty, conc.max), "open"
end

local function Section(items, title, rows)
	if #rows == 0 then
		return
	end
	items[#items + 1] = { kind = "header", text = title }
	for _, row in ipairs(rows) do
		row.kind = row.kind or "row"
		items[#items + 1] = row
	end
end

local function Renown(v)
	local list = {}
	for id, r in pairs(v.renown) do
		list[#list + 1] = { id = id, r = r }
	end
	table.sort(list, function(a, b)
		return (a.r.name or "") < (b.r.name or "")
	end)
	return list
end

local function CrestRows(v)
	local rows = {}
	for _, id in ipairs(ns.WEEKLY_CRESTS) do
		local c = v.currencies[id]
		if c then
			local have, cap = ns.Weekly_CurrencyProgress(c)
			rows[#rows + 1] = {
				left = c.name or ("Currency " .. id),
				right = cap and ("%d / %d"):format(have, cap) or tostring(have),
				state = cap and have >= cap and "done" or "open",
				frac = cap and min(have / cap, 1) or nil,
			}
		end
	end
	return rows
end

-- "1,250"
local function Thousands(n)
	local text = tostring(floor(n or 0))
	local replaced
	repeat
		text, replaced = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until replaced == 0
	return text
end

-- "Resets in 11h 23m · Tue 05:00" (local time of the reset), or nil when the client gave no reset time.
function ns.Weekly_ResetText(seconds, now)
	if not seconds or seconds <= 0 then
		return nil
	end
	return ("Resets in %s · %s"):format(ns.Weekly_Duration(seconds), date("%a %H:%M", now + seconds))
end

-- What one more activity of a vault track is: singular, plural.
local VAULT_UNITS = { raid = { "boss", "bosses" }, dungeons = { "dungeon", "dungeons" },
	world = { "activity", "activities" } }

-- "This week" on the board for the current character:
-- { vaultReady, vault = { { key, label, slots, nextSlot, note, done } }, todo = items, progress = items }
-- todo: weekly quests (open first) and each profession's open knowledge sources; progress: renown (the bar is the
-- level out of max), crests and lockouts. Items use the row schema at the top of this file.
function ns.Weekly_BoardModel(v, learned, now, showLearned)
	local model = { vaultReady = v.vaultReady, vault = {}, todo = {}, progress = {} }
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		local slots = v.vault[track.key]
		if slots and #slots > 0 then
			local unlocked, nextSlot = ns.Weekly_VaultGoal(slots)
			local note
			if nextSlot then
				local need = slots[nextSlot].threshold - slots[nextSlot].progress
				local unit = VAULT_UNITS[track.key] or { "more", "more" }
				note = ("%d more %s for slot %d"):format(need, need == 1 and unit[1] or unit[2], nextSlot)
			else
				note = ("All %d slots unlocked"):format(#slots)
			end
			model.vault[#model.vault + 1] = { key = track.key, label = track.label, slots = slots, nextSlot = nextSlot,
				note = note, done = unlocked == #slots }
		end
	end

	local todo = model.todo
	if showLearned then
		local open, done = {}, {}
		for _, q in ipairs(ns.Weekly_Quests(v, learned)) do
			if q.done then
				done[#done + 1] = { left = q.title, right = "done", state = "done", dimLeft = true }
			else
				open[#open + 1] = { left = q.title, right = "open", state = "open" }
			end
		end
		for _, row in ipairs(done) do
			open[#open + 1] = row
		end
		Section(todo, "Weekly quests", open)
	end
	for _, p in ipairs(Profs(v)) do
		local name = p.prof.name or p.def.name
		local _, _, left = KnowledgeTotal(p.def, p.prof.knowledge, p.prof.expansion)
		local concText, concState
		if p.prof.conc then
			concText, concState = ConcText(p.prof.conc, now)
		end
		if left == 0 then
			local right = "knowledge done"
			if concText then
				right = right .. " · " .. concText
			end
			todo[#todo + 1] = { kind = "row", left = name, right = right, state = concState == "warn" and "warn" or "done" }
		else
			todo[#todo + 1] = { kind = "header", text = name, right = concText, state = concState }
			for _, k in ipairs(ns.Weekly_Knowledge(p.def, p.prof.knowledge, p.prof.expansion)) do
				if k.n < k.of then
					local status = KnowledgeStatus(k)
					todo[#todo + 1] = { kind = "row", left = k.label, right = status, state = "open", tip = k.tip, loc = k.loc,
						indent = true }
				end
			end
		end
	end

	local progress = model.progress
	local renown = {}
	for _, entry in ipairs(Renown(v)) do
		local r = entry.r
		local maxed = r.max and r.level >= r.max
		local toNext = not maxed and r.threshold and r.threshold > 0
			and ("%s / %s to %d"):format(Thousands(r.earned), Thousands(r.threshold), r.level + 1) or nil
		local frac
		if maxed then
			frac = 1
		elseif r.max and r.max > 0 then
			frac = min(r.level / r.max, 1)
		elseif r.threshold and r.threshold > 0 then
			frac = min((r.earned or 0) / r.threshold, 1)
		end
		renown[#renown + 1] = {
			left = r.name or ("Faction " .. entry.id), note = toNext,
			right = maxed and "max" or (r.max and ("%d / %d"):format(r.level, r.max) or ("level %d"):format(r.level)),
			state = maxed and "gold" or "open", frac = frac,
		}
	end
	Section(progress, "Renown", renown)
	Section(progress, "Crests", CrestRows(v))
	local lockouts = {}
	for _, l in ipairs(v.lockouts) do
		local killed = l.worldBoss and "killed" or ("%d/%d"):format(l.killed or 0, l.total or 0)
		lockouts[#lockouts + 1] = {
			left = l.difficulty and (l.name .. " " .. l.difficulty) or l.name,
			right = ("%s · resets in %s"):format(killed, ns.Weekly_Duration(l.expires - now)),
			state = (l.worldBoss or l.killed == l.total) and "done" or "open",
		}
	end
	Section(progress, "Lockouts", lockouts)
	return model
end

-- Popup: only what is still open for the current character.
function ns.Weekly_OpenModel(v, learned, now, showLearned)
	local rows = {}
	if v.vaultReady then
		rows[#rows + 1] = { kind = "banner", text = "Great Vault waiting" }
	end
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		local slots = v.vault[track.key]
		if slots and #slots > 0 then
			local text, unlocked, n = ns.Weekly_VaultText(slots)
			if unlocked < n then
				rows[#rows + 1] = { kind = "row", left = "Vault: " .. track.label, right = text, state = "open" }
			end
		end
	end
	for _, row in ipairs(CrestRows(v)) do
		if row.state == "open" and row.frac then
			row.kind = "row"
			rows[#rows + 1] = row
		end
	end
	if showLearned then
		for _, q in ipairs(ns.Weekly_Quests(v, learned)) do
			if not q.done then
				rows[#rows + 1] = { kind = "row", left = q.title, right = "open", state = "open" }
			end
		end
	end
	for _, p in ipairs(Profs(v)) do
		for _, k in ipairs(ns.Weekly_Knowledge(p.def, p.prof.knowledge, p.prof.expansion)) do
			if k.n < k.of then
				local right = KnowledgeStatus(k)
				rows[#rows + 1] = { kind = "row", left = (p.prof.name or p.def.name) .. ": " .. k.label,
					right = right, state = "open", tip = k.tip, loc = k.loc }
			end
		end
		if p.prof.conc and p.prof.conc.full then
			rows[#rows + 1] = { kind = "row", left = (p.prof.name or p.def.name) .. ": Concentration",
				right = "full", state = "warn" }
		end
	end
	return rows
end

-- Professions view: every character with professions.
function ns.Weekly_ProfModel(views, now)
	local items = {}
	for _, v in ipairs(views) do
		local profs = Profs(v)
		if #profs > 0 then
			items[#items + 1] = { kind = "header", text = v.name or "?", class = v.class }
			for _, p in ipairs(profs) do
				local _, _, left = KnowledgeTotal(p.def, p.prof.knowledge, p.prof.expansion)
				local row = {
					kind = "row", left = p.prof.name or p.def.name,
					right = left > 0 and ("%s of knowledge left this week"):format(Pts(left)) or "all knowledge collected",
					state = left == 0 and "done" or (v.stale and "dim" or "open"),
				}
				items[#items + 1] = row
				if p.prof.conc and p.prof.conc.qty then
					local text, state = ConcText(p.prof.conc, now)
					items[#items + 1] = { kind = "row", indent = true, left = "Concentration", right = text, state = state,
						frac = p.prof.conc.qty / p.prof.conc.max,
						tip = "Spent on crafts for higher quality; refills over time. Full means it's going to waste." }
				end
				for _, k in ipairs(ns.Weekly_Knowledge(p.def, p.prof.knowledge, p.prof.expansion)) do
					local right, state = KnowledgeStatus(k)
					items[#items + 1] = {
						kind = "row", indent = true, left = k.label, right = right,
						state = state == "open" and v.stale and "dim" or state, tip = k.tip, loc = k.loc,
					}
				end
			end
		end
	end
	return items
end

-- Characters grid: { columns = views, rows = { { header } or { label, cells = { { text, state, tip } } } } }.
-- A row appears when at least one character has data for it.
function ns.Weekly_GridModel(views, learned, now)
	local rows = {}
	local function Weekly(v, state)
		return v.stale and "dim" or state
	end
	local function Add(label, cell)
		local cells, any = {}, false
		for i, v in ipairs(views) do
			local c = cell(v)
			cells[i] = c or { text = "" }
			any = any or c ~= nil
		end
		if any then
			rows[#rows + 1] = { label = label, cells = cells }
		end
	end
	local function Header(text)
		rows[#rows + 1] = { header = text }
	end

	Header("Great Vault")
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		Add(track.label, function(v)
			local slots = v.vault[track.key]
			if not slots or #slots == 0 then
				return nil
			end
			local text, unlocked, n = ns.Weekly_VaultText(slots)
			return { text = ("%d/%d"):format(unlocked, n), tip = text, state = Weekly(v, unlocked == n and "done" or "open") }
		end)
	end

	Header("Currencies")
	for _, id in ipairs(ns.WEEKLY_CRESTS) do
		local name
		for _, v in ipairs(views) do
			name = name or (v.currencies[id] and v.currencies[id].name)
		end
		Add(name or ("Currency " .. id), function(v)
			local c = v.currencies[id]
			if not c then
				return nil
			end
			local have, cap = ns.Weekly_CurrencyProgress(c)
			return { text = cap and ("%d/%d"):format(have, cap) or tostring(have), tip = ("%d held"):format(c.qty or 0),
				state = Weekly(v, cap and have >= cap and "done" or "open") }
		end)
	end

	Header("This week")
	Add("Weekly quests", function(v)
		local list = ns.Weekly_Quests(v, learned)
		if #list == 0 then
			return nil
		end
		local n, tip = 0, {}
		for _, q in ipairs(list) do
			n = n + (q.done and 1 or 0)
			tip[#tip + 1] = (q.done and "done  " or "open  ") .. q.title
		end
		return { text = ("%d/%d"):format(n, #list), tip = table.concat(tip, "\n"), state = Weekly(v, n == #list and "done" or "open") }
	end)
	Add("Knowledge", function(v)
		local profs = Profs(v)
		if #profs == 0 then
			return nil
		end
		local n, of, tip = 0, 0, {}
		for _, p in ipairs(profs) do
			local pn, pof = KnowledgeTotal(p.def, p.prof.knowledge, p.prof.expansion)
			n, of = n + pn, of + pof
			tip[#tip + 1] = ("%s %d/%d"):format(p.prof.name or p.def.name, pn, pof)
		end
		return { text = ("%d/%d"):format(n, of), tip = table.concat(tip, "\n"), state = Weekly(v, n == of and "done" or "open") }
	end)
	Add("Concentration", function(v)
		local best, tip = nil, {}
		for _, p in ipairs(Profs(v)) do
			local conc = p.prof.conc
			if conc and conc.qty then
				local text = ConcText(conc, now)
				tip[#tip + 1] = (p.prof.name or p.def.name) .. ": " .. text
				if not best or conc.qty / conc.max > best.qty / best.max then
					best = conc
				end
			end
		end
		if not best then
			return nil
		end
		return { text = best.full and "full" or ("%d"):format(best.qty), tip = table.concat(tip, "\n"),
			state = best.full and "warn" or "open" }
	end)

	Header("Renown")
	local factions, seen = {}, {}
	for _, v in ipairs(views) do
		for id, r in pairs(v.renown) do
			if not seen[id] then
				seen[id] = true
				factions[#factions + 1] = { id = id, name = r.name or ("Faction " .. id) }
			end
		end
	end
	table.sort(factions, function(a, b)
		return a.name < b.name
	end)
	for _, f in ipairs(factions) do
		Add(f.name, function(v)
			local r = v.renown[f.id]
			if not r then
				return nil
			end
			local maxed = r.max and r.level >= r.max
			return { text = tostring(r.level), state = maxed and "done" or "open" }
		end)
	end

	Header("Lockouts")
	local raids, seenRaid = {}, {}
	for _, v in ipairs(views) do
		for _, l in ipairs(v.lockouts) do
			local key = l.name .. "|" .. (l.difficulty or "")
			if not seenRaid[key] then
				seenRaid[key] = true
				raids[#raids + 1] = { key = key, label = l.difficulty and (l.name .. " " .. l.difficulty) or l.name }
			end
		end
	end
	table.sort(raids, function(a, b)
		return a.label < b.label
	end)
	for _, raid in ipairs(raids) do
		Add(raid.label, function(v)
			for _, l in ipairs(v.lockouts) do
				if l.name .. "|" .. (l.difficulty or "") == raid.key then
					local text = l.worldBoss and "killed" or ("%d/%d"):format(l.killed or 0, l.total or 0)
					return { text = text, tip = "resets in " .. ns.Weekly_Duration(l.expires - now),
						state = (l.worldBoss or l.killed == l.total) and "done" or "open" }
				end
			end
			return nil
		end)
	end

	-- Drop headers with nothing under them.
	local kept = {}
	for i, row in ipairs(rows) do
		local nextRow = rows[i + 1]
		if not row.header or (nextRow and not nextRow.header) then
			kept[#kept + 1] = row
		end
	end
	return { columns = views, rows = kept }
end

-- Concentration toasts: predicted full and not toasted for this fill. Returns { { guid, skillLine } }.
function ns.Weekly_DueConc(chars, now)
	local due = {}
	for guid, snap in pairs(chars) do
		for skillLine, p in pairs(snap.profs or {}) do
			local conc = p.conc
			if conc and not conc.notified then
				local qty = ns.Weekly_ConcNow(conc, now)
				if qty and qty >= conc.max then
					due[#due + 1] = { guid = guid, skillLine = skillLine }
				end
			end
		end
	end
	table.sort(due, function(a, b)
		if a.guid ~= b.guid then
			return a.guid < b.guid
		end
		return a.skillLine < b.skillLine
	end)
	return due
end

-- The earliest future moment some not-yet-toasted Concentration becomes full (nil: none).
function ns.Weekly_NextConcFull(chars, now)
	local soonest
	for _, snap in pairs(chars) do
		for _, p in pairs(snap.profs or {}) do
			if p.conc and not p.conc.notified then
				local _, fullAt = ns.Weekly_ConcNow(p.conc, now)
				if fullAt and fullAt > now and (not soonest or fullAt < soonest) then
					soonest = fullAt
				end
			end
		end
	end
	return soonest
end

-- Grid/profession column order: the current character first, then the rest by last seen. Hidden ones are left out
-- (the current one too, unless keepCurrent).
function ns.Weekly_CharOrder(chars, current, hidden, keepCurrent)
	local list = {}
	for guid in pairs(chars) do
		if guid ~= current and not hidden[guid] then
			list[#list + 1] = guid
		end
	end
	table.sort(list, function(a, b)
		local sa, sb = chars[a].seen or chars[a].at or 0, chars[b].seen or chars[b].at or 0
		if sa ~= sb then
			return sa > sb
		end
		return (chars[a].name or "") < (chars[b].name or "")
	end)
	if chars[current] and (keepCurrent or not hidden[current]) then
		table.insert(list, 1, current)
	end
	return list
end

-- Home tile line: "Vault 2/6 · 9 knowledge left" (unlocked vault slots, open knowledge sources of all professions).
function ns.Weekly_HomeSummary(v)
	local parts = {}
	local unlocked, total = 0, 0
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		local slots = v.vault and v.vault[track.key] or {}
		unlocked = unlocked + ns.Weekly_VaultGoal(slots)
		total = total + #slots
	end
	if v.vaultReady then
		parts[1] = "Vault rewards waiting"
	elseif total > 0 then
		parts[1] = ("Vault %d/%d"):format(unlocked, total)
	end
	local left = 0
	for _, p in ipairs(v.profs and Profs(v) or {}) do
		local n, of = KnowledgeTotal(p.def, p.prof.knowledge or {}, p.prof.expansion)
		left = left + of - n
	end
	if left > 0 then
		parts[#parts + 1] = ("%d knowledge left"):format(left)
	end
	return table.concat(parts, " · ")
end

-- Next up: knowledge sources still open this week that have a place to go. { name, icon, label, pts, tip, loc }.
function ns.Weekly_OpenKnowledge(v)
	local list = {}
	for _, p in ipairs(v.profs and Profs(v) or {}) do
		for _, k in ipairs(ns.Weekly_Knowledge(p.def, p.prof.knowledge or {}, p.prof.expansion)) do
			if k.n < k.of and k.loc then
				list[#list + 1] = { name = p.prof.name or p.def.name, icon = p.prof.icon, skillLine = p.skillLine,
					label = k.label, pts = k.pts, tip = k.tip, loc = k.loc }
			end
		end
	end
	return list
end

-- Home "This week" list: what's still open this week, then what's done. { text, right, done }.
-- Knowledge sources per profession ("Mining treatise"), learned weekly quests, crests with a cap.
function ns.Weekly_HomeTodo(v, learned)
	local open, done = {}, {}
	local function Add(row)
		local list = row.done and done or open
		list[#list + 1] = row
	end
	for _, p in ipairs(v.profs and Profs(v) or {}) do
		local name = p.prof.name or p.def.name
		for _, k in ipairs(ns.Weekly_Knowledge(p.def, p.prof.knowledge or {}, p.prof.expansion)) do
			Add({
				text = ("%s %s"):format(name, k.label:lower()),
				right = k.of > 1 and ("%d/%d"):format(k.n, k.of) or Pts(k.pts),
				done = k.n >= k.of,
			})
		end
	end
	for _, q in ipairs(ns.Weekly_Quests(v, learned or {})) do
		Add({ text = q.title, right = q.done and "done" or "in log", done = q.done })
	end
	local ids = {}
	for id in pairs(v.currencies or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local c = v.currencies[id]
		local amount, cap = ns.Weekly_CurrencyProgress(c)
		if cap then
			Add({ text = c.name or ("Currency " .. id), right = ("%d / %d"):format(amount, cap), done = amount >= cap })
		end
	end
	for _, row in ipairs(done) do
		open[#open + 1] = row
	end
	return open
end
