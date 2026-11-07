local addonName, ns = ...

-- Gear Check, roll advice (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in
-- tests/test_gear_roll.lua). What to roll on group loot: need, greed or pass, and why. Roll.lua reads the roll and the
-- game, Forever.lua's verdicts judge the gear.

local LEVELS_AHEAD = 5 -- gear needing up to this many levels more is judged as if you had them: a dungeon run and a bit
local CLASS_RECIPE, CLASS_CONTAINER = 9, 1 -- Enum.ItemClass
ns.GEARROLL_CLASS_RECIPE, ns.GEARROLL_CLASS_CONTAINER = CLASS_RECIPE, CLASS_CONTAINER

-- The level to judge an item at: yours, the item's when it's a few levels ahead, nil when it's out of reach.
function ns.GearRoll_JudgeLevel(level, minLevel)
	if not minLevel or minLevel <= level then
		return level
	elseif minLevel - level <= LEVELS_AHEAD then
		return minLevel
	end
	return nil
end

-- Gear verdicts that are worth a need, and their words.
local function UpgradeText(v)
	local kind = v.kind
	if (kind == "upgrade" or kind == "upgradeBut") and v.pct then
		return ("Upgrade %+.1f%%"):format(v.pct)
	elseif kind == "levelUp" or (kind == "ilvl" and (v.ilvlDiff or 0) > 0) then
		return ("Upgrade: %+d item level"):format(v.ilvlDiff)
	elseif kind == "empty" then
		return "Fills an empty slot"
	elseif kind == "noStats" then
		return "Upgrade: yours has no stats"
	end
	return nil
end

-- What an upgrade waits for: "Upgrade at level 17", "Upgrade once you learn Two-Handed Swords", or both. ahead: the
-- level it was judged at, when above yours. nil when it's no upgrade, or there's nothing to wait for. Also the bags'
-- "later" arrow and its tooltip line (Forever.lua).
function ns.GearRoll_LaterText(v, ahead)
	if not UpgradeText(v) or not (ahead or v.untrained) then
		return nil
	end
	if ahead and v.untrained then
		return ("Upgrade at level %d once you learn %s"):format(ahead, v.untrained)
	elseif ahead then
		return ("Upgrade at level %d"):format(ahead)
	end
	return ("Upgrade once you learn %s"):format(v.untrained)
end

local function NoBetterText(v)
	local kind = v.kind
	if kind == "notForYou" then
		return "Not for you: " .. v.why
	elseif kind == "downgrade" then
		return "Worse than yours"
	elseif kind == "sidegrade" then
		return "About the same as yours"
	elseif kind == "pair" then
		return "Replaces your two-hander"
	end
	return "Can't tell if it's better"
end

local function Gear(info)
	if info.needsLevel then
		return { roll = "greed", text = ("Needs level %d"):format(info.needsLevel) }
	end
	local v = info.verdict
	if not v then
		return nil
	end
	local upgrade = UpgradeText(v)
	if not upgrade then
		return { roll = "greed", text = NoBetterText(v) }
	end
	local advice = { roll = "need", text = ns.GearRoll_LaterText(v, info.ahead) or upgrade }
	if (v.warnings or 0) > 0 and v.reasons and v.reasons[1] then
		advice.reason = v.reasons[1]
	end
	return advice
end

local function Recipe(info)
	if info.recipe == "learnable" then
		return { roll = "need", text = "A recipe you can learn" }
	elseif info.recipe == "known" then
		return { roll = "greed", text = "You know this recipe" }
	end
	return { roll = "greed", text = "A recipe you can't learn now" }
end

local function Bag(info)
	local bag = info.bag
	if bag.smallest == 0 then
		return { roll = "need", text = "A bag for your empty bag slot" }
	elseif bag.slots > bag.smallest then
		return { roll = "need", text = ("A bigger bag: %d slots, your smallest has %d"):format(bag.slots, bag.smallest) }
	end
	return nil
end

-- What to roll. info: { canNeed, canGreed (the game's say), gear (it goes on a slot), verdict (Gear Check's, judged at
-- `ahead` when set), ahead (the level it was judged at when that's above yours), needsLevel (the level it needs when that's
-- out of reach), recipe ("learnable" | "known" | "other"), bag ({ slots, smallest: your smallest bag, 0 with a slot
-- empty }), sell (what the roll's stack sells for, in copper) }.
-- Returns { roll = "need" | "greed" | "pass", text (nil: say what it sells for), reason (a catch to read), sell }.
-- Never a pass on what can be greeded: it sells, or a friend can use it.
function ns.GearRoll_Advice(info)
	local advice
	if info.gear then
		advice = Gear(info)
	elseif info.recipe then
		advice = Recipe(info)
	elseif info.bag then
		advice = Bag(info)
	end
	advice = advice or { roll = "greed" }
	advice.sell = info.sell
	if advice.roll == "need" and not info.canNeed then
		advice.roll = "greed"
		advice.reason = "The game won't let you need it"
	end
	if advice.roll == "greed" and not info.canGreed then
		advice.roll = "pass"
	end
	return advice
end
