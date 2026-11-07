local addonName, ns = ...

-- Loot, Make room (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_lootroom.lua). Whether
-- loot fits, what may be destroyed for it, whether that's worth it and what the button says. Room.lua reads the game and acts.

local QUALITY_POOR, QUALITY_RARE = 0, 3 -- Enum.ItemQuality
local CLASS_CONSUMABLE, CLASS_CONTAINER, CLASS_PROJECTILE, CLASS_QUEST, CLASS_KEY = 0, 1, 6, 12, 13 -- Enum.ItemClass
local CLASS_PROFESSION = 19 -- what Bags_ItemClass files tools and fishing poles under
-- Food, potions, bags, ammo, quest items and keys are kept, whatever they'd sell for.
local KEPT_CLASSES = { [CLASS_CONSUMABLE] = true, [CLASS_CONTAINER] = true, [CLASS_PROJECTILE] = true, [CLASS_QUEST] = true,
	[CLASS_KEY] = true }

-- Whether something fits: a free slot in a bag that takes it, or room on stacks of it. bags: { { free, topUp } } for those bags.
function ns.LootRoom_Fits(quantity, bags)
	local topUp = 0
	for _, bag in ipairs(bags) do
		if (bag.free or 0) > 0 then
			return true
		end
		topUp = topUp + (bag.topUp or 0)
	end
	return topUp >= (quantity or 1)
end

-- How an item may go: "grey" (one click), "ask" (a second click to confirm) or nil (never). item: { quality, classID (from
-- Bags_ItemClass), bound, noValue, upgrade, kept (a hearthstone), locked }. Greys with no vendor price are left: the game doesn't
-- count them as junk either, and some are quest-like.
function ns.LootRoom_MayDestroy(item)
	if item.locked or item.bound or item.upgrade or item.kept or item.noValue or item.quality == nil
		or item.classID == CLASS_PROFESSION then
		return nil
	end
	if item.quality == QUALITY_POOR then
		return "grey"
	end
	if item.quality >= QUALITY_RARE or KEPT_CLASSES[item.classID] then
		return nil
	end
	return "ask"
end

-- What a whole stack is worth: the vendor's price or Gold & value's, whichever is higher.
function ns.LootRoom_Worth(item, count)
	return math.max(item.sell or 0, item.value or 0) * (count or item.count or item.quantity or 1)
end

-- Loot that's wanted whatever it sells for: for a quest, an upgrade, a new appearance. So is what has no price at all, as it can't
-- be compared.
local function AlwaysWanted(loot)
	return loot.quest ~= nil or (loot.verdict and (loot.verdict.upgrade or loot.verdict.maybe)) or loot.newLook
		or (loot.quality ~= QUALITY_POOR and ns.LootRoom_Worth(loot) == 0)
end

-- How strongly loot is wanted when choosing among several: for a quest or an upgrade first, then the most valuable, then a
-- new appearance at the same worth. A new look or a missing price still gets room once chosen (AlwaysWanted), but doesn't
-- push aside loot worth more.
local function Rank(loot)
	if loot.quest ~= nil or (loot.verdict and (loot.verdict.upgrade or loot.verdict.maybe)) then
		return 2
	end
	return 0
end

-- The loot to make room for (see Rank), then the first slot.
function ns.LootRoom_PickLoot(blocked)
	local best
	for _, loot in ipairs(blocked) do
		if not best then
			best = loot
		else
			local a, b = Rank(loot), Rank(best)
			local worth, bestWorth = ns.LootRoom_Worth(loot), ns.LootRoom_Worth(best)
			if a > b or (a == b and (worth > bestWorth or (worth == bestWorth and loot.newLook and not best.newLook))) then
				best = loot
			end
		end
	end
	return best
end

-- What to do for loot, given the items in bags that could take it. Each candidate: { bag, slot, name, count, quality, ... }.
-- Returns { kind = "destroy", target, loot, confirm } | { kind = "leave", loot, target } | { kind = "stuck", loot }. Greys go first,
-- cheapest first, as they're what nobody is saving. Not worth it: everything you could destroy is worth at least what's on the corpse.
-- That isn't offered even with a second click: players click the red button without reading it (seen on Forever, 1.31).
function ns.LootRoom_Plan(loot, candidates)
	local best, bestTier
	for _, item in ipairs(candidates) do
		local tier = ns.LootRoom_MayDestroy(item)
		if tier then
			local better = not best or (tier == "grey" and bestTier ~= "grey")
			if not better and tier == bestTier then
				local worth, bestWorth = ns.LootRoom_Worth(item), ns.LootRoom_Worth(best)
				better = worth < bestWorth or (worth == bestWorth and (item.bag < best.bag
					or (item.bag == best.bag and item.slot < best.slot)))
			end
			if better then
				best, bestTier = item, tier
			end
		end
	end
	if not best then
		return { kind = "stuck", loot = loot }
	end
	if not AlwaysWanted(loot) and ns.LootRoom_Worth(best) >= ns.LootRoom_Worth(loot) then
		return { kind = "leave", loot = loot, target = best }
	end
	return { kind = "destroy", loot = loot, target = best, confirm = bestTier == "ask" }
end

local function Named(item)
	local count = item.count or 1
	return count > 1 and (("%s x%d"):format(item.name or "?", count)) or (item.name or "?")
end

-- The button's text: two lines. armed: the first click of a confirmation has been made.
function ns.LootRoom_Text(plan, armed)
	local lootName = plan.loot.name or "this"
	if plan.kind == "stuck" then
		return ("Bags full, and nothing safe to destroy.\nMake room by hand for %s."):format(lootName)
	elseif plan.kind == "leave" then
		return ("Bags full. Leave %s:\nit's worth less than anything you'd destroy."):format(lootName)
	end
	local price = ns.Price(ns.LootRoom_Worth(plan.target))
	if armed then
		return ("Click again to destroy for good:\n%s (%s)"):format(Named(plan.target), price)
	elseif plan.confirm then
		return ("Bags full. Destroy %s (%s)?\nFor %s. Click to confirm."):format(Named(plan.target), price, lootName)
	end
	return ("Destroy %s (%s)\nand loot %s"):format(Named(plan.target), price, lootName)
end
