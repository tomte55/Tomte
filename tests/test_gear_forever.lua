-- Run from the AddOns folder: lua Tomte/tests/test_gear_forever.lua
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ns = {}
loadfile("Tomte/Modules/Gear/Rules.lua")("Tomte", ns)
loadfile("Tomte/Modules/Gear/ForeverRules.lua")("Tomte", ns)

local ARMOR, WEAPON = 4, 2
local CLOTH, LEATHER, MAIL = 1, 2, 3
local BOW, WAND = 2, 19
local RANGED_SLOT = 18

local function Ctx(class, level, levelingIlvl)
	return ns.GearForever_Context({ class = class, level = level or 20, rangedSlot = RANGED_SLOT,
		levelingIlvl = levelingIlvl })
end

local function Item(fields)
	fields.link = fields.link or tostring(fields)
	fields.stats = fields.stats or {}
	return fields
end

local function Chest(ilvl, subclassID, stats)
	return Item({ equipLoc = "INVTYPE_CHEST", classID = ARMOR, subclassID = subclassID or MAIL, ilvl = ilvl, stats = stats })
end

local function Sword(ilvl, dps)
	return Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 7, ilvl = ilvl, dps = dps })
end

test("a higher item level wins while leveling, a lower one loses", function()
	local ctx = Ctx("WARRIOR")
	local worn = { [5] = Chest(10) }
	local up = ns.GearForever_Evaluate(Chest(14), worn, ctx)
	eq(up.kind, "levelUp")
	eq(up.ilvlDiff, 4)
	eq(up.slot, 5)
	eq(ns.Gear_IsCleanUpgrade(up), true)
	local down = ns.GearForever_Evaluate(Chest(8), worn, ctx)
	eq(down.kind, "downgrade")
	eq(down.levelDown, true)
	eq(down.ilvlDiff, -2)
end)

test("the same item level goes by this class's stats", function()
	local ctx = Ctx("WARRIOR")
	local worn = { [5] = Chest(10, MAIL, { STA = 4 }) }
	local strength = Chest(10, MAIL, { PRIMARY = { STR = 4 } })
	eq(ns.GearForever_Evaluate(strength, worn, ctx).kind, "upgrade")
	local weaker = { [5] = Chest(10, MAIL, { PRIMARY = { STR = 8 } }) }
	eq(ns.GearForever_Evaluate(Chest(10, MAIL, { STA = 4 }), weaker, ctx).kind, "downgrade")
end)

test("attack power counts for the classes that fight with it", function()
	local dagger = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, ilvl = 13, dps = 6.2,
		stats = { PRIMARY = { AGI = 1 } } })
	local hatchet = Item({ equipLoc = "INVTYPE_WEAPONMAINHAND", classID = WEAPON, subclassID = 0, ilvl = 13, dps = 7.5,
		stats = { AP = 2 } })
	local v = ns.GearForever_Evaluate(hatchet, { [16] = dagger }, Ctx("HUNTER"))
	eq(v.kind ~= "downgrade", true, "+2 attack power isn't nothing to a hunter")
	local warrior = ns.GearForever_Evaluate(Chest(10, MAIL, { AP = 4 }), { [5] = Chest(10, MAIL, { STA = 2 }) }, Ctx("WARRIOR"))
	eq(warrior.kind, "upgrade")
	local mage = ns.GearForever_Evaluate(Chest(10, CLOTH, { AP = 4 }), { [5] = Chest(10, CLOTH, { STA = 2 }) }, Ctx("MAGE"))
	eq(mage.kind, "downgrade", "a caster has no use for it")
	local ranged = ns.GearForever_Evaluate(Chest(10, MAIL, { RAP = 4 }), { [5] = Chest(10, MAIL, { STA = 2 }) }, Ctx("HUNTER"))
	eq(ranged.kind, "upgrade", "ranged attack power is a hunter's")
end)

test("a red weapon or armor type says why: not learned yet, never, or a later level", function()
	local function Why(class, level, fields)
		fields.redSkill = true
		return ns.GearForever_Unusable(Item(fields), Ctx(class, level))
	end
	eq(Why("HUNTER", 16, { classID = WEAPON, subclassID = 8, subclassName = "Two-Handed Swords" }),
		"needs the Two-Handed Swords skill from a weapon trainer")
	eq(Why("HUNTER", 16, { classID = WEAPON, subclassID = 4, subclassName = "One-Handed Maces" }),
		"your class can't use One-Handed Maces")
	eq(Why("HUNTER", 16, { classID = ARMOR, subclassID = MAIL, subclassName = "Mail" }), "you can wear mail from level 40")
	eq(Why("MAGE", 16, { classID = ARMOR, subclassID = MAIL, subclassName = "Mail" }), "your class can't wear mail")
	eq(Why("PRIEST", 16, { classID = ARMOR, subclassID = 6, subclassName = "Shields" }), "your class can't wear shields")
	eq(Why("HUNTER", 16, { classID = WEAPON, subclassID = 99, subclassName = "Odd", redText = "Odd" }), "Odd",
		"a type it doesn't know: the red text")
end)

test("assuming training, a weapon type you can learn is judged, and says what to learn", function()
	local ctx = ns.GearForever_Context({ class = "WARRIOR", level = 20, rangedSlot = RANGED_SLOT, assumeTrained = true })
	local greatsword = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 8, ilvl = 20, dps = 15,
		subclassName = "Two-Handed Swords", redSkill = true })
	local v = ns.GearForever_Evaluate(greatsword, { [16] = Sword(20, 10) }, ctx)
	eq(v.kind, "upgrade")
	eq(v.untrained, "Two-Handed Swords")
	local mace = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 4, ilvl = 20, dps = 15,
		subclassName = "One-Handed Maces", redSkill = true })
	local hunter = ns.GearForever_Context({ class = "HUNTER", level = 20, rangedSlot = RANGED_SLOT, assumeTrained = true })
	eq(ns.GearForever_Evaluate(mace, { [16] = Sword(20, 10) }, hunter).kind, "notForYou", "never learnable stays out")
	eq(ns.GearForever_Evaluate(greatsword, { [16] = Sword(20, 10) }, Ctx("WARRIOR")).kind, "notForYou",
		"without the assumption: not yet")
end)

test("a melee weapon a class doesn't swing for damage is a stat stick: its stats decide, not its item level", function()
	local ctx = Ctx("HUNTER", 20)
	local dagger = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, ilvl = 20, dps = 6,
		stats = { PRIMARY = { AGI = 3 } } })
	local lower = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 0, ilvl = 15, dps = 5,
		stats = { PRIMARY = { AGI = 5 } } })
	eq(ns.GearForever_Evaluate(lower, { [16] = dagger }, ctx).kind, "upgrade", "more Agility, five item levels lower")
	local strength = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 7, ilvl = 30, dps = 15,
		stats = { PRIMARY = { STR = 6, AGI = 1 } } })
	eq(ns.GearForever_Evaluate(strength, { [16] = dagger }, ctx).kind, "downgrade", "ten item levels up, but less Agility")
	local bow = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 20, dps = 8 })
	local better = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 20, dps = 10 })
	eq(ns.GearForever_Evaluate(better, { [RANGED_SLOT] = bow }, ctx).kind, "upgrade", "the bow still goes by damage")
	local warrior = ns.GearForever_Evaluate(Sword(30, 10), { [16] = Sword(20, 12) }, Ctx("WARRIOR", 20))
	eq(warrior.kind, "downgrade", "a warrior's sword still goes by damage")
end)

test("a hunter's stat stick counts Agility, Stamina and attack power, not Intellect", function()
	local ctx = Ctx("HUNTER", 20)
	local dagger = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, ilvl = 13, dps = 6,
		stats = { PRIMARY = { AGI = 1 } } })
	local sword = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 8, ilvl = 23, dps = 19,
		stats = { PRIMARY = { STR = 6, INT = 9 } } })
	local v = ns.GearForever_Evaluate(sword, { [16] = dagger }, ctx)
	eq(v.kind, "notForYou")
	eq(v.why, "wrong main stat")
	local stamina = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 0, ilvl = 13, dps = 6,
		stats = { STA = 4, PRIMARY = { INT = 5 } } })
	eq(ns.GearForever_Evaluate(stamina, { [16] = dagger }, ctx).kind, "upgrade", "Stamina counts, the Intellect doesn't")
	local staff = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 10, ilvl = 20,
		stats = { PRIMARY = { INT = 6 } } })
	eq(ns.GearForever_Evaluate(staff, { [16] = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 10,
		ilvl = 20, stats = { PRIMARY = { INT = 2 } } }) }, Ctx("MAGE", 20)).kind, "upgrade", "a caster's staff keeps Intellect")
end)

test("a reason that never goes away comes before the level it needs", function()
	local ctx = Ctx("HUNTER", 16)
	local sword = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 8, ilvl = 23, minLevel = 18,
		stats = { PRIMARY = { STR = 6, INT = 9 } } })
	eq(ns.GearForever_Unusable(sword, ctx), "wrong main stat")
	local mace = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 4, minLevel = 18,
		subclassName = "One-Handed Maces", redSkill = true, stats = { PRIMARY = { AGI = 2 } } })
	eq(ns.GearForever_Unusable(mace, ctx), "your class can't use One-Handed Maces")
	local agile = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, minLevel = 18,
		stats = { PRIMARY = { AGI = 2 } } })
	eq(ns.GearForever_Unusable(agile, ctx), "needs level 18", "only waiting: the level")
	local mail = Item({ equipLoc = "INVTYPE_WRIST", classID = ARMOR, subclassID = MAIL, minLevel = 18,
		subclassName = "Mail", redSkill = true })
	eq(ns.GearForever_Unusable(mail, ctx), "needs level 18", "mail at 40 waits too: the nearer wait first")
end)

test("ParseEquip reads the stats Equip lines give", function()
	local function P(text)
		local key, amount = ns.GearForever_ParseEquip(text)
		return key and (key .. "=" .. amount) or nil
	end
	eq(P("Equip: Increases damage and healing done by magical spells and effects by up to 12."), "SP=12")
	eq(P("Equip: Increases healing done by spells and effects by up to 22."), "HEAL=22")
	eq(P("Equip: Increases damage done by Fire spells and effects by up to 9."), "SPSCHOOL=9")
	eq(P("Equip: Improves your chance to get a critical strike with spells by 1%."), "SCRIT=1")
	eq(P("Equip: Improves your chance to hit with spells by 1%."), "SHIT=1")
	eq(P("Equip: Improves your chance to get a critical strike by 1%."), "MCRIT=1")
	eq(P("Equip: Improves your chance to hit by 2%."), "MHIT=2")
	eq(P("Equip: Increased Defense +7."), "DEF=7")
	eq(P("Equip: Restores 3 mana per 5 sec."), "MP5=3")
	eq(P("Equip: +2 Attack Power."), nil, "the game's own stats have it")
	eq(P("Chance on hit: Blasts the target for 20 Fire damage."), nil)
end)

test("caster stats from Equip lines count for casters, crit for the physical classes", function()
	local ring = function(stats)
		return Item({ equipLoc = "INVTYPE_FINGER", classID = ARMOR, subclassID = 0, ilvl = 20, stats = stats })
	end
	local worn = { [11] = ring({ PRIMARY = { INT = 3 } }), [12] = ring({ PRIMARY = { INT = 3 } }) }
	eq(ns.GearForever_Evaluate(ring({ SP = 12 }), worn, Ctx("MAGE", 20)).kind, "upgrade", "12 spell damage over 3 Intellect")
	local str = { [11] = ring({ PRIMARY = { STR = 3 } }), [12] = ring({ PRIMARY = { STR = 3 } }) }
	eq(ns.GearForever_Evaluate(ring({ SP = 12 }), str, Ctx("WARRIOR", 20)).kind, "downgrade", "spell damage is nothing to him")
	eq(ns.GearForever_Evaluate(ring({ MCRIT = 1 }), str, Ctx("WARRIOR", 20)).kind, "upgrade", "1% crit over 3 Strength")
end)

test("TeacherText names your side's weapon masters for a type", function()
	local masters = {
		{ name = "Archibald", city = "Undercity", faction = "Horde", skills = { 8 } },
		{ name = "Woo Ping", city = "Stormwind", faction = "Alliance", skills = { 8 } },
		{ name = "Hanashi", city = "Orgrimmar", faction = "Horde", skills = { 1, 8 } },
	}
	eq(ns.GearForever_TeacherText(masters, 8, "Horde"), "Taught by Archibald in Undercity or Hanashi in Orgrimmar")
	eq(ns.GearForever_TeacherText(masters, 8, "Alliance"), "Taught by Woo Ping in Stormwind")
	eq(ns.GearForever_TeacherText(masters, 4, "Horde"), nil)
	eq(ns.GearForever_TeacherText(nil, 8, "Horde"), nil)
end)

test("no stats on either at the same level: nothing to choose", function()
	local v = ns.GearForever_Evaluate(Chest(10), { [5] = Chest(10) }, Ctx("WARRIOR"))
	eq(v.kind, "ilvl")
	eq(v.ilvlDiff, 0)
end)

test("stats over a worn item without any is an upgrade", function()
	local v = ns.GearForever_Evaluate(Chest(10, MAIL, { STA = 2 }), { [5] = Chest(10) }, Ctx("WARRIOR"))
	eq(v.kind, "noStats")
end)

test("an empty slot is an upgrade", function()
	local v = ns.GearForever_Evaluate(Chest(5), {}, Ctx("WARRIOR"))
	eq(v.kind, "empty")
	eq(ns.Gear_IsCleanUpgrade(v), true)
end)

test("what you wear says nothing, nor does what has no slot", function()
	local chest = Chest(10)
	eq(ns.GearForever_Evaluate(chest, { [5] = chest }, Ctx("WARRIOR")), nil)
	eq(ns.GearForever_Evaluate(Item({ equipLoc = "INVTYPE_BAG" }), {}, Ctx("WARRIOR")), nil)
end)

test("a weapon judged by its damage isn't ruled out by a stat you don't use", function()
	-- Heavy Shortbow (+1 Strength, 6.0 DPS) over Hickory Shortbow (3.7 DPS) for a hunter.
	local worn = { [RANGED_SLOT] = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 8,
		dps = 3.7 }) }
	local heavy = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 10, dps = 6,
		stats = { PRIMARY = { STR = 1 } } })
	eq(ns.GearForever_Evaluate(heavy, worn, Ctx("HUNTER")).kind, "upgrade")
	-- A melee weapon for a class that judges by damage too, but a strength chest for a hunter is still wrong.
	local sword = Sword(10, 9)
	sword.stats = { PRIMARY = { INT = 2 } }
	eq(ns.GearForever_Evaluate(sword, {}, Ctx("WARRIOR")).kind ~= "notForYou", true)
	eq(ns.GearForever_Evaluate(Chest(10, MAIL, { PRIMARY = { STR = 5 } }), {}, Ctx("HUNTER")).why, "wrong main stat")
end)

test("level requirements, red tooltip lines and the wrong main stat say not for you", function()
	local ctx = Ctx("WARRIOR", 10)
	local high = Chest(30)
	high.minLevel = 25
	local v = ns.GearForever_Evaluate(high, {}, ctx)
	eq(v.kind, "notForYou")
	eq(v.why, "needs level 25")
	local red = Chest(10)
	red.redText = "Mail"
	eq(ns.GearForever_Evaluate(red, {}, ctx).why, "Mail")
	eq(ns.GearForever_Evaluate(Chest(10, CLOTH, { PRIMARY = { INT = 5 } }), {}, ctx).why, "wrong main stat")
	eq(ns.GearForever_Evaluate(Chest(10, CLOTH, { PRIMARY = { INT = 5, STR = 2 } }), {}, ctx).kind, "empty")
end)

test("the level requirement is met on the level itself", function()
	local chest = Chest(20)
	chest.minLevel = 10
	eq(ns.GearForever_Evaluate(chest, {}, Ctx("WARRIOR", 10)).kind, "empty")
end)

test("lighter armor at a higher level warns and isn't a clean upgrade", function()
	local v = ns.GearForever_Evaluate(Chest(14, LEATHER), { [5] = Chest(10, MAIL) }, Ctx("WARRIOR"))
	eq(v.kind, "levelUp")
	eq(v.warnings, 1)
	eq(v.reasons[1], "Lighter armor than yours (Leather)")
	eq(ns.Gear_IsCleanUpgrade(v), false)
	eq(ns.Gear_IsMaybeUpgrade(v), true)
end)

test("lighter armor with less in it is a downgrade, whatever its item level", function()
	local vest = Chest(10, LEATHER, { ARMOR = 33 })
	vest.enchant, vest.enchantText = { STA = 1, ARMOR = 8 }, "Stamina +1 and Armor +8"
	local v = ns.GearForever_Evaluate(Chest(12, CLOTH, { ARMOR = 13 }), { [5] = vest }, Ctx("HUNTER", 12))
	eq(v.kind, "downgrade")
	eq(v.levelDown, nil, "by what's in it")
	eq(#v.reasons, 0, "it stays where it is")
	eq(ns.Gear_Headline(v):find("Downgrade", 1, true) ~= nil, true)
	v = ns.GearForever_Evaluate(Chest(30, CLOTH, { ARMOR = 13 }), { [5] = Chest(10, LEATHER, { ARMOR = 33 }) }, Ctx("HUNTER", 30))
	eq(v.kind, "downgrade", "even far above it")
end)

test("lighter armor with better stats is an upgrade, with the warning", function()
	local v = ns.GearForever_Evaluate(Chest(12, CLOTH, { ARMOR = 13, STA = 8 }), { [5] = Chest(10, LEATHER, { ARMOR = 33 }) },
		Ctx("HUNTER", 12))
	eq(v.kind, "upgradeBut")
	eq(v.warnings, 1)
end)

test("a small item level gap goes by what's on the item", function()
	local worn = { [5] = Chest(10, MAIL, { ARMOR = 100, STR = 10 }) }
	eq(ns.GearForever_Evaluate(Chest(12, MAIL, { ARMOR = 100 }), worn, Ctx("WARRIOR", 12)).kind, "downgrade", "higher, but worse")
	eq(ns.GearForever_Evaluate(Chest(8, MAIL, { ARMOR = 100, STR = 20 }), worn, Ctx("WARRIOR", 12)).kind, "upgrade", "lower, but better")
	eq(ns.GearForever_Evaluate(Chest(14, MAIL, { ARMOR = 100 }), worn, Ctx("WARRIOR", 12)).kind, "downgrade", "4 apart")
end)

test("a clear item level gap still wins while leveling", function()
	local worn = { [5] = Chest(10, MAIL, { ARMOR = 100, STR = 10 }) }
	local v = ns.GearForever_Evaluate(Chest(15, MAIL, { ARMOR = 100 }), worn, Ctx("WARRIOR", 15))
	eq(v.kind, "levelUp")
	eq(v.ilvlDiff, 5)
	v = ns.GearForever_Evaluate(Chest(5, MAIL, { ARMOR = 100, STR = 90 }), worn, Ctx("WARRIOR", 15))
	eq(v.kind, "downgrade")
	eq(v.levelDown, true)
end)

test("with no stats on either, the item level still decides", function()
	local v = ns.GearForever_Evaluate(Chest(12, MAIL), { [5] = Chest(10, MAIL) }, Ctx("WARRIOR", 12))
	eq(v.kind, "levelUp")
	eq(ns.GearForever_Evaluate(Chest(9, MAIL), { [5] = Chest(10, MAIL) }, Ctx("WARRIOR", 12)).kind, "downgrade")
end)

test("what's enchanted counts, and losing it says so", function()
	local kitted = Chest(10, MAIL, { ARMOR = 30 })
	kitted.enchant, kitted.enchantText = { STA = 1, ARMOR = 8 }, "Stamina +1 and Armor +8"
	local plain = Chest(10, MAIL, { ARMOR = 33 })
	eq(ns.GearForever_Evaluate(plain, { [5] = kitted }, Ctx("WARRIOR", 12)).kind, "downgrade", "a little more armor doesn't pay for the kit")
	local better = Chest(16, MAIL, { ARMOR = 80 })
	local v = ns.GearForever_Evaluate(better, { [5] = kitted }, Ctx("WARRIOR", 16))
	eq(v.kind, "levelUp")
	eq(v.warnings, 1)
	eq(v.reasons[1], "You'd lose the enchant on yours (Stamina +1 and Armor +8)")
	better.enchantText = "Agility +1"
	eq(ns.GearForever_Evaluate(better, { [5] = kitted }, Ctx("WARRIOR", 16)).warnings, 0, "the new one has its own")
end)

test("ParseEnchant reads both ways round", function()
	local names = { STA = "Stamina", AGI = "Agility", ARMOR = "Armor" }
	local e = ns.GearForever_ParseEnchant("Stamina +1 and Armor +8", names)
	eq(e.STA, 1)
	eq(e.ARMOR, 8)
	eq(ns.GearForever_ParseEnchant("+3 Agility", names).AGI, 3)
	eq(ns.GearForever_ParseEnchant("Minor Speed Increase", names), nil, "nothing it can count")
	eq(ns.GearForever_ParseEnchant(nil, names), nil)
end)

test("heavier armor doesn't warn", function()
	local v = ns.GearForever_Evaluate(Chest(14, MAIL), { [5] = Chest(10, LEATHER) }, Ctx("WARRIOR"))
	eq(v.warnings, 0)
end)

test("a downgrade in lighter armor just says downgrade", function()
	local v = ns.GearForever_Evaluate(Chest(8, LEATHER), { [5] = Chest(10, MAIL) }, Ctx("WARRIOR"))
	eq(v.kind, "downgrade")
	eq(#v.reasons, 0)
end)

test("melee classes judge weapons by damage, whatever the item level", function()
	local ctx = Ctx("ROGUE")
	local worn = { [16] = Sword(10, 8) }
	local v = ns.GearForever_Evaluate(Sword(5, 10), worn, ctx)
	eq(v.kind, "upgrade")
	H.near(v.pct, 25, 0.01)
	eq(v.reasons[1], "10.0 damage per second, yours 8.0")
	eq(ns.GearForever_Evaluate(Sword(20, 6), worn, ctx).kind, "downgrade")
	eq(ns.GearForever_Evaluate(Sword(20, 8), worn, ctx).kind, "sidegrade")
end)

test("casters judge melee weapons by item level", function()
	local v = ns.GearForever_Evaluate(Sword(14, 2), { [16] = Sword(10, 8) }, Ctx("MAGE"))
	eq(v.kind, "levelUp")
end)

test("a two-hander takes on both hands' damage", function()
	local two = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 8, ilvl = 12, dps = 12 })
	local worn = { [16] = Sword(10, 8), [17] = Sword(10, 6) }
	eq(ns.GearForever_Evaluate(two, worn, Ctx("WARRIOR")).pct < 0, true)
	two.dps = 20
	eq(ns.GearForever_Evaluate(two, worn, Ctx("WARRIOR")).kind, "upgrade")
end)

test("a one-hander over a two-hander asks for an off-hand", function()
	local two = Item({ equipLoc = "INVTYPE_2HWEAPON", classID = WEAPON, subclassID = 8, ilvl = 12, dps = 12 })
	eq(ns.GearForever_Evaluate(Sword(14, 20), { [16] = two }, Ctx("WARRIOR")).kind, "pair")
end)

test("a dual wielder's new weapon replaces the weaker hand", function()
	local worn = { [16] = Sword(10, 8), [17] = Sword(10, 6) }
	local v = ns.GearForever_Evaluate(Sword(10, 7), worn, Ctx("ROGUE"))
	eq(v.slot, 17)
	eq(v.kind, "upgrade")
end)

test("ranged weapons go to the ranged slot, not the main hand", function()
	local bow = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 12, dps = 9 })
	local v = ns.GearForever_Evaluate(bow, { [16] = Sword(10, 8) }, Ctx("HUNTER"))
	eq(v.kind, "empty")
	eq(v.slot, RANGED_SLOT)
end)

test("hunters judge ranged weapons by damage, melee by item level", function()
	local ctx = Ctx("HUNTER")
	local worn = { [RANGED_SLOT] = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 12, dps = 8 }) }
	local bow = Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = 8, dps = 10 })
	eq(ns.GearForever_Evaluate(bow, worn, ctx).kind, "upgrade")
	local melee = { [16] = Sword(10, 20) }
	eq(ns.GearForever_Evaluate(Sword(14, 2), melee, ctx).kind, "levelUp")
end)

test("casters judge wands by damage, a warrior's bow by item level", function()
	local wand = function(ilvl, dps)
		return Item({ equipLoc = "INVTYPE_RANGEDRIGHT", classID = WEAPON, subclassID = WAND, ilvl = ilvl, dps = dps })
	end
	eq(ns.GearForever_Evaluate(wand(8, 10), { [RANGED_SLOT] = wand(12, 8) }, Ctx("MAGE")).kind, "upgrade")
	local bow = function(ilvl, dps)
		return Item({ equipLoc = "INVTYPE_RANGED", classID = WEAPON, subclassID = BOW, ilvl = ilvl, dps = dps })
	end
	eq(ns.GearForever_Evaluate(bow(14, 2), { [RANGED_SLOT] = bow(10, 9) }, Ctx("WARRIOR")).kind, "levelUp")
end)

test("thrown weapons and relics have a slot only with a ranged slot", function()
	local thrown = Item({ equipLoc = "INVTYPE_THROWN", classID = WEAPON, subclassID = 16, ilvl = 5 })
	eq(ns.GearForever_Evaluate(thrown, {}, Ctx("ROGUE")).slot, RANGED_SLOT)
	local noSlot = ns.GearForever_Context({ class = "ROGUE", level = 20 })
	eq(ns.GearForever_Evaluate(thrown, {}, noSlot), nil)
end)

test("rings replace the lower item level while leveling, and the empty finger first", function()
	local ring = function(ilvl)
		return Item({ equipLoc = "INVTYPE_FINGER", classID = ARMOR, subclassID = 0, ilvl = ilvl })
	end
	eq(ns.GearForever_Evaluate(ring(10), { [11] = ring(8) }, Ctx("MAGE")).slot, 12)
	local v = ns.GearForever_Evaluate(ring(10), { [11] = ring(12), [12] = ring(8) }, Ctx("MAGE"))
	eq(v.slot, 12)
	eq(v.kind, "levelUp")
	eq(v.ilvlDiff, 2)
end)

test("a unique ring replaces its own copy, not the weaker ring", function()
	local ring = function(id, ilvl)
		return Item({ equipLoc = "INVTYPE_FINGER", classID = ARMOR, subclassID = 0, ilvl = ilvl, itemID = id,
			unique = { max = 1 } })
	end
	local other = Item({ equipLoc = "INVTYPE_FINGER", classID = ARMOR, subclassID = 0, ilvl = 8, itemID = 2 })
	eq(ns.GearForever_Evaluate(ring(1, 12), { [11] = ring(1, 10), [12] = other }, Ctx("MAGE")).slot, 11)
end)

test("a unique weapon you wear in the other hand says so", function()
	local unique = function(dps)
		local sword = Sword(10, dps)
		sword.itemID, sword.unique = 1, { max = 1 }
		return sword
	end
	local v = ns.GearForever_Evaluate(unique(9), { [16] = unique(8), [17] = Sword(10, 6) }, Ctx("ROGUE"))
	eq(v.kind, "notForYou")
	eq(v.why, "unique, you already wear one")
end)

test("at the level cap stats decide, not item level", function()
	local ctx = Ctx("WARRIOR", 60)
	eq(ctx.leveling, false)
	local worn = { [5] = Chest(50, MAIL, { PRIMARY = { STR = 10 } }) }
	eq(ns.GearForever_Evaluate(Chest(60, MAIL, { STA = 2 }), worn, ctx).kind, "downgrade")
end)

test("turning the setting off makes stats decide while leveling", function()
	local ctx = Ctx("WARRIOR", 20, false)
	eq(ctx.leveling, false)
end)

test("an unknown class can use every main stat", function()
	eq(ns.GearForever_Evaluate(Chest(10, CLOTH, { PRIMARY = { INT = 5 } }), {}, Ctx("MONK")).kind, "empty")
end)

test("spirit counts for casters, not for a rogue", function()
	local worn = { [5] = Chest(10, CLOTH, { STA = 4 }) }
	eq(ns.GearForever_Evaluate(Chest(10, CLOTH, { STA = 4, SPI = 4 }), worn, Ctx("PRIEST")).kind, "upgrade")
	eq(ns.GearForever_Evaluate(Chest(10, CLOTH, { STA = 4, SPI = 4 }), worn, Ctx("ROGUE")).kind, "sidegrade")
end)

test("armor splits two items that are otherwise the same", function()
	local worn = { [5] = Chest(10, MAIL, { ARMOR = 100 }) }
	eq(ns.GearForever_Evaluate(Chest(10, MAIL, { ARMOR = 120 }), worn, Ctx("WARRIOR")).kind, "upgrade")
end)

test("a weapon whose skill is well behind warns and isn't a clean upgrade", function()
	local ctx = ns.GearForever_Context({ class = "ROGUE", level = 20, rangedSlot = RANGED_SLOT,
		weaponSkills = { [15] = { name = "Daggers", rank = 5, max = 100 }, [7] = { name = "Swords", rank = 98, max = 100 } } })
	local dagger = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, ilvl = 10, dps = 12 })
	local v = ns.GearForever_Evaluate(dagger, { [16] = Sword(10, 8) }, ctx)
	eq(v.kind, "upgradeBut")
	eq(v.warnings, 1)
	eq(v.reasons[1], "Your Daggers skill is behind (5/100)")
	eq(ns.Gear_IsCleanUpgrade(v), false)
end)

test("no skill warning for a trained weapon, or the kind you already swing", function()
	local skills = { [15] = { name = "Daggers", rank = 5, max = 100 }, [7] = { name = "Swords", rank = 95, max = 100 } }
	local ctx = ns.GearForever_Context({ class = "ROGUE", level = 20, rangedSlot = RANGED_SLOT, weaponSkills = skills })
	eq(ns.GearForever_Evaluate(Sword(10, 12), { [16] = Sword(10, 8) }, ctx).kind, "upgrade", "trained")
	local dagger = function(dps)
		return Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, ilvl = 10, dps = dps })
	end
	eq(ns.GearForever_Evaluate(dagger(12), { [16] = dagger(8) }, ctx).kind, "upgrade", "same kind")
	eq(ns.GearForever_Evaluate(dagger(12), {}, ctx).kind, "empty", "empty hand")
end)

test("a skill warning stops a level-up being clean too", function()
	local ctx = ns.GearForever_Context({ class = "MAGE", level = 20, rangedSlot = RANGED_SLOT,
		weaponSkills = { [15] = { name = "Daggers", rank = 5, max = 100 } } })
	local dagger = Item({ equipLoc = "INVTYPE_WEAPON", classID = WEAPON, subclassID = 15, ilvl = 14 })
	local v = ns.GearForever_Evaluate(dagger, { [16] = Sword(10, 8) }, ctx)
	eq(v.kind, "levelUp")
	eq(ns.Gear_IsCleanUpgrade(v), false)
end)

test("verdicts read through retail's headline", function()
	local headline, color = ns.Gear_Headline(ns.GearForever_Evaluate(Chest(14), { [5] = Chest(10) }, Ctx("WARRIOR")))
	eq(headline, "Upgrade (+4 item level): equip it")
	eq(color, "green")
end)

test("the reward pick takes the biggest item level gain", function()
	local worn = { [5] = Chest(10) }
	local ctx = Ctx("WARRIOR")
	local best = ns.Gear_PickReveals({
		{ verdict = ns.GearForever_Evaluate(Chest(12), worn, ctx) },
		{ verdict = ns.GearForever_Evaluate(Chest(16), worn, ctx) },
	}, 0)
	eq(#best, 1)
	eq(best[1].verdict.ilvlDiff, 6)
end)

test("ParseDps reads Blizzard's template, also with a decimal comma", function()
	local pattern = ns.Gear_FormatPattern("(%s damage per second)")
	eq(ns.GearForever_ParseDps("(12.5 damage per second)", pattern), 12.5)
	eq(ns.GearForever_ParseDps("(12,5 damage per second)", pattern), 12.5)
	eq(ns.GearForever_ParseDps("Durability 10 / 10", pattern), nil)
	eq(ns.GearForever_ParseDps(nil, pattern), nil)
	eq(ns.GearForever_ParseDps("(12.5 damage per second)", nil), nil)
end)

test("NewItems finds what's new and second copies", function()
	local new, now = ns.GearForever_NewItems({}, { "a", "b" })
	eq(#new, 2)
	new, now = ns.GearForever_NewItems(now, { "a", "b" })
	eq(#new, 0)
	new, now = ns.GearForever_NewItems(now, { "a", "a", "b", "c" })
	eq(#new, 2)
	eq(new[1], "a")
	eq(new[2], "c")
	new = ns.GearForever_NewItems(now, { "a" })
	eq(#new, 0)
end)

H.done()
