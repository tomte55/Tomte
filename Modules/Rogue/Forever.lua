local addonName, ns = ...

-- Rogue Poisons on World of Warcraft: Forever: reads the weapons and bags for the poison buttons and the poison check
-- in Rogue.lua (poisons are items there, not retail's spells). Out of combat only. Pure rules in Data.lua, the poison
-- list in Data/Forever/Rogue.lua. Forever only: not in the retail TOC.

local SLOT_NAME = { [16] = "main hand", [17] = "off hand" }
local SLOT_LABEL = { [16] = "Main", [17] = "Off" } -- under a button, which is too small for the full name
local WEAPON_SLOT = { [16] = 0, [17] = 1 } -- Enum.WeaponSlot: what C_Item.GetWeaponEnchantInfo takes

local IsSecret = ns.IsSecret

local function Families()
	return ns.Content_Get(ns.CONTENT_FOREVER, "poisons") or {}
end

-- enchants as plain values. Anything secret counts as a poison with its time unknown: no false alarm.
local function PoisonLeft(slot)
	local enchants = C_Item.GetWeaponEnchantInfo(WEAPON_SLOT[slot])
	for _, e in ipairs(enchants) do
		if IsSecret(e.hasEnchant) or IsSecret(e.charges) or IsSecret(e.enchantType) or IsSecret(e.timeLeft) then
			return math.huge
		end
	end
	return ns.Rogue_ForeverPoisonLeft(enchants)
end

local function Weapons()
	local weapons = {}
	for _, slot in ipairs(ns.ROGUE_FOREVER_SLOTS) do
		local itemID = GetInventoryItemID("player", slot)
		if itemID then
			local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
			if ns.Rogue_TakesPoison(classID, subclassID) then
				weapons[#weapons + 1] = { slot = slot, left = PoisonLeft(slot) }
			end
		end
	end
	return weapons
end

-- Poisons in the bags this character can use (a higher rank's level requirement says no).
local function Bags()
	local bags = {}
	for _, family in ipairs(Families()) do
		for _, id in ipairs(family.items) do
			local count = C_Item.GetItemCount(id)
			if count > 0 and C_Item.IsUsableItem(id) ~= false then
				bags[id] = count
			end
		end
	end
	return bags
end

local function Read(char)
	return {
		weapons = Weapons(),
		families = Families(),
		bags = Bags(),
		last = char.last.forever,
		known = ns.SpellKnown(ns.ROGUE_FOREVER_POISONS_SPELL),
	}
end

-- Text and looks for Rogue.lua's shared button and check code.
local function Dress(p)
	local slot = SLOT_NAME[p.slot]
	p.macro = p.itemID and ns.Rogue_ForeverMacro(p.itemID, p.slot)
	p.label = SLOT_LABEL[p.slot]
	p.notOn = "Not on your " .. slot .. "."
	if p.reason == "low" then
		p.text = "Poison on your " .. slot .. ": " .. ns.Rogue_FormatLeft(p.left) .. " left"
	else
		p.text = "No poison on your " .. slot .. (p.itemID and "" or " (none in your bags)")
	end
	return p
end

-- Every problem, also the ones with no poison in the bags (the check reports them).
function ns.RogueForever_Problems(char, rules)
	local problems = ns.Rogue_ForeverProblems(Read(char), rules)
	for _, p in ipairs(problems) do
		Dress(p)
	end
	return problems
end

-- Only what a button can fix.
function ns.RogueForever_Buttons(char, rules)
	local buttons = {}
	for _, p in ipairs(ns.RogueForever_Problems(char, rules)) do
		if p.itemID then
			buttons[#buttons + 1] = p
		end
	end
	return buttons
end

-- /tomte rogue check: what's in the bags and on the weapons.
function ns.RogueForever_Describe(char)
	local s = Read(char)
	local inBags = {}
	for id, count in pairs(s.bags) do
		inBags[#inBags + 1] = (C_Item.GetItemNameByID(id) or ("item " .. id)) .. " x" .. count
	end
	table.sort(inBags)
	ns.Print("poisons in your bags: " .. (#inBags > 0 and table.concat(inBags, ", ") or "none"))
	local on = {}
	for _, weapon in ipairs(s.weapons) do
		local left = weapon.left
		on[#on + 1] = SLOT_NAME[weapon.slot] .. " "
			.. (not left and "none" or left == math.huge and "on" or ns.Rogue_FormatLeft(left))
	end
	ns.Print("on your weapons: " .. (#on > 0 and table.concat(on, ", ") or "no weapon that takes a poison"))
end
