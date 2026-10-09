local addonName, ns = ...

-- Gear Check advice (pure, unit-tested): which stat weights apply and what to tell the player about them, the best
-- gem for those weights, gem and enchant checks on worn items, the off-spec line, the evaluator context for any
-- character, and upgrades for alts (bind state, who counts, their verdict and lines). Built-in sets (weights, gems)
-- live in Data/<Expansion>/Gear.lua, read through Scales.lua.

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

-- The weights for any character and spec: weightsByGuid is the saved db.weights ([guid][specID] = imported),
-- scales is the character's built-in set (Gear_ScalesFor). Same order and returns as Gear_ResolveWeights. Works for another character's guid
-- and spec too (alts).
function ns.Gear_WeightsFor(weightsByGuid, guid, specID, primary, scales)
	local mine = weightsByGuid and guid and weightsByGuid[guid]
	return ns.Gear_ResolveWeights(mine and mine[specID], scales and scales.specs[specID], primary)
end

-- Built-in weights from class guides rather than sims (healers, Augmentation): their label says so.
function ns.Gear_IsGuideLabel(label)
	return type(label) == "string" and label:find("^guide priority") ~= nil
end

-- Where weights come from, for /tomte gear weights and the settings row: 'imported "Name"', "built-in, <label>"
-- (guide weights add ": import a sim for better"), or nil for none.
function ns.Gear_SourceText(source, label)
	if source == "imported" then
		return ("imported \"%s\""):format(label or "Raidbots")
	elseif source == "builtin" then
		return "built-in, " .. (label or "") .. (ns.Gear_IsGuideLabel(label) and ": import a sim for better" or "")
	end
	return nil
end

local function AtMax(level, maxLevel)
	return level ~= nil and maxLevel ~= nil and level >= maxLevel
end

-- One-time chat hint for built-in weights, only at max level (built-in is fine while leveling). seen is what was
-- already said for this character and spec (saved): nil, "builtin" (the old any-level hint, which doesn't count),
-- "max", or "stale:<season>". currentSeason is nil when the game can't say. Returns the hint kind ("max" |
-- "stale") and the new seen value, or nil when there's nothing to say.
-- Stale only for a set that isn't final: the display season is global (a War Within character on a Midnight
-- client sees Midnight's season), and a final set is its expansion's last season, so nothing newer exists for it.
function ns.Gear_WeightsHint(source, builtin, seen, currentSeason, level, maxLevel)
	if source ~= "builtin" or not AtMax(level, maxLevel) then
		return nil
	end
	if currentSeason and builtin.season and not builtin.final and builtin.season < currentSeason then
		local key = "stale:" .. currentSeason
		if seen ~= key then
			return "stale", key
		end
		return nil
	end
	if seen == nil or seen == "builtin" then
		return "max", "max"
	end
	return nil
end

-- Next up's "Sim on Raidbots": built-in weights at max level.
function ns.Gear_SimSuggested(source, level, maxLevel)
	return source == "builtin" and AtMax(level, maxLevel)
end

-- db.hinted used to be [specID] = seen for the whole account; now it's [guid][specID]. Moves the old keys for
-- this character's class (specIDs: { [specID] = true }) to guid; other classes' keys wait for one of theirs.
-- Returns the character's table.
function ns.Gear_MigrateHinted(hinted, guid, specIDs)
	hinted[guid] = hinted[guid] or {}
	local mine = hinted[guid]
	for key, seen in pairs(hinted) do
		if type(key) == "number" and specIDs[key] then
			if mine[key] == nil then
				mine[key] = seen
			end
			hinted[key] = nil
		end
	end
	return mine
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

---------------------------------------------------------------------------------------------------------------
-- Context for any character

-- The evaluator context for a spec ({ id, name, primary }) of a character (guid, class token): its imported weights
-- (weightsByGuid = the saved db.weights) or the built-in ones, armor type from the class, best gem out of gems
-- ({ { itemID, name, stats } }, the loaded ones). nil without spec.id or spec.primary. Gear.lua's ContextFor.
function ns.Gear_BuildContext(spec, guid, classToken, weightsByGuid, scales, gems)
	if not (spec and spec.id and spec.primary) then
		return nil
	end
	local weights, source, label = ns.Gear_WeightsFor(weightsByGuid, guid, spec.id, spec.primary, scales)
	local best, bestValue = ns.Gear_BestGem(gems, weights, spec.primary)
	return {
		spec = spec,
		primary = spec.primary,
		weights = weights,
		source = source,
		label = label,
		noWeights = source == "none",
		armorSubclass = ns.Gear_ArmorForClass(classToken),
		specID = spec.id,
		best = best,
		bestValue = bestValue,
		gemValue = best and bestValue or nil,
	}
end

-- The spec of a stored character (Alts' chars[guid]: specID, spec = its name, primary), nil when not read yet.
function ns.Gear_CharSpec(c)
	if not (c and c.specID and c.primary) then
		return nil
	end
	return { id = c.specID, name = c.spec or "?", primary = c.primary }
end

---------------------------------------------------------------------------------------------------------------
-- Upgrades for alts (Alts.lua): which items can get to another character, which characters count, the verdict for
-- one of them and the tooltip lines.

ns.GEAR_ALT_STALE_DAYS = 60 -- characters not played for longer are left out (their gear snapshot is old)

-- Enum.ItemBind (GetItemInfo's 14th return): None 0, OnAcquire 1, OnEquip 2, OnUse 3, Quest 4, ToWoWAccount 7,
-- ToBnetAccount 8, ToBnetAccountUntilEquipped 9.
local BIND_ACCOUNT = { [7] = true, [8] = true }
local BIND_FREE = { [0] = true, [2] = true, [3] = true }
local BIND_UNTIL_EQUIP = 9

-- An item's bind state: "warbound" (bound to the account), "warboundUntilEquip", "boe" (Bind on Equip or Use and not
-- bound yet, or never binds), "soulbound" (bound to a character, or binds on pickup), nil while unknown.
-- bindType: Enum.ItemBind, nil while the item isn't loaded. bound: C_Item.IsBound (soul- or account-bound) for an
-- item you hold; nil for a bare link (vendor, quest reward, auction), which isn't bound to anyone yet.
-- untilEquip: C_Item.IsBoundToAccountUntilEquip for an item you hold.
function ns.Gear_BindState(bindType, bound, untilEquip)
	if untilEquip then
		return "warboundUntilEquip"
	elseif bindType == nil then
		return nil
	elseif BIND_ACCOUNT[bindType] then
		return "warbound"
	elseif bound then
		return "soulbound" -- includes Bind on Equip and Warbound until equipped items that have been worn
	elseif bindType == BIND_UNTIL_EQUIP then
		return "warboundUntilEquip"
	elseif BIND_FREE[bindType] then
		return "boe"
	end
	return "soulbound"
end

-- The bind state from tooltip lines (the displayed item's own: a worn Bind on Equip item says "Soulbound").
-- known: [line text] = state, from Blizzard's global strings (Items.lua). First match, nil when none.
function ns.Gear_BindStateFromLines(texts, known)
	for _, text in ipairs(texts) do
		if known[text] then
			return known[text]
		end
	end
	return nil
end

-- How an item gets to another character: "mail" (Bind on Equip, not bound), "warband" (warbound, through the
-- Warband bank), nil when it can't (soulbound) or the state is unknown.
function ns.Gear_TransferRoute(state)
	if state == "boe" then
		return "mail"
	elseif state == "warbound" or state == "warboundUntilEquip" then
		return "warband"
	end
	return nil
end

-- The characters to judge items for, by name: not me, with a stored spec and worn gear, played in the last 60
-- days; mode "max" only those atMax(level) says are at max level (their content expansion's), "off" nobody. now and
-- seen are server times.
function ns.Gear_AltsToJudge(chars, me, now, mode, atMax)
	local list = {}
	if mode == "off" then
		return list
	end
	local oldest = now - ns.GEAR_ALT_STALE_DAYS * 86400
	for guid, c in pairs(chars or {}) do
		if guid ~= me and c.gear and ns.Gear_CharSpec(c) and c.seen and c.seen >= oldest
			and (mode ~= "max" or (atMax ~= nil and c.level ~= nil and atMax(c.level))) then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- The verdict for another character. cand's red tooltip text describes the character you're on (its level, its
-- weapon skills), so it's left out; that character's own level is checked against the item's instead. Armor type,
-- main stat and spec come from ctx, unique limits and set pieces from equipped (their worn gear).
function ns.Gear_AltVerdict(cand, equipped, ctx, level)
	if cand.minLevel and level and cand.minLevel > level then
		return { kind = "notForYou", why = ("requires level %d"):format(cand.minLevel), reasons = {} }
	end
	local copy = {}
	for k, v in pairs(cand) do
		copy[k] = v
	end
	copy.redText = nil
	ctx.specOK = cand.specs == nil or cand.specs[ctx.specID] == true
	return ns.Gear_Evaluate(copy, equipped, ctx)
end

-- "+8.2%", or why a clean upgrade has no percentage.
function ns.Gear_AltGain(v)
	if v.kind == "empty" then
		return "empty slot"
	elseif v.kind == "noStats" then
		return "theirs has no stats"
	end
	return ("%+.1f%%"):format(v.pct or 0)
end

-- results: { { name, spec, verdict } }, sorted in place: biggest first (an empty slot or stat-less gear first of
-- all), then by name.
function ns.Gear_SortAltUpgrades(results)
	local function Value(r)
		return r.verdict.pct or math.huge
	end
	table.sort(results, function(a, b)
		local va, vb = Value(a), Value(b)
		if va ~= vb then
			return va > vb
		end
		return (a.name or "") < (b.name or "")
	end)
	return results
end

-- Tooltip lines for sorted results: "Upgrade for Mira (Holy): +8.2%" for the first max, then "+n more" (or nil).
function ns.Gear_AltLines(results, max)
	local lines = {}
	for i = 1, math.min(#results, max) do
		local r = results[i]
		lines[i] = ("Upgrade for %s (%s): %s"):format(r.name or "?", r.spec or "?", ns.Gear_AltGain(r.verdict))
	end
	local more = #results > max and ("+%d more"):format(#results - max) or nil
	return lines, more
end
