local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_leveling.lua). What's
-- ready at the trainer, old spell ranks, ammo and reagents, quests sorted by what's worth doing, weapon skills. The game
-- is read in Read.lua; the page is Page.lua; Leveling.lua wires it up.

local WEAPON_BOWS, WEAPON_GUNS, WEAPON_CROSSBOW = 2, 3, 18 -- Enum.ItemWeaponSubclass
local AMMO_CLASS = 6 -- Enum.ItemClass.Projectile
local AMMO_ARROW, AMMO_BULLET = 2, 3 -- warcraft.wiki.gg ItemType: Projectile's subclasses
local AMMO_FOR = { [WEAPON_BOWS] = AMMO_ARROW, [WEAPON_CROSSBOW] = AMMO_ARROW, [WEAPON_GUNS] = AMMO_BULLET }
local AUTO_BUDGET_SHARE = 0.25 -- of your money, at most, on one automatic ammo purchase
-- Enum.RelativeContentDifficulty.
local TRIVIAL, EASY, FAIR = 0, 1, 2
-- role: the group's heading and quest levels. textRole: its quest titles, fading as a quest is worth less.
ns.LEVELING_QUEST_GROUPS = {
	{ key = "done", name = "Ready to turn in", role = "success", textRole = "text" },
	{ key = "timed", name = "On a timer", role = "warning", textRole = "text" },
	{ key = "now", name = "Worth doing now", role = "accent", textRole = "text" },
	{ key = "hard", name = "Hard or elite: a group helps", role = "danger", textRole = "text" },
	{ key = "easy", name = "Easy", role = "textMuted", textRole = "textMuted" },
	{ key = "grey", name = "Grey: little XP left", role = "textFaint", textRole = "textFaint" },
}
local ICONS = {
	turnIns = "Interface\\Icons\\INV_Misc_Note_01",
	trainer = "Interface\\Icons\\INV_Misc_Book_09",
	talents = "Interface\\Icons\\Ability_Marksmanship",
	ranks = "Interface\\Icons\\INV_Misc_Book_11",
	reagents = "Interface\\Icons\\INV_Misc_Dust_02",
	ammo = "Interface\\Icons\\INV_Ammo_Arrow_02",
}

-- Trainer --------------------------------------------------------------------------------------------------------------

-- A trainer's row as saved: rows you've learned and headers are nil. serviceType: "available" | "unavailable" | "used" |
-- "header" (GetTrainerServiceInfo).
function ns.Leveling_SlimService(name, serviceType, rank, level, cost)
	if not name or (serviceType ~= "available" and serviceType ~= "unavailable") then
		return nil
	end
	return { name = name, rank = rank ~= "" and rank or nil, level = level or 0, cost = cost or 0 }
end

local function ByLevelThenName(a, b)
	if a.level ~= b.level then
		return a.level < b.level
	end
	return a.name < b.name
end

-- What can be learned at this level, and what comes next: the lowest level above it with anything, and its rows.
function ns.Leveling_TrainerSplit(services, level)
	local ready, later = {}, {}
	for _, s in ipairs(services or {}) do
		if s.level <= level then
			ready[#ready + 1] = s
		else
			later[#later + 1] = s
		end
	end
	table.sort(ready, ByLevelThenName)
	table.sort(later, ByLevelThenName)
	local nextLevel = later[1] and later[1].level
	local upcoming = {}
	for _, s in ipairs(later) do
		if s.level == nextLevel then
			upcoming[#upcoming + 1] = s
		end
	end
	return ready, nextLevel, upcoming
end

-- What to save after a visit. seesLater: the trainer's "not available yet" filter is on, so rows is the whole list. With
-- it off only what's learnable shows: rows for later levels from the last visit stay.
function ns.Leveling_MergeTrainer(old, rows, level, seesLater)
	local merged = {}
	for _, s in ipairs(rows) do
		merged[#merged + 1] = s
	end
	if not seesLater then
		for _, s in ipairs(old or {}) do
			if s.level > level then
				merged[#merged + 1] = s
			end
		end
	end
	return merged
end

-- Copper for a list of rows.
function ns.Leveling_TrainerCost(rows)
	local total = 0
	for _, s in ipairs(rows) do
		total = total + s.cost
	end
	return total
end

-- "Frostbolt (Rank 2)".
function ns.Leveling_ServiceName(s)
	return s.rank and (s.name .. " (" .. s.rank .. ")") or s.name
end

-- Names joined, with "and 2 more" past max.
function ns.Leveling_JoinNames(names, max)
	local shown = {}
	for i = 1, math.min(#names, max) do
		shown[i] = names[i]
	end
	local text = table.concat(shown, ", ")
	if #names > max then
		text = ("%s and %d more"):format(text, #names - max)
	end
	return text
end

-- Bars ------------------------------------------------------------------------------------------------------------------

-- actions: { { spellID, name, subtext, highest, consumable, count } } from the action bars. A spell on two bars counts once.
-- Old ranks by name: "Frostbolt (Rank 1)".
function ns.Leveling_OldRanks(actions)
	local seen, list = {}, {}
	for _, a in ipairs(actions) do
		if a.highest == false and a.name and not seen[a.spellID] then
			seen[a.spellID] = true
			list[#list + 1] = (a.subtext and a.subtext ~= "") and (a.name .. " (" .. a.subtext .. ")") or a.name
		end
	end
	table.sort(list)
	return list
end

-- Spells that use a reagent with low casts or fewer left: { { name, count } }, fewest first. A name once, at its lowest:
-- ranks of a spell usually share a reagent.
function ns.Leveling_LowReagents(actions, low)
	local byName = {}
	for _, a in ipairs(actions) do
		if a.consumable and a.name and a.count and a.count <= low then
			if not byName[a.name] or a.count < byName[a.name] then
				byName[a.name] = a.count
			end
		end
	end
	local list = {}
	for name, count in pairs(byName) do
		list[#list + 1] = { name = name, count = count }
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count < b.count
		end
		return a.name < b.name
	end)
	return list
end

-- Ammo --------------------------------------------------------------------------------------------------------------------

-- The ammo a ranged weapon fires (ItemProjectile subclass), nil for thrown weapons, wands and no weapon.
function ns.Leveling_AmmoFor(weaponSubclass)
	return AMMO_FOR[weaponSubclass]
end

-- "none" | "low" | "ok", nil when this character doesn't use ammo.
function ns.Leveling_AmmoState(needs, count, low)
	if not needs then
		return nil
	end
	if (count or 0) <= 0 then
		return "none"
	end
	return count <= low and "low" or "ok"
end

-- The merchant's best ammo for this weapon: the highest level you can use and, when money is given, afford a stack of.
-- items: { { index, classID, subclassID, minLevel, price, usable } }. Nil when none fits.
function ns.Leveling_PickAmmo(items, weaponSubclass, level, money)
	local wanted, best = AMMO_FOR[weaponSubclass], nil
	if not wanted then
		return nil
	end
	for _, item in ipairs(items) do
		if item.classID == AMMO_CLASS and item.subclassID == wanted and item.usable ~= false
			and (item.minLevel or 0) <= level and (not money or (item.price or 0) <= money) then
			if not best or (item.minLevel or 0) > (best.minLevel or 0) then
				best = item
			end
		end
	end
	return best
end

-- How much of an ammo fits. bags: { { family, free, topUp } } for the bags that take it; topUp is the room left in its
-- part stacks. Returns the room in ammo bags (quivers, pouches; nil without one) and the room in ordinary bags.
function ns.Leveling_AmmoRoom(bags, maxStack)
	local ammoRoom, normalRoom = nil, 0
	for _, bag in ipairs(bags) do
		local room = bag.free * maxStack + (bag.topUp or 0)
		if (bag.family or 0) ~= 0 then
			ammoRoom = (ammoRoom or 0) + room
		else
			normalRoom = normalRoom + room
		end
	end
	return ammoRoom, normalRoom
end

-- How many to buy and what that costs. An ammo bag is filled and never overflows into your other bags; without one, you
-- buy up to target as far as your bags hold it. Either way as many as money and the merchant's stock allow. item: { price
-- (per stack of stack), stack, available (above 0 when the stock is limited) }.
function ns.Leveling_AmmoFill(item, ammoRoom, normalRoom, have, target, money)
	local amount = ammoRoom or math.min(target - have, normalRoom)
	if item.available and item.available > 0 then
		amount = math.min(amount, item.available)
	end
	local price, stack = item.price or 0, item.stack or 1
	if price > 0 then
		amount = math.min(amount, math.floor(money * stack / price))
	end
	amount = math.max(amount, 0)
	return amount, math.ceil(price * amount / stack)
end

-- What buying automatically may spend: a share of your money, so a visit you didn't think about can't empty your purse.
function ns.Leveling_AutoBudget(money)
	return math.floor(money * AUTO_BUDGET_SHARE)
end

-- An amount as the purchases that make it up, each at most maxBuy (the game's limit for one purchase).
function ns.Leveling_BuyBatches(amount, maxBuy)
	local batches = {}
	while amount > 0 do
		local n = math.min(amount, maxBuy)
		batches[#batches + 1] = n
		amount = amount - n
	end
	return batches
end

-- What a toast says about supplies that just ran low: title, text, icon. entries: { kind = "ammo", out (none left), name
-- (the item's, nil until it has loaded), countText, icon } and { kind = "reagent", name (the spell's), count }.
function ns.Leveling_SupplyToast(entries)
	local ammo, hasReagents, lines = nil, false, {}
	for _, e in ipairs(entries) do
		if e.kind == "ammo" then
			ammo = e
			if not e.out then
				lines[#lines + 1] = ("%s: %s left."):format(e.name or "Ammo", e.countText)
			end
		else
			hasReagents = true
			lines[#lines + 1] = ("%s: %d %s left."):format(e.name, e.count, e.count == 1 and "cast" or "casts")
		end
	end
	if ammo then
		lines[#lines + 1] = "Buy more at a vendor."
	end
	local title
	if ammo and ammo.out then
		title = hasReagents and "Out of ammo, low on reagents" or "Out of ammo"
	elseif ammo then
		title = hasReagents and "Low on ammo and reagents" or "Low on ammo"
	else
		title = "Low on reagents"
	end
	return title, table.concat(lines, " "), ammo and (ammo.icon or ICONS.ammo) or ICONS.reagents
end

-- Warning once: which keys are low now and weren't before. prev and the returned table: [key] = true.
function ns.Leveling_NewlyLow(prev, keys)
	local now, fresh = {}, {}
	for _, key in ipairs(keys) do
		now[key] = true
		if not prev[key] then
			fresh[#fresh + 1] = key
		end
	end
	return fresh, now
end

-- Quests --------------------------------------------------------------------------------------------------------------

local function QuestGroup(q)
	if q.complete then
		return "done"
	elseif q.timeLeft then
		return "timed"
	elseif q.elite or (q.difficulty and q.difficulty > FAIR) then
		return "hard"
	elseif q.difficulty == TRIVIAL then
		return "grey"
	elseif q.difficulty == EASY then
		return "easy"
	end
	return "now"
end
ns.Leveling_QuestGroup = QuestGroup

-- quests: { { questID, title, level, difficulty, elite, complete, timeLeft } }. Returns { [group key] = rows }, each sorted by
-- level, shortest timer first in "timed".
function ns.Leveling_SortQuests(quests)
	local groups = {}
	for _, g in ipairs(ns.LEVELING_QUEST_GROUPS) do
		groups[g.key] = {}
	end
	for _, q in ipairs(quests) do
		local list = groups[QuestGroup(q)]
		list[#list + 1] = q
	end
	for key, list in pairs(groups) do
		table.sort(list, function(a, b)
			if key == "timed" and a.timeLeft ~= b.timeLeft then
				return a.timeLeft < b.timeLeft
			end
			if (a.level or 0) ~= (b.level or 0) then
				return (a.level or 0) < (b.level or 0)
			end
			return (a.title or "") < (b.title or "")
		end)
	end
	return groups
end

-- "12s", "4m", "1h 5m".
function ns.Leveling_TimeLeft(seconds)
	if seconds < 60 then
		return ("%ds"):format(seconds)
	elseif seconds < 3600 then
		return ("%dm"):format(math.floor(seconds / 60))
	end
	return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- XP ---------------------------------------------------------------------------------------------------------------------

local function Share(value, max)
	return math.min(math.max(value / max, 0), 1)
end

-- Where the XP bar's parts end (0..1) and how far there is to go; nil when there's no XP to earn. rested and turnIn: XP
-- beyond what you have, each counted from your current XP. reachesLevel: turning in what's ready is enough to level.
function ns.Leveling_XPView(xp, xpMax, rested, turnIn)
	if not xpMax or xpMax <= 0 then
		return nil
	end
	xp, rested, turnIn = xp or 0, rested or 0, turnIn or 0
	return {
		fraction = Share(xp, xpMax),
		percent = math.floor(Share(xp, xpMax) * 100),
		toGo = math.max(xpMax - xp, 0),
		rested = rested,
		restedEnd = Share(xp + rested, xpMax),
		turnIn = turnIn,
		turnInEnd = Share(xp + turnIn, xpMax),
		reachesLevel = turnIn > 0 and xp + turnIn >= xpMax,
	}
end

-- To do --------------------------------------------------------------------------------------------------------------

-- What's waiting, most useful first, and the checks that came up clean. s: { visited (the trainer list is saved), ready
-- (trainer rows), talents, oldRanks (names), reagents ({ name, count }), ammoState, ammoText, turnIns (quest rows) }.
-- Returns todo: { { key, icon, text, sub, role, cost (copper), xp } } and fine: "All fine: ..." or nil.
function ns.Leveling_Checklist(s)
	local todo, clean = {}, {}
	local function Add(key, text, sub, role, cost, xp)
		todo[#todo + 1] = { key = key, icon = ICONS[key], text = text, sub = sub, role = role or "text", cost = cost, xp = xp }
	end

	if #s.turnIns > 0 then
		local names, xp = {}, 0
		for i, q in ipairs(s.turnIns) do
			names[i] = q.title or "?"
			xp = xp + (q.xp or 0)
		end
		Add("turnIns", #names == 1 and "1 quest to turn in" or ("%d quests to turn in"):format(#names),
			ns.Leveling_JoinNames(names, 2), "success", nil, xp > 0 and xp or nil)
	end

	if not s.visited then
		Add("trainer", "Visit your class trainer once", "Then Tomte can say what's new at each level.")
	elseif #s.ready > 0 then
		local names = {}
		for i, row in ipairs(s.ready) do
			names[i] = ns.Leveling_ServiceName(row)
		end
		Add("trainer", ("%d new at your class trainer"):format(#names), ns.Leveling_JoinNames(names, 3), "success",
			ns.Leveling_TrainerCost(s.ready))
	else
		clean[#clean + 1] = "trainer"
	end

	if s.talents then
		Add("talents", "Talent points to spend", "Open your talents and spend them.", "warning")
	else
		clean[#clean + 1] = "talents"
	end

	if #s.oldRanks > 0 then
		Add("ranks", #s.oldRanks == 1 and "An old rank on your bars" or ("%d old ranks on your bars"):format(#s.oldRanks),
			ns.Leveling_JoinNames(s.oldRanks, 3), "warning")
	else
		clean[#clean + 1] = "spell ranks"
	end

	if #s.reagents > 0 then
		local parts = {}
		for i, r in ipairs(s.reagents) do
			parts[i] = ("%s: %d %s"):format(r.name, r.count, r.count == 1 and "cast" or "casts")
		end
		Add("reagents", "Low on reagents", ns.Leveling_JoinNames(parts, 2), "warning")
	end

	if s.ammoState == "none" then
		Add("ammo", "Out of ammo", "Buy more at a vendor.", "danger")
	elseif s.ammoState == "low" then
		Add("ammo", ("Low on ammo: %s left"):format(s.ammoText), "Buy more at a vendor.", "warning")
	elseif s.ammoState == "ok" then
		clean[#clean + 1] = ("ammo (%s)"):format(s.ammoText)
	end

	return todo, #clean > 0 and ("All fine: " .. table.concat(clean, ", ")) or nil
end

-- Weapon skills --------------------------------------------------------------------------------------------------------

-- skills: { { name, rank, max, worn } }. Those at least gap behind, worn weapons first, then furthest behind.
function ns.Leveling_SkillsBehind(skills, gap)
	local list = {}
	for _, s in ipairs(skills) do
		if s.max > 0 and s.max - s.rank >= gap then
			list[#list + 1] = s
		end
	end
	table.sort(list, function(a, b)
		if (a.worn or false) ~= (b.worn or false) then
			return a.worn == true
		end
		if a.max - a.rank ~= b.max - b.rank then
			return a.max - a.rank > b.max - b.rank
		end
		return a.name < b.name
	end)
	return list
end
