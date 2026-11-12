local addonName, ns = ...

-- Gear Check on World of Warcraft: Forever: pure logic (no WoW API calls; unit-tested in tests/test_gear_forever.lua).
-- A leveling helper: weapons go by damage for the classes that swing them, and rough per-class stat values (armor and what's
-- enchanted on the item included) decide the rest; only between items with nothing on them does the item level, while leveling.
-- Forever has no specs (one per class in the API) and a ranged slot.
-- Verdicts use retail's kinds, so Gear_Headline, Gear_IsCleanUpgrade, Gear_PickReveals and the reward card (Rules.lua,
-- Rewards.lua) work on them. Items are the descriptors from ForeverItems.lua: { link, itemID, equipLoc, classID,
-- subclassID, subclassName, ilvl, minLevel, stats, dps, unique, redText, redSkill and redSkillText (the type line is red),
-- enchant, enchantText }.

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

-- Rough values for telling gear apart; damage decides weapons for the classes that swing them. A primary
-- stat missing here makes an item "wrong main stat". Hybrids keep what any of their ways to level can use. AP (attack power)
-- is half a point of the stat that gives it: a point of Strength or Agility is worth about two. RAP is ranged attack power.
-- From Equip lines (GearForever_ParseEquip): SP spell damage and healing, SPSCHOOL one school's damage, HEAL healing,
-- SCRIT / SHIT spell crit and hit and MCRIT / MHIT the physical ones (per 1%, about ten points of the main stat), DEF
-- defense, MP5 mana every 5 seconds.
local WEIGHTS = {
	WARRIOR = { STR = 1, AGI = 0.5, STA = 0.5, AP = 0.5, MCRIT = 10, MHIT = 8, DEF = 0.5 },
	PALADIN = { STR = 1, INT = 0.5, STA = 0.5, SPI = 0.1, AP = 0.5, MCRIT = 8, MHIT = 6, DEF = 0.4, SP = 0.3, HEAL = 0.3,
		SCRIT = 3, MP5 = 1 },
	HUNTER = { AGI = 1, INT = 0.3, STA = 0.5, SPI = 0.1, AP = 0.5, RAP = 0.5, MCRIT = 10, MHIT = 8, MP5 = 1 },
	ROGUE = { AGI = 1, STR = 0.5, STA = 0.5, AP = 0.5, MCRIT = 10, MHIT = 10 },
	PRIEST = { INT = 1, STA = 0.5, SPI = 0.7, SP = 0.8, SPSCHOOL = 0.5, HEAL = 0.8, SCRIT = 8, SHIT = 6, MP5 = 2 },
	SHAMAN = { INT = 0.8, STR = 0.8, AGI = 0.5, STA = 0.5, SPI = 0.2, AP = 0.4, SP = 0.6, HEAL = 0.5, SCRIT = 6, SHIT = 4,
		MCRIT = 6, MHIT = 5, MP5 = 1.5 },
	MAGE = { INT = 1, STA = 0.5, SPI = 0.5, SP = 0.9, SPSCHOOL = 0.6, SCRIT = 10, SHIT = 10, MP5 = 1 },
	WARLOCK = { INT = 1, STA = 0.7, SPI = 0.3, SP = 0.9, SPSCHOOL = 0.6, SCRIT = 6, SHIT = 10, MP5 = 1 },
	DRUID = { INT = 0.8, STR = 0.8, AGI = 0.8, STA = 0.5, SPI = 0.3, AP = 0.4, SP = 0.6, HEAL = 0.5, SCRIT = 6, SHIT = 4,
		MCRIT = 6, MHIT = 5, MP5 = 1.5 },
}
local ANY_CLASS = { STR = 1, AGI = 1, INT = 1, STA = 0.5, SPI = 0.2, AP = 0.5, RAP = 0.3, SP = 0.5, HEAL = 0.3, SCRIT = 5,
	SHIT = 5, MCRIT = 5, MHIT = 5, MP5 = 1, DEF = 0.2 }
-- What the group's healer values (GearForever_Fit): a hybrid's WEIGHTS mix healing with how it levels alone.
local HEALER_WEIGHTS = { INT = 1, SPI = 0.5, STA = 0.3, SP = 0.6, HEAL = 1, SCRIT = 6, MP5 = 2 }
-- Equip lines that are stats, as English clients write them (the game has no stat for them, and no localized string
-- either: they're each item's spell text). Each: a pattern with the amount captured, and its stat key.
local EQUIP_STATS = {
	{ "Increases damage and healing done by magical spells and effects by up to (%d+)", "SP" },
	{ "Increases healing done by spells and effects by up to (%d+)", "HEAL" },
	{ "Increases damage done by %a+ spells and effects by up to (%d+)", "SPSCHOOL" },
	{ "Improves your chance to get a critical strike with spells by (%d+)%%", "SCRIT" },
	{ "Improves your chance to hit with spells by (%d+)%%", "SHIT" },
	{ "Improves your chance to get a critical strike by (%d+)%%", "MCRIT" },
	{ "Improves your chance to hit by (%d+)%%", "MHIT" },
	{ "Increased Defense %+(%d+)", "DEF" },
	{ "Restores (%d+) mana per 5 sec", "MP5" },
}
local ARMOR_WEIGHT = 0.02 -- per point of armor: enough to split two items that are otherwise the same

-- Who judges melee weapons and ranged weapons by their damage; for the others item level and stats decide.
local MELEE_DPS = { WARRIOR = true, PALADIN = true, ROGUE = true, SHAMAN = true }
-- A hunter's melee weapon is a stat stick for the bow: Agility, Stamina and attack power, not the Intellect WEIGHTS
-- gives a hunter's armor (a Strength and Intellect sword isn't worth a slot an Agility dagger fills). Casters' staves
-- keep their WEIGHTS: Intellect is their main stat.
local STAT_STICK = { HUNTER = { AGI = 1, STA = 0.5, AP = 0.5, RAP = 0.5, MCRIT = 10, MHIT = 8 } }
local RANGED_DPS = { HUNTER = true }
local WAND_DPS = { MAGE = true, PRIEST = true, WARLOCK = true } -- a caster's wand is its autoattack
local SKILL_BEHIND = 10 -- a weapon skill this far under its cap is worth a warning: you'd miss more with it
-- The level each class's trainer teaches Dual Wield, as in the original game (shamans and the rest never had it there).
local DUAL_WIELD_FROM = { ROGUE = 10, WARRIOR = 20, HUNTER = 20 }
local DUAL_WIELD = "Dual Wield"
local ONE_HAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

-- Enum.ItemWeaponSubclass -> weapon skill line, the IDs in Blizzard's Camelot/SkillsFrame.lua. Also read by Modules/Leveling.
ns.GEARFOREVER_WEAPON_SKILLS = {
	[0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43, [8] = 55, [10] = 136, [13] = 162,
	[15] = 173, [16] = 176, [18] = 226, [19] = 228,
}

-- The context to judge with. opts: { level, class, rangedSlot (nil when the client has none), levelingIlvl (setting),
-- weaponSkills ([weapon subclass] = { name, rank, max }), assumeTrained, dualWield (Dual Wield is known) }.
function ns.GearForever_Context(opts)
	local weights = WEIGHTS[opts.class] or ANY_CLASS
	return {
		class = opts.class,
		level = opts.level,
		rangedSlot = opts.rangedSlot,
		weaponSkills = opts.weaponSkills,
		weights = weights,
		leveling = opts.levelingIlvl ~= false and (opts.level or 0) < MAX_LEVEL,
		assumeTrained = opts.assumeTrained, -- judge weapon types a trainer can teach you as if learned (roll advice)
		dualWield = opts.dualWield,
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

-- "Taught by Archibald in Undercity or Hanashi in Orgrimmar": who teaches a weapon type (Enum.ItemWeaponSubclass) to
-- this faction. masters: Data/Forever/WeaponMasters.lua's list. nil when none does.
function ns.GearForever_TeacherText(masters, subclassID, faction)
	local names = {}
	for _, master in ipairs(masters or {}) do
		if master.faction == faction then
			for _, skill in ipairs(master.skills) do
				if skill == subclassID then
					names[#names + 1] = ("%s in %s"):format(master.name, master.city)
					break
				end
			end
		end
	end
	return #names > 0 and ("Taught by " .. table.concat(names, " or ")) or nil
end

-- A stat from a tooltip's Equip line: key, amount; nil when the line isn't one of EQUIP_STATS.
function ns.GearForever_ParseEquip(text)
	if type(text) ~= "string" then
		return nil
	end
	for _, entry in ipairs(EQUIP_STATS) do
		local amount = text:match(entry[1])
		if amount then
			return entry[2], tonumber(amount)
		end
	end
	return nil
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

-- Which weapon types (Enum.ItemWeaponSubclass) each class can learn, the original game's proficiencies: a red weapon type
-- in this list is one a weapon trainer teaches.
local WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
	MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 10, 13, 15 },
}
local SHIELD_SUBCLASS = 6 -- Enum.ItemArmorSubclass.Shield
-- Armor types (Enum.ItemArmorSubclass) beyond cloth, and the level each class can wear them from.
local ARMOR_FROM = {
	[2] = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, SHAMAN = 1, DRUID = 1 }, -- leather
	[3] = { WARRIOR = 1, PALADIN = 1, HUNTER = 40, SHAMAN = 40 }, -- mail
	[4] = { WARRIOR = 40, PALADIN = 40 }, -- plate
	[SHIELD_SUBCLASS] = { WARRIOR = 1, PALADIN = 1, SHAMAN = 1 },
}

-- Why a weapon or armor type shows red (cand.redSkill), in words; nil when it's a type these tables don't know. Second:
-- true when it's a weapon type a trainer can teach this class. Third: true when the class can never use it.
local function TypeWhy(cand, ctx)
	local name = cand.subclassName
	if not name then
		return nil
	end
	if cand.classID == WEAPON_CLASS_ID then
		local learnable = WEAPONS[ctx.class]
		if not learnable then
			return nil
		end
		for _, subclass in ipairs(learnable) do
			if subclass == cand.subclassID then
				return ("needs the %s skill from a weapon trainer"):format(name), true
			end
		end
		if ns.GEARFOREVER_WEAPON_SKILLS[cand.subclassID] then
			return ("your class can't use %s"):format(name), false, true
		end
		return nil
	elseif cand.classID == ARMOR_CLASS_ID and ARMOR_FROM[cand.subclassID] then
		local from = ARMOR_FROM[cand.subclassID][ctx.class]
		if from and ctx.level and from > ctx.level then
			return ("you can wear %s from level %d"):format(name:lower(), from)
		elseif not from then
			return ("your class can't wear %s"):format(name:lower()), false, true
		end
	end
	return nil
end

-- The stat values to judge an item with: a weapon a class only carries for its stats (a hunter's melee weapon) counts
-- what helps that class fight its own way, from STAT_STICK; anything else the class's WEIGHTS.
local function Weights(cand, ctx)
	local stick = cand.classID == WEAPON_CLASS_ID and not JudgedByDamage(cand, ctx) and STAT_STICK[ctx.class]
	return stick or ctx.weights
end

local function NotForYou(why)
	return { kind = "notForYou", why = why, reasons = {}, warnings = 0 }
end

-- Why this character can't use the item (now), or nil. Second: the weapon type it would need training in, when
-- ctx.assumeTrained let that pass (the roll advice: you can learn it before the item is worth less).
-- Whether none of the item's main stats is one this class uses.
local function WrongStat(cand, ctx)
	local primaries = cand.stats and cand.stats.PRIMARY
	-- A weapon this class judges by its damage (a hunter's bow) isn't ruled out by a stat it doesn't use: the damage
	-- decides, as a Heavy Shortbow's +1 Strength showed (6.0 DPS over 3.7, called wrong main stat).
	if not (primaries and next(primaries)) or JudgedByDamage(cand, ctx) then
		return false
	end
	local weights = Weights(cand, ctx)
	for stat in pairs(primaries) do
		if weights[stat] then
			return false
		end
	end
	-- A stat stick only needs something that counts: Stamina or attack power on it will do.
	if weights ~= ctx.weights then
		for key, amount in pairs(cand.stats) do
			if key ~= "PRIMARY" and weights[key] and amount > 0 then
				return false
			end
		end
	end
	return true
end

-- Why this character can't use the item (now), or nil. A reason that never goes away (a type the class can't use, the
-- wrong main stat) comes before one you can wait out (a level, a weapon trainer), so "needs level 18" isn't said of
-- something that will never be for you. Second: the weapon type it would need training in, when ctx.assumeTrained let
-- that pass (the roll advice: you can learn it before the item is worth less).
function ns.GearForever_Unusable(cand, ctx)
	local typeWhy, learnable, never
	if cand.redSkill then
		typeWhy, learnable, never = TypeWhy(cand, ctx)
	end
	if never then
		return typeWhy
	end
	if WrongStat(cand, ctx) then
		return "wrong main stat"
	end
	if cand.minLevel and ctx.level and cand.minLevel > ctx.level then
		return ("needs level %d"):format(cand.minLevel)
	end
	local untrained
	if cand.redSkill then
		if learnable and ctx.assumeTrained then
			untrained = cand.subclassName
		elseif typeWhy then
			return typeWhy
		elseif cand.redSkillText then
			return cand.redSkillText
		end
	end
	if cand.redText then
		return cand.redText
	end
	return nil, untrained
end

-- Whether this character can hold a weapon in each hand: "known", "learnable" (its trainer teaches Dual Wield at its
-- level) or nil.
local function DualWield(ctx)
	if ctx.dualWield then
		return "known"
	end
	local from = DUAL_WIELD_FROM[ctx.class]
	return from and ctx.level and ctx.level >= from and "learnable" or nil
end

-- What the candidate replaces: { mode = "single" | "weaker" | "sum" | "pair" | "empty", slots }.
local function Target(cand, equipped, ctx)
	if RANGED_LOCS[cand.equipLoc] and ctx.rangedSlot then
		return { mode = equipped[ctx.rangedSlot] and "single" or "empty", slots = { ctx.rangedSlot } }
	end
	return ns.Gear_Target(cand, equipped)
end

-- Whether a one-hander could go in an empty off-hand next to the one-hander in the main hand: "known" or "learnable"
-- (Dual Wield from the trainer), nil when not. The shared rules only ever weigh it against the main hand.
local function OffHandFree(cand, equipped, ctx)
	local mh = equipped[16]
	if cand.classID ~= WEAPON_CLASS_ID or not ONE_HAND_WEAPON[cand.equipLoc] or equipped[17] or not mh
		or not ONE_HAND_WEAPON[mh.equipLoc] then
		return nil
	end
	return DualWield(ctx)
end

local UPGRADES = { upgrade = true, upgradeBut = true, levelUp = true, empty = true, noStats = true }

-- Which of two slots a candidate replaces: the weaker one by what decides for this item.
local function WeakerSlot(a, b, equipped, ctx, byDamage, weights)
	local da, db = equipped[a], equipped[b]
	if byDamage then
		return Dps(da) <= Dps(db) and a or b
	end
	if ctx.leveling and weights == ctx.weights and da and db and da.ilvl and db.ilvl and da.ilvl ~= db.ilvl then
		return da.ilvl < db.ilvl and a or b
	end
	return Score(da, weights) <= Score(db, weights) and a or b
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
local Judge

-- The verdict for cand against what's worn. A one-hander that doesn't beat the main hand still fills an empty off-hand
-- for a class that dual wields, as Tail Spike next to a Harpy Skinner showed (called a sidegrade, so it was greeded).
-- Not learned yet: it can't go there now, so the main hand's verdict stands, marked offHandLater (an upgrade once you
-- learn Dual Wield: the tooltip's line and the bags' "later" arrow); the look-ahead (ctx.assumeTrained: the roll advice)
-- calls it filling the empty off-hand, so it's worth a Need.
function ns.GearForever_Evaluate(cand, equipped, ctx)
	local verdict = Judge(cand, equipped, ctx)
	if not verdict or verdict.kind == "notForYou" or UPGRADES[verdict.kind] then
		return verdict
	end
	local dual = OffHandFree(cand, equipped, ctx)
	if not dual then
		return verdict
	end
	if dual == "learnable" and not ctx.assumeTrained then
		verdict.offHandLater = true
		return verdict
	end
	local off = { kind = "empty", slot = 17, reasons = {}, warnings = 0, untrained = verdict.untrained }
	if dual == "learnable" then
		off.untrained = off.untrained or DUAL_WIELD
		off.reasons[1] = "For your off-hand: learn Dual Wield from your class trainer"
	end
	return off
end

Judge = function(cand, equipped, ctx)
	for _, desc in pairs(equipped) do
		if desc.link == cand.link then
			return nil
		end
	end
	if not ns.GearForever_Slots(cand.equipLoc, ctx.rangedSlot) then
		return nil
	end
	local why, untrained = ns.GearForever_Unusable(cand, ctx)
	if why then
		return NotForYou(why)
	end

	local target = Target(cand, equipped, ctx)
	if not target then
		return nil
	end
	local byDamage = JudgedByDamage(cand, ctx)
	local weights = Weights(cand, ctx)
	if target.mode == "weaker" then
		local slot = WeakerSlot(target.slots[1], target.slots[2], equipped, ctx, byDamage, weights)
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

	local verdict = { reasons = {}, warnings = 0, slot = target.slots[1], untrained = untrained }
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
		oldScore = oldScore + Score(old, weights)
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

	-- The stats, armor and enchants on the items decide. Only with nothing on either (a plain ring, a caster's sword) does the
	-- item level, while leveling: a higher one is then the better item for your level.
	local newScore = Score(cand, weights)
	local hasStats = oldScore > 0 or newScore > 0
	local higher = cand.ilvl and topIlvl and cand.ilvl > topIlvl
	local lower = cand.ilvl and lowIlvl and cand.ilvl < lowIlvl
	if ctx.leveling and not hasStats then
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

-- How much someone gets out of a piece of armor, on the WEIGHTS scale, or nil when they can't wear it or none of its main
-- stats is theirs: the roll advice weighs a party member against you with it (RollData.lua). who: { class, level (the
-- level to judge at), role (the group's "HEALER", "TANK", ...) }. Weapons give nil: they go by damage, not stats.
function ns.GearForever_Fit(cand, who)
	if cand.classID ~= ARMOR_CLASS_ID or not WEIGHTS[who.class] then
		return nil
	end
	local wear = ARMOR_FROM[cand.subclassID]
	if wear and not (wear[who.class] and who.level and wear[who.class] <= who.level) then
		return nil
	end
	local weights = who.role == "HEALER" and HEALER_WEIGHTS or WEIGHTS[who.class]
	local primaries = cand.stats and cand.stats.PRIMARY
	if primaries and next(primaries) then
		local any = false
		for stat in pairs(primaries) do
			any = any or weights[stat] ~= nil
		end
		if not any then
			return nil
		end
	end
	return Score(cand, weights)
end

-- Whether reaching newLevel from oldLevel is what lets you wear the item (its level requirement is in between), so a
-- level-up toasts it once and not what you could already wear and chose not to.
function ns.GearForever_NewlyWearable(cand, oldLevel, newLevel)
	local need = cand and cand.minLevel
	return need ~= nil and need > oldLevel and need <= newLevel
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
