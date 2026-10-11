local addonName, ns = ...

-- Alts: which crafted items a character can use, upgrade marks, crafting quality and profession gear (pure logic,
-- tested with plain Lua). The saved-data layout is described in PlanData.lua.

local floor, max, min = math.floor, math.max, math.min

---------------------------------------------------------------------------------------------------------------
-- Gear for a character (Crafting tab's "Gear for" filter): which crafted items a character can use, and how the
-- item level of a craft compares with what they wear.

local ARMOR, WEAPON, PROFESSION = 4, 2, 19 -- Enum.ItemClass
-- Enum.ItemArmorSubclass: Cloth 1, Leather 2, Mail 3, Plate 4 (Generic 0: rings, necks, trinkets; Shield 6).
local ARMOR_FOR_CLASS = {
	WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
	HUNTER = 3, SHAMAN = 3, EVOKER = 3,
	ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
	PRIEST = 1, MAGE = 1, WARLOCK = 1,
}
local BODY_LOCS = {
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true,
	INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}
local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local HOLDABLE_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, MONK = true,
	PALADIN = true, EVOKER = true }
-- Enum.ItemWeaponSubclass a class can equip: Axe1H 0, Axe2H 1, Bows 2, Guns 3, Mace1H 4, Mace2H 5, Polearm 6,
-- Sword1H 7, Sword2H 8, Warglaive 9, Staff 10, Unarmed (fist) 13, Dagger 15, Crossbow 18, Wand 19. Only hunters use
-- bows, guns and crossbows (warriors lost them in Legion).
local function Set(list)
	local t = {}
	for _, v in ipairs(list) do
		t[v] = true
	end
	return t
end
local WEAPONS = {
	WARRIOR = Set({ 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 }),
	PALADIN = Set({ 0, 1, 4, 5, 6, 7, 8 }),
	DEATHKNIGHT = Set({ 0, 1, 4, 5, 6, 7, 8 }),
	HUNTER = Set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18 }),
	SHAMAN = Set({ 0, 1, 4, 5, 10, 13, 15 }),
	EVOKER = Set({ 0, 1, 4, 5, 7, 8, 10, 13, 15 }),
	ROGUE = Set({ 0, 4, 7, 13, 15 }),
	DRUID = Set({ 4, 5, 6, 10, 13, 15 }),
	MONK = Set({ 0, 4, 6, 7, 10, 13 }),
	DEMONHUNTER = Set({ 0, 7, 9, 13 }),
	PRIEST = Set({ 4, 10, 15, 19 }),
	MAGE = Set({ 7, 10, 15, 19 }),
	WARLOCK = Set({ 7, 10, 15, 19 }),
}
-- Enum.ItemProfessionSubclass by profession base skill line.
local PROF_SUBCLASS = {
	[164] = 0, [165] = 1, [171] = 2, [182] = 3, [185] = 4, [186] = 5, [197] = 6, [202] = 7, [333] = 8, [356] = 9,
	[393] = 10, [755] = 11, [773] = 12, [794] = 13,
}

-- Can character c use a crafted item? item = { classID, subclassID, equipLoc, primaries = { AGI = true, ... } | nil
-- (nil while its stats load: not held against it) }. Returns false, "gear" or "tool" (a profession tool or accessory
-- for one of c's professions). Armor of c's type, weapons c's class can equip, cloaks, rings, necks and trinkets;
-- anything with a main stat needs c's (c.primary, when known).
function ns.Alts_GearFor(item, c)
	if not (item and c and c.class) then
		return false
	end
	if item.classID == PROFESSION then
		for _, prof in pairs(c.profs or {}) do
			if PROF_SUBCLASS[prof.base] ~= nil and PROF_SUBCLASS[prof.base] == item.subclassID then
				return "tool"
			end
		end
		return false
	end
	local loc = item.equipLoc
	if item.classID == ARMOR then
		if BODY_LOCS[loc] then
			if item.subclassID ~= ARMOR_FOR_CLASS[c.class] then
				return false
			end
		elseif loc == "INVTYPE_SHIELD" then
			if not SHIELD_CLASSES[c.class] then
				return false
			end
		elseif loc == "INVTYPE_HOLDABLE" then
			if not HOLDABLE_CLASSES[c.class] then
				return false
			end
		elseif not (loc == "INVTYPE_CLOAK" or loc == "INVTYPE_NECK" or loc == "INVTYPE_FINGER" or loc == "INVTYPE_TRINKET") then
			return false -- shirts, tabards, cosmetics
		end
	elseif item.classID == WEAPON then
		if not (WEAPONS[c.class] and WEAPONS[c.class][item.subclassID]) then
			return false
		end
		if loc == "INVTYPE_WEAPONOFFHAND" and (c.class == "PALADIN" or c.class == "PRIEST" or c.class == "MAGE"
			or c.class == "WARLOCK" or c.class == "DRUID" or c.class == "EVOKER") then
			return false -- off-hand weapons need dual wield
		end
	else
		return false
	end
	if item.primaries and next(item.primaries) and c.primary and not item.primaries[c.primary] then
		return false
	end
	return "gear"
end

-- Worn slots an equip location goes in (Gear Check's slot numbers).
local ITEM_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}
local SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
	[9] = "Wrist", [10] = "Hands", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
	[16] = "Main hand", [17] = "Off hand",
}

-- What a crafted item would replace on a character: { slot, name, ilvl (nil: the slot is empty), loading,
-- twoHand (an off-hand item while a two-hander is worn: can't be told) }. worn = { [slot] = ilvl | false (worn,
-- item level not loaded yet), twoHand = true when the main hand is a two-hander, offWeapon = true when the off hand
-- holds a weapon (not a shield or held-in-off-hand item; missing counts as not a weapon) }. Of two slots (rings,
-- trinkets) the lower one; a one-hander goes against the off hand only when a weapon is worn there. nil for things
-- that aren't worn gear (profession tools).
function ns.Alts_WornFor(equipLoc, worn)
	local slots = ITEM_SLOTS[equipLoc]
	if not slots then
		return nil
	end
	if equipLoc == "INVTYPE_WEAPON" and (worn[17] == nil or not worn.offWeapon) then
		slots = { 16 }
	elseif slots[1] == 17 and worn.twoHand then
		return { slot = 17, name = SLOT_NAMES[17], twoHand = true }
	end
	local best
	for _, slot in ipairs(slots) do
		local ilvl = worn[slot]
		if ilvl == nil then
			return { slot = slot, name = SLOT_NAMES[slot] } -- an empty slot is the one it goes in
		elseif ilvl == false then
			return { slot = slot, name = SLOT_NAMES[slot], loading = true }
		elseif not best or ilvl < best.ilvl then
			best = { slot = slot, name = SLOT_NAMES[slot], ilvl = ilvl }
		end
	end
	return best
end

-- The upgrade mark for a craft: lo, hi = the item level at the lowest and highest crafting quality; target from
-- Alts_WornFor. Returns kind, gain: "empty" (nothing worn there), "sure" (an upgrade at every quality, gain at the
-- lowest), "top" (only at the higher qualities, gain at the highest), "no" (not an upgrade at any quality), nil when
-- it can't be told (item levels unknown or loading).
function ns.Alts_Upgrade(lo, hi, target)
	if not (target and hi) or target.loading or target.twoHand then
		return nil
	end
	lo = lo or hi
	if not target.ilvl then
		return "empty", nil
	elseif lo > target.ilvl then
		return "sure", lo - target.ilvl
	elseif hi > target.ilvl then
		return "top", hi - target.ilvl
	end
	return "no", hi - target.ilvl
end

-- Crafting quality ------------------------------------------------------------------------------------------------

-- How many qualities a recipe can be crafted at (1 when it has none).
function ns.Alts_Qualities(recipe)
	return max(recipe and recipe.nq or 1, recipe and recipe.outQ and #recipe.outQ or 1)
end

-- A quality the recipe has: q (1, 2, ...) brought within the recipe's qualities; nil for "any" (nil or "range").
function ns.Alts_ClampQuality(recipe, q)
	q = tonumber(q)
	if not q then
		return nil
	end
	return min(max(floor(q), 1), ns.Alts_Qualities(recipe))
end

-- The links to compare a craft by: lo, hi = the output at the lowest and highest quality, or both at quality q
-- (Alts_ClampQuality) once every quality's link has been read. Third value: true when q was applied.
function ns.Alts_QualityLinks(recipe, q)
	local out = recipe and recipe.out
	if not out then
		return nil, nil, false
	end
	q = ns.Alts_ClampQuality(recipe, q)
	local all = recipe.outQ
	if q and all and #all > 0 then
		local link = all[min(q, #all)]
		return link, link, true
	end
	return out[1], out[2], false
end

---------------------------------------------------------------------------------------------------------------
-- Profession gear: each profession has a tool slot and accessory slots (two; cooking one; archaeology none).
-- Worn profession gear is stored per character (Collect.lua, slots 20-30); an item's profession is its subclass.

local ARCHAEOLOGY = 794 -- base skill line; it has no gear slots
local PROF_BY_SUBCLASS = {}
for base, sub in pairs(PROF_SUBCLASS) do
	if base ~= ARCHAEOLOGY then
		PROF_BY_SUBCLASS[sub] = base
	end
end
local ACCESSORY_SLOTS = { [185] = 1 } -- cooking; every other profession has two
local KIND_NAMES = { tool = "Tool", acc = "Accessory" }

-- The profession (base skill line) and kind ("tool" | "acc") of a profession item, nil for anything else.
function ns.Alts_ProfItem(classID, subclassID, equipLoc)
	if classID ~= PROFESSION then
		return nil
	end
	local base = PROF_BY_SUBCLASS[subclassID]
	local kind = equipLoc == "INVTYPE_PROFESSION_TOOL" and "tool" or equipLoc == "INVTYPE_PROFESSION_GEAR" and "acc" or nil
	if base and kind then
		return base, kind
	end
	return nil
end

-- How many slots of a kind a profession has.
function ns.Alts_ProfSlots(base, kind)
	if base == ARCHAEOLOGY or not PROF_SUBCLASS[base] then
		return 0
	end
	return kind == "tool" and 1 or (ACCESSORY_SLOTS[base] or 2)
end

-- What a profession item would replace: like Alts_WornFor ({ name, ilvl (nil: a slot is free), loading }).
-- worn = { { base, kind, ilvl (number | false while loading) } } (all of a character's profession gear). Of two
-- accessories the lower one. nil when the profession has no such slot.
function ns.Alts_ProfTarget(worn, base, kind)
	local slots = ns.Alts_ProfSlots(base, kind)
	if slots == 0 then
		return nil
	end
	local name = KIND_NAMES[kind]
	local same = {}
	for _, w in ipairs(worn) do
		if w.base == base and w.kind == kind then
			same[#same + 1] = w
		end
	end
	if #same < slots then
		return { name = name }
	end
	local best
	for _, w in ipairs(same) do
		if w.ilvl == false then
			return { name = name, loading = true }
		elseif not best or w.ilvl < best.ilvl then
			best = { name = name, ilvl = w.ilvl }
		end
	end
	return best
end

-- The best craft for a profession slot: candidates = { { recipeID, lo, hi, known (somebody knows it) } }, target from
-- Alts_ProfTarget. Known recipes only, highest item level first (then the cheaper lowest quality). Returns the
-- candidate with mark and gain (Alts_Upgrade) when it's an upgrade ("sure", "top" or "empty"), else nil.
function ns.Alts_BestProfCraft(candidates, target)
	local best
	for _, cand in ipairs(candidates) do
		if cand.known and cand.hi and (not best or cand.hi > best.hi or (cand.hi == best.hi and (cand.lo or 0) > (best.lo or 0))) then
			best = cand
		end
	end
	if not best then
		return nil
	end
	local mark, gain = ns.Alts_Upgrade(best.lo, best.hi, target)
	if mark == "sure" or mark == "top" or mark == "empty" then
		return { recipeID = best.recipeID, lo = best.lo, hi = best.hi, mark = mark, gain = gain }
	end
	return nil
end

-- A bag item's best home among the characters: items = { ilvl, base, kind }, targets = { { guid, target } } (other
-- characters that have the profession, with their Alts_ProfTarget). The character it improves most: { guid, gain }
-- (gain nil for an empty slot, which comes first), nil when it's nobody's upgrade.
function ns.Alts_ProfBagUpgrade(ilvl, targets)
	local best
	for _, t in ipairs(targets) do
		local mark, gain = ns.Alts_Upgrade(ilvl, ilvl, t.target)
		if mark == "empty" or mark == "sure" then
			local better = not best or (best.gain ~= nil and (gain == nil or gain > best.gain))
			if better then
				best = { guid = t.guid, gain = gain }
			end
		end
	end
	return best
end
