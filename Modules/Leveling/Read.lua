local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): reads the game into plain tables for Data.lua and the page. Every API here is
-- from Blizzard's own Forever UI; values that can be secret in combat are checked before use. Registered in Leveling.lua.

local BAR_SLOTS = 120 -- the action bars' slots; Blizzard's stance and possess bars above it hold no reagent spells
local WEAPON_SLOTS = { 16, 17, 18 } -- main hand, off hand, ranged
local SKILL_GAP = 5 -- weapon skills this far under their cap are listed; Gear Check warns from further behind
local LAST_CARRIED_BAG = 4 -- bag IDs: 0 is the backpack, 1 to 4 the bags you wear

local IsSecret = ns.IsSecret

-- The class trainer's rows, or nil at another kind of trainer (trade, pet) or when it's listing nothing. Second return:
-- whether its "not available yet" rows are showing (its own filter), so later levels are in the list.
function ns.LevelingRead_Trainer()
	if C_Trainer.GetTrainerType() ~= Enum.TrainerType.General then
		return nil
	end
	local total = GetNumTrainerServices()
	if not total or total == 0 then
		return nil
	end
	local rows = {}
	for i = 1, total do
		local name, serviceType, _, level, rank = GetTrainerServiceInfo(i)
		local row = ns.Leveling_SlimService(name, serviceType, rank, level, (GetTrainerServiceCost(i)))
		if row then
			rows[#rows + 1] = row
		end
	end
	return rows, GetTrainerServiceTypeFilter("unavailable") == true
end

-- The spells on the action bars: { { spellID, name, subtext, highest, consumable, count } }.
function ns.LevelingRead_Bars()
	local list = {}
	for slot = 1, BAR_SLOTS do
		if C_ActionBar.HasAction(slot) then
			local kind, id = GetActionInfo(slot)
			if kind == "spell" and id and not IsSecret(id) then
				local count = C_ActionBar.GetActionUseCount(slot)
				list[#list + 1] = {
					spellID = id,
					name = C_Spell.GetSpellName(id),
					subtext = C_Spell.GetSpellSubtext(id),
					highest = C_ActionBar.IsHighestSpellRank(id),
					consumable = C_ActionBar.IsConsumableAction(slot),
					count = not IsSecret(count) and count or nil,
				}
			end
		end
	end
	return list
end

function ns.LevelingRead_UnspentTalents()
	return C_SpecializationInfo.HasPlayerEarnedATalentPoint() and C_ClassTalents.HasUnspentTalentPoints() or false
end

-- Whether this character uses ammo right now, how much it has, its ranged weapon's subclass.
function ns.LevelingRead_Ammo()
	if not (UnitUsesAmmo("player") and C_PaperDollInfo.AmmoNeeded()) then
		return false, 0, nil
	end
	-- pcall: the API errors on a slot name the client doesn't know.
	local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
	local count = ok and slot and GetInventoryItemCount("player", slot) or 0
	local rangedOK, ranged = pcall(GetInventorySlotInfo, "RangedSlot")
	local weapon = rangedOK and ranged and GetInventoryItemID("player", ranged)
	local subclass = weapon and select(7, C_Item.GetItemInfoInstant(weapon))
	return true, count, subclass
end

-- What the open merchant sells, for Leveling_PickAmmo. Items with another price than gold aren't offered. maxStack is how
-- many fit in a bag slot, maxBuy how many one purchase can buy.
function ns.LevelingRead_Merchant()
	local items = {}
	for i = 1, GetMerchantNumItems() do
		local info = C_MerchantFrame.GetItemInfo(i)
		local link = GetMerchantItemLink(i)
		if info and link and info.isPurchasable and not info.hasExtendedCost then
			local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
			local _, _, _, _, minLevel, _, _, maxStack = C_Item.GetItemInfo(link)
			local stack = info.stackCount or 1
			items[#items + 1] = {
				index = i, itemID = itemID, name = info.name, icon = info.texture, classID = classID, subclassID = subclassID,
				price = info.price, stack = stack, available = info.numAvailable, usable = info.isUsable,
				minLevel = minLevel, maxStack = maxStack or stack, maxBuy = GetMerchantItemMaxStack(i),
			}
		end
	end
	return items
end

-- The carried bags that take this ammo, for Leveling_AmmoRoom: { { family, free, topUp } }.
function ns.LevelingRead_AmmoBags(item)
	local bags = {}
	local itemFamily = C_Item.GetItemFamily(item.itemID)
	for bag = 0, LAST_CARRIED_BAG do
		local free, family = C_Container.GetContainerNumFreeSlots(bag)
		if ns.Bags_BagTakes(family, itemFamily) then
			local topUp = 0
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID == item.itemID then
					topUp = topUp + math.max(item.maxStack - info.stackCount, 0)
				end
			end
			bags[#bags + 1] = { family = family, free = free or 0, topUp = topUp }
		end
	end
	return bags
end

-- The quest log: { { questID, title, level, difficulty, elite, complete, timeLeft, xp } }. xp is 0 until the game has the
-- quest's rewards.
function ns.LevelingRead_Quests()
	local list = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID then
			local id = info.questID
			local total, elapsed = C_QuestLog.GetTimeAllowed(id)
			local xp = GetQuestLogRewardXP(id)
			list[#list + 1] = {
				xp = xp and not IsSecret(xp) and xp or 0,
				questID = id,
				title = info.title,
				level = info.difficultyLevel or info.level,
				difficulty = C_PlayerInfo.GetContentDifficultyQuestForPlayer(id),
				elite = C_QuestLog.IsEliteQuest(id),
				complete = C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id),
				timeLeft = total and elapsed and total > elapsed and total - elapsed or nil,
			}
		end
	end
	return list
end

-- The weapon skills this character has: { { name, rank, max, worn } }.
function ns.LevelingRead_Skills()
	local worn = {}
	for _, slot in ipairs(WEAPON_SLOTS) do
		local id = GetInventoryItemID("player", slot)
		local subclass = id and select(7, C_Item.GetItemInfoInstant(id))
		if subclass then
			worn[subclass] = true
		end
	end
	local list = {}
	for subclass, skill in pairs(ns.GearForever_WeaponSkills()) do
		list[#list + 1] = { name = skill.name, rank = skill.rank, max = skill.max, worn = worn[subclass] == true }
	end
	return list
end

-- Everything the page and the Home section draw, read fresh each time: { level, atCap, xp (Leveling_XPView), todo, fine,
-- nextLevel, upcoming (trainer rows), skills, questCount, groups (Leveling_SortQuests) }.
function ns.LevelingRead_State()
	local db = ns.Leveling_DB()
	local level = UnitLevel("player")
	local char = db.chars[UnitGUID("player")]
	local services = char and char.services
	local ready, nextLevel, upcoming = ns.Leveling_TrainerSplit(services, level)
	local bars = ns.LevelingRead_Bars()
	local quests = ns.LevelingRead_Quests()
	local groups = ns.Leveling_SortQuests(quests)
	local needs, count = ns.LevelingRead_Ammo()
	local todo, fine = ns.Leveling_Checklist({
		visited = services ~= nil,
		ready = ready,
		talents = ns.LevelingRead_UnspentTalents(),
		oldRanks = ns.Leveling_OldRanks(bars),
		reagents = ns.Leveling_LowReagents(bars, db.reagentLow),
		ammoState = ns.Leveling_AmmoState(needs, count, db.ammoLow),
		ammoText = ns.Thousands(count),
		turnIns = groups.done,
	})
	local turnIn = 0
	for _, q in ipairs(groups.done) do
		turnIn = turnIn + q.xp
	end
	local atCap = level >= GameRulesUtil.GetEffectiveMaxLevelForPlayer()
	return {
		level = level,
		atCap = atCap,
		xp = not atCap and ns.Leveling_XPView(UnitXP("player"), UnitXPMax("player"), GetXPExhaustion(), turnIn) or nil,
		todo = todo,
		fine = fine,
		nextLevel = nextLevel,
		upcoming = upcoming,
		skills = ns.Leveling_SkillsBehind(ns.LevelingRead_Skills(), SKILL_GAP),
		questCount = #quests,
		groups = groups,
	}
end
