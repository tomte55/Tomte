local addonName, ns = ...

-- Rogue Poisons: pure logic (no WoW API calls; unit-tested in tests/test_rogue.lua). Which poisons a rogue should
-- have on, which ones to offer when one is missing or about to run out, and Handy Lockpick's lockbox check and
-- macros.

-- Poison spell IDs (the weapon buff on the player has the same ID). Lethal ones in the order they're offered
-- when you haven't picked one yet; Assassination prefers Deadly Poison, the other specs Instant Poison.
ns.ROGUE_LETHAL = { 2823, 315584, 8679, 381664 } -- Deadly, Instant, Wound, Amplifying
ns.ROGUE_NONLETHAL = { 3408, 381637, 5761 } -- Crippling, Atrophic, Numbing
ns.ROGUE_DRAGON_TEMPERED_BLADES = 381801 -- talent: two lethal and two non-lethal poisons at once
local DEADLY, INSTANT = 2823, 315584
local SPEC_ASSASSINATION = 259

local KIND = {}
for _, id in ipairs(ns.ROGUE_LETHAL) do
	KIND[id] = "lethal"
end
for _, id in ipairs(ns.ROGUE_NONLETHAL) do
	KIND[id] = "nonLethal"
end

-- "lethal", "nonLethal" or nil.
function ns.Rogue_PoisonKind(spellID)
	return KIND[spellID]
end

-- Order to offer poisons of one kind in: what this character applied last first, then the default order.
local function Order(kind, specID, last)
	local order, seen = {}, {}
	local function add(id)
		if id and KIND[id] == kind and not seen[id] then
			seen[id] = true
			order[#order + 1] = id
		end
	end
	for _, id in ipairs(last or {}) do
		add(id)
	end
	if kind == "lethal" then
		if specID == SPEC_ASSASSINATION then
			add(DEADLY)
		else
			add(INSTANT)
		end
		for _, id in ipairs(ns.ROGUE_LETHAL) do
			add(id)
		end
	else
		for _, id in ipairs(ns.ROGUE_NONLETHAL) do
			add(id)
		end
	end
	return order
end

-- Remembers the poison just applied at the front of its kind's list (kept to 4 entries).
function ns.Rogue_RememberPoison(last, spellID)
	if not KIND[spellID] then
		return last
	end
	last = last or {}
	for i = #last, 1, -1 do
		if last[i] == spellID then
			table.remove(last, i)
		end
	end
	table.insert(last, 1, spellID)
	while #last > 4 do
		table.remove(last)
	end
	return last
end

-- What's wrong with the poisons. s = {
--   known = { [spellID] = true }, the poisons this character can cast
--   active = { [spellID] = seconds left (math.huge when unknown) }, the poisons on the weapons
--   twoEach = Dragon-Tempered Blades (two of each kind),
--   specID, last = { lethal = { ids }, nonLethal = { ids } } (newest first),
-- }
-- rules = { lethal = bool, nonLethal = bool, lowSeconds = number }.
-- Returns a list of { spellID, kind, reason = "missing" | "low", left = seconds (low only) }: lethal first, low
-- ones before missing ones within a kind.
function ns.Rogue_PoisonProblems(s, rules)
	local problems = {}
	for _, kind in ipairs({ "lethal", "nonLethal" }) do
		if rules[kind] then
			local want = s.twoEach and 2 or 1
			local order = Order(kind, s.specID, s.last and s.last[kind])
			local on, missing = 0, {}
			for _, id in ipairs(order) do
				local left = s.active[id]
				if left then
					on = on + 1
					if left < rules.lowSeconds then
						problems[#problems + 1] = { spellID = id, kind = kind, reason = "low", left = left }
					end
				end
			end
			for _, id in ipairs(order) do
				if on + #missing >= want then
					break
				end
				if s.known[id] and not s.active[id] then
					missing[#missing + 1] = { spellID = id, kind = kind, reason = "missing" }
				end
			end
			for _, p in ipairs(missing) do
				problems[#problems + 1] = p
			end
		end
	end
	return problems
end

-- "42 min", "3 min", "45 sec".
function ns.Rogue_FormatLeft(seconds)
	if seconds >= 60 then
		return math.floor(seconds / 60) .. " min"
	end
	return math.max(0, math.floor(seconds)) .. " sec"
end

-- World of Warcraft: Forever ----------------------------------------------------------------------------------------

-- Poisons are bag items there, one on each weapon. Read in Forever.lua.
ns.ROGUE_FOREVER_POISONS_SPELL = 2842 -- the Poisons skill, learned at level 20
ns.ROGUE_FOREVER_SLOTS = { 16, 17 } -- main and off hand (INVSLOT_MAINHAND, INVSLOT_OFFHAND)
-- Enum.ItemClass.Weapon, and the Enum.ItemWeaponSubclass values that aren't real weapons: Generic and Fishingpole.
local WEAPON_CLASS = 2
local NO_POISON_SUBCLASS = { [14] = true, [20] = true }
local IMBUE = 3 -- Enum.ItemEnchantType.Imbue

function ns.Rogue_TakesPoison(classID, subclassID)
	return classID == WEAPON_CLASS and not NO_POISON_SUBCLASS[subclassID]
end

-- Seconds left on a weapon's poison, nil when it has none. enchants: C_Item.GetWeaponEnchantInfo's list, timeLeft in
-- milliseconds. A poison sits beside a stone there; a poison has charges and a stone doesn't, or it's an Imbue.
function ns.Rogue_ForeverPoisonLeft(enchants)
	for _, e in ipairs(enchants) do
		if e.hasEnchant and ((e.charges or 0) > 0 or e.enchantType == IMBUE) then
			return (e.timeLeft and e.timeLeft > 0) and e.timeLeft / 1000 or math.huge
		end
	end
	return nil
end

-- The family to offer: the one last used on this weapon when it's in the bags, else the first one that is. Returns
-- its key and its highest rank in the bags, or nil. families: lowest rank first; bags: { [itemID] = count }.
local function PickPoison(families, bags, last)
	local function best(family)
		for i = #family.items, 1, -1 do
			if (bags[family.items[i]] or 0) > 0 then
				return family.items[i]
			end
		end
		return nil
	end
	for _, family in ipairs(families) do
		if family.key == last and best(family) then
			return family.key, best(family)
		end
	end
	for _, family in ipairs(families) do
		if best(family) then
			return family.key, best(family)
		end
	end
	return nil
end

-- What's wrong with the poisons. s = {
--   weapons = { { slot, left = seconds | nil (no poison) } }, the weapons that take a poison,
--   families (Data/Forever/Rogue.lua), bags = { [itemID] = count }, last = { [slot] = family key },
--   known = the Poisons skill is learned,
-- }
-- rules = { lowSeconds = number }. Returns a list of { slot, reason = "missing" | "low", left (low only), family,
-- itemID }; no itemID when the bags have no poison to apply. Nothing for a rogue with neither the skill nor a poison.
function ns.Rogue_ForeverProblems(s, rules)
	local problems = {}
	local anyInBags = false
	for _, family in ipairs(s.families) do
		for _, id in ipairs(family.items) do
			anyInBags = anyInBags or (s.bags[id] or 0) > 0
		end
	end
	if not (s.known or anyInBags) then
		return problems
	end
	for _, weapon in ipairs(s.weapons) do
		if not weapon.left or weapon.left < rules.lowSeconds then
			local family, itemID = PickPoison(s.families, s.bags, s.last and s.last[weapon.slot])
			problems[#problems + 1] = { slot = weapon.slot, reason = weapon.left and "low" or "missing",
				left = weapon.left, family = family, itemID = itemID }
		end
	end
	return problems
end

-- Remembers the family just applied to a weapon. last is the character's saved table.
function ns.Rogue_ForeverRemember(last, slot, family)
	last.forever = last.forever or {} -- [slot] = family key
	last.forever[slot] = family
end

-- The macro that applies a poison item to a weapon: using the item leaves it waiting for a target, then /use picks
-- the equipped slot.
function ns.Rogue_ForeverMacro(itemID, slot)
	return ("/use item:%d\n/use %d"):format(itemID, slot)
end

-- Handy Lockpick --------------------------------------------------------------------------------------------------

ns.ROGUE_PICK_LOCK = 1804
ns.ROGUE_SKELETON_PINKIE = 312890 -- Mechagnome racial: opens lockboxes like Pick Lock
-- The lock line sits right under the name and quality lines; a description further down may use the same word.
local LOCK_LINES = 5
-- Colorblind mode puts a short marker in front of the line ("[-]").
local LOCK_PREFIX = 6

local function IsRed(r, g, b)
	return type(r) == "number" and r > 0.9 and (g or 0) < 0.35 and (b or 0) < 0.35
end

-- Whether an item tooltip says the item is locked. lines = { { text, r, g, b } } in tooltip order; locked =
-- Blizzard's LOCKED text in the client's language. Returns "pickable", "tooHard" (the line is red: your skill
-- can't open it) or nil (not locked).
function ns.Rogue_LockState(lines, locked)
	if type(locked) ~= "string" or locked == "" then
		return nil
	end
	for i = 2, math.min(#lines, LOCK_LINES) do
		local line = lines[i]
		local text = line and line.text
		if type(text) == "string" and #text >= #locked and #text <= #locked + LOCK_PREFIX
			and text:sub(-#locked) == locked then
			return IsRed(line.r, line.g, line.b) and "tooHard" or "pickable"
		end
	end
	return nil
end

-- The macro that picks the lock of the item in bag, slot. [@none] keeps the spell waiting for a target, so a soft
-- (interact) target in front of you can't take it before /use points it at the item.
function ns.Rogue_LockpickMacro(spellName, bag, slot)
	return ("/cast [@none] %s\n/use %d %d"):format(spellName, bag, slot)
end

-- The same for the trade window's "will not be traded" slot: clicking that slot's button while the spell waits
-- for a target picks it. button = the slot's global button name.
function ns.Rogue_LockpickTradeMacro(spellName, button)
	return ("/cast [@none] %s\n/click %s"):format(spellName, button)
end
