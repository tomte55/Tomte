local addonName, ns = ...

-- Delves: pure logic (no WoW API calls; unit-tested with plain Lua 5.1). Bountiful detection and order, the key
-- line, the Great Vault World track plan, the tier ladder, the tier suggestion, the companion role hint, the Gilded
-- Stash count, the season journey bar, the key and shard caps for tooltips and the delve power pick.

ns.DELVES_BOUNTIFUL_ATLAS = "delves-bountiful"
ns.DELVES_ROLE_BY_ENUM = { [0] = "DAMAGER", [1] = "HEALER", [2] = "TANK" } -- Enum.CompanionRoleType

local LADDER_STEPS = 20
local SUGGEST = { TANK = "HEALER", HEALER = "DAMAGER" }
local WORD = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }

local function Plural(n, one, many)
	return n == 1 and one or many
end

function ns.Delves_IsBountiful(e, known)
	if e.atlas == ns.DELVES_BOUNTIFUL_ATLAS then
		return true
	end
	return known ~= nil and e.poi ~= nil and known[e.poi] ~= nil
end

function ns.Delves_Sort(list, myZone)
	table.sort(list, function(a, b)
		local ab, bb = a.bountiful == true, b.bountiful == true
		if ab ~= bb then
			return ab
		end
		local am, bm = a.map == myZone, b.map == myZone
		if am ~= bm then
			return am
		end
		if (a.name or "") ~= (b.name or "") then
			return (a.name or "") < (b.name or "")
		end
		return (a.poi or 0) < (b.poi or 0)
	end)
	return list
end

function ns.Delves_Earned(curated, kind)
	for _, g in ipairs(curated or {}) do
		for _, e in ipairs(g.entries or {}) do
			if e.kind == kind and e.of then
				return { n = e.n or 0, of = e.of }
			end
		end
	end
	return nil
end

-- k (Read.lua ReadKeys): keys, perKey, shards, shardWeek = { n, of }, earned = { n, of }. Returns the line and
-- whether the shards make at least one more key (combine).
function ns.Delves_KeyLine(k)
	local keys = k.keys or 0
	local parts = { ("%d %s"):format(keys, Plural(keys, "key", "keys")) }
	local combine = false
	if k.shards then
		local perKey = k.perKey or 100
		local text = ("%d shards"):format(k.shards)
		if k.shards >= perKey then
			local n = math.floor(k.shards / perKey)
			text = text .. (" (%d more %s)"):format(n, Plural(n, "key", "keys"))
			combine = true
		end
		if k.shardWeek and (k.shardWeek.of or 0) > 0 then
			text = text .. (", %d/%d this week"):format(k.shardWeek.n or 0, k.shardWeek.of)
		end
		parts[#parts + 1] = text
	end
	if k.earned then
		parts[#parts + 1] = ("keys this week %d/%d"):format(k.earned.n, k.earned.of)
	end
	return table.concat(parts, " · "), combine
end

-- The tier of the threshold-th best run (a slot pays for that run), or nil with fewer runs.
local function TierAt(runs, threshold)
	local seen = 0
	for _, r in ipairs(runs) do
		seen = seen + (r.numPoints or 0)
		if seen >= threshold then
			return r.difficulty
		end
	end
	return nil
end

local function CountAtLeast(runs, tier)
	local n = 0
	for _, r in ipairs(runs) do
		if r.difficulty >= tier then
			n = n + (r.numPoints or 0)
		end
	end
	return n
end

local function VaultText(plan)
	local a = plan.advice
	if not a then
		return #plan.rows > 0 and "Every World slot is maxed" or nil
	end
	if a.unlocked then
		return ("Tier %d or higher: %d more %s vault slot %d (now Tier %d)"):format(plan.top, a.need,
			Plural(a.need, "run maxes", "runs max"), a.index, a.tier or 1)
	end
	return ("Tier %d or higher: %d more %s vault slot %d at the top"):format(plan.top, a.need,
		Plural(a.need, "run unlocks", "runs unlock"), a.index)
end

-- slots: the World track's { threshold, progress } in slot order; runs: GetSortedProgressForActivity entries
-- ({ difficulty, numPoints }); top: the tier that maxes a slot. Returns { top, rows, advice, text }: one row per slot
-- ({ index, threshold, unlocked, tier, maxed, need }), advice the first row not maxed (nil when all are), text its line.
function ns.Delves_VaultPlan(slots, runs, top)
	local sorted = {}
	for i, r in ipairs(runs or {}) do
		sorted[i] = r
	end
	table.sort(sorted, function(a, b)
		return a.difficulty > b.difficulty
	end)
	local atTop = CountAtLeast(sorted, top)
	local plan = { top = top, rows = {} }
	for i, s in ipairs(slots or {}) do
		local row = { index = i, threshold = s.threshold, unlocked = (s.progress or 0) >= s.threshold,
			tier = TierAt(sorted, s.threshold) }
		row.maxed = row.unlocked and row.tier ~= nil and row.tier >= top
		row.need = math.max(s.threshold - atTop, 0)
		plan.rows[i] = row
		if not plan.advice and not row.maxed then
			plan.advice = row
		end
	end
	plan.text = VaultText(plan)
	return plan
end

-- step(tierID, level) is C_WeeklyRewards.GetNextActivitiesIncrease: hasSeasonData, nextActivityTierID, nextLevel,
-- itemLevel. Walks up from level (at most LADDER_STEPS). Returns { { tier, ilvl } } and the highest level reached,
-- or nil, nil when the game has no data at all.
function ns.Delves_Ladder(step, level, tierID)
	local ladder = {}
	for _ = 1, LADDER_STEPS do
		local hasData, nextTierID, nextLevel, itemLevel = step(tierID, level)
		if not hasData then
			if #ladder == 0 then
				return nil, nil
			end
			return ladder, level
		end
		if not nextLevel or nextLevel <= level then
			return ladder, level
		end
		ladder[#ladder + 1] = { tier = nextLevel, ilvl = itemLevel }
		level, tierID = nextLevel, nextTierID or tierID
	end
	return ladder, level
end

function ns.Delves_LadderText(ladder)
	if not ladder or #ladder == 0 then
		return nil
	end
	local parts = {}
	for i, step in ipairs(ladder) do
		parts[i] = ("Tier %d: %s"):format(step.tier, step.ilvl and tostring(step.ilvl) or "?")
	end
	return table.concat(parts, " · ")
end

-- tiers: C_DelvesUI.GetDelveEntranceTiers() ({ tier, unlocked, suggestedILvl }). The highest unlocked tier whose
-- suggested item level is at most ilvl (that tier's table), or nil.
function ns.Delves_SuggestTier(tiers, ilvl)
	if not ilvl then
		return nil
	end
	local best
	for _, t in ipairs(tiers or {}) do
		if t.unlocked and (t.suggestedILvl or 0) <= ilvl and (not best or t.tier > best.tier) then
			best = t
		end
	end
	return best
end

-- Roles are "TANK", "HEALER" or "DAMAGER"; names: the game's role names by role (the companion's subtree names),
-- English words when missing. A hint only when both roles match and there's a role to suggest, else nil.
function ns.Delves_RoleHint(playerRole, companionRole, companionName, names)
	if not playerRole or playerRole ~= companionRole then
		return nil
	end
	local suggest = SUGGEST[playerRole]
	if not suggest then
		return nil
	end
	names = names or {}
	return ("%s is set to %s: %s suits a %s"):format(companionName or "Your companion",
		names[companionRole] or WORD[companionRole], names[suggest] or WORD[suggest], WORD[playerRole])
end

-- season: C_MajorFactions.GetMajorFactionData of the season's delve faction (or nil). "season" when it has a
-- companion and belongs to the character's content expansion, else "fallback" (the expansion table's faction).
function ns.Delves_PickCompanionSource(season, expansion)
	if season and season.playerCompanionID and season.expansionID == expansion then
		return "season"
	end
	return "fallback"
end

-- Continent map IDs. "poi": super-track the AreaPOI (same continent), "pin": a user waypoint at the entrance.
function ns.Delves_TrackMode(myContinent, delveContinent)
	if myContinent and myContinent == delveContinent then
		return "poi"
	end
	return "pin"
end

-- One entry per delve and map: a bountiful entrance is its own POI, so drop the same delve's normal entrance when
-- both are listed (kept in the normal one's place). Names are the game's, compared with each other only. The key
-- joins map and name with "\0", which no name contains.
function ns.Delves_Dedupe(list)
	local bountiful = {}
	for _, e in ipairs(list) do
		if e.bountiful then
			bountiful[(e.map or 0) .. "\0" .. (e.name or "")] = e
		end
	end
	local out, used = {}, {}
	for _, e in ipairs(list) do
		local key = (e.map or 0) .. "\0" .. (e.name or "")
		local b = bountiful[key]
		if b and b ~= e then
			e = b
		end
		if not used[e] then
			used[e] = true
			out[#out + 1] = e
		end
	end
	return out
end

-- Next up's bountiful suggestion: mode "key" (default) only while you hold a Restored Coffer Key, "always" always.
function ns.Delves_SuggestBountiful(keys, mode)
	if mode == "always" then
		return true
	end
	return (keys or 0) > 0
end

-- Gilded Stash ---------------------------------------------------------------------------------------------------

-- The stash widget's tooltip text holds this week's count as "n/of" (digits in every client language). Returns n, of
-- or nil when there's no count in it.
function ns.Delves_StashParse(text)
	if type(text) ~= "string" then
		return nil
	end
	local n, of = text:match("(%d+)%s*/%s*(%d+)")
	n, of = tonumber(n), tonumber(of)
	if not (n and of) or of <= 0 then
		return nil
	end
	return n, of
end

-- live: { n, of, accurate } from the widget (nil away from the expansion's zones); saved: { n, of, week } from the
-- last accurate read; week: this week's start (ns.WeekStart, which can drift by a second between calls, so "same
-- week" allows WEEK_SLACK). Returns { n, of, old } (old: not read live this time) or nil.
local WEEK_SLACK = 3600
function ns.Delves_StashPick(live, saved, week)
	if live and live.accurate then
		return { n = live.n, of = live.of }
	end
	if saved and week and saved.week and math.abs(saved.week - week) < WEEK_SLACK and saved.of then
		return { n = saved.n or 0, of = saved.of, old = true }
	end
	if live then
		return { n = live.n, of = live.of, old = true }
	end
	return nil
end

-- name: the stash's own name (the game's spell name). The page line, or nil without a count.
function ns.Delves_StashText(stash, name)
	if not stash then
		return nil
	end
	local text = ("%s: %d/%d this week"):format(name or "Gilded Stash", stash.n, stash.of)
	if stash.n >= stash.of then
		text = text .. " (all found)"
	end
	return text
end

-- Season journey -------------------------------------------------------------------------------------------------

-- j: the reader's journey ({ level, earned, threshold, max }). The bar's fill, 0 to 1 (full at max renown).
function ns.Delves_JourneyFraction(j)
	if not j then
		return 0
	end
	if j.max and j.level and j.level >= j.max then
		return 1
	end
	if not j.threshold or j.threshold <= 0 then
		return 0
	end
	return math.min(math.max((j.earned or 0) / j.threshold, 0), 1)
end

-- Tooltip caps ---------------------------------------------------------------------------------------------------

local function CapLine(label, week)
	if not (week and (week.of or 0) > 0) then
		return nil
	end
	local done = (week.n or 0) >= week.of
	return { left = label, right = ("%d/%d"):format(week.n or 0, week.of) .. (done and " (cap reached)" or ""),
		role = done and "textMuted" or "text" }
end

-- k: the reader's keys ({ keys, perKey, shards, shardWeek, shardEarned, keyWeek, earned }); kind "keys" or "shards"
-- (the tooltip being shown). Returns { { left, right, role } } for the tooltip, maybe empty.
function ns.Delves_CapLines(k, kind)
	local lines = {}
	if not k then
		return lines
	end
	local function Add(line)
		if line then
			lines[#lines + 1] = line
		end
	end
	if kind == "keys" then
		Add(CapLine("Keys this week", k.keyWeek or k.earned))
		Add(CapLine("Shard caches this week", k.shardEarned))
		if k.shards then
			local perKey = k.perKey or 100
			local more = math.floor(k.shards / perKey)
			Add({ left = "Coffer Key Shards", right = more > 0 and ("%d (%d more %s)"):format(k.shards, more,
				Plural(more, "key", "keys")) or tostring(k.shards), role = more > 0 and "success" or "text" })
		end
	elseif kind == "shards" then
		Add(CapLine("Shards this week", k.shardWeek))
		Add(CapLine("Shard caches this week", k.shardEarned))
		if k.shards then
			local perKey = k.perKey or 100
			Add({ left = "Next key", right = ("%d/%d"):format(k.shards % perKey, perKey), role = "text" })
		end
		Add(CapLine("Keys this week", k.keyWeek or k.earned))
	end
	return lines
end

-- Delve powers ---------------------------------------------------------------------------------------------------

-- The "Preferred powers" setting: names or spell IDs, separated by commas or semicolons. Returns the list in order,
-- each { id = number } or { name = lower-case name }.
function ns.Delves_ParsePowers(text)
	local list = {}
	for part in tostring(text or ""):gmatch("[^,;]+") do
		part = part:match("^%s*(.-)%s*$")
		if part ~= "" then
			local id = tonumber(part)
			list[#list + 1] = id and { id = id } or { name = part:lower() }
		end
	end
	return list
end

local function Pickable(o)
	local b = o.buttons and o.buttons[1]
	return o.spellID ~= nil and not o.disabledOption and o.buttons and #o.buttons == 1 and b and b.id ~= nil
		and not b.disabled and not b.confirmation
end

-- options: PlayerChoiceOptionInfo list ({ spellID, header, disabledOption, buttons = { { id, disabled,
-- confirmation } } }); prefs: Delves_ParsePowers. Every option must be a power (a spell with one plain button), else
-- nothing is picked. One option: that one. Several: the one earliest in prefs. Returns the option and why
-- ("only", "preferred") or nil and why not ("notpowers", "nomatch", "none").
function ns.Delves_PickPower(options, prefs)
	if not options or #options == 0 then
		return nil, "none"
	end
	for _, o in ipairs(options) do
		if not Pickable(o) then
			return nil, "notpowers"
		end
	end
	if #options == 1 then
		return options[1], "only"
	end
	for _, p in ipairs(prefs or {}) do
		for _, o in ipairs(options) do
			if (p.id and o.spellID == p.id) or (p.name and type(o.header) == "string" and o.header:lower() == p.name) then
				return o, "preferred"
			end
		end
	end
	return nil, "nomatch"
end
