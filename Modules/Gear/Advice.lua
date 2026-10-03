local addonName, ns = ...

-- Gear Check advice (pure, unit-tested): which stat weights apply and what to tell the player about them, the best
-- gem for those weights, gem and enchant checks on worn items, and the off-spec line. Built-in scales and the gem
-- list live in Scales.lua.

local GEM_SLACK = 0.05 -- a socketed gem this much below the best one is fine (weights aren't that precise)
local STAT_LABELS = { -- also ns.GEAR_STAT_LABELS (Sheet.lua)
	CRIT = "Crit", HASTE = "Haste", MASTERY = "Mastery", VERS = "Versatility", STA = "Stamina",
	STR = "Strength", AGI = "Agility", INT = "Intellect",
}
ns.GEAR_STAT_LABELS = STAT_LABELS

---------------------------------------------------------------------------------------------------------------
-- Weights

-- Imported for this character beats built-in for the spec beats the fallback (main stat 1, secondaries 0.5).
-- Returns weights, source ("imported" | "builtin" | "none"), label.
function ns.Gear_ResolveWeights(saved, builtin, primary)
	if saved then
		return saved.weights, "imported", saved.name
	end
	if builtin then
		return builtin.weights, "builtin", builtin.label
	end
	return ns.Gear_DefaultWeights(primary), "none", nil
end

-- One-time chat hint for built-in weights. seen is what was already shown for this spec (saved): nil, "builtin",
-- or "stale:<season>". currentSeason is nil when the game can't say. Returns the hint kind and the new seen value,
-- or nil when there's nothing to say.
function ns.Gear_WeightsHint(source, builtin, seen, currentSeason)
	if source ~= "builtin" then
		return nil
	end
	if currentSeason and builtin.season and builtin.season < currentSeason then
		local key = "stale:" .. currentSeason
		if seen ~= key then
			return "stale", key
		end
		return nil
	end
	if seen == nil then
		return "builtin", "builtin"
	end
	return nil
end

-- "Haste, Mastery": the stats a gem gives, largest first.
function ns.Gear_StatLabel(stats)
	local list = {}
	for key, amount in pairs(stats or {}) do
		if key == "PRIMARY" then
			for p, a in pairs(amount) do
				list[#list + 1] = { STAT_LABELS[p] or p, a }
			end
		elseif STAT_LABELS[key] then
			list[#list + 1] = { STAT_LABELS[key], amount }
		end
	end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then
			return a[2] > b[2]
		end
		return a[1] < b[1]
	end)
	local names = {}
	for i, entry in ipairs(list) do
		names[i] = entry[1]
	end
	return table.concat(names, ", ")
end

---------------------------------------------------------------------------------------------------------------
-- Gems

-- gems: { { itemID, name, stats } } (stat gems only, stats normalized). Returns the best gem and its value.
function ns.Gear_BestGem(gems, weights, primary)
	local best, bestValue = nil, 0
	for _, gem in ipairs(gems or {}) do
		local value = ns.Gear_StatsScore(gem.stats, weights, primary)
		if value > bestValue then
			best, bestValue = gem, value
		end
	end
	return best, bestValue
end

-- Tooltip lines about an item's sockets. worn: also flag socketed gems clearly worse than the best one.
-- gemStats(itemID) returns a socketed gem's normalized stats, or nil while it isn't loaded. diamond: the unique
-- gem's name when none is worn (it's never ranked: most have an effect).
function ns.Gear_GemLines(desc, best, bestValue, worn, gemStats, weights, primary, diamond)
	local lines = {}
	if not best then
		return lines
	end
	local empty = math.max((desc.sockets or 0) - (desc.gems or 0), 0)
	if empty > 0 then
		local what = empty == 1 and "Empty socket" or (empty .. " empty sockets")
		lines[#lines + 1] = ("%s: best gem %s (%s)"):format(what, best.name, ns.Gear_StatLabel(best.stats))
		if diamond then
			lines[#lines + 1] = ("Or your one %s (sim which)"):format(diamond)
		end
	end
	if worn then
		local worse = 0
		for _, id in ipairs(desc.gemIDs or {}) do
			local stats = id ~= best.itemID and gemStats(id)
			if stats and ns.Gear_StatsScore(stats, weights, primary) < bestValue * (1 - GEM_SLACK) then
				worse = worse + 1
			end
		end
		if worse > 0 then
			lines[#lines + 1] = ("Gem: %s is better for your spec"):format(best.name)
		end
	end
	return lines
end

---------------------------------------------------------------------------------------------------------------
-- Worn gear

-- Slot a link is worn in, or nil.
function ns.Gear_WornSlot(link, equipped)
	for slot, desc in pairs(equipped) do
		if desc.link == link then
			return slot
		end
	end
	return nil
end

-- Whether any worn item has one of these gems socketed (ids: set of item IDs).
function ns.Gear_WearsGem(equipped, ids)
	for _, desc in pairs(equipped) do
		for _, id in ipairs(desc.gemIDs or {}) do
			if ids[id] then
				return true
			end
		end
	end
	return false
end

function ns.Gear_MissingEnchant(slot, desc)
	return ns.Gear_EnchantSlot(slot, desc.equipLoc) and not desc.enchanted
end

-- Counts over everything worn: { enchants = missing enchants, sockets = empty sockets }.
function ns.Gear_Audit(equipped)
	local result = { enchants = 0, sockets = 0 }
	for slot, desc in pairs(equipped) do
		if ns.Gear_MissingEnchant(slot, desc) then
			result.enchants = result.enchants + 1
		end
		result.sockets = result.sockets + math.max((desc.sockets or 0) - (desc.gems or 0), 0)
	end
	return result
end

-- Worn items with something missing, in slot order: { slot, link, enchant = missing enchant, empty = empty sockets }.
function ns.Gear_AuditList(equipped)
	local list = {}
	for slot, desc in pairs(equipped) do
		local enchant = ns.Gear_MissingEnchant(slot, desc)
		local empty = math.max((desc.sockets or 0) - (desc.gems or 0), 0)
		if enchant or empty > 0 then
			list[#list + 1] = { slot = slot, link = desc.link, enchant = enchant, empty = empty }
		end
	end
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return list
end

-- "Not enchanted, 2 empty sockets" for one AuditList entry.
function ns.Gear_AuditEntryText(entry)
	local parts = {}
	if entry.enchant then
		parts[#parts + 1] = "Not enchanted"
	end
	if entry.empty > 0 then
		parts[#parts + 1] = ("%d empty socket%s"):format(entry.empty, entry.empty == 1 and "" or "s")
	end
	return table.concat(parts, ", ")
end

-- "Gear: 2 missing enchants, 1 empty socket", or nil when nothing is missing.
function ns.Gear_AuditText(audit)
	local parts = {}
	if audit.enchants > 0 then
		parts[#parts + 1] = ("%d missing enchant%s"):format(audit.enchants, audit.enchants == 1 and "" or "s")
	end
	if audit.sockets > 0 then
		parts[#parts + 1] = ("%d empty socket%s"):format(audit.sockets, audit.sockets == 1 and "" or "s")
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------------------------------------------
-- Rank of a worn item ("your best", "your second best", "bag has better")

-- Whether an item gets ranked at all: trinkets and items with effects are valued by their effect, not stats.
function ns.Gear_Rankable(desc)
	return desc.equipLoc ~= "INVTYPE_TRINKET" and not desc.effect
end

-- Whether item can take the worn item's place: fits that slot (weapons: same kind), usable by the spec, rankable.
function ns.Gear_RankPeer(item, worn, slot, ctx)
	if item.link == worn.link or not ns.Gear_Rankable(item) then
		return false
	end
	if slot == 16 or slot == 17 then
		if item.equipLoc ~= worn.equipLoc then
			return false
		end
	else
		local fits = false
		for _, s in ipairs(ns.Gear_Slots(item.equipLoc) or {}) do
			fits = fits or s == slot
		end
		if not fits then
			return false
		end
	end
	return ns.Gear_Unusable(item, ctx) == nil
end

-- worn: the worn item in slot. others: the other worn item of the pair (rings) or nil. bag: bag items.
-- Returns rank (1 = best) and the best bag item that beats the worn one (or nil).
function ns.Gear_Rank(worn, slot, others, bag, ctx, score)
	local mine, rank = score(worn), 1
	local better, betterScore
	for _, item in ipairs(others) do
		if ns.Gear_RankPeer(item, worn, slot, ctx) and score(item) > mine then
			rank = rank + 1
		end
	end
	for _, item in ipairs(bag) do
		if ns.Gear_RankPeer(item, worn, slot, ctx) then
			local value = score(item)
			if value > mine then
				rank = rank + 1
				if not betterScore or value > betterScore then
					better, betterScore = item, value
				end
			end
		end
	end
	return rank, better
end

-- pairSize: 2 for rings, else 1. betterName: the bag item that beats it. Returns text, color key (or nil).
function ns.Gear_RankLine(specName, rank, pairSize, betterName)
	if rank == 1 then
		return specName .. ": your best", "green"
	elseif rank == 2 and pairSize == 2 then
		return specName .. ": your second best", "green"
	elseif betterName then
		return ("%s: bag has better (%s)"):format(specName, betterName), "orange"
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- Off-spec

-- "Also an upgrade for Marksmanship +4.0%", only for a plain upgrade (an empty slot says nothing about the spec).
function ns.Gear_OffspecLine(specName, verdict)
	if verdict and verdict.kind == "upgrade" and verdict.pct then
		return ("Also an upgrade for %s %+.1f%%"):format(specName, verdict.pct)
	end
	return nil
end
