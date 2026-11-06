local addonName, ns = ...

-- Buff reminders: reads the player's and the group's buffs and the weapons' temporary enchants into the plain table
-- Data.lua's ns.Buffs_Evaluate takes. Out of combat only (Buffs.lua never calls it in combat). Aura reads go by
-- localized spell name (C_UnitAuras.GetAuraDataBySpellName), and only while C_Secrets.ShouldAurasBeSecret() is
-- false: under a combat, encounter, Mythic+ or PvP restriction a read can come back empty for a buff that's there,
-- so the checks say "unknown" instead of "missing". Every value read is tested with ns.IsSecret as well.

local IsSecret = ns.IsSecret
-- Main and off hand (INVSLOT_MAINHAND, INVSLOT_OFFHAND): the slots that take an oil or a whetstone.
local WEAPON_SLOTS = { 16, 17 }
local MAX_RAID = 40

-- True when aura reads would be secret right now (no C_Secrets: older client, never).
local function AurasHidden()
	return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() and true or false
end

-- Localized buff names for a list of spell IDs, without repeats (spells this client lacks are skipped).
local function Names(ids)
	local names, seen = {}, {}
	for _, id in ipairs(ids or {}) do
		local name = C_Spell.GetSpellName(id)
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	return names
end

-- true when the unit has a helpful aura with one of these names, false when it has none, nil when a read was secret.
local function HasAny(unit, names)
	for _, name in ipairs(names) do
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL")
		if aura then
			if IsSecret(aura.name) then
				return nil
			end
			return true
		end
	end
	return false
end

-- The weapons worn that can take an oil or stone (ns.Buffs_TakesWeaponEnchant), and whether each has one. Any
-- returned info means an enchant is on (its fields aren't needed, so a secret one still counts).
local function Weapons()
	local list = {}
	for _, slot in ipairs(WEAPON_SLOTS) do
		local itemID = GetInventoryItemID("player", slot)
		if itemID then
			local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
			if ns.Buffs_TakesWeaponEnchant(classID, subclassID) then
				list[#list + 1] = { slot = slot, has = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot) ~= nil }
			end
		end
	end
	return list
end

-- The units to look at for the group buff: you, then the party or raid (each one once).
local function GroupUnits()
	local units = { "player" }
	if IsInRaid() then
		for i = 1, math.min(GetNumGroupMembers(), MAX_RAID) do
			local unit = "raid" .. i
			if not UnitIsUnit(unit, "player") then
				units[#units + 1] = unit
			end
		end
	else
		for i = 1, GetNumSubgroupMembers() do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

-- The group buff spells of a class, the one it casts first; nil when it brings none. Forever's come from its content
-- list: a buff there has a separate raid-wide version, and either one counts.
local groupSpells = {}
function ns.Buffs_GroupSpells(class)
	if groupSpells[class] == nil then
		local spells
		if ns.FOREVER then
			local data = ns.Content_Get(ns.CONTENT_FOREVER, "buffs")
			spells = data and data.group[class]
		else
			spells = ns.BUFFS_GROUP[class] and { ns.BUFFS_GROUP[class] }
		end
		groupSpells[class] = spells or false
	end
	return groupSpells[class] or nil
end

local function Group(class, hidden)
	local spells = ns.Buffs_GroupSpells(class)
	if not spells then
		return nil
	end
	local spellID = spells[1]
	local name = C_Spell.GetSpellName(spellID)
	local g = { spellID = spellID, name = name, known = name ~= nil and C_SpellBook.IsSpellKnown(spellID) or false,
		missing = {}, unknown = 0 }
	if not g.known or hidden then
		return g
	end
	local names = Names(spells)
	for _, unit in ipairs(GroupUnits()) do
		if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
			if not UnitIsVisible(unit) then
				g.unknown = g.unknown + 1
			else
				local has = HasAny(unit, names)
				if has == nil then
					g.unknown = g.unknown + 1
				elseif not has then
					local unitName = unit == "player" and "you" or UnitName(unit)
					if IsSecret(unitName) or not unitName then
						unitName = "someone"
					end
					local _, unitClass = UnitClass(unit)
					g.missing[#g.missing + 1] = { name = unitName, class = unitClass, isPlayer = unit == "player" }
				end
			end
		end
	end
	return g
end

-- readyCheck: a ready check is on. Returns the table ns.Buffs_Evaluate takes, plus `names` (the buff names looked
-- for, for /tomte buffs why) and `expansion`.
function ns.Buffs_Read(readyCheck)
	local _, class = UnitClass("player")
	local _, instanceType, difficultyID = GetInstanceInfo()
	local expansion = ns.ContentExpansion()
	local data = ns.Content_Get(expansion, "buffs")
	local hidden = AurasHidden()
	local s = {
		class = class,
		content = ns.Check_ContentKind(instanceType, difficultyID),
		readyCheck = readyCheck and true or false,
		atMax = ns.ContentAtMax(),
		hasData = data ~= nil,
		aurasHidden = hidden,
		expansion = expansion,
		names = {},
	}
	if ns.FOREVER then
		s.noList = { flask = true, rune = true }
	end
	if data and not hidden then
		for _, key in ipairs({ "food", "flask", "rune" }) do
			if not (s.noList and s.noList[key]) then
				s.names[key] = Names(data[key])
				s[key] = HasAny("player", s.names[key])
			end
		end
	end
	-- A Forever hunter's bow is in the ranged slot: the melee stat stick in these slots isn't what a stone is for.
	s.weapons = (ns.FOREVER and class == "HUNTER") and {} or Weapons()
	s.group = Group(class, hidden)
	return s
end
