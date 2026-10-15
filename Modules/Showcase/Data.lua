local addonName, ns = ...

-- Showcase pure logic (unit-tested in tests/test_showcase.lua): slot columns, stat rows, camera numbers.

local floor, max, min = math.floor, math.max, math.min

-- Gear columns, top to bottom. false leaves a row empty, so both weapons sit on the bottom row. Shirt and tabard
-- are left out (as on Gear Check's slot levels).
ns.CHARSHOW_LEFT = { 1, 2, 3, 15, 5, 9, false, false, 16 } -- head, neck, shoulders, back, chest, wrists, main hand
ns.CHARSHOW_RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14, 17 } -- hands, waist, legs, feet, rings, trinkets, off hand
-- GetInventorySlotInfo names (for the empty-slot art).
ns.CHARSHOW_SLOT_NAMES = {
	"HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "SHIRTSLOT", "CHESTSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "WRISTSLOT",
	"HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT", "BACKSLOT", "MAINHANDSLOT",
	"SECONDARYHANDSLOT",
}

-- Camera -----------------------------------------------------------------------------------------------------------

local DEFAULT_HEIGHT = 2 -- yards, until the model was measured
-- A knee-up shot (first try, 1.6 + 1.3 x height, showed the whole body far too small).
local ZOOM_BASE = 0.4
local ZOOM_PER_YARD = 1.1
local MOUNTED_FACTOR, MOUNTED_EXTRA = 1.6, 2
local MIN_ZOOM, MAX_ZOOM = 1.5, 20
-- test_cameraOverShoulder per yard of zoom: puts the character about a third in from the left of the screen.
local SHIFT_PER_ZOOM = 0.33

-- Camera distance that frames the whole character. height: the model's height in yards (nil: not measured yet);
-- scale: the "Camera distance" setting (1 = 100%).
function ns.CharShow_Zoom(height, mounted, scale)
	local zoom = (ZOOM_BASE + ZOOM_PER_YARD * (height or DEFAULT_HEIGHT)) * (scale or 1)
	if mounted then
		zoom = zoom * MOUNTED_FACTOR + MOUNTED_EXTRA
	end
	return max(MIN_ZOOM, min(zoom, MAX_ZOOM))
end

-- The shoulder offset that keeps the character at the same spot on screen at this zoom (0 when centered).
function ns.CharShow_Shoulder(zoom, toSide)
	if not toSide then
		return 0
	end
	return floor((zoom or 0) * SHIFT_PER_ZOOM * 100 + 0.5) / 100
end

-- The swing's turn rate t seconds in: it rises from the slow turn to `from` over `ramp` seconds, and decays back
-- down to `to` (the slow turn) by `duration`, sine-eased, so it starts and blends into the slow turn without a jolt.
function ns.CharShow_SwingRate(t, duration, from, to, ramp)
	local p = max(0, min(t / duration, 1))
	local r = ramp and ramp > 0 and max(0, min(t / ramp, 1)) or 1
	r = r * r * (3 - 2 * r)
	return to + (from - to) * r * (1 + math.cos(math.pi * p)) / 2
end

-- Degrees per second for MoveViewLeftStart(speed): the speed scales the cameraYawMoveSpeed CVar.
function ns.CharShow_YawRate(cvarSpeed, speed)
	return (tonumber(cvarSpeed) or 180) * speed
end

-- Slots ------------------------------------------------------------------------------------------------------------


-- The track for the pips: "Hero", 4, 6 from desc.upgrade; nil without a track.
function ns.CharShow_Track(upgrade)
	if not (upgrade and upgrade.track and upgrade.track ~= "" and (upgrade.max or 0) > 0) then
		return nil
	end
	return upgrade.track, max(0, min(upgrade.cur or 0, upgrade.max)), upgrade.max
end

-- Secondary stats as parts of one bar, by rating: each entry gets .share (0..1, the parts add up to 1).
-- nil when there's no rating at all (nothing to split).
function ns.CharShow_Split(entries)
	local total = 0
	for _, e in ipairs(entries) do
		total = total + max(e.rating or 0, 0)
	end
	if total <= 0 then
		return nil
	end
	local parts = {}
	for i, e in ipairs(entries) do
		parts[i] = { key = e.key, label = e.label, value = e.value, rating = e.rating or 0,
			share = max(e.rating or 0, 0) / total }
	end
	return parts
end

-- Item level dial: how full the ring is (equipped / best in bags, 0..1) and how many of `ticks` are lit.
function ns.CharShow_DialFill(equipped, best, ticks)
	local fill = 0
	if (best or 0) > 0 then
		fill = max(0, min((equipped or 0) / best, 1))
	end
	return fill, floor(fill * ticks + 0.5)
end

-- A Lua pattern from a Blizzard format string ("Enchanted: %s" -> "^Enchanted: (.+)$").
local function FormatPattern(fmt)
	local escaped = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

-- The enchant's own text from its tooltip line ("Enchanted: +86 Haste" -> "+86 Haste"), color codes removed.
-- fmt: ENCHANTED_TOOLTIP_LINE (the client's language).
function ns.CharShow_EnchantText(line, fmt)
	if type(line) ~= "string" or line == "" then
		return nil
	end
	line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if type(fmt) == "string" and fmt:find("%%s") then
		local inner = line:match(FormatPattern(fmt))
		if inner then
			return inner
		end
	end
	return line
end

-- What a slot shows under its item level. desc: Gear Check's item descriptor; takesEnchant: the slot takes one
-- (Gear_EnchantSlot); atMax: the character is at max level (no "No enchant" while leveling).
-- -> { enchant = text or nil, missing = bool, gems = n, empty = n }
function ns.CharShow_Hints(desc, takesEnchant, atMax, enchantText)
	local gems = desc.gems or 0
	local hints = { gems = gems, empty = max((desc.sockets or 0) - gems, 0), missing = false }
	if desc.enchanted then
		hints.enchant = enchantText
	elseif takesEnchant and atMax then
		hints.missing = true
	end
	return hints
end

-- Stats ------------------------------------------------------------------------------------------------------------

-- Always listed; the rest only when not 0 (as on Blizzard's character sheet).
local ALWAYS = { primary = true, stamina = true, health = true, armor = true }

-- entries: { key, label, value, rating, percent }, in display order. Keeps what Blizzard's sheet would show:
-- dodge and parry for tanks only, block with a shield only, others not at 0.
function ns.CharShow_FilterStats(entries, isTank, hasShield)
	local list = {}
	for _, e in ipairs(entries) do
		local keep = e.value ~= nil
		if keep and (e.key == "dodge" or e.key == "parry") and not isTank then
			keep = false
		elseif keep and e.key == "block" and not hasShield then
			keep = false
		elseif keep and not ALWAYS[e.key] and e.value == 0 then
			keep = false
		end
		if keep then
			list[#list + 1] = e
		end
	end
	return list
end

-- The value column: "39.84%" for percentages, "138,468" for counts. The rating ("302") as a second string, or nil.
function ns.CharShow_StatText(e)
	local value
	if e.percent then
		value = ("%.2f%%"):format(e.value)
	else
		value = ns.Thousands(e.value)
	end
	local rating = e.rating and e.rating > 0 and ns.Thousands(e.rating) or nil
	return value, rating
end

-- "Level 80 Beast Mastery Hunter" style subtitle parts, empty ones skipped.
function ns.CharShow_Subtitle(level, spec, class)
	local parts = {}
	if level then
		parts[#parts + 1] = tostring(level)
	end
	if spec and spec ~= "" then
		parts[#parts + 1] = spec
	end
	if class and class ~= "" then
		parts[#parts + 1] = class
	end
	return table.concat(parts, " ")
end

-- A title from GetTitleName ("the Fabulous ", " Jenkins", "%s the Patient") without the name slot and spaces.
function ns.CharShow_Title(title)
	if type(title) ~= "string" then
		return nil
	end
	title = title:gsub("%%s", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return title ~= "" and title or nil
end

-- Slot card ----------------------------------------------------------------------------------------------------------

-- The card's stat rows from Gear Check's normalized stats (Rules.lua's keys): armor, the spec's primary stat (one
-- of STR, AGI, INT; others on the item are left out), stamina, then the secondaries. labels: [key] = the stat's
-- name in the client's language. -> { { key, amount, text = "+39 Agility", secondary = bool } }
local CARD_SECONDARY = { "CRIT", "HASTE", "MASTERY", "VERS" }
function ns.CharShow_CardStats(stats, primary, labels)
	local rows = {}
	local function Add(key, amount, secondary)
		if amount and amount > 0 then
			local label = labels[key] or key
			local text = key == "ARMOR" and ("%s %s"):format(ns.Thousands(amount), label)
				or ("+%s %s"):format(ns.Thousands(amount), label)
			rows[#rows + 1] = { key = key, amount = amount, text = text, secondary = secondary }
		end
	end
	stats = stats or {}
	Add("ARMOR", stats.ARMOR, false)
	if primary and stats.PRIMARY then
		Add(primary, stats.PRIMARY[primary], false)
	end
	Add("STA", stats.STA, false)
	for _, key in ipairs(CARD_SECONDARY) do
		Add(key, stats[key], true)
	end
	return rows
end

-- "Head · Mail · Soulbound": the non-empty parts.
function ns.CharShow_MetaLine(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local part = select(i, ...)
		if type(part) == "string" and part ~= "" then
			parts[#parts + 1] = part
		end
	end
	return table.concat(parts, " · ")
end

-- "1.72%" (nil without a value).
function ns.CharShow_Percent(value)
	if type(value) ~= "number" then
		return nil
	end
	return ("%.2f%%"):format(value)
end

-- Gear menu ----------------------------------------------------------------------------------------------------------

-- Each status: text, theme role.
function ns.CharShow_EquipStatus(count, slotName)
	if count == 0 then
		return ("No other item for %s"):format(slotName or "this slot"), "danger"
	end
	return ("%d %s in your bags"):format(count, count == 1 and "item" or "items"), "textMuted"
end

-- takes: the slot takes an enchant (at max level); current: the enchant's text; count: enchants in the bags for it.
function ns.CharShow_EnchantStatus(takes, current, count)
	if current then
		return current, "success"
	elseif takes then
		return "No enchant", "danger"
	elseif count > 0 then
		return ("%d in your bags"):format(count), "textMuted"
	end
	return "Doesn't take one", "textMuted"
end

function ns.CharShow_GemStatus(sockets, empty)
	if sockets == 0 then
		return "No sockets", "danger"
	elseif empty > 0 then
		return ("%d empty %s"):format(empty, empty == 1 and "socket" or "sockets"), "warning"
	end
	return "All sockets filled", "textMuted"
end

-- Item Enhancement (item class 8) subclasses -> the slots they enchant. Weapon kinds go by the worn item's
-- equipLoc: 11 any weapon (current weapon enchants go on two-handers and ranged too), 12 two-handers (ranged
-- included), 13 shields and off-hand frills.
local ENCHANT_SUBCLASS_SLOTS = {
	[0] = { [1] = true }, [1] = { [2] = true }, [2] = { [3] = true }, [3] = { [15] = true }, [4] = { [5] = true },
	[5] = { [9] = true }, [6] = { [10] = true }, [7] = { [6] = true }, [8] = { [7] = true }, [9] = { [8] = true },
	[10] = { [11] = true, [12] = true },
}
local TWO_HAND_LOCS = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }
local OFF_HAND_LOCS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
local ENHANCEMENT_CLASS, CONSUMABLE_CLASS, CONSUMABLE_ENHANCEMENT = 8, 0, 6

-- Whether a bag item (its class and subclass) enchants what's worn in slot (its equipLoc). -> "permanent",
-- "temporary" (oils and stones: weapons only) or nil.
function ns.CharShow_EnchantFits(slot, equipLoc, classID, subclassID)
	if classID == ENHANCEMENT_CLASS then
		local slots = ENCHANT_SUBCLASS_SLOTS[subclassID]
		if slots then
			return slots[slot] and "permanent" or nil
		end
		if slot ~= 16 and slot ~= 17 then
			return nil
		end
		if (subclassID == 11 and equipLoc and not OFF_HAND_LOCS[equipLoc])
			or (subclassID == 12 and TWO_HAND_LOCS[equipLoc]) or (subclassID == 13 and OFF_HAND_LOCS[equipLoc]) then
			return "permanent"
		end
		return nil
	end
	if classID == CONSUMABLE_CLASS and subclassID == CONSUMABLE_ENHANCEMENT and (slot == 16 or slot == 17)
		and not OFF_HAND_LOCS[equipLoc] then
		return "temporary"
	end
	return nil
end

-- The secure macro that uses a bag item on an equipped slot.
function ns.CharShow_EnchantMacro(bag, bagSlot, slot)
	return ("/use %d %d\n/use %d"):format(bag, bagSlot, slot)
end

-- Gem class 3; relics (subclass 11) don't go in gear sockets.
function ns.CharShow_IsGem(classID, subclassID)
	return classID == 3 and subclassID ~= 11
end

-- The socket the gem list fills: the first empty one, else the first. gems: [i] = gem item ID or nil.
function ns.CharShow_PickSocket(sockets, gems)
	for i = 1, sockets do
		if not gems[i] then
			return i
		end
	end
	return sockets > 0 and 1 or nil
end
