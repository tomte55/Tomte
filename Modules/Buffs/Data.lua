local addonName, ns = ...

-- Buff reminders: pure logic (no WoW API calls; unit-tested in tests/test_buffs.lua). Which checks apply to this
-- character and place, and what's missing given plain read results (Read.lua). Shown by Strip.lua, registered in
-- Buffs.lua.

-- The raid-wide buff each class brings: the spell it casts. Every one of them puts a buff of the same name on the
-- group (Blessing of the Bronze puts a different spell per class, all named alike), so Read.lua matches by name.
-- Spell IDs from the SpellName table on wago.tools, build 12.1.5.
ns.BUFFS_GROUP = {
	MAGE = 1459, -- Arcane Intellect
	PRIEST = 21562, -- Power Word: Fortitude
	WARRIOR = 6673, -- Battle Shout
	DRUID = 1126, -- Mark of the Wild
	SHAMAN = 462854, -- Skyfury
	EVOKER = 364342, -- Blessing of the Bronze
}

-- Check keys in the order their icons show.
ns.BUFFS_CHECKS = { "food", "flask", "rune", "weapon", "group" }

-- Enum.ItemClass.Weapon, and the Enum.ItemWeaponSubclass values that never take an oil or stone: Generic
-- (miscellaneous held items) and Fishingpole. Bows, guns and crossbows do take oils (hunters use them).
local WEAPON_CLASS = 2
local NO_ENCHANT_SUBCLASS = { [14] = true, [20] = true }

-- Whether an equipped item (classID, subclassID from C_Item.GetItemInfoInstant) can take a temporary weapon enchant.
-- Shields and off-hand frills aren't weapons, so they never count.
function ns.Buffs_TakesWeaponEnchant(classID, subclassID)
	return classID == WEAPON_CLASS and not NO_ENCHANT_SUBCLASS[subclassID]
end

-- Which kinds of place (ns.Check_ContentKind) each "where" choice covers.
local WHERE = {
	raid = { raid = true },
	group = { raid = true, dungeon = true },
	all = { raid = true, dungeon = true, delve = true },
}

local LABEL = {
	food = "Food buff",
	flask = "Flask",
	rune = "Augment rune",
	weapon = "Weapon oil or stone",
	group = "Group buff",
}

-- Consumables only matter at the content's max level: a levelling character isn't nagged for flasks.
local CONSUMABLE = { food = true, flask = true, rune = true, weapon = true }

function ns.Buffs_Label(key)
	return LABEL[key]
end

-- Whether a check set to `where` runs in this place. content: "raid" | "dungeon" | "delve" | nil (elsewhere).
-- A ready check outside an instance runs every check that's on; inside one the place rule still holds.
function ns.Buffs_PlaceAllows(where, content, readyCheck)
	if not content then
		return readyCheck and true or false
	end
	local covers = WHERE[where] or WHERE.all
	return covers[content] or false
end

-- Whether the module looks at all right now (in a dungeon, raid or delve, or during a ready check).
function ns.Buffs_Watching(content, readyCheck)
	return content ~= nil or readyCheck == true
end

local function Result(key, state, why, extra)
	local r = extra or {}
	r.key, r.state, r.why = key, state, why
	return r
end

local function ConsumableResult(key, s, have)
	if not s.hasData then
		return Result(key, "noData", "no list for this expansion")
	end
	if s.aurasHidden then
		return Result(key, "unknown", "the game hides buffs right now")
	end
	if have == nil then
		return Result(key, "unknown", "couldn't read it")
	end
	if have then
		return Result(key, "ok", "you have it")
	end
	return Result(key, "missing", "missing")
end

local function WeaponResult(s)
	if s.class == "ROGUE" then
		return Result("weapon", "none", "rogues: Rogue Poisons covers your weapons")
	end
	local weapons = s.weapons or {}
	if #weapons == 0 then
		return Result("weapon", "none", "no weapon that takes an oil or stone")
	end
	local missing = {}
	for _, w in ipairs(weapons) do
		if not w.has then
			missing[#missing + 1] = w
		end
	end
	if #missing == 0 then
		return Result("weapon", "ok", "every weapon has one")
	end
	return Result("weapon", "missing", "missing on " .. #missing .. " of " .. #weapons, { weapons = missing })
end

local function GroupResult(s)
	local g = s.group
	if not g then
		return Result("group", "none", "your class has no group buff")
	end
	if not g.known then
		return Result("group", "none", "you don't know " .. (g.name or "it") .. " yet")
	end
	if s.aurasHidden then
		return Result("group", "unknown", "the game hides buffs right now")
	end
	local missing = g.missing or {}
	if #missing == 0 then
		local why = "everyone has it"
		if (g.unknown or 0) > 0 then
			why = why .. " (" .. g.unknown .. " out of range)"
		end
		return Result("group", "ok", why)
	end
	return Result("group", "missing", #missing .. " missing it", { missing = missing, spellID = g.spellID })
end

-- s = {
--   class = "MAGE" (UnitClass token), content = "raid" | "dungeon" | "delve" | nil, readyCheck = bool,
--   atMax = bool (at the content's max level), hasData = bool (the expansion has a consumable list),
--   aurasHidden = bool (the game makes aura reads secret right now: combat, encounter, Mythic+, PvP),
--   food, flask, rune = true | false | nil (nil: couldn't read),
--   weapons = { { slot, has = bool } } (only weapons that can take an oil or stone),
--   group = nil | { spellID, name, known = bool, missing = { names }, unknown = number (out of range) },
-- }
-- rules = { [key] = { on = bool, where = "raid" | "group" | "all" } } for every key in BUFFS_CHECKS.
-- Returns one result per check, in BUFFS_CHECKS order: { key, state, why, ... } where state is "missing", "ok",
-- "off" (setting off), "notHere" (place rule), "notMax", "noData", "unknown" or "none" (doesn't apply).
function ns.Buffs_Evaluate(s, rules)
	local results = {}
	for _, key in ipairs(ns.BUFFS_CHECKS) do
		local rule = rules[key] or {}
		local r
		if not rule.on then
			r = Result(key, "off", "turned off")
		elseif not ns.Buffs_PlaceAllows(rule.where, s.content, s.readyCheck) then
			r = Result(key, "notHere", "not checked here")
		elseif CONSUMABLE[key] and not s.atMax then
			r = Result(key, "notMax", "only at max level")
		elseif key == "weapon" then
			r = WeaponResult(s)
		elseif key == "group" then
			r = GroupResult(s)
		else
			r = ConsumableResult(key, s, s[key])
		end
		results[#results + 1] = r
	end
	return results
end

-- The results that are missing, in order.
function ns.Buffs_Missing(results)
	local out = {}
	for _, r in ipairs(results) do
		if r.state == "missing" then
			out[#out + 1] = r
		end
	end
	return out
end

-- "Aldric, Kesha, Mira and 2 more" (names as given, `limit` shown).
function ns.Buffs_NameList(names, limit)
	limit = limit or 3
	if #names <= limit then
		return table.concat(names, ", ")
	end
	local shown = {}
	for i = 1, limit do
		shown[i] = names[i]
	end
	return table.concat(shown, ", ") .. " and " .. (#names - limit) .. " more"
end

-- A chat line for a missing result. groupName: the class buff's name.
function ns.Buffs_MissingText(r, groupName)
	if r.key == "group" then
		local names = {}
		for i, m in ipairs(r.missing) do
			names[i] = m.name
		end
		return "No " .. (groupName or "group buff") .. ": " .. ns.Buffs_NameList(names)
	end
	if r.key == "weapon" then
		return "No weapon oil or stone"
	end
	return "No " .. LABEL[r.key]:lower()
end
