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
-- A knee-up shot like Narcissus's (first try, 1.6 + 1.3 x height, showed the whole body far too small).
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

-- After turning the camera left by `turned` degrees in all: the way back, the short way round.
-- -> "RIGHT" or "LEFT" and the degrees (0..180), or nil when it's already back.
function ns.CharShow_TurnBack(turned)
	local x = (turned or 0) % 360
	if x < 0.5 or x > 359.5 then
		return nil
	end
	if x <= 180 then
		return "RIGHT", x
	end
	return "LEFT", 360 - x
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
