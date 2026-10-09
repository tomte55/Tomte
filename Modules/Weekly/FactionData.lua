local addonName, ns = ...

-- Factions tab: pure logic (tested with plain Lua). Records come from Factions.lua's reader:
-- { id, name, renown = bool, level, max, earned, threshold, maxed, paragon = { value, threshold, pending } | nil, kit,
--   icon, display, standing, parent }
-- (standing is the text for non-renown reputations, like "Rank 3" or "Honored"; maxed is set for those at their top).
-- Sub-factions (Undermine cartels, Severed Threads' three) aren't renown factions, so they're listed by hand per
-- expansion (`subfactions` in Data/<Expansion>/Weekly.lua).

local floor, min, max = math.floor, math.min, math.max

local function Thousands(n)
	local text = tostring(floor(n or 0))
	local replaced
	repeat
		text, replaced = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until replaced == 0
	return text
end

local function Maxed(rec)
	if rec.renown then
		return rec.max ~= nil and (rec.level or 0) >= rec.max
	end
	return rec.maxed == true
end

function ns.Weekly_FactionAtlas(kit, atlasExists)
	if not kit then
		return nil
	end
	local atlas = ("majorfactions_icons_%s512"):format(kit)
	return atlasExists(atlas) and atlas or nil
end

-- Paragon progress inside the current paragon round; a full round shows full rather than empty.
local function ParagonFrac(p)
	local value = p.value or 0
	local inRound = value % p.threshold
	if inRound == 0 and value > 0 then
		return 1, p.threshold
	end
	return inRound / p.threshold, inRound
end

-- Ring: progress inside the level (paragon progress once maxed), the badge and the colour.
function ns.Weekly_FactionRing(rec)
	local p = rec.paragon
	local badge = rec.level and tostring(rec.level) or nil
	if Maxed(rec) then
		if p and (p.threshold or 0) > 0 then
			return { frac = p.pending and 1 or min(ParagonFrac(p), 1), badge = badge, color = "gold",
				glow = p.pending == true }
		end
		return { frac = 1, badge = badge, color = "gold", glow = false }
	end
	local frac = (rec.threshold or 0) > 0 and min(max((rec.earned or 0) / rec.threshold, 0), 1) or 0
	return { frac = frac, badge = badge, color = rec.renown and "blue" or "white",
		glow = p ~= nil and p.pending == true }
end

function ns.Weekly_FactionDetail(rec)
	local d = { title = rec.name or "?" }
	local p = rec.paragon
	if not rec.renown then
		d.line1 = rec.standing or ""
		if p and p.pending then
			d.line2 = "Paragon reward waiting"
		elseif Maxed(rec) then
			d.line2 = "Max rank"
		else
			d.line2 = (rec.threshold or 0) > 0 and ("%s / %s"):format(Thousands(rec.earned), Thousands(rec.threshold)) or ""
		end
		return d
	end
	d.line1 = rec.max and ("Renown %d/%d"):format(rec.level, rec.max) or ("Renown %d"):format(rec.level)
	if Maxed(rec) then
		if p and p.pending then
			d.line2 = "Paragon reward waiting"
		elseif p and (p.threshold or 0) > 0 then
			local _, inRound = ParagonFrac(p)
			d.line2 = ("Paragon %s / %s"):format(Thousands(inRound), Thousands(p.threshold))
		else
			d.line2 = "Max renown"
		end
	else
		d.line2 = ("%s until next level"):format(Thousands((rec.threshold or 0) - (rec.earned or 0)))
	end
	return d
end

-- levels: C_MajorFactions.GetRenownLevels; rewardsFor(level): C_MajorFactions.GetRenownRewardsForLevel.
function ns.Weekly_RewardTrack(rec, levels, rewardsFor)
	local track = {}
	for _, info in ipairs(levels or {}) do
		local rewards = {}
		for _, r in ipairs(rewardsFor(info.level) or {}) do
			rewards[#rewards + 1] = { name = r.name or "?", icon = r.icon, uiOrder = r.uiOrder }
		end
		table.sort(rewards, function(a, b)
			if a.uiOrder and b.uiOrder and a.uiOrder ~= b.uiOrder then
				return a.uiOrder < b.uiOrder
			end
			return a.name < b.name
		end)
		track[#track + 1] = { level = info.level, earned = info.level <= (rec.level or 0), rewards = rewards }
	end
	return track
end

-- Parents in name order with their sub-factions (records with .parent) attached in the order they came.
function ns.Weekly_FactionLayout(recs)
	local byParent, parents = {}, {}
	for _, rec in ipairs(recs) do
		if rec.parent then
			byParent[rec.parent] = byParent[rec.parent] or {}
			table.insert(byParent[rec.parent], rec)
		else
			parents[#parents + 1] = rec
		end
	end
	table.sort(parents, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	local layout = {}
	for _, rec in ipairs(parents) do
		layout[#layout + 1] = { rec = rec, subs = byParent[rec.id] or {} }
	end
	return layout
end
