local addonName, ns = ...

-- Gear Check on World of Warcraft: Forever: pure logic (no WoW API calls; unit-tested in tests/test_gear_forever.lua).
-- A leveling helper: while leveling a clearly higher item level wins, weapons go by damage for the classes that swing them, and
-- rough per-class stat values decide the rest, counting what's enchanted on the item. Forever has no specs (one per class in the
-- API) and a ranged slot.
-- Verdicts use retail's kinds, so Gear_Headline, Gear_IsCleanUpgrade, Gear_PickReveals and the reward card (Rules.lua,
-- Rewards.lua) work on them. Items are the descriptors from ForeverItems.lua: { link, itemID, equipLoc, classID,
-- subclassID, ilvl, minLevel, stats, dps, unique, redText, enchant, enchantText }.

local MAX_LEVEL = 60 -- warcraft.wiki.gg: Forever's level cap, with no raises planned
local UPGRADE_PCT = 1 -- above +1% is an upgrade, within +-1% a sidegrade (as on retail)
local ARMOR_CLASS_ID = 4 -- Enum.ItemClass.Armor
local WEAPON_CLASS_ID = 2 -- Enum.ItemClass.Weapon
local WAND_SUBCLASS = 19 -- Enum.ItemWeaponSubclass.Wand
-- Enum.ItemArmorSubclass: Cloth 1, Leather 2, Mail 3, Plate 4, so a lower number is lighter armor.
local ARMOR_NAMES = { "Cloth", "Leather", "Mail", "Plate" }
local ARMOR_LOCS = {
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true,
	INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}
local RANGED_LOCS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true }

-- Rough values for telling apart gear of the same item level; item level and damage decide everything else. A primary
-- stat missing here makes an item "wrong main stat". Hybrids keep what any of their ways to level can use.
local WEIGHTS = {
	WARRIOR = { STR = 1, AGI = 0.5, STA = 0.5 },
	PALADIN = { STR = 1, INT = 0.5, STA = 0.5, SPI = 0.1 },
	HUNTER = { AGI = 1, INT = 0.3, STA = 0.5, SPI = 0.1 },
	ROGUE = { AGI = 1, STR = 0.5, STA = 0.5 },
	PRIEST = { INT = 1, STA = 0.5, SPI = 0.7 },
	SHAMAN = { INT = 0.8, STR = 0.8, AGI = 0.5, STA = 0.5, SPI = 0.2 },
	MAGE = { INT = 1, STA = 0.5, SPI = 0.5 },
	WARLOCK = { INT = 1, STA = 0.7, SPI = 0.3 },
	DRUID = { INT = 0.8, STR = 0.8, AGI = 0.8, STA = 0.5, SPI = 0.3 },
}
local ANY_CLASS = { STR = 1, AGI = 1, INT = 1, STA = 0.5, SPI = 0.2 }
local ARMOR_WEIGHT = 0.02 -- per point of armor: enough to split two items that are otherwise the same
-- Item levels apart before the item level alone decides while leveling. Closer than this says little: Patchwork Armor is 2 levels
-- above a leather vest with almost three times its armor.
local CLEAR_ILVL_GAP = 5

-- Who judges melee weapons and ranged weapons by their damage; for the others item level and stats decide.
local MELEE_DPS = { WARRIOR = true, PALADIN = true, ROGUE = true, SHAMAN = true }
local RANGED_DPS = { HUNTER = true }
local WAND_DPS = { MAGE = true, PRIEST = true, WARLOCK = true } -- a caster's wand is its autoattack
local SKILL_BEHIND = 10 -- a weapon skill this far under its cap is worth a warning: you'd miss more with it

-- Enum.ItemWeaponSubclass -> weapon skill line, the IDs in Blizzard's Camelot/SkillsFrame.lua. Also read by Modules/Leveling.
ns.GEARFOREVER_WEAPON_SKILLS = {
	[0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43, [8] = 55, [10] = 136, [13] = 162,
	[15] = 173, [16] = 176, [18] = 226, [19] = 228,
}

-- The context to judge with. opts: { level, class, rangedSlot (nil when the client has none), levelingIlvl (setting),
-- weaponSkills ([weapon subclass] = { name, rank, max }) }.
function ns.GearForever_Context(opts)
	local weights = WEIGHTS[opts.class] or ANY_CLASS
	return {
		class = opts.class,
		level = opts.level,
		rangedSlot = opts.rangedSlot,
		weaponSkills = opts.weaponSkills,
		weights = weights,
		leveling = opts.levelingIlvl ~= false and (opts.level or 0) < MAX_LEVEL,
	}
end

-- "(12.5 damage per second)" as a number; template is Blizzard's DPS_TEMPLATE pattern (Gear_FormatPattern). Some client
-- languages write the decimal with a comma.
function ns.GearForever_ParseDps(text, pattern)
	if type(text) ~= "string" or not pattern then
		return nil
	end
	local value = text:match(pattern)
	return value and tonumber((value:gsub(",", "."))) or nil
end

-- The worn-slot number an equip location goes to, as retail's Gear_Slots but with Forever's ranged slot.
function ns.GearForever_Slots(equipLoc, rangedSlot)
	if RANGED_LOCS[equipLoc] and rangedSlot then
		return { rangedSlot }
	end
	return ns.Gear_Slots(equipLoc)
end

-- What an "Enchanted:" tooltip line gives: { [stat] = amount }, nil when it names none of them. text: what comes after the prefix,
-- as "Stamina +1 and Armor +8" or "+3 Agility". names: { [stat] = this client's name for it }.
function ns.GearForever_ParseEnchant(text, names)
	if type(text) ~= "string" then
		return nil
	end
	local lower = text:lower()
	local found
	for stat, name in pairs(names) do
		local plain = name:lower():gsub("%p", "%%%0")
		local amount = lower:match(plain .. "%s*%+(%d+)") or lower:match("%+(%d+)%s*" .. plain)
		if amount then
			found = found or {}
			found[stat] = tonumber(amount)
		end
	end
	return found
end

local function Score(desc, weights)
	if not desc then
		return 0
	end
	local total = 0
	for stat, amount in pairs(desc.enchant or {}) do
		total = total + amount * (stat == "ARMOR" and ARMOR_WEIGHT or (weights[stat] or 0))
	end
	for key, amount in pairs(desc.stats or {}) do
		if key == "PRIMARY" then
			for stat, value in pairs(amount) do
				total = total + value * (weights[stat] or 0)
			end
		elseif key == "ARMOR" then
			total = total + amount * ARMOR_WEIGHT
		else
			total = total + amount * (weights[key] or 0)
		end
	end
	return total
end

local function Dps(desc)
	return desc and (desc.dps or (desc.stats and desc.stats.DPS)) or 0
end

-- Whether this class judges this item by its damage.
local function JudgedByDamage(cand, ctx)
	if cand.classID ~= WEAPON_CLASS_ID then
		return false
	end
	if not RANGED_LOCS[cand.equipLoc] then
		return MELEE_DPS[ctx.class] == true
	end
	if cand.subclassID == WAND_SUBCLASS then
		return WAND_DPS[ctx.class] == true
	end
	return RANGED_DPS[ctx.class] == true
end

local function NotForYou(why)
	return { kind = "notForYou", why = why, reasons = {}, warnings = 0 }
end

-- Why this character can't use the item (now), or nil.
function ns.GearForever_Unusable(cand, ctx)
	if cand.minLevel and ctx.level and cand.minLevel > ctx.level then
		return ("needs level %d"):format(cand.minLevel)
	end
	if cand.redText then
		return cand.redText
	end
	local primaries = cand.stats and cand.stats.PRIMARY
	-- A weapon this class judges by its damage (a hunter's bow) isn't ruled out by a stat it doesn't use: the damage
	-- decides, as a Heavy Shortbow's +1 Strength showed (6.0 DPS over 3.7, called wrong main stat).
	if primaries and next(primaries) and not JudgedByDamage(cand, ctx) then
		for stat in pairs(primaries) do
			if ctx.weights[stat] then
				return nil
			end
		end
		return "wrong main stat"
	end
	return nil
end

-- What the candidate replaces: { mode = "single" | "weaker" | "sum" | "pair" | "empty", slots }.
local function Target(cand, equipped, ctx)
	if RANGED_LOCS[cand.equipLoc] and ctx.rangedSlot then
		return { mode = equipped[ctx.rangedSlot] and "single" or "empty", slots = { ctx.rangedSlot } }
	end
	return ns.Gear_Target(cand, equipped)
end

-- Which of two slots a candidate replaces: the weaker one by what decides for this item.
local function WeakerSlot(a, b, equipped, ctx, byDamage)
	local da, db = equipped[a], equipped[b]
	if byDamage then
		return Dps(da) <= Dps(db) and a or b
	end
	if ctx.leveling and da and db and da.ilvl and db.ilvl and da.ilvl ~= db.ilvl then
		return da.ilvl < db.ilvl and a or b
	end
	return Score(da, ctx.weights) <= Score(db, ctx.weights) and a or b
end

-- The item would be lighter armor than what it replaces (a warrior's leather over mail): name it for the warning.
local function LighterArmor(cand, replaced, equipped)
	if cand.classID ~= ARMOR_CLASS_ID or not ARMOR_LOCS[cand.equipLoc] or not ARMOR_NAMES[cand.subclassID or 0] then
		return nil
	end
	for slot in pairs(replaced) do
		local old = equipped[slot]
		if old and old.classID == ARMOR_CLASS_ID and ARMOR_NAMES[old.subclassID or 0] and cand.subclassID < old.subclassID then
			return ARMOR_NAMES[cand.subclassID]
		end
	end
	return nil
end

-- The weapon's skill when it's well behind and you'd be switching to it: a new weapon of the kind you already swing costs
-- nothing. Nil otherwise.
local function BehindSkill(cand, replaced, equipped, ctx)
	local skill = ctx.weaponSkills and cand.classID == WEAPON_CLASS_ID and ctx.weaponSkills[cand.subclassID]
	if not skill or skill.max - skill.rank < SKILL_BEHIND then
		return nil
	end
	for slot in pairs(replaced) do
		local old = equipped[slot]
		if old and old.subclassID == cand.subclassID then
			return nil
		end
	end
	return skill
end

local function ByPercent(verdict, pct, warned)
	verdict.pct = pct
	if pct > UPGRADE_PCT then
		verdict.kind = warned and "upgradeBut" or "upgrade"
	elseif pct >= -UPGRADE_PCT then
		verdict.kind = "sidegrade"
	else
		verdict.kind = "downgrade"
	end
	return verdict
end

-- A verdict for this character, or nil when the item doesn't go on a slot or is worn.
function ns.GearForever_Evaluate(cand, equipped, ctx)
	for _, desc in pairs(equipped) do
		if desc.link == cand.link then
			return nil
		end
	end
	if not ns.GearForever_Slots(cand.equipLoc, ctx.rangedSlot) then
		return nil
	end
	local why = ns.GearForever_Unusable(cand, ctx)
	if why then
		return NotForYou(why)
	end

	local target = Target(cand, equipped, ctx)
	if not target then
		return nil
	end
	local byDamage = JudgedByDamage(cand, ctx)
	if target.mode == "weaker" then
		local slot = WeakerSlot(target.slots[1], target.slots[2], equipped, ctx, byDamage)
		target = { mode = "single", slots = { slot } }
	end
	local replaced = {}
	for _, slot in ipairs(target.slots) do
		replaced[slot] = true
	end

	if cand.unique then
		local key = cand.unique.category or cand.itemID
		local worn = 0
		for slot, desc in pairs(equipped) do
			if not replaced[slot] and desc.unique and (desc.unique.category or desc.itemID) == key then
				worn = worn + 1
			end
		end
		if worn + 1 > (cand.unique.max or 1) then
			return NotForYou("unique, you already wear one")
		end
	end

	local verdict = { reasons = {}, warnings = 0, slot = target.slots[1] }
	if target.mode == "pair" then
		verdict.kind = "pair"
		verdict.reasons = { "Needs an off-hand to go with it" }
		return verdict
	end
	if target.mode == "empty" then
		verdict.kind = "empty"
		return verdict
	end

	local oldDps, oldScore, topIlvl, lowIlvl = 0, 0, nil, nil
	for slot in pairs(replaced) do
		local old = equipped[slot]
		oldDps = oldDps + Dps(old)
		oldScore = oldScore + Score(old, ctx.weights)
		local ilvl = old and old.ilvl
		if ilvl then
			topIlvl = (not topIlvl or ilvl > topIlvl) and ilvl or topIlvl
			lowIlvl = (not lowIlvl or ilvl < lowIlvl) and ilvl or lowIlvl
		end
	end

	local lighter = LighterArmor(cand, replaced, equipped)
	if lighter then
		verdict.warnings = 1
		verdict.reasons[1] = ("Lighter armor than yours (%s)"):format(lighter)
	end
	-- Replacing it costs the enchant or armor kit on it. It's in the scores too; this says so in words.
	for slot in pairs(replaced) do
		local old = equipped[slot]
		if old and old.enchantText and not cand.enchantText then
			verdict.warnings = verdict.warnings + 1
			verdict.reasons[#verdict.reasons + 1] = ("You'd lose the enchant on yours (%s)"):format(old.enchantText)
		end
	end
	local skill = BehindSkill(cand, replaced, equipped, ctx)
	if skill then
		verdict.warnings = verdict.warnings + 1
		verdict.reasons[#verdict.reasons + 1] = ("Your %s skill is behind (%d/%d)"):format(skill.name, skill.rank, skill.max)
	end

	if byDamage and Dps(cand) > 0 and oldDps > 0 then
		verdict.reasons[#verdict.reasons + 1] = ("%.1f damage per second, yours %.1f"):format(Dps(cand), oldDps)
		return ByPercent(verdict, (Dps(cand) - oldDps) / oldDps * 100, verdict.warnings > 0)
	end

	-- The item level decides while leveling, unless the stats can say better: it's only a little apart, or lighter armor, where a
	-- higher item level still means less armor. With no stats on either there's only the item level to go by.
	local newScore = Score(cand, ctx.weights)
	local hasStats = oldScore > 0 or newScore > 0
	local higher = cand.ilvl and topIlvl and cand.ilvl > topIlvl
	local lower = cand.ilvl and lowIlvl and cand.ilvl < lowIlvl
	local clear = (higher and cand.ilvl - topIlvl >= CLEAR_ILVL_GAP) or (lower and lowIlvl - cand.ilvl >= CLEAR_ILVL_GAP)
	if ctx.leveling and not (hasStats and (lighter or not clear)) then
		if higher then
			verdict.kind = "levelUp"
			verdict.ilvlDiff = cand.ilvl - topIlvl
			return verdict
		end
		if lower then
			verdict.kind = "downgrade"
			verdict.levelDown = true
			verdict.ilvlDiff = cand.ilvl - lowIlvl
			verdict.reasons, verdict.warnings = {}, 0 -- it stays where it is, so nothing to warn about
			return verdict
		end
	end

	if oldScore <= 0 then
		verdict.statless = true
		verdict.kind = newScore > 0 and "noStats" or "ilvl"
		verdict.ilvlDiff = cand.ilvl and topIlvl and cand.ilvl - topIlvl or 0
		return verdict
	end
	ByPercent(verdict, (newScore - oldScore) / oldScore * 100, verdict.warnings > 0)
	if verdict.kind == "downgrade" then
		verdict.reasons, verdict.warnings = {}, 0 -- it stays where it is, so nothing to warn about
	end
	return verdict
end

-- Bags: which links are new since the last look. before: [link] = count (replaced by the counts of links). A second
-- copy of something you already carry counts as new, an item that left and came back doesn't need telling apart: it's
-- judged again and only a clean upgrade says anything.
function ns.GearForever_NewItems(before, links)
	local now, new = {}, {}
	for _, link in ipairs(links) do
		now[link] = (now[link] or 0) + 1
		if now[link] > (before[link] or 0) then
			new[#new + 1] = link
		end
	end
	return new, now
end
