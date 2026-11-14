local addonName, ns = ...

-- Leveling (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_leveling.lua). Ammo,
-- armor kits and the ammo counter: what to load, buy and put on. Moved out of Data.lua; read by Read.lua, AmmoCounter.lua
-- and ArmorKit.lua.

local WEAPON_BOWS, WEAPON_GUNS, WEAPON_CROSSBOW = 2, 3, 18 -- Enum.ItemWeaponSubclass
local AMMO_CLASS = 6 -- Enum.ItemClass.Projectile
local AMMO_ARROW, AMMO_BULLET = 2, 3 -- warcraft.wiki.gg ItemType: Projectile's subclasses
local AMMO_FOR = { [WEAPON_BOWS] = AMMO_ARROW, [WEAPON_CROSSBOW] = AMMO_ARROW, [WEAPON_GUNS] = AMMO_BULLET }
local AUTO_BUDGET_SHARE = 0.25 -- of your money, at most, on one automatic ammo purchase

local ICONS = ns.LEVELING_ICONS -- Data.lua, earlier in the TOC

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

-- "none" | "low" | "ok" | "switch", nil when this character doesn't use ammo. count: of what's in the slot. equippedFits:
-- false when that ammo doesn't go with your weapon (arrows with a gun), which leaves none to shoot. spare: ammo in your
-- bags that fits and isn't in the slot ({ name, count }): with nothing to shoot it's "switch" (equip it), not "none".
function ns.Leveling_AmmoState(needs, count, low, equippedFits, spare)
	if not needs then
		return nil
	end
	local usable = equippedFits ~= false and (count or 0) or 0
	if usable <= 0 then
		return (spare and (spare.count or 0) > 0) and "switch" or "none"
	end
	return usable <= low and "low" or "ok"
end

-- The line about ammo to equip: "Heavy Shot: 1,200 in your bags. Click the ammo counter to put it on." spare.countText:
-- its count as shown.
function ns.Leveling_SwitchText(spare)
	return ("%s: %s in your bags. Click the ammo counter to put it on."):format(spare.name or "Ammo that fits",
		spare.countText or tostring(spare.count or 0))
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
-- (the item's, nil until it has loaded), countText, icon, switch (Leveling_AmmoState's spare: ammo that fits is in the
-- bags, not in the slot) } and { kind = "reagent", name (the spell's), count }.
function ns.Leveling_SupplyToast(entries)
	local ammo, hasReagents, lines = nil, false, {}
	for _, e in ipairs(entries) do
		if e.kind == "ammo" then
			ammo = e
			if e.switch then
				lines[#lines + 1] = ns.Leveling_SwitchText(e.switch)
			elseif not e.out then
				lines[#lines + 1] = ("%s: %s left."):format(e.name or "Ammo", e.countText)
			end
		else
			hasReagents = true
			lines[#lines + 1] = ("%s: %d %s left."):format(e.name, e.count, e.count == 1 and "cast" or "casts")
		end
	end
	if ammo and not ammo.switch then
		lines[#lines + 1] = "Buy more at a vendor."
	end
	local title
	if ammo and ammo.switch then
		title = hasReagents and "Equip your ammo, low on reagents" or "Equip your ammo"
	elseif ammo and ammo.out then
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
