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
