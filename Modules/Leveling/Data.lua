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
	kits = "Interface\\Icons\\INV_Misc_ArmorKit_17",
	professions = "Interface\\Icons\\INV_Misc_Book_08",
	dungeons = "Interface\\Icons\\INV_Misc_Key_03",
	mount = "Interface\\Icons\\Ability_Mount_BlackDireWolf",
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
-- Old ranks by name: "Frostbolt (Rank 1)". Only a spell with a rank in its subtext: the game also says "not the highest"
-- for Tame Beast, which has no ranks (seen on Forever). A number, as "Rank" is translated and "Racial" has none.
function ns.Leveling_OldRanks(actions)
	local seen, list = {}, {}
	for _, a in ipairs(actions) do
		if a.highest == false and a.name and a.subtext and a.subtext:find("%d") and not seen[a.spellID] then
			seen[a.spellID] = true
			list[#list + 1] = a.name .. " (" .. a.subtext .. ")"
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

-- Whether the ammo helpers care about this character. Any class with a bow or gun "uses ammo" to the game, but only
-- hunters live on it; a rogue or warrior counts only while they keep ammo loaded, so an empty slot never nags them.
-- classFile: UnitClass's second return ("HUNTER").
function ns.Leveling_CaresAboutAmmo(classFile, loaded)
	return classFile == "HUNTER" or loaded == true
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

-- Armor kits -----------------------------------------------------------------------------------------------------------

-- Where a kit goes, in the order the button fills them. slot: the inventory slot (INVSLOT_CHEST and so on).
ns.LEVELING_KIT_SLOTS = {
	{ slot = 5, label = "chest" },
	{ slot = 7, label = "legs" },
	{ slot = 10, label = "hands" },
	{ slot = 8, label = "feet" },
}

-- The enchant on an item, from its link ("item:ID:enchant:..."): nil when there's none. An armor kit counts as one.
function ns.Leveling_ItemEnchant(link)
	if type(link) ~= "string" then
		return nil
	end
	local enchant = tonumber(link:match("item:%-?%d+:(%-?%d*)") or "")
	return enchant and enchant ~= 0 and enchant or nil
end

-- The worn pieces with nothing on them. gear: { { slot, label, name, link } }. A piece whose link can't be read isn't offered.
function ns.Leveling_EmptyGear(gear)
	local empty = {}
	for _, piece in ipairs(gear) do
		if type(piece.link) == "string" and not ns.Leveling_ItemEnchant(piece.link) then
			empty[#empty + 1] = piece
		end
	end
	return empty
end

-- What a press does: { kit, slot, label, gear (its name), empty }, or nil when there's nothing to do. kits: what you carry,
-- best first: { { itemID, name, count, minLevel } }.
function ns.Leveling_KitPlan(kits, gear, level)
	local empty = ns.Leveling_EmptyGear(gear)
	if #empty == 0 then
		return nil
	end
	for _, kit in ipairs(kits) do
		if (kit.count or 0) > 0 and (kit.minLevel or 0) <= level then
			local piece = empty[1]
			return { kit = kit, slot = piece.slot, label = piece.label, gear = piece.name, empty = empty }
		end
	end
	return nil
end

-- As a poison on a weapon: the item waits for a target, then /use picks the slot.
function ns.Leveling_KitMacro(itemID, slot)
	return ("/use item:%d\n/use %d"):format(itemID, slot)
end

function ns.Leveling_KitPieces(empty)
	local labels = {}
	for i, piece in ipairs(empty) do
		labels[i] = piece.label
	end
	return table.concat(labels, ", ")
end

-- The line on a kit's tooltip.
function ns.Leveling_KitTipLine(empty)
	if #empty == 0 then
		return "Nothing empty to put it on"
	end
	return "Can go on: " .. ns.Leveling_KitPieces(empty)
end

-- Ammo counter ---------------------------------------------------------------------------------------------------------

-- Whether an item is ammo at all, so the bag scan can skip the rest.
function ns.Leveling_IsAmmo(classID)
	return classID == AMMO_CLASS
end

-- Whether this ammo goes with this weapon.
function ns.Leveling_AmmoFitsWeapon(subclassID, weaponSubclass)
	return AMMO_FOR[weaponSubclass] ~= nil and AMMO_FOR[weaponSubclass] == subclassID
end

-- Every ammo carried, one row per kind, what you can fire first and then the best: { itemID, name, count, fits }. items: {
-- itemID, name, count, subclassID, minLevel, itemLevel }, one per bag slot.
function ns.Leveling_AmmoTypes(items, weaponSubclass, level)
	local byID, types = {}, {}
	for _, item in ipairs(items) do
		local row = byID[item.itemID]
		if row then
			row.count = row.count + item.count
		else
			row = { itemID = item.itemID, name = item.name, count = item.count, minLevel = item.minLevel or 0,
				itemLevel = item.itemLevel or 0,
				fits = ns.Leveling_AmmoFitsWeapon(item.subclassID, weaponSubclass) and (item.minLevel or 0) <= level }
			byID[item.itemID] = row
			types[#types + 1] = row
		end
	end
	table.sort(types, function(a, b)
		if a.fits ~= b.fits then
			return a.fits
		elseif a.minLevel ~= b.minLevel then
			return a.minLevel > b.minLevel
		elseif a.itemLevel ~= b.itemLevel then
			return a.itemLevel > b.itemLevel
		end
		return a.itemID < b.itemID
	end)
	return types
end

-- The ammo a click equips: the one after what's equipped, round and round, so the first click from anything else is the
-- best and you can still get back to the cheap one you were saving it with. nil when there's nothing else to switch to.
function ns.Leveling_AmmoNext(types, equippedID)
	local usable = {}
	for _, row in ipairs(types) do
		if row.fits then
			usable[#usable + 1] = row
		end
	end
	if #usable == 0 then
		return nil
	end
	for i, row in ipairs(usable) do
		if row.itemID == equippedID then
			local following = usable[i % #usable + 1]
			return following ~= row and following or nil
		end
	end
	return usable[1]
end

-- What the counter shows, nil when this character has no use for ammo. count: of what's in the slot. equippedFits: it goes
-- with your weapon, as a bow can't fire bullets however many you have. canSwitch: a click would equip something.
function ns.Leveling_AmmoView(needs, count, low, equippedFits, canSwitch)
	if not needs then
		return nil
	end
	local usable = equippedFits and count or 0
	local state = ns.Leveling_AmmoState(needs, usable, low)
	if state == "none" then
		return { count = usable, role = "danger", hint = canSwitch and "Click to switch" or "No ammo" }
	end
	return { count = usable, role = state == "low" and "warning" or "text" }
end

function ns.Leveling_AmmoMacro(itemID)
	return ("/equip item:%d"):format(itemID)
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

-- Professions, quests to hand in, the mount fund, dungeons ------------------------------------------------------------

-- A profession's cap and the rank that lifts it: Classic's ranks and the levels they need (Journeyman 10, Expert 20,
-- Artisan 35), not confirmed on Forever.
local NEXT_RANK = { [75] = { "Journeyman", 10 }, [150] = { "Expert", 20 }, [225] = { "Artisan", 35 } }
local MOUNT_FROM = 30 -- the level the mount fund shows from: ten levels to save before riding at 40
local DUNGEON_NEAR = 3 -- levels outside a dungeon's range that still count as near (as Groups in chat's filter)

-- Professions at their cap: { { name, skill, max, rank (the next rank's name), needLevel, ready } }. profs: { { name,
-- skill, max } }.
function ns.Leveling_ProfessionRanks(profs, level)
	local list = {}
	for _, p in ipairs(profs) do
		local nextRank = NEXT_RANK[p.max]
		if nextRank and p.skill >= p.max then
			list[#list + 1] = { name = p.name, skill = p.skill, max = p.max, rank = nextRank[1], needLevel = nextRank[2],
				ready = level >= nextRank[2] }
		end
	end
	return list
end

-- "The Barrens: 2, Mulgore: 1": finished quests by the quest log heading they're under, most first. nil without any.
function ns.Leveling_TurnInPlaces(quests)
	local counts, order = {}, {}
	for _, q in ipairs(quests) do
		if q.zone then
			if not counts[q.zone] then
				order[#order + 1] = q.zone
			end
			counts[q.zone] = (counts[q.zone] or 0) + 1
		end
	end
	if #order == 0 then
		return nil
	end
	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	local parts = {}
	for i, zone in ipairs(order) do
		parts[i] = ("%s: %d"):format(zone, counts[zone])
	end
	return table.concat(parts, ", ")
end

-- Saving for riding at 40: { goal, left (copper), hours (at perHour copper an hour, one decimal; nil without a pace or
-- with nothing left) }, or nil below MOUNT_FROM, with a mount or with the goal (gold) set to 0.
function ns.Leveling_MountFund(money, goalGold, level, mounts, perHour)
	if not goalGold or goalGold <= 0 or level < MOUNT_FROM or (mounts or 0) > 0 then
		return nil
	end
	local goal = goalGold * 10000
	local left = math.max(goal - money, 0)
	local hours = perHour and perHour > 0 and left > 0 and math.floor(left / perHour * 10 + 0.5) / 10 or nil
	return { goal = goal, have = money, left = left, hours = hours }
end

-- Dungeons near your level with quests in your log (the log files them under the dungeon's name): { { name, min, max,
-- quests } }, the most quests first.
function ns.Leveling_DungeonsNear(dungeons, level, quests)
	local counts = {}
	for _, q in ipairs(quests) do
		if q.zone then
			counts[q.zone] = (counts[q.zone] or 0) + 1
		end
	end
	local list = {}
	for _, d in ipairs(dungeons) do
		local n = counts[d.name] or 0
		if n > 0 and level >= d.min - DUNGEON_NEAR and level <= d.max + DUNGEON_NEAR then
			list[#list + 1] = { name = d.name, min = d.min, max = d.max, quests = n }
		end
	end
	table.sort(list, function(a, b)
		return a.quests > b.quests
	end)
	return list
end

-- To do --------------------------------------------------------------------------------------------------------------

-- What's waiting, most useful first, and the checks that came up clean. s: { visited (the trainer list is saved), ready
-- (trainer rows), talents, oldRanks (names), reagents ({ name, count }), ammoState, ammoText, turnIns (quest rows), kit (the
-- armor kit plan, or nil) }.
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
			ns.Leveling_TurnInPlaces(s.turnIns) or ns.Leveling_JoinNames(names, 2), "success", nil, xp > 0 and xp or nil)
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

	if s.kit then
		local count = #s.kit.empty
		Add("kits", ("%s could take your %s"):format(count == 1 and "1 piece" or (count .. " pieces"), s.kit.kit.name or "armor kit"),
			"Use the armor kit button: " .. ns.Leveling_KitPieces(s.kit.empty) .. ".")
	end

	for _, p in ipairs(s.professions or {}) do
		local rank = ("%s %s"):format(p.rank, p.name)
		Add("professions", ("%s is at %d/%d"):format(p.name, p.skill, p.max),
			p.ready and ("Learn %s at its trainer."):format(rank) or ("%s needs level %d."):format(rank, p.needLevel),
			p.ready and "success" or "textMuted")
	end

	for _, d in ipairs(s.dungeons or {}) do
		Add("dungeons", ("%s: %d of your quests"):format(d.name, d.quests),
			("Levels %d-%d. Groups in chat lists who's going."):format(d.min, d.max))
	end

	if s.mount then
		Add("mount", ("Riding: %s saved"):format(s.mountText),
			s.mount.left == 0 and "Enough for riding at level 40." or s.mountHours
				and ("About %s at your usual gold per hour."):format(s.mountHours) or "At level 40 you can learn to ride.",
			s.mount.left == 0 and "success" or "text")
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
