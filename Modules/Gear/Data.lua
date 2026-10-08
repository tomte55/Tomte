local addonName, ns = ...

-- Gear Check pure logic (unit-tested with plain Lua): Pawn weight strings, stat tables, scores, what a candidate
-- is compared against, set/unique/effect checks and the verdict. Items come in as descriptors built by Items.lua:
-- { link, equipLoc, classID, subclassID, stats, gemStats, gemText (first gem's line), gems, sockets, enchanted,
--   setID, unique = {category, max}, effect (text), upgrade = {cur, max, maxIlvl, track}, redText }.
-- Stat keys: STR AGI INT (only inside stats.PRIMARY), STA CRIT HASTE MASTERY VERS DPS ARMOR.

local UPGRADE_PCT = 1 -- above +1% is an upgrade, within +-1% a sidegrade
local SET_LIFT_PCT = -5 -- completing a set bonus turns a downgrade down to this into "upgrade for the set"
-- Stat mix: items this close in item level differ mostly in which secondary stats they have. Linear weights are
-- least reliable exactly there (they "flap" after every gear change, see Raidbots "Beware of stat weights"), so
-- differences up to STAT_MIX_PCT are called a sidegrade and sent to a sim.
local STAT_MIX_ILVL = 4
local STAT_MIX_PCT = 3

local PAWN_KEYS = {
	Strength = "STR", Agility = "AGI", Intellect = "INT", Stamina = "STA", CritRating = "CRIT",
	HasteRating = "HASTE", MasteryRating = "MASTERY", Versatility = "VERS", Dps = "DPS", Armor = "ARMOR",
}
local PRIMARY = { STR = true, AGI = true, INT = true }

-- Pawn's spec names per class token, in spec index order.
local SPECS = {
	WARRIOR = { "ARMS", "FURY", "PROTECTION" },
	PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
	HUNTER = { "BEASTMASTERY", "MARKSMANSHIP", "SURVIVAL" },
	ROGUE = { "ASSASSINATION", "OUTLAW", "SUBTLETY" },
	PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" },
	DEATHKNIGHT = { "BLOOD", "FROST", "UNHOLY" },
	SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" },
	MAGE = { "ARCANE", "FIRE", "FROST" },
	WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
	MONK = { "BREWMASTER", "MISTWEAVER", "WINDWALKER" },
	DRUID = { "BALANCE", "FERAL", "GUARDIAN", "RESTORATION" },
	DEMONHUNTER = { "HAVOC", "VENGEANCE", "DEVOURER" },
	EVOKER = { "DEVASTATION", "PRESERVATION", "AUGMENTATION" },
}

-- Enum.ItemArmorSubclass: Cloth 1, Leather 2, Mail 3, Plate 4.
local ARMOR_FOR_CLASS = {
	WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
	HUNTER = 3, SHAMAN = 3, EVOKER = 3,
	ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
	PRIEST = 1, MAGE = 1, WARLOCK = 1,
}
local ARMOR_NAMES = { "Cloth", "Leather", "Mail", "Plate" }
local ARMOR_CLASS_ID = 4 -- Enum.ItemClass.Armor
local ARMOR_LOCS = {
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true,
	INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}
local TWO_HAND = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }
local ONE_HAND = {
	INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true,
	INVTYPE_HOLDABLE = true,
}
local OFFHAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local TIER_SLOTS = { [1] = true, [3] = true, [5] = true, [7] = true, [10] = true }
-- The Catalyst takes Veteran track or higher (GetItemUpgradeInfo's trackString, English client).
local CATALYST_TRACKS = { Veteran = true, Champion = true, Hero = true, Myth = true }
local ENCHANT_SLOTS = { [1] = true, [3] = true, [5] = true, [8] = true, [11] = true, [12] = true, [16] = true }

local STAT_NAMES = {
	["critical strike"] = "CRIT", haste = "HASTE", mastery = "MASTERY", versatility = "VERS", stamina = "STA",
	strength = "STR", agility = "AGI", intellect = "INT",
}

function ns.Gear_ArmorForClass(classToken)
	return ARMOR_FOR_CLASS[classToken]
end

local function Add(stats, key, amount)
	if PRIMARY[key] then
		stats.PRIMARY = stats.PRIMARY or {}
		stats.PRIMARY[key] = (stats.PRIMARY[key] or 0) + amount
	else
		stats[key] = (stats[key] or 0) + amount
	end
end

---------------------------------------------------------------------------------------------------------------
-- Weights and stats

-- '( Pawn: v1: "Name": Class=Hunter, Spec=BeastMastery, Agility=1.00, CritRating=0.61, ... )'
function ns.Gear_ParsePawn(text)
	if type(text) ~= "string" then
		return nil, "That isn't a Pawn string."
	end
	local name, values = text:match('^%s*%(%s*Pawn%s*:%s*v%d+%s*:%s*"([^"]+)"%s*:%s*(.-)%s*%)%s*$')
	if not name then
		return nil, "That isn't a Pawn string. It should look like ( Pawn: v1: \"Name\": Agility=1.00, ... )."
	end
	local result = { name = name, weights = {} }
	local count, specName = 0, nil
	for pair in (values .. ","):gmatch("([^,]*),") do
		local key, value = pair:match("^%s*([%a%d]+)%s*=%s*(.-)%s*$")
		if key == "Class" then
			result.class = value:upper()
		elseif key == "Spec" then
			specName = value
		elseif key and PAWN_KEYS[key] and tonumber(value) then
			result.weights[PAWN_KEYS[key]] = tonumber(value)
			count = count + 1
		end
	end
	if count == 0 then
		return nil, "No stat weights found in that string."
	end
	if not (result.class and specName and SPECS[result.class]) then
		return nil, "The string doesn't say which class and spec it's for."
	end
	result.spec = tonumber(specName)
	if not result.spec then
		for i, s in ipairs(SPECS[result.class]) do
			if s == specName:upper():gsub("%s", "") then
				result.spec = i
			end
		end
	end
	if not result.spec then
		return nil, "Unknown spec: " .. specName
	end
	return result
end

-- Keys from C_Item.GetItemStats. Hybrid primaries (e.g. agility/intellect) count for each primary they name.
local RAW_KEYS = {
	ITEM_MOD_STAMINA_SHORT = "STA", ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
	ITEM_MOD_MASTERY_RATING_SHORT = "MASTERY", ITEM_MOD_VERSATILITY = "VERS",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", RESISTANCE0_NAME = "ARMOR",
}
function ns.Gear_NormalizeStats(raw)
	local stats = {}
	for key, amount in pairs(raw or {}) do
		if type(amount) == "number" then
			if RAW_KEYS[key] then
				Add(stats, RAW_KEYS[key], amount)
			elseif key:find("^ITEM_MOD_") then
				if key:find("STRENGTH") then
					Add(stats, "STR", amount)
				end
				if key:find("AGILITY") then
					Add(stats, "AGI", amount)
				end
				if key:find("INTELLECT") then
					Add(stats, "INT", amount)
				end
			end
		end
	end
	return stats
end

-- Gem and enchant text: "+13 Haste", "+12 Haste and +5 Mastery", "+10 Critical Strike, +4 Versatility".
function ns.Gear_ParseStatText(text, into)
	local stats = into or {}
	text = (text or ""):gsub(" and ", ","):gsub("\n", ",")
	for part in (text .. ","):gmatch("([^,]*),") do
		local amount, name = part:match("^%s*%+([%d]+)%s+(.-)%s*$")
		local key = name and STAT_NAMES[name:lower()]
		if key then
			Add(stats, key, tonumber(amount))
		end
	end
	return stats
end

function ns.Gear_DefaultWeights(primary)
	return { [primary] = 1, CRIT = 0.5, HASTE = 0.5, MASTERY = 0.5, VERS = 0.5 }
end

local function StatsScore(stats, weights, primary)
	local total = 0
	for key, amount in pairs(stats or {}) do
		if key == "PRIMARY" then
			total = total + (amount[primary] or 0) * (weights[primary] or 0)
		else
			total = total + amount * (weights[key] or 0)
		end
	end
	return total
end
ns.Gear_StatsScore = StatsScore

-- Average value of one socketed gem, over everything equipped. 0 when no gems are known.
function ns.Gear_GemValue(equipped, weights, primary)
	local total, count = 0, 0
	for _, desc in pairs(equipped) do
		if (desc.gems or 0) > 0 then
			total = total + StatsScore(desc.gemStats, weights, primary)
			count = count + desc.gems
		end
	end
	return count > 0 and total / count or 0
end

function ns.Gear_Score(desc, weights, primary, gemValue)
	local empty = math.max((desc.sockets or 0) - (desc.gems or 0), 0)
	return StatsScore(desc.stats, weights, primary) + StatsScore(desc.gemStats, weights, primary)
		+ empty * (gemValue or 0)
end

-- Item string fields 2-6 (enchant, gems) cleared, bonus IDs kept: the stats of the item itself.
function ns.Gear_StripLink(link)
	return (link:gsub("(item:%-?%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*", "%1:::::", 1))
end

-- Enchant and socketed gems from the item string: enchanted (bool), gems (count).
function ns.Gear_LinkInfo(link)
	local enchant, g1, g2, g3, g4 = (link or ""):match("item:%-?%d+:([^:|]*):([^:|]*):([^:|]*):([^:|]*):([^:|]*)")
	local gems = 0
	for _, g in ipairs({ g1 or "", g2 or "", g3 or "", g4 or "" }) do
		if (tonumber(g) or 0) > 0 then
			gems = gems + 1
		end
	end
	return (tonumber(enchant) or 0) > 0, gems
end

-- Socketed gem item IDs from the item string, in socket order (fields 3-6).
function ns.Gear_LinkGemIDs(link)
	local ids = {}
	local g1, g2, g3, g4 = (link or ""):match("item:%-?%d+:[^:|]*:([^:|]*):([^:|]*):([^:|]*):([^:|]*)")
	for _, g in ipairs({ g1 or "", g2 or "", g3 or "", g4 or "" }) do
		if (tonumber(g) or 0) > 0 then
			ids[#ids + 1] = tonumber(g)
		end
	end
	return ids
end

-- Whether what's worn in slot takes an enchant. The off-hand only when it's a weapon (not a shield or frill).
function ns.Gear_EnchantSlot(slot, equipLoc)
	if slot == 17 then
		return OFFHAND_WEAPON[equipLoc] == true
	end
	return ENCHANT_SLOTS[slot] == true
end

-- "Unique-Equipped: Embellished (2)" -> { category = "Embellished", max = 2 }; "Unique-Equipped" -> max 1.
function ns.Gear_ParseUnique(text)
	if type(text) ~= "string" then
		return nil
	end
	local category, max = text:match("^Unique%-Equipped: (.-) %((%d+)%)$")
	if category then
		return { category = category, max = tonumber(max) }
	end
	if text == "Unique-Equipped" or text == "Unique" then
		return { max = 1 }
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- Comparison

function ns.Gear_Slots(equipLoc)
	return SLOTS[equipLoc]
end

-- What the candidate replaces. mode: "single" (slots[1]), "weaker" (the weaker of slots), "sum" (both hands
-- against a two-hander), "pair" (a one-hander while a two-hander is worn), "empty".
function ns.Gear_Target(cand, equipped)
	local loc = cand.equipLoc
	local slots = SLOTS[loc]
	if not slots then
		return nil
	end
	local mh, oh = equipped[16], equipped[17]
	local mhTwo = mh and TWO_HAND[mh.equipLoc]
	local ohTwo = oh and TWO_HAND[oh.equipLoc]
	if TWO_HAND[loc] then
		if mhTwo and ohTwo then
			return { mode = "weaker", slots = { 16, 17 } } -- Titan's Grip
		elseif mh and not mhTwo then
			return { mode = "sum", slots = { 16, 17 } }
		end
		return { mode = mh and "single" or "empty", slots = { 16 } }
	end
	if ONE_HAND[loc] then
		if mhTwo and not ohTwo then
			return { mode = "pair", slots = { 16 } }
		end
		if loc == "INVTYPE_WEAPON" and oh and OFFHAND_WEAPON[oh.equipLoc] then
			return { mode = "weaker", slots = { 16, 17 } }
		end
		local slot = loc == "INVTYPE_WEAPON" and 16 or slots[1]
		return { mode = equipped[slot] and "single" or "empty", slots = { slot } }
	end
	if #slots == 2 then
		-- A unique item you already wear one of replaces that one.
		if cand.unique then
			for _, s in ipairs(slots) do
				local u = equipped[s] and equipped[s].unique
				if u and (u.category or equipped[s].itemID) == (cand.unique.category or cand.itemID) then
					return { mode = "single", slots = { s } }
				end
			end
		end
		for _, s in ipairs(slots) do
			if not equipped[s] then
				return { mode = "empty", slots = { s } }
			end
		end
		return { mode = "weaker", slots = slots }
	end
	return { mode = equipped[slots[1]] and "single" or "empty", slots = { slots[1] } }
end

local function SetTier(n)
	return n >= 4 and 4 or n >= 2 and 2 or 0
end

local function CountSets(equipped, skip, extra)
	local counts = {}
	for slot, desc in pairs(equipped) do
		if desc.setID and not skip[slot] then
			counts[desc.setID] = (counts[desc.setID] or 0) + 1
		end
	end
	if extra then
		counts[extra] = (counts[extra] or 0) + 1
	end
	return counts
end

-- The set with the most pieces in tier slots (the one the catalyst would make).
local function MainSet(equipped)
	local counts, best, bestN = {}, nil, 0
	for slot, desc in pairs(equipped) do
		if desc.setID and TIER_SLOTS[slot] then
			counts[desc.setID] = (counts[desc.setID] or 0) + 1
			if counts[desc.setID] > bestN then
				best, bestN = desc.setID, counts[desc.setID]
			end
		end
	end
	return best
end

-- "Equip: ..." -> "an Equip", "Use: ..." -> "a Use"; anything else -> "an".
local function EffectKind(effect)
	local word = effect:match("^(%a+):")
	if word == "Use" then
		return "a Use"
	elseif word then
		return "an " .. word
	end
	return "an"
end

local function SameItem(a, b)
	return a and b and a.link == b.link
end

local function NotForYou(why)
	return { kind = "notForYou", why = why, reasons = {} }
end

-- Why the spec in ctx can't use an item, or nil. ctx.specOK (set by the caller) or ctx.specID against cand.specs.
function ns.Gear_Unusable(cand, ctx)
	if cand.redText then
		return cand.redText
	end
	if cand.classID == ARMOR_CLASS_ID and ARMOR_LOCS[cand.equipLoc] and ARMOR_NAMES[cand.subclassID or 0]
		and ctx.armorSubclass and cand.subclassID ~= ctx.armorSubclass then
		return "wrong armor type (" .. ARMOR_NAMES[cand.subclassID] .. ")"
	end
	local primaries = cand.stats and cand.stats.PRIMARY
	if primaries and next(primaries) and not primaries[ctx.primary] then
		return "wrong main stat"
	end
	if ctx.specOK == false or (cand.specs and ctx.specID and not cand.specs[ctx.specID]) then
		return "not for your spec"
	end
	return nil
end

-- ctx: { primary = "AGI", weights, noWeights, armorSubclass, specOK, gemValue (best gem's value; else the
-- average of the gems worn) }
function ns.Gear_Evaluate(cand, equipped, ctx)
	for _, desc in pairs(equipped) do
		if SameItem(cand, desc) then
			return nil -- hovering something you wear
		end
	end
	if not SLOTS[cand.equipLoc] then
		return nil
	end
	local why = ns.Gear_Unusable(cand, ctx)
	if why then
		return NotForYou(why)
	end

	local target = ns.Gear_Target(cand, equipped)
	local replaced = {}
	for _, s in ipairs(target.slots) do
		replaced[s] = true
	end

	local weights, primary = ctx.weights, ctx.primary
	local gemValue = ctx.gemValue or ns.Gear_GemValue(equipped, weights, primary)
	local function Score(desc)
		return desc and ns.Gear_Score(desc, weights, primary, gemValue) or 0
	end

	if target.mode == "weaker" then
		local a, b = target.slots[1], target.slots[2]
		local slot = Score(equipped[a]) <= Score(equipped[b]) and a or b
		target = { mode = "single", slots = { slot } }
		replaced = { [slot] = true }
	end

	-- Unique limits (e.g. Embellished (2)) over everything not being replaced.
	if cand.unique then
		local key = cand.unique.category or cand.itemID
		local n = 0
		for slot, desc in pairs(equipped) do
			if not replaced[slot] and desc.unique and (desc.unique.category or desc.itemID) == key then
				n = n + 1
			end
		end
		if n + 1 > (cand.unique.max or 1) then
			if cand.unique.category then
				return NotForYou(("would exceed %s (%d)"):format(cand.unique.category, cand.unique.max))
			end
			return NotForYou("unique, you already wear one")
		end
	end

	local verdict = { reasons = {}, noWeights = ctx.noWeights, slot = target.slots[1] } -- slot = where it goes
	local warnings, info = {}, {}

	if target.mode == "pair" then
		verdict.kind = "pair"
		verdict.reasons = { "Needs an off-hand to go with it" }
		return verdict
	end

	local old, oldIlvl = 0, nil
	for slot in pairs(replaced) do
		old = old + Score(equipped[slot])
		oldIlvl = equipped[slot] and equipped[slot].ilvl
	end
	local new = Score(cand)
	local empty = target.mode == "empty"
	-- Something is worn but scores nothing (no stats under these weights, or they didn't read): no percentage.
	local statless = not empty and old <= 0
	local pct = not (empty or statless) and (new - old) / old * 100 or nil
	verdict.pct = pct

	-- Set bonuses.
	local completes
	local before = CountSets(equipped, {})
	local after = CountSets(equipped, replaced, cand.setID)
	for setID, n in pairs(before) do
		local m = after[setID] or 0
		if SetTier(m) < SetTier(n) then
			warnings[#warnings + 1] = ("Breaks your %d-set (%d > %d)"):format(SetTier(n), n, m)
		end
	end
	if cand.setID and SetTier(after[cand.setID]) > SetTier(before[cand.setID] or 0) then
		completes = SetTier(after[cand.setID])
		info[#info + 1] = ("Completes your %d-set"):format(completes)
	end
	local slot = target.slots[1]
	if not cand.setID and TIER_SLOTS[slot] and cand.upgrade and CATALYST_TRACKS[cand.upgrade.track] then
		local main = MainSet(equipped)
		if main then
			local skip = { [slot] = true }
			local n = CountSets(equipped, skip, main)[main]
			local note = ("Can be catalysed into tier (%d pieces)"):format(n)
			if SetTier(n) > SetTier(before[main] or 0) then
				note = ("Can be catalysed into tier (completes %d-set)"):format(SetTier(n))
			end
			info[#info + 1] = note
		else
			info[#info + 1] = "Can be catalysed into tier"
		end
	end

	-- What the replaced item has that the candidate doesn't.
	local lostEffects = {}
	for s in pairs(replaced) do
		local desc = equipped[s]
		if desc then
			if desc.unique and desc.unique.category == "Embellished"
				and not (cand.unique and cand.unique.category == "Embellished") then
				warnings[#warnings + 1] = "Loses an embellishment"
			elseif desc.effect then
				-- Stats can't value an effect, so this is a sim question, like a candidate with an effect.
				lostEffects[#lostEffects + 1] = ("Your current gear has %s effect that stats can't value"):format(
					EffectKind(desc.effect))
			end
			local lostSockets = (desc.sockets or 0) - (cand.sockets or 0)
			if lostSockets == 1 then
				info[#info + 1] = desc.gemText and ("Loses a socket (your gem: %s)"):format(desc.gemText) or "Loses a socket"
			elseif lostSockets > 1 then
				info[#info + 1] = ("Loses %d sockets"):format(lostSockets)
			end
			if desc.enchanted and ENCHANT_SLOTS[s] and not cand.enchanted then
				info[#info + 1] = "Current one is enchanted: re-enchant"
			end
			if gemValue == 0 and (cand.sockets or 0) > (desc.sockets or 0) then
				info[#info + 1] = ("+%d socket"):format(cand.sockets - (desc.sockets or 0))
			end
		end
	end
	if empty and gemValue == 0 and (cand.sockets or 0) > 0 then
		info[#info + 1] = ("+%d socket"):format(cand.sockets)
	end

	local up = cand.upgrade
	if up and up.cur and up.max and up.cur < up.max then
		info[#info + 1] = ("%s %d/%d, upgrades to %d"):format(up.track or "Upgradable", up.cur, up.max, up.maxIlvl or 0)
	end

	if cand.equipLoc == "INVTYPE_TRINKET" or cand.effect or #lostEffects > 0 then
		verdict.kind = "simIt"
		local sim = (cand.equipLoc == "INVTYPE_TRINKET" or cand.effect) and "Its effect decides: check with /tomte gear sim"
			or "Sim both to know: /tomte gear sim"
		table.insert(warnings, 1, sim)
		for i = #lostEffects, 1, -1 do
			table.insert(warnings, 1, lostEffects[i])
		end
	elseif empty then
		verdict.kind = "empty"
	elseif statless then
		-- With stats it beats yours; with none either, item level is all there is to go on.
		verdict.kind = new > 0 and "noStats" or "ilvl"
		verdict.ilvlDiff = cand.ilvl and oldIlvl and cand.ilvl - oldIlvl or 0
	elseif target.mode == "single" and cand.ilvl and oldIlvl and math.abs(cand.ilvl - oldIlvl) <= STAT_MIX_ILVL
		and math.abs(pct) > UPGRADE_PCT and math.abs(pct) <= STAT_MIX_PCT and not completes then
		verdict.kind = "sidegrade"
		verdict.statMix = true
		table.insert(warnings, 1, "Same level, different stats: sim to be sure (/tomte gear sim)")
	elseif pct > UPGRADE_PCT then
		verdict.kind = #warnings > 0 and "upgradeBut" or "upgrade"
	elseif completes and pct >= SET_LIFT_PCT and #warnings == 0 then
		verdict.kind = "upgradeBut"
	elseif pct >= -UPGRADE_PCT then
		verdict.kind = "sidegrade"
	else
		verdict.kind = "downgrade"
	end

	for _, r in ipairs(warnings) do
		verdict.reasons[#verdict.reasons + 1] = r
	end
	for _, r in ipairs(info) do
		verdict.reasons[#verdict.reasons + 1] = r
	end
	verdict.warnings = #warnings
	return verdict
end

local function Pct(pct)
	return ("%+.1f%%"):format(pct)
end

-- colorKey: "green" | "yellow" | "grey" | "red" | "orange"
function ns.Gear_Headline(v)
	local kind = v.kind
	if kind == "upgrade" then
		return "Upgrade " .. Pct(v.pct) .. ": equip it", "green"
	elseif kind == "upgradeBut" then
		if v.pct > UPGRADE_PCT then
			return "Upgrade " .. Pct(v.pct) .. ", but check this:", "yellow"
		end
		return "Worth it for the set bonus (stats " .. Pct(v.pct) .. ")", "yellow"
	elseif kind == "sidegrade" then
		return "Sidegrade (" .. Pct(v.pct) .. "): either is fine", "grey"
	elseif kind == "downgrade" then
		return "Downgrade " .. Pct(v.pct) .. ": keep yours", "red"
	elseif kind == "notForYou" then
		return "Not for you: " .. v.why, "grey"
	elseif kind == "simIt" then
		if v.pct then
			return "Can't judge (stats alone " .. Pct(v.pct) .. ")", "orange"
		end
		return "Can't judge: new slot, has an effect", "orange"
	elseif kind == "pair" then
		return "Replaces your two-hander", "grey"
	elseif kind == "empty" then
		return "Upgrade (slot empty): equip it", "green"
	elseif kind == "noStats" then
		return "Upgrade (yours has no stats): equip it", "green"
	elseif kind == "ilvl" then
		local d = v.ilvlDiff
		if d > 0 then
			return ("No stats on either, item level +%d"):format(d), "grey"
		elseif d < 0 then
			return ("No stats on either, item level %d: keep yours"):format(d), "red"
		end
		return "No stats on either, same item level", "grey"
	end
end

-- Only a clean upgrade marks a bag item.
function ns.Gear_IsCleanUpgrade(v)
	return v ~= nil and (v.kind == "upgrade" or v.kind == "empty" or v.kind == "noStats")
end

-- Stats say upgrade but something else needs checking: an effect or trinket to sim, same level with different
-- stats, or an upgrade with a warning (breaks a set, loses an embellishment). Never true for a clean upgrade.
function ns.Gear_IsMaybeUpgrade(v)
	if not (v and v.pct and v.pct > UPGRADE_PCT) then
		return false
	end
	return v.kind == "simIt" or v.kind == "upgradeBut" or (v.kind == "sidegrade" and v.statMix == true)
end

---------------------------------------------------------------------------------------------------------------
-- Upgrade reveal (Reveal.lua): which new items get a moment.

-- Item quality -> Moments reveal tier: green and below common, blue rare, purple epic, orange and up legendary.
function ns.Gear_RevealTier(quality)
	if not quality or quality <= 2 then
		return "common"
	elseif quality == 3 then
		return "rare"
	elseif quality == 4 then
		return "epic"
	end
	return "legendary"
end

-- items = { { verdict, ... } } new to the bags. Keeps clean upgrades of at least minPct (an empty slot always
-- counts, and so does replacing an item with no stats), the best one per slot (a ring and a better ring: only the
-- better), biggest first.
function ns.Gear_PickReveals(items, minPct)
	local best = {}
	local function Value(v)
		return v.pct or math.huge
	end
	for _, item in ipairs(items) do
		local v = item.verdict
		if ns.Gear_IsCleanUpgrade(v) and v.slot and Value(v) >= minPct then
			local held = best[v.slot]
			if not held or Value(v) > Value(held.verdict) then
				best[v.slot] = item
			end
		end
	end
	local list = {}
	for _, item in pairs(best) do
		list[#list + 1] = item
	end
	table.sort(list, function(a, b)
		local va, vb = Value(a.verdict), Value(b.verdict)
		if va ~= vb then
			return va > vb
		end
		return a.verdict.slot < b.verdict.slot
	end)
	return list
end

-- The moment's label: "Upgrade +4.2%", or "Upgrade for an empty slot".
function ns.Gear_RevealLabel(v)
	if v.kind == "empty" then
		return "Upgrade for an empty slot"
	elseif v.kind == "noStats" then
		return "Upgrade over gear with no stats"
	end
	return "Upgrade " .. Pct(v.pct)
end

-- "Item level 684, replaces Old Helm (671)". Either name or level may be missing.
function ns.Gear_RevealLine(ilvl, oldName, oldIlvl)
	local parts = {}
	if ilvl then
		parts[#parts + 1] = "Item level " .. ilvl
	end
	if oldName then
		parts[#parts + 1] = "replaces " .. oldName .. (oldIlvl and (" (" .. oldIlvl .. ")") or "")
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ", ")
end
